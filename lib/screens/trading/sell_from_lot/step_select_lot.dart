import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../lots/lot_widgets.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

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
    // Only a single-location lot picks its source automatically; a
    // partially-received lot leaves the choice to the next step.
    draft.sourceLocation = lot.location == LotLocation.atSupplier
        ? 'supplier'
        : lot.location == LotLocation.atFarm
        ? 'farm'
        : '';

    widget.onSelected();
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
                  Text('No goats available to sell', style: AppTheme.heading(size: 16)),
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
          itemBuilder: (_, i) => _LotTile(lot: lots[i], onTap: () => _select(lots[i])),
        );
      },
    );
  }
}

class _LotTile extends StatelessWidget {
  final TradingPurchase lot;
  final VoidCallback onTap;

  const _LotTile({required this.lot, required this.onTap});

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
                    style: AppTheme.heading(size: 15, color: AppColors.primaryGreen),
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
              Row(
                children: [
                  if (lot.supplierQty > 0)
                    _pill('At Supplier', lot.supplierQty),
                  if (lot.farmAvailableQty > 0)
                    _pill('At Farm', lot.farmAvailableQty),
                ],
              ),
            ],
          ),
        ),
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