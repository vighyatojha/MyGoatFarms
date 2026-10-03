import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_categories.dart';
import '../models/sale_model.dart';
import '../models/sale_settlement.dart';
import '../models/wait_delivery_group.dart';
import 'firestore_service.dart';
import 'sales_service.dart';

/// What is being paid for one booking in a batch delivery.
class WaitDeliveryPayment {
  /// Total pickup weight of this booking (sum of its goats), in kg.
  final double pickupWeight;

  /// Optional transportation charge collected at pickup (0 when none).
  /// Included in [expectedRemaining]; never farm revenue.
  final double transportCharges;

  /// What the customer still owes at this weight, after the bookings were
  /// netted against each other — shown to the person before saving and
  /// used only as a fallback for the result message; the service
  /// re-derives and re-checks the real figure itself.
  final double expectedRemaining;

  /// How much of [expectedRemaining] is being received right now.
  final double amountReceivedNow;

  /// Whatever is left after [amountReceivedNow] goes onto the customer's
  /// outstanding balance instead of blocking the delivery.
  final bool onCredit;

  /// Discount on the goat value at pickup. Null keeps the discount given
  /// at booking time.
  final double? discount;

  /// What to do with money the advance covered beyond the final bill.
  final ExcessAction excessAction;

  const WaitDeliveryPayment({
    required this.pickupWeight,
    this.transportCharges = 0,
    required this.expectedRemaining,
    required this.amountReceivedNow,
    required this.onCredit,
    this.discount,
    this.excessAction = ExcessAction.carryToAdvance,
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
/// SalesService.completeWaitForDeliveryGroup, which the single-goat path
/// (completeWaitForDeliveryPickup) also goes through, so the two can never
/// drift apart — every rule enforced there (full payment required unless
/// Sell on Credit, amount can't exceed what's due, ...) applies here too.
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
  /// that booking). [payments] must be in the order the bookings are shown
  /// on screen: that is the order dues are covered in.
  ///
  /// The ticked bookings are one customer settlement: a booking whose
  /// advance is more than its bill pays part of another booking's due
  /// (see [WaitDeliveryAllocator]). Bookings that exchange money are saved
  /// TOGETHER, in one Firestore transaction
  /// (SalesService.completeWaitForDeliveryGroup), so a failure can never
  /// leave the extra recorded as used but not applied. Bookings with no
  /// transfer between them stay independent, one transaction each, as
  /// before.
  ///
  /// A failure is reported back in the result instead of being thrown:
  /// every booking of a failed group is listed as failed with the same
  /// message, and the other groups are still delivered.
  Future<WaitDeliveryBatchResult> deliverSales({
    required String farmId,
    required Map<String, WaitDeliveryPayment> payments,
    required String paymentMethod,
  }) async {
    final ids = payments.keys.toList();

    // Read each booking once, outside a transaction, only to find which
    // bookings exchange money. The transaction re-reads and re-checks
    // everything it saves.
    final bills = <WaitDeliveryBill>[];
    final unreadable = <String>{};

    for (final saleId in ids) {
      final payment = payments[saleId]!;

      try {
        final snap = await FirebaseFirestore.instance
            .collection('farms')
            .doc(farmId)
            .collection('sales')
            .doc(saleId)
            .get();

        if (!snap.exists) {
          unreadable.add(saleId);
          continue;
        }

        final sale = Sale.fromDoc(snap);
        final advance = sale.bookingAdvanceAmount ?? 0;

        final settlement = SaleSettlement.fromAmount(
          goatAmount: sale.goatValueAtWeight(payment.pickupWeight),
          discount: payment.discount ?? sale.appliedDiscount,
          transportCharge:
          payment.transportCharges < 0 ? 0 : payment.transportCharges,
          advancePaid: advance,
        );

        bills.add(
          WaitDeliveryBill(
            saleId: saleId,
            payable: settlement.payable,
            advancePaid: advance,
          ),
        );
      } catch (_) {
        // Let the delivery itself report the real problem.
        unreadable.add(saleId);
      }
    }

    final allocation = WaitDeliveryAllocator.allocate(bills);

    // Group bookings that are linked by a transfer.
    final parent = <String, String>{for (final id in ids) id: id};

    String find(String id) {
      var root = id;

      while (parent[root] != root) {
        root = parent[root]!;
      }

      return root;
    }

    for (final transfer in allocation.transfers) {
      final a = find(transfer.fromSaleId);
      final b = find(transfer.toSaleId);

      if (a != b) parent[b] = a;
    }

    final groups = <String, List<String>>{};

    for (final id in ids) {
      groups.putIfAbsent(find(id), () => <String>[]).add(id);
    }

    final outcomeById = <String, WaitDeliveryOutcome>{};

    for (final group in groups.values) {
      // What is still to collect per booking, after the transfers. A
      // booking that could not be read is shown as it was on screen.
      double remainingOf(String saleId) {
        final alloc = allocation.bySale[saleId];
        final payment = payments[saleId]!;
        final due = alloc?.toCollect ?? payment.expectedRemaining;
        final left = Sale.roundMoney(due - payment.amountReceivedNow);

        return left < 0 ? 0 : left;
      }

      try {
        await SalesService.instance.completeWaitForDeliveryGroup(
          farmId: farmId,
          paymentMethod: paymentMethod,
          items: [
            for (final saleId in group)
              WaitPickupInput(
                saleId: saleId,
                pickupWeight: payments[saleId]!.pickupWeight,
                transportCharges: payments[saleId]!.transportCharges,
                amountReceivedNow: payments[saleId]!.amountReceivedNow,
                onCredit: payments[saleId]!.onCredit,
                discount: payments[saleId]!.discount,
                excessAction: payments[saleId]!.excessAction,
              ),
          ],
        );

        for (final saleId in group) {
          outcomeById[saleId] = WaitDeliveryOutcome(
            saleId: saleId,
            remaining: remainingOf(saleId),
          );
        }
      } catch (e) {
        final message = e is StateError
            ? e.message
            : FirestoreService.instance.describeError(e);

        for (final saleId in group) {
          outcomeById[saleId] = WaitDeliveryOutcome(
            saleId: saleId,
            remaining: remainingOf(saleId),
            error: message,
          );
        }
      }
    }

    return WaitDeliveryBatchResult([
      for (final saleId in ids) outcomeById[saleId]!,
    ]);
  }

  /// Payment methods to offer for the money received at delivery — same
  /// list the single-goat Complete Delivery screen uses.
  List<String> get paymentMethods => FinancePaymentMethods.all;
}