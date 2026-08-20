import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';

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

      setState(() {
        _customer = customer;
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
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Checkout Completed',
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
            CrossAxisAlignment.start,
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

              const SizedBox(height: 16),

              _dialogRow(
                'Bill Number',
                billNumber,
              ),

              _dialogRow(
                'New Charges',
                _rupees(
                  billResult.newCharges,
                ),
              ),

              _dialogRow(
                'Previous Pending',
                _rupees(
                  billResult.previousPending,
                ),
              ),

              _dialogRow(
                'Advance Applied',
                _rupees(
                  billResult.advanceApplied,
                ),
              ),

              _dialogRow(
                'Total Due',
                _rupees(
                  billResult.totalDue,
                ),
              ),

              _dialogRow(
                'Paid',
                _rupees(
                  billResult.paid,
                ),
              ),

              _dialogRow(
                'Pending After',
                _rupees(
                  billResult.pendingAfter,
                ),
              ),

              if (billResult.advanceAfter > 0)
                _dialogRow(
                  'Advance After',
                  _rupees(
                    billResult.advanceAfter,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(),
              child: const Text(
                'Done',
              ),
            ),
          ],
        );
      },
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