import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/sale_model.dart';
import '../../../widgets/fast_route.dart';
import '../sale_receipt_screen.dart';

/// Which kind of delivery history to show.
enum CompletedDeliveryKind { booking, waitForDelivery }

extension CompletedDeliveryKindX on CompletedDeliveryKind {
  /// Sale status a sale reaches once its delivery is done.
  String get completedStatus => this == CompletedDeliveryKind.booking
      ? Sale.statusDeliveryCompleted
      : Sale.statusPickupCompleted;

  String get label => this == CompletedDeliveryKind.booking
      ? 'Booking / Holding'
      : 'Wait for Delivery';

  String get emptyTitle => this == CompletedDeliveryKind.booking
      ? 'No completed bookings yet'
      : 'No completed deliveries yet';

  String get emptySubtitle => this == CompletedDeliveryKind.booking
      ? 'Bookings show up here, grouped by customer, once their goats '
      'have been delivered.'
      : 'Wait for Delivery sales show up here, grouped by customer, '
      'once their goats have been picked up.';
}

/// Open / Completed switch shown at the top of the Booking and Wait for
/// Delivery customer lists.
class DeliveryStatusToggle extends StatelessWidget {
  final bool showCompleted;
  final ValueChanged<bool> onChanged;

  const DeliveryStatusToggle({
    super.key,
    required this.showCompleted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTheme.body(
                size: 12,
                color: selected ? Colors.white : AppColors.textGrey,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            tab('Open', !showCompleted, () => onChanged(false)),
            tab('Completed', showCompleted, () => onChanged(true)),
          ],
        ),
      ),
    );
  }
}

/// One customer's completed deliveries.
class _CompletedCustomer {
  final String key;
  final String name;
  final String mobile;
  final List<Sale> sales;

  _CompletedCustomer({
    required this.key,
    required this.name,
    required this.mobile,
    required this.sales,
  });

  int get goatCount => sales.fold(0, (sum, s) => sum + s.goatCount);

  double get total =>
      sales.fold(0.0, (sum, s) => sum + s.billCustomerTotal);

  double get balanceDue =>
      sales.fold(0.0, (sum, s) => sum + s.billBalanceDue);

  DateTime? get lastDelivered {
    DateTime? latest;

    for (final s in sales) {
      final d = s.deliveredOn;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }

    return latest;
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return true;

    if (name.toLowerCase().contains(q) || mobile.contains(q)) return true;

    return sales.any((s) => s.id.toLowerCase().contains(q));
  }
}

/// Completed deliveries for Booking / Holding or Wait for Delivery,
/// grouped by customer. Tapping a delivery opens its receipt.
///
/// Embedded under the Open / Completed toggle of the matching customer
/// list. Uses a single equality filter on `status`, so no composite index
/// is needed — same pattern as the open-sales streams.
class CompletedDeliveriesView extends StatefulWidget {
  final String farmId;
  final CompletedDeliveryKind kind;

  const CompletedDeliveriesView({
    super.key,
    required this.farmId,
    required this.kind,
  });

  @override
  State<CompletedDeliveriesView> createState() =>
      _CompletedDeliveriesViewState();
}

class _CompletedDeliveriesViewState extends State<CompletedDeliveriesView> {
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Sale>> _stream = FirebaseFirestore.instance
      .collection('farms')
      .doc(widget.farmId)
      .collection('sales')
      .where('status', isEqualTo: widget.kind.completedStatus)
      .snapshots()
      .map((snap) => snap.docs.map(Sale.fromDoc).toList());

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  /// Customer keys the person has expanded.
  final Set<String> _expanded = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _keyFor(Sale sale) {
    var digits = sale.mobile.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) digits = digits.substring(digits.length - 10);

    if (digits.isNotEmpty) return 'm:$digits';

    final id = sale.customerId.trim();

    if (id.isNotEmpty) return 'c:$id';

