import 'goat_model.dart';
import 'sale_model.dart';

/// One booking (a Booking / Holding sale) still open, together with the
/// goats being held for it.
///
/// A Booking/Holding sale is never repriced by weight at delivery — its
/// final amount is [Sale.totalSaleAmount] plus holding charges (holding
/// days x [Sale.holdingChargePerDay]) minus the booking amount already
/// paid. This is exactly the formula CompleteBookingDeliveryScreen shows
/// and SalesService.completeBookingDelivery stores, so the figure shown
/// here is the figure that gets saved. Holding days are counted
/// inclusively from [Sale.holdingStart] to the delivery date, both days
/// counted — see [Sale.holdingDaysBetween].
///
/// Unlike Wait for Delivery, the delivery date (and therefore the final
/// amount) is not fixed per booking — it depends on the day the batch is
/// actually delivered, which is chosen once for the whole customer batch
/// in [BookingDeliveryCustomer]. That is why the amount here is a
/// function of a delivery date rather than a stored field.
class BookingDeliverySale {
  final Sale sale;

  /// The sale's goats that are still "Booked".
  final List<Goat> goats;

  const BookingDeliverySale({
    required this.sale,
    required this.goats,
  });

  String get id => sale.id;

  /// True when the goats were sold for one agreed price instead of a
  /// price per KG. Kept for parity with the Wait for Delivery batch
  /// screen's fixed-price tag — Booking's total is not repriced either
  /// way, so this only affects display.
  bool get isFixedPrice => sale.isFixedPrice;

  double get bookingAmount => sale.bookingAmount ?? 0;

  double get holdingChargePerDay => sale.holdingChargePerDay ?? 0;

  DateTime get holdingStart => sale.holdingStart;

  DateTime get bookedAt => sale.createdAt ?? sale.holdingStart;

  /// Holding days from [holdingStart] to [deliveryDate], both days
  /// counted — mirrors Sale.holdingDaysBetween/
  /// CompleteBookingDeliveryScreen exactly.
  int holdingDaysAt(DateTime deliveryDate) {
    final start = DateTime(
      holdingStart.year,
      holdingStart.month,
      holdingStart.day,
    );
    final end = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
    );

    return Sale.holdingDaysBetween(start, end);
  }

  double holdingChargesAt(DateTime deliveryDate) {
    return Sale.roundMoney(holdingDaysAt(deliveryDate) * holdingChargePerDay);
  }

  /// Goat Sale Amount + Holding Charges − Booking Amount, never below 0 —
  /// the same figure `completeBookingDelivery` saves as
  /// `finalAmountAfterHolding`.
  double finalAmountAt(DateTime deliveryDate) {
    final raw = Sale.roundMoney(
      sale.totalSaleAmount + holdingChargesAt(deliveryDate) - bookingAmount,
    );

    return raw < 0 ? 0 : raw;
  }
}

/// A customer who has one or more open Booking / Holding sales, with
/// every open booking they have. This is what the "Booking / Holding"
/// tab lists.
class BookingDeliveryCustomer {
  /// Stable grouping key (see [group]).
  final String key;

  final String name;
  final String mobile;
  final String address;

  /// Open bookings, newest first.
  final List<BookingDeliverySale> sales;

  const BookingDeliveryCustomer({
    required this.key,
    required this.name,
    required this.mobile,
    required this.address,
    required this.sales,
  });

  /// Every held goat of this customer, booking by booking.
  List<Goat> get goats {
    return [
      for (final entry in sales) ...entry.goats,
    ];
  }

  int get goatCount {
    return sales.fold<int>(0, (sum, entry) => sum + entry.goats.length);
  }

  double get bookingAmountTotal {
    return Sale.roundMoney(
      sales.fold<double>(0, (sum, entry) => sum + entry.bookingAmount),
    );
  }

  /// Newest booking date, used to order the customer list.
  DateTime get latestBookedAt {
    var latest = sales.first.bookedAt;

    for (final entry in sales) {
      if (entry.bookedAt.isAfter(latest)) {
        latest = entry.bookedAt;
      }
    }

    return latest;
  }

  /// Earliest holding-start date across this customer's bookings — a
  /// shared delivery date can never be before this, or it would predate
  /// holding for at least one booking.
  DateTime get earliestHoldingStart {
    var earliest = sales.first.holdingStart;

    for (final entry in sales) {
      if (entry.holdingStart.isAfter(earliest)) continue;
      earliest = entry.holdingStart;
    }

    return earliest;
  }

  /// Search across name, mobile, goat IDs and booking IDs.
  bool matches(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return true;

    if (name.toLowerCase().contains(q)) return true;
    if (mobile.toLowerCase().contains(q)) return true;

    for (final entry in sales) {
      if (entry.id.toLowerCase().contains(q)) return true;

      for (final goat in entry.goats) {
        if (goat.id.toLowerCase().contains(q)) return true;
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------
  // GROUPING
  // ---------------------------------------------------------------------

  /// Builds the customer list from the open Booking sales and the goats
  /// stream.
  ///
  /// A customer is identified by mobile number (last 10 digits) — the
  /// same identifier [WaitDeliveryCustomer] and the Sell Goat lookup use.
  /// If a sale has no mobile it falls back to the customer ID, then to
  /// the name.
  ///
  /// A sale only appears while it still has at least one goat that is
  /// "Booked" — anything else is stale data and is skipped rather than
  /// shown as an empty booking.
  static List<BookingDeliveryCustomer> group({
    required Iterable<Sale> sales,
    required Iterable<Goat> goats,
  }) {
    final goatsBySale = <String, List<Goat>>{};

    for (final goat in goats) {
      final saleId = (goat.saleId ?? '').trim();

      if (saleId.isEmpty || !goat.isBooked) continue;

      goatsBySale.putIfAbsent(saleId, () => <Goat>[]).add(goat);
    }

    final byCustomer = <String, List<BookingDeliverySale>>{};

    for (final sale in sales) {
      if (!sale.isBooking || sale.status != Sale.statusBooked) {
        continue;
      }

      final saleGoats = goatsBySale[sale.id.trim()];

      if (saleGoats == null || saleGoats.isEmpty) continue;

      byCustomer
          .putIfAbsent(_keyFor(sale), () => <BookingDeliverySale>[])
          .add(BookingDeliverySale(sale: sale, goats: saleGoats));
    }

    final customers = <BookingDeliveryCustomer>[];

    byCustomer.forEach((key, entries) {
      entries.sort((a, b) => b.bookedAt.compareTo(a.bookedAt));

      final newest = entries.first.sale;

      customers.add(
        BookingDeliveryCustomer(
          key: key,
          name: newest.customerName.trim().isEmpty
              ? 'Unnamed customer'
              : newest.customerName.trim(),
          mobile: newest.mobile.trim(),
          address: newest.address.trim(),
          sales: entries,
        ),
      );
    });

    customers.sort((a, b) => b.latestBookedAt.compareTo(a.latestBookedAt));

    return customers;
  }

  static String _keyFor(Sale sale) {
    var digits = sale.mobile.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }

    if (digits.isNotEmpty) return 'm:$digits';

    final id = sale.customerId.trim();

    if (id.isNotEmpty) return 'c:$id';

    return 'n:${sale.customerName.trim().toLowerCase()}';
  }
}