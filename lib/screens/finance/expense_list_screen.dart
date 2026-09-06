import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/expense_categories.dart';
import '../../models/expense_model.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../../widgets/finance/expense_category_chip.dart';
import 'add_edit_expense_screen.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  String? _category;
  String _search = '';
  final _searchController = TextEditingController();

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _openAdd() async {
    final result = await Navigator.of(context).push<bool>(
      fastRoute(const AddEditExpenseScreen()),
    );
    if (result == true) setState(() {});
  }

  Future<void> _openEdit(ExpenseModel expense) async {
    final result = await Navigator.of(context).push<bool>(
      fastRoute(AddEditExpenseScreen(existing: expense)),
    );
    if (result == true) setState(() {});
  }

  Future<void> _confirmVoid(ExpenseModel expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Void this expense?', style: AppTheme.heading(size: 17)),
        content: Text(
          'This removes it from all totals and reports, but keeps it visible here for your records.',
          style: AppTheme.body(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: AppTheme.body(size: 13, color: AppColors.textGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Void',
              style: AppTheme.body(size: 13, color: AppColors.error, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || _farmId == null) return;

    try {
      await FinanceService.instance.voidExpense(_farmId!, expense);
      _message('Expense voided');
    } on TimeoutException {
      _message('This is taking too long. Check your connection and try again.', error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
    }
  }

  List<ExpenseModel> _filter(List<ExpenseModel> items) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((e) {
      return e.title.toLowerCase().contains(query) ||
          (e.supplierName ?? '').toLowerCase().contains(query) ||
          (e.invoiceNumber ?? '').toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query);
    }).toList();
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
        title: Text('Expenses', style: AppTheme.heading(size: 18)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        backgroundColor: AppColors.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
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
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _search = v),
                          style: AppTheme.body(size: 13),
                          decoration: InputDecoration(
                            hintText: 'Search title, supplier, invoice...',
                            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textGrey),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                              borderSide: BorderSide(color: AppColors.divider),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CategoryChipRow(
                          categories: ExpenseCategories.all,
                          selected: _category,
                          onSelected: (v) => setState(() => _category = v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<List<ExpenseModel>>(
                          stream: FinanceService.instance.expensesStream(
                            _farmId!,
                            category: _category,
                          ),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(color: AppColors.primaryGreen),
                              );
                            }
                            final items = _filter(snapshot.data!);
                            if (items.isEmpty) {
                              return Center(
                                child: Text('No expenses found.', style: AppTheme.body(size: 13)),
                              );
                            }

                            final total = items.fold<double>(0, (sum, e) => sum + e.amount);

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: items.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      'Total: ₹${total.toStringAsFixed(0)}',
                                      style: AppTheme.heading(size: 16),
                                    ),
                                  );
                                }
                                final expense = items[index - 1];
                                return _expenseCard(expense);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _expenseCard(ExpenseModel expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: InkWell(
        onTap: () => _openEdit(expense),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w700),
                  ),
                  Text(
                    '${expense.category} · ${DateFormat('dd MMM yyyy').format(expense.date)}',
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                  if (expense.supplierName != null && expense.supplierName!.isNotEmpty)
                    Text(
                      expense.supplierName!,
                      style: AppTheme.body(size: 10, color: AppColors.textGrey),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${expense.amount.toStringAsFixed(0)}',
                  style: AppTheme.body(size: 14, color: AppColors.error, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _confirmVoid(expense),
                  child: Text(
                    'Void',
                    style: AppTheme.body(size: 10, color: AppColors.textGrey, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
