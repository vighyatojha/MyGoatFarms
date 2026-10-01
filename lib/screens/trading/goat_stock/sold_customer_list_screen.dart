import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/sale_model.dart';
import '../../../widgets/fast_route.dart';
import '../sale_receipt_screen.dart';

/// Total Sold — customer-wise sales list.
///
/// This screen combines completed sales of individually registered goats and
/// completed sales made directly from Purchase Lots. Sales are grouped by
/// customer so the Total Sold dashboard card opens into one customer-first
/// view instead of asking the user to choose between two different lists.
class SoldCustomerListScreen extends StatefulWidget {
  final String farmId;

  const SoldCustomerListScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<SoldCustomerListScreen> createState() => _SoldCustomerListScreenState();
}

class _SoldCustomerListScreenState extends State<SoldCustomerListScreen> {
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Sale>> _salesStream = FirebaseFirestore.instance
      .collection('farms')
      .doc(widget.farmId)
      .collection('sales')
      .snapshots()
      .map((snap) => snap.docs.map(Sale.fromDoc).toList());

  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  final Set<String> _expandedCustomers = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: StreamBuilder<List<Sale>>(
                stream: _salesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _errorState();

                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    );
                  }

                  final sold = snapshot.data!
                      .where((sale) => sale.isDelivered)
                      .toList();

                  final customers = _groupCustomers(sold);
                  return _body(customers);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Back',
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Total Sold',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(size: 19),
            ),
          ),
        ],
      ),
    );
  }

  List<_SoldCustomer> _groupCustomers(List<Sale> sales) {
    final grouped = <String, _SoldCustomer>{};

    for (final sale in sales) {
      final name = sale.customerName.trim().isEmpty
          ? 'Customer'
          : sale.customerName.trim();
      final mobile = sale.mobile.trim();
      final id = sale.customerId.trim();

      // Customer id is the primary key. Older records without one fall
      // back to mobile/name so they still group together correctly.
      final key = id.isNotEmpty
          ? 'id:$id'
          : mobile.isNotEmpty
          ? 'mobile:$mobile'
          : 'name:${name.toLowerCase()}';

      final customer = grouped.putIfAbsent(
        key,
            () => _SoldCustomer(
          key: key,
          name: name,
          mobile: mobile,
        ),
      );
      customer.sales.add(sale);
    }

    final customers = grouped.values.toList();

    for (final customer in customers) {
      customer.sales.sort((a, b) {
        final ad = a.deliveredOn ?? a.saleDate ?? DateTime(1970);
        final bd = b.deliveredOn ?? b.saleDate ?? DateTime(1970);
        return bd.compareTo(ad);
      });
    }

    customers.sort((a, b) {
      final ad = a.sales.first.deliveredOn ?? a.sales.first.saleDate ?? DateTime(1970);
      final bd = b.sales.first.deliveredOn ?? b.sales.first.saleDate ?? DateTime(1970);
      return bd.compareTo(ad);
    });

    return customers
        .where((customer) => customer.matches(_search))
        .toList();
  }

  Widget _body(List<_SoldCustomer> customers) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _summary(customers)),
        SliverToBoxAdapter(child: _searchBox()),
        if (customers.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(customers.isNotEmpty),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
            sliver: SliverList.separated(
              itemCount: customers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) => _customerCard(customers[index]),
            ),
          ),
      ],
    );
  }

  Widget _summary(List<_SoldCustomer> customers) {
    final goats = customers.fold<int>(
      0,
          (sum, customer) => sum + customer.goatCount,
    );
    final revenue = customers.fold<double>(
      0,
          (sum, customer) => sum + customer.salesValue,
    );
    final totalSales = customers.fold<int>(
      0,
          (sum, customer) => sum + customer.sales.length,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16).copyWith(
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(child: _stat('Customers', '${customers.length}')),
          Expanded(child: _stat('Goats sold', '$goats')),
          Expanded(child: _stat('Sales', '$totalSales')),
          Expanded(child: _stat('Value', _money.format(revenue))),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 9.5)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: AppTheme.heading(size: 14)),
        ),
      ],
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        height: 46,
        decoration: AppTheme.card(radius: 15).copyWith(
          border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.6),
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _search = value),
          textInputAction: TextInputAction.search,
          style: AppTheme.body(size: 12, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: 'Search customer, mobile or sale ID',
            hintStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColors.textGrey,
            ),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _searchController.clear();
                setState(() => _search = '');
              },
              icon: const Icon(
                Icons.close_rounded,
                size: 17,
                color: AppColors.textGrey,
              ),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _customerCard(_SoldCustomer customer) {
    final expanded = _expandedCustomers.contains(customer.key);

    return Container(
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedCustomers.remove(customer.key);
                } else {
                  _expandedCustomers.add(customer.key);
                }
              });
            },
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(customer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                customer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.heading(size: 15),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _goatCountPill(customer.goatCount),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          customer.mobile.isEmpty
                              ? '${customer.sales.length} sale${customer.sales.length == 1 ? '' : 's'}'
                              : '${customer.mobile} · ${customer.sales.length} sale${customer.sales.length == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 11, color: AppColors.textGrey),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            _infoChip(
                              Icons.sell_outlined,
                              _money.format(customer.salesValue),
                            ),
                            _infoChip(
                              Icons.payments_outlined,
                              'Received ${_money.format(customer.received)}',
                            ),
                            if (customer.pending > 0.01)
                              _infoChip(
                                Icons.hourglass_bottom_rounded,
                                'Pending ${_money.format(customer.pending)}',
                              )
                            else
                              _infoChip(
                                Icons.check_circle_outline_rounded,
                                'Fully collected',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _salesForCustomer(customer),
        ],
      ),
    );
  }

  Widget _salesForCustomer(_SoldCustomer customer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          for (var i = 0; i < customer.sales.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            _saleRow(customer.sales[i]),
          ],
        ],
      ),
    );
  }

  Widget _saleRow(Sale sale) {
    final saleValue = sale.billGoatSale;
    final date = sale.deliveredOn ?? sale.saleDate;
    final label = sale.isLotSale
        ? '${sale.lotDisplayId} · ${sale.lotQuantity} goat${sale.lotQuantity == 1 ? '' : 's'}'
        : '${sale.goatCount} goat${sale.goatCount == 1 ? '' : 's'} · ${sale.goatsReceiptLabel}';

    return Material(
      color: AppColors.paleGreen.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            fastRoute(
              SaleReceiptScreen(
                farmId: widget.farmId,
                saleId: sale.id,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(
                sale.isLotSale
                    ? Icons.layers_outlined
                    : Icons.sell_outlined,
                size: 19,
                color: sale.isLotSale
                    ? AppColors.tradingBlue
                    : AppColors.primaryGreen,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(size: 12.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        sale.id,
                        if (date != null) _dateFormat.format(date),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(saleValue),
                    style: AppTheme.heading(size: 12.5),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textGrey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(_SoldCustomer customer) {
    final initial = customer.name.trim().isEmpty
        ? '?'
        : customer.name.trim().substring(0, 1).toUpperCase();

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTheme.heading(size: 17, color: AppColors.success),
      ),
    );
  }

  Widget _goatCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pets_outlined, size: 10, color: AppColors.success),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textGrey),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textDark,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool hasAny) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sell_outlined,
                size: 25,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              hasAny ? 'No matching customers' : 'No completed sales',
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              hasAny
                  ? 'Try a different customer, mobile number or sale ID.'
                  : 'Completed Trading sales will appear here grouped by customer.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.error,
            ),
            const SizedBox(height: 10),
            Text(
              'Unable to load Total Sold',
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoldCustomer {
  final String key;
  final String name;
  final String mobile;
  final List<Sale> sales = <Sale>[];

  _SoldCustomer({
    required this.key,
    required this.name,
    required this.mobile,
  });

  int get goatCount => sales.fold<int>(0, (sum, sale) => sum + sale.goatCount);

  double get salesValue => sales.fold<double>(
    0,
        (sum, sale) => sum + sale.billGoatSale,
  );

  double get received => sales.fold<double>(
    0,
        (sum, sale) => sum + sale.billAmountPaid,
  );

  double get pending => sales.fold<double>(
    0,
        (sum, sale) => sum + sale.billBalanceDue,
  );

  bool matches(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final haystack = <String>[
      name,
      mobile,
      ...sales.map((sale) => sale.id),
      ...sales.map((sale) => sale.lotDisplayId),
      ...sales.map((sale) => sale.goatsReceiptLabel),
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }
}
