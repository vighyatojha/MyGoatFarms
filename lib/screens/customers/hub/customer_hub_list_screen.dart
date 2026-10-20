import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/customer_account.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/customer_account_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/payment_reminder_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/lot_origin_card.dart';
import '../../finance/credit_customers_screen.dart';
import '../../trading/goat_stock/goat_stock_detail_screen.dart';
import '../../trading/sale_receipt_screen.dart';
import 'customer_hub_profile_screen.dart';
import 'customer_sales_history_screen.dart';
import 'hub_widgets.dart';
import 'sale_money_widgets.dart';

/// Customers, opened from the Trading dashboard: every person the farm
/// trades with (Palai customers and goat buyers), one row per mobile
/// number.
///
/// Trading money only (no Palai bills or payments). Read-only. Totals come
/// from [CustomerAccountBook], the same calculation the account screen
/// uses: total sale pending = Finance ▸ Trading ▸ Receivable. Due at
/// delivery is an estimate for open bookings and is not in Finance until
/// the goats are delivered.
///
/// FOCUSED MODE ([focus] set) — how the dashboards open Wait on Delivery,
/// Booking & Holding and Sales: the same screen, showing ONLY that group's
/// customers (no filter chips). Tapping a customer always opens their
/// profile ([CustomerHubProfileScreen]). From the profile:
///   * Wait on Delivery / Booking & Holding → their goats in that section
///     (goat details, health / weight / photo updates, Complete →
///     checkout);
///   * Purchase history / Trading ledger → sales and money.
enum HubFocus { waitOnDelivery, bookingHolding, sales }

/// SALES focus: what the list shows.
enum _SalesTab { customers, sales, goats }

/// SALES focus: when the sale was completed.
enum _SalesPeriod { all, today, week, month }

/// SALES focus: paid in full, or money still due.
enum _SalesPay { all, paid, pending }

extension HubFocusInfo on HubFocus {
  String get title {
    switch (this) {
      case HubFocus.waitOnDelivery:
        return 'Wait on Delivery';
      case HubFocus.bookingHolding:
        return 'Booking & Holding';
      case HubFocus.sales:
        return 'Sales';
    }
  }

  IconData get icon {
    switch (this) {
      case HubFocus.waitOnDelivery:
        return Icons.local_shipping_outlined;
      case HubFocus.bookingHolding:
        return Icons.event_available_outlined;
      case HubFocus.sales:
        return Icons.sell_outlined;
    }
  }

  Color get color {
    switch (this) {
      case HubFocus.waitOnDelivery:
        return HubColors.wait;
      case HubFocus.bookingHolding:
        return HubColors.holding;
      case HubFocus.sales:
        return AppColors.error;
    }
  }
}

class CustomerHubListScreen extends StatefulWidget {
  const CustomerHubListScreen({
    super.key,
    required this.farmId,
    this.initialFilter = CustomerFilter.all,
    this.focus,
  });

  final String farmId;
  final CustomerFilter initialFilter;

  /// Show only this group's customers (see class doc). Null = every
  /// customer with the filter chips, the original screen.
  final HubFocus? focus;

  @override
  State<CustomerHubListScreen> createState() => _CustomerHubListScreenState();
}

class _CustomerHubListScreenState extends State<CustomerHubListScreen> {
  late final Stream<CustomerAccountBook> _book =
  CustomerAccountService.instance.bookStream(widget.farmId);

  /// Every sale — only read in the Sales focus, to count each customer's
  /// sold goats.
  late final Stream<List<Sale>>? _sales = widget.focus == HubFocus.sales
      ? CustomerAccountService.instance.allSalesStream(widget.farmId)
      : null;

  /// Every trading goat — only read in the Sales focus, for All goats.
  late final Stream<List<Goat>>? _goats = widget.focus == HubFocus.sales
      ? GoatService.instance.goatsStream(widget.farmId)
      : null;

  // SALES focus: tab, filters, and the customer picked with "Sold goats".
  _SalesTab _salesTab = _SalesTab.customers;
  _SalesPeriod _period = _SalesPeriod.all;
  _SalesPay _pay = _SalesPay.all;
  String? _customerKey;
  String _customerName = '';

  HubFocus? get _focus => widget.focus;

