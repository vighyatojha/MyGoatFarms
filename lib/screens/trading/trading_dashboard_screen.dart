import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/goat_model.dart';
import '../../models/trading_purchase_model.dart';
import '../../models/trading_summary_model.dart';
import '../../services/firestore_service.dart';
import '../../services/trading_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../../widgets/fast_route.dart';
import 'goat_stock/goat_stock_list_screen.dart';
import 'own_palai/own_palai_list_screen.dart';
import 'purchase_goats/complete_receiving_screen.dart';
import 'purchase_goats/purchase_goats_wizard_screen.dart';
import 'register_goats/select_purchase_screen.dart';
import 'sell_goat/sell_goat_wizard_screen.dart';

/// Trading Dashboard.
///
/// Layout (top to bottom):
///  1. Header (back, title, recalculate)
///  2. 2x2 stat cards + compact secondary stats list
///  3. Quick actions (Register Goats hero + 2x2 action tiles)
///  4. Pending receiving (empty state card or list of pending purchases)
class TradingDashboardScreen extends StatefulWidget {
  const TradingDashboardScreen({super.key});

  @override
  State<TradingDashboardScreen> createState() => _TradingDashboardScreenState();
}

class _TradingDashboardScreenState extends State<TradingDashboardScreen> {
  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final DateFormat _dateFmt = DateFormat('dd MMM yyyy');

  String? _farmId;
  bool _loadingFarm = true;
  bool _recalculating = false;

  // Created once per farm (not in build) so rebuilds never resubscribe.
  Stream<TradingSummary>? _summaryStream;
  Stream<List<TradingPurchase>>? _pendingStream;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  // ===========================================================================
  // FARM
  // ===========================================================================

  void _applyFarm(String? raw) {
    final id = raw?.trim();
    final next = (id == null || id.isEmpty) ? null : id;
    if (next == _farmId) return;

    _farmId = next;
    _summaryStream = next == null
        ? null
        : TradingService.instance.dashboardSummaryStream(next);
    _pendingStream = next == null
        ? null
        : TradingService.instance.pendingReceivingStream(next);
  }

  /// [silent] = pull-to-refresh: keeps the current farm/streams on failure
  /// and never swaps the screen for the skeleton.
  Future<void> _loadFarm({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingFarm = true);
    }

