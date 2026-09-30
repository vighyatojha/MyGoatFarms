import 'dart:math' as math;

import 'trading_purchase_model.dart';

/// What converting ONE older (goat-first, `lotSchema == 0`) purchase into a
/// Purchase Lot will write. Pure data — no Firestore.
///
/// Built by [LegacyConversionPlanner.plan] from the purchase as it is now
/// plus the number of `tradingGoats` documents that really exist for it.
/// The service shows these plans as a dry run, then writes exactly the same
/// numbers, so the owner sees before confirming what will happen.
class LegacyConversionPlan {
  final String purchaseId;

  final int totalGoats;

  /// Goats that arrived alive. 0 while receiving is still pending.
  final int receivedAliveQty;

  /// Mortality to store on the lot (reset to 0 while receiving is pending).
  final int mortality;

  /// Goats already moved out of the lot into individual goat records.
  final int registeredCount;

  /// Legacy mirror of `farmQty` — must equal [farmQty].
  final int pendingCount;

  // What the purchase says today (used to detect a change mid-run and to
  // describe what was corrected).
  final String storedReceivingStatus;
  final int storedRegisteredCount;
  final int storedPendingCount;
  final int storedMortality;

  /// `tradingGoats` documents whose `purchaseId` is this purchase.
  final int goatDocCount;

  const LegacyConversionPlan({
    required this.purchaseId,
    required this.totalGoats,
    required this.receivedAliveQty,
    required this.mortality,
    required this.registeredCount,
    required this.pendingCount,
    required this.storedReceivingStatus,
    required this.storedRegisteredCount,
    required this.storedPendingCount,
    required this.storedMortality,
    required this.goatDocCount,
  });

  /// Same formula the lot uses: `receivedAlive - soldFromFarm(0) - registered`.
  int get farmQty => math.max(0, receivedAliveQty - registeredCount);

  /// Goats still at the supplier after conversion (pending receiving).
  int get supplierQty =>
      math.max(0, totalGoats - receivedAliveQty - mortality);

  /// True when conversion changes `registeredCount` or `pendingCount`
  /// (i.e. the old counters disagreed with the goats that really exist).
  bool get countersAdjusted =>
      registeredCount != storedRegisteredCount ||
          pendingCount != storedPendingCount;

  /// True when a stray non-zero mortality on a still-pending purchase is
  /// reset to 0 (costing ignored it while pending).
  bool get mortalityReset => mortality != storedMortality;

  /// Something worth a human look. Conversion still goes ahead — these are
  /// reported, never silently hidden.
  List<String> get warnings {
    final out = <String>[];

    if (goatDocCount < storedRegisteredCount) {
      out.add(
        '$purchaseId: purchase says $storedRegisteredCount goats were '
            'registered but only $goatDocCount goat records exist. The '
            'purchase figure was kept, so no extra stock appears.',
      );
    }

    if (goatDocCount > receivedAliveQty) {
      out.add(
        '$purchaseId: $goatDocCount goat records exist but only '
            '$receivedAliveQty goats are recorded as received. Farm stock '
            'for this lot is 0.',
      );
    }

    if (pendingCount < storedPendingCount) {
      out.add(
        '$purchaseId: waiting-to-register count lowered from '
            '$storedPendingCount to $pendingCount to match the goats that '
            'really exist.',
      );
    }

    return out;
  }
}

/// Everything a dry run reports before the owner confirms.
class LegacyConversionPreview {
  final List<LegacyConversionPlan> plans;

  const LegacyConversionPreview(this.plans);

  int get purchaseCount => plans.length;

  bool get isEmpty => plans.isEmpty;

  /// Goats that will sit in lots at the farm afterwards.
  int get farmGoats => plans.fold(0, (s, p) => s + p.farmQty);

  /// Goats that will sit in lots still at the supplier (receiving pending).
  int get supplierGoats => plans.fold(0, (s, p) => s + p.supplierQty);

  int get adjustedCount => plans.where((p) => p.countersAdjusted).length;

  List<String> get warnings => [for (final p in plans) ...p.warnings];
}

/// Decides the lot figures for an older purchase.
///
/// Rules (handover §7.3):
/// * Receiving completed -> `receivedAliveQty = survivingGoats`.
///   Receiving pending   -> `receivedAliveQty = 0`, `mortality = 0`.
/// * `registeredCount` follows the goat records that really exist, but is
///   never lowered below what the purchase already said, and farm stock is
///   never raised above the purchase's own `pendingCount`. Converting must
///   not invent goats that the old screens did not think were waiting.
/// * `pendingCount` is set to the resulting `farmQty`, as every lot writer
///   does.
class LegacyConversionPlanner {
  LegacyConversionPlanner._();

  static LegacyConversionPlan plan(
      TradingPurchase purchase,
      int goatDocCount,
      ) {
    final completed = purchase.isReceivingCompleted;

    final received = completed ? purchase.survivingGoats : 0;
    final mortality = completed ? purchase.mortality : 0;

    var registered = math.max(purchase.registeredCount, goatDocCount);

    var farm = math.max(0, received - registered);

    // Never more farm stock than the old counter said was waiting.
    final storedPending = math.max(0, purchase.pendingCount);
    if (farm > storedPending) farm = storedPending;

    // Keep farmQty = received - registered true after the clamp above,
    // without ever lowering registered below the goats that exist.
    registered = math.max(registered, received - farm);

    return LegacyConversionPlan(
      purchaseId: purchase.id,
      totalGoats: purchase.totalGoats,
      receivedAliveQty: received,
      mortality: mortality,
      registeredCount: registered,
      pendingCount: farm,
      storedReceivingStatus: purchase.receivingStatus,
      storedRegisteredCount: purchase.registeredCount,
      storedPendingCount: purchase.pendingCount,
      storedMortality: purchase.mortality,
      goatDocCount: goatDocCount,
    );
  }
}