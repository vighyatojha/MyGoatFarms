import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../services/pdf_bill_service.dart';
import '../../widgets/fast_route.dart';
import 'checkout_success_screen.dart';

/// Data carried from the Review Checkout screen into
/// Charges & Payment.
class GoatCheckoutDraft {
  final PalaiGoat goat;
  final double finalWeight;
  final String healthStatus;
  final String deliveryStatus;
  final Uint8List? afterImage;
  final String notes;

  const GoatCheckoutDraft({
    required this.goat,
    required this.finalWeight,
    required this.healthStatus,
    required this.deliveryStatus,
    required this.afterImage,
    required this.notes,
  });
}

class CheckoutChargesPaymentScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final List<GoatCheckoutDraft> goats;

  const CheckoutChargesPaymentScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goats,
  });

  @override
  State<CheckoutChargesPaymentScreen> createState() =>
      _CheckoutChargesPaymentScreenState();
}

class _CheckoutChargesPaymentScreenState
    extends State<CheckoutChargesPaymentScreen> {
  PalaiCustomer? _customer;

  BillSettings _billSettings = const BillSettings();

  bool _loading = true;
  bool _saving = false;

  String? _error;

  late final TextEditingController _chargesController;
  late final TextEditingController _transportController;
  late final TextEditingController _discountController;
  late final TextEditingController _paidController;
  late final TextEditingController _noteController;

  String _paymentMethod = 'Cash';

  @override
  void initState() {
    super.initState();

    final defaultCharges = widget.goats.fold<double>(
      0,
          (sum, item) => sum + item.goat.pricing,
    );

    _chargesController = TextEditingController(
      text: defaultCharges.toStringAsFixed(0),
    );

    _transportController =
        TextEditingController(text: '0');

    _discountController =
        TextEditingController(text: '0');

    _paidController =
        TextEditingController(text: '0');

    _noteController =
        TextEditingController();

    _loadCustomer();
  }

  // ================================================================
  // LOAD CUSTOMER
  // ================================================================

  Future<void> _loadCustomer() async {
    try {
      final customer =
      await FirestoreService.instance.getCustomer(
        widget.farmId,
        widget.customerId,
      );

      if (!mounted) return;

      if (customer == null) {
        setState(() {
          _loading = false;
          _error = 'Customer could not be found.';
        });
        return;
      }

      final farm = await FirestoreService.instance.getFarmById(
        widget.farmId,
      );

      if (!mounted) return;

      setState(() {
        _customer = customer;
        _billSettings = farm?.billSettings ?? const BillSettings();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = FirestoreService.instance
            .describeError(e);
      });
    }
  }

  Future<void> _shareCheckoutBill(
      MonthlyBillResult billResult,
      ) async {
    try {
      if (_customer == null) {
        throw StateError('Customer information is unavailable.');
      }

      await PdfBillService.instance.shareMonthlyBill(
        customerName: _customer!.name,
        billNumber: billResult.billNumber,

        monthlyCharges: _palaiCharges,
        transport: _transport,

        previousBalance: billResult.previousPending,

        discount: _discount,
        paid: billResult.paid,

        // Total before applying the customer's advance.
        totalBill: _totalBeforeAdvance,

        pendingAmount: billResult.pendingAfter,

        advanceBefore: billResult.advanceBefore,
        advanceApplied: billResult.advanceApplied,
        advanceAfter: billResult.advanceAfter,

        paymentMethod: billResult.paymentMethod,

        billSettings: _billSettings,
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Could not share the PDF: '
            '${FirestoreService.instance.describeError(e)}',
      );
    }
  }

  Future<String> _saveCheckoutBillAndReturnPath(
      MonthlyBillResult billResult,
      ) async {
    if (_customer == null) {
      throw StateError(
        'Customer information is unavailable.',
      );
    }

    final path =
    await PdfBillService.instance.saveMonthlyBillToDevice(
      customerName: _customer!.name,
      billNumber: billResult.billNumber,

      monthlyCharges: _palaiCharges,
      transport: _transport,

      previousBalance:
      billResult.previousPending,

      discount: _discount,
      paid: billResult.paid,

      totalBill:
      _totalBeforeAdvance,

      pendingAmount:
      billResult.pendingAfter,

      advanceBefore:
      billResult.advanceBefore,

      advanceApplied:
      billResult.advanceApplied,

      advanceAfter:
      billResult.advanceAfter,

      paymentMethod:
      billResult.paymentMethod,

      billSettings:
      _billSettings,
    );

    return path;
  }

  // ================================================================
  // PARSING
  // ================================================================

  double _parse(
      TextEditingController controller,
      ) {
    return double.tryParse(
      controller.text.trim(),
    ) ??
        0;
  }

  // ================================================================
  // AMOUNT CALCULATIONS
  // ================================================================

  double get _palaiCharges =>
      _parse(_chargesController);

  double get _transport =>
      _parse(_transportController);

  double get _discount =>
      _parse(_discountController);

  double get _paid =>
      _parse(_paidController);

  double get _previousPending =>
      _customer?.pendingAmount ?? 0;

  double get _advanceBefore =>
      _customer?.advanceAmount ?? 0;

  double get _newCharges {
    return (_palaiCharges +
        _transport -
        _discount)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  double get _totalBeforeAdvance {
    return _previousPending +
        _newCharges;
  }

  double get _advanceApplied {
    return _advanceBefore
        .clamp(
      0,
      _totalBeforeAdvance,
    )
        .toDouble();
  }

  double get _totalDue {
    return (_totalBeforeAdvance -
        _advanceApplied)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  double get _amountAppliedFromPayment {
    return _paid
        .clamp(
      0,
      _totalDue,
    )
        .toDouble();
  }

  double get _newAdvanceFromPayment {
    return (_paid - _totalDue)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  double get _pendingAfter {
    return (_totalDue - _paid)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  double get _advanceAfter {
    return (_advanceBefore -
        _advanceApplied +
        _newAdvanceFromPayment)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  // ================================================================
  // SAVE CHECKOUT
  // ================================================================

  Future<void> _completeCheckout() async {
    if (_saving) return;

    if (widget.goats.isEmpty) {
      _showError(
        'No goats were selected for checkout.',
      );
      return;
    }

    if (_palaiCharges < 0 ||
        _transport < 0 ||
        _discount < 0 ||
        _paid < 0) {
      _showError(
        'Amounts cannot be negative.',
      );
      return;
    }

    if (_discount >
        (_palaiCharges + _transport)) {
      _showError(
        'Discount cannot be greater than the charges.',
      );
      return;
    }

    if (_paid > 0 &&
        _paymentMethod.trim().isEmpty) {
      _showError(
        'Please select a payment method.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // ------------------------------------------------------------
      // 1. CREATE BILL / PAYMENT
      // ------------------------------------------------------------

      final billResult =
      await FirestoreService.instance
          .createMonthlyBill(
        farmId: widget.farmId,
        customerId: widget.customerId,
        monthlyCharges: _palaiCharges,
        transportCharges: _transport,
        discount: _discount,
        paidAmount: _paid,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
      );

      // ------------------------------------------------------------
      // 2. CHECK OUT EVERY SELECTED GOAT
      // ------------------------------------------------------------

      for (final draft in widget.goats) {
        await FirestoreService.instance.checkOutGoat(
          widget.farmId,
          widget.customerId,
          draft.goat.id,
          finalWeight: draft.finalWeight,
          healthStatus: draft.healthStatus,
          afterImage: draft.afterImage,
          afterImageContentType:
          draft.afterImage != null
              ? 'image/jpeg'
              : null,
        );
      }

      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      // ------------------------------------------------------------
      // 3. SHOW SUCCESS
      // ------------------------------------------------------------

      await _showSuccessDialog(
        billNumber: billResult.billNumber,
        billResult: billResult,
      );

      if (!mounted) return;

      // ------------------------------------------------------------
      // 4. OFFER EACH GOAT'S OWN FINAL CHECK-OUT REPORT
      // ------------------------------------------------------------
      // The dialog above covers the customer's combined monthly bill.
      // Each goat also gets its own final report (weight, health,
      // before/after photos) via CheckoutSuccessScreen.

      await _offerFinalCheckoutReports();

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        FirestoreService.instance.describeError(e),
      );
    }
  }

  // ================================================================
  // SUCCESS DIALOG
  // ================================================================

  Future<void> _showSuccessDialog({
    required String billNumber,
    required MonthlyBillResult billResult,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool pdfBusy = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> shareBill() async {
              if (pdfBusy) return;

              setDialogState(() {
                pdfBusy = true;
              });

              try {
                await _shareCheckoutBill(billResult);

                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Bill PDF is ready to share.'),
                    backgroundColor: AppColors.primaryGreen,
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Could not share bill: '
                          '${FirestoreService.instance.describeError(e)}',
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    pdfBusy = false;
                  });
                }
              }
            }

            Future<void> downloadBill() async {
              if (pdfBusy) return;

              setDialogState(() {
                pdfBusy = true;
              });

              try {
                final path = await _saveCheckoutBillAndReturnPath(
                  billResult,
                );

                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Bill saved successfully.\n$path',
                    ),
                    backgroundColor: AppColors.primaryGreen,
                    duration: const Duration(seconds: 4),
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Could not save bill: '
                          '${FirestoreService.instance.describeError(e)}',
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    pdfBusy = false;
                  });
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),

              title: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.lightGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.primaryGreen,
                      size: 27,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      'Checkout Completed',
                      style: AppTheme.heading(size: 18),
                    ),
                  ),
                ],
              ),

              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.goats.length} '
                          '${widget.goats.length == 1 ? 'goat' : 'goats'} '
                          'checked out successfully.',
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.textDark,
                      ),
                    ),

                    const SizedBox(height: 18),

                    _dialogRow(
                      'Bill Number',
                      billResult.billNumber,
                    ),

                    _dialogRow(
                      'New Charges',
                      _rupees(billResult.newCharges),
                    ),

                    _dialogRow(
                      'Previous Pending',
                      _rupees(billResult.previousPending),
                    ),

                    _dialogRow(
                      'Advance Applied',
                      _rupees(billResult.advanceApplied),
                    ),

                    _dialogRow(
                      'Total Due',
                      _rupees(billResult.totalDue),
                    ),

                    _dialogRow(
                      'Paid',
                      _rupees(billResult.paid),
                    ),

                    _dialogRow(
                      'Pending After',
                      _rupees(billResult.pendingAfter),
                    ),

                    _dialogRow(
                      'Advance After',
                      _rupees(billResult.advanceAfter),
                    ),

                    const SizedBox(height: 22),

                    // ------------------------------------------------
                    // BILL ACTIONS
                    // ------------------------------------------------

                    Text(
                      'Bill & Receipt',
                      style: AppTheme.heading(size: 14),
                    ),

                    const SizedBox(height: 10),

                    // SHARE BILL
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: pdfBusy ? null : shareBill,
                        icon: pdfBusy
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(
                          Icons.share_rounded,
                          size: 19,
                        ),
                        label: Text(
                          pdfBusy
                              ? 'Preparing Bill...'
                              : 'Share Bill PDF',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // DOWNLOAD BILL
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: pdfBusy ? null : downloadBill,
                        icon: const Icon(
                          Icons.download_rounded,
                          size: 19,
                        ),
                        label: const Text(
                          'Download Bill PDF',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(
                            color: AppColors.primaryGreen,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'You can share the bill directly through WhatsApp, '
                          'email or other apps.',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed: pdfBusy
                      ? null
                      : () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    'Done',
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.textGrey,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================================================================
  // PER-GOAT FINAL CHECK-OUT REPORT
  // ================================================================

  /// Single goat: goes straight to its final report. Multiple goats:
  /// offers a pick list so the user can view/share any (or all) of
  /// them before finishing, without forcing a screen per goat.
  Future<void> _offerFinalCheckoutReports() async {
    if (widget.goats.length == 1) {
      await _pushFinalCheckoutReport(widget.goats.first);
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Final Check-out Reports',
                  style: AppTheme.heading(size: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'View or share each goat\'s own report.',
                  style: AppTheme.body(size: 12, color: AppColors.textGrey),
                ),
                const SizedBox(height: 12),
                ...widget.goats.map(
                      (draft) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined, color: AppColors.primaryGreen),
                    title: Text(draft.goat.goatCode, style: AppTheme.body(size: 13, weight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _pushFinalCheckoutReport(draft),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pushFinalCheckoutReport(GoatCheckoutDraft draft) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      fastRoute(
        CheckoutSuccessScreen(
          goat: draft.goat,
          finalWeight: draft.finalWeight,
          healthStatus: draft.healthStatus,
          deliveryStatus: draft.deliveryStatus,
          totalCharges: draft.goat.pricing,
          beforeImage: draft.goat.beforeImage,
          afterImage: draft.afterImage,
          billSettings: _billSettings,
        ),
      ),
    );
  }

  // ================================================================
  // ERROR
  // ================================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  // ================================================================
  // RUPEES
  // ================================================================

  String _rupees(double value) {
    return '₹${value.toStringAsFixed(0)}';
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor:
        AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor:
          AppColors.paleGreen,
          elevation: 0,
          title: Text(
            'Charges & Payment',
            style:
            AppTheme.heading(size: 17),
          ),
        ),
        body: const Center(
          child:
          CircularProgressIndicator(
            color:
            AppColors.primaryGreen,
          ),
        ),
      );
    }

    if (_error != null ||
        _customer == null) {
      return Scaffold(
        backgroundColor:
        AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor:
          AppColors.paleGreen,
          elevation: 0,
          title: Text(
            'Charges & Payment',
            style:
            AppTheme.heading(size: 17),
          ),
        ),
        body: Center(
          child: Padding(
            padding:
            const EdgeInsets.all(24),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 46,
                ),
                const SizedBox(height: 12),
                Text(
                  _error ??
                      'Customer not found.',
                  textAlign:
                  TextAlign.center,
                  style:
                  AppTheme.body(size: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
      AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor:
        AppColors.paleGreen,
        elevation: 0,
        foregroundColor:
        AppColors.textDark,
        title: Text(
          'Charges & Payment',
          style:
          AppTheme.heading(size: 17),
        ),
      ),

      bottomNavigationBar:
      _buildBottomBar(),

      body: SafeArea(
        child: ListView(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            10,
            16,
            120,
          ),
          children: [
            _buildHeader(),

            const SizedBox(height: 16),

            _buildCustomerCard(),

            const SizedBox(height: 16),

            _buildGoatsCard(),

            const SizedBox(height: 16),

            _buildChargesCard(),

            const SizedBox(height: 16),

            _buildBalanceCard(),

            const SizedBox(height: 16),

            _buildPaymentCard(),

            const SizedBox(height: 16),

            _buildNoteCard(),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // HEADER
  // ================================================================

  Widget _buildHeader() {
    return Container(
      padding:
      const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient:
        const LinearGradient(
          colors:
          AppColors.headerGradient,
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
        ),
        borderRadius:
        BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration:
            BoxDecoration(
              color:
              Colors.white
                  .withOpacity(.18),
              shape:
              BoxShape.circle,
            ),
            child:
            const Icon(
              Icons.receipt_long_outlined,
              color:
              Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Charges & Payment',
                  style:
                  AppTheme.heading(
                    size: 17,
                    color:
                    Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Complete the final bill and payment.',
                  style:
                  AppTheme.body(
                    size: 11,
                    color: Colors.white
                        .withOpacity(.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // CUSTOMER CARD
  // ================================================================

  Widget _buildCustomerCard() {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      AppTheme.card(radius: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration:
            const BoxDecoration(
              color:
              AppColors.lightGreen,
              shape:
              BoxShape.circle,
            ),
            alignment:
            Alignment.center,
            child: Text(
              _customer!.name.isNotEmpty
                  ? _customer!.name[0]
                  .toUpperCase()
                  : '?',
              style:
              AppTheme.heading(
                size: 18,
                color:
                AppColors.darkGreen,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  _customer!.name,
                  style:
                  AppTheme.heading(
                    size: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _customer!.mobileNumber,
                  style:
                  AppTheme.body(size: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  _customer!.package,
                  style:
                  AppTheme.body(
                    size: 10,
                    color:
                    AppColors.darkGreen,
                    weight:
                    FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // GOATS CARD
  // ================================================================

  Widget _buildGoatsCard() {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pets,
                color:
                AppColors.primaryGreen,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                'Goats Being Checked Out',
                style:
                AppTheme.heading(size: 14),
              ),
              const Spacer(),
              Text(
                '${widget.goats.length}',
                style:
                AppTheme.heading(
                  size: 14,
                  color:
                  AppColors.primaryGreen,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          ...widget.goats.map(
                (draft) => Padding(
              padding:
              const EdgeInsets.only(
                bottom: 8,
              ),
              child: Container(
                padding:
                const EdgeInsets.all(10),
                decoration:
                BoxDecoration(
                  color:
                  AppColors.paleGreen,
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration:
                      const BoxDecoration(
                        color:
                        AppColors.lightGreen,
                        shape:
                        BoxShape.circle,
                      ),
                      child:
                      const Icon(
                        Icons.pets,
                        size: 19,
                        color:
                        AppColors
                            .primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          Text(
                            draft.goat
                                .goatCode,
                            style:
                            AppTheme
                                .heading(
                              size: 12,
                            ),
                          ),
                          const SizedBox(
                            height: 2,
                          ),
                          Text(
                            '${draft.goat.breed} · ${draft.goat.gender}',
                            style:
                            AppTheme.body(
                              size: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${draft.goat.pricing.toStringAsFixed(0)}',
                      style:
                      AppTheme.heading(
                        size: 11,
                        color:
                        AppColors
                            .darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // CHARGES
  // ================================================================

  Widget _buildChargesCard() {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Charges',
            style:
            AppTheme.heading(size: 14),
          ),

          const SizedBox(height: 12),

          _amountField(
            label:
            'Palai Charges',
            controller:
            _chargesController,
            onChanged:
                (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          _amountField(
            label:
            'Transport Charges',
            controller:
            _transportController,
            onChanged:
                (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          _amountField(
            label:
            'Discount',
            controller:
            _discountController,
            onChanged:
                (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // BALANCE
  // ================================================================

  Widget _buildBalanceCard() {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      BoxDecoration(
        color:
        Colors.white,
        borderRadius:
        BorderRadius.circular(16),
        border:
        Border.all(
          color:
          AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Account Summary',
            style:
            AppTheme.heading(size: 14),
          ),

          const SizedBox(height: 12),

          _summaryRow(
            'Previous Outstanding',
            _rupees(
              _previousPending,
            ),
            valueColor:
            _previousPending > 0
                ? AppColors.error
                : AppColors.success,
          ),

          _summaryRow(
            'New Charges',
            _rupees(_newCharges),
          ),

          _summaryRow(
            'Advance Available',
            _rupees(
              _advanceBefore,
            ),
            valueColor:
            AppColors.success,
          ),

          _summaryRow(
            'Advance Applied',
            _rupees(
              _advanceApplied,
            ),
            valueColor:
            AppColors.success,
          ),

          const Divider(
            height: 22,
          ),

          _summaryRow(
            'Total Due',
            _rupees(_totalDue),
            bold: true,
          ),

          _summaryRow(
            'Payment Received',
            _rupees(_paid),
            valueColor:
            AppColors.success,
          ),

          _summaryRow(
            'Pending After',
            _rupees(
              _pendingAfter,
            ),
            valueColor:
            _pendingAfter > 0
                ? AppColors.error
                : AppColors.success,
            bold: true,
          ),

          if (_advanceAfter > 0)
            _summaryRow(
              'Advance After',
              _rupees(
                _advanceAfter,
              ),
              valueColor:
              AppColors.darkGreen,
              bold: true,
            ),
        ],
      ),
    );
  }

  // ================================================================
  // PAYMENT
  // ================================================================

  Widget _buildPaymentCard() {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Payment',
            style:
            AppTheme.heading(size: 14),
          ),

          const SizedBox(height: 12),

          _amountField(
            label:
            'Amount Received',
            controller:
            _paidController,
            onChanged:
                (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          Text(
            'Payment Method',
            style:
            AppTheme.body(
              size: 11,
              weight:
              FontWeight.w600,
            ),
          ),

          const SizedBox(height: 6),

          Container(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            decoration:
            BoxDecoration(
              color:
              Colors.white,
              borderRadius:
              BorderRadius.circular(
                12,
              ),
              border:
              Border.all(
                color:
                AppColors.divider,
              ),
            ),
            child:
            DropdownButtonHideUnderline(
              child:
              DropdownButton<String>(
                value:
                _paymentMethod,
                isExpanded:
                true,
                items:
                const [
                  DropdownMenuItem(
                    value:
                    'Cash',
                    child:
                    Text('Cash'),
                  ),
                  DropdownMenuItem(
                    value:
                    'UPI',
                    child:
                    Text('UPI'),
                  ),
                  DropdownMenuItem(
                    value:
                    'Bank Transfer',
                    child:
                    Text(
                        'Bank Transfer'),
                  ),
                  DropdownMenuItem(
                    value:
                    'Cheque',
                    child:
                    Text('Cheque'),
                  ),
                  DropdownMenuItem(
                    value:
                    'Other',
                    child:
                    Text('Other'),
                  ),
                ],
                onChanged:
                    (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _paymentMethod =
                        value;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // NOTE
  // ================================================================

  Widget _buildNoteCard() {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Note',
            style:
            AppTheme.heading(size: 14),
          ),

          const SizedBox(height: 10),

          TextField(
            controller:
            _noteController,
            maxLines: 3,
            decoration:
            InputDecoration(
              hintText:
              'Add any checkout or payment note...',
              filled:
              true,
              fillColor:
              Colors.white,
              border:
              OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
                borderSide:
                const BorderSide(
                  color:
                  AppColors.divider,
                ),
              ),
              enabledBorder:
              OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
                borderSide:
                const BorderSide(
                  color:
                  AppColors.divider,
                ),
              ),
              focusedBorder:
              OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
                borderSide:
                const BorderSide(
                  color:
                  AppColors
                      .primaryGreen,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // AMOUNT FIELD
  // ================================================================

  Widget _amountField({
    required String label,
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
          AppTheme.body(
            size: 11,
            weight:
            FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller:
          controller,
          keyboardType:
          const TextInputType
              .numberWithOptions(
            decimal: true,
          ),
          onChanged:
          onChanged,
          decoration:
          InputDecoration(
            prefixText:
            '₹ ',
            filled:
            true,
            fillColor:
            Colors.white,
            border:
            OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(
                12,
              ),
              borderSide:
              const BorderSide(
                color:
                AppColors.divider,
              ),
            ),
            enabledBorder:
            OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(
                12,
              ),
              borderSide:
              const BorderSide(
                color:
                AppColors.divider,
              ),
            ),
            focusedBorder:
            OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(
                12,
              ),
              borderSide:
              const BorderSide(
                color:
                AppColors
                    .primaryGreen,
                width: 1.5,
              ),
            ),
          ),
          style:
          AppTheme.body(
            size: 13,
            color:
            AppColors.textDark,
          ),
        ),
      ],
    );
  }

  // ================================================================
  // SUMMARY ROW
  // ================================================================

  Widget _summaryRow(
      String label,
      String value, {
        Color? valueColor,
        bool bold = false,
      }) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
              AppTheme.body(
                size: 11,
              ),
            ),
          ),
          Text(
            value,
            style:
            AppTheme.body(
              size: 11,
              color:
              valueColor ??
                  AppColors.textDark,
              weight: bold
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
              AppTheme.body(size: 11),
            ),
          ),
          Text(
            value,
            style:
            AppTheme.heading(size: 11),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // BOTTOM BAR
  // ================================================================

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding:
        const EdgeInsets.fromLTRB(
          16,
          10,
          16,
          12,
        ),
        decoration:
        const BoxDecoration(
          color:
          Colors.white,
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              offset:
              Offset(0, -3),
              color:
              Color(0x18000000),
            ),
          ],
        ),
        child:
        Row(
          children: [
            Expanded(
              child:
              OutlinedButton(
                onPressed:
                _saving
                    ? null
                    : () =>
                    Navigator.of(
                      context,
                    ).pop(),
                style:
                OutlinedButton.styleFrom(
                  foregroundColor:
                  AppColors
                      .darkGreen,
                  side:
                  const BorderSide(
                    color:
                    AppColors.divider,
                  ),
                  minimumSize:
                  const Size
                      .fromHeight(
                    52,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius
                        .circular(
                      14,
                    ),
                  ),
                ),
                child:
                const Text(
                  'Back',
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              flex: 2,
              child:
              ElevatedButton(
                onPressed:
                _saving
                    ? null
                    : _completeCheckout,
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors
                      .primaryGreen,
                  foregroundColor:
                  Colors.white,
                  minimumSize:
                  const Size
                      .fromHeight(
                    52,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius
                        .circular(
                      14,
                    ),
                  ),
                ),
                child:
                _saving
                    ? const SizedBox(
                  width: 21,
                  height: 21,
                  child:
                  CircularProgressIndicator(
                    color:
                    Colors.white,
                    strokeWidth:
                    2,
                  ),
                )
                    : const Text(
                  'Complete Checkout',
                  style:
                  TextStyle(
                    fontWeight:
                    FontWeight
                        .w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}