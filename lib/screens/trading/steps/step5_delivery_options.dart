import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
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

  late final TextEditingController _bookingAdvanceController;

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

    _bookingAdvanceController = TextEditingController(
      text: _trimZero(draft.bookingAdvanceAmount),
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
    _bookingAdvanceController.dispose();
    _palaiPackageController.dispose();
    _monthlyChargeController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // VALIDATE (called by the wizard's Save button)
  // ===========================================================================

  bool validate() {
    final draft = widget.draft;

    if (draft.deliveryType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a delivery option to continue.'),
        ),
      );
      return false;
    }

    if (draft.isDeliverNow) {
      final valid = _deliverNowFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      draft.transportCost =
          double.tryParse(_transportCostController.text.trim()) ?? 0;
      draft.amountReceived =
          double.tryParse(_amountReceivedController.text.trim()) ?? 0;

      return true;
    }

    if (draft.isBooking) {
      final valid = _bookingFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      draft.bookingAmount =
          double.tryParse(_bookingAmountController.text.trim()) ?? 0;
      draft.holdingDays =
          int.tryParse(_holdingDaysController.text.trim()) ?? 0;
      draft.holdingChargePerDay = double.tryParse(
        _holdingChargePerDayController.text.trim(),
      ) ??
          0;
      draft.expectedDeliveryDate ??= DateTime.now();

      return true;
    }

    if (draft.isWaitForDelivery) {
      final valid =
          _waitForDeliveryFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      draft.bookingAdvanceAmount =
          double.tryParse(_bookingAdvanceController.text.trim()) ?? 0;

      return true;
    }

    if (draft.isPalaiTransfer) {
      final valid = _palaiFormKey.currentState?.validate() ?? false;
      if (!valid) return false;

      draft.palaiPackage = _palaiPackageController.text.trim();
      draft.monthlyPalaiCharge =
          double.tryParse(_monthlyChargeController.text.trim()) ?? 0;

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
                label: 'Transport Cost',
                hint: '0.00',
                icon: Icons.directions_car_outlined,
                suffix: 'Optional',
                optional: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(() {}),
                validator: (_) => null,
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _amountReceivedController,
                label: 'Amount Received',
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
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildBalanceCard(
            draft.remainingBalanceDeliverNow,
            draft.paymentStatusDeliverNow,
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(double remaining, String status) {
    Color statusColor;

    switch (status) {
      case Sale.paymentStatusPaid:
        statusColor = AppColors.success;
        break;
      case Sale.paymentStatusPartial:
        statusColor = AppColors.warning;
        break;
      default:
        statusColor = AppColors.error;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remaining Balance',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _currency(remaining),
                  style: AppTheme.heading(
                    size: 15,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              WizardDateField(
                label: 'Expected Delivery Date',
                date: draft.expectedDeliveryDate ?? DateTime.now(),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: draft.expectedDeliveryDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(
                      const Duration(days: 365),
                    ),
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
                hint: 'e.g. 5',
                icon: Icons.today_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');

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
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid charge';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSummaryCard([
            _SummaryRow(
              'Total Holding Charges',
              _currency(draft.totalHoldingCharges),
            ),
            _SummaryRow(
              'Remaining Balance',
              _currency(draft.remainingBalanceBooking),
              emphasized: true,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(List<_SummaryRow> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rows[i].label,
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
                Text(
                  rows[i].value,
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
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSummaryCard([
            _SummaryRow(
              'Booking Weight',
              '${_trimZero(draft.bookingWeightTotal)} kg',
            ),
            _SummaryRow(
              'Booking Price/Kg',
              _currency(draft.bookingPricePerKg),
            ),
            _SummaryRow(
              'Remaining Balance',
              _currency(draft.remainingAdvanceBalanceWaitForDelivery),
              emphasized: true,
            ),
          ]),
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
              final picked = await showDatePicker(
                context: context,
                initialDate: draft.transferDate ?? DateTime.now(),
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
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