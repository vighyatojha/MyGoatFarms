import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 2 — where the goats are coming from (when the lot has stock in
/// both places) and how many, plus the total selling weight.
///
/// A lot still at the supplier can only be sold Deliver Now — Booking and
/// Wait for Delivery need goats that have actually arrived, so those
/// options are for farm stock only and are offered on the next step
/// (delivery options), not here.
class StepSourceAndQuantity extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final SaleDraft draft;
  final TradingPurchase lot;

  const StepSourceAndQuantity({
    super.key,
    required this.formKey,
    required this.draft,
    required this.lot,
  });

  @override
  State<StepSourceAndQuantity> createState() => _StepSourceAndQuantityState();
}

class _StepSourceAndQuantityState extends State<StepSourceAndQuantity> {
  late final TextEditingController _quantityController;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _quantityController = TextEditingController(
      text: draft.lotQuantity == 0 ? '' : draft.lotQuantity.toString(),
    );

    _weightController = TextEditingController(
      text: draft.lotSellingWeight == 0
          ? ''
          : SaleDraft.formatWeight(draft.lotSellingWeight),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  bool get _fromSupplier => widget.draft.sourceLocation == Sale.sourceSupplier;

  int get _available {
    final lot = widget.lot;
    return _fromSupplier ? lot.supplierQty : lot.farmAvailableQty;
  }

  void _setSource(String source) {
    setState(() {
      widget.draft.sourceLocation = source;
      // Switching source changes the max — re-check what's already typed.
      widget.formKey.currentState?.validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final lot = widget.lot;

    final bothLocations = lot.supplierQty > 0 && lot.farmAvailableQty > 0;

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardSectionCard(
            title: lot.lotId,
            icon: Icons.inventory_2_outlined,
            children: [
              if (bothLocations) ...[
                Text('Sell From', style: AppTheme.body(size: 11)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SourceOption(
                        title: 'At Supplier',
                        subtitle: '${lot.supplierQty} available',
                        icon: Icons.local_shipping_outlined,
                        selected: _fromSupplier,
                        onTap: () => _setSource(Sale.sourceSupplier),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SourceOption(
                        title: 'At Farm',
                        subtitle: '${lot.farmAvailableQty} available',
                        icon: Icons.home_work_outlined,
                        selected: !_fromSupplier,
                        onTap: () => _setSource(Sale.sourceFarm),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ] else
                WizardComputedRow(
                  label: 'Selling from',
                  value: _fromSupplier ? 'At Supplier' : 'At Farm',
                ),

              if (_fromSupplier)
                const WizardNote(
                  'Goats still at the supplier can only be sold Deliver '
                      'Now — Booking and Wait for Delivery need goats '
                      'that have arrived at the farm.',
                ),

              const SizedBox(height: 14),

              wizardField(
                controller: _quantityController,
                label: 'Number of Goats',
                hint: 'Up to $_available',
                icon: GoatIcons.paw,
                suffix: 'goats',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (v) {
                  draft.lotQuantity = int.tryParse(v.trim()) ?? 0;
                  setState(() {});
                },
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');

                  if (n == null || n <= 0) return 'Enter a valid count';
                  if (n > _available) {
                    return 'Only $_available available';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _weightController,
                label: 'Total Selling Weight',
                hint: '0.00',
                icon: Icons.scale_outlined,
                suffix: 'KG',
                keyboardType: wizardDecimalKeyboard,
                inputFormatters: wizardDecimalFormatters(),
                onChanged: (v) {
                  draft.lotSellingWeight = double.tryParse(v.trim()) ?? 0;
                  setState(() {});
                },
                validator: (value) {
                  final n = double.tryParse(value?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid weight';
                  return null;
                },
              ),
            ],
          ),

          if (draft.lotQuantity > 0) ...[
            const SizedBox(height: 14),
            WizardStatTile(
              icon: Icons.currency_rupee_rounded,
              label: 'Lot cost for these goats',
              value: wizardCurrency(
                PurchaseCosting.round2(lot.lotCostPerGoat * draft.lotQuantity),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SourceOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.darkGreen : AppColors.textGrey),
              const SizedBox(height: 6),
              Text(title, style: AppTheme.heading(size: 13, color: selected ? AppColors.darkGreen : AppColors.textDark)),
              Text(subtitle, style: AppTheme.body(size: 11)),
            ],
          ),
        ),
      ),
    );
  }
}