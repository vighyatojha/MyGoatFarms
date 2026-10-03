import 'package:flutter/material.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/expense_categories.dart';
import 'package:mygoatfarms/models/finance_scope.dart';
import 'package:mygoatfarms/models/finance_summary_model.dart';
import 'package:mygoatfarms/models/trading_finance_summary.dart';
import 'package:mygoatfarms/screens/finance/trading_loss_screen.dart';
import 'package:mygoatfarms/services/finance_service.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/sales_service.dart';
import 'package:mygoatfarms/services/trading_service.dart';
import 'package:mygoatfarms/models/trading_purchase_model.dart';
import 'package:mygoatfarms/widgets/fast_route.dart';
import 'package:mygoatfarms/widgets/finance/finance_widgets.dart';
import 'package:mygoatfarms/widgets/finance/payment_reminder_service.dart';
import 'package:mygoatfarms/screens/finance/credit_customers_screen.dart';
import 'package:mygoatfarms/screens/finance/expense_list_screen.dart';
import 'package:mygoatfarms/screens/finance/finance_range.dart';
import 'package:mygoatfarms/screens/finance/revenue_list_screen.dart';
import 'package:mygoatfarms/screens/finance/supplier_pending_payments_screen.dart';

/// TRADING side of the Finance tab.
///
/// Goat purchases, goat sales and goat-sale credit — nothing from Palai
/// customers or the farm's running costs.
///
///   Sales Revenue  = Sold Goat Revenue received
///   Total Spent    = Goat purchase costs + transport/loading/other
///   Net Cash Flow  = Sales Revenue - Total Spent
///   Receivables    = Goat-sale balances customers still owe
///
/// Losses are displayed separately from Trading Net Cash Flow so the
/// existing trading cash-flow calculation is not double-counted.
class TradingFinanceView extends StatefulWidget {
  final String farmId;
  final FinanceRangePreset preset;

  const TradingFinanceView({
    super.key,
    required this.farmId,
    required this.preset,
  });

  @override
  State<TradingFinanceView> createState() =>
      _TradingFinanceViewState();
}

