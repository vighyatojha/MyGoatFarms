
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../goat_icons.dart';
import '../../models/goat_model.dart';
import '../../models/lot_sales_summary.dart';
import '../../models/sale_model.dart';
import '../../models/trading_lot_overview.dart';
import '../../models/trading_purchase_model.dart';
import '../../models/trading_summary_model.dart';
import '../../services/firestore_service.dart';
import '../../services/goat_service.dart';
import '../../services/trading_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../../widgets/fast_route.dart';
import 'goat_stock/booking_delivery_customer_list_screen.dart';
import 'goat_stock/goat_stock_list_screen.dart';
import 'goat_stock/wait_delivery_customer_list_screen.dart';
import 'lots/lot_management_screen.dart';
import 'lots/lot_sales_list_screen.dart';
import 'lots/lot_stock_screen.dart';
import 'lots/receive_lot_screen.dart';
import 'purchase_goats/complete_receiving_screen.dart';
import 'purchase_goats/purchase_goats_wizard_screen.dart';
import 'register_goats/select_purchase_screen.dart';
import 'sell_from_lot/sell_from_lot_wizard_screen.dart';

/// Trading Dashboard.
///
/// Layout (top to bottom):
///  1. Header (back, title, recalculate)
///  2. 2x2 stat cards (Available Stock, Booking, Wait on Delivery,
///     Total Sold) + compact secondary stats list
///  3. Secondary trading stats with direct Purchase / Sell controls.
///     Goats stay anonymous inside a lot; they are only registered when
///     transferred to a Palai, so there is no standalone "Register Goats" action.
///  4. Pending receiving (empty state card or list of pending purchases)
class TradingDashboardScreen extends StatefulWidget {
  const TradingDashboardScreen({super.key});

  @override
  State<TradingDashboardScreen> createState() => _TradingDashboardScreenState();
}

class _TradingDashboardScreenState extends State<TradingDashboardScreen> {
  /// Farms whose dashboard counters were already re-derived in this app
  /// session. The stored counters (Total Sold, stock, profit) are kept
  /// with increments, so they can drift if a write was ever interrupted;
  /// re-deriving them once per launch heals that without re-reading every
  /// goat each time the dashboard is opened.
  static final Set<String> _syncedFarms = <String>{};

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
  Stream<TradingLotOverview>? _lotOverviewStream;

  // Every lot sale, for the dashboard's Sales Revenue / Customer Pending.
  Stream<List<Sale>>? _lotSalesStream;

