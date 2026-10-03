import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/monthly_bill_model.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_bill_pdf_service.dart';
import '../../services/monthly_billing_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../utils/billing_ledger.dart';
import '../../utils/pdf_download.dart';
import 'edit_statement_screen.dart';
import 'monthly_bill_generate_screen.dart';

/// Customer-level Monthly Bills.
///
/// This screen is intentionally separate from the goat Check-Out / Final Bill.
///
/// Flow:
///
/// Customer Profile
///       ↓
/// Monthly Bills
///       ↓
/// View / Download Monthly Bill
///       ↓
/// Unpaid / Partially Paid
///       ↓
/// Toggle Paid
///       ↓
/// Existing Add Payment flow
///       ↓
/// Payment successful
///       ↓
/// Monthly bill becomes Paid
class MonthlyBillsScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;

  /// Connects this screen to the EXISTING Add Payment screen.
  ///
  /// Return true when payment was successfully recorded.
  /// Return false/null when the user cancels.
  final Future<bool> Function(MonthlyBill bill)? onAddPayment;

  const MonthlyBillsScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
    this.onAddPayment,
  });

  @override
  State<MonthlyBillsScreen> createState() =>
      _MonthlyBillsScreenState();
}

class _MonthlyBillsScreenState
    extends State<MonthlyBillsScreen> {
  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  final MonthlyBillPdfService _pdfService =
      MonthlyBillPdfService.instance;

  bool _loading = true;
  bool _creatingBill = false;

  List<MonthlyBill> _bills = [];

  /// The customer's live balance, read with the bills. On statement
  /// billing this equals the latest statement's remaining Total Payable
  /// unless something was charged or paid since (checkout, payment).
  double? _livePending;
  double? _liveAdvance;

  /// Payment from a deleted bill, waiting to be used on the next bill.
  double? _liveCredit;

  // ==========================================================================
  // PDF ACTION STATE
  // ==========================================================================
  //
  // Tracks which bill currently has a View / Download / Share PDF action
  // running, so the relevant button can show a spinner and disable itself
  // instead of appearing to do nothing while the PDF is being generated
  // (PDF generation can take a few seconds, e.g. while fonts are fetched).

  final Set<String> _viewingBillIds = {};

  /// Bills being deleted right now: their card shows a loader until the
  /// delete finishes, then the card is removed in place.
  final Set<String> _deletingBillIds = {};
  final Set<String> _downloadingBillIds = {};
  final Set<String> _sharingBillIds = {};

  /// Cached after the first PDF action so View/Share/Download don't each
  /// re-fetch the farm document — cleared to `null` if a fetch fails so
  /// the next attempt tries again rather than getting stuck on a failed
  /// read.
  BillSettings? _billSettings;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  // ========================================================================
  // FIRESTORE REFERENCES
  // ========================================================================

  CollectionReference<Map<String, dynamic>>
  get _billsCollection {
    return _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('monthlyBills');
  }

  DocumentReference<Map<String, dynamic>>
  get _customerReference {
    return _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId);
  }

  DocumentReference<Map<String, dynamic>>
  get _farmReference {
    return _db
        .collection('farms')
        .doc(widget.farmId);
  }

  // ========================================================================
  // BILL SETTINGS (Business details / Terms & Conditions / Important Notes)
  // ========================================================================
  //
  // Read fresh from the farm document each time a PDF action is first
  // requested in this screen session, then cached — same source
  // [FirestoreService.updateBillSettings] writes to (`farms/{farmId}`,
  // field `billSettings`), so bill details edited on the Bill Details
  // screen show up on the very next PDF generated here without needing
  // an app restart.
  //
  // Falls back to the farm's own name/address/phone/email (same fields
  // the old per-bill snapshot used) when Bill Details hasn't been filled
  // in yet, so a farm that never opened Bill Details still gets a
  // sensibly filled-in bill instead of blank fields.
  //
  // Logo: Bill Details has its own dedicated "Bill Logo" upload
  // (`billLogo`), separate from the farm's Profile photo
  // (`profileImage`, set via [FirestoreService.updateProfileImage]).
  // When no Bill Logo has been set, we now fall back to the farm's own
  // Profile photo here — NOT the bundled placeholder app icon — so the
  // header always shows this farm's actual branding, matching how the
  // Customer Goat Progress Report's header sources its logo. The PDF
  // service's own placeholder-asset fallback only ever applies if a
  // farm has neither a Bill Logo nor a Profile photo.

  Future<BillSettings> _loadBillSettings() async {
    if (_billSettings != null) {
      return _billSettings!;
    }

    final farmSnapshot = await _farmReference.get();
    final farmData = farmSnapshot.data() ?? {};

    var settings = BillSettings.fromMap(
      farmData['billSettings'] as Map<String, dynamic>?,
      fallbackName: (farmData['farmName'] ?? '').toString(),
      fallbackAddress: (farmData['address'] ?? '').toString(),
      fallbackPhone: (farmData['mobileNumber'] ?? '').toString(),
      fallbackEmail: (farmData['email'] ?? '').toString(),
    );

    if (settings.billLogo == null) {
      final profileImage = farmData['profileImage'];

      if (profileImage is Blob && profileImage.bytes.isNotEmpty) {
        settings = settings.copyWith(
          billLogo: profileImage.bytes,
          billLogoContentType:
          (farmData['profileImageContentType'] as String?) ??
              settings.billLogoContentType,
        );
      }
    }

    _billSettings = settings;
    return settings;
  }

  // ========================================================================
  // LOAD BILLS
  // ========================================================================

  /// Loads the bills. [silent] keeps the list on screen while it refreshes
  /// (used after an action), instead of the full-screen loader that is
  /// only shown on first open.
  Future<void> _loadBills({bool silent = false}) async {
    if (mounted && !silent) {
      setState(() {
        _loading = true;
      });
    }

    try {
      // Only filter by customerId in Firestore.
      //
      // We intentionally do NOT use:
      // .orderBy('billingMonth')
      //
      // because that combination requires a composite Firestore index.
      //
      // We sort the customer's bills locally instead.
      final snapshot = await _billsCollection
          .where(
        'customerId',
        isEqualTo: widget.customerId,
      )
          .get();

      final bills = snapshot.docs
          .where((doc) => doc.data()['type']?.toString() == 'monthly')
          .map(
            (doc) => MonthlyBill.fromDoc(doc),
      )
          .where((bill) => !bill.isVoid)
          .toList();

      final customerSnapshot = await _customerReference.get();
      final customerData = customerSnapshot.data() ?? {};

      bills.sort(
            (a, b) => b.billingMonth.compareTo(
          a.billingMonth,
        ),
      );

      if (!mounted) return;

      setState(() {
        _bills = bills;
        _livePending = _number(customerData['pendingAmount']);
        _liveAdvance = _number(customerData['advanceAmount']);
        _liveCredit = _number(customerData['billPaymentCredit']);
      });
    } catch (e) {
      debugPrint(
        'Monthly bills load error: $e',
      );

      if (!mounted) return;

      _showError(
        'Unable to load monthly bills.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ========================================================================
  // CREATE MONTHLY BILL
  // ========================================================================
  //
  // Opens the statement preview for this customer. Bills are always for
  // the previous month (see MonthlyStatementEngine); the same engine runs
  // behind the Generate Bills button on the Customers screen.

  Future<void> _createMonthlyBill() async {
    if (_creatingBill) return;

    setState(() {
      _creatingBill = true;
    });

    try {
      final generated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MonthlyBillGenerateScreen(
            farmId: widget.farmId,
            customerId: widget.customerId,
            customerName: widget.customerName,
          ),
        ),
      );

      if (generated == true) {
        await _loadBills(silent: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingBill = false;
        });
      }
    }
  }

  // ========================================================================
  // CORRECTIONS (latest statement only)
  // ========================================================================

  /// The customer's newest real bill (not an opening balance or an
  /// adjustment), while no newer bill has carried it forward.
  bool _isLatestBill(MonthlyBill bill) {
    if (bill.locked || bill.isOpeningBalance || bill.isAdjustment) {
      return false;
    }
    for (final b in _bills) {
      if (b.isAdjustment || b.isOpeningBalance) continue;
      return b.id == bill.id;
    }
    return false;
  }

  Future<void> _editBill(MonthlyBill bill) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditStatementScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          bill: bill,
        ),
      ),
    );
    if (saved == true) await _loadBills(silent: true);
  }

  /// Deletes the newest bill so it can be generated again from the goats
  /// on the farm now (e.g. after a goat was deleted or a price fixed).
  Future<void> _deleteBill(MonthlyBill bill) async {
    // The dialog owns its text controller and disposes it itself once it
    // has fully closed. Disposing it here, while the dialog was still
    // animating out, caused the "_dependents.isEmpty" red screen.
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteBillDialog(bill: bill),
    );
    if (reason == null || !mounted) return;
    if (_deletingBillIds.contains(bill.id)) return;

    // Loader on this card only; it stays until the delete has really
    // finished (on a slow connection that can take a while).
    setState(() => _deletingBillIds.add(bill.id));

    String periodKey;
    try {
      periodKey = await MonthlyStatementEngine.instance.deleteLatestBill(
        farmId: widget.farmId,
        customerId: widget.customerId,
        billId: bill.id,
        reason: reason,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingBillIds.remove(bill.id));
      _showError(FirestoreService.instance.describeError(e));
      return;
    }

    if (!mounted) return;

    // Remove the card in place: no full-screen reload.
    setState(() {
      _deletingBillIds.remove(bill.id);
      _bills = _bills.where((b) => b.id != bill.id).toList();
    });

    // Quietly refresh totals and the previous bill (it is the latest
    // again, so it gets its menu back) while the list stays on screen.
    await _loadBills(silent: true);
    if (!mounted) return;
    await _showRegenerateInfo(periodKey);
  }

  /// After deleting: says when the month can be generated again and
  /// offers to do it now when it already can.
  Future<void> _showRegenerateInfo(String periodKey) async {
    final month = periodLabel(periodKey);
    final target = MonthlyStatementEngine.instance.targetPeriodKey();
    final canNow = periodKey.compareTo(target) <= 0;
    final availableFrom = periodStart(nextPeriodKey(periodKey));

    final generateNow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Bill deleted', style: AppTheme.heading(size: 17)),
        content: Text(
          canNow
              ? 'Generate the $month bill again now? It will be worked out '
              'fresh from the goats on the farm.'
              : 'Bills are made for the previous month, so the $month bill '
              'can be generated from '
              '${DateFormat('d MMMM yyyy').format(availableFrom)} with '
              'Generate Bills.',
          style: AppTheme.body(size: 13, color: AppColors.textDark),
        ),
        actions: [
          if (canNow)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(canNow),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text(canNow ? 'Generate now' : 'OK'),
          ),
        ],
      ),
    );

    if (generateNow == true && mounted) {
      await _createMonthlyBill();
    }
  }

  // ========================================================================
  // ADJUSTMENTS + BALANCE CHECK
  // ========================================================================

  Future<void> _addAdjustment() async {
    List<String> months;
    try {
      months = await MonthlyStatementEngine.instance.adjustableMonths(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
    } catch (e) {
      _showError(FirestoreService.instance.describeError(e));
      return;
    }
    if (!mounted) return;
    if (months.isEmpty) {
      _showError(
        'No older billed months to adjust. Use Edit on the latest bill.',
      );
      return;
    }

    // The dialog owns its controllers (see _DeleteBillDialog for why).
    final result = await showDialog<_AdjustmentInput>(
      context: context,
      builder: (_) => _AdjustmentDialog(months: months),
    );
    if (result == null || !mounted) return;

    final month = result.month;
    final isCredit = result.isCredit;
    final amount = result.amount;
    final reason = result.reason;

    if (amount <= 0) {
      _showError('Enter an amount above zero.');
      return;
    }
    if (reason.isEmpty) {
      _showError('Add a reason for the adjustment.');
      return;
    }

    try {
      await MonthlyStatementEngine.instance.addAdjustment(
        farmId: widget.farmId,
        customerId: widget.customerId,
        periodKey: month,
        amount: isCredit ? -amount : amount,
        reason: reason,
      );
      if (!mounted) return;
      _showSuccess('Adjustment saved.');
      await _loadBills(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showError(FirestoreService.instance.describeError(e));
    }
  }

  Future<void> _checkBalances() async {
    List<String> issues;
    try {
      issues = await MonthlyBillingService.instance.checkCustomerConsistency(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
    } catch (e) {
      _showError(FirestoreService.instance.describeError(e));
      return;
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          issues.isEmpty ? 'Balances look right' : 'Needs a look',
          style: AppTheme.heading(size: 17),
        ),
        content: Text(
          issues.isEmpty
              ? 'The unpaid months match the customer\'s pending amount.'
              : '${issues.join('\n\n')}\n\nNothing was changed. Use an '
              'adjustment if a figure needs correcting.',
          style: AppTheme.body(size: 13, color: AppColors.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // PAYMENT TOGGLE
  // ========================================================================

  Future<void> _togglePayment(
      MonthlyBill bill,
      bool value,
      ) async {
    // Turning OFF is not a payment operation.
    //
    // We only allow the user to move to Paid by recording payment.
    // This prevents the UI from saying "Paid" when no payment exists.

    if (!value) {
      return;
    }

    if (bill.isPaid) {
      return;
    }

    if (widget.onAddPayment == null) {
      _showError(
        'Add Payment is not connected to Monthly Bills yet.',
      );
      return;
    }

    final paidSuccessfully =
    await widget.onAddPayment!(bill);

    if (!mounted) return;

    if (!paidSuccessfully) {
      // User cancelled.
      //
      // Do nothing.
      // Switch remains OFF because the bill was never changed.
      return;
    }

    await _loadBills(silent: true);
  }

  // ========================================================================
  // VIEW PDF
  // ========================================================================

  Future<void> _viewBill(
      MonthlyBill bill,
      ) async {
    if (_viewingBillIds.contains(bill.id)) return;

    setState(() {
      _viewingBillIds.add(bill.id);
    });

    try {
      final settings = await _loadBillSettings();
      await _pdfService.preview(bill, settings);
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to open bill PDF.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _viewingBillIds.remove(bill.id);
        });
      }
    }
  }

  // ========================================================================
  // DOWNLOAD / SAVE PDF
  // ========================================================================

  Future<void> _downloadBill(
      MonthlyBill bill,
      ) async {
    if (_downloadingBillIds.contains(bill.id)) return;

    setState(() {
      _downloadingBillIds.add(bill.id);
    });

    try {
      final settings = await _loadBillSettings();

      // Opens the phone's own "Save as" screen: the name can be changed
      // and any folder (Downloads, Drive...) chosen.
      final result = await _pdfService.saveAs(bill, settings);

      if (!mounted) return;

      switch (result.status) {
        case PdfSaveStatus.saved:
          _showSuccess('Saved: ${result.fileName}');
        case PdfSaveStatus.cancelled:
          break; // closed the save screen: nothing to say
        case PdfSaveStatus.shared:
          break; // share sheet was shown instead (iOS)
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        e is PlatformException
            ? (e.message ?? 'Unable to save bill PDF.')
            : 'Unable to save bill PDF.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingBillIds.remove(bill.id);
        });
      }
    }
  }

  // ========================================================================
  // SHARE PDF
  // ========================================================================

  Future<void> _shareBill(
      MonthlyBill bill,
      ) async {
    if (_sharingBillIds.contains(bill.id)) return;

    setState(() {
      _sharingBillIds.add(bill.id);
    });

    try {
      final settings = await _loadBillSettings();
      await _pdfService.share(bill, settings);
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to share bill PDF.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharingBillIds.remove(bill.id);
        });
      }
    }
  }

  // ========================================================================
  // NUMBER PARSER
  // ========================================================================

  double _number(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  // ========================================================================
  // CURRENCY
  // ========================================================================

  String _currency(
      double value,
      ) {
    final formatter = NumberFormat(
      '#,##0.00',
      'en_IN',
    );

    return '₹${formatter.format(value)}';
  }

  // ========================================================================
  // STATUS COLOR
  // ========================================================================

  Color _statusColor(
      MonthlyBillStatus status,
      ) {
    switch (status) {
      case MonthlyBillStatus.paid:
        return AppColors.success;

      case MonthlyBillStatus.partial:
        return AppColors.warning;

      case MonthlyBillStatus.unpaid:
        return AppColors.error;
    }
  }

  // ========================================================================
  // BILL CARD
  // ========================================================================

  /// The bill card, with a "Deleting…" loader over it while it is being
  /// deleted (the rest of the screen stays usable).
  Widget _buildBillCard(
      MonthlyBill bill,
      ) {
    final deleting = _deletingBillIds.contains(bill.id);
    final card = _buildBillCardContent(bill);
    if (!deleting) return card;

    return Stack(
      children: [
        AbsorbPointer(
          child: Opacity(opacity: 0.45, child: card),
        ),
        Positioned.fill(
          bottom: 14, // the card's own bottom margin
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Deleting bill…',
                    style: AppTheme.heading(size: 13, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBillCardContent(
      MonthlyBill bill,
      ) {
    // A locked (older) bill's statement balance was carried into the
    // newer bill, so its badge shows its own month's payment state.
    final displayStatus = bill.locked
        ? MonthlyBill.statusFromString(bill.effectiveOwnStatus)
        : bill.status;

    final statusColor =
    _statusColor(displayStatus);

    return Container(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:
            0.04,
            ),
            blurRadius: 10,
            offset: const Offset(
              0,
              4,
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ----------------------------------------------------------
            // TOP
            // ----------------------------------------------------------

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color:
                    AppColors.lightGreen,
                    borderRadius:
                    BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color:
                    AppColors.primaryGreen,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.displayTitle,
                        style: AppTheme.heading(
                          size: 16,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        bill.billNumber,
                        style: AppTheme.body(
                          size: 11,
                          color:
                          AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),

                _statusBadge(
                  displayStatus,
                ),

                // Corrections: only the customer's newest bill.
                if (_isLatestBill(bill) && !_deletingBillIds.contains(bill.id))
                  PopupMenuButton<String>(
                    tooltip: 'Correct bill',
                    icon: const Icon(
                      Icons.more_vert,
                      color: AppColors.textGrey,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') _editBill(bill);
                      if (value == 'delete') _deleteBill(bill);
                    },
                    itemBuilder: (_) => [
                      if (bill.isStatement)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit charges'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete bill'),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ----------------------------------------------------------
            // AMOUNTS
            // ----------------------------------------------------------

            if (bill.isStatement)
              _buildStatementFigures(bill, statusColor)
            else if (bill.isOpeningBalance)
              _buildOpeningFigures(bill, statusColor)
            else if (bill.isAdjustment)
                _buildAdjustmentFigures(bill)
              else
                _buildLegacyFigures(bill, statusColor),

            const SizedBox(height: 14),

            const Divider(
              height: 1,
            ),

            const SizedBox(height: 8),

            // ----------------------------------------------------------
            // PAYMENT
            //
            // Only the newest, unlocked bill takes a payment here: its
            // Remaining is the customer's Total Payable. An older bill's
            // unpaid amount was carried into the next statement and is
            // paid through that one (payments always clear the oldest
            // month first).
            // ----------------------------------------------------------

            if (bill.isAdjustment)
              const SizedBox.shrink()
            else if (bill.locked)
              _buildCarriedForwardNote(bill)
            else
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          bill.isPaid
                              ? Icons
                              .check_circle_outline
                              : Icons
                              .radio_button_unchecked,
                          size: 20,
                          color:
                          bill.isPaid
                              ? AppColors
                              .success
                              : AppColors
                              .textGrey,
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        Text(
                          bill.isPaid
                              ? 'Paid'
                              : bill.isPartiallyPaid
                              ? 'Partially Paid'
                              : 'Unpaid',
                          style:
                          AppTheme.body(
                            size: 13,
                            weight:
                            FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Switch(
                    value: bill.isPaid,
                    activeColor:
                    AppColors.success,
                    onChanged: bill.isPaid
                        ? null
                        : (value) {
                      _togglePayment(
                        bill,
                        value,
                      );
                    },
                  ),
                ],
              ),

            const SizedBox(height: 8),

            // ----------------------------------------------------------
            // PDF ACTIONS
            // ----------------------------------------------------------

            // An opening balance is not a bill of its own; it is shown on
            // the customer's first bill, so it has no PDF.
            if (!bill.isOpeningBalance && !bill.isAdjustment)
              Builder(
                builder: (context) {
                  final isViewing =
                  _viewingBillIds.contains(bill.id);
                  final isDownloading =
                  _downloadingBillIds.contains(bill.id);
                  final isSharing =
                  _sharingBillIds.contains(bill.id);

                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isViewing
                              ? null
                              : () {
                            _viewBill(bill);
                          },
                          icon: isViewing
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                            CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors
                                  .primaryGreen,
                            ),
                          )
                              : const Icon(
                            Icons.visibility_outlined,
                            size: 18,
                          ),
                          label: Text(
                            isViewing
                                ? 'Opening…'
                                : 'View Bill',
                          ),
                          style:
                          OutlinedButton.styleFrom(
                            foregroundColor:
                            AppColors
                                .primaryGreen,
                            side: const BorderSide(
                              color:
                              AppColors
                                  .primaryGreen,
                            ),
                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(
                                11,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isDownloading
                              ? null
                              : () {
                            _downloadBill(bill);
                          },
                          icon: isDownloading
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                            CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors
                                  .textDark,
                            ),
                          )
                              : const Icon(
                            Icons.download_outlined,
                            size: 18,
                          ),
                          label: Text(
                            isDownloading
                                ? 'Saving…'
                                : 'Download',
                          ),
                          style:
                          OutlinedButton.styleFrom(
                            foregroundColor:
                            AppColors.textDark,
                            side: BorderSide(
                              color: Colors.grey.shade300,
                            ),
                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(
                                11,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      IconButton(
                        tooltip: 'Share bill',
                        onPressed: isSharing
                            ? null
                            : () {
                          _shareBill(bill);
                        },
                        icon: isSharing
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors
                                .primaryGreen,
                          ),
                        )
                            : const Icon(
                          Icons.share_outlined,
                        ),
                        color:
                        AppColors.primaryGreen,
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // STATEMENT FIGURES
  // ========================================================================

  /// Statement bill: the month's own charges, what was carried forward,
  /// the advance used, and the Total Payable the customer was shown.
  Widget _buildStatementFigures(MonthlyBill bill, Color statusColor) {
    final month = periodLabel(bill.billingPeriodKey);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _figureRow(
            '$month charges (${bill.goatCount} goat${bill.goatCount == 1 ? '' : 's'})',
            _currency(bill.currentBillAmount),
          ),
          const SizedBox(height: 5),
          _figureRow(
            'Previous outstanding',
            _currency(bill.previousOutstanding),
          ),
          for (final line in bill.previousBreakdown)
            _figureRow(
              '   ${line.displayLabel}',
              _currency(line.amount),
              muted: true,
            ),
          if (bill.earlierBalance > kMoneyEpsilon)
            _figureRow(
              '   Earlier balance',
              _currency(bill.earlierBalance),
              muted: true,
            ),
          if (bill.adjustmentLines.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Adjustments since the last bill (already included above):',
                style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
              ),
            ),
            for (final line in bill.adjustmentLines)
              _figureRow(
                '   ${line.displayLabel}',
                '${line.amount < 0 ? '−' : '+'} ${_currency(line.amount.abs())}',
                muted: true,
              ),
          ],
          if (bill.advanceApplied > kMoneyEpsilon) ...[
            const SizedBox(height: 5),
            _figureRow(
              'Less: advance applied',
              '− ${_currency(bill.advanceApplied)}',
            ),
          ],
          if (bill.paidFromDeletedBill > kMoneyEpsilon) ...[
            const SizedBox(height: 5),
            _figureRow(
              'Less: already paid for $month',
              '− ${_currency(bill.paidFromDeletedBill)}',
            ),
          ],
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total payable',
                  style: AppTheme.heading(size: 14),
                ),
              ),
              Text(
                _currency(bill.totalPayable),
                style: AppTheme.heading(size: 17),
              ),
            ],
          ),
          if (bill.amountPaid > kMoneyEpsilon) ...[
            const SizedBox(height: 4),
            _figureRow('Paid on this bill', _currency(bill.amountPaid)),
          ],
          if (!bill.locked) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Remaining',
                    style: AppTheme.body(size: 12, color: AppColors.textGrey),
                  ),
                ),
                Text(
                  _currency(bill.remainingAmount),
                  style: AppTheme.heading(size: 15, color: statusColor),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$month charges: ${_ownStatusText(bill)}',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
          ),
        ],
      ),
    );
  }

  /// Opening balance entered when the customer was added: what was still
  /// owed for the months before their first bill.
  Widget _buildOpeningFigures(MonthlyBill bill, Color statusColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _figureRow('Pending when added', _currency(bill.currentBillAmount)),
          _figureRow('Paid', _currency(bill.effectiveOwnPaid)),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Still owed',
                  style: AppTheme.body(size: 12, color: AppColors.textGrey),
                ),
              ),
              Text(
                _currency(bill.effectiveOwnRemaining),
                style: AppTheme.heading(size: 15, color: statusColor),
              ),
            ],
          ),
          if (bill.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                bill.notes,
                style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdjustmentFigures(MonthlyBill bill) {
    final amount = bill.currentBillAmount;
    final isCredit = amount < 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _figureRow(
            isCredit ? 'Credit' : 'Extra charge',
            '${isCredit ? '−' : '+'} ${_currency(amount.abs())}',
          ),
          if (!isCredit)
            _figureRow('Still owed', _currency(bill.effectiveOwnRemaining)),
          if (bill.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: ${bill.notes}',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Shown on the customer\'s next bill.',
            style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  /// Bill made before statement billing: only that month's own charge.
  Widget _buildLegacyFigures(MonthlyBill bill, Color statusColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _figureRow('Monthly bill', _currency(bill.currentBillAmount)),
          if (bill.advanceApplied > kMoneyEpsilon)
            _figureRow(
              'Less: advance applied',
              '− ${_currency(bill.advanceApplied)}',
            ),
          _figureRow('Paid', _currency(bill.effectiveOwnPaid)),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Remaining on this month',
                  style: AppTheme.body(size: 12, color: AppColors.textGrey),
                ),
              ),
              Text(
                _currency(bill.effectiveOwnRemaining),
                style: AppTheme.heading(size: 15, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Older-style bill. Previous outstanding at the time: '
                  '${_currency(bill.previousOutstanding)} (not part of this '
                  'month\'s amount).',
              style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarriedForwardNote(MonthlyBill bill) {
    final remaining = bill.effectiveOwnRemaining;
    final text = remaining > kMoneyEpsilon
        ? '${_currency(remaining)} of this month is still unpaid and is '
        'included in the newer bill\'s Previous outstanding.'
        : 'This month is fully paid.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            remaining > kMoneyEpsilon
                ? Icons.redo_rounded
                : Icons.check_circle_outline,
            size: 18,
            color: remaining > kMoneyEpsilon
                ? AppColors.warning
                : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(size: 12, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  String _ownStatusText(MonthlyBill bill) {
    switch (bill.effectiveOwnStatus) {
      case 'paid':
        return 'paid';
      case 'partial':
        return '${_currency(bill.effectiveOwnRemaining)} still unpaid';
      default:
        return 'unpaid';
    }
  }

  Widget _figureRow(String label, String value, {bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: muted ? 11 : 12,
                color: muted ? AppColors.textGrey : AppColors.textDark,
              ),
            ),
          ),
          Text(
            value,
            style: AppTheme.body(
              size: muted ? 11 : 12,
              color: muted ? AppColors.textGrey : AppColors.textDark,
              weight: muted ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // STATUS BADGE
  // ========================================================================

  Widget _statusBadge(
      MonthlyBillStatus status,
      ) {
    final color =
    _statusColor(status);

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha:
        0.10,
        ),
        borderRadius:
        BorderRadius.circular(8),
      ),
      child: Text(
        status == MonthlyBillStatus.paid
            ? 'PAID'
            : status ==
            MonthlyBillStatus.partial
            ? 'PARTIAL'
            : 'UNPAID',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight:
          FontWeight.w800,
        ),
      ),
    );
  }

  // ========================================================================
  // EMPTY
  // ========================================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        top: 50,
      ),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 30,
              color:
              AppColors.primaryGreen,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'No Monthly Bills',
            style: AppTheme.heading(
              size: 17,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            'Bills are for the previous month. Generate one here, or for '
                'every customer with Generate Bills on the Customers screen.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
          ),

          const SizedBox(height: 18),

          ElevatedButton.icon(
            onPressed:
            _creatingBill
                ? null
                : _createMonthlyBill,
            icon: const Icon(
              Icons.add,
            ),
            label:
            const Text('Generate bill'),
            style:
            ElevatedButton.styleFrom(
              backgroundColor:
              AppColors.primaryGreen,
              foregroundColor:
              Colors.white,
              shape:
              RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // SNACKBARS
  // ========================================================================

  void _showSuccess(
      String message,
      ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        AppColors.success,
      ),
    );
  }

  void _showError(
      String message,
      ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        AppColors.error,
        duration:
        const Duration(seconds: 4),
      ),
    );
  }

  // ========================================================================
  // BUILD
  // ========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor:
        AppColors.paleGreen,
        foregroundColor:
        AppColors.textDark,
        elevation: 0,
        title: Text(
          'Monthly Bills',
          style: AppTheme.heading(
            size: 18,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'adjust') _addAdjustment();
              if (value == 'check') _checkBalances();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'adjust',
                child: Text('Add adjustment'),
              ),
              PopupMenuItem(
                value: 'check',
                child: Text('Check balances'),
              ),
            ],
          ),
          IconButton(
            tooltip:
            'Generate bill',
            onPressed:
            _creatingBill
                ? null
                : _createMonthlyBill,
            icon: _creatingBill
                ? const SizedBox(
              width: 20,
              height: 20,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
                color:
                AppColors
                    .primaryGreen,
              ),
            )
                : const Icon(
              Icons.add,
            ),
          ),
        ],
      ),

      body: RefreshIndicator(
        color:
        AppColors.primaryGreen,
        onRefresh: () => _loadBills(silent: true),
        child: _loading
            ? const Center(
          child:
          CircularProgressIndicator(
            color:
            AppColors
                .primaryGreen,
          ),
        )
            : _bills.isEmpty
            ? ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          children: [
            _buildEmptyState(),
          ],
        )
            : ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            32,
          ),
          children: [
            // --------------------------------------------------
            // CUSTOMER HEADER
            // --------------------------------------------------

            Container(
              width:
              double.infinity,
              padding:
              const EdgeInsets
                  .all(16),
              decoration:
              BoxDecoration(
                color:
                Colors.white,
                borderRadius:
                BorderRadius
                    .circular(
                  16,
                ),
                border:
                Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration:
                    const BoxDecoration(
                      color: AppColors
                          .lightGreen,
                      shape:
                      BoxShape
                          .circle,
                    ),
                    alignment:
                    Alignment
                        .center,
                    child: Text(
                      widget.customerName
                          .isNotEmpty
                          ? widget
                          .customerName[
                      0]
                          .toUpperCase()
                          : '?',
                      style:
                      AppTheme
                          .heading(
                        size: 17,
                        color: AppColors
                            .darkGreen,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          widget
                              .customerName,
                          style:
                          AppTheme
                              .heading(
                            size: 15,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          '${_bills.length} monthly bill${_bills.length == 1 ? '' : 's'}'
                              '${_livePending == null ? '' : ' · Total pending ${_currency(_livePending!)}'}'
                              '${(_liveAdvance ?? 0) > kMoneyEpsilon ? ' · Advance ${_currency(_liveAdvance!)}' : ''}'
                              '${(_liveCredit ?? 0) > kMoneyEpsilon ? ' · Paid ${_currency(_liveCredit!)} on a deleted bill (used on the next bill)' : ''}',
                          style:
                          AppTheme
                              .body(
                            size: 11,
                            color: AppColors
                                .textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            ..._bills.map(
              _buildBillCard,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DIALOGS
// ============================================================================
//
// Each dialog is its own StatefulWidget so its TextEditingControllers are
// disposed in its own dispose(), i.e. only after the dialog has completely
// left the screen.

class _DeleteBillDialog extends StatefulWidget {
  const _DeleteBillDialog({required this.bill});

  final MonthlyBill bill;

  @override
  State<_DeleteBillDialog> createState() => _DeleteBillDialogState();
}

class _DeleteBillDialogState extends State<_DeleteBillDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final month = bill.displayTitle;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Delete $month bill?', style: AppTheme.heading(size: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use this when the bill is wrong, for example a goat was '
                  'deleted or a price changed after it was made.',
              style: AppTheme.body(size: 12.5, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            Text(
              '• ${bill.billNumber} is removed from the bills (a deleted '
                  'record is kept).\n'
                  '• Its charges come off what the customer owes. Any '
                  'advance it used goes back to advance.\n'
                  '• Money already paid for this month is kept and used '
                  'on the new bill, so nothing paid is lost.\n'
                  '• Payments for older months stay as they are.\n'
                  '• Generating again works the bill out fresh from the '
                  'goats on the farm now.',
              style: AppTheme.body(size: 12, color: AppColors.textDark),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          // Pops the reason ('' when none); null means cancelled.
          onPressed: () =>
              Navigator.of(context).pop(_reasonController.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Delete bill'),
        ),
      ],
    );
  }
}

class _AdjustmentInput {
  const _AdjustmentInput({
    required this.month,
    required this.isCredit,
    required this.amount,
    required this.reason,
  });

  final String month;
  final bool isCredit;
  final double amount;
  final String reason;
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({required this.months});

  /// Adjustable months, newest first.
  final List<String> months;

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  late String _month = widget.months.first;
  bool _isCredit = false;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Add adjustment', style: AppTheme.heading(size: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _month,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'For month',
              ),
              items: [
                for (final m in widget.months)
                  DropdownMenuItem(value: m, child: Text(periodLabel(m))),
              ],
              onChanged: (v) =>
                  setState(() => _month = v ?? widget.months.first),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Charge more'),
                  selected: !_isCredit,
                  onSelected: (_) => setState(() => _isCredit = false),
                ),
                ChoiceChip(
                  label: const Text('Credit (reduce)'),
                  selected: _isCredit,
                  onSelected: (_) => setState(() => _isCredit = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Reason (required)',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isCredit
                  ? 'Reduces what the customer owes, oldest month first. '
                  'Anything beyond what they owe becomes advance.'
                  : 'Added to what the customer owes for that month.',
              style: AppTheme.body(size: 11.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
            _AdjustmentInput(
              month: _month,
              isCredit: _isCredit,
              amount: double.tryParse(_amountController.text.trim()) ?? 0,
              reason: _reasonController.text.trim(),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}