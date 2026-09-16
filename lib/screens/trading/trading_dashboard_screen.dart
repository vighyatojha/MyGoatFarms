import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/trading_purchase_model.dart';
import '../../models/trading_summary_model.dart';
import '../../services/firestore_service.dart';
import '../../services/trading_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import 'purchase_goats/complete_receiving_screen.dart';
import 'purchase_goats/purchase_goats_wizard_screen.dart';

/// Trading Dashboard.
///
/// Current Trading features:
/// - Trading overview
/// - Purchase Goats
/// - Pending Receiving
/// - Complete Receiving
///
/// This screen intentionally contains no forced null assertions.
/// The farm ID is loaded asynchronously and is captured locally before
/// creating any Firestore streams.
class TradingDashboardScreen extends StatefulWidget {
  const TradingDashboardScreen({
    super.key,
  });

  @override
  State<TradingDashboardScreen> createState() =>
      _TradingDashboardScreenState();
}

class _TradingDashboardScreenState
    extends State<TradingDashboardScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  String? _farmLoadError;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  // ===========================================================================
  // FARM
  // ===========================================================================

  Future<void> _loadFarm() async {
    if (mounted) {
      setState(() {
        _loadingFarm = true;
        _farmLoadError = null;
      });
    }

    try {
      final id =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId =
        id == null || id.trim().isEmpty ? null : id.trim();
        _loadingFarm = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _farmId = null;
        _loadingFarm = false;
        _farmLoadError = e.toString();
      });
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(value);
  }

  void _comingSoon(String feature) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature module coming soon',
        ),
        backgroundColor: AppColors.darkGreen,
      ),
    );
  }

  // ===========================================================================
  // COMPLETE RECEIVING
  // ===========================================================================

  Future<void> _openCompleteReceiving(
      TradingPurchase purchase,
      ) async {
    final farmId = _farmId;

    if (farmId == null || farmId.isEmpty) {
      return;
    }

    final result =
    await Navigator.of(context).push<TradingPurchase>(
      MaterialPageRoute<TradingPurchase>(
        builder: (_) {
          return CompleteReceivingScreen(
            farmId: farmId,
            purchase: purchase,
          );
        },
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Receiving completed successfully.',
        ),
        backgroundColor: AppColors.darkGreen,
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final farmId = _farmId;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _buildBody(farmId),
      ),
    );
  }

  Widget _buildBody(String? farmId) {
    if (_loadingFarm) {
      return Column(
        children: [
          _header(),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryGreen,
              ),
            ),
          ),
        ],
      );
    }

    if (farmId == null || farmId.isEmpty) {
      return Column(
        children: [
          _header(),
          Expanded(
            child: FarmNotLinkedState(
              buttonColor: AppColors.primaryGreen,
              onRetry: _loadFarm,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _loadFarm,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          28,
        ),
        children: [
          _header(),

          const SizedBox(height: 20),

          _summarySection(farmId),

          const SizedBox(height: 24),

          _sectionHeader(
            title: 'Pending Receiving',
            icon: Icons.local_shipping_outlined,
          ),

          const SizedBox(height: 10),

          _pendingReceivingSection(farmId),

          const SizedBox(height: 24),

          _sectionHeader(
            title: 'Quick Actions',
            icon: Icons.flash_on_outlined,
          ),

          const SizedBox(height: 12),

          _quickActions(),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _summarySection(String farmId) {
    return StreamBuilder<TradingSummary>(
      stream: TradingService.instance.dashboardSummaryStream(
        farmId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _summaryError();
        }

        final summary =
            snapshot.data ?? TradingSummary.empty;

        return _statGrid(
          summary,
          loading:
          snapshot.connectionState ==
              ConnectionState.waiting &&
              !snapshot.hasData,
        );
      },
    );
  }

  Widget _summaryError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Unable to load the Trading summary.',
              style: AppTheme.body(size: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        4,
        4,
        4,
        0,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color:
              AppColors.primaryGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.primaryGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Trading',
                  style: AppTheme.heading(
                    size: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Wholesale purchases & stock',
                  style: AppTheme.body(
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION HEADER
  // ===========================================================================

  Widget _sectionHeader({
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: AppColors.primaryGreen,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTheme.heading(
            size: 16,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // STAT GRID
  // ===========================================================================

  Widget _statGrid(
      TradingSummary summary, {
        required bool loading,
      }) {
    final cards = <_TradingStatCardData>[
      _TradingStatCardData(
        icon: Icons.pets,
        label: 'Total Stock',
        value: '${summary.totalStock}',
      ),
      _TradingStatCardData(
        icon: Icons.shopping_cart_outlined,
        label: 'Wholesale Purchased',
        value: '${summary.wholesalePurchased}',
      ),
      _TradingStatCardData(
        icon: Icons.sell_outlined,
        label: 'Total Sold',
        value: '${summary.totalSold}',
      ),
      _TradingStatCardData(
        icon: Icons.trending_up_rounded,
        label: 'Total Profit',
        value: _currency(summary.totalProfit),
      ),
      _TradingStatCardData(
        icon: Icons.pending_actions_outlined,
        label: 'Pending Registrations',
        value: '${summary.pendingRegistrations}',
      ),
      _TradingStatCardData(
        icon: Icons.event_available_outlined,
        label: 'Booking',
        value: '${summary.booking}',
      ),
      _TradingStatCardData(
        icon: Icons.local_shipping_outlined,
        label: 'Wait on Delivery',
        value: '${summary.waitOnDelivery}',
      ),
    ];

    final rows = <Widget>[];

    for (var i = 0; i < cards.length; i += 2) {
      final first = cards[i];

      final second =
      i + 1 < cards.length
          ? cards[i + 1]
          : null;

      rows.add(
        Padding(
          padding: EdgeInsets.only(
            bottom:
            i + 2 < cards.length
                ? 12
                : 0,
          ),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TradingStatCard(
                  data: first,
                  loading: loading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: second == null
                    ? const SizedBox()
                    : _TradingStatCard(
                  data: second,
                  loading: loading,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: rows,
    );
  }

  // ===========================================================================
  // PENDING RECEIVING
  // ===========================================================================

  Widget _pendingReceivingSection(
      String farmId,
      ) {
    return StreamBuilder<List<TradingPurchase>>(
      stream: TradingService.instance
          .pendingReceivingStream(
        farmId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _pendingError();
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting &&
            !snapshot.hasData) {
          return _pendingLoading();
        }

        final purchases =
            snapshot.data ?? <TradingPurchase>[];

        if (purchases.isEmpty) {
          return _emptyPending();
        }

        return Column(
          children: purchases.map(
                (purchase) {
              return Padding(
                padding:
                const EdgeInsets.only(
                  bottom: 12,
                ),
                child:
                _pendingReceivingCard(
                  purchase,
                ),
              );
            },
          ).toList(),
        );
      },
    );
  }

  Widget _pendingReceivingCard(
      TradingPurchase purchase,
      ) {
    final purchaseId = purchase.id;
    final seller = purchase.sellerName;
    final goats = purchase.totalGoats;
    final weight =
        purchase.totalWeightAtPurchase;
    final payment =
        purchase.paymentMethod;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                  AppColors.warning
                      .withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons
                      .local_shipping_outlined,
                  color: AppColors.warning,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Receiving',
                      style: AppTheme.body(
                        size: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      purchaseId,
                      style: AppTheme.heading(
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                  AppColors.warning
                      .withOpacity(0.10),
                  borderRadius:
                  BorderRadius.circular(
                    20,
                  ),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color:
                    AppColors.warning,
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          const Divider(height: 1),

          const SizedBox(height: 14),

          _pendingInfoRow(
            Icons.person_outline,
            'Seller',
            seller,
          ),

          const SizedBox(height: 9),

          _pendingInfoRow(
            Icons.pets_outlined,
            'Goats',
            '$goats',
          ),

          const SizedBox(height: 9),

          _pendingInfoRow(
            Icons.monitor_weight_outlined,
            'Purchase Weight',
            '${weight.toStringAsFixed(2)} Kg',
          ),

          const SizedBox(height: 9),

          _pendingInfoRow(
            Icons.calendar_today_outlined,
            'Purchase Date',
            DateFormat(
              'dd MMM yyyy',
            ).format(
              purchase.purchaseDate,
            ),
          ),

          const SizedBox(height: 9),

          _pendingInfoRow(
            Icons.payments_outlined,
            'Payment',
            payment,
          ),

          const SizedBox(height: 9),

          _pendingInfoRow(
            Icons.currency_rupee,
            'Purchase Amount',
            _currency(
              purchase.purchaseAmount,
            ),
            valueBold: true,
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                _openCompleteReceiving(
                  purchase,
                );
              },
              icon: const Icon(
                Icons.check_circle_outline,
                size: 20,
              ),
              label: const Text(
                'Complete Receiving',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor:
                Colors.white,
                elevation: 0,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingInfoRow(
      IconData icon,
      String label,
      String value, {
        bool valueBold = false,
      }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: AppColors.primaryGreen,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: AppTheme.body(
              size: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: valueBold
                ? AppTheme.heading(
              size: 13,
            )
                : AppTheme.body(
              size: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyPending() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color:
              AppColors.primaryGreen
                  .withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color:
              AppColors.primaryGreen,
              size: 27,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No Pending Receiving',
            style: AppTheme.heading(
              size: 15,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'All purchased goats have been received.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingLoading() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(24),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color:
          AppColors.primaryGreen,
        ),
      ),
    );
  }

  Widget _pendingError() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(16),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: const Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: AppColors.error,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Unable to load pending receiving records.',
              style: TextStyle(
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // QUICK ACTIONS
  // ===========================================================================

  Widget _quickActions() {
    return SingleChildScrollView(
      scrollDirection:
      Axis.horizontal,
      child: Row(
        children: [
          _TradingQuickAction(
            icon:
            Icons.shopping_cart_outlined,
            label: 'Purchase\nGoats',
            onTap: () {
              Navigator.of(context).push(
                fastRoute(
                  const PurchaseGoatsWizardScreen(),
                ),
              );
            },
          ),

          const SizedBox(width: 18),

          _TradingQuickAction(
            icon:
            Icons.how_to_reg_outlined,
            label: 'Register\nGoats',
            onTap: () {
              _comingSoon(
                'Register Goats',
              );
            },
          ),

          const SizedBox(width: 18),

          _TradingQuickAction(
            icon:
            Icons.inventory_2_outlined,
            label: 'Goat\nStock',
            onTap: () {
              _comingSoon(
                'Goat Stock',
              );
            },
          ),

          const SizedBox(width: 18),

          _TradingQuickAction(
            icon: Icons.sell_outlined,
            label: 'Sell\nGoat',
            onTap: () {
              _comingSoon(
                'Sell Goat',
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STAT CARD DATA
// ============================================================================

class _TradingStatCardData {
  final IconData icon;
  final String label;
  final String value;

  const _TradingStatCardData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

// ============================================================================
// STAT CARD
// ============================================================================

class _TradingStatCard
    extends StatelessWidget {
  final _TradingStatCardData data;
  final bool loading;

  const _TradingStatCard({
    required this.data,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            padding:
            const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
              AppColors.primaryGreen
                  .withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              data.icon,
              color:
              AppColors.primaryGreen,
              size: 20,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            loading ? '—' : data.value,
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style: AppTheme.heading(
              size: 18,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            data.label,
            maxLines: 2,
            overflow:
            TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// QUICK ACTION
// ============================================================================

class _TradingQuickAction
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TradingQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior:
      HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration:
              BoxDecoration(
                color:
                AppColors.primaryGreen
                    .withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color:
                AppColors.primaryGreen,
                size: 23,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign:
              TextAlign.center,
              maxLines: 2,
              overflow:
              TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}