  final TextEditingController _search = TextEditingController();
  late CustomerFilter _filter = widget.initialFilter;
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  /// Every customer row opens the customer's profile. In Wait on
  /// Delivery / Booking & Holding the goats are reached from there (the
  /// profile's entry for that section), never straight from this list.
  void _open(CustomerAccount account) {
    Navigator.of(context).push(
      fastRoute(
        CustomerHubProfileScreen(
          farmId: widget.farmId,
          personKey: account.key,
          initialName: account.name,
        ),
      ),
    );
  }

  void _openFinanceCredit() {
    Navigator.of(context).push(
      fastRoute(CreditCustomersScreen(farmId: widget.farmId)),
    );
  }

  Future<void> _remind(CustomerAccount account) async {
    final reminders = PaymentReminderService.instance;
    final days = await reminders.loadDays();
    final ok = await reminders.openWhatsApp(
      mobile: account.mobile,
      message: reminders.buildMessage(
        customerName: account.name,
        pendingAmount: account.goatSaleCredit,
        days: days,
      ),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't open WhatsApp. Check the mobile number."),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _header(),
            ),
            Expanded(
              child: StreamBuilder<CustomerAccountBook>(
                stream: _book,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return HubMessage(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load customers",
                      subtitle: 'Check your connection and open this screen again.',
                    );
                  }
                  if (!snap.hasData) return const _ListSkeleton();
                  final sales = _sales;
                  if (sales == null) return _body(snap.data!);
                  return StreamBuilder<List<Sale>>(
                    stream: sales,
                    builder: (context, saleSnap) {
                      if (!saleSnap.hasData) return const _ListSkeleton();
                      return StreamBuilder<List<Goat>>(
                        stream: _goats,
                        builder: (context, goatSnap) => _salesBody(
                          snap.data!,
                          saleSnap.data!,
                          goatSnap.data ?? const <Goat>[],
                        ),
                      );
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

  Widget _header() {
    return Row(
      children: [
        HubHeaderButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _searching
              ? TextField(
            controller: _search,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Name or mobile',
              isDense: true,
              contentPadding:
              EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          )
              : Row(
            children: [
              HubIconBox(
                icon: _focus?.icon ?? Icons.groups_2_outlined,
                color: _focus?.color ?? HubColors.customers,
                size: 38,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _focus?.title ?? 'Customers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        HubHeaderButton(
          icon: _searching ? Icons.close_rounded : Icons.search_rounded,
          tooltip: _searching ? 'Close search' : 'Search',
          onTap: _toggleSearch,
        ),
      ],
    );
  }

  /// Finds whose sale it is: the account key a sale is filed under
  /// (mobile first, then trading customer record, then name).
  String? Function(Sale sale) _ownerOf(CustomerAccountBook book) {
    final byMobile = <String, String>{};
    final byTradingId = <String, String>{};
    final byName = <String, String>{};

    for (final a in book.accounts) {
      final digits = CustomerAccountBook.digitsOf(a.mobile);
      if (digits.isNotEmpty) byMobile[digits] = a.key;
      for (final t in a.tradingCustomers) {
        byTradingId[t.id] = a.key;
      }
      byName[a.name.trim().toLowerCase()] = a.key;
    }

    return (sale) {
      final digits = CustomerAccountBook.digitsOf(sale.mobile);
      return (digits.isNotEmpty ? byMobile[digits] : null) ??
          byTradingId[sale.customerId] ??
          byName[sale.customerName.trim().toLowerCase()];
    };
  }

  bool _inFocus(CustomerAccount a, Map<String, int>? sold) {
    switch (_focus) {
      case null:
        return _filter.test(a);
      case HubFocus.waitOnDelivery:
        return a.waitGoats > 0;
      case HubFocus.bookingHolding:
        return a.holdingGoats > 0;
      case HubFocus.sales:
        return (sold?[a.key] ?? 0) > 0;
    }
  }

  Widget _body(CustomerAccountBook book, {Map<String, int>? sold}) {
    final visible = book.accounts
        .where((a) => _inFocus(a, sold))
        .where((a) => a.matches(_query))
        .toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _summary(book, sold: sold),
        const SizedBox(height: 14),
        if (_focus == null) ...[
          _chips(book),
          const SizedBox(height: 12),
        ] else ...[
          _focusBar(visible.length),
          const SizedBox(height: 12),
        ],
        if (visible.isEmpty)
          HubMessage(
            icon: Icons.person_search_outlined,
            title: _query.isNotEmpty
                ? 'No customer matches "${_query.trim()}"'
                : 'No customers in this filter',
            action: (_focus != null && _query.isEmpty) ||
                (_filter == CustomerFilter.all && _query.isEmpty)
                ? null
                : TextButton(
              onPressed: () => setState(() {
                _filter = CustomerFilter.all;
                _search.clear();
                _query = '';
              }),
              child: const Text('Show all'),
            ),
          )
        else
          for (final account in visible) ...[
            _CustomerRow(
              account: account,
              soldGoats: sold?[account.key],
              onTap: () => _open(account),
              onRemind: () => unawaited(_remind(account)),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  // ===========================================================================
  // SALES FOCUS — tabs (Customers / All sales / All goats) + filters
  // ===========================================================================

  /// A completed sale that counts as a goat sale (not a Palai transfer).
  bool _isGoatSale(Sale sale) =>
      sale.isDelivered && sale.status != Sale.statusTransferredToPalai;

  /// When the sale was completed (delivered), or made.
  DateTime _saleWhen(Sale sale) =>
      sale.deliveryCompletedAt ?? sale.saleDate ?? DateTime(2000);

  bool _inPeriod(Sale sale) {
    if (_period == _SalesPeriod.all) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final when = _saleWhen(sale);
    switch (_period) {
      case _SalesPeriod.all:
        return true;
      case _SalesPeriod.today:
        return !when.isBefore(today);
      case _SalesPeriod.week:
        return !when.isBefore(today.subtract(const Duration(days: 6)));
      case _SalesPeriod.month:
        return when.year == now.year && when.month == now.month;
    }
  }

  bool _isPaid(Sale sale) => sale.billBalanceDue <= 0.009;

  bool _inPay(Sale sale) {
    switch (_pay) {
      case _SalesPay.all:
        return true;
      case _SalesPay.paid:
        return _isPaid(sale);
      case _SalesPay.pending:
        return !_isPaid(sale);
    }
  }

  int _goatsIn(Sale sale) {
    final goats = sale.isLotSale ? sale.lotQuantity : sale.goatIds.length;
    return goats <= 0 ? 1 : goats;
  }

  String _saleType(Sale sale) {
    if (sale.isBooking) return 'Booking';
    if (sale.isWaitForDelivery) return 'Wait on Delivery';
    if (sale.isLotSale) return 'Lot sale';
    return 'Deliver now';
  }

  bool _saleMatches(Sale sale) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return sale.id.toLowerCase().contains(q) ||
        sale.customerName.toLowerCase().contains(q) ||
        sale.mobile.contains(q) ||
        sale.goatIds.any((id) => id.toLowerCase().contains(q)) ||
        (sale.isLotSale && sale.lotDisplayId.toLowerCase().contains(q));
  }

  Widget _salesBody(
      CustomerAccountBook book,
      List<Sale> allSales,
      List<Goat> goats,
      ) {
    final ownerOf = _ownerOf(book);

    // Every filter except the customer picked with "Sold goats".
    final filtered = allSales
        .where(_isGoatSale)
        .where(_inPeriod)
        .where(_inPay)
        .toList()
      ..sort((a, b) => _saleWhen(b).compareTo(_saleWhen(a)));

    final sold = <String, int>{};
    for (final sale in filtered) {
      final key = ownerOf(sale);
      if (key == null) continue;
      sold[key] = (sold[key] ?? 0) + _goatsIn(sale);
    }

    final picked = _customerKey;
    final sales = filtered
        .where((sale) => picked == null || ownerOf(sale) == picked)
        .where(_saleMatches)
        .toList();

    final customers = book.accounts
        .where((a) => (sold[a.key] ?? 0) > 0)
        .where((a) => a.matches(_query))
        .toList();

    final goatsById = {for (final g in goats) g.id: g};
    final goatCount = sales.fold<int>(0, (t, s) => t + _goatsIn(s));

    final count = switch (_salesTab) {
      _SalesTab.customers => customers.length,
      _SalesTab.sales => sales.length,
      _SalesTab.goats => goatCount,
    };

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _summary(book, sold: sold),
        const SizedBox(height: 14),
        _salesTabs(),
        const SizedBox(height: 10),
        _salesFilters(),
        if (picked != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Customer: $_customerName'),
              onDeleted: () => setState(() {
                _customerKey = null;
                _customerName = '';
              }),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _focusBar(count),
        const SizedBox(height: 12),
        if (count == 0)
          HubMessage(
            icon: Icons.search_off_rounded,
            title: _query.isNotEmpty
                ? 'Nothing matches "${_query.trim()}"'
                : 'No sales in this filter',
            action: _period == _SalesPeriod.all &&
                _pay == _SalesPay.all &&
                picked == null &&
                _query.isEmpty
                ? null
                : TextButton(
              onPressed: () => setState(() {
                _period = _SalesPeriod.all;
                _pay = _SalesPay.all;
                _customerKey = null;
                _customerName = '';
                _search.clear();
                _query = '';
              }),
              child: const Text('Clear filters'),
            ),
          )
        else if (_salesTab == _SalesTab.customers)
          for (final account in customers) ...[
            _CustomerRow(
              account: account,
              soldGoats: sold[account.key],
              onTap: () => _open(account),
              onRemind: () => unawaited(_remind(account)),
              footer: _customerShortcuts(account),
            ),
            const SizedBox(height: 10),
          ]
        else if (_salesTab == _SalesTab.sales)
            for (final sale in sales) ...[
              _saleRow(sale),
              const SizedBox(height: 8),
            ]
          else
            for (final sale in sales) ...[
              if (sale.isLotSale)
                _lotGoatsRow(sale)
              else
                for (final id in sale.goatIds) _soldGoatRow(sale, id, goatsById[id]),
            ],
      ],
    );
  }

  Widget _salesTabs() {
    Widget tab(_SalesTab value, String label, IconData icon) {
      final selected = _salesTab == value;
      return Expanded(
        child: Material(
          color: selected ? AppColors.textDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _salesTab = value),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.textDark : AppColors.divider,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : AppColors.textGrey,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(_SalesTab.customers, 'Customers', Icons.groups_2_outlined),
        const SizedBox(width: 6),
        tab(_SalesTab.sales, 'All sales', Icons.receipt_long_outlined),
        const SizedBox(width: 6),
        tab(_SalesTab.goats, 'All goats', GoatIcons.paw),
      ],
    );
  }

  Widget _salesFilters() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(onTap),
          labelStyle: AppTheme.body(
            size: 11,
            weight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textDark,
          ),
          selectedColor: AppColors.darkGreen,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: selected ? AppColors.darkGreen : AppColors.divider,
          ),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All time', _period == _SalesPeriod.all,
                  () => _period = _SalesPeriod.all),
          chip('Today', _period == _SalesPeriod.today,
                  () => _period = _SalesPeriod.today),
          chip('This week', _period == _SalesPeriod.week,
                  () => _period = _SalesPeriod.week),
          chip('This month', _period == _SalesPeriod.month,
                  () => _period = _SalesPeriod.month),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.only(right: 6),
            color: AppColors.divider,
          ),
          chip('Paid & pending', _pay == _SalesPay.all,
                  () => _pay = _SalesPay.all),
          chip('Paid', _pay == _SalesPay.paid, () => _pay = _SalesPay.paid),
          chip('Pending', _pay == _SalesPay.pending,
                  () => _pay = _SalesPay.pending),
        ],
      ),
    );
  }

