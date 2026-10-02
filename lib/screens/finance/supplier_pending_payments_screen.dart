import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/trading_purchase_model.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/trading_service.dart';
import 'package:mygoatfarms/screens/trading/lots/add_lot_payment_sheet.dart';

/// Supplier Pending Payments — every goat supplier the farm still owes
/// money to, with the lots behind each balance.
///
/// Nothing is stored for this list. It is worked out live from the
/// purchase lots ([TradingPurchase.dueAmount] = purchase amount minus what
/// has been paid), the same figures the lot screens use, so paying a
/// supplier here lowers the balance straight away and a supplier who has
/// been paid in full drops off the list.
///
/// Suppliers are grouped by mobile number (else by name), so two lots
/// bought from the same person show as one supplier.
///
/// Only purchase lots are listed: an older goat-first purchase was always
/// paid in full when it was made, so it never has a pending balance.
class SupplierPendingPaymentsScreen extends StatefulWidget {
  final String farmId;

  const SupplierPendingPaymentsScreen({super.key, required this.farmId});

  @override
  State<SupplierPendingPaymentsScreen> createState() =>
      _SupplierPendingPaymentsScreenState();
}

class _SupplierDue {
  final String key;
  final String name;
  final String mobile;
  final List<TradingPurchase> lots;

  _SupplierDue({
    required this.key,
    required this.name,
    required this.mobile,
    required this.lots,
  });

  double get totalDue =>
      lots.fold<double>(0, (sum, lot) => sum + lot.dueAmount);

  double get totalAmount =>
      lots.fold<double>(0, (sum, lot) => sum + lot.purchaseAmount);

  DateTime get oldestPurchase => lots
      .map((l) => l.purchaseDate)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

class _SupplierPendingPaymentsScreenState
    extends State<SupplierPendingPaymentsScreen> {
  late final Stream<List<TradingPurchase>> _stream =
  TradingService.instance.purchasesStream(widget.farmId);

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  /// Lots with money still owed, grouped by supplier, biggest debt first.
  List<_SupplierDue> _group(List<TradingPurchase> purchases) {
    final byKey = <String, List<TradingPurchase>>{};

    for (final lot in purchases) {
      if (!lot.isLot || lot.dueAmount < 0.01) continue;

      final mobile = lot.mobile.trim();
      final name = lot.sellerName.trim();
      final key = mobile.isNotEmpty ? mobile : name.toLowerCase();

      byKey.putIfAbsent(key, () => []).add(lot);
    }

    final result = byKey.entries.map((entry) {
      final lots = [...entry.value]
        ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));

      return _SupplierDue(
        key: entry.key,
        name: lots.last.sellerName.trim().isEmpty
            ? 'Unnamed supplier'
            : lots.last.sellerName.trim(),
        mobile: lots.last.mobile.trim(),
        lots: lots,
      );
    }).toList();

    result.sort((a, b) => b.totalDue.compareTo(a.totalDue));

    return result;
  }

  List<_SupplierDue> _filter(List<_SupplierDue> suppliers) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) return suppliers;

    return suppliers
        .where(
          (s) =>
      s.name.toLowerCase().contains(query) ||
          s.mobile.toLowerCase().contains(query),
    )
        .toList();
  }

  Future<void> _pay(TradingPurchase lot) async {
    final saved = await showAddLotPaymentSheet(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier payment recorded.')),
      );
    }
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
        title: Text(
          'Supplier Pending Payments',
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<TradingPurchase>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _message(
                icon: Icons.error_outline,
                color: AppColors.error,
                text: 'Could not load supplier payments.\n'
                    '${FirestoreService.instance.describeError(snapshot.error!)}',
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              );
            }

            final all = _group(snapshot.data!);

            if (all.isEmpty) {
              return _message(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                text: 'No pending supplier payments.\n'
                    'Every purchase lot has been paid in full.',
              );
            }

            final suppliers = _filter(all);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _summary(all),
                const SizedBox(height: 12),
                _searchField(),
                const SizedBox(height: 12),
                if (suppliers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Center(
                      child: Text(
                        'No suppliers found.',
                        style: AppTheme.body(size: 13),
                      ),
                    ),
                  )
                else
                  for (final supplier in suppliers) _supplierCard(supplier),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(List<_SupplierDue> all) {
    final total = all.fold<double>(0, (sum, s) => sum + s.totalDue);
    final lotCount = all.fold<int>(0, (sum, s) => sum + s.lots.length);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.outbox_outlined,
              color: AppColors.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total to pay suppliers',
                  style: AppTheme.body(size: 11, color: AppColors.textGrey),
                ),
                const SizedBox(height: 2),
                Text(
                  _currency(total),
                  style: AppTheme.heading(size: 20, color: AppColors.error),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${all.length} supplier${all.length == 1 ? '' : 's'}',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                  weight: FontWeight.w600,
                ),
              ),
              Text(
                '$lotCount lot${lotCount == 1 ? '' : 's'}',
                style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _search = value),
      style: AppTheme.body(size: 13),
      decoration: InputDecoration(
        hintText: 'Search supplier name or mobile number...',
        prefixIcon: const Icon(
          Icons.search,
          size: 20,
          color: AppColors.textGrey,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }

  Widget _supplierCard(_SupplierDue supplier) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: AppTheme.card(radius: 16),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text(
              supplier.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(size: 14),
            ),
            subtitle: Text(
              [
                if (supplier.mobile.isNotEmpty) supplier.mobile,
                '${supplier.lots.length} lot'
                    '${supplier.lots.length == 1 ? '' : 's'}',
                'since ${DateFormat('d MMM yyyy').format(supplier.oldestPurchase)}',
              ].join(' · '),
              style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _currency(supplier.totalDue),
                  style: AppTheme.heading(size: 14, color: AppColors.error),
                ),
                Text('Due', style: AppTheme.body(size: 9.5)),
              ],
            ),
            children: [
              for (final lot in supplier.lots) _lotRow(lot),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lotRow(TradingPurchase lot) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${lot.lotId} · ${lot.totalGoats} goats',
                  style: AppTheme.heading(size: 13),
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (lot.paymentStatus == 'Partial'
                      ? AppColors.warning
                      : AppColors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  lot.paymentStatus,
                  style: AppTheme.body(
                    size: 10,
                    weight: FontWeight.w700,
                    color: lot.paymentStatus == 'Partial'
                        ? AppColors.warning
                        : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Bought ${DateFormat('d MMM yyyy').format(lot.purchaseDate)}',
            style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
          ),
          const SizedBox(height: 8),
          _amountRow('Purchase amount', _currency(lot.purchaseAmount)),
          _amountRow('Paid', _currency(lot.paidAmount)),
          _amountRow(
            'Still to pay',
            _currency(lot.dueAmount),
            bold: true,
            color: AppColors.error,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _pay(lot),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Pay supplier'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(
      String label,
      String value, {
        bool bold = false,
        Color? color,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(size: 11.5, color: AppColors.textGrey),
            ),
          ),
          Text(
            value,
            style: AppTheme.body(
              size: 12,
              weight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}