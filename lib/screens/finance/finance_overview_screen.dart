import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/finance_summary_model.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../../widgets/finance/finance_transaction_tile.dart';
import 'add_edit_expense_screen.dart';
import 'add_edit_revenue_screen.dart';
import 'customer_ledger_screen.dart';
import 'expense_list_screen.dart';
import 'revenue_list_screen.dart';

enum _RangePreset { thisMonth, lastMonth, thisWeek, today }

class FinanceOverviewScreen extends StatefulWidget {
  const FinanceOverviewScreen({super.key});

  @override
  State<FinanceOverviewScreen> createState() => _FinanceOverviewScreenState();
}

class _FinanceOverviewScreenState extends State<FinanceOverviewScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  bool _loadingSummary = true;

  _RangePreset _preset = _RangePreset.thisMonth;
  FinanceSummary _summary = FinanceSummary.empty;
  List<FinanceTransactionRow> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final id = await FirestoreService.instance.currentFarmId();
    if (!mounted) return;
    setState(() {
      _farmId = id;
      _loadingFarm = false;
    });
    if (id != null) await _loadSummary(id);
  }

  ({DateTime start, DateTime end}) _rangeFor(_RangePreset preset) {
    final now = DateTime.now();
    switch (preset) {
      case _RangePreset.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start: start, end: start.add(const Duration(days: 1)));
      case _RangePreset.thisWeek:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (start: start, end: start.add(const Duration(days: 7)));
      case _RangePreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return (start: start, end: end);
      case _RangePreset.lastMonth:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 1);
        return (start: start, end: end);
    }
  }

  Future<void> _loadSummary(String farmId) async {
    setState(() => _loadingSummary = true);
    final range = _rangeFor(_preset);
    try {
      final results = await Future.wait([
        FinanceService.instance.getFinanceSummary(farmId, start: range.start, end: range.end),
        FinanceService.instance.getRecentTransactions(farmId, limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as FinanceSummary;
        _recent = results[1] as List<FinanceTransactionRow>;
        _loadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FirestoreService.instance.describeError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _refresh() async {
    if (_farmId != null) await _loadSummary(_farmId!);
  }

  Future<void> _openAddExpense() async {
    final result = await Navigator.of(context).push<bool>(fastRoute(const AddEditExpenseScreen()));
    if (result == true) _refresh();
  }

  Future<void> _openAddRevenue() async {
    final result = await Navigator.of(context).push<bool>(fastRoute(const AddEditRevenueScreen()));
    if (result == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text('Finance', style: AppTheme.heading(size: 18)),
      ),
      body: SafeArea(
        child: _loadingFarm
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _farmId == null
                ? FarmNotLinkedState(
                    buttonColor: AppColors.primaryGreen,
                    onRetry: () {
                      setState(() => _loadingFarm = true);
                      _loadFarm();
                    },
                  )
                : RefreshIndicator(
                    color: AppColors.primaryGreen,
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _rangeSelector(),
                        const SizedBox(height: 14),
                        _loadingSummary ? _summarySkeleton() : _summaryCards(),
                        const SizedBox(height: 14),
                        _quickLinks(),
                        const SizedBox(height: 10),
                        _viewAllLinks(),
                        const SizedBox(height: 18),
                        Text('Recent Transactions', style: AppTheme.heading(size: 15)),
                        const SizedBox(height: 10),
                        _recentTransactions(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _rangeSelector() {
    final labels = {
      _RangePreset.today: 'Today',
      _RangePreset.thisWeek: 'This Week',
      _RangePreset.thisMonth: 'This Month',
      _RangePreset.lastMonth: 'Last Month',
    };

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: labels.entries.map((entry) {
          final selected = _preset == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _preset = entry.key);
                if (_farmId != null) _loadSummary(_farmId!);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryGreen : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? AppColors.primaryGreen : AppColors.divider),
                ),
                child: Text(
                  entry.value,
                  style: AppTheme.body(
                    size: 12,
                    color: selected ? Colors.white : AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _summarySkeleton() {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: AppTheme.card(radius: 18),
      child: const CircularProgressIndicator(color: AppColors.primaryGreen),
    );
  }

  Widget _summaryCards() {
    final netColor = _summary.netCashFlow >= 0 ? AppColors.success : AppColors.error;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _statTile('Revenue', _summary.revenue, AppColors.success, Icons.arrow_upward_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _statTile('Expenses', _summary.expenses, AppColors.error, Icons.arrow_downward_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.card(radius: 18),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: netColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net Cash Flow', style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                    Text(
                      '₹${_summary.netCashFlow.toStringAsFixed(0)}',
                      style: AppTheme.heading(size: 18, color: netColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statTile(
                'Receivables',
                _summary.totalOutstanding,
                AppColors.warning,
                Icons.hourglass_empty_rounded,
                onTap: () => Navigator.of(context).push(fastRoute(const CustomerLedgerScreen())),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statTile(
                'Customer Advances',
                _summary.totalAdvance,
                AppColors.info,
                Icons.savings_outlined,
                onTap: () => Navigator.of(context).push(fastRoute(const CustomerLedgerScreen())),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statTile(String label, double value, Color color, IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.card(radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text('₹${value.toStringAsFixed(0)}', style: AppTheme.heading(size: 16)),
            const SizedBox(height: 2),
            Text(label, style: AppTheme.body(size: 11), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _quickLinks() {
    return Row(
      children: [
        Expanded(
          child: _linkButton(
            label: 'Add Expense',
            icon: Icons.remove_rounded,
            color: AppColors.error,
            onTap: _openAddExpense,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _linkButton(
            label: 'Add Revenue',
            icon: Icons.add_rounded,
            color: AppColors.success,
            onTap: _openAddRevenue,
          ),
        ),
      ],
    );
  }

  /// Direct navigation to the full Expenses / Revenue / Customer Ledger
  /// screens — separate from the "Recent Transactions" tap-through
  /// below, which only shows the last few rows.
  Widget _viewAllLinks() {
    return Row(
      children: [
        Expanded(
          child: _navChip(
            label: 'Expenses',
            icon: Icons.receipt_long_outlined,
            onTap: () => Navigator.of(context).push(fastRoute(const ExpenseListScreen())),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _navChip(
            label: 'Revenue',
            icon: Icons.trending_up_rounded,
            onTap: () => Navigator.of(context).push(fastRoute(const RevenueListScreen())),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _navChip(
            label: 'Ledger',
            icon: Icons.people_alt_outlined,
            onTap: () => Navigator.of(context).push(fastRoute(const CustomerLedgerScreen())),
          ),
        ),
      ],
    );
  }

  Widget _navChip({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.darkGreen, size: 18),
            const SizedBox(height: 5),
            Text(label, style: AppTheme.body(size: 11, color: AppColors.textDark, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _linkButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(label, style: AppTheme.body(size: 11, color: color, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _recentTransactions() {
    if (_loadingSummary) {
      return Container(
        height: 130,
        alignment: Alignment.center,
        decoration: AppTheme.card(radius: 17),
        child: const CircularProgressIndicator(color: AppColors.primaryGreen, strokeWidth: 2),
      );
    }

    if (_recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: AppTheme.card(radius: 17),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, color: AppColors.textGrey, size: 30),
            const SizedBox(height: 9),
            Text('No transactions yet', style: AppTheme.body(size: 12, color: AppColors.textGrey, weight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('Expenses and revenue will appear here.', style: AppTheme.body(size: 10)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider.withOpacity(0.7)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _recent.length; i++)
            FinanceTransactionTile(
              row: _recent[i],
              showDivider: i != _recent.length - 1,
              onTap: () {
                Navigator.of(context).push(
                  fastRoute(
                    _recent[i].isIncome ? const RevenueListScreen() : const ExpenseListScreen(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
