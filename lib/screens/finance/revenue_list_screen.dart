import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/expense_categories.dart';
import '../../models/finance_summary_model.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../../widgets/finance/expense_category_chip.dart';
import 'add_edit_revenue_screen.dart';

/// Revenue — reads the existing shared `transactions` collection, so
/// every customer payment from the current billing flow shows up here
/// automatically alongside manually-added revenue.
///
/// This absorbs what the old, now-deleted `IncomeDetailScreen` did
/// (a calendar day-filter, and a detailed payment-breakdown bottom
/// sheet showing pending/advance before-and-after snapshots) so there
/// is one income view instead of two that each showed a slightly
/// different slice of the same data.
class RevenueListScreen extends StatefulWidget {
  const RevenueListScreen({super.key});

  @override
  State<RevenueListScreen> createState() => _RevenueListScreenState();
}

class _RevenueListScreenState extends State<RevenueListScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  String? _category;
  String _search = '';
  final _searchController = TextEditingController();

  DateTime? _selectedDate;
  bool _showCalendar = false;

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
      fastRoute(const AddEditRevenueScreen()),
    );
    if (result == true) setState(() {});
  }

  /// Manual revenue rows open the edit form. Customer-payment rows open
  /// the read-only detail sheet (ported from the old IncomeDetailScreen)
  /// instead — correcting a real payment goes through Customers/Palai,
  /// not here (spec §29).
  Future<void> _handleTap(FinanceTransactionRow row) async {
    final doc = await FirebaseFirestore.instance
        .collection('farms')
        .doc(_farmId)
        .collection('transactions')
        .doc(row.id)
        .get();

    final data = doc.data();
    if (data == null) return;

    if (data['referenceType'] == 'manualRevenue') {
      final result = await Navigator.of(context).push<bool>(
        fastRoute(AddEditRevenueScreen(existingTransactionId: row.id, existingData: data)),
      );
      if (result == true) setState(() {});
      return;
    }

    _showPaymentDetails(data);
  }

  Future<void> _confirmVoidManual(FinanceTransactionRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Void this revenue?', style: AppTheme.heading(size: 17)),
        content: Text(
          'This removes it from all totals and reports, but keeps it visible for your records.',
          style: AppTheme.body(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: AppTheme.body(size: 13, color: AppColors.textGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Void', style: AppTheme.body(size: 13, color: AppColors.error, weight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || _farmId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('farms')
          .doc(_farmId)
          .collection('transactions')
          .doc(row.id)
          .get();
      final data = doc.data();
      if (data == null) return;

      await FinanceService.instance.voidManualRevenue(_farmId!, row.id, data);
      _message('Revenue voided');
    } on TimeoutException {
      _message('This is taking too long. Check your connection and try again.', error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
    }
  }

  List<FinanceTransactionRow> _filter(List<FinanceTransactionRow> items) {
    var results = items;

    if (_selectedDate != null) {
      final day = _selectedDate!;
      results = results.where((r) =>
          r.date.year == day.year && r.date.month == day.month && r.date.day == day.day).toList();
    }

    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      results = results.where((r) {
        return r.title.toLowerCase().contains(query) ||
            (r.customerName ?? '').toLowerCase().contains(query) ||
            r.category.toLowerCase().contains(query);
      }).toList();
    }

    return results;
  }

  String _rupees(double v) => '₹${v.toStringAsFixed(0)}';

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDateTime(dynamic value) {
    DateTime? date;
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (date == null) return 'Date unavailable';

    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} • $hour:$minute $period';
  }

  String _formatDayLabel(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // ---------------------------------------------------------------------
  // PAYMENT DETAILS SHEET — ported from the old IncomeDetailScreen so a
  // customer-payment row still shows its full pending/advance breakdown,
  // not just a "go elsewhere" message.
  // ---------------------------------------------------------------------

  void _showPaymentDetails(Map<String, dynamic> data) {
    final customerName = (data['customerName'] ?? '').toString();
    final paymentMethod = (data['paymentMethod'] ?? '').toString();
    final paymentNumber = (data['paymentNumber'] ?? '').toString();
    final billNumber = (data['billNumber'] ?? '').toString();
    final amount = _number(data['amount']);
    final pendingBefore = _number(data['pendingBefore']);
    final appliedToPending = _number(data['amountAppliedToPending'] ?? data['amountAppliedToBill']);
    final pendingAfter = _number(data['pendingAfter']);
    final advanceBefore = _number(data['advanceBefore']);
    final advanceAdded = _number(data['advanceAmount']);
    final advanceAfter = _number(data['advanceAfter']);
    final note = (data['note'] ?? '').toString();
    final date = data['date'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Payment Details', style: AppTheme.heading(size: 18)),
                const SizedBox(height: 4),
                Text(_formatDateTime(date), style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                const SizedBox(height: 18),
                _detailRow('Amount', _rupees(amount)),
                if (customerName.isNotEmpty) _detailRow('Customer', customerName),
                if (paymentNumber.isNotEmpty) _detailRow('Payment Number', paymentNumber),
                if (billNumber.isNotEmpty) _detailRow('Bill Number', billNumber),
                if (paymentMethod.isNotEmpty) _detailRow('Payment Method', paymentMethod),
                if (pendingBefore > 0) _detailRow('Pending Before', _rupees(pendingBefore)),
                if (appliedToPending > 0) _detailRow('Applied to Pending', _rupees(appliedToPending)),
                _detailRow('Pending After', _rupees(pendingAfter)),
                if (advanceBefore > 0) _detailRow('Advance Before', _rupees(advanceBefore)),
                if (advanceAdded > 0) _detailRow('Advance Added', _rupees(advanceAdded)),
                if (advanceAfter > 0) _detailRow('Advance After', _rupees(advanceAfter)),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Note', style: AppTheme.heading(size: 12)),
                  const SizedBox(height: 4),
                  Text(note, style: AppTheme.body(size: 12)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTheme.body(size: 12, color: AppColors.textGrey))),
          const SizedBox(width: 15),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: AppTheme.heading(size: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRevenueCategories = [...RevenueCategories.all];

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text('Revenue', style: AppTheme.heading(size: 18)),
        actions: [
          IconButton(
            tooltip: 'Browse by date',
            icon: Icon(
              _showCalendar ? Icons.calendar_month : Icons.calendar_month_outlined,
              color: AppColors.primaryGreen,
            ),
            onPressed: () => setState(() => _showCalendar = !_showCalendar),
          ),
        ],
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
                            hintText: 'Search customer, category...',
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
                      if (_showCalendar)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          decoration: AppTheme.card(radius: 16),
                          clipBehavior: Clip.antiAlias,
                          child: CalendarDatePicker(
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime(DateTime.now().year - 5),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setState(() {
                                _selectedDate = date;
                                _showCalendar = false;
                              });
                            },
                          ),
                        ),
                      if (_selectedDate != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.event, size: 14, color: AppColors.primaryGreen),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatDayLabel(_selectedDate!),
                                      style: AppTheme.body(size: 12, color: AppColors.darkGreen, weight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _selectedDate = null),
                                child: Text('Clear', style: AppTheme.body(size: 12, color: AppColors.textGrey, weight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CategoryChipRow(
                          categories: allRevenueCategories,
                          selected: _category,
                          onSelected: (v) => setState(() => _category = v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<List<FinanceTransactionRow>>(
                          stream: FinanceService.instance.revenueStream(
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
                                child: Text(
                                  _selectedDate != null ? 'No revenue on this day.' : 'No revenue found.',
                                  style: AppTheme.body(size: 13),
                                ),
                              );
                            }

                            final total = items.fold<double>(0, (sum, r) => sum + r.amount);

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: items.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      'Total: ${_rupees(total)}',
                                      style: AppTheme.heading(size: 16),
                                    ),
                                  );
                                }
                                final row = items[index - 1];
                                return _revenueCard(row);
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

  Widget _revenueCard(FinanceTransactionRow row) {
    final isManual = RevenueCategories.all.contains(row.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: InkWell(
        onTap: () => _handleTap(row),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_circle_outline, color: AppColors.success, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.customerName ?? row.category,
                    style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w700),
                  ),
                  Text(
                    '${row.category} · ${DateFormat('dd MMM yyyy').format(row.date)}',
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                  Text(
                    isManual ? 'Manual Revenue' : 'Customer Payment · tap for details',
                    style: AppTheme.body(size: 10, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${row.amount.toStringAsFixed(0)}',
                  style: AppTheme.body(size: 14, color: AppColors.success, weight: FontWeight.w800),
                ),
                if (isManual) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _confirmVoidManual(row),
                    child: Text(
                      'Void',
                      style: AppTheme.body(size: 10, color: AppColors.textGrey, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
