import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/death_record.dart';
import '../models/sale_model.dart';
import '../models/trading_lot_death_model.dart';
import '../models/trading_purchase_model.dart';
import 'death_settlement_service.dart';
import 'trading_service.dart';

enum TradingLossType {
  all,
  goatDeath,
  lotDeath,
  cancellation,
  saleDiscount,
  belowCost,
  other,
}

/// One Trading loss, whatever it came from.
class TradingLossItem {
  final String id;
  final String title;
  final String subtitle;
  final String typeLabel;
  final double amount;
  final DateTime date;
  final String? actorName;
  final TradingLossType type;
  final IconData icon;

  const TradingLossItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.typeLabel,
    required this.amount,
    required this.date,
    required this.actorName,
    required this.type,
    required this.icon,
  });
}

/// The ONE place that collects Trading losses.
///
/// Both the Trading Losses screen and the Recent Trading Activity feed
/// read from here, so a loss can never show on one and be missing from
/// the other. To add a new kind of loss, add it in [load] and both
/// places pick it up.
///
/// Sources:
///   * `deathRecords`                         goat deaths + manual losses
///   * `tradingPurchases/{lot}/deaths`        purchase-lot deaths
///   * `tradingPurchases` (dealCancelled)     paid minus refunded
///   * `sales` (delivered, discount > 0)      discount given to a customer
///   * `sales` (lot sale, below cost)         sold for less than the lot cost
class TradingLossService {
  TradingLossService._();
  static final TradingLossService instance = TradingLossService._();

  Future<List<TradingLossItem>> load(
      String farmId, {
        required DateTime start,
        required DateTime end,
      }) async {
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);

    final results = await Future.wait([
      DeathSettlementService.instance.deathHistoryStream(farmId).first,
      TradingService.instance.purchasesStream(farmId).first,
    ]);

    final deathRecords = results[0] as List<DeathRecord>;
    final lots = results[1] as List<TradingPurchase>;
    final items = <TradingLossItem>[];

    // ---- Farm / goat / manual losses -----------------------------------
    // A Customer Palai death with farmLossAmount == 0 is intentionally
    // excluded: no money was lost by the farm.
    for (final record in deathRecords) {
      if (record.farmLossAmount <= 0) continue;
      if (!inRange(record.deathDate)) continue;

      if (record.isManualLoss) {
        items.add(
          TradingLossItem(
            id: 'death_${record.id}',
            title: record.displayTitle,
            subtitle: record.description.trim().isNotEmpty
                ? record.description.trim()
                : record.reason.trim().isNotEmpty
                ? record.reason.trim()
                : record.goatTypeLabel,
            typeLabel: record.goatTypeLabel,
            amount: record.farmLossAmount,
            date: record.deathDate,
            actorName: record.actorName,
            type: TradingLossType.other,
            icon: Icons.report_gmailerrorred_outlined,
          ),
        );
        continue;
      }

      final goatLabel =
      record.goatLabel.trim().isNotEmpty ? record.goatLabel.trim() : 'Goat';
      final customerSuffix = record.customerName?.trim().isNotEmpty == true
          ? ' • ${record.customerName!.trim()}'
          : '';

      items.add(
        TradingLossItem(
          id: 'death_${record.id}',
          title: '$goatLabel$customerSuffix',
          subtitle: record.reason.trim().isNotEmpty
              ? record.reason.trim()
              : 'Goat death loss',
          typeLabel: record.goatTypeLabel,
          amount: record.farmLossAmount,
          date: record.deathDate,
          actorName: record.actorName,
          type: TradingLossType.goatDeath,
          icon: Icons.pets_outlined,
        ),
      );
    }

    // ---- Purchase-lot deaths + cancelled deals -------------------------
    final lotResults = await Future.wait(
      lots.where((lot) => lot.isLot).map(
            (lot) => TradingService.instance
            .lotDeathsStream(farmId, lot.id)
            .first
            .then((deaths) => (lot: lot, deaths: deaths)),
      ),
    );

