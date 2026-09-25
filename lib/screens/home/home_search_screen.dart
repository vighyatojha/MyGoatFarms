import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/monthly_bill_model.dart';
import '../../models/palai_models.dart';
import '../../models/trading_purchase_model.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_billing_service.dart';
import '../../services/trading_service.dart';
import '../../widgets/fast_route.dart';
import '../customers/customer_profile_screen.dart';
import '../customers/monthly_bills_screen.dart';
import '../palai/customer_palai/goat_profile_screen.dart';
import '../trading/trading_dashboard_screen.dart';

/// Universal search opened from the Home screen's search bar.
///
/// Searches, client-side, across the four things the search bar's hint
/// text promises: Goat ID, Customer, Batch (Trading purchase) and
/// Invoice (Monthly bill). Each category subscribes to the same live
/// stream its own module already uses, so results stay in sync with the
/// rest of the app — this screen just filters and groups them.
///
/// There's no dedicated "purchase batch" detail screen anywhere in the
/// app yet, so tapping a Batch result opens the Trading Dashboard rather
/// than deep-linking into that specific purchase.
class HomeSearchScreen extends StatefulWidget {
  final String farmId;

  /// Pre-fills the search field with whatever the user had already typed
  /// in the Home screen's own search bar, so opening this screen doesn't
  /// throw that input away.
  final String initialQuery;

  const HomeSearchScreen({
    super.key,
    required this.farmId,
    this.initialQuery = '',
  });

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  late final TextEditingController _controller;
  String _query = '';

  List<PalaiGoat> _goats = [];
  List<PalaiCustomer> _customers = [];
  List<TradingPurchase> _purchases = [];
  List<MonthlyBill> _bills = [];

  bool _goatsReady = false;
  bool _customersReady = false;
  bool _purchasesReady = false;
  bool _billsReady = false;

  StreamSubscription<List<PalaiGoat>>? _goatsSub;
  StreamSubscription<List<PalaiCustomer>>? _customersSub;
  StreamSubscription<List<TradingPurchase>>? _purchasesSub;
  StreamSubscription<List<MonthlyBill>>? _billsSub;

  static const int _maxPerSection = 20;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _controller = TextEditingController(text: widget.initialQuery);
    _controller.addListener(() {
      final next = _controller.text.trim();
      if (next != _query) setState(() => _query = next);
    });

    _goatsSub = FirestoreService.instance.allActiveGoatsStream(widget.farmId).listen((goats) {
      if (!mounted) return;
      setState(() {
        _goats = goats;
        _goatsReady = true;
      });
    });

