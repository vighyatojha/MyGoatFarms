import 'goat_model.dart';
import 'sale_model.dart';

/// One booking (a Wait for Delivery sale) that is still waiting to be
/// picked up, together with the goats that belong to it.
///
/// A sale is the unit that gets delivered: it has ONE rate (or fixed
/// price), ONE advance and ONE pickup weight (the total of its goats), so
/// its goats always move together. That is why the delivery selector
/// works on a [WaitDeliverySale] rather than on a single goat.
class WaitDeliverySale {
  final Sale sale;

  /// The sale's goats that are still "Wait on Delivery".
  final List<Goat> goats;

  const WaitDeliverySale({
    required this.sale,
    required this.goats,
  });

  String get id => sale.id;

  /// True when the goats were sold for one agreed price instead of a
  /// price per KG — the pickup weight is then only recorded, never used
  /// to reprice.
  bool get isFixedPrice => sale.isFixedPrice;

  /// The rate fixed at booking time. Meaningless for a fixed-price sale
  /// (kept there only for reference — see [Sale.fixedSalePrice] doc).
  double get ratePerKg => sale.bookingPricePerKg ?? 0;

  double get advancePaid => sale.bookingAdvanceAmount ?? 0;

  /// Total weight recorded at booking.
  double get bookedWeight => sale.bookingWeight ?? 0;

  DateTime get bookedAt => sale.createdAt ?? DateTime.now();

  /// What the goats are worth at [pickupWeight]: pickup weight x the
  /// booking-time rate, or the agreed fixed price, whatever the weight
  /// turns out to be. Delivery is never re-priced at today's rate — same
  /// rule as SalesService.completeWaitForDeliveryPickup.
  double saleValueAt(double pickupWeight) {
    return sale.goatValueAtWeight(pickupWeight);
  }

  /// What the customer still owes at pickup:
  ///
  ///   sale value at pickup weight - advance paid   (never below 0)
  ///
  /// This is the same formula SalesService.completeWaitForDeliveryPickup
  /// stores as `finalPriceAfterPickup`, so the figure shown here is the
  /// figure that gets saved.
  double remainingAt(double pickupWeight) {
    final raw = saleValueAt(pickupWeight) - advancePaid;

    return Sale.roundMoney(raw < 0 ? 0 : raw);
  }

  /// Estimate at the weight recorded when the goats were booked.
  double get estimatedRemaining => remainingAt(bookedWeight);
}

/// A customer who has goats waiting for delivery, with every open booking
/// they have. This is what the "Wait on Delivery" tab lists.
class WaitDeliveryCustomer {
  /// Stable grouping key (see [group]).
  final String key;

  final String name;
  final String mobile;
  final String address;

  /// Open bookings, newest first.
  final List<WaitDeliverySale> sales;

  const WaitDeliveryCustomer({
    required this.key,
    required this.name,
    required this.mobile,
    required this.address,
    required this.sales,
  });

  /// Every waiting goat of this customer, booking by booking.
  List<Goat> get goats {
    return [
      for (final entry in sales) ...entry.goats,
    ];
  }

  int get goatCount {
    return sales.fold<int>(0, (sum, entry) => sum + entry.goats.length);
  }

  double get advanceTotal {
    return Sale.roundMoney(
      sales.fold<double>(0, (sum, entry) => sum + entry.advancePaid),
    );
  }

  /// Sum of each booking's estimate at its booked weight.
  double get estimatedRemaining {
    return Sale.roundMoney(
      sales.fold<double>(0, (sum, entry) => sum + entry.estimatedRemaining),
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

  /// True when at least one waiting goat has the given gender.
  bool hasGoatWithGender(String gender) {
    final wanted = gender.trim().toLowerCase();

    return goats.any((goat) => goat.gender.trim().toLowerCase() == wanted);
  }

  // ---------------------------------------------------------------------
  // GROUPING
  // ---------------------------------------------------------------------

  /// Builds the customer list from the open Wait for Delivery sales and
  /// the goats stream.
  ///
  /// A customer is identified by mobile number (last 10 digits) — the
  /// same identifier the Sell Goat lookup uses to find a returning
  /// customer. If a sale has no mobile it falls back to the customer ID,
  /// then to the name. This keeps one person together even when their
  /// bookings were saved against a Sale customer record on one occasion
  /// and a Palai customer record on another.
  ///
  /// A sale only appears while it still has at least one goat that is
  /// "Wait on Delivery" — anything else is stale data and is skipped
  /// rather than shown as an empty booking.
  static List<WaitDeliveryCustomer> group({
    required Iterable<Sale> sales,
    required Iterable<Goat> goats,
  }) {
    final goatsBySale = <String, List<Goat>>{};

    for (final goat in goats) {
      final saleId = (goat.saleId ?? '').trim();

      if (saleId.isEmpty || !goat.isWaitOnDelivery) continue;

      goatsBySale.putIfAbsent(saleId, () => <Goat>[]).add(goat);
    }

    final byCustomer = <String, List<WaitDeliverySale>>{};

    for (final sale in sales) {
      if (!sale.isWaitForDelivery ||
          sale.status != Sale.statusWaitForDelivery) {
        continue;
      }

      final saleGoats = goatsBySale[sale.id.trim()];

      if (saleGoats == null || saleGoats.isEmpty) continue;

      byCustomer
          .putIfAbsent(_keyFor(sale), () => <WaitDeliverySale>[])
          .add(WaitDeliverySale(sale: sale, goats: saleGoats));
    }

    final customers = <WaitDeliveryCustomer>[];

    byCustomer.forEach((key, entries) {
      entries.sort((a, b) => b.bookedAt.compareTo(a.bookedAt));

      final newest = entries.first.sale;

      customers.add(
        WaitDeliveryCustomer(
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