    for (final result in lotResults) {
      final lot = result.lot;

      for (final death in result.deaths) {
        if (death.reversed) continue;
        if (death.lossAmount <= 0) continue;
        if (!inRange(death.date)) continue;

        final lotName = lot.lotId.trim().isNotEmpty ? lot.lotId : 'Purchase Lot';
        final reason =
        death.reason.trim().isNotEmpty ? death.reason.trim() : 'Goat death';

        items.add(
          TradingLossItem(
            id: 'lotdeath_${lot.id}_${death.id}',
            title: '$lotName • Goat death',
            subtitle:
            '${death.qty} goat${death.qty == 1 ? '' : 's'} • $reason',
            typeLabel: 'Lot Death',
            amount: death.lossAmount,
            date: death.date,
            actorName: death.actorName,
            type: TradingLossType.lotDeath,
            icon: Icons.pets_outlined,
          ),
        );
      }

      if (lot.dealCancelled &&
          lot.cancelLossAmount > 0 &&
          lot.cancelledAt != null &&
          inRange(lot.cancelledAt!)) {
        final note = lot.cancelNote.trim();
        items.add(
          TradingLossItem(
            id: 'cancel_${lot.id}',
            title: '${lot.lotId} • Deal cancellation',
            subtitle: note.isNotEmpty ? note : 'Supplier cancellation loss',
            typeLabel: 'Cancellation',
            amount: lot.cancelLossAmount,
            date: lot.cancelledAt!,
            actorName: null,
            type: TradingLossType.cancellation,
            icon: Icons.cancel_outlined,
          ),
        );
      }
    }

    // ---- Sales: discounts + lot goats sold below cost -------------------
    //
    // Discounts are money the farm chose not to collect. A lot sale whose
    // goat value is under the cost snapshot is a real loss on that sale.
    // Filtered by date here (not in the query) so no index is needed.
    try {
      final salesSnap = await FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId)
          .collection('sales')
          .get()
          .timeout(const Duration(seconds: 15));

      for (final doc in salesSnap.docs) {
        final sale = Sale.fromDoc(doc);
        final when = sale.saleDate;

        if (!sale.isDelivered || when == null || !inRange(when)) continue;

        final who = sale.customerName.trim().isNotEmpty
            ? sale.customerName.trim()
            : 'Customer';

        if (sale.appliedDiscount > 0) {
          items.add(
            TradingLossItem(
              id: 'discount_${sale.id}',
              title: '$who • Sale discount',
              subtitle: sale.isLotSale
                  ? '${sale.lotDisplayId} • ${sale.goatCount} goat'
                  '${sale.goatCount == 1 ? '' : 's'}'
                  : '${sale.goatCount} goat'
                  '${sale.goatCount == 1 ? '' : 's'}',
              typeLabel: 'Discount',
              amount: sale.appliedDiscount,
              date: when,
              actorName: null,
              type: TradingLossType.saleDiscount,
              icon: Icons.local_offer_outlined,
            ),
          );
        }

        if (sale.isLotSale && sale.costPerGoatSnapshot != null) {
          final cost = sale.costPerGoatSnapshot! * sale.lotQuantity;
          final shortfall = cost - sale.billGoatSale;
          if (shortfall > 0.5) {
            items.add(
              TradingLossItem(
                id: 'belowcost_${sale.id}',
                title: '$who • Sold below cost',
                subtitle: '${sale.lotDisplayId} • cost '
                    '₹${cost.toStringAsFixed(0)}, sold '
                    '₹${sale.billGoatSale.toStringAsFixed(0)}',
                typeLabel: 'Below Cost',
                amount: double.parse(shortfall.toStringAsFixed(2)),
                date: when,
                actorName: null,
                type: TradingLossType.belowCost,
                icon: Icons.trending_down_rounded,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Additive source: a failure here must not hide the other losses.
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }
}