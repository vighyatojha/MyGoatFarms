import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/trading_lot_overview.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/partner_access_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../widgets/permission_gate.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import 'cancel_lot_deal_screen.dart';
import 'edit_lot_screen.dart';
import 'legacy_conversion_sheet.dart';
import 'lot_sales_list_screen.dart';
import 'lot_detail_screen.dart';
import 'lot_widgets.dart';

/// Every size on this screen (paddings, radii, icons, fonts) goes through
/// [_s], so the whole layout can be tightened or relaxed from one place.
/// 0.95 = 5 % more compact than the original layout.
const double _kScale = 0.95;

double _s(double value) => value * _kScale;

/// Lot Management — every purchase lot, filterable by where the goats are
/// (At Supplier / Partially Received / At Farm) and by Active vs Completed.
///
/// A lot is Active while it still owns goats (supplier + farm quantity > 0)
/// and Completed once everything has been sold or moved out to Palai (or
/// the deal was cancelled).
///
/// The location filter only applies to Active lots. A completed lot owns no
/// goats any more, so "At Supplier / At Farm" says nothing about it — its
/// card instead shows where every goat went (sold / died / moved to Palai).
class LotManagementScreen extends StatefulWidget {
  final String farmId;

  const LotManagementScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<LotManagementScreen> createState() => _LotManagementScreenState();
}

class _LotManagementScreenState extends State<LotManagementScreen> {
  late final Stream<List<TradingPurchase>> _stream;

  /// Only used to know how many older purchases are still unconverted.
  late final Stream<TradingLotOverview> _overviewStream;

  bool _showCompleted = false;

  /// null = all locations. Only used while Active is showing.
  LotLocation? _location;

  @override
  void initState() {
    super.initState();

    // Created once: recreating a stream on every rebuild makes the list
    // flash back to its loading state.
    // Live Firestore listener. TradingService reads
    // farms/{farmId}/tradingPurchases and converts every lot document into
    // TradingPurchase, so the card is rebuilt whenever a purchase,
    // receiving, sale, transfer or death changes its counters.
    _stream = TradingService.instance.lotsStream(widget.farmId);
    _overviewStream =
        TradingService.instance.lotOverviewStream(widget.farmId);
  }

  Future<void> _openConversion() async {
    final converted = await showLegacyConversionSheet(
      context: context,
      farmId: widget.farmId,
    );

    if (converted == true && mounted) {
      wizardSnack(
        context,
        'Older purchases are now in Lot Management.',
      );
    }
  }

  bool _canEdit(TradingPurchase lot) =>
      lot.isLot &&
          !lot.dealCancelled &&
          PartnerAccessService.instance
              .allows(PartnerPermissionKeys.tradingManageStock);

  bool _canCancelDeal(TradingPurchase lot) =>
      lot.canCancelDeal &&
          PartnerAccessService.instance
              .allows(PartnerPermissionKeys.tradingSupplierPayment);

