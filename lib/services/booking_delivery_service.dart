import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_categories.dart';
import '../models/sale_model.dart';
import '../models/sale_settlement.dart';
import '../models/wait_delivery_group.dart';
import 'firestore_service.dart';
import 'sales_service.dart';

/// What is being paid for one booking in a batch delivery.
class BookingDeliveryPayment {
  /// What the customer owes for this booking at the batch's chosen
  /// delivery date — shown to the person before saving and carried
  /// through only for the result message; the service re-derives and
  /// re-checks the real figure itself.
  final double expectedRemaining;

  /// How much of [expectedRemaining] is being received right now.
  final double amountReceivedNow;

  /// Whatever is left after [amountReceivedNow] goes onto the customer's
  /// outstanding balance instead of blocking the delivery.
  final bool onCredit;

  /// Optional transportation charge collected at delivery (0 when none).
  /// It is added to what the customer owes but is never farm revenue.
  final double transportCharges;

  /// Extra discount given at delivery, on top of the booking discount.
  /// Comes off the goat value only. 0 when none.
  final double discount;

  /// Holding charge per day edited at delivery. Null keeps the rate agreed
  /// at booking.
  final double? holdingChargePerDay;

  /// What to do with money the booking amount covered beyond the final
  /// bill.
  final ExcessAction excessAction;

  /// Total weight of the booking's goats at delivery. The goat value is
  /// the agreed amount x this / the booked weight. Null keeps the amount
  /// agreed at booking.
  final double? pickupWeight;

  const BookingDeliveryPayment({
    required this.expectedRemaining,
    required this.amountReceivedNow,
    required this.onCredit,
    this.transportCharges = 0,
    this.discount = 0,
    this.holdingChargePerDay,
    this.excessAction = ExcessAction.carryToAdvance,
    this.pickupWeight,
  });
}

/// What happened to one booking during a batch delivery.
class BookingDeliveryOutcome {
  final String saleId;

  /// The amount that ended up on the customer's outstanding balance for
  /// this booking (0 when it was paid in full).
  final double remaining;

  /// Null when the delivery went through, otherwise a message that is fit
  /// to show to the person.
  final String? error;

  const BookingDeliveryOutcome({
    required this.saleId,
    required this.remaining,
    this.error,
  });

  bool get ok => error == null;
}

/// Result of delivering several bookings in one go.
class BookingDeliveryBatchResult {
  final List<BookingDeliveryOutcome> outcomes;

  const BookingDeliveryBatchResult(this.outcomes);

  List<BookingDeliveryOutcome> get delivered =>
      outcomes.where((o) => o.ok).toList();

  List<BookingDeliveryOutcome> get failed =>
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

/// Reads and completes open Booking / Holding sales for the
/// customer-grouped Booking / Holding screens.
///
/// Deliberately thin, exactly like [WaitDeliveryService]: the actual
/// delivery accounting (holding-charge settlement, payment received,
/// credit handling, goats -> Sold, dashboard counters, Finance revenue)
/// stays in SalesService.completeBookingDeliveryGroup, which the single-goat
/// path (completeBookingDelivery, used by CompleteBookingDeliveryScreen)
/// also goes through, so the two can never drift apart — every rule
/// enforced there (full payment required unless Sell on Credit, amount
/// can't exceed what's due, delivery date can't be before holding
/// started, ...) applies here too.
class BookingDeliveryService {
  BookingDeliveryService._();

  static final BookingDeliveryService instance = BookingDeliveryService._();

  /// Live list of every sale that is still Booked / on hold.
  ///
  /// A single equality filter, so it needs no composite index — same
  /// pattern as [WaitDeliveryService.openSalesStream].
  Stream<List<Sale>> openSalesStream(String farmId) {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('sales')
        .where('status', isEqualTo: Sale.statusBooked)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(Sale.fromDoc)
          .where((sale) => sale.isBooking)
          .toList(),
    );
  }

