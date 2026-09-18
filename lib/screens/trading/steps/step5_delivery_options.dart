import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app_theme.dart';
import '../../../../models/sale_draft.dart';
import '../../../../models/sale_model.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 5 — Delivery Options (the branch).
///
/// Built as four independent sub-tasks per the plan, not one mega-form.
/// Only Branch A (Deliver Now) and Branch D (Transfer to Palai) are
/// wired up so far — they're the two simplest, single-shot branches and
/// come first in the plan's build order. Branch B (Booking) and
/// Branch C (Wait for Delivery) show as "coming soon" and can't be
/// selected yet.
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
  final GlobalKey<FormState> _palaiFormKey = GlobalKey<FormState>();

  late final TextEditingController _transportCostController;
  late final TextEditingController _amountReceivedController;

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
          subtitle: 'Coming soon',
          icon: Icons.bookmark_outline_rounded,
          enabled: false,
        ),
        const SizedBox(height: 10),
        _BranchCard(
          title: 'Wait for Delivery',
          subtitle: 'Coming soon',
          icon: Icons.schedule_outlined,
          enabled: false,
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