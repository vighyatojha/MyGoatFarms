import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/lot_sales_summary.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../widgets/fast_route.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../sale_receipt_screen.dart';
import 'lot_widgets.dart';

/// The two Lot Detail cards that come from a lot's sales:
///
/// * **Sales & Profit** — goats sold, sales weight, revenue, customer
///   pending and profit (PDF §16).
/// * **Lot history** — every sale from this lot, newest first, with Sale
///   ID, customer, goats, weight, price/kg and amount (PDF §15).
///
/// Everything is computed by [LotSalesSummary]; this widget only lays it
/// out. Completed sales open their receipt (where a balance can be
/// collected); open Booking / Wait-for-Delivery sales have no receipt yet.
class LotSalesCards extends StatelessWidget {
  final String farmId;
  final TradingPurchase lot;
  final List<Sale> sales;

  /// Total "Loss at lot cost" of goats that died at the farm (Step 20
  /// Record Death events). Informational only — it is never added to or
  /// subtracted from [LotSalesSummary.profit].
  final double farmDeathLoss;

  const LotSalesCards({
    super.key,
    required this.farmId,
    required this.lot,
    required this.sales,
    this.farmDeathLoss = 0,
  });

  @override
  Widget build(BuildContext context) {
    final summary = LotSalesSummary.from(lot, sales);

    return Column(
      children: [
        _financialCard(summary),
        const SizedBox(height: 14),
        _historyCard(context, summary),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // SALES & PROFIT
  // ---------------------------------------------------------------------

  Widget _financialCard(LotSalesSummary s) {
    final profit = s.profit;
    final profitColor = profit >= 0 ? AppColors.success : AppColors.error;

    return WizardSectionCard(
      title: 'Sales & Profit',
      icon: Icons.trending_up_rounded,
      children: [
        WizardComputedRow(label: 'Goats sold', value: '${s.goatsSold}'),
        WizardComputedRow(
          label: 'Sales weight',
          value: '${PurchaseCosting.formatNumber(s.salesWeight)} kg',
        ),
        if (s.salesWeight > 0)
          WizardComputedRow(
            label: 'Average price per kg',
            value: wizardCurrency(s.averagePricePerKg),
          ),
        WizardComputedRow(
          label: 'Sales revenue',
          value: wizardCurrency(s.revenue),
        ),
        WizardComputedRow(
          label: 'Customer pending',
          value: wizardCurrency(s.customerPending),
        ),
        if (s.openGoats > 0)
          WizardComputedRow(
            label: 'Booked / waiting (not yet delivered)',
            value: '${s.openGoats} goat${s.openGoats == 1 ? '' : 's'}',
          ),
        if (s.openGoats > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Sales revenue and customer pending count delivered sales '
                  'only. Booked / waiting goats are added once delivered.',
              style: AppTheme.body(size: 11),
            ),
          ),
        const Divider(height: 18, color: AppColors.divider),
        WizardComputedRow(
          label: 'Cost of goats sold',
          value: wizardCurrency(s.cost),
        ),
        Row(
          children: [
            Text(
              'Profit',
              style: AppTheme.body(
                size: 13.5,
                color: AppColors.textDark,
                weight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              wizardCurrency(profit),
              style: AppTheme.heading(size: 16, color: profitColor),
            ),
          ],
        ),
        if (lot.farmDeathQty > 0) ...[
          const Divider(height: 18, color: AppColors.divider),
          WizardComputedRow(
            label: 'Died at farm (${lot.farmDeathQty} '
                'goat${lot.farmDeathQty == 1 ? '' : 's'})',
            value: '≈ ${wizardCurrency(farmDeathLoss)}',
          ),
          const SizedBox(height: 4),
          Text(
            lot.remainingQty > 0
                ? 'This loss is already carried by the ${lot.remainingQty} '
                'goat${lot.remainingQty == 1 ? '' : 's'} still in the lot '
                '(their cost per goat is higher). It is not deducted from '
                'profit again.'
                : 'No goats are left in this lot to carry this loss, so it '
                'is not included in the profit above.',
            style: AppTheme.body(size: 11),
          ),
          if (s.unrecoveredCost(lot) > 0) ...[
            const SizedBox(height: 10),
            WizardComputedRow(
              label: 'Cost not recovered (goats died)',
              value: '− ${wizardCurrency(s.unrecoveredCost(lot))}',
            ),
            Row(
              children: [
                Text(
                  'Profit after death loss',
                  style: AppTheme.body(
                    size: 13.5,
                    color: AppColors.textDark,
                    weight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  wizardCurrency(s.profitAfterUnrecovered(lot)),
                  style: AppTheme.heading(
                    size: 16,
                    color: s.profitAfterUnrecovered(lot) >= 0
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Lot total cost minus the cost carried by the goats sold. '
                  'For information only — Trading Finance \'Lot profit\' '
                  'is unchanged.',
              style: AppTheme.body(size: 11),
            ),
          ],
        ],
        const SizedBox(height: 8),
        Text(
          'Profit = sales revenue − purchase cost of the goats sold. Goats '
              'that die (in transit or at the farm) after a sale are not '
              'deducted from that sale.',
          style: AppTheme.body(size: 11),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // LOT HISTORY
  // ---------------------------------------------------------------------

  Widget _historyCard(BuildContext context, LotSalesSummary s) {
    final all = [...s.openSales, ...s.completedSales]..sort(
          (a, b) => (b.saleDate ?? DateTime(2000))
          .compareTo(a.saleDate ?? DateTime(2000)),
    );

    return WizardSectionCard(
      title: 'Lot history',
      icon: Icons.history_rounded,
      children: [
        if (all.isEmpty)
          Text(
            'No sales from this lot yet.',
            style: AppTheme.body(size: 12.5),
          )
        else
          for (var i = 0; i < all.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: AppColors.divider),
            _saleRow(context, all[i]),
          ],
      ],
    );
  }

  static bool _isOpen(Sale sale) => !sale.isDelivered;

  static bool _hasReceipt(Sale sale) =>
      sale.status == Sale.statusSold ||
          sale.status == Sale.statusDeliveryCompleted ||
          sale.status == Sale.statusPickupCompleted;

  static String _statusLabel(Sale sale) {
    switch (sale.status) {
      case Sale.statusSold:
        return 'Sold';
      case Sale.statusBooked:
        return 'Booked';
      case Sale.statusDeliveryCompleted:
        return 'Delivered';
      case Sale.statusWaitForDelivery:
        return 'Waiting';
      case Sale.statusPickupCompleted:
        return 'Picked up';
      case Sale.statusTransferredToPalai:
        return 'In Palai';
      default:
        return sale.status.isEmpty ? 'Sold' : sale.status;
    }
  }

  /// Paid / Partial / Pending from the money actually received.
  static String _paymentLabel(Sale sale) {
    if (sale.billBalanceDue <= 0) return 'Paid';
    return sale.billAmountPaid > 0 ? 'Partial' : 'Pending';
  }

  static Color _paymentColor(String label) {
    switch (label) {
      case 'Paid':
        return AppColors.success;
      case 'Partial':
        return const Color(0xFFB26A00);
      default:
        return AppColors.error;
    }
  }

  Widget _saleRow(BuildContext context, Sale sale) {
    final open = _isOpen(sale);
    final statusColor = open ? AppColors.warning : AppColors.success;
    final payment = _paymentLabel(sale);
    final weight = LotSalesSummary.saleWeight(sale);
    final customer =
    sale.customerName.trim().isEmpty ? 'Customer' : sale.customerName;
    final tappable = _hasReceipt(sale);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${sale.id} • $customer',
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              LotBadge(label: _statusLabel(sale), color: statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (sale.saleDate != null) wizardDate(sale.saleDate!),
              '${sale.lotQuantity} goat${sale.lotQuantity == 1 ? '' : 's'}',
              '${PurchaseCosting.formatNumber(weight)} kg',
              if (sale.isFixedPrice)
                'Fixed ${wizardCurrency(sale.fixedSalePrice ?? sale.totalSaleAmount)}'
              else if (weight > 0)
                '${wizardCurrency(LotSalesSummary.effectivePricePerKg(sale))}'
                    '/kg',
            ].join('  •  '),
            style: AppTheme.body(size: 11.5),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                wizardCurrency(sale.billGoatSale),
                style: AppTheme.body(
                  size: 13.5,
                  color: AppColors.textDark,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              LotBadge(label: payment, color: _paymentColor(payment)),
              const Spacer(),
              if (tappable)
                Row(
                  children: [
                    Text(
                      sale.canCollectBalance ? 'Receipt / collect' : 'Receipt',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.primaryGreen,
                    ),
                  ],
                )
              else if (open)
                Text(
                  'Finish from Booking / Wait on Delivery',
                  style: AppTheme.body(size: 10.5),
                ),
            ],
          ),
          if (sale.canCollectBalance) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _receivePayment(context, sale),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: Text(
                  'Receive payment • ${wizardCurrency(sale.billBalanceDue)} due',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!tappable) return row;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        fastRoute(SaleReceiptScreen(farmId: farmId, saleId: sale.id)),
      ),
      child: row,
    );
  }

  /// Opens the same balance-payment form as the receipt. The sale stream on
  /// Lot Detail refreshes the row (Paid / Partial, amount due) by itself.
  Future<void> _receivePayment(BuildContext context, Sale sale) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaleReceivePaymentSheet(farmId: farmId, sale: sale),
    );

    if (recorded != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment recorded.')),
    );
  }
}