  /// Profile, Purchases and Sold goats, under a customer in Sales.
  Widget _customerShortcuts(CustomerAccount account) {
    Widget button(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 15),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkGreen,
            side: const BorderSide(color: AppColors.divider),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(Icons.person_outline_rounded, 'Profile', () => _open(account)),
        const SizedBox(width: 6),
        button(
          Icons.shopping_bag_outlined,
          'Purchases',
              () => Navigator.of(context).push(
            fastRoute(
              CustomerSalesHistoryScreen(
                farmId: widget.farmId,
                personKey: account.key,
                customerName: account.name,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        button(
          GoatIcons.paw,
          'Sold goats',
              () => setState(() {
            _customerKey = account.key;
            _customerName = account.name;
            _salesTab = _SalesTab.goats;
          }),
        ),
      ],
    );
  }

  void _openReceipt(Sale sale) {
    Navigator.of(context).push(
      fastRoute(SaleReceiptScreen(farmId: widget.farmId, saleId: sale.id)),
    );
  }

  Widget _saleRow(Sale sale) {
    final paid = _isPaid(sale);
    final goats = _goatsIn(sale);

    return HubCard(
      onTap: () => _openReceipt(sale),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const HubIconBox(
            icon: Icons.receipt_long_outlined,
            color: AppColors.tradingBlue,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sale.id} · ${sale.customerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 13.5),
                ),
                Text(
                  '${_saleType(sale)} · ${saleDay(_saleWhen(sale))} · '
                      '$goats goat${goats == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11),
                ),
                if (sale.isLotSale)
                  LotIdText(
                    farmId: widget.farmId,
                    lotDocId: sale.lotDocId,
                    style: AppTheme.body(size: 10.5, color: AppColors.info),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hubMoney(sale.billCustomerTotal),
                style: AppTheme.heading(size: 13.5),
              ),
              const SizedBox(height: 4),
              paid
                  ? const HubPill('Paid', AppColors.success)
                  : HubPill(
                'Due ${hubMoney(sale.billBalanceDue)}',
                HubColors.owes,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _soldGoatRow(Sale sale, String goatId, Goat? goat) {
    final photo = goat?.photo;
    final details = [
      if (goat != null && goat.breed.trim().isNotEmpty) goat.breed.trim(),
      if (goat != null && goat.weight > 0)
        '${goat.weight.toStringAsFixed(1)} kg',
      if (goat != null && goat.currentAgeMonths > 0) goat.age,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HubCard(
        onTap: goat == null
            ? () => _openReceipt(sale)
            : () => Navigator.of(context).push(
          fastRoute(
            GoatStockDetailScreen(farmId: widget.farmId, goat: goat),
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photo != null
                  ? Image.memory(photo, width: 44, height: 44, fit: BoxFit.cover)
                  : Container(
                width: 44,
                height: 44,
                color: AppColors.error.withValues(alpha: 0.08),
                child: const Icon(GoatIcons.paw,
                    size: 18, color: AppColors.error),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goatId, style: AppTheme.heading(size: 13)),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10.5),
                    ),
                  if (goat != null && goat.purchaseId.trim().isNotEmpty)
                    LotIdText(
                      farmId: widget.farmId,
                      lotDocId: goat.purchaseId,
                      style: AppTheme.body(size: 10.5, color: AppColors.info),
                    ),
                  Text(
                    '${sale.customerName} · ${sale.id} · '
                        '${saleDay(_saleWhen(sale))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5),
                  ),
                ],
              ),
            ),
            if (!_isPaid(sale))
              HubPill('Due', HubColors.owes),
          ],
        ),
      ),
    );
  }

  /// A lot sale's goats are not registered: one row for the lot.
  Widget _lotGoatsRow(Sale sale) {
    final goats = _goatsIn(sale);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HubCard(
        onTap: () => _openReceipt(sale),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const HubIconBox(
              icon: Icons.layers_outlined,
              color: AppColors.tradingBlue,
              size: 44,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$goats goat${goats == 1 ? '' : 's'} from a lot',
                    style: AppTheme.heading(size: 13),
                  ),
                  LotIdText(
                    farmId: widget.farmId,
                    lotDocId: sale.lotDocId,
                    style: AppTheme.body(size: 10.5, color: AppColors.info),
                  ),
                  Text(
                    '${sale.customerName} · ${sale.id} · '
                        '${saleDay(_saleWhen(sale))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5),
                  ),
                ],
              ),
            ),
            if (!_isPaid(sale))
              HubPill('Due', HubColors.owes),
          ],
        ),
      ),
    );
  }

  /// The single chip shown in a focused list (in place of the filters).
  Widget _focusBar(int count) {
    final focus = _focus!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: ShapeDecoration(
          color: focus.color,
          shape: const StadiumBorder(),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            '${focus.title}  $count',
            style: AppTheme.body(
              size: 11.5,
              weight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  /// The figures at the top follow the screen: the whole customer book on
  /// the main Customers screen (Palai customers and their goats included),
  /// but on a focused screen ONLY that group — e.g. Wait on Delivery counts
  /// just the customers with goats waiting and just those goats, never
  /// Palai boarding goats. The Finance receivable line below always stays
  /// farm-wide, so its Matches / Check stays a true reconciliation.
  Widget _summary(CustomerAccountBook book, {Map<String, int>? sold}) {
    const divider = Divider(height: 20, color: AppColors.divider);

    final focus = _focus;
    final scope = focus == null
        ? book.accounts
        : book.accounts.where((a) => _inFocus(a, sold)).toList();

    int sumGoats(int Function(CustomerAccount a) of) =>
        scope.fold<int>(0, (t, a) => t + of(a));
    double sumMoney(double Function(CustomerAccount a) of) =>
        Sale.roundMoney(scope.fold<double>(0, (t, a) => t + of(a)));

    final (String goatLabel, int goats, double due) = switch (focus) {
      null => (
      'Goats with farm',
      book.goatsWithFarm,
      book.totalDueAtDelivery,
      ),
      HubFocus.waitOnDelivery => (
      'Goats waiting',
      sumGoats((a) => a.waitGoats),
      sumMoney((a) => a.waitDue),
      ),
      HubFocus.bookingHolding => (
      'Goats on hold',
      sumGoats((a) => a.holdingGoats),
      sumMoney((a) => a.holdingDue),
      ),
      HubFocus.sales => (
      'Goats sold',
      scope.fold<int>(0, (t, a) => t + (sold?[a.key] ?? 0)),
      sumMoney((a) => a.dueAtDelivery),
      ),
    };

    final pending = focus == null
        ? book.totalSalePending
        : sumMoney((a) => a.goatSaleCredit);

    return HubCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Customers',
                  value: '${scope.length}',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: goatLabel,
                  value: '$goats',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Sale pending',
                  value: hubMoney(pending),
                  color: pending > 0 ? HubColors.owes : AppColors.textDark,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Due on open bookings (est.)',
                  value: hubMoney(due),
                  color: due > 0 ? HubColors.estimate : AppColors.textDark,
                ),
              ),
            ],
          ),
          divider,
          _SummaryLine(
            label: 'Trading receivable in Finance',
            value: hubMoney(book.allGoatSaleCredit),
            trailing: book.isReconciled
                ? const HubPill('Matches', AppColors.success)
                : const HubPill('Check', AppColors.warning),
            onTap: _openFinanceCredit,
          ),
          if (!book.isReconciled)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Sale pending doesn't match Finance. Don't take payments from here until this is fixed.",
                      style: AppTheme.body(size: 10, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTER CHIPS
  // ---------------------------------------------------------------------------

  Widget _chips(CustomerAccountBook book) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: CustomerFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = CustomerFilter.values[i];
          final selected = filter == _filter;
          return Material(
            color: selected ? AppColors.primaryGreen : Colors.white,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _filter = filter),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    '${filter.label}  ${book.countFor(filter)}',
                    style: AppTheme.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// ROW
// =============================================================================

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.account,
    required this.onTap,
    required this.onRemind,
    this.soldGoats,
    this.footer,
  });

  final CustomerAccount account;

  /// Shown under the row (the Sales focus' shortcuts).
  final Widget? footer;

  /// Goats sold to this customer (Sales focus only).
  final int? soldGoats;
  final VoidCallback onTap;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[
      if ((soldGoats ?? 0) > 0) HubPill('Sold $soldGoats', AppColors.error),
      if (account.waitGoats > 0) HubPill('Wait ${account.waitGoats}', HubColors.wait),
      if (account.holdingGoats > 0)
        HubPill('Holding ${account.holdingGoats}', HubColors.holding),
      if (account.palaiGoats > 0) HubPill('Palai ${account.palaiGoats}', HubColors.palai),
    ];

    final row = Row(
      children: [
        HubAvatar(name: account.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(size: 14),
              ),
              Text(
                account.mobile.trim().isEmpty ? 'No mobile' : account.mobile,
                maxLines: 1,
                style: AppTheme.body(size: 11),
              ),
              if (pills.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: pills),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            HubNetText(net: account.net),
            if (account.owes && account.hasMobile) ...[
              const SizedBox(height: 6),
              Tooltip(
                message: 'Send WhatsApp reminder',
                child: InkResponse(
                  onTap: onRemind,
                  radius: 22,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_outlined,
                      size: 16,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );

    final extra = footer;

    return HubCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: extra == null
          ? row
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [row, const SizedBox(height: 10), extra],
      ),
    );
  }
}

// =============================================================================
// SMALL PIECES
// =============================================================================

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.color = AppColors.textDark,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 11)),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, style: AppTheme.heading(size: 19, color: color)),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTheme.body(size: 12)),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
            Text(value, style: AppTheme.heading(size: 13)),
            SizedBox(
              width: 22,
              child: onTap == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        HubBone(height: 170),
        SizedBox(height: 14),
        HubBone(height: 34, radius: 20),
        SizedBox(height: 12),
        HubBone(height: 78),
        SizedBox(height: 10),
        HubBone(height: 78),
        SizedBox(height: 10),
        HubBone(height: 78),
      ],
    );
  }
}