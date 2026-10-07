import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/goat_model.dart';
import '../models/sale_model.dart';
import '../models/trading_purchase_model.dart';
import '../services/trading_service.dart';

/// "Which lot did these goats come from?" — shown at the top of a booking
/// with the booking ID: lot number, supplier and purchase date.
///
/// The lot is the sale's own lot for a lot booking, otherwise the lot each
/// goat was bought in (`Goat.purchaseId`). Goats picked from several lots
/// show every lot.
class LotOriginCard extends StatelessWidget {
  final String farmId;
  final String bookingId;
  final List<String> lotDocIds;

  /// Shown as a pill, e.g. "At supplier".
  final String? note;

  const LotOriginCard({
    super.key,
    required this.farmId,
    required this.bookingId,
    required this.lotDocIds,
    this.note,
  });

  /// The lots of [sale] (and its [goats]).
  static List<String> lotsOf(Sale sale, Iterable<Goat> goats) {
    if (sale.isLotSale) return [sale.lotDocId];
    final ids = <String>{
      for (final g in goats)
        if (g.purchaseId.trim().isNotEmpty) g.purchaseId.trim(),
    };
    return ids.toList()..sort();
  }

  /// One read per lot per app session: these cards are rebuilt often.
  static final Map<String, Future<TradingPurchase?>> _cache = {};

  Future<TradingPurchase?> _lot(String id) => _cache.putIfAbsent(
    '$farmId/$id',
        () => TradingService.instance
        .getPurchase(farmId, id)
        .catchError((_) => null),
  );

  static String _display(String docId) {
    final dash = docId.indexOf('-');
    return dash < 0 ? docId : 'LOT-${docId.substring(dash + 1)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 15, color: AppColors.info),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Booking $bookingId',
                  style: AppTheme.heading(size: 12.5),
                ),
              ),
              if (note != null)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    note!,
                    style: AppTheme.body(
                      size: 9.5,
                      color: AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (lotDocIds.isEmpty)
            Text('Lot not recorded', style: AppTheme.body(size: 11))
          else
            for (final id in lotDocIds)
              FutureBuilder<TradingPurchase?>(
                future: _lot(id),
                builder: (context, snap) {
                  final lot = snap.data;
                  final parts = <String>[
                    lot?.lotId ?? _display(id),
                    if (lot != null && lot.sellerName.trim().isNotEmpty)
                      'Supplier: ${lot.sellerName.trim()}',
                    if (lot != null)
                      'Bought ${DateFormat('d MMM yyyy').format(lot.purchaseDate)}',
                  ];
                  return Text(
                    'From ${parts.join(' · ')}',
                    style: AppTheme.body(size: 11, color: AppColors.textDark),
                  );
                },
              ),
        ],
      ),
    );
  }
}