import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_categories.dart';
import '../models/sale_model.dart';
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

  const BookingDeliveryPayment({
    required this.expectedRemaining,
    required this.amountReceivedNow,
    required this.onCredit,
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
/// stays in SalesService.completeBookingDelivery, so the single-goat path
/// (CompleteBookingDeliveryScreen) and this batch path can never drift
/// apart — every rule enforced there (full payment required unless Sell
/// on Credit, amount can't exceed what's due, delivery date can't be
/// before holding started, ...) applies here too, one booking at a time.
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
  /// that booking) against the one shared [deliveryDate], one after the
  /// other.
  ///
  /// Each booking is its own Firestore transaction — exactly as when it
  /// is delivered from the single-goat screen — so this is NOT one
  /// atomic write across bookings. If one booking fails (for example it
  /// was already delivered from another device, or the amount no longer
  /// matches what is due) the others are still delivered, and the
  /// failure is reported back in the result instead of being thrown.
  Future<BookingDeliveryBatchResult> deliverSales({
    required String farmId,
    required DateTime deliveryDate,
    required Map<String, BookingDeliveryPayment> payments,
    required String paymentMethod,
  }) async {
    final outcomes = <BookingDeliveryOutcome>[];

    for (final entry in payments.entries) {
      final saleId = entry.key;
      final payment = entry.value;

      final remaining = Sale.roundMoney(
        payment.expectedRemaining - payment.amountReceivedNow,
      );

      try {
        await SalesService.instance.completeBookingDelivery(
          farmId: farmId,
          saleId: saleId,
          deliveryDate: deliveryDate,
          amountReceivedNow: payment.amountReceivedNow,
          paymentMethod: paymentMethod,
          onCredit: payment.onCredit,
        );

        outcomes.add(
          BookingDeliveryOutcome(
            saleId: saleId,
            remaining: remaining < 0 ? 0 : remaining,
          ),
        );
      } catch (e) {
        outcomes.add(
          BookingDeliveryOutcome(
            saleId: saleId,
            remaining: remaining < 0 ? 0 : remaining,
            error: e is StateError
                ? e.message
                : FirestoreService.instance.describeError(e),
          ),
        );
      }
    }

    return BookingDeliveryBatchResult(outcomes);
  }

  /// Payment methods to offer for the money received at delivery — same
  /// list the single-goat Complete Delivery screen uses.
  List<String> get paymentMethods => FinancePaymentMethods.all;
}