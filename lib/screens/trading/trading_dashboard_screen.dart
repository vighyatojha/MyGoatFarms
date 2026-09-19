import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/goat_model.dart';
import '../../models/trading_purchase_model.dart';
import '../../models/trading_summary_model.dart';
import '../../services/firestore_service.dart';
import '../../services/trading_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import 'goat_stock/goat_stock_list_screen.dart';
import 'own_palai/own_palai_list_screen.dart';
import 'purchase_goats/complete_receiving_screen.dart';
import 'purchase_goats/purchase_goats_wizard_screen.dart';
import 'register_goats/select_purchase_screen.dart';
import 'sell_goat/sell_goat_wizard_screen.dart';

/// Trading Dashboard.
///
/// UI follows the same compact visual language as the Stock screen:
/// - compact widgets
/// - pastel/colorful cards
/// - stock-style header
/// - skeleton loading
/// - default AppTheme/AppColors
///
/// Existing trading functionality is preserved.
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
  bool _recalculating = false;
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

  /// Refresh farm state without replacing the RefreshIndicator subtree.
  Future<void> _refreshFarm() async {
    try {
      final id =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId =
        id == null || id.trim().isEmpty ? null : id.trim();
        _farmLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _farmLoadError = e.toString();
      });
    }
  }

  /// Fixes dashboard stat cards showing negative or drifted numbers by
  /// re-deriving every count straight from the actual purchase and
  /// goat records, then overwriting the stored aggregate with the
  /// corrected values. Safe to run any time — it's a pure
  /// recomputation, not an increment, so running it twice in a row
  /// produces the same result.
  Future<void> _recalculateDashboard() async {
    final farmId = _farmId;
    if (farmId == null || _recalculating) return;

    setState(() {
      _recalculating = true;
    });

    try {
      await TradingService.instance.backfillDashboardSummary(farmId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard numbers recalculated.'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not recalculate: '
                '${FirestoreService.instance.describeError(e)}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _recalculating = false;
        });
      }
    }
  }

  // ===========================================================================
  // NAVIGATION HELPERS
  // ===========================================================================

  /// Shared by the stat cards below and by the "Goat Stock" quick
  /// action — every one of them ends up on the same list screen, just
  /// pre-filtered differently.
  void _openGoatStock({String? statusFilter}) {
    Navigator.of(context).push(
      fastRoute(
        GoatStockListScreen(
          initialStatusFilter: statusFilter,
        ),
      ),
    );
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

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Receiving completed successfully.',
          ),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // -------------------------------------------------------------------------
    // FARM LOADING
    // -------------------------------------------------------------------------

    if (_loadingFarm) {
      return const _TradingDashboardSkeleton();
    }

    // -------------------------------------------------------------------------
    // FARM NOT LINKED
    // -------------------------------------------------------------------------

    if (_farmId == null || _farmId!.isEmpty) {
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

    // -------------------------------------------------------------------------
    // MAIN DASHBOARD
    // -------------------------------------------------------------------------

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _refreshFarm,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          30,
        ),
        children: [
          _header(),

          const SizedBox(height: 20),

          _sectionHeader(
            title: 'Trading Overview',
            subtitle: 'Your trading activity at a glance',
            icon: Icons.bar_chart_rounded,
            color: AppColors.primaryGreen,
          ),

          const SizedBox(height: 12),

          _summarySection(_farmId!),

          const SizedBox(height: 24),

          _sectionHeader(
            title: 'Pending Receiving',
            subtitle: 'Purchases waiting to be received',
            icon: Icons.local_shipping_outlined,
            color: AppColors.stockTeal,
          ),

          const SizedBox(height: 12),

          _pendingReceivingSection(_farmId!),

          const SizedBox(height: 24),

          _sectionHeader(
            title: 'Quick Actions',
            subtitle: 'Manage your trading quickly',
            icon: Icons.bolt_rounded,
            color: AppColors.primaryGreen,
          ),

          const SizedBox(height: 12),

          _quickActions(),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        4,
        10,
        4,
        2,
      ),
      child: Row(
        children: [
          // Header icon
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.10),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.primaryGreen,
              size: 28,
            ),
          ),

          const SizedBox(width: 13),

          // Header title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trading',
                  style: AppTheme.heading(
                    size: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Wholesale purchases & stock',
                  style: AppTheme.body(
                    size: 12,
                  ),
                ),
              ],
            ),
          ),

          // Recalculate dashboard numbers — fixes stat cards that have
          // drifted or gone negative by re-deriving them from the
          // actual purchase / goat records.
          Tooltip(
            message: 'Recalculate dashboard numbers',
            child: Material(
              color: AppColors.primaryGreen.withOpacity(0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recalculating ? null : _recalculateDashboard,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: _recalculating
                      ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primaryGreen,
                    ),
                  )
                      : const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.primaryGreen,
                    size: 24,
                  ),
                ),
              ),
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
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: color,
            size: 22,
          ),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.heading(
                  size: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _summarySection(String farmId) {
    return StreamBuilder<TradingSummary>(
      stream:
      TradingService.instance.dashboardSummaryStream(
        farmId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _summaryError();
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _TradingSummarySkeleton();
        }

        final summary =
            snapshot.data ?? TradingSummary.empty;

        return _statGrid(summary);
      },
    );
  }

  Widget _summaryError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: AppTheme.card(
        radius: 17,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Unable to load trading summary. Pull down to refresh.',
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STAT GRID
  // ===========================================================================

  Widget _statGrid(TradingSummary summary) {
    // Only stats with somewhere real to go get a full card — a card
    // that goes nowhere just wastes a tap. Everything else moves to
    // the compact strip below instead of taking up a full tile.
    final cards = <_TradingStatCardData>[
      _TradingStatCardData(
        icon: Icons.pets_rounded,
        label: 'Total Stock',
        value: '${summary.totalStock}',
        color: AppColors.primaryGreen,
        onTap: () => _openGoatStock(),
      ),
      _TradingStatCardData(
        icon: Icons.event_available_outlined,
        label: 'Booking',
        value: '${summary.booking}',
        color: Colors.deepPurple,
        onTap: () => _openGoatStock(
          statusFilter: Goat.statusBooked,
        ),
      ),
      _TradingStatCardData(
        icon: Icons.local_shipping_outlined,
        label: 'Wait on Delivery',
        value: '${summary.waitOnDelivery}',
        color: AppColors.stockTeal,
        onTap: () => _openGoatStock(
          statusFilter: Goat.statusWaitOnDelivery,
        ),
      ),
      _TradingStatCardData(
        icon: Icons.sell_outlined,
        label: 'Total Sold',
        value: '${summary.totalSold}',
        color: AppColors.error,
        onTap: () => _openGoatStock(
          statusFilter: Goat.statusSold,
        ),
      ),
    ];

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
          ),
          itemBuilder: (context, index) {
            return _TradingStatCard(
              data: cards[index],
            );
          },
        ),
        const SizedBox(height: 12),
        _secondaryStatsStrip(summary),
      ],
    );
  }

  /// Everything that doesn't have a screen of its own to go to —
  /// shown as a single compact, non-tappable strip instead of three
  /// more big cards that would otherwise just sit there unusable.
  Widget _secondaryStatsStrip(TradingSummary summary) {
    final items = <_SecondaryStatData>[
      _SecondaryStatData(
        icon: Icons.shopping_cart_outlined,
        label: 'Wholesale Purchased',
        value: '${summary.wholesalePurchased}',
        color: AppColors.info,
      ),
      _SecondaryStatData(
        icon: Icons.pending_actions_outlined,
        label: 'Pending Registrations',
        value: '${summary.pendingRegistrations}',
        color: AppColors.warning,
      ),
      _SecondaryStatData(
        icon: Icons.trending_up_rounded,
        label: 'Total Profit',
        value: _currency(summary.totalProfit),
        color: AppColors.success,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 4,
      ),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                color: AppColors.divider,
              ),
            _secondaryStatRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _secondaryStatRow(_SecondaryStatData item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              item.icon,
              color: item.color,
              size: 16,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              item.label,
              style: AppTheme.body(size: 12),
            ),
          ),
          Text(
            item.value,
            style: AppTheme.heading(size: 14, color: item.color),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PENDING RECEIVING
  // ===========================================================================

  Widget _pendingReceivingSection(
      String farmId,
      ) {
    return StreamBuilder<List<TradingPurchase>>(
      stream:
      TradingService.instance.pendingReceivingStream(
        farmId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _pendingError();
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _PendingReceivingSkeleton();
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
                padding: const EdgeInsets.only(
                  bottom: 10,
                ),
                child: _pendingReceivingCard(
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
    final weight = purchase.totalWeightAtPurchase;
    final payment = purchase.paymentMethod;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------------------------------------------------------------------
          // Header
          // -------------------------------------------------------------------

          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Receiving',
                      style: AppTheme.body(
                        size: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      purchaseId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          // -------------------------------------------------------------------
          // Information
          // -------------------------------------------------------------------

          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.paleGreen.withOpacity(0.55),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              children: [
                _pendingInfoRow(
                  Icons.person_outline,
                  'Seller',
                  seller,
                ),
                const SizedBox(height: 8),
                _pendingInfoRow(
                  Icons.pets_outlined,
                  'Goats',
                  '$goats',
                ),
                const SizedBox(height: 8),
                _pendingInfoRow(
                  Icons.monitor_weight_outlined,
                  'Weight',
                  '${weight.toStringAsFixed(2)} Kg',
                ),
                const SizedBox(height: 8),
                _pendingInfoRow(
                  Icons.calendar_today_outlined,
                  'Purchase Date',
                  DateFormat(
                    'dd MMM yyyy',
                  ).format(
                    purchase.purchaseDate,
                  ),
                ),
                const SizedBox(height: 8),
                _pendingInfoRow(
                  Icons.payments_outlined,
                  'Payment',
                  payment,
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // -------------------------------------------------------------------
          // Amount
          // -------------------------------------------------------------------

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color:
              AppColors.primaryGreen.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.currency_rupee,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Purchase Amount',
                    style: AppTheme.body(
                      size: 10.5,
                    ),
                  ),
                ),
                Text(
                  _currency(
                    purchase.purchaseAmount,
                  ),
                  style: AppTheme.heading(
                    size: 14,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 11),

          // -------------------------------------------------------------------
          // Complete receiving
          // -------------------------------------------------------------------

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () {
                _openCompleteReceiving(
                  purchase,
                );
              },
              icon: const Icon(
                Icons.check_circle_outline,
                size: 18,
              ),
              label: const Text(
                'Complete Receiving',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(12),
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
      String value,
      ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: AppColors.primaryGreen,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: AppTheme.body(
              size: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyPending() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 22,
      ),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
              AppColors.success.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 26,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No Pending Receiving',
            style: AppTheme.heading(
              size: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'All purchased goats have been received.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
        radius: 17,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Unable to load pending receiving records. Pull down to refresh.',
              style: AppTheme.body(
                size: 10.5,
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
    final actions = <_TradingQuickActionData>[
      _TradingQuickActionData(
        icon: Icons.shopping_cart_outlined,
        title: 'Purchase Goats',
        subtitle: 'Buy new wholesale stock',
        color: AppColors.primaryGreen,
        onTap: () {
          Navigator.of(context).push(
            fastRoute(
              const PurchaseGoatsWizardScreen(),
            ),
          );
        },
      ),
      _TradingQuickActionData(
        icon: Icons.how_to_reg_outlined,
        title: 'Register Goats',
        subtitle: 'Add individual records for received goats',
        color: AppColors.info,
        onTap: () {
          Navigator.of(context).push(
            fastRoute(
              const SelectPurchaseScreen(),
            ),
          );
        },
      ),
      _TradingQuickActionData(
        icon: Icons.inventory_2_outlined,
        title: 'Goat Stock',
        subtitle: 'Browse, filter, and manage every goat',
        color: Colors.deepPurple,
        onTap: () => _openGoatStock(),
      ),
      _TradingQuickActionData(
        icon: Icons.holiday_village_outlined,
        title: 'Own Palai',
        subtitle: 'Goats kept and boarded by your own farm',
        color: AppColors.warning,
        onTap: () {
          Navigator.of(context).push(
            fastRoute(
              const OwnPalaiListScreen(),
            ),
          );
        },
      ),
      _TradingQuickActionData(
        icon: Icons.sell_outlined,
        title: 'Sell Goat',
        subtitle: 'Start a new sale',
        color: AppColors.error,
        onTap: () {
          Navigator.of(context).push(
            fastRoute(
              const SellGoatWizardScreen(),
            ),
          );
        },
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          _TradingQuickAction(data: actions[i]),
        ],
      ],
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
  final Color color;
  final VoidCallback onTap;

  const _TradingStatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });
}

// ============================================================================
// SECONDARY STAT DATA (non-navigable — shown in the compact strip)
// ============================================================================

class _SecondaryStatData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SecondaryStatData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

// ============================================================================
// STAT CARD
// ============================================================================

class _TradingStatCard extends StatelessWidget {
  final _TradingStatCardData data;

  const _TradingStatCard({
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: data.color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: data.color.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: data.color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      data.icon,
                      color: data.color,
                      size: 19,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: data.color.withOpacity(0.55),
                    size: 20,
                  ),
                ],
              ),

              const Spacer(),

              Text(
                data.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 9.5,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(
                  size: 17,
                  color: data.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// QUICK ACTION DATA
// ============================================================================

class _TradingQuickActionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TradingQuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

// ============================================================================
// QUICK ACTION
// ============================================================================

class _TradingQuickAction extends StatelessWidget {
  final _TradingQuickActionData data;

  const _TradingQuickAction({
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: data.color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: data.color.withOpacity(0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  data.icon,
                  color: data.color,
                  size: 21,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 12,
                        color: data.color,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right_rounded,
                color: data.color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SKELETON BASE
// ============================================================================

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  State<_SkeletonBox> createState() =>
      _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 950,
      ),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity =
            0.35 + (_controller.value * 0.30);

        return Opacity(
          opacity: opacity,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: AppColors.textGrey.withOpacity(0.18),
              borderRadius:
              BorderRadius.circular(widget.radius),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// DASHBOARD SKELETON
// ============================================================================

class _TradingDashboardSkeleton extends StatelessWidget {
  const _TradingDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        30,
      ),
      children: [
        // Header
        Row(
          children: [
            const _SkeletonBox(
              width: 54,
              height: 54,
              radius: 17,
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(
                    width: 110,
                    height: 22,
                    radius: 7,
                  ),
                  SizedBox(height: 7),
                  _SkeletonBox(
                    width: 185,
                    height: 12,
                    radius: 6,
                  ),
                ],
              ),
            ),
            _SkeletonBox(
              width: 48,
              height: 48,
              radius: 24,
            ),
          ],
        ),

        const SizedBox(height: 24),

        const _SkeletonSectionHeader(),

        const SizedBox(height: 12),

        const _TradingSummarySkeleton(),

        const SizedBox(height: 24),

        const _SkeletonSectionHeader(),

        const SizedBox(height: 12),

        const _PendingReceivingSkeleton(),

        const SizedBox(height: 24),

        const _SkeletonSectionHeader(),

        const SizedBox(height: 12),

        const _QuickActionsSkeleton(),
      ],
    );
  }
}

// ============================================================================
// SKELETON SECTION HEADER
// ============================================================================

class _SkeletonSectionHeader extends StatelessWidget {
  const _SkeletonSectionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _SkeletonBox(
          width: 42,
          height: 42,
          radius: 14,
        ),
        SizedBox(width: 11),
        Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            _SkeletonBox(
              width: 145,
              height: 17,
              radius: 6,
            ),
            SizedBox(height: 5),
            _SkeletonBox(
              width: 210,
              height: 10,
              radius: 5,
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// SUMMARY SKELETON
// ============================================================================

class _TradingSummarySkeleton extends StatelessWidget {
  const _TradingSummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(
            radius: 17,
          ),
          child: const Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              _SkeletonBox(
                width: 36,
                height: 36,
                radius: 11,
              ),
              Spacer(),
              _SkeletonBox(
                width: 78,
                height: 10,
                radius: 5,
              ),
              SizedBox(height: 6),
              _SkeletonBox(
                width: 48,
                height: 17,
                radius: 6,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// PENDING SKELETON
// ============================================================================

class _PendingReceivingSkeleton
    extends StatelessWidget {
  const _PendingReceivingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        children: [
          Row(
            children: const [
              _SkeletonBox(
                width: 43,
                height: 43,
                radius: 13,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(
                      width: 95,
                      height: 10,
                      radius: 5,
                    ),
                    SizedBox(height: 5),
                    _SkeletonBox(
                      width: 120,
                      height: 14,
                      radius: 6,
                    ),
                  ],
                ),
              ),
              _SkeletonBox(
                width: 54,
                height: 22,
                radius: 12,
              ),
            ],
          ),

          SizedBox(height: 14),

          _SkeletonBox(
            width: double.infinity,
            height: 112,
            radius: 13,
          ),

          SizedBox(height: 10),

          _SkeletonBox(
            width: double.infinity,
            height: 38,
            radius: 12,
          ),

          SizedBox(height: 10),

          _SkeletonBox(
            width: double.infinity,
            height: 44,
            radius: 12,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// QUICK ACTIONS SKELETON
// ============================================================================

class _QuickActionsSkeleton
    extends StatelessWidget {
  const _QuickActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == 4 ? 0 : 9,
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: AppTheme.card(
              radius: 17,
            ),
            child: const Row(
              children: [
                _SkeletonBox(
                  width: 43,
                  height: 43,
                  radius: 13,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(
                        width: 110,
                        height: 11,
                        radius: 5,
                      ),
                      SizedBox(height: 5),
                      _SkeletonBox(
                        width: 160,
                        height: 9,
                        radius: 5,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}