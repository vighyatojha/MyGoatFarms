import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/finance_scope.dart';
import '../../models/finance_summary_model.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/finance/finance_widgets.dart';
import 'add_edit_expense_screen.dart';
import 'add_edit_revenue_screen.dart';
import 'customer_ledger_screen.dart';
import 'expense_list_screen.dart';
import 'finance_range.dart';
import 'revenue_list_screen.dart';
import 'supplier_ledger_screen.dart';

/// PALAI side of the Finance tab.
///
/// Palai customer money (bills, monthly bills, payments, receivables,
/// advances) plus the farm's own running costs (feed, medicine, office...).
/// Goat Trading money is deliberately NOT here — it lives on the Trading
/// side, so the two never mix in one total.
class PalaiFinanceView extends StatefulWidget {
  final String farmId;
  final FinanceRangePreset preset;

  const PalaiFinanceView({
    super.key,
    required this.farmId,
    required this.preset,
  });

  @override
  State<PalaiFinanceView> createState() => _PalaiFinanceViewState();
}

class _PalaiFinanceViewState extends State<PalaiFinanceView> {
  bool _loading = true;
  FinanceSummary _summary = FinanceSummary.empty;
  List<FinanceTransactionRow> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PalaiFinanceView oldWidget) {
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
        FinanceService.instance.getFinanceSummary(
          widget.farmId,
          start: range.start,
          end: range.end,
          scope: FinanceScope.palai,
        ),
        FinanceService.instance.getRecentTransactions(
          widget.farmId,
          limit: 8,
          scope: FinanceScope.palai,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as FinanceSummary;
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

  Future<void> _openAddExpense() async {
    final result = await Navigator.of(context)
        .push<bool>(fastRoute(const AddEditExpenseScreen()));
    if (result == true) _load();
  }

  Future<void> _openAddRevenue() async {
    final result = await Navigator.of(context)
        .push<bool>(fastRoute(const AddEditRevenueScreen()));
    if (result == true) _load();
  }

  void _push(Widget screen) {
    Navigator.of(context).push(fastRoute(screen));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _loading ? _skeleton() : _summaryCards(),
          const SizedBox(height: 14),
          if (!_loading)
            FinanceModeCard(
              title: 'Payments Received',
              cash: _summary.cashReceived,
              online: _summary.onlineReceived,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FinanceActionButton(
                  label: 'Add Expense',
                  icon: Icons.remove_rounded,
                  color: AppColors.error,
                  onTap: _openAddExpense,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FinanceActionButton(
                  label: 'Add Revenue',
                  icon: Icons.add_rounded,
                  color: AppColors.success,
                  onTap: _openAddRevenue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FinanceNavChip(
                  label: 'Expenses',
                  icon: Icons.receipt_long_outlined,
                  onTap: () => _push(
                    const ExpenseListScreen(scope: FinanceScope.palai),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Revenue',
                  icon: Icons.trending_up_rounded,
                  onTap: () => _push(
                    const RevenueListScreen(scope: FinanceScope.palai),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Ledger',
                  icon: Icons.people_alt_outlined,
                  onTap: () => _push(const CustomerLedgerScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinanceNavChip(
                  label: 'Suppliers',
                  icon: Icons.local_shipping_outlined,
                  onTap: () => _push(const SupplierLedgerScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Recent Transactions', style: AppTheme.heading(size: 15)),
          const SizedBox(height: 10),
          FinanceRecentList(
            loading: _loading,
            rows: _recent,
            emptyHint: 'Palai payments and farm expenses will appear here.',
            onTapRow: (row) => _push(
              row.isIncome
                  ? const RevenueListScreen(scope: FinanceScope.palai)
                  : const ExpenseListScreen(scope: FinanceScope.palai),
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
      child: const CircularProgressIndicator(color: AppColors.primaryGreen),
    );
  }

  Widget _summaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FinanceStatTile(
                label: 'Revenue',
                value: _summary.revenue,
                color: AppColors.success,
                icon: Icons.arrow_upward_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FinanceStatTile(
                label: 'Expenses',
                value: _summary.expenses,
                color: AppColors.error,
                icon: Icons.arrow_downward_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FinanceNetCard(label: 'Net Cash Flow', value: _summary.netCashFlow),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FinanceStatTile(
                label: 'Receivables',
                value: _summary.totalOutstanding,
                color: AppColors.warning,
                icon: Icons.hourglass_empty_rounded,
                onTap: () => _push(const CustomerLedgerScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FinanceStatTile(
                label: 'Customer Advances',
                value: _summary.totalAdvance,
                color: AppColors.info,
                icon: Icons.savings_outlined,
                onTap: () => _push(const CustomerLedgerScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}