  /// Delivers every booking in [payments] (saleId -> what to record for
  /// that booking) against the one shared [deliveryDate]. [payments] must
  /// be in the order the bookings are shown on screen: that is the order
  /// dues are covered in.
  ///
  /// The ticked bookings are one customer settlement: a booking whose
  /// booking amount is more than its bill pays part of another booking's
  /// due (see [WaitDeliveryAllocator]). Bookings that exchange money are
  /// saved TOGETHER, in one Firestore transaction
  /// (SalesService.completeBookingDeliveryGroup), so a failure can never
  /// leave the extra recorded as used but not applied. Bookings with no
  /// transfer between them stay independent, one transaction each.
  ///
  /// A failure is reported back in the result instead of being thrown:
  /// every booking of a failed group is listed as failed with the same
  /// message, and the other groups are still delivered.
  Future<BookingDeliveryBatchResult> deliverSales({
    required String farmId,
    required DateTime deliveryDate,
    required Map<String, BookingDeliveryPayment> payments,
    required String paymentMethod,
  }) async {
    final ids = payments.keys.toList();

    final deliveryDay = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
    );

    // Read each booking once, outside a transaction, only to find which
    // bookings exchange money. The transaction re-reads and re-checks
    // everything it saves.
    final bills = <WaitDeliveryBill>[];

    for (final saleId in ids) {
      final payment = payments[saleId]!;

      try {
        final snap = await FirebaseFirestore.instance
            .collection('farms')
            .doc(farmId)
            .collection('sales')
            .doc(saleId)
            .get();

        if (!snap.exists) continue;

        final sale = Sale.fromDoc(snap);
        final start = sale.holdingStart;
        final startDay = DateTime(start.year, start.month, start.day);

        if (deliveryDay.isBefore(startDay)) continue;

        final rate = payment.holdingChargePerDay ??
            sale.holdingChargePerDay ??
            0;
        final days = Sale.holdingDaysBetween(startDay, deliveryDay);
        final advance = sale.bookingAmount ?? 0;

        final settlement = SaleSettlement.fromAmount(
          goatAmount: sale.bookingGoatAmountAt(payment.pickupWeight),
          discount: payment.discount < 0 ? 0 : payment.discount,
          holdingCharges: Sale.roundMoney(days * (rate < 0 ? 0 : rate)),
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

    final outcomeById = <String, BookingDeliveryOutcome>{};

    for (final group in groups.values) {
      double remainingOf(String saleId) {
        final alloc = allocation.bySale[saleId];
        final payment = payments[saleId]!;
        final due = alloc?.toCollect ?? payment.expectedRemaining;
        final left = Sale.roundMoney(due - payment.amountReceivedNow);

        return left < 0 ? 0 : left;
      }

      try {
        await SalesService.instance.completeBookingDeliveryGroup(
          farmId: farmId,
          deliveryDate: deliveryDate,
          paymentMethod: paymentMethod,
          items: [
            for (final saleId in group)
              BookingPickupInput(
                saleId: saleId,
                transportCharges: payments[saleId]!.transportCharges,
                amountReceivedNow: payments[saleId]!.amountReceivedNow,
                onCredit: payments[saleId]!.onCredit,
                excessAction: payments[saleId]!.excessAction,
                discount: payments[saleId]!.discount,
                holdingChargePerDay: payments[saleId]!.holdingChargePerDay,
                pickupWeight: payments[saleId]!.pickupWeight,
              ),
          ],
        );

        for (final saleId in group) {
          outcomeById[saleId] = BookingDeliveryOutcome(
            saleId: saleId,
            remaining: remainingOf(saleId),
          );
        }
      } catch (e) {
        final message = e is StateError
            ? e.message
            : FirestoreService.instance.describeError(e);

        for (final saleId in group) {
          outcomeById[saleId] = BookingDeliveryOutcome(
            saleId: saleId,
            remaining: remainingOf(saleId),
            error: message,
          );
        }
      }
    }

    return BookingDeliveryBatchResult([
      for (final saleId in ids) outcomeById[saleId]!,
    ]);
  }

  /// Payment methods to offer for the money received at delivery — same
  /// list the single-goat Complete Delivery screen uses.
  List<String> get paymentMethods => FinancePaymentMethods.all;
}