import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import 'purchase_wizard_widgets.dart';

/// Live "what did these goats really cost me?" card.
///
/// Reads everything from [PurchaseCosting], so it is always identical to
/// what is saved. It shows the cost AFTER transportation, mortality and
/// arrival weight:
///
///   Purchase Amount + Expenses = Grand Total
///   Grand Total / weight after arrival  = Effective cost per KG
///   Grand Total / goats that survived   = Cost per surviving goat
///
/// Until an arrival weight is entered, the "after arrival" figures are not
/// shown at all (rather than showing misleading zeros).
class PurchaseCostCard extends StatelessWidget {
  final PurchaseCosting costing;

  const PurchaseCostCard({
    super.key,
    required this.costing,
  });

  String _kg(double value) => '${PurchaseCosting.formatNumber(value)} kg';

  @override
  Widget build(BuildContext context) {
    final c = costing;

    return WizardSectionCard(
      title: 'Purchase Cost After Arrival',
      icon: Icons.calculate_outlined,
      children: [
        // -------------------------------------------------------------------
        // COST BUILD-UP
        // -------------------------------------------------------------------

        WizardComputedRow(
          label: 'Purchase Amount',
          value: wizardCurrency(c.purchaseAmount),
        ),
        WizardComputedRow(
          label: 'Transport & Other Expenses',
          value: wizardCurrency(c.totalExpenses),
        ),
        const Divider(height: 18, color: AppColors.divider),
        WizardComputedRow(
          label: 'Grand Total',
          value: wizardCurrency(c.grandTotal),
          emphasize: true,
        ),

        const SizedBox(height: 10),

        // -------------------------------------------------------------------
        // AFTER ARRIVAL
        // -------------------------------------------------------------------

        if (!c.hasArrival)
          const WizardNote(
            'Enter the weight after arrival to see the effective '
                'cost per KG and per goat.',
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: WizardStatTile(
                  icon: Icons.scale_outlined,
                  label: 'Weight loss',
                  value: '${_kg(c.weightLoss)} '
                      '(${PurchaseCosting.formatNumber(c.weightLossPercent)}%)',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WizardStatTile(
                  icon: Icons.pets_outlined,
                  label: 'Goats arrived',
                  value: '${c.survivingGoats} of ${c.totalGoats}',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _HighlightTile(
            title: 'Effective Cost per KG',
            subtitle:
            '${wizardCurrency(c.grandTotal)} ÷ ${_kg(c.weightAfterArrival)}',
            value: wizardCurrency(c.effectiveCostPerKg),
            footnote: c.costIncreasePerKg > 0
                ? '+${wizardCurrency(c.costIncreasePerKg)} more than the '
                '${wizardCurrency(c.pricePerKg)} / kg you paid'
                : null,
          ),

          const SizedBox(height: 10),

          _HighlightTile(
            title: 'Cost per Surviving Goat',
            subtitle:
            '${wizardCurrency(c.grandTotal)} ÷ ${c.survivingGoats} '
                'goat${c.survivingGoats == 1 ? '' : 's'}',
            value: wizardCurrency(c.costPerSurvivingGoat),
          ),

          if (c.safeMortality > 0) ...[
            const SizedBox(height: 10),
            WizardNote(
              '${c.safeMortality} goat${c.safeMortality == 1 ? '' : 's'} '
                  'lost in transit (about ${wizardCurrency(c.mortalityLoss)} '
                  'of the purchase amount). That cost is already inside the '
                  'Grand Total, which is why cost per goat is higher.',
              tone: WizardNoteTone.warning,
            ),
          ],
        ],
      ],
    );
  }
}

class _HighlightTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String? footnote;

  const _HighlightTile({
    required this.title,
    required this.subtitle,
    required this.value,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.heading(
                        size: 12,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTheme.heading(
                      size: 18,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Text(
              footnote!,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}