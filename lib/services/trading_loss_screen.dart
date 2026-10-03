import 'package:flutter/material.dart';

import '../models/death_record.dart';
import '../models/trading_purchase_model.dart';
import 'death_settlement_service.dart';
import 'trading_service.dart';

enum TradingLossType {
  all,
  goatDeath,
  lotDeath,
  cancellation,
  other,
}

/// One Trading loss, whatever it came from.
///
/// IMPORTANT:
/// Sales are NOT losses in MyGoatFarms.
///
/// Sale discounts, sale price differences and "sold below cost"
/// are intentionally NOT represented by this model.
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

/// Central source for Trading Losses.
///
/// IMPORTANT ACCOUNTING RULE:
///
/// Sales are NEVER treated as losses here.
///
/// Therefore this service does NOT read the `sales` collection and
/// does NOT create loss rows for:
///
///   - Sale discounts
///   - Sold below cost
///   - Sale price differences
///
/// Actual Trading/Farm losses come only from:
///
///   1. Farm / goat / manual loss records
///   2. Purchase-lot goat deaths
///   3. Cancelled supplier deals
///
/// Both the Trading Losses screen and any Trading activity feed that
/// uses this service will therefore show the same loss categories.
class TradingLossService {
  TradingLossService._();

  static final TradingLossService instance =
  TradingLossService._();

  Future<List<TradingLossItem>> load(
      String farmId, {
        required DateTime start,
        required DateTime end,
      }) async {
    bool inRange(DateTime date) {
      return !date.isBefore(start) && date.isBefore(end);
    }

    final results = await Future.wait([
      DeathSettlementService.instance
          .deathHistoryStream(farmId)
          .first,
      TradingService.instance
          .purchasesStream(farmId)
          .first,
    ]);

    final deathRecords =
    results[0] as List<DeathRecord>;

    final lots =
    results[1] as List<TradingPurchase>;

    final items = <TradingLossItem>[];

    // ------------------------------------------------------------------
    // FARM / GOAT / MANUAL LOSSES
    // ------------------------------------------------------------------
    //
    // A Customer Palai death with farmLossAmount == 0 is intentionally
    // excluded because the farm did not suffer a financial loss.
    //
    for (final record in deathRecords) {
      if (record.farmLossAmount <= 0) {
        continue;
      }

      if (!inRange(record.deathDate)) {
        continue;
      }

      // Manual farm loss.
      if (record.isManualLoss) {
        final description =
        record.description.trim();

        final reason =
        record.reason.trim();

        items.add(
          TradingLossItem(
            id: 'death_${record.id}',
            title: record.displayTitle,
            subtitle: description.isNotEmpty
                ? description
                : reason.isNotEmpty
                ? reason
                : record.goatTypeLabel,
            typeLabel: record.goatTypeLabel,
            amount: record.farmLossAmount,
            date: record.deathDate,
            actorName: record.actorName,
            type: TradingLossType.other,
            icon:
            Icons.report_gmailerrorred_outlined,
          ),
        );

        continue;
      }

      // Normal goat death.
      final goatLabel =
      record.goatLabel.trim().isNotEmpty
          ? record.goatLabel.trim()
          : 'Goat';

      final customerName =
          record.customerName?.trim() ?? '';

      final customerSuffix =
      customerName.isNotEmpty
          ? ' • $customerName'
          : '';

      final reason =
      record.reason.trim();

      items.add(
        TradingLossItem(
          id: 'death_${record.id}',
          title:
          '$goatLabel$customerSuffix',
          subtitle: reason.isNotEmpty
              ? reason
              : 'Goat death loss',
          typeLabel:
          record.goatTypeLabel,
          amount:
          record.farmLossAmount,
          date:
          record.deathDate,
          actorName:
          record.actorName,
          type:
          TradingLossType.goatDeath,
          icon:
          Icons.pets_outlined,
        ),
      );
    }

    // ------------------------------------------------------------------
    // PURCHASE LOT LOSSES
    // ------------------------------------------------------------------
    //
    // These are losses related to goats purchased in a trading lot.
    //
    // Sales are NOT processed here.
    //
    final lotResults = await Future.wait(
      lots
          .where((lot) => lot.isLot)
          .map(
            (lot) =>
            TradingService.instance
                .lotDeathsStream(
              farmId,
              lot.id,
            )
                .first
                .then(
                  (deaths) => (
              lot: lot,
              deaths: deaths,
              ),
            ),
      ),
    );

    for (final result in lotResults) {
      final lot = result.lot;

      // --------------------------------------------------------------
      // Purchase-lot goat deaths
      // --------------------------------------------------------------
      for (final death in result.deaths) {
        if (death.reversed) {
          continue;
        }

        if (death.lossAmount <= 0) {
          continue;
        }

        if (!inRange(death.date)) {
          continue;
        }

        final lotName =
        lot.lotId.trim().isNotEmpty
            ? lot.lotId.trim()
            : 'Purchase Lot';

        final reason =
        death.reason.trim().isNotEmpty
            ? death.reason.trim()
            : 'Goat death';

        items.add(
          TradingLossItem(
            id:
            'lotdeath_${lot.id}_${death.id}',
            title:
            '$lotName • Goat death',
            subtitle:
            '${death.qty} goat'
                '${death.qty == 1 ? '' : 's'}'
                ' • $reason',
            typeLabel:
            'Lot Death',
            amount:
            death.lossAmount,
            date:
            death.date,
            actorName:
            death.actorName,
            type:
            TradingLossType.lotDeath,
            icon:
            Icons.pets_outlined,
          ),
        );
      }

      // --------------------------------------------------------------
      // Supplier deal cancellation
      // --------------------------------------------------------------
      //
      // This is a purchase-side loss, NOT a sale loss.
      //
      if (lot.dealCancelled &&
          lot.cancelLossAmount > 0 &&
          lot.cancelledAt != null &&
          inRange(lot.cancelledAt!)) {
        final note =
        lot.cancelNote.trim();

        items.add(
          TradingLossItem(
            id:
            'cancel_${lot.id}',
            title:
            '${lot.lotId} • Deal cancellation',
            subtitle: note.isNotEmpty
                ? note
                : 'Supplier cancellation loss',
            typeLabel:
            'Cancellation',
            amount:
            lot.cancelLossAmount,
            date:
            lot.cancelledAt!,
            actorName:
            null,
            type:
            TradingLossType.cancellation,
            icon:
            Icons.cancel_outlined,
          ),
        );
      }
    }

    // ------------------------------------------------------------------
    // IMPORTANT:
    //
    // There is intentionally NO sales collection query here.
    //
    // The following are NOT losses:
    //
    //   - Sale discount
    //   - Sold below purchase cost
    //   - Lower sale price
    //   - Customer negotiation
    //
    // Sales remain part of normal Trading Revenue / Sales accounting.
    // ------------------------------------------------------------------

    items.sort(
          (a, b) => b.date.compareTo(a.date),
    );

    return items;
  }
}