class _TradingFinanceViewState
    extends State<TradingFinanceView> {
  bool _loading = true;
  bool _sendingReminders = false;

  TradingFinanceSummary _summary =
      TradingFinanceSummary.empty;

  List<FinanceTransactionRow> _recent = [];

  // What the farm still owes goat suppliers.
  // Current balance, not affected by the date range.
  double _supplierDue = 0;
  int _supplierLotCount = 0;

  // Used in the WhatsApp reminder text.
  String _farmName = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadFarmName();
  }

  Future<void> _loadFarmName() async {
    final farm =
    await FirestoreService.instance.getFarmById(
      widget.farmId,
    );

    if (!mounted) return;

    setState(() {
      _farmName = farm?.farmName ?? '';
    });
  }

  @override
  void didUpdateWidget(
      covariant TradingFinanceView oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.preset != widget.preset ||
        oldWidget.farmId != widget.farmId) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }

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
        TradingService.instance
            .purchasesStream(widget.farmId)
            .first,
      ]);

      final lotsOwed =
      (results[2] as List<TradingPurchase>)
          .where(
            (p) =>
        p.isLot &&
            p.dueAmount >= 0.01,
      )
          .toList();

      if (!mounted) return;

      setState(() {
        _summary =
        results[0] as TradingFinanceSummary;

        _recent =
        results[1] as List<FinanceTransactionRow>;

        _supplierDue = lotsOwed.fold<double>(
          0,
              (sum, p) => sum + p.dueAmount,
        );

        _supplierLotCount =
            lotsOwed.length;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirestoreService.instance.describeError(e),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      fastRoute(screen),
    );
  }

  void _openCredit() {
    _push(
      CreditCustomersScreen(
        farmId: widget.farmId,
      ),
    );
  }

  Future<void> _openSupplierDues() async {
    await Navigator.of(context).push(
      fastRoute(
        SupplierPendingPaymentsScreen(
          farmId: widget.farmId,
        ),
      ),
    );

    if (mounted) {
      _load();
    }
  }

  /// Opens the Trading Loss ledger using the same Finance date range
  /// currently selected at the top of Finance.
  void _openLosses() {
    final range = widget.preset.range;

    _push(
      TradingLossScreen(
        farmId: widget.farmId,
        start: range.start,
        end: range.end,
      ),
    );
  }

  /// One-tap WhatsApp reminders for every goat-sale customer who still
  /// owes money.
  Future<void> _openReminders() async {
    if (_sendingReminders) return;

    setState(() => _sendingReminders = true);

    try {
      final all = await SalesService.instance
          .creditCustomersStream(widget.farmId)
          .first;

      if (!mounted) return;

      final owing =
      all.where((c) => c.totalDue > 0).toList();

      if (owing.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No customers currently owe money on goat sales.',
            ),
            backgroundColor: AppColors.darkGreen,
          ),
        );

        return;
      }

      await showPaymentReminderSheet(
        context,
        customers: owing
            .map(
          ReminderRecipient.fromCustomerCredit,
        )
            .toList(),
        farmName: _farmName,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirestoreService.instance.describeError(e),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(
              () => _sendingReminders = false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.info,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          4,
          16,
          28,
        ),
        children: [
          if (_loading)
            _skeleton()
          else
            ..._summaryWidgets(),

          const SizedBox(height: 16),

          // -------------------------------------------------------------
          // TRADING NAVIGATION
          // -------------------------------------------------------------

          Text(
            'Trading Finance',
            style: AppTheme.heading(size: 15),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: FinanceNavChip(
                  label: 'Purchases',
                  icon: Icons.shopping_cart_outlined,
                  onTap: () => _push(
                    const ExpenseListScreen(
                      scope: FinanceScope.trading,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Sales',
                  icon: Icons.sell_outlined,
                  onTap: () => _push(
                    const RevenueListScreen(
                      scope: FinanceScope.trading,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Credit',
                  icon:
                  Icons.account_balance_wallet_outlined,
                  onTap: _openCredit,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          FinanceNavChip(
            label: 'Supplier Pending Payments',
            icon: Icons.outbox_outlined,
            onTap: _openSupplierDues,
          ),

          const SizedBox(height: 8),

          // -------------------------------------------------------------
          // LOSS REDIRECTION
          // -------------------------------------------------------------
          //
          // Full width intentionally: Losses is a finance ledger and
          // should not be squeezed into the three small navigation chips.
          //
          FinanceNavChip(
            label: 'Trading Losses',
            icon: Icons.trending_down_rounded,
            iconColor: AppColors.error,
            onTap: _openLosses,
          ),

          const SizedBox(height: 8),

          FinanceNavChip(
            label: _sendingReminders
                ? 'Loading...'
                : 'Send WhatsApp Reminder',
            icon: Icons.chat,
            iconColor: const Color(0xFF25D366),
            onTap:
            _sendingReminders
                ? null
                : _openReminders,
          ),

          const SizedBox(height: 20),

          Text(
            'Recent Trading Activity',
            style: AppTheme.heading(size: 15),
          ),

          const SizedBox(height: 10),

          FinanceRecentList(
            loading: _loading,
            rows: _recent,
            emptyHint:
            'Goat purchases and sales will appear here.',
            onTapRow: (row) => _push(
              row.isIncome
                  ? const RevenueListScreen(
                scope: FinanceScope.trading,
              )
                  : const ExpenseListScreen(
                scope: FinanceScope.trading,
              ),
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
      child: const CircularProgressIndicator(
        color: AppColors.info,
      ),
    );
  }

  List<Widget> _summaryWidgets() {
    final s = _summary;
    final avgCostPerGoat =
        s.avgCostPerGoat;

    return [
      Row(
        children: [
          Expanded(
            child: FinanceStatTile(
              label: 'Sales Revenue',
              value: s.salesRevenue,
              color: AppColors.success,
              icon: Icons.arrow_upward_rounded,
              caption:
              '${s.salesCount} sale'
                  '${s.salesCount == 1 ? '' : 's'}',
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
              '${s.purchaseCount} purchase'
                  '${s.purchaseCount == 1 ? '' : 's'}',
            ),
          ),
        ],
      ),

      const SizedBox(height: 10),

      FinanceNetCard(
        label: 'Trading Net Cash Flow',
        value: s.netCashFlow,
        caption:
        'Sales received − purchase costs',
      ),

      const SizedBox(height: 10),

      Row(
        children: [
          Expanded(
            child: FinanceStatTile(
              label: 'Receivables',
              value: s.receivable,
              color: AppColors.warning,
              icon:
              Icons.hourglass_empty_rounded,
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
              caption:
              '${s.goatsPurchased} goats bought',
            ),
          ),
        ],
      ),

      const SizedBox(height: 10),

      FinanceStatTile(
        label: 'Supplier Pending Payments',
        value: _supplierDue,
        color: AppColors.error,
        icon: Icons.outbox_outlined,
        caption: _supplierLotCount == 0
            ? 'Every supplier is paid'
            : '$_supplierLotCount lot'
            '${_supplierLotCount == 1 ? '' : 's'} '
            'not paid in full',
        onTap: _openSupplierDues,
      ),

      const SizedBox(height: 14),

      _costBreakdown(s),

      if (s.hasLotAccounting) ...[
        const SizedBox(height: 14),
        _lotAccounting(s),
      ],

      const SizedBox(height: 14),

      FinanceModeCard(
        title: 'Payments Received',
        cash: s.cashReceived,
        online: s.onlineReceived,
      ),

      const SizedBox(height: 10),

      FinanceModeCard(
        title: 'Cash Paid',
        titleIcon: Icons.outbox_outlined,
        cash: s.cashPaid,
        online: s.onlinePaid,
      ),

      const SizedBox(height: 6),

      Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Cash Paid includes supplier payments and '
              'purchase-related transport/loading/other costs. '
              'Online Paid reflects recorded online supplier payments.',
          style: AppTheme.body(
            size: 10.5,
            color: AppColors.textGrey,
          ),
        ),
      ),
    ];
  }

  Widget _lotAccounting(
      TradingFinanceSummary s,
      ) {
    Widget row(
        String label,
        double value, {
          bool bold = false,
          Color? color,
        }) {
      return Padding(
        padding:
        const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTheme.body(
                  size: 12,
                  color: bold
                      ? AppColors.textDark
                      : AppColors.textGrey,
                  weight: bold
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            Text(
              financeRupees(value),
              style: AppTheme.heading(
                size: bold ? 14 : 12.5,
                color:
                color ?? AppColors.textDark,
              ),
            ),
          ],
        ),
      );
    }

    final profit = s.lotProfit;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.darkGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Lot Accounting',
                style: AppTheme.heading(size: 14),
              ),
            ],
          ),

          const SizedBox(height: 8),

          row(
            'Purchase value (lots bought)',
            s.lotPurchaseValue,
          ),

          row(
            'Paid to suppliers (lot payments)',
            s.expenseByCategory[
            ExpenseCategories.supplierPayment] ??
                0,
          ),

          row(
            'Supplier pending (now)',
            s.lotSupplierPending,
          ),

          const Divider(height: 14),

          row(
            'Sales value (${s.lotGoatsSold} goats)',
            s.lotSalesValue,
          ),

          row(
            'Cost of goats sold',
            s.lotCostOfSales,
          ),

          const Divider(height: 14),

          row(
            'Lot profit',
            profit,
            bold: true,
            color: profit >= 0
                ? AppColors.success
                : AppColors.error,
          ),

          const SizedBox(height: 6),

          Text(
            'Counts purchases and sales when they happen, '
                'not when cash moves, for Purchase Lots only. '
                'Net Cash Flow above is unchanged.',
            style: AppTheme.body(size: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _costBreakdown(
      TradingFinanceSummary s,
      ) {
    Widget row(
        String label,
        double value, {
          bool bold = false,
        }) {
      return Padding(
        padding:
        const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTheme.body(
                  size: 12,
                  color: bold
                      ? AppColors.textDark
                      : AppColors.textGrey,
                  weight: bold
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            Text(
              financeRupees(value),
              style: AppTheme.heading(
                size: bold ? 14 : 12.5,
              ),
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
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.darkGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Purchase Costs',
                style: AppTheme.heading(size: 14),
              ),
            ],
          ),

          const SizedBox(height: 8),

          row(
            'Paid to sellers',
            s.purchaseSpend,
          ),

          row(
            'Transport, loading & other',
            s.otherPurchaseCosts,
          ),

          const Divider(height: 14),

          row(
            'Total spent',
            s.totalCost,
            bold: true,
          ),
        ],
      ),
    );
  }
}