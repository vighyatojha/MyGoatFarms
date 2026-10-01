import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../lots/lot_detail_screen.dart';
import '../lots/lot_widgets.dart';

/// Step 1 of Sell From Lot — pick which lot to sell from.
///
/// Only active lots with something available to sell
/// ([TradingPurchase.availableForSaleQty] > 0) are shown.
class StepSelectLot extends StatefulWidget {
  final String farmId;
  final SaleDraft draft;
  final VoidCallback onSelected;

  const StepSelectLot({
    super.key,
    required this.farmId,
    required this.draft,
    required this.onSelected,
  });

  @override
  State<StepSelectLot> createState() => _StepSelectLotState();
}

class _StepSelectLotState extends State<StepSelectLot> {
  late final Stream<List<TradingPurchase>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = TradingService.instance.activeLotsStream(widget.farmId);
  }

  void _select(TradingPurchase lot) {
    final draft = widget.draft;

    draft.lotDocId = lot.id;
    draft.lotDisplayId = lot.lotId;
    // Always pick a valid source so the screen never says "At Farm" while
    // the draft is still empty. Farm goats that are free to sell win;
    // otherwise the goats still at the supplier are the only option. The
    // owner can still switch on the next step when a lot has both.
    draft.sourceLocation =
    lot.farmAvailableQty > 0 ? Sale.sourceFarm : Sale.sourceSupplier;

    widget.onSelected();
  }

  void _openLotDetail(TradingPurchase lot) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LotDetailScreen(
          farmId: widget.farmId,
          lotDocId: lot.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TradingPurchase>>(
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

        final lots = snapshot.data!
            .where((l) => l.availableForSaleQty > 0)
            .toList();

        if (lots.isEmpty) {
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
                    'No goats available to sell',
                    style: AppTheme.heading(size: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every lot is either sold out or reserved by bookings.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(size: 12),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: lots.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _LotTile(
            lot: lots[i],
            onTap: () => _select(lots[i]),
            onViewDetails: () => _openLotDetail(lots[i]),
          ),
        );
      },
    );
  }
}

class _LotTile extends StatelessWidget {
  final TradingPurchase lot;
  final VoidCallback onTap;
  final VoidCallback onViewDetails;

  const _LotTile({
    required this.lot,
    required this.onTap,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    lot.lotId,
                    style: AppTheme.heading(
                      size: 15,
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
              Text(lot.sellerName, style: AppTheme.body(size: 12)),
              const SizedBox(height: 10),

              // Lot | Total | Sold | Remaining | Status (PDF §8).
              Row(
                children: [
                  _figure('Total', '${lot.totalGoats}'),
                  _figure('Sold', '${lot.soldQty}'),
                  _figure('Remaining', '${lot.remainingQty}'),
                  _figure(
                    'Status',
                    lot.isActive ? 'Active' : 'Completed',
                    color: lot.isActive
                        ? AppColors.success
                        : AppColors.textGrey,
                  ),
                ],
              ),
              if (lot.unsoldOutLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${lot.unsoldOutLabel} (not sold)',
                  style: AppTheme.body(size: 11),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (lot.supplierQty > 0)
                    _pill('At Supplier', lot.supplierQty),
                  if (lot.farmAvailableQty > 0)
                    _pill('At Farm', lot.farmAvailableQty),
                ],
              ),

              // Lot details are available from the sales flow only when
              // goats from this lot have actually reached the farm.
              if (lot.farmAvailableQty > 0) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: onViewDetails,
                    icon: const Icon(
                      Icons.inventory_2_outlined,
                      size: 17,
                    ),
                    label: const Text('View Lot Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: BorderSide(
                        color: AppColors.primaryGreen.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _figure(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.heading(
              size: 13.5,
              color: color ?? AppColors.textDark,
            ),
          ),
          const SizedBox(height: 1),
          Text(label, style: AppTheme.body(size: 10)),
        ],
      ),
    );
  }

  Widget _pill(String label, int qty) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$qty $label',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.darkGreen,
          ),
        ),
      ),
    );
  }
}