  // "Available Stock" = registered goats whose status is Available.
  //
  // It deliberately does NOT come from TradingSummary.totalStock, because
  // that number also includes received-but-unregistered goats and goats
  // that are Booked / Wait on Delivery / in Own Palai. It is read with a
  // cheap count query instead, and re-read whenever the summary doc
  // changes (a sale, booking or registration touches it), when the user
  // returns from another screen, and on pull-to-refresh.
  int? _availableCount;
  bool _availableBusy = false;
  bool _availableDirty = false;
  StreamSubscription<TradingSummary>? _summarySignal;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  @override
  void dispose() {
    _summarySignal?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // FARM
  // ===========================================================================

  void _applyFarm(String? raw) {
    final id = raw?.trim();
    final next = (id == null || id.isEmpty) ? null : id;
    if (next == _farmId) return;

    _farmId = next;
    if (next != null && _syncedFarms.add(next)) {
      unawaited(_autoSync());
    }
    _summaryStream = next == null
        ? null
        : TradingService.instance.dashboardSummaryStream(next);
    // Pending Receiving is driven entirely by _lotOverviewStream
    // (TradingLotOverview.pendingReceiving), which is lot-aware.
    _lotOverviewStream = next == null
        ? null
        : TradingService.instance.lotOverviewStream(next);
    _lotSalesStream = next == null
        ? null
        : TradingService.instance.lotSalesStream(next);

    // New farm: forget the old count and use the summary doc purely as a
    // "something changed" signal. Its first emission also triggers the
    // initial load of the Available count.
    _availableCount = null;
    _summarySignal?.cancel();
    _summarySignal = next == null
        ? null
        : TradingService.instance.dashboardSummaryStream(next).listen(
          (_) => _refreshAvailable(),
      onError: (_) {},
    );
  }

  /// Re-reads the Available goat count. Overlapping calls are coalesced:
  /// if one is already running, it simply runs once more when it finishes.
  /// On failure the last known number stays on screen.
  Future<void> _refreshAvailable() async {
    if (_farmId == null) return;

    if (_availableBusy) {
      _availableDirty = true;
      return;
    }

    _availableBusy = true;

    try {
      do {
        _availableDirty = false;

        final farmId = _farmId;
        if (!mounted || farmId == null) return;

        final count = await GoatService.instance.availableGoatCount(farmId);

        if (!mounted) return;

        if (farmId != _farmId) {
          // Farm changed while counting; count again for the new one.
          _availableDirty = true;
          continue;
        }

        setState(() => _availableCount = count);
      } while (_availableDirty);
    } catch (_) {
      // Keep showing the last known number.
    } finally {
      _availableBusy = false;
    }
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
      // Repairs any lot payment / purchase that is missing its Finance row
      // (idempotent — see TradingService.reconcileLotFinance).
      await TradingService.instance.reconcileLotFinance(farmId);
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

  /// First open of the session: same recalculation as pull-to-refresh, but
  /// invisible. A failure is ignored (the next pull-to-refresh retries) and
  /// the farm is forgotten so the next open tries again.
  Future<void> _autoSync() async {
    final farmId = _farmId;
    if (farmId == null) return;

    try {
      await TradingService.instance.backfillDashboardSummary(farmId);
      await TradingService.instance.reconcileLotFinance(farmId);
    } catch (_) {
      _syncedFarms.remove(farmId);
    }
  }

  /// Pull-to-refresh: re-check the farm, then re-derive the counts.
  Future<void> _onRefresh() async {
    await _loadFarm(silent: true);
    await Future.wait([
      _recalculateDashboard(quiet: true),
      _refreshAvailable(),
    ]);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  /// Opens [screen]; when the user comes back, the Available count is
  /// re-read (a sale or status change may have happened in there).
  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(fastRoute(screen));
    if (mounted) _refreshAvailable();
  }

  Future<void> _openGoatStock({String? statusFilter}) {
    return _push(GoatStockListScreen(initialStatusFilter: statusFilter));
  }

  /// Total Sold counts individual goats AND goats sold straight from
  /// lots, but the two live in different lists. With no lot sales it
  /// opens the Sold goats exactly as before; otherwise it asks which list.
  Future<void> _openTotalSold(TradingLotOverview lotOverview) async {
    final farmId = _farmId;

    if (farmId == null || lotOverview.lotSoldQty == 0) {
      return _openGoatStock(statusFilter: Goat.statusSold);
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.cardWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Sold goats'),
                subtitle: const Text('Individually registered goats'),
                onTap: () => Navigator.of(sheetContext).pop('goats'),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Lot sales'),
                subtitle: Text(
                  '${lotOverview.lotSoldQty} goat'
                      '${lotOverview.lotSoldQty == 1 ? '' : 's'} sold '
                      'straight from lots',
                ),
                onTap: () => Navigator.of(sheetContext).pop('lots'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'lots') {
      return _push(LotSalesListScreen(farmId: farmId));
    }

    return _openGoatStock(statusFilter: Goat.statusSold);
  }

  /// Booking / Holding opens its own customer-grouped screen (not a flat
  /// goat-stock filter), so a customer's booked goats are delivered — and
  /// paid for — together, exactly like Wait on Delivery.
  Future<void> _openBooking() {
    final farmId = _farmId;
    if (farmId == null) return Future.value();
    return _push(BookingDeliveryCustomerListScreen(farmId: farmId));
  }

  /// Wait on Delivery opens its own customer-grouped screen (not a flat
  /// goat-stock filter).
  Future<void> _openWaitOnDelivery() {
    final farmId = _farmId;
    if (farmId == null) return Future.value();
    return _push(WaitDeliveryCustomerListScreen(farmId: farmId));
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

  Future<void> _openReceiveLot(TradingPurchase lot) async {
    final farmId = _farmId;
    if (farmId == null) return;

    final saved = await Navigator.of(context).push<bool>(
      fastRoute(ReceiveLotScreen(farmId: farmId, lot: lot)),
    );

    if (saved == true) {
      _snack('Receiving saved.', AppColors.darkGreen);
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

          // One subscription feeds the lot numbers everywhere below —
          // the overview strip, the "Purchase Lots" hero, and Pending
          // Receiving. See TradingLotOverview's doc comment for why the
          // dashboard no longer reads lot stock from the stored
          // tradingSummary counters.
          StreamBuilder<TradingLotOverview>(
            stream: _lotOverviewStream,
            builder: (context, lotSnap) {
              final lotOverview = lotSnap.data ?? TradingLotOverview.empty();

              return Column(
                children: [
                  StreamBuilder<TradingSummary>(
                    stream: _summaryStream,
                    builder: (context, snap) {
                      final summary = snap.data ?? TradingSummary.empty;
                      return Column(
                        children: [
                          _overview(snap, summary, lotOverview),
                          const SizedBox(height: 18),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _pendingSection(lotSnap, lotOverview),
                ],
              );
            },
          ),
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

  Widget _overview(
      AsyncSnapshot<TradingSummary> snap,
      TradingSummary s,
      TradingLotOverview lotOverview,
      ) {
    if (snap.hasError) {
      return _errorCard('Unable to load trading summary. Pull down to refresh.');
    }

    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const _Pulse(child: _OverviewSkeleton());
    }

    final availableInLots = lotOverview.farmAvailableQty;

    return Column(
      children: [
        _pair(
          _StatCard(
            icon: GoatIcons.paw,
            label: 'Available Stock',
            // Individually-registered goats marked Available, plus goats
            // sitting free inside a lot at the farm (not yet transferred,
            // not reserved) — the badge breaks out the lot half so the
            // number doesn't look unexplained next to Goat Stock, which
            // only ever shows the individually-registered half.
            value: _availableCount == null
                ? '—'
                : '${_availableCount! + availableInLots}',
            badge: availableInLots > 0 ? '$availableInLots in lots' : null,
            color: AppColors.primaryGreen,
            onTap: () => _openGoatStock(statusFilter: Goat.statusAvailable),
          ),
          _StatCard(
            icon: Icons.event_available_outlined,
            label: 'Booking',
            value: '${s.booking}',
            color: Colors.deepPurple,
            badge: s.booking > 0 ? 'Deposit paid' : null,
            onTap: _openBooking,
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
            onTap: _openWaitOnDelivery,
          ),
          _StatCard(
            icon: Icons.sell_outlined,
            label: 'Total Sold',
            value: '${s.totalSold}',
            color: AppColors.error,
            badge: s.totalSold > 0 ? 'Sold Out' : null,
            onTap: () => _openTotalSold(lotOverview),
          ),
          height: 116,
        ),
        const SizedBox(height: 10),
        _secondaryStats(s, lotOverview),
        _lotFigures(lotOverview),
      ],
    );
  }

  Widget _secondaryStats(TradingSummary s, TradingLotOverview lotOverview) {
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
              subtitle: '${s.wholesalePurchased} head • Purchase or sell from lots',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CompactActionButton(
                    label: 'Purchase',
                    icon: Icons.add_shopping_cart_rounded,
                    color: AppColors.primaryGreen,
                    onTap: () => _push(const PurchaseGoatsWizardScreen()),
                  ),
                  const SizedBox(width: 6),
                  _CompactActionButton(
                    label: 'Sell',
                    icon: Icons.sell_outlined,
                    color: AppColors.tradingBlue,
                    onTap: () => _push(const SellFromLotWizardScreen()),
                  ),
                ],
              ),
            ),
            divider,
            _StripRow(
              icon: Icons.currency_rupee_rounded,
              color: AppColors.error,
              title: 'Supplier Payments Due',
              subtitle: 'Owed across all lots',
              subtitleColor: AppColors.error,
              onTap: () {
                final farmId = _farmId;
                if (farmId == null) return;
                _push(LotManagementScreen(farmId: farmId));
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  lotOverview.supplierDue >= 0.01
                      ? _Pill(_inr.format(lotOverview.supplierDue),
                      AppColors.error)
                      : const _Pill('Fully paid', AppColors.success),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textGrey,
                  ),
                ],
              ),
            ),
            // Only the lot-first purchases show above. A purchase made
            // before lots existed still needs one-by-one registration
            // until it's converted (TradingService.
            // convertLegacyPurchasesToLots) — this strip is the only way
            // to reach that old flow now, and disappears on its own once
            // nothing is left to convert.
            if (lotOverview.legacyPendingRegistrations > 0) ...[
              divider,
              _StripRow(
                icon: Icons.description_outlined,
                color: AppColors.warning,
                title: 'Older Purchases to Register',
                subtitle: 'From before Purchase Lots — register one by one',
                subtitleColor: AppColors.warning,
                onTap: () => _push(const SelectPurchaseScreen()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Pill(
                      '${lotOverview.legacyPendingRegistrations} Pending',
                      AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textGrey,
                    ),
                  ],
                ),
              ),
            ],
            divider,
            _StripRow(
              icon: Icons.trending_up_rounded,
              color: AppColors.success,
              title: 'Total Trading Profit',
              subtitle: 'Current realized trading margin',
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

  /// Purchase Lot money and stock totals (PDF §2, D1 §17): goats bought and
  /// still held, total purchase amount, paid to suppliers, sales revenue and
  /// customer pending. Hidden until the farm has bought its first lot.
  ///
  /// Purchase / paid figures come from [lotOverview] (already live); sales
  /// revenue and customer pending come from one query of the lot sales, so
  /// they are the same numbers Lot Sales and every Lot Detail add up to.
  /// Supplier pending is the "Supplier Payments Due" row above.
  Widget _lotFigures(TradingLotOverview lotOverview) {
    if (lotOverview.totalPurchasedQty == 0) return const SizedBox.shrink();

    const divider = Divider(
      height: 1,
      indent: 12,
      endIndent: 12,
      color: AppColors.divider,
    );

    void openLotSales() {
      final farmId = _farmId;
      if (farmId == null) return;
      _push(LotSalesListScreen(farmId: farmId));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: AppTheme.card(radius: 16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              _StripRow(
                icon: Icons.layers_outlined,
                color: AppColors.primaryGreen,
                title: 'Goats in Lots',
                subtitle:
                '${lotOverview.totalPurchasedQty} bought • '
                    '${lotOverview.lotSoldQty} sold',
                trailing: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${lotOverview.remainingQty}',
                        style: AppTheme.heading(
                          size: 15,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      TextSpan(
                        text: ' remaining',
                        style: AppTheme.body(size: 10),
                      ),
                    ],
                  ),
                ),
              ),
              divider,
              _StripRow(
                icon: Icons.shopping_bag_outlined,
                color: AppColors.info,
                title: 'Total Purchase Amount',
                subtitle: 'Bought from suppliers',
                trailing: Text(
                  _inr.format(lotOverview.totalPurchaseAmount),
                  style: AppTheme.heading(size: 14.5, color: AppColors.info),
                ),
              ),
              divider,
              _StripRow(
                icon: Icons.account_balance_wallet_outlined,
                color: AppColors.success,
                title: 'Paid to Suppliers',
                subtitle: 'All supplier payments so far',
                trailing: Text(
                  _inr.format(lotOverview.totalPaidToSuppliers),
                  style: AppTheme.heading(size: 14.5, color: AppColors.success),
                ),
              ),
              divider,
              StreamBuilder<List<Sale>>(
                stream: _lotSalesStream,
                builder: (context, snap) {
                  final ready = snap.hasData;
                  final totals = ready
                      ? LotSalesTotals.from(snap.data!)
                      : const LotSalesTotals();

                  String money(double v) => ready ? _inr.format(v) : '—';

                  // Booked / Wait-for-Delivery sales are not revenue or
                  // pending until the goats are delivered, so say so when
                  // some are waiting (otherwise the totals look short).
                  final waiting = totals.openGoats > 0
                      ? ' \u2022 ${totals.openGoats} still waiting'
                      : '';

                  return Column(
                    children: [
                      _StripRow(
                        icon: Icons.trending_up_rounded,
                        color: AppColors.tradingBlue,
                        title: 'Sales Revenue',
                        subtitle: 'Delivered sales$waiting',
                        onTap: openLotSales,
                        trailing: Text(
                          money(totals.revenue),
                          style: AppTheme.heading(
                            size: 14.5,
                            color: AppColors.tradingBlue,
                          ),
                        ),
                      ),
                      divider,
                      _StripRow(
                        icon: Icons.hourglass_bottom_rounded,
                        color: AppColors.warning,
                        title: 'Customer Pending',
                        subtitle: totals.openGoats > 0
                            ? 'Delivered sales$waiting'
                            : 'To collect on delivered sales',
                        subtitleColor: totals.customerPending >= 0.01
                            ? AppColors.warning
                            : null,
                        onTap: openLotSales,
                        trailing: ready && totals.customerPending < 0.01
                            ? const _Pill('All collected', AppColors.success)
                            : Text(
                          money(totals.customerPending),
                          style: AppTheme.heading(
                            size: 14.5,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PENDING RECEIVING
  // ===========================================================================

  Widget _pendingSection(
      AsyncSnapshot<TradingLotOverview> lotSnap,
      TradingLotOverview lotOverview,
      ) {
    if (lotSnap.hasError) {
      return _errorCard(
        'Unable to load pending receiving records. Pull down to refresh.',
      );
    }

    if (lotSnap.connectionState == ConnectionState.waiting &&
        !lotSnap.hasData) {
      return const _Pulse(child: _PendingSkeleton());
    }

    final purchases = lotOverview.pendingReceiving;
    return purchases.isEmpty ? _pendingEmpty() : _pendingList(purchases);
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
              color: AppColors.success.withValues(alpha: 0.10),
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
    if (p.isLot) return _pendingLotCard(p);

    final rows = <Widget>[
      _InfoRow(Icons.person_outline, 'Seller', p.sellerName),
      _InfoRow(GoatIcons.paw, 'Goats', '${p.totalGoats}'),
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
              color: AppColors.paleGreen.withValues(alpha: 0.55),
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
              color: AppColors.primaryGreen.withValues(alpha: 0.07),
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

  /// A lot can be "pending" here even with `receivingStatus == completed`
  /// (that field only reflects whether receiving finished, not whether
  /// anything is still at the supplier — see TradingLotOverview). So the
  /// headline number is always "X of Y at supplier", never a status word.
  Widget _pendingLotCard(TradingPurchase lot) {
    final status = lot.paymentStatus;
    final statusColor = status == 'Paid'
        ? AppColors.success
        : status == 'Partial'
        ? AppColors.warning
        : AppColors.error;

    final rows = <Widget>[
      _InfoRow(Icons.person_outline, 'Seller', lot.sellerName),
      _InfoRow(
        GoatIcons.paw,
        'At Supplier',
        '${lot.supplierQty} of ${lot.totalGoats}',
      ),
      _InfoRow(
        Icons.calendar_today_outlined,
        'Purchase Date',
        _dateFmt.format(lot.purchaseDate),
      ),
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
                icon: Icons.layers_outlined,
                color: AppColors.tradingBlue,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lot', style: AppTheme.body(size: 10)),
                    Text(
                      lot.lotId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(size: 13),
                    ),
                  ],
                ),
              ),
              _Pill(supplierPaymentStatusLabel(status), statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.paleGreen.withValues(alpha: 0.55),
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
          if (lot.dueAmount >= 0.01) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.currency_rupee,
                    color: AppColors.error,
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Balance Due',
                      style: AppTheme.body(size: 10.5),
                    ),
                  ),
                  Text(
                    _inr.format(lot.dueAmount),
                    style: AppTheme.heading(size: 14, color: AppColors.error),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => _openReceiveLot(lot),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text(
                'Receive Lot',
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
        color: color.withValues(alpha: 0.10),
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
        color: solid ? color : color.withValues(alpha: 0.10),
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

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTheme.heading(size: 9.5, color: color),
              ),
            ],
          ),
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
        color: AppColors.textGrey.withValues(alpha: 0.18),
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
