import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/permission_gate.dart';
import 'lot_detail_screen.dart';
import 'lot_widgets.dart';

/// Lot Stock — a compact "how many goats are where" view of every ACTIVE
/// lot (PDF §2, D1 §6).
///
/// Lot Management is for running lots (filters, completed lots, payments);
/// this screen answers one question: what stock do the lots hold right
/// now — at the supplier, at the farm, reserved, and free to sell.
/// Tapping a lot opens its Lot Detail.
class LotStockScreen extends StatefulWidget {
  final String farmId;

  const LotStockScreen({super.key, required this.farmId});

  @override
  State<LotStockScreen> createState() => _LotStockScreenState();
}

class _LotStockScreenState extends State<LotStockScreen> {
  late final Stream<List<TradingPurchase>> _stream =
  TradingService.instance.activeLotsStream(widget.farmId);

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: PartnerPermissionKeys.tradingView,
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(title: const Text('Lot Stock')),
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

            final lots = snapshot.data!;

            if (lots.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 44,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(height: 12),
                      Text('No goats in lots', style: AppTheme.heading(size: 16)),
                      const SizedBox(height: 4),
                      Text(
                        'Active lots and the goats they hold will show here.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 12.5),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _totals(lots),
                const SizedBox(height: 14),
                for (final lot in lots) ...[
                  _lotCard(lot),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _totals(List<TradingPurchase> lots) {
    // Free goats only: booked ones are promised to customers and shown
    // under Booked, not counted as stock until the deal is cancelled.
    final supplier = lots.fold<int>(0, (s, l) => s + l.supplierAvailableQty);
    final farm = lots.fold<int>(0, (s, l) => s + l.farmAvailableQty);
    final reserved = lots.fold<int>(0, (s, l) => s + l.reservedQty);
    final available = lots.fold<int>(0, (s, l) => s + l.availableForSaleQty);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${lots.length} active lot${lots.length == 1 ? '' : 's'} • '
                '${supplier + farm} goats'
                '${reserved > 0 ? ' (+$reserved booked)' : ''}',
            style: AppTheme.heading(size: 14.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('At Supplier', supplier),
              _stat('At Farm', farm),
              _stat('Booked', reserved),
              _stat('Available', available, emphasize: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, {bool emphasize = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.body(size: 10.5)),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: AppTheme.heading(
              size: 17,
              color: emphasize ? AppColors.primaryGreen : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lotCard(TradingPurchase lot) {
    final location = lot.location;

    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          fastRoute(
            LotDetailScreen(farmId: widget.farmId, lotDocId: lot.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${lot.lotId} • ${lot.sellerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(size: 14.5),
                    ),
                  ),
                  LotBadge(
                    label: lotLocationLabel(location),
                    color: lotLocationColor(location),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Bought ${lot.totalGoats} • Sold ${lot.soldQty}',
                style: AppTheme.body(size: 11.5),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _stat('At Supplier', lot.supplierAvailableQty),
                  _stat('At Farm', lot.farmAvailableQty),
                  _stat('Booked', lot.reservedQty),
                  _stat('Available', lot.availableForSaleQty, emphasize: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}