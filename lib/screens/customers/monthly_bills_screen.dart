import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/monthly_bill_model.dart';
import '../../services/monthly_bill_pdf_service.dart';
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

  // ========================================================================
  // LOAD BILLS
  // ========================================================================

  Future<void> _loadBills() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final snapshot = await _billsCollection
          .where(
        'customerId',
        isEqualTo: widget.customerId,
      )
          .orderBy(
        'billingMonth',
        descending: true,
      )
          .get();

      final bills = snapshot.docs
          .map(
            (doc) => MonthlyBill.fromDoc(doc),
      )
          .toList();

      if (!mounted) return;

      setState(() {
        _bills = bills;
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
  // This used to build and write the bill inline, right here. That logic
  // now lives in MonthlyBillGenerateScreen + MonthlyBillingService (which
  // covers the same duplicate-protection and outstanding-balance update,
  // transactionally). We just compute the same prefill values — current
  // goat count and the customer's package price — and hand off to it.

  Future<void> _createMonthlyBill() async {
    if (_creatingBill) return;

    try {
      setState(() {
        _creatingBill = true;
      });

      final customerSnapshot = await _customerReference.get();

      if (!customerSnapshot.exists) {
        throw StateError('Customer could not be found.');
      }

      final customerData = customerSnapshot.data() ?? {};

      final suggestedMonthlyAmount = _number(customerData['price']);

      final goatsSnapshot = await _db
          .collection('farms')
          .doc(widget.farmId)
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .collection('goats')
          .get();

      final goatCount = goatsSnapshot.docs
          .where((doc) => doc.data()['isCheckedOut'] != true)
          .length;

      if (!mounted) return;

      final createdBill = await Navigator.of(context).push<MonthlyBill>(
        MaterialPageRoute(
          builder: (_) => MonthlyBillGenerateScreen(
            farmId: widget.farmId,
            customerId: widget.customerId,
            customerName: widget.customerName,
            goatCount: goatCount,
            suggestedMonthlyAmount: suggestedMonthlyAmount,
          ),
        ),
      );

      if (createdBill != null) {
        await _loadBills();
      }
    } catch (e) {
      debugPrint('Create monthly bill error: $e');

      if (!mounted) return;

      _showError(
        e.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingBill = false;
        });
      }
    }
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

    await _loadBills();
  }

  // ========================================================================
  // VIEW PDF
  // ========================================================================

  Future<void> _viewBill(
      MonthlyBill bill,
      ) async {
    try {
      await _pdfService.preview(bill);
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to open bill PDF.\n$e',
      );
    }
  }

  // ========================================================================
  // DOWNLOAD / SAVE PDF
  // ========================================================================

  Future<void> _downloadBill(
      MonthlyBill bill,
      ) async {
    try {
      final path =
      await _pdfService.save(bill);

      if (!mounted) return;

      _showSuccess(
        'Bill saved successfully.\n$path',
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to save bill PDF.\n$e',
      );
    }
  }

  // ========================================================================
  // SHARE PDF
  // ========================================================================

  Future<void> _shareBill(
      MonthlyBill bill,
      ) async {
    try {
      await _pdfService.share(bill);
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to share bill PDF.\n$e',
      );
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

  Widget _buildBillCard(
      MonthlyBill bill,
      ) {
    final statusColor =
    _statusColor(bill.status);

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
            color: Colors.black.withOpacity(
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
                        bill.monthYear,
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
                  bill.status,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ----------------------------------------------------------
            // AMOUNT
            // ----------------------------------------------------------

            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color:
                AppColors.paleGreen,
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Bill',
                          style:
                          AppTheme.body(
                            size: 11,
                            color:
                            AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          _currency(
                            bill.currentBillAmount,
                          ),
                          style:
                          AppTheme.heading(
                            size: 17,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Remaining',
                        style:
                        AppTheme.body(
                          size: 11,
                          color:
                          AppColors.textGrey,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        _currency(
                          bill.remainingAmount,
                        ),
                        style:
                        AppTheme.heading(
                          size: 15,
                          color:
                          statusColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ----------------------------------------------------------
            // DETAILS
            // ----------------------------------------------------------

            Row(
              children: [
                Expanded(
                  child: _detail(
                    'Goats',
                    '${bill.goatCount}',
                  ),
                ),
                Expanded(
                  child: _detail(
                    'Previous',
                    _currency(
                      bill.previousOutstanding,
                    ),
                  ),
                ),
                Expanded(
                  child: _detail(
                    'Total Due',
                    _currency(
                      bill.totalDue,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            const Divider(
              height: 1,
            ),

            const SizedBox(height: 8),

            // ----------------------------------------------------------
            // PAYMENT TOGGLE
            // ----------------------------------------------------------

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

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _viewBill(bill);
                    },
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                    ),
                    label:
                    const Text('View Bill'),
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
                    onPressed: () {
                      _downloadBill(bill);
                    },
                    icon: const Icon(
                      Icons.download_outlined,
                      size: 18,
                    ),
                    label:
                    const Text('Download'),
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
                  onPressed: () {
                    _shareBill(bill);
                  },
                  icon: const Icon(
                    Icons.share_outlined,
                  ),
                  color:
                  AppColors.primaryGreen,
                ),
              ],
            ),
          ],
        ),
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
        color: color.withOpacity(
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
  // DETAIL
  // ========================================================================

  Widget _detail(
      String label,
      String value,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.body(
            size: 10,
            color: AppColors.textGrey,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          overflow:
          TextOverflow.ellipsis,
          style: AppTheme.body(
            size: 11,
            weight: FontWeight.w600,
          ),
        ),
      ],
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
            'Generate the first monthly bill '
                'for this customer.',
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
            const Text('Create Monthly Bill'),
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
          IconButton(
            tooltip:
            'Create Monthly Bill',
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
        onRefresh: _loadBills,
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
                          '${_bills.length} monthly bill${_bills.length == 1 ? '' : 's'}',
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