import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/expense_categories.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 5 — Delivery Options (the branch).
///
/// Built as four independent sub-tasks per the plan, not one mega-form.
/// All four branches' creation forms are wired up:
///  - A: Deliver Now
///  - B: Booking / Holding
///  - C: Wait for Delivery
///  - D: Transfer to Palai
///
/// Each branch's own "Complete Delivery" follow-up action (B and C only)
/// is out of scope for this phase per the plan's Pair 7 note — this step
/// only ever creates the sale in its initial state (Booked /
/// WaitForDelivery), never completes it.
///
/// LIVE CALCULATIONS: every input writes into the [SaleDraft] on each
/// keystroke (see the `_sync*` methods). The summary cards read the same
/// draft getters that the save step uses, so what the person sees while
/// typing is exactly what gets saved — there is no second copy of the
/// maths on this screen.
///
/// Exposes [validate] via its State (same pattern as earlier steps) so
/// the wizard's Save action can block until the selected branch's
/// required fields are filled in.
class Step5DeliveryOptions extends StatefulWidget {
  final SaleDraft draft;

  const Step5DeliveryOptions({
    super.key,
    required this.draft,
  });

  @override
  State<Step5DeliveryOptions> createState() =>
      Step5DeliveryOptionsState();
}

class Step5DeliveryOptionsState extends State<Step5DeliveryOptions> {
  final GlobalKey<FormState> _deliverNowFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _bookingFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _waitForDeliveryFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _palaiFormKey = GlobalKey<FormState>();

  late final TextEditingController _transportCostController;
  late final TextEditingController _amountReceivedController;

  late final TextEditingController _bookingAmountController;
  late final TextEditingController _holdingDaysController;
  late final TextEditingController _holdingChargePerDayController;
  late final TextEditingController _bookingTransportCostController;

  late final TextEditingController _bookingAdvanceController;
  late final TextEditingController _waitForDeliveryTransportCostController;

  late final TextEditingController _palaiPackageController;
  late final TextEditingController _monthlyChargeController;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _trimZero(double value) {
    return value == 0
        ? ''
        : value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _transportCostController = TextEditingController(
      text: _trimZero(draft.transportCost),
    );
    _amountReceivedController = TextEditingController(
      text: _trimZero(draft.amountReceived),
    );

    _bookingAmountController = TextEditingController(
      text: _trimZero(draft.bookingAmount),
    );
    _holdingDaysController = TextEditingController(
      text: draft.holdingDays == 0 ? '' : draft.holdingDays.toString(),
    );
    _holdingChargePerDayController = TextEditingController(
      text: _trimZero(draft.holdingChargePerDay),
    );
    _bookingTransportCostController = TextEditingController(
      text: _trimZero(draft.bookingTransportCost),
    );

    _bookingAdvanceController = TextEditingController(
      text: _trimZero(draft.bookingAdvanceAmount),
    );
    _waitForDeliveryTransportCostController = TextEditingController(
      text: _trimZero(draft.waitForDeliveryTransportCost),
    );

    _palaiPackageController = TextEditingController(
      text: draft.palaiPackage,
    );
    _monthlyChargeController = TextEditingController(
      text: _trimZero(draft.monthlyPalaiCharge),
    );

    draft.transferDate ??= DateTime.now();
  }

