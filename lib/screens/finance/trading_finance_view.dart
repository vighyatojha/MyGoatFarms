import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/finance_scope.dart';
import '../../models/finance_summary_model.dart';
import '../../models/trading_finance_summary.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/finance/finance_widgets.dart';
import 'credit_customers_screen.dart';
import 'expense_list_screen.dart';
import 'finance_range.dart';
import 'revenue_list_screen.dart';

/// TRADING side of the Finance tab.
///
/// Goat purchases, goat sales and goat-sale credit — nothing from Palai
/// customers or the farm's running costs. Cash-based, like the Palai
/// side: money counts when it is received or paid.
///
///   Sales Revenue  = Sold Goat Revenue received
///   Total Spent    = goat purchase amounts + transport/loading/other
///                    costs of those purchases
///   Net Cash Flow  = Sales Revenue - Total Spent
///   Receivables    = goat-sale balances customers still owe (current
///                    balance, not affected by the date range)
class TradingFinanceView extends StatefulWidget {
  final String farmId;
  final FinanceRangePreset preset;

  const TradingFinanceView({
    super.key,
    required this.farmId,
    required this.preset,
  });

  @override
  State<TradingFinanceView> createState() => _TradingFinanceViewState();
}

class _TradingFinanceViewState extends State<TradingFinanceView> {
  bool _loading = true;
  TradingFinanceSummary _summary = TradingFinanceSummary.empty;
  List<FinanceTransactionRow> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TradingFinanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset ||
        oldWidget.farmId != widget.farmId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final range = widget.preset.range;

    try {
      final results = await Future.wait([
        FinanceService.instance.getTradingFinanceSummary(
          widget.farmId,
          start: range.start,
          end: range.end,
        ),
        FinanceService.instance.getRecentTransactions(
          widget.farmId,
          limit: 8,
          scope: FinanceScope.trading,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as TradingFinanceSummary;
        _recent = results[1] as List<FinanceTransactionRow>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FirestoreService.instance.describeError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _push(Widget screen) {
    Navigator.of(context).push(fastRoute(screen));
  }

  void _openCredit() => _push(CreditCustomersScreen(farmId: widget.farmId));

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.info,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_loading) _skeleton() else ..._summaryWidgets(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FinanceNavChip(
                  label: 'Purchases',
                  icon: Icons.shopping_cart_outlined,
                  onTap: () => _push(
                    const ExpenseListScreen(scope: FinanceScope.trading),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Sales',
                  icon: Icons.sell_outlined,
                  onTap: () => _push(
                    const RevenueListScreen(scope: FinanceScope.trading),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Credit',
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: _openCredit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Recent Trading Activity', style: AppTheme.heading(size: 15)),
          const SizedBox(height: 10),
          FinanceRecentList(
            loading: _loading,
            rows: _recent,
            emptyHint: 'Goat purchases and sales will appear here.',
            onTapRow: (row) => _push(
              row.isIncome
                  ? const RevenueListScreen(scope: FinanceScope.trading)
                  : const ExpenseListScreen(scope: FinanceScope.trading),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton() {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: AppTheme.card(radius: 18),
      child: const CircularProgressIndicator(color: AppColors.info),
    );
  }

  List<Widget> _summaryWidgets() {
    final s = _summary;
    final avgCostPerGoat =
    s.goatsPurchased > 0 ? s.totalCost / s.goatsPurchased : 0.0;

    return [
      Row(
        children: [
          Expanded(
            child: FinanceStatTile(
              label: 'Sales Revenue',
              value: s.salesRevenue,
              color: AppColors.success,
              icon: Icons.arrow_upward_rounded,
              caption: '${s.salesCount} sale${s.salesCount == 1 ? '' : 's'}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FinanceStatTile(
              label: 'Total Spent',
              value: s.totalCost,
              color: AppColors.error,
              icon: Icons.arrow_downward_rounded,
              caption:
              '${s.purchaseCount} purchase${s.purchaseCount == 1 ? '' : 's'}',
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      FinanceNetCard(
        label: 'Trading Net Cash Flow',
        value: s.netCashFlow,
        caption: 'Sales received − purchase costs',
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: FinanceStatTile(
              label: 'Receivables',
              value: s.receivable,
              color: AppColors.warning,
              icon: Icons.hourglass_empty_rounded,
              caption: s.receivableCount == 0
                  ? 'Nothing pending'
                  : '${s.receivableCount} unpaid sale'
                  '${s.receivableCount == 1 ? '' : 's'}',
              onTap: _openCredit,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FinanceStatTile(
              label: 'Avg Cost / Goat',
              value: avgCostPerGoat,
              color: AppColors.info,
              icon: Icons.pets_outlined,
              caption: '${s.goatsPurchased} goats bought',
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _costBreakdown(s),
      const SizedBox(height: 14),
      FinanceModeCard(
        title: 'Payments Received',
        cash: s.cashReceived,
        online: s.onlineReceived,
      ),
      const SizedBox(height: 10),
      FinanceModeCard(
        title: 'Paid to Sellers',
        titleIcon: Icons.outbox_outlined,
        cash: s.cashPaid,
        online: s.onlinePaid,
      ),
    ];
  }

  Widget _costBreakdown(TradingFinanceSummary s) {
    Widget row(String label, double value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTheme.body(
                  size: 12,
                  color: bold ? AppColors.textDark : AppColors.textGrey,
                  weight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              financeRupees(value),
              style: AppTheme.heading(size: bold ? 14 : 12.5),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  color: AppColors.darkGreen, size: 18),
              const SizedBox(width: 8),
              Text('Purchase Costs', style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 8),
          row('Goat purchase amount', s.purchaseSpend),
          row('Transport, loading & other', s.otherPurchaseCosts),
          const Divider(height: 14),
          row('Total spent', s.totalCost, bold: true),
        ],
      ),
    );
  }
}