    _customersSub = FirestoreService.instance.customersStream(widget.farmId).listen((customers) {
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _customersReady = true;
      });
    });

    _purchasesSub = TradingService.instance.purchasesStream(widget.farmId).listen((purchases) {
      if (!mounted) return;
      setState(() {
        _purchases = purchases;
        _purchasesReady = true;
      });
    });

    _billsSub = MonthlyBillingService.instance.allBillsStream(widget.farmId).listen((bills) {
      if (!mounted) return;
      setState(() {
        _bills = bills;
        _billsReady = true;
      });
    });
  }

  @override
  void dispose() {
    _goatsSub?.cancel();
    _customersSub?.cancel();
    _purchasesSub?.cancel();
    _billsSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _isLoading =>
      !_goatsReady || !_customersReady || !_purchasesReady || !_billsReady;

  bool _matches(String haystack, String q) => haystack.toLowerCase().contains(q);

  List<PalaiGoat> get _goatResults {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    return _goats
        .where((g) =>
    _matches(g.tagNumber, q) ||
        _matches(g.goatCode, q) ||
        _matches(g.name, q) ||
        _matches(g.id, q))
        .take(_maxPerSection)
        .toList();
  }

  List<PalaiCustomer> get _customerResults {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    return _customers
        .where((c) => _matches(c.name, q) || _matches(c.mobileNumber, q))
        .take(_maxPerSection)
        .toList();
  }

  List<TradingPurchase> get _purchaseResults {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    return _purchases
        .where((p) =>
    _matches(p.sellerName, q) ||
        _matches(p.market, q) ||
        _matches(p.vehicleNumber, q) ||
        _matches(p.id, q))
        .take(_maxPerSection)
        .toList();
  }

  List<MonthlyBill> get _billResults {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    return _bills
        .where((b) => _matches(b.billNumber, q) || _matches(b.customerName, q))
        .take(_maxPerSection)
        .toList();
  }

  int get _totalResults =>
      _goatResults.length + _customerResults.length + _purchaseResults.length + _billResults.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchField(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Container(
              decoration: AppTheme.card(radius: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search Goat ID, Customer, Batch, Invoice...',
                  hintStyle: AppTheme.body(size: 12.5),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => _controller.clear(),
                  ),
                ),
                style: AppTheme.body(size: 13, color: AppColors.textDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return _buildMessage(
        icon: Icons.search_rounded,
        title: 'Search across your farm',
        subtitle: 'Look up a goat by tag, a customer by name or phone, '
            'a purchase batch, or an invoice number.',
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }

    if (_totalResults == 0) {
      return _buildMessage(
        icon: Icons.search_off_rounded,
        title: 'No results for "$_query"',
        subtitle: 'Try a different tag, name, phone number or bill number.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_goatResults.isNotEmpty) ..._buildSection('Goats', _goatResults.map(_goatTile)),
        if (_customerResults.isNotEmpty)
          ..._buildSection('Customers', _customerResults.map(_customerTile)),
        if (_purchaseResults.isNotEmpty)
          ..._buildSection('Batches', _purchaseResults.map(_purchaseTile)),
        if (_billResults.isNotEmpty) ..._buildSection('Invoices', _billResults.map(_billTile)),
      ],
    );
  }

  List<Widget> _buildSection(String title, Iterable<Widget> tiles) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
        child: Text(title, style: AppTheme.heading(size: 13)),
      ),
      ...tiles,
    ];
  }

  Widget _resultTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.card(radius: 14),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(title, style: AppTheme.body(size: 13.5, color: AppColors.textDark)),
        subtitle: Text(subtitle, style: AppTheme.body(size: 11.5, color: AppColors.textGrey)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textGrey, size: 18),
      ),
    );
  }

  Widget _goatTile(PalaiGoat g) {
    final tag = g.tagNumber.isNotEmpty ? g.tagNumber : g.goatCode;
    return _resultTile(
      icon: Icons.pets_rounded,
      color: AppColors.primaryGreen,
      title: g.name.isNotEmpty ? g.name : (tag.isNotEmpty ? tag : 'Goat'),
      subtitle: [
        if (tag.isNotEmpty) tag,
        if (g.breed.isNotEmpty) g.breed,
      ].join(' · '),
      onTap: () => Navigator.of(context)
          .push(fastRoute(GoatProfileScreen(farmId: widget.farmId, goat: g))),
    );
  }

  Widget _customerTile(PalaiCustomer c) {
    return _resultTile(
      icon: Icons.person_rounded,
      color: AppColors.info,
      title: c.name.isNotEmpty ? c.name : 'Customer',
      subtitle: c.mobileNumber,
      onTap: () => Navigator.of(context)
          .push(fastRoute(CustomerProfileScreen(customer: c, farmId: widget.farmId))),
    );
  }

  Widget _purchaseTile(TradingPurchase p) {
    return _resultTile(
      icon: Icons.local_shipping_outlined,
      color: AppColors.tradingBlue,
      title: p.sellerName.isNotEmpty ? p.sellerName : 'Purchase batch',
      subtitle: [
        if (p.market.isNotEmpty) p.market,
        '${p.totalGoats} goats',
      ].join(' · '),
      onTap: () => Navigator.of(context).push(fastRoute(const TradingDashboardScreen())),
    );
  }

  Widget _billTile(MonthlyBill b) {
    return _resultTile(
      icon: Icons.receipt_long_outlined,
      color: AppColors.warning,
      title: b.billNumber,
      subtitle: '${b.customerName} · ₹${b.totalDue.toStringAsFixed(0)} due',
      onTap: () => Navigator.of(context).push(fastRoute(MonthlyBillsScreen(
        farmId: widget.farmId,
        customerId: b.customerId,
        customerName: b.customerName,
      ))),
    );
  }

  Widget _buildMessage({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: AppColors.textGrey),
            const SizedBox(height: 12),
            Text(title, style: AppTheme.heading(size: 15), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle,
                style: AppTheme.body(size: 12.5, color: AppColors.textGrey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}