  Future<void> _editLot(TradingPurchase lot) async {
    final saved = await openEditLotScreen(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (saved == true && mounted) {
      wizardSnack(context, 'Lot updated.');
    }
  }

  Future<void> _cancelDeal(TradingPurchase lot) async {
    final cancelled = await openCancelLotDealScreen(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (cancelled == true && mounted) {
      wizardSnack(
        context,
        'Deal cancelled and settled.',
      );
    }
  }

  List<TradingPurchase> _filter(List<TradingPurchase> all) {
    return all.where((lot) {
      if (lot.isActive == _showCompleted) {
        return false;
      }

      // Location only means something while the lot still owns goats.
      if (!_showCompleted &&
          _location != null &&
          lot.location != _location) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: PartnerPermissionKeys.tradingView,
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Lot Management'),
        actions: [
          IconButton(
            tooltip: 'Lot sales',
            icon: const Icon(
              Icons.receipt_long_outlined,
            ),
            onPressed: () {
              Navigator.of(context).push(
                fastRoute(
                  LotSalesListScreen(
                    farmId: widget.farmId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<TradingPurchase>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  FirestoreService.instance
                      .describeError(snapshot.error!),
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 13),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final all = snapshot.data!;
          final lots = _filter(all);

          final activeCount =
              all.where((l) => l.isActive).length;
          final completedCount =
              all.length - activeCount;

          return Column(
            children: [
              _legacyBanner(),
              _statusToggle(
                activeCount,
                completedCount,
              ),
              if (!_showCompleted) _locationChips(),
              Expanded(
                child: lots.isEmpty
                    ? _empty(all.isEmpty)
                    : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    _s(16),
                    _s(8),
                    _s(16),
                    _s(24),
                  ),
                  itemCount: lots.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: _s(10)),
                  itemBuilder: (_, i) {
                    final lot = lots[i];

                    return _LotCard(
                      lot: lot,
                      onEdit: _canEdit(lot)
                          ? () => _editLot(lot)
                          : null,
                      onCancelDeal: _canCancelDeal(lot)
                          ? () => _cancelDeal(lot)
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(
                            LotDetailScreen(
                              farmId: widget.farmId,
                              lotDocId: lot.id,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shown only while older purchases are still unconverted.
  Widget _legacyBanner() {
    return StreamBuilder<TradingLotOverview>(
      stream: _overviewStream,
      builder: (context, snapshot) {
        final count =
            snapshot.data?.unconvertedPurchases ?? 0;

        if (count == 0) {
          return const SizedBox.shrink();
        }

        final isOwner =
        !PartnerAccessService.instance.isPartner;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            _s(16),
            _s(10),
            _s(16),
            0,
          ),
          child: Container(
            padding: EdgeInsets.all(_s(13)),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(_s(16)),
              border: Border.all(
                color: AppColors.warning.withValues(
                  alpha: 0.30,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: _s(36),
                  height: _s(36),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(
                      alpha: 0.12,
                    ),
                    borderRadius:
                    BorderRadius.circular(_s(10)),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    color: AppColors.warning,
                    size: _s(21),
                  ),
                ),
                SizedBox(width: _s(11)),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count older purchase'
                            '${count == 1 ? '' : 's'} '
                            'not shown here',
                        style: AppTheme.heading(
                          size: _s(13.5),
                        ),
                      ),
                      SizedBox(height: _s(3)),
                      Text(
                        isOwner
                            ? 'Convert them to lots to receive, '
                            'sell, register and transfer their '
                            'goats from here.'
                            : 'The farm owner needs to convert '
                            'them before they appear here.',
                        style: AppTheme.body(
                          size: _s(10.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOwner) ...[
                  SizedBox(width: _s(6)),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: _s(8),
                        vertical: _s(6),
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _openConversion,
                    child: const Text(
                      'Convert',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusToggle(
      int active,
      int completed,
      ) {
    Widget tab(
        String label,
        bool selected,
        VoidCallback onTap,
        ) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration:
            const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding:
            EdgeInsets.symmetric(vertical: _s(10)),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryGreen
                  : Colors.transparent,
              borderRadius:
              BorderRadius.circular(_s(12)),
              boxShadow: selected
                  ? [
                BoxShadow(
                  color: AppColors.primaryGreen
                      .withValues(alpha: 0.16),
                  blurRadius: _s(8),
                  offset: Offset(0, _s(3)),
                ),
              ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: _s(13),
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : AppColors.textGrey,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16),
        _s(10),
        _s(16),
        _s(4),
      ),
      child: Container(
        padding: EdgeInsets.all(_s(4)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_s(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: 0.035,
              ),
              blurRadius: _s(10),
              offset: Offset(0, _s(3)),
            ),
          ],
        ),
        child: Row(
          children: [
            tab(
              'Active ($active)',
              !_showCompleted,
                  () => setState(
                    () => _showCompleted = false,
              ),
            ),
            tab(
              'Completed ($completed)',
              _showCompleted,
                  () => setState(
                    () => _showCompleted = true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationChips() {
    Widget chip(
        String label,
        LotLocation? value,
        ) {
      final selected = _location == value;

      return Padding(
        padding: EdgeInsets.only(right: _s(8)),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) {
            setState(() {
              _location = value;
            });
          },
          selectedColor: AppColors.lightGreen,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: selected
                ? AppColors.primaryGreen
                .withValues(alpha: 0.25)
                : AppColors.divider,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(_s(11)),
          ),
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: _s(11),
            fontWeight: FontWeight.w600,
            color: selected
                ? AppColors.darkGreen
                : AppColors.textGrey,
          ),
        ),
      );
    }

    return SizedBox(
      height: _s(47),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          _s(16),
          _s(4),
          _s(8),
          _s(5),
        ),
        children: [
          chip('All', null),
          chip(
            'At Supplier',
            LotLocation.atSupplier,
          ),
          chip(
            'Partially Received',
            LotLocation.partiallyAtFarm,
          ),
          chip(
            'At Farm',
            LotLocation.atFarm,
          ),
        ],
      ),
    );
  }

  Widget _empty(bool noLotsAtAll) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(_s(32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _s(70),
              height: _s(70),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius:
                BorderRadius.circular(_s(22)),
              ),
              child: Icon(
                _showCompleted
                    ? Icons.task_alt_rounded
                    : Icons.inventory_2_outlined,
                size: _s(34),
                color: AppColors.darkGreen,
              ),
            ),
            SizedBox(height: _s(14)),
            Text(
              noLotsAtAll
                  ? 'No lots yet'
                  : _showCompleted
                  ? 'No completed lots'
                  : 'No active lots here',
              style: AppTheme.heading(size: _s(17)),
            ),
            SizedBox(height: _s(6)),
            Text(
              noLotsAtAll
                  ? 'Lots you purchase will appear here.'
                  : _showCompleted
                  ? 'A lot appears here once all its goats are '
                  'sold or moved out, or its deal is cancelled.'
                  : 'Try a different filter.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: _s(12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LotCard extends StatelessWidget {
  final TradingPurchase lot;
  final VoidCallback onTap;

  /// Null when the person may not edit this lot.
  final VoidCallback? onEdit;

  /// Null unless the deal can still be cancelled.
  final VoidCallback? onCancelDeal;

  const _LotCard({
    required this.lot,
    required this.onTap,
    this.onEdit,
    this.onCancelDeal,
  });

  /// Completed = no longer owns goats, but not a cancelled deal.
  bool get _isCompleted => !lot.isActive && !lot.dealCancelled;

  @override
  Widget build(BuildContext context) {
    final status = lot.paymentStatus;

    final accent = lot.dealCancelled
        ? AppColors.error
        : _isCompleted
        ? AppColors.success
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_s(20)),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            _s(14),
            _s(13),
            _s(14),
            _s(12),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(_s(20)),
            border: accent == null
                ? null
                : Border.all(
              color: accent.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.045,
                ),
                blurRadius: _s(12),
                offset: Offset(0, _s(4)),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              _header(),
              SizedBox(height: _s(3)),
              Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: _s(12.5),
                    color: AppColors.textGrey,
                  ),
                  SizedBox(width: _s(4)),
                  Expanded(
                    child: Text(
                      '${lot.sellerName} • '
                          '${wizardDate(lot.purchaseDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: _s(11.5),
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: _s(11)),
              Container(
                height: 1,
                color: AppColors.divider.withValues(
                  alpha: 0.70,
                ),
              ),
              SizedBox(height: _s(11)),

              // Every figure below is derived from the live
              // TradingPurchase (never cached): the model reads the
              // Firestore lot fields (totalGoats, soldFromSupplierQty,
              // soldFromFarmQty, receivedAliveQty, mortality,
              // registeredCount) and computes the quantities from them.
              if (lot.dealCancelled)
                _cancelledStats()
              else if (_isCompleted)
                _completedStats()
              else
                _activeStats(),

              if (!_isCompleted &&
                  !lot.dealCancelled &&
                  lot.unsoldOutLabel.isNotEmpty) ...[
                SizedBox(height: _s(10)),
                _informationLine(
                  text:
                  '${lot.unsoldOutLabel} (not sold)',
                ),
              ],

              if (lot.dealCancelled) ...[
                SizedBox(height: _s(10)),
                _informationLine(
                  text: 'Deal cancelled before any goats were '
                      'received or sold.',
                ),
              ],

              SizedBox(height: _s(11)),
              _paymentRow(status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final String badgeLabel;
    final Color badgeColor;

    if (lot.dealCancelled) {
      badgeLabel = 'Deal Cancelled';
      badgeColor = AppColors.error;
    } else if (_isCompleted) {
      // A finished lot owns no goats, so "At Farm" / "At Supplier" would
      // be misleading. Say what it is.
      badgeLabel = 'Completed';
      badgeColor = AppColors.success;
    } else {
      badgeLabel = lotLocationLabel(lot.location);
      badgeColor = lotLocationColor(lot.location);
    }

    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            lot.lotId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(
              size: _s(16),
              color: AppColors.primaryGreen,
            ),
          ),
        ),
        SizedBox(width: _s(8)),
        LotBadge(
          label: badgeLabel,
          color: badgeColor,
        ),
        if (onEdit != null || onCancelDeal != null)
          SizedBox(
            width: _s(34),
            height: _s(34),
            child: PopupMenuButton<String>(
              tooltip: 'Lot options',
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert_rounded,
                size: _s(20),
                color: AppColors.textGrey,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit?.call();
                }

                if (value == 'cancel') {
                  onCancelDeal?.call();
                }
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text('Edit lot'),
                      ],
                    ),
                  ),
                if (onCancelDeal != null)
                  const PopupMenuItem<String>(
                    value: 'cancel',
                    child: Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          size: 20,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Cancel deal',
                          style: TextStyle(
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------------

  // Colours shared by the tiles.
  static const _blue = (bg: Color(0xFFEAF2FF), fg: Color(0xFF3569A8));
  static const _red = (bg: Color(0xFFFFEEF0), fg: Color(0xFFD25563));
  static const _green = (bg: Color(0xFFEAF8EF), fg: Color(0xFF31965A));
  static const _purple = (bg: Color(0xFFF0EEFF), fg: Color(0xFF6757B7));
  static const _teal = (bg: Color(0xFFE8F7F1), fg: Color(0xFF278B68));
  static const _grey = (bg: Color(0xFFF1F3F1), fg: Color(0xFF68756A));
  static const _amber = (bg: Color(0xFFFFF4E0), fg: Color(0xFFB26A00));

  Widget _gap() => SizedBox(width: _s(7));

  /// Active lot: where every goat that is still owned is right now.
  Widget _activeStats() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statTile(
                label: 'Purchased',
                value: lot.totalGoats,
                icon: Icons.shopping_cart_outlined,
                colors: _blue,
              ),
            ),
            _gap(),
            Expanded(
              child: _statTile(
                label: 'Sold',
                value: lot.soldQty,
                icon: Icons.sell_outlined,
                colors: _red,
              ),
            ),
            _gap(),
            Expanded(
              child: _statTile(
                label: 'Remaining',
                value: lot.remainingQty,
                icon: Icons.inventory_2_outlined,
                colors: _green,
              ),
            ),
          ],
        ),
        SizedBox(height: _s(7)),
        Row(
          children: [
            Expanded(
              child: _statTile(
                label: 'At Supplier',
                value: lot.supplierQty,
                icon: Icons.local_shipping_outlined,
                colors: _purple,
              ),
            ),
            _gap(),
            Expanded(
              child: _statTile(
                label: 'At Farm',
                value: lot.farmQty,
                icon: Icons.home_work_outlined,
                colors: _teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Completed lot: where every goat went. Nothing is left, so
  /// Remaining / At Supplier / At Farm (all 0) are not repeated; instead
  /// the tiles reconcile exactly:
  ///   Purchased = Sold + Died + Moved to Palai
  Widget _completedStats() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            label: 'Purchased',
            value: lot.totalGoats,
            icon: Icons.shopping_cart_outlined,
            colors: _blue,
          ),
        ),
        _gap(),
        Expanded(
          child: _statTile(
            label: 'Sold',
            value: lot.soldQty,
            icon: Icons.sell_outlined,
            colors: _red,
          ),
        ),
        _gap(),
        Expanded(
          child: _statTile(
            label: 'Died',
            value: lot.mortality,
            icon: Icons.heart_broken_outlined,
            colors: lot.mortality > 0 ? _amber : _grey,
          ),
        ),
        _gap(),
        Expanded(
          child: _statTile(
            label: 'To Palai',
            value: lot.registeredCount,
            icon: Icons.swap_horiz_rounded,
            colors: lot.registeredCount > 0 ? _teal : _grey,
          ),
        ),
      ],
    );
  }

  /// Cancelled deal: the goats were never taken, so only the purchase size
  /// is meaningful.
  Widget _cancelledStats() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            label: 'Purchased',
            value: lot.totalGoats,
            icon: Icons.shopping_cart_outlined,
            colors: _blue,
          ),
        ),
        _gap(),
        const Expanded(flex: 3, child: SizedBox.shrink()),
      ],
    );
  }

  Widget _statTile({
    required String label,
    required int value,
    required IconData icon,
    required ({Color bg, Color fg}) colors,
  }) {
    return Container(
      constraints: BoxConstraints(
        minHeight: _s(64),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: _s(7),
        vertical: _s(7),
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(_s(12)),
        border: Border.all(
          color: colors.fg.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: _s(11),
                color: colors.fg.withValues(alpha: 0.72),
              ),
              SizedBox(width: _s(3)),
              Text(
                value.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTheme.heading(
                  size: _s(15),
                  color: colors.fg,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: _s(2)),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: _s(8.8),
              color: colors.fg.withValues(alpha: 0.78),
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _informationLine({
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _s(10),
        vertical: _s(8),
      ),
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withValues(
          alpha: 0.65,
        ),
        borderRadius:
        BorderRadius.circular(_s(10)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: _s(15),
            color: AppColors.darkGreen,
          ),
          SizedBox(width: _s(7)),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                size: _s(10.5),
                color: AppColors.darkGreen,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentRow(
      dynamic status,
      ) {
    final String amountText;

    if (lot.dealCancelled) {
      amountText =
      'Loss ${wizardCurrency(lot.cancelLossAmount)}'
          '  •  Refunded '
          '${wizardCurrency(lot.cancelRefundAmount)}';
    } else if (lot.dueAmount >= 0.01) {
      amountText =
      'Due ${wizardCurrency(lot.dueAmount)}';
    } else {
      amountText = 'Fully paid';
    }

    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            amountText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: _s(11.5),
              color: AppColors.textDark,
              weight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: _s(8)),
        LotBadge(
          label: supplierPaymentStatusLabel(status),
          color: lotPaymentColor(status),
        ),
      ],
    );
  }
}