  @override
  void dispose() {
    _transportCostController.dispose();
    _amountReceivedController.dispose();
    _bookingAmountController.dispose();
    _holdingDaysController.dispose();
    _holdingChargePerDayController.dispose();
    _bookingTransportCostController.dispose();
    _bookingAdvanceController.dispose();
    _waitForDeliveryTransportCostController.dispose();
    _palaiPackageController.dispose();
    _monthlyChargeController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // LIVE SYNC — controllers -> draft
  // ===========================================================================
  //
  // The summary cards below read `draft.*` getters. The draft therefore
  // has to be updated as the person types, not only when Save is pressed —
  // otherwise every "live" figure stays frozen at its old value.

  double _money(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  void _syncDeliverNow() {
    final draft = widget.draft;

    draft.transportCost = _money(_transportCostController);
    draft.amountReceived = _money(_amountReceivedController);
  }

  void _syncBooking() {
    final draft = widget.draft;

    draft.bookingAmount = _money(_bookingAmountController);
    draft.holdingDays =
        int.tryParse(_holdingDaysController.text.trim()) ?? 0;
    draft.holdingChargePerDay = _money(_holdingChargePerDayController);
    draft.bookingTransportCost = _money(_bookingTransportCostController);
  }

  void _syncWaitForDelivery() {
    final draft = widget.draft;

    draft.bookingAdvanceAmount = _money(_bookingAdvanceController);
    draft.waitForDeliveryTransportCost =
        _money(_waitForDeliveryTransportCostController);
  }

  void _syncPalai() {
    final draft = widget.draft;

    draft.palaiPackage = _palaiPackageController.text.trim();
    draft.monthlyPalaiCharge = _money(_monthlyChargeController);
  }

  // ===========================================================================
  // VALIDATE (called by the wizard's Save button)
  // ===========================================================================

  bool validate() {
    final draft = widget.draft;

    if (draft.deliveryType.isEmpty) {
      wizardSnack(
        context,
        'Choose a delivery option to continue.',
        error: true,
      );
      return false;
    }

    if (draft.isDeliverNow) {
      final valid = _deliverNowFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      _syncDeliverNow();

      return true;
    }

    if (draft.isBooking) {
      final valid = _bookingFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      _syncBooking();
      draft.expectedDeliveryDate ??= DateTime.now();

      return true;
    }

    if (draft.isWaitForDelivery) {
      final valid =
          _waitForDeliveryFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      _syncWaitForDelivery();

      return true;
    }

    if (draft.isPalaiTransfer) {
      final valid = _palaiFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      _syncPalai();

      return true;
    }

    return false;
  }

  // ===========================================================================
  // BRANCH SELECTION
  // ===========================================================================

  void _selectBranch(String type) {
    setState(() {
      widget.draft.deliveryType = type;
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'How is this goat leaving the farm?',
          style: AppTheme.heading(size: 14, color: AppColors.textDark),
        ),
        const SizedBox(height: 12),

        _BranchCard(
          title: 'Deliver Now',
          subtitle: 'Handed over today, paid on the spot',
          icon: Icons.local_shipping_outlined,
          selected: draft.deliveryType == Sale.deliveryTypeDeliverNow,
          onTap: () => _selectBranch(Sale.deliveryTypeDeliverNow),
        ),
        const SizedBox(height: 10),
        _BranchCard(
          title: 'Booking / Holding',
          subtitle: 'Held here after payment, picked up later',
          icon: Icons.bookmark_outline_rounded,
          selected: draft.deliveryType == Sale.deliveryTypeBooking,
          onTap: () => _selectBranch(Sale.deliveryTypeBooking),
        ),
        const SizedBox(height: 10),
        _BranchCard(
          title: 'Wait for Delivery',
          subtitle: 'Booked now at today\'s rate, weighed at pickup',
          icon: Icons.schedule_outlined,
          selected: draft.deliveryType == Sale.deliveryTypeWaitForDelivery,
          onTap: () => _selectBranch(Sale.deliveryTypeWaitForDelivery),
        ),
        const SizedBox(height: 10),
        _BranchCard(
          title: 'Transfer to Palai',
          subtitle: 'Customer keeps boarding this goat here',
          icon: Icons.holiday_village_outlined,
          selected: draft.deliveryType == Sale.deliveryTypePalai,
          onTap: () => _selectBranch(Sale.deliveryTypePalai),
        ),

        const SizedBox(height: 18),

        if (draft.isDeliverNow) _buildDeliverNowForm(draft),
        if (draft.isBooking) _buildBookingForm(draft),
        if (draft.isWaitForDelivery) _buildWaitForDeliveryForm(draft),
        if (draft.isPalaiTransfer) _buildPalaiTransferForm(draft),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAYMENT METHOD (shared by Deliver Now, Booking and Wait for Delivery)
  // ---------------------------------------------------------------------------
  //
  // How the money taken now is being paid. It is saved on the sale and
  // becomes the payment method of the Sold Goat Revenue entry for that
  // money, which is what keeps the Finance Cash / Online tracker right.
  // Only one branch's form is on screen at a time, so they all share
  // [SaleDraft.paymentMethod].

  Widget _paymentMethodPicker(SaleDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FinancePaymentMethods.all.map((method) {
            final selected = draft.paymentMethod == method;

            return ChoiceChip(
              label: Text(method),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  draft.paymentMethod = method;
                });
              },
              selectedColor: AppColors.primaryGreen.withOpacity(0.15),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.darkGreen : AppColors.textDark,
              ),
              side: BorderSide(
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'How the amount above is being paid now.',
          style: AppTheme.body(
            size: 10,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BRANCH A — DELIVER NOW
  // ---------------------------------------------------------------------------

  Widget _buildDeliverNowForm(SaleDraft draft) {
    return Form(
      key: _deliverNowFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Deliver Now',
            icon: Icons.local_shipping_outlined,
            children: [
              wizardField(
                controller: _transportCostController,
                label: 'Transportation Charge',
                hint: '0.00',
                icon: Icons.directions_car_outlined,
                suffix: 'Added to bill',
                optional: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncDeliverNow),
                validator: (_) => null,
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _amountReceivedController,
                label: 'Amount Received',
                optional: true,
                helper: 'Leave blank if nothing was received yet (status: Pending)',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncDeliverNow),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  // Blank counts as 0 (the draft reads it that way).
                  if (text.isEmpty) return null;

                  final number = double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              _paymentMethodPicker(draft),
            ],
          ),

          const SizedBox(height: 12),

          _buildDeliverNowSummary(draft),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case Sale.paymentStatusPaid:
        return AppColors.success;
      case Sale.paymentStatusPartial:
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }

  Widget _buildDeliverNowSummary(SaleDraft draft) {
    final status = draft.paymentStatusDeliverNow;
    final extra = draft.extraReceivedDeliverNow;

    return _buildSummaryCard(
      [
        _SummaryRow(
          'Goat Sale',
          _currency(draft.totalSaleAmount),
        ),
        if (draft.transportCost > 0)
          _SummaryRow(
            'Transportation',
            _currency(draft.transportCost),
          ),
        _SummaryRow(
          'Customer Total',
          _currency(draft.customerTotalDeliverNow),
        ),
        _SummaryRow(
          'Amount Received',
          _currency(draft.amountReceived),
        ),
        _SummaryRow(
          'Remaining Balance',
          _currency(draft.remainingBalanceDeliverNow),
          emphasized: true,
        ),
      ],
      title: 'Payment Summary',
      statusLabel: status,
      statusColor: _statusColor(status),
      notes: [
        if (extra > 0)
          _SummaryNote(
            'You entered ${_currency(extra)} more than the customer '
                'total. Check the amount received before saving.',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),
        if (draft.transportCost > 0)
          _SummaryNote(
            'Transportation charge (${_currency(draft.transportCost)}) '
                'is added to the customer\'s bill. It is not recorded as '
                'a farm expense.',
            color: AppColors.textGrey,
            icon: Icons.info_outline_rounded,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BRANCH B — BOOKING / HOLDING
  // ---------------------------------------------------------------------------

  Widget _buildBookingForm(SaleDraft draft) {
    return Form(
      key: _bookingFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Booking / Holding',
            icon: Icons.bookmark_outline_rounded,
            children: [
              wizardField(
                controller: _bookingAmountController,
                label: 'Booking Amount',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncBooking),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              _paymentMethodPicker(draft),
              const SizedBox(height: 14),
              WizardDateField(
                label: 'Expected Delivery Date',
                date: draft.expectedDeliveryDate ?? DateTime.now(),
                onTap: () async {
                  final picked = await showWizardDatePicker(
                    context: context,
                    initialDate: draft.expectedDeliveryDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(
                      const Duration(days: 365),
                    ),
                    helpText: 'Expected delivery date',
                  );

                  if (picked == null) return;

                  setState(() {
                    draft.expectedDeliveryDate = picked;
                  });
                },
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _holdingDaysController,
                label: 'Holding Days',
                optional: true,
                hint: '0 if none',
                icon: Icons.today_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(_syncBooking),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  // Blank counts as 0 (the draft reads it that way).
                  if (text.isEmpty) return null;

                  final number = int.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter valid days';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _holdingChargePerDayController,
                label: 'Holding Charge / Day',
                optional: true,
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                suffix: '/ day',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncBooking),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  // Blank counts as 0 (the draft reads it that way).
                  if (text.isEmpty) return null;

                  final number = double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid charge';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _bookingTransportCostController,
                label: 'Transportation Charge',
                hint: '0.00',
                icon: Icons.directions_car_outlined,
                suffix: 'Added to bill',
                optional: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncBooking),
                validator: (_) => null,
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSummaryCard(
            [
              _SummaryRow(
                'Goat Sale',
                _currency(draft.totalSaleAmount),
              ),
              _SummaryRow(
                'Holding Charges '
                    '(${draft.holdingDays} '
                    'day${draft.holdingDays == 1 ? '' : 's'} × '
                    '${_currency(draft.holdingChargePerDay)})',
                _currency(draft.totalHoldingCharges),
              ),
              if (draft.bookingTransportCost > 0)
                _SummaryRow(
                  'Transportation',
                  _currency(draft.bookingTransportCost),
                ),
              _SummaryRow(
                'Total Payable',
                _currency(draft.totalPayableBooking),
              ),
              _SummaryRow(
                'Booking Amount Paid',
                _currency(draft.bookingAmount),
              ),
              _SummaryRow(
                'Remaining Balance',
                _currency(draft.remainingBalanceBooking),
                emphasized: true,
              ),
            ],
            title: 'Booking Summary',
            notes: [
              if (draft.bookingAmount > draft.totalPayableBooking)
                _SummaryNote(
                  'The booking amount is more than the total payable '
                      '(${_currency(draft.totalPayableBooking)}). '
                      'Check the amount before saving.',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              _SummaryNote(
                'This is an estimate using the holding days entered '
                    'above. The final amount is recalculated from the '
                    'actual holding days when delivery is completed.',
                color: AppColors.textGrey,
                icon: Icons.info_outline_rounded,
              ),
              if (draft.bookingTransportCost > 0)
                _SummaryNote(
                  'Transportation charge '
                      '(${_currency(draft.bookingTransportCost)}) is '
                      'added to the customer\'s bill. It is not recorded '
                      'as a farm expense.',
                  color: AppColors.textGrey,
                  icon: Icons.info_outline_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      List<_SummaryRow> rows, {
        String? title,
        String? statusLabel,
        Color? statusColor,
        List<_SummaryNote> notes = const [],
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || statusLabel != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? '',
                    style: AppTheme.heading(
                      size: 13,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                if (statusLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (statusColor ?? AppColors.textGrey)
                          .withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor ?? AppColors.textGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 10),
          ],
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Expanded label: a long label such as
                // "Holding Charges (5 days × ₹150.00)" wraps instead of
                // overflowing the row.
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: rows[i].emphasized
                        ? AppTheme.heading(
                      size: 12,
                      color: AppColors.textDark,
                    )
                        : AppTheme.body(
                      size: 11,
                      color: AppColors.textGrey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  rows[i].value,
                  textAlign: TextAlign.right,
                  style: rows[i].emphasized
                      ? AppTheme.heading(
                    size: 14,
                    color: AppColors.textDark,
                  )
                      : AppTheme.body(
                    size: 12,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          for (final note in notes) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(note.icon, size: 14, color: note.color),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.text,
                    style: AppTheme.body(
                      size: 10,
                      color: note.color,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BRANCH C — WAIT FOR DELIVERY
  // ---------------------------------------------------------------------------

  Widget _buildWaitForDeliveryForm(SaleDraft draft) {
    return Form(
      key: _waitForDeliveryFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Wait for Delivery',
            icon: Icons.schedule_outlined,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_clock_outlined,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Price/kg is locked in at ${_currency(draft.bookingPricePerKg)} '
                            'now. When this delivery is completed later, use '
                            'this same rate with the new pickup weight — '
                            'never the market rate on that day.',
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _bookingAdvanceController,
                label: 'Booking / Advance Amount',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncWaitForDelivery),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              _paymentMethodPicker(draft),
              const SizedBox(height: 14),
              wizardField(
                controller: _waitForDeliveryTransportCostController,
                label: 'Transportation Charge',
                hint: '0.00',
                icon: Icons.directions_car_outlined,
                suffix: 'Added to bill',
                optional: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncWaitForDelivery),
                validator: (_) => null,
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSummaryCard(
            [
              _SummaryRow(
                'Booking Weight',
                '${SaleDraft.formatWeight(draft.bookingWeightTotal)} kg',
              ),
              _SummaryRow(
                'Booking Price/Kg',
                _currency(draft.bookingPricePerKg),
              ),
              _SummaryRow(
                'Goat Sale (Estimated)',
                _currency(draft.totalSaleAmount),
              ),
              if (draft.waitForDeliveryTransportCost > 0)
                _SummaryRow(
                  'Transportation',
                  _currency(draft.waitForDeliveryTransportCost),
                ),
              _SummaryRow(
                'Estimated Customer Total',
                _currency(draft.customerTotalWaitForDelivery),
              ),
              _SummaryRow(
                'Advance Paid',
                _currency(draft.bookingAdvanceAmount),
              ),
              _SummaryRow(
                'Estimated Remaining',
                _currency(draft.remainingAdvanceBalanceWaitForDelivery),
                emphasized: true,
              ),
            ],
            title: 'Booking Summary',
            notes: [
              if (draft.bookingAdvanceAmount >
                  draft.customerTotalWaitForDelivery)
                _SummaryNote(
                  'The advance is more than the estimated customer total '
                      '(${_currency(draft.customerTotalWaitForDelivery)}). '
                      'Check the amount before saving.',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              _SummaryNote(
                'Estimated at today\'s weight. At pickup the goat is '
                    'weighed again and the final amount is: pickup weight '
                    '× ${_currency(draft.bookingPricePerKg)}/kg + '
                    'transportation − advance.',
                color: AppColors.textGrey,
                icon: Icons.info_outline_rounded,
              ),
              if (draft.waitForDeliveryTransportCost > 0)
                _SummaryNote(
                  'Transportation charge '
                      '(${_currency(draft.waitForDeliveryTransportCost)}) '
                      'is added to the customer\'s bill. It is not '
                      'recorded as a farm expense.',
                  color: AppColors.textGrey,
                  icon: Icons.info_outline_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BRANCH D — TRANSFER TO PALAI
  // ---------------------------------------------------------------------------

  Widget _buildPalaiTransferForm(SaleDraft draft) {
    return Form(
      key: _palaiFormKey,
      child: WizardSectionCard(
        title: 'Transfer to Palai',
        icon: Icons.holiday_village_outlined,
        children: [
          Text(
            'The ongoing monthly billing and health tracking for this '
                'goat is handled by the Customer Palai module from here on — '
                'this just captures the handoff.',
            style: AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
          const SizedBox(height: 14),

          WizardDateField(
            label: 'Transfer Date',
            date: draft.transferDate ?? DateTime.now(),
            onTap: () async {
              final picked = await showWizardDatePicker(
                context: context,
                initialDate: draft.transferDate ?? DateTime.now(),
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
                helpText: 'Transfer date',
              );

              if (picked == null) return;

              setState(() {
                draft.transferDate = picked;
              });
            },
          ),

          const SizedBox(height: 14),

          wizardField(
            controller: _palaiPackageController,
            label: 'Palai Package',
            hint: 'e.g. Standard Monthly Care',
            icon: Icons.card_giftcard_outlined,
            onChanged: (_) => _syncPalai(),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Enter the Palai package';
              return null;
            },
          ),

          const SizedBox(height: 14),

          wizardField(
            controller: _monthlyChargeController,
            label: 'Monthly Palai Charge',
            hint: '0.00',
            icon: Icons.currency_rupee_rounded,
            suffix: '/ month',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d*\.?\d{0,2}'),
              ),
            ],
            onChanged: (_) => _syncPalai(),
            validator: (value) {
              final number = double.tryParse(value?.trim() ?? '');

              if (number == null || number <= 0) {
                return 'Enter a valid monthly charge';
              }

              return null;
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUMMARY ROW
// ============================================================================

class _SummaryRow {
  final String label;
  final String value;
  final bool emphasized;

  const _SummaryRow(this.label, this.value, {this.emphasized = false});
}

/// Small explanatory / warning line under a summary card.
class _SummaryNote {
  final String text;
  final Color color;
  final IconData icon;

  const _SummaryNote(
      this.text, {
        required this.color,
        required this.icon,
      });
}

// ============================================================================
// BRANCH CARD
// ============================================================================

class _BranchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _BranchCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (selected
                        ? AppColors.primaryGreen
                        : AppColors.textGrey)
                        .withOpacity(0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? AppColors.primaryGreen
                        : AppColors.textGrey,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.heading(
                          size: 13,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? AppColors.primaryGreen
                      : AppColors.divider,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}