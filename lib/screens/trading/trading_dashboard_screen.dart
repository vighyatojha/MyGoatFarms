import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/trading_summary_model.dart';
import '../../services/firestore_service.dart';
import '../../services/trading_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import 'purchase_goats/purchase_goats_wizard_screen.dart';

/// Trading Dashboard — Feature 1 of the Trading Module.
///
/// Task 2.1 — static layout: 7 summary cards + 4 quick actions.
/// Task 2.2 — cards stream from `TradingService.dashboardSummaryStream`;
///   only Wholesale Purchased and Pending Registrations are live in
///   Phase 1, the rest show honest zeros until later phases populate
///   them (no faked data).
/// Task 2.3 — Purchase Goats opens the wizard (placeholder until Task
///   3 builds it); Register Goats / Goat Stock / Sell Goat show a
///   "coming soon" toast rather than doing nothing.
class TradingDashboardScreen extends StatefulWidget {
  const TradingDashboardScreen({super.key});

  @override
  State<TradingDashboardScreen> createState() => _TradingDashboardScreenState();
}

class _TradingDashboardScreenState extends State<TradingDashboardScreen> {
  String? _farmId;
  bool _loadingFarm = true;

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

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature module coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  String _currency(num value) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _loadingFarm
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _farmId == null
            ? Column(
          children: [
            _header(),
            Expanded(
              child: FarmNotLinkedState(
                buttonColor: AppColors.primaryGreen,
                onRetry: () {
                  setState(() => _loadingFarm = true);
                  _loadFarm();
                },
              ),
            ),
          ],
        )
            : RefreshIndicator(
          color: AppColors.primaryGreen,
          onRefresh: _loadFarm,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _header(),
              const SizedBox(height: 16),
              StreamBuilder<TradingSummary>(
                stream: TradingService.instance.dashboardSummaryStream(_farmId!),
                builder: (context, snap) {
                  final summary = snap.data ?? TradingSummary.empty;
                  return _statGrid(summary, loading: !snap.hasData);
                },
              ),
              const SizedBox(height: 24),
              Text('Quick Actions', style: AppTheme.heading(size: 16)),
              const SizedBox(height: 12),
              _quickActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// Branded header — matches Finance Overview / Home's own header
  /// style rather than a bare AppBar title.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.tradingBlue.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.storefront_rounded, color: AppColors.tradingBlue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trading', style: AppTheme.heading(size: 18)),
                Text('Wholesale purchases & stock', style: AppTheme.body(size: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SUMMARY CARDS (Task 2.1 / 2.2)
  // --------------------------------------------------------------------------

  Widget _statGrid(TradingSummary summary, {required bool loading}) {
    final cards = <_TradingStatCardData>[
      _TradingStatCardData(
        icon: Icons.pets,
        label: 'Total Stock',
        value: '${summary.totalStock}',
        color: AppColors.primaryGreen,
      ),
      _TradingStatCardData(
        icon: Icons.shopping_cart_outlined,
        label: 'Wholesale Purchased',
        value: '${summary.wholesalePurchased}',
        color: AppColors.tradingBlue,
      ),
      _TradingStatCardData(
        icon: Icons.sell_outlined,
        label: 'Total Sold',
        value: '${summary.totalSold}',
        color: AppColors.success,
      ),
      _TradingStatCardData(
        icon: Icons.trending_up_rounded,
        label: 'Total Profit',
        value: _currency(summary.totalProfit),
        color: AppColors.warning,
      ),
      _TradingStatCardData(
        icon: Icons.pending_actions_outlined,
        label: 'Pending Registrations',
        value: '${summary.pendingRegistrations}',
        color: AppColors.error,
      ),
      _TradingStatCardData(
        icon: Icons.event_available_outlined,
        label: 'Booking',
        value: '${summary.booking}',
        color: AppColors.info,
      ),
      _TradingStatCardData(
        icon: Icons.local_shipping_outlined,
        label: 'Wait on Delivery',
        value: '${summary.waitOnDelivery}',
        color: AppColors.breedingPurple,
      ),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final second = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < cards.length ? 12 : 0),
          child: Row(
            children: [
              Expanded(child: _TradingStatCard(data: cards[i], loading: loading)),
              const SizedBox(width: 12),
              Expanded(child: second == null ? const SizedBox() : _TradingStatCard(data: second, loading: loading)),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  // --------------------------------------------------------------------------
  // QUICK ACTIONS (Task 2.3)
  // --------------------------------------------------------------------------

  Widget _quickActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _TradingQuickAction(
            icon: Icons.shopping_cart_outlined,
            label: 'Purchase\nGoats',
            color: AppColors.tradingBlue,
            onTap: () => Navigator.of(context).push(fastRoute(const PurchaseGoatsWizardScreen())),
          ),
          const SizedBox(width: 18),
          _TradingQuickAction(
            icon: Icons.how_to_reg_outlined,
            label: 'Register\nGoats',
            color: AppColors.primaryGreen,
            onTap: () => _comingSoon('Register Goats'),
          ),
          const SizedBox(width: 18),
          _TradingQuickAction(
            icon: Icons.inventory_2_outlined,
            label: 'Goat\nStock',
            color: AppColors.stockTeal,
            onTap: () => _comingSoon('Goat Stock'),
          ),
          const SizedBox(width: 18),
          _TradingQuickAction(
            icon: Icons.sell_outlined,
            label: 'Sell\nGoat',
            color: AppColors.warning,
            onTap: () => _comingSoon('Sell Goat'),
          ),
        ],
      ),
    );
  }
}

class _TradingStatCardData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TradingStatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _TradingStatCard extends StatelessWidget {
  final _TradingStatCardData data;
  final bool loading;

  const _TradingStatCard({required this.data, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: data.color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(loading ? '—' : data.value, style: AppTheme.heading(size: 18)),
          const SizedBox(height: 2),
          Text(data.label, style: AppTheme.body(size: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TradingQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TradingQuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.body(size: 10), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}