    try {
      final id = await FirestoreService.instance.currentFarmId();
      if (!mounted) return;
      setState(() {
        _applyFarm(id);
        _loadingFarm = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (!silent) _applyFarm(null);
        _loadingFarm = false;
      });
    }
  }

  /// Re-derives every dashboard count from the real purchase / goat records.
  /// Pure recomputation, so it is safe to run repeatedly.
  Future<void> _recalculateDashboard({bool quiet = false}) async {
    final farmId = _farmId;
    if (farmId == null || _recalculating) return;

    _recalculating = true; // guard only, no UI depends on it

    try {
      await TradingService.instance.backfillDashboardSummary(farmId);
      if (!quiet) {
        _snack('Dashboard numbers recalculated.', AppColors.darkGreen);
      }
    } catch (e) {
      _snack(
        'Could not recalculate: ${FirestoreService.instance.describeError(e)}',
        AppColors.error,
      );
    } finally {
      _recalculating = false;
    }
  }

  /// Pull-to-refresh: re-check the farm, then re-derive the counts.
  Future<void> _onRefresh() async {
    await _loadFarm(silent: true);
    await _recalculateDashboard(quiet: true);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  void _push(Widget screen) {
    Navigator.of(context).push(fastRoute(screen));
  }

  void _openGoatStock({String? statusFilter}) {
    _push(GoatStockListScreen(initialStatusFilter: statusFilter));
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _openCompleteReceiving(TradingPurchase purchase) async {
    final farmId = _farmId;
    if (farmId == null) return;

    final result = await Navigator.of(context).push<TradingPurchase>(
      MaterialPageRoute<TradingPurchase>(
        builder: (_) => CompleteReceivingScreen(
          farmId: farmId,
          purchase: purchase,
        ),
      ),
    );

    if (result != null) {
      _snack('Receiving completed successfully.', AppColors.darkGreen);
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loadingFarm) return const _DashboardSkeleton();

    if (_farmId == null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _header(),
          ),
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
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          _header(),
          const SizedBox(height: 16),

          // One subscription feeds both the overview and the
          // "Register Goats" hero (pending registrations count).
          StreamBuilder<TradingSummary>(
            stream: _summaryStream,
            builder: (context, snap) {
              final summary = snap.data ?? TradingSummary.empty;
              return Column(
                children: [
                  _overview(snap, summary),
                  const SizedBox(height: 18),
                  _quickActions(summary),
                ],
              );
            },
          ),

          const SizedBox(height: 18),
          _pendingSection(),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _header() {
    final canPop = Navigator.of(context).canPop();

    return Row(
      children: [
        if (canPop) ...[
          _HeaderButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
        const _IconBox(
          icon: Icons.storefront_rounded,
          color: AppColors.primaryGreen,
          size: 38,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Trading Overview',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(size: 20),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // OVERVIEW (stat cards + secondary stats)
  // ===========================================================================

  Widget _overview(AsyncSnapshot<TradingSummary> snap, TradingSummary s) {
    if (snap.hasError) {
      return _errorCard('Unable to load trading summary. Pull down to refresh.');
    }

    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const _Pulse(child: _OverviewSkeleton());
    }

    return Column(
      children: [
        _pair(
          _StatCard(
            icon: Icons.pets_rounded,
            label: 'Total Stock',
            value: '${s.totalStock}',
            color: AppColors.primaryGreen,
            // Needs a "new this week" field on TradingSummary, e.g.
            // badge: '+${s.newThisWeek} new',
            onTap: () => _openGoatStock(),
          ),
          _StatCard(
            icon: Icons.event_available_outlined,
            label: 'Booking',
            value: '${s.booking}',
            color: Colors.deepPurple,
            badge: s.booking > 0 ? 'Deposit paid' : null,
            onTap: () => _openGoatStock(statusFilter: Goat.statusBooked),
          ),
          height: 116,
        ),
        const SizedBox(height: 10),
        _pair(
          _StatCard(
            icon: Icons.local_shipping_outlined,
            label: 'Wait on Delivery',
            value: '${s.waitOnDelivery}',
            color: AppColors.stockTeal,
            badge: s.waitOnDelivery == 0 ? 'All clear' : null,
            onTap: () => _openGoatStock(
              statusFilter: Goat.statusWaitOnDelivery,
            ),
          ),
          _StatCard(
            icon: Icons.sell_outlined,
            label: 'Total Sold',
            value: '${s.totalSold}',
            color: AppColors.error,
            badge: s.totalSold > 0 ? 'Sold Out' : null,
            onTap: () => _openGoatStock(statusFilter: Goat.statusSold),
          ),
          height: 116,
        ),
        const SizedBox(height: 10),
        _secondaryStats(s),
      ],
    );
  }

  Widget _secondaryStats(TradingSummary s) {
    final profit = s.totalProfit;
    final profitColor = profit > 0
        ? AppColors.success
        : profit < 0
        ? AppColors.error
        : AppColors.textDark;
    final profitNote = profit > 0
        ? 'In profit'
        : profit < 0
        ? 'In loss'
        : 'Break-even phase';

    const divider = Divider(
      height: 1,
      indent: 12,
      endIndent: 12,
      color: AppColors.divider,
    );

    return DecoratedBox(
      decoration: AppTheme.card(radius: 16),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            _StripRow(
              icon: Icons.shopping_cart_outlined,
              color: AppColors.info,
              title: 'Wholesale Purchased',
              subtitle: 'Inbound batch goats',
              trailing: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${s.wholesalePurchased}',
                      style: AppTheme.heading(size: 15, color: AppColors.info),
                    ),
                    TextSpan(text: ' head', style: AppTheme.body(size: 10)),
                  ],
                ),
              ),
            ),
            divider,
            _StripRow(
              icon: Icons.description_outlined,
              color: AppColors.warning,
              title: 'Pending Registrations',
              subtitle: 'Needs ear-tags & weight',
              subtitleColor: AppColors.warning,
              onTap: () => _push(const SelectPurchaseScreen()),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  s.pendingRegistrations > 0
                      ? _Pill('${s.pendingRegistrations} Pending',
                      AppColors.warning)
                      : const _Pill('All done', AppColors.success),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textGrey,
                  ),
                ],
              ),
            ),
            divider,
            _StripRow(
              icon: Icons.trending_up_rounded,
              color: AppColors.success,
              title: 'Total Realized Profit',
              subtitle: 'Current Q${_quarter(DateTime.now())} cycle margin',
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inr.format(profit),
                    style: AppTheme.heading(size: 16, color: profitColor),
                  ),
                  Text(profitNote, style: AppTheme.body(size: 9.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // QUICK ACTIONS
  // ===========================================================================

  Widget _quickActions(TradingSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _IconBox(
              icon: Icons.bolt_rounded,
              color: AppColors.primaryGreen,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text('Quick Actions', style: AppTheme.heading(size: 14)),
            const Spacer(),
            Text('Trading operations', style: AppTheme.body(size: 10)),
          ],
        ),
        const SizedBox(height: 10),
        _registerHero(s.pendingRegistrations),
        const SizedBox(height: 10),
        _pair(
          _ActionTile(
            icon: Icons.shopping_cart_outlined,
            title: 'Purchase Goats',
            subtitle: 'Wholesale & direct stock',
            color: AppColors.primaryGreen,
            onTap: () => _push(const PurchaseGoatsWizardScreen()),
          ),
          _ActionTile(
            icon: Icons.currency_rupee_rounded,
            title: 'Sell Goat',
            subtitle: 'Invoice & gate pass',
            color: AppColors.error,
            onTap: () => _push(const SellGoatWizardScreen()),
          ),
          height: 100,
        ),
        const SizedBox(height: 10),
        _pair(
          _ActionTile(
            icon: Icons.inventory_2_outlined,
            title: 'Goat Stock',
            subtitle: 'Browse & filter herd',
            color: Colors.deepPurple,
            onTap: () => _openGoatStock(),
          ),
          _ActionTile(
            icon: Icons.holiday_village_outlined,
            title: 'Own Palai',
            subtitle: 'Boarded pen records',
            color: AppColors.warning,
            onTap: () => _push(const OwnPalaiListScreen()),
          ),
          height: 100,
        ),
      ],
    );
  }

  Widget _registerHero(int pending) {
    final now = DateTime.now();

    return _CardTap(
      radius: 18,
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(18),
      ),
      onTap: () => _push(const SelectPurchaseScreen()),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.how_to_reg_outlined,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Register Goats',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.heading(
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (pending > 0) ...[
                            const SizedBox(width: 8),
                            _Pill('$pending Pending', AppColors.warning,
                                solid: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tag & weigh incoming batch',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 10.5,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Batch ${now.year}-Q${_quarter(now)} · Queue',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pending > 0 ? 'Process Now' : 'Open',
                        style: const TextStyle(
                          color: AppColors.darkGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.darkGreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PENDING RECEIVING
  // ===========================================================================

  Widget _pendingSection() {
    return StreamBuilder<List<TradingPurchase>>(
      stream: _pendingStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorCard(
            'Unable to load pending receiving records. Pull down to refresh.',
          );
        }

        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const _Pulse(child: _PendingSkeleton());
        }

        final purchases = snap.data ?? const <TradingPurchase>[];
        return purchases.isEmpty ? _pendingEmpty() : _pendingList(purchases);
      },
    );
  }

  Widget _pendingHeader(Widget trailing) {
    return Row(
      children: [
        const _IconBox(
          icon: Icons.local_shipping_outlined,
          color: AppColors.stockTeal,
          size: 36,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pending Receiving', style: AppTheme.heading(size: 13.5)),
              const SizedBox(height: 1),
              Text(
                'Purchases waiting delivery',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 10),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _pendingEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        children: [
          _pendingHeader(const _Pill('Synced', AppColors.success)),
          const SizedBox(height: 16),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text('No Pending Receiving', style: AppTheme.heading(size: 14)),
          const SizedBox(height: 4),
          Text(
            'All purchased goats have been received, weighed, and moved to '
                'quarantine or active barns.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 10.5),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _pendingList(List<TradingPurchase> purchases) {
    return Column(
      children: [
        _pendingHeader(
          _Pill('${purchases.length} Pending', AppColors.warning),
        ),
        const SizedBox(height: 10),
        for (final purchase in purchases)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _pendingCard(purchase),
          ),
      ],
    );
  }

  Widget _pendingCard(TradingPurchase p) {
    final rows = <Widget>[
      _InfoRow(Icons.person_outline, 'Seller', p.sellerName),
      _InfoRow(Icons.pets_outlined, 'Goats', '${p.totalGoats}'),
      _InfoRow(
        Icons.monitor_weight_outlined,
        'Weight',
        '${p.totalWeightAtPurchase.toStringAsFixed(2)} Kg',
      ),
      _InfoRow(
        Icons.calendar_today_outlined,
        'Purchase Date',
        _dateFmt.format(p.purchaseDate),
      ),
      _InfoRow(Icons.payments_outlined, 'Payment', p.paymentMethod),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBox(
                icon: Icons.local_shipping_outlined,
                color: AppColors.warning,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Purchase', style: AppTheme.body(size: 10)),
                    Text(
                      p.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(size: 13),
                    ),
                  ],
                ),
              ),
              const _Pill('Pending', AppColors.warning),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.paleGreen.withOpacity(0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  rows[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.currency_rupee,
                  color: AppColors.primaryGreen,
                  size: 17,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Purchase Amount',
                    style: AppTheme.body(size: 10.5),
                  ),
                ),
                Text(
                  _inr.format(p.purchaseAmount),
                  style: AppTheme.heading(size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => _openCompleteReceiving(p),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text(
                'Complete Receiving',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: Row(
        children: [
          const _IconBox(
            icon: Icons.error_outline,
            color: AppColors.error,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.body(size: 11, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED HELPERS
// ============================================================================

int _quarter(DateTime d) => (d.month - 1) ~/ 3 + 1;

/// Two equal-width cells with a fixed height (lighter than a shrink-wrapped
/// GridView and immune to aspect-ratio drift).
Widget _pair(Widget a, Widget b, {required double height}) {
  return SizedBox(
    height: height,
    child: Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    ),
  );
}

// ============================================================================
// SMALL WIDGETS
// ============================================================================

/// Card surface with a correctly clipped ink ripple.
class _CardTap extends StatelessWidget {
  const _CardTap({
    required this.radius,
    required this.child,
    this.onTap,
    this.decoration,
  });

  final double radius;
  final Widget child;
  final VoidCallback? onTap;
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: decoration ?? AppTheme.card(radius: radius),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = _CardTap(
      radius: 14,
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Center(
          child: Icon(icon, size: 22, color: AppColors.textDark),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.icon,
    required this.color,
    this.size = 34,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.solid = false});

  final String text;
  final Color color;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: solid ? Colors.white : color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return _CardTap(
      radius: 16,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _IconBox(icon: icon, color: color),
                Icon(Icons.chevron_right_rounded, size: 20, color: color),
              ],
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 11),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: AppTheme.heading(
                    size: 22,
                    color: AppColors.textDark,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _Pill(badge!, color),
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

class _StripRow extends StatelessWidget {
  const _StripRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.subtitleColor,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Color? subtitleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _IconBox(icon: icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(size: 12.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleColor == null
                        ? AppTheme.body(size: 10)
                        : AppTheme.body(size: 10, color: subtitleColor!),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardTap(
      radius: 16,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _IconBox(icon: icon, color: color),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(size: 12.5),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primaryGreen),
        const SizedBox(width: 7),
        Expanded(child: Text(label, style: AppTheme.body(size: 10))),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTheme.body(size: 10, color: AppColors.textDark),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SKELETONS
//
// One animation controller per skeleton *group* (via _Pulse) instead of one
// per box, so loading states stay cheap.
// ============================================================================

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  late final Animation<double> _opacity =
  Tween<double>(begin: 0.45, end: 0.95).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.textGrey.withOpacity(0.18),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bone(width: 34, height: 34, radius: 10),
          Spacer(),
          _Bone(width: 72, height: 10, radius: 5),
          SizedBox(height: 6),
          _Bone(width: 44, height: 16, radius: 6),
        ],
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _pair(const _SkeletonCard(), const _SkeletonCard(), height: 116),
        const SizedBox(height: 10),
        _pair(const _SkeletonCard(), const _SkeletonCard(), height: 116),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: AppTheme.card(radius: 16),
          child: Column(
            children: List.generate(3, (i) {
              return Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: const Row(
                  children: [
                    _Bone(width: 34, height: 34, radius: 10),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Bone(width: 130, height: 12, radius: 5),
                          SizedBox(height: 5),
                          _Bone(width: 90, height: 9, radius: 5),
                        ],
                      ),
                    ),
                    _Bone(width: 46, height: 16, radius: 6),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _QuickActionsSkeleton extends StatelessWidget {
  const _QuickActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            _Bone(width: 28, height: 28, radius: 9),
            SizedBox(width: 8),
            _Bone(width: 100, height: 14, radius: 5),
          ],
        ),
        const SizedBox(height: 10),
        const _Bone(width: double.infinity, height: 110, radius: 18),
        const SizedBox(height: 10),
        _pair(const _SkeletonCard(), const _SkeletonCard(), height: 100),
        const SizedBox(height: 10),
        _pair(const _SkeletonCard(), const _SkeletonCard(), height: 100),
      ],
    );
  }
}

class _PendingSkeleton extends StatelessWidget {
  const _PendingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 18),
      child: const Column(
        children: [
          Row(
            children: [
              _Bone(width: 36, height: 36, radius: 11),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(width: 110, height: 12, radius: 5),
                    SizedBox(height: 5),
                    _Bone(width: 150, height: 9, radius: 5),
                  ],
                ),
              ),
              _Bone(width: 54, height: 20, radius: 10),
            ],
          ),
          SizedBox(height: 14),
          _Bone(width: double.infinity, height: 96, radius: 13),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Pulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: const [
          Row(
            children: [
              _Bone(width: 42, height: 42, radius: 14),
              SizedBox(width: 12),
              _Bone(width: 160, height: 20, radius: 6),
            ],
          ),
          SizedBox(height: 16),
          _OverviewSkeleton(),
          SizedBox(height: 18),
          _QuickActionsSkeleton(),
          SizedBox(height: 18),
          _PendingSkeleton(),
        ],
      ),
    );
  }
}