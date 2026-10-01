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
import 'legacy_conversion_sheet.dart';
import 'lot_sales_list_screen.dart';
import 'lot_detail_screen.dart';
import 'lot_widgets.dart';

/// Lot Management — every purchase lot, filterable by where the goats are
/// (At Supplier / Partially Received / At Farm) and by Active vs Completed.
///
/// A lot is Active while it still owns goats (supplier + farm quantity > 0)
/// and Completed once everything has been sold or moved out to Palai.
class LotManagementScreen extends StatefulWidget {
  final String farmId;

  const LotManagementScreen({super.key, required this.farmId});

  @override
  State<LotManagementScreen> createState() => _LotManagementScreenState();
}

class _LotManagementScreenState extends State<LotManagementScreen> {
  late final Stream<List<TradingPurchase>> _stream;

  /// Only used to know how many older purchases are still unconverted.
  late final Stream<TradingLotOverview> _overviewStream;

  bool _showCompleted = false;

  /// null = all locations.
  LotLocation? _location;

  @override
  void initState() {
    super.initState();
    // Created once: recreating a stream on every rebuild makes the list
    // flash back to its loading state.
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
      wizardSnack(context, 'Older purchases are now in Lot Management.');
    }
  }

  List<TradingPurchase> _filter(List<TradingPurchase> all) {
    return all.where((lot) {
      if (lot.isActive == _showCompleted) return false;
      if (_location != null && lot.location != _location) return false;
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
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              fastRoute(LotSalesListScreen(farmId: widget.farmId)),
            ),
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
                  FirestoreService.instance.describeError(snapshot.error!),
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 13),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          final lots = _filter(all);

          final activeCount = all.where((l) => l.isActive).length;
          final completedCount = all.length - activeCount;

          return Column(
            children: [
              _legacyBanner(),
              _statusToggle(activeCount, completedCount),
              _locationChips(),
              Expanded(
                child: lots.isEmpty
                    ? _empty(all.isEmpty)
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: lots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _LotCard(
                    lot: lots[i],
                    onTap: () => Navigator.of(context).push(
                      fastRoute(
                        LotDetailScreen(
                          farmId: widget.farmId,
                          lotDocId: lots[i].id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shown only while older (goat-first) purchases are still unconverted.
  /// The owner gets the Convert button; an invited partner just sees why
  /// some purchases are missing from the list.
  Widget _legacyBanner() {
    return StreamBuilder<TradingLotOverview>(
      stream: _overviewStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.unconvertedPurchases ?? 0;

        if (count == 0) return const SizedBox.shrink();

        final isOwner = !PartnerAccessService.instance.isPartner;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: AppColors.warning,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count older purchase${count == 1 ? '' : 's'} '
                            'not shown here',
                        style: AppTheme.heading(size: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOwner
                            ? 'Convert them to lots to receive, sell and '
                            'transfer their goats from here.'
                            : 'The farm owner needs to convert them '
                            'before they appear here.',
                        style: AppTheme.body(size: 11.5),
                      ),
                    ],
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _openConversion,
                    child: const Text(
                      'Convert',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  Widget _statusToggle(int active, int completed) {
    Widget tab(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textGrey,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            tab('Active ($active)', !_showCompleted,
                    () => setState(() => _showCompleted = false)),
            tab('Completed ($completed)', _showCompleted,
                    () => setState(() => _showCompleted = true)),
          ],
        ),
      ),
    );
  }

  Widget _locationChips() {
    Widget chip(String label, LotLocation? value) {
      final selected = _location == value;

      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _location = value),
          selectedColor: AppColors.lightGreen,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.darkGreen : AppColors.textGrey,
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        children: [
          chip('All', null),
          chip('At Supplier', LotLocation.atSupplier),
          chip('Partially Received', LotLocation.partiallyAtFarm),
          chip('At Farm', LotLocation.atFarm),
        ],
      ),
    );
  }

  Widget _empty(bool noLotsAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 54,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: 12),
            Text(
              noLotsAtAll
                  ? 'No lots yet'
                  : _showCompleted
                  ? 'No completed lots'
                  : 'No active lots here',
              style: AppTheme.heading(size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              noLotsAtAll
                  ? 'Lots you purchase will appear here.'
                  : 'Try a different filter.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12),
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

  const _LotCard({required this.lot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = lot.paymentStatus;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    lot.lotId,
                    style: AppTheme.heading(
                      size: 16,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const Spacer(),
                  LotBadge(
                    label: lotLocationLabel(lot.location),
                    color: lotLocationColor(lot.location),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${lot.sellerName} • ${wizardDate(lot.purchaseDate)}',
                style: AppTheme.body(size: 12),
              ),
              const Divider(height: 20, color: AppColors.divider),
              Row(
                children: [
                  _stat('Purchased', '${lot.totalGoats}'),
                  _stat('Sold', '${lot.soldQty}'),
                  _stat('Remaining', '${lot.remainingQty}'),
                  _stat('At Supplier', '${lot.supplierQty}'),
                  _stat('At Farm', '${lot.farmQty}'),
                ],
              ),
              if (lot.unsoldOutLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${lot.unsoldOutLabel} (not sold)',
                  style: AppTheme.body(size: 11),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    lot.dueAmount >= 0.01
                        ? 'Due ${wizardCurrency(lot.dueAmount)}'
                        : 'Fully paid',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  LotBadge(
                    label: supplierPaymentStatusLabel(status),
                    color: lotPaymentColor(status),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTheme.heading(size: 15)),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 9.5),
          ),
        ],
      ),
    );
  }
}