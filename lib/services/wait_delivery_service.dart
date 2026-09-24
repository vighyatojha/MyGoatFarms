import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_categories.dart';
import '../models/sale_model.dart';
import 'firestore_service.dart';
import 'sales_service.dart';

/// What is being paid for one booking in a batch delivery.
class WaitDeliveryPayment {
  /// Total pickup weight of this booking (sum of its goats), in kg.
  final double pickupWeight;

  /// Optional transportation charge collected at pickup (0 when none).
  /// Included in [expectedRemaining]; never farm revenue.
  final double transportCharges;

  /// What the customer still owes at this weight — shown to the person
  /// before saving and carried through only for the result message; the
  /// service re-derives and re-checks the real figure itself.
  final double expectedRemaining;

  /// How much of [expectedRemaining] is being received right now.
  final double amountReceivedNow;

  /// Whatever is left after [amountReceivedNow] goes onto the customer's
  /// outstanding balance instead of blocking the delivery.
  final bool onCredit;

  const WaitDeliveryPayment({
    required this.pickupWeight,
    this.transportCharges = 0,
    required this.expectedRemaining,
    required this.amountReceivedNow,
    required this.onCredit,
  });
}

/// What happened to one booking during a batch delivery.
class WaitDeliveryOutcome {
  final String saleId;

  /// The amount that ended up on the customer's outstanding balance for
  /// this booking (0 when it was paid in full).
  final double remaining;

  /// Null when the delivery went through, otherwise a message that is fit
  /// to show to the person.
  final String? error;

  const WaitDeliveryOutcome({
    required this.saleId,
    required this.remaining,
    this.error,
  });

  bool get ok => error == null;
}

/// Result of delivering several bookings in one go.
class WaitDeliveryBatchResult {
  final List<WaitDeliveryOutcome> outcomes;

  const WaitDeliveryBatchResult(this.outcomes);

  List<WaitDeliveryOutcome> get delivered =>
      outcomes.where((o) => o.ok).toList();

  List<WaitDeliveryOutcome> get failed =>
      outcomes.where((o) => !o.ok).toList();

  bool get allDelivered => outcomes.isNotEmpty && failed.isEmpty;

  /// Balance left outstanding across the bookings that WERE delivered
  /// (0 when everything selected was paid in full).
  double get totalRemainingDelivered {
    return Sale.roundMoney(
      delivered.fold<double>(0, (sum, o) => sum + o.remaining),
    );
  }
}

/// Reads and completes open Wait for Delivery bookings for the
/// customer-grouped Wait on Delivery screens.
///
/// Deliberately thin: the actual delivery accounting (booking-rate /
/// fixed-price settlement, payment received, credit handling, goats ->
/// Sold, dashboard counters, Finance revenue) stays in
/// SalesService.completeWaitForDeliveryPickup, so the single-goat path
/// and this batch path can never drift apart — every rule enforced there
/// (full payment required unless Sell on Credit, amount can't exceed
/// what's due, ...) applies here too, one booking at a time.
class WaitDeliveryService {
  WaitDeliveryService._();

  static final WaitDeliveryService instance = WaitDeliveryService._();

  /// Live list of every sale that is still waiting for pickup.
  ///
  /// A single equality filter, so it needs no composite index.
  Stream<List<Sale>> openSalesStream(String farmId) {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('sales')
        .where('status', isEqualTo: Sale.statusWaitForDelivery)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(Sale.fromDoc)
          .where((sale) => sale.isWaitForDelivery)
          .toList(),
    );
  }

  /// Delivers every booking in [payments] (saleId -> what to record for
  /// that booking), one after the other.
  ///
  /// Each booking is its own Firestore transaction — exactly as when it
  /// is delivered from the single-goat screen — so this is NOT one
  /// atomic write across bookings. If one booking fails (for example it
  /// was already delivered from another device, or the amount no longer
  /// matches what is due) the others are still delivered, and the
  /// failure is reported back in the result instead of being thrown, so
  /// the person can see exactly what did and did not go through.
  Future<WaitDeliveryBatchResult> deliverSales({
    required String farmId,
    required Map<String, WaitDeliveryPayment> payments,
    required String paymentMethod,
  }) async {
    final outcomes = <WaitDeliveryOutcome>[];

    for (final entry in payments.entries) {
      final saleId = entry.key;
      final payment = entry.value;

      final remaining = Sale.roundMoney(
        payment.expectedRemaining - payment.amountReceivedNow,
      );

      try {
        await SalesService.instance.completeWaitForDeliveryPickup(
          farmId: farmId,
          saleId: saleId,
          pickupWeight: payment.pickupWeight,
          transportCharges: payment.transportCharges,
          amountReceivedNow: payment.amountReceivedNow,
          paymentMethod: paymentMethod,
          onCredit: payment.onCredit,
        );

        outcomes.add(
          WaitDeliveryOutcome(
            saleId: saleId,
            remaining: remaining < 0 ? 0 : remaining,
          ),
        );
      } catch (e) {
        outcomes.add(
          WaitDeliveryOutcome(
            saleId: saleId,
            remaining: remaining < 0 ? 0 : remaining,
            error: e is StateError
                ? e.message
                : FirestoreService.instance.describeError(e),
          ),
        );
      }
    }

    return WaitDeliveryBatchResult(outcomes);
  }

  /// Payment methods to offer for the money received at delivery — same
  /// list the single-goat Complete Delivery screen uses.
  List<String> get paymentMethods => FinancePaymentMethods.all;
}