    return 'n:${sale.customerName.trim().toLowerCase()}';
  }

  List<_CompletedCustomer> _group(List<Sale> sales) {
    final byCustomer = <String, List<Sale>>{};

    for (final sale in sales) {
      byCustomer.putIfAbsent(_keyFor(sale), () => <Sale>[]).add(sale);
    }

    DateTime stamp(Sale s) =>
        s.deliveredOn ??
            s.saleDate ??
            DateTime.fromMillisecondsSinceEpoch(0);

    final customers = <_CompletedCustomer>[];

    byCustomer.forEach((key, list) {
      list.sort((a, b) => stamp(b).compareTo(stamp(a)));

      final newest = list.first;

      customers.add(
        _CompletedCustomer(
          key: key,
          name: newest.customerName.trim().isEmpty
              ? 'Customer'
              : newest.customerName.trim(),
          mobile: newest.mobile.trim(),
          sales: list,
        ),
      );
    });

    customers.sort((a, b) {
      final x = a.lastDelivered ?? DateTime.fromMillisecondsSinceEpoch(0);
      final y = b.lastDelivered ?? DateTime.fromMillisecondsSinceEpoch(0);

      return y.compareTo(x);
    });

    return customers;
  }

  void _openReceipt(Sale sale) {
    Navigator.of(context).push(
      fastRoute(SaleReceiptScreen(farmId: widget.farmId, saleId: sale.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Sale>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return _errorState();

        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        }

        final customers = _group(snap.data!);
        final visible = customers.where((c) => c.matches(_search)).toList();

        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (customers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 1, 14, 10),
                  child: _searchBox(),
                ),
              ),
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(hasAny: customers.isNotEmpty),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) =>
                      _customerCard(visible[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  Widget _searchBox() {
    return Container(
      height: 46,
      decoration: AppTheme.card(radius: 15).copyWith(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
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
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CUSTOMER CARD
  // ---------------------------------------------------------------------------

  Widget _customerCard(_CompletedCustomer customer) {
    final open = _expanded.contains(customer.key);
    final count = customer.sales.length;
    final countLabel = count == 1 ? '1 delivery' : '$count deliveries';
    final last = customer.lastDelivered;

    return Container(
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(customer.key);
              } else {
                _expanded.add(customer.key);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(customer.name),
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
                              ? countLabel
                              : '${customer.mobile} · $countLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            size: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            if (last != null)
                              _infoChip(
                                Icons.event_available_outlined,
                                'Last ${_dateFormat.format(last)}',
                              ),
                            _infoChip(
                              Icons.payments_outlined,
                              'Total ${_money.format(customer.total)}',
                            ),
                            if (customer.balanceDue > 0)
                              _infoChip(
                                Icons.account_balance_wallet_outlined,
                                'Due ${_money.format(customer.balanceDue)}',
                                color: AppColors.warning,
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
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: AppColors.divider),
            for (final sale in customer.sales) _saleRow(sale),
          ],
        ],
      ),
    );
  }

  Widget _saleRow(Sale sale) {
    final delivered = sale.deliveredOn;
    final goats = sale.goatCount;
    final due = sale.billBalanceDue;

    return InkWell(
      onTap: () => _openReceipt(sale),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    delivered == null
                        ? 'Delivered'
                        : 'Delivered ${_dateFormat.format(delivered)}',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textDark,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$goats ${goats == 1 ? 'goat' : 'goats'} · '
                        '${_money.format(sale.billCustomerTotal)}'
                        '${sale.appliedDiscount > 0 ? ' · ${_money.format(sale.appliedDiscount)} discount' : ''}',
                    style: AppTheme.body(
                      size: 10.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              due > 0 ? 'Due ${_money.format(due)}' : 'Paid',
              style: AppTheme.body(
                size: 11,
                color: due > 0 ? AppColors.warning : AppColors.success,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String name) {
    final initial =
    name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

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
          const Icon(GoatIcons.paw, size: 10, color: AppColors.success),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, {Color? color}) {
    final tint = color ?? AppColors.textGrey;

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
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTheme.body(
              size: 10,
              color: color ?? AppColors.textDark,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY / ERROR
  // ---------------------------------------------------------------------------

  Widget _emptyState({required bool hasAny}) {
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
                Icons.task_alt_rounded,
                size: 25,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              hasAny ? 'No matching customers' : widget.kind.emptyTitle,
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              hasAny
                  ? 'Try a different name, mobile or sale ID.'
                  : widget.kind.emptySubtitle,
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
              'Unable to load completed deliveries',
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