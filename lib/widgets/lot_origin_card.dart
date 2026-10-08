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

  /// False on screens that already show the booking ID in their own
  /// header: the card then reads "Lots" instead of "Booking S-xxxx".
  final bool showBookingHeader;

  /// How many of the booking's goats came from each lot (by lot doc ID),
  /// shown at the end of the lot's line. Null hides the count.
  final Map<String, int>? goatsByLot;

  const LotOriginCard({
    super.key,
    required this.farmId,
    required this.bookingId,
    required this.lotDocIds,
    this.note,
    this.showBookingHeader = true,
    this.goatsByLot,
  });

  /// How many goats of [sale] came from each lot: the sale's quantity for
  /// a lot booking, otherwise its goats counted by `Goat.purchaseId`.
  static Map<String, int> goatsByLotOf(Sale sale, Iterable<Goat> goats) {
    if (sale.isLotSale) return {sale.lotDocId: sale.lotQuantity};
    final counts = <String, int>{};
    for (final g in goats) {
      final id = g.purchaseId.trim();
      if (id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

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

  static Future<TradingPurchase?> lotFor(String farmId, String id) =>
      _cache.putIfAbsent(
        '$farmId/$id',
            () => TradingService.instance
            .getPurchase(farmId, id)
            .catchError((_) => null),
      );

  Future<TradingPurchase?> _lot(String id) => lotFor(farmId, id);

  /// "LOT-0001" from a lot doc ID, used until the lot itself is loaded.
  static String displayId(String docId) {
    final dash = docId.indexOf('-');
    return dash < 0 ? docId : 'LOT-${docId.substring(dash + 1)}';
  }

  static String _display(String docId) => displayId(docId);

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
                  showBookingHeader
                      ? 'Booking $bookingId'
                      : lotDocIds.length == 1
                      ? 'Lot'
                      : 'Lots (${lotDocIds.length})',
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
                  final count = goatsByLot?[id];
                  final parts = <String>[
                    lot?.lotId ?? _display(id),
                    if (lot != null && lot.sellerName.trim().isNotEmpty)
                      'Supplier: ${lot.sellerName.trim()}',
                    if (lot != null)
                      'Bought ${DateFormat('d MMM yyyy').format(lot.purchaseDate)}',
                    if (count != null)
                      count == 1 ? '1 goat' : '$count goats',
                  ];
                  return Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      showBookingHeader
                          ? 'From ${parts.join(' · ')}'
                          : '• ${parts.join(' · ')}',
                      style:
                      AppTheme.body(size: 11, color: AppColors.textDark),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

/// A goat's lot number ("LOT-0001"), read from the lot itself (cached).
class LotIdText extends StatelessWidget {
  final String farmId;

  /// The lot doc ID (`Goat.purchaseId`, or the sale's lot for a lot
  /// booking). Empty shows "No lot".
  final String lotDocId;
  final TextStyle? style;

  const LotIdText({
    super.key,
    required this.farmId,
    required this.lotDocId,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final id = lotDocId.trim();
    final textStyle = style ?? AppTheme.body(size: 10.5);
    if (id.isEmpty) return Text('No lot', style: textStyle);

    return FutureBuilder<TradingPurchase?>(
      future: LotOriginCard.lotFor(farmId, id),
      builder: (context, snap) => Text(
        snap.data?.lotId ?? LotOriginCard.displayId(id),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      ),
    );
  }
}