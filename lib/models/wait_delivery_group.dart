import 'goat_model.dart';
import 'sale_model.dart';
import 'sale_settlement.dart';

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

  /// Goats in this sale. A lot sale has no goat records (the goats are
  /// anonymous inside the lot), so its quantity is used instead of
  /// `goats.length`.
  int get goatCount => sale.isLotSale ? sale.lotQuantity : goats.length;

  bool get isLotSale => sale.isLotSale;

  /// True when the goats were sold for one agreed price instead of a
  /// price per KG. It is converted to a locked rate per KG (agreed amount
  /// / booked weight) and repriced by the pickup weight like a per-KG deal.
  bool get isFixedPrice => sale.isFixedPrice;

  /// The locked price per KG (for display): the booking-time rate, or the
  /// fixed price / booked weight.
  double get ratePerKg => sale.lockedRatePerKg;

  double get advancePaid => sale.bookingAdvanceAmount ?? 0;

  /// Total weight recorded at booking.
  double get bookedWeight => sale.bookedWeightTotal;

  DateTime get bookedAt => sale.saleDate ?? sale.holdingStart;

  /// What the goats are worth at [pickupWeight]: the agreed amount x
  /// pickup weight / booked weight (per-KG: pickup weight x the
  /// booking-time rate). Delivery is never re-priced at today's rate —
  /// same rule as SalesService.completeWaitForDeliveryPickup.
  double saleValueAt(double pickupWeight) {
    return sale.goatValueAtWeight(pickupWeight);
  }

  /// Discount given when the goats were booked. It is the starting value
  /// of the discount field at pickup, where it can be changed.
  double get bookingDiscount => sale.appliedDiscount;

  /// The pickup settlement at [pickupWeight]: goat value (before discount),
  /// the discount, transportation and the advance already paid, worked out
  /// by [SaleSettlement] so the figures here are exactly the ones
  /// SalesService.completeWaitForDeliveryPickup saves.
  ///
  /// [discount] null means "the discount given at booking". [transport] is
  /// the optional transportation charge entered at pickup. It is collected
  /// on top of the goat value and passed on to the transport team, so it
  /// is never farm revenue.
  SaleSettlement settlementAt(
      double pickupWeight, {
        double transport = 0,
        double? discount,
        ExcessAction excessAction = ExcessAction.carryToAdvance,
      }) {
    return SaleSettlement.fromAmount(
      goatAmount: saleValueAt(pickupWeight),
      discount: discount ?? bookingDiscount,
      transportCharge: transport < 0 ? 0 : transport,
      advancePaid: advancePaid,
      excessAction: excessAction,
    );
  }

  /// What the customer still owes at pickup:
  ///
  ///   sale value at pickup weight - discount + transportation - advance
  ///                                                   (never below 0)
  ///
  /// This is the same formula SalesService.completeWaitForDeliveryPickup
  /// stores as `finalPriceAfterPickup`, so the figure shown here is the
  /// figure that gets saved.
  double remainingAt(
      double pickupWeight, {
        double transport = 0,
        double? discount,
      }) {
    return settlementAt(
      pickupWeight,
      transport: transport,
      discount: discount,
    ).balanceDue;
  }

  /// What the advance covered beyond the final bill (0 when it did not).
  /// Example: 85 kg x 620 = 52,700 against a 60,000 advance -> 7,300.
  double excessAt(
      double pickupWeight, {
        double transport = 0,
        double? discount,
      }) {
    return settlementAt(
      pickupWeight,
      transport: transport,
      discount: discount,
    ).excess;
  }

  /// Estimate at the weight recorded when the goats were booked.
  double get estimatedRemaining => remainingAt(bookedWeight);
}

/// What one ticked booking owes and has already paid, as the input to
/// [WaitDeliveryAllocator.allocate].
///
/// [payable] is the final bill at pickup: goat value - discount +
/// transport (exactly [SaleSettlement.payable]). [advancePaid] is the
/// advance already received on this booking.
class WaitDeliveryBill {
  final String saleId;
  final double payable;
  final double advancePaid;

  const WaitDeliveryBill({
    required this.saleId,
    required this.payable,
    required this.advancePaid,
  });
}

/// Part of one booking's extra advance that pays another booking's due.
class WaitDeliveryTransfer {
  final String fromSaleId;
  final String toSaleId;
  final double amount;

  const WaitDeliveryTransfer({
    required this.fromSaleId,
    required this.toSaleId,
    required this.amount,
  });
}

/// The result for one booking after the shared pool has been applied.
class WaitDeliverySaleAllocation {
  final String saleId;
  final double payable;
  final double advancePaid;

  /// Extra advance this booking handed to other bookings.
  final double givenOut;

  /// Extra advance this booking received from other bookings.
  final double takenIn;

  /// What is still to collect after the transfers (never below 0).
  final double toCollect;

  /// Extra of THIS booking left after the transfers. Only this part goes
  /// to the "Add to advance / Return to customer" choice.
  final double leftoverExcess;

  const WaitDeliverySaleAllocation({
    required this.saleId,
    required this.payable,
    required this.advancePaid,
    required this.givenOut,
    required this.takenIn,
    required this.toCollect,
    required this.leftoverExcess,
  });

  bool get isDonor => givenOut > 0;

  bool get isReceiver => takenIn > 0;
}

/// Everything the screen and the service need from one allocation run.
class WaitDeliveryAllocation {
  final List<WaitDeliveryTransfer> transfers;
  final Map<String, WaitDeliverySaleAllocation> bySale;

  const WaitDeliveryAllocation({
    required this.transfers,
    required this.bySale,
  });

  /// Total still to collect across every booking.
  double get totalToCollect {
    return Sale.roundMoney(
      bySale.values.fold<double>(0, (sum, a) => sum + a.toCollect),
    );
  }

  /// Total extra left for the advance / refund choice.
  double get totalLeftoverExcess {
    return Sale.roundMoney(
      bySale.values.fold<double>(0, (sum, a) => sum + a.leftoverExcess),
    );
  }

  bool get hasTransfers => transfers.isNotEmpty;

  /// Transfers that go INTO [saleId].
  List<WaitDeliveryTransfer> transfersInto(String saleId) =>
      transfers.where((t) => t.toSaleId == saleId).toList();

  /// Transfers that come OUT OF [saleId].
  List<WaitDeliveryTransfer> transfersFrom(String saleId) =>
      transfers.where((t) => t.fromSaleId == saleId).toList();
}

/// Treats every ticked booking as ONE customer settlement.
///
/// A booking whose advance is more than its bill is a donor; its extra
/// goes into a pool that covers the dues of bookings whose advance is
/// less than their bill (receivers). Only what is left in the pool after
/// every due is covered goes to the advance / refund choice.
///
/// Pure and deterministic: the screen shows its result and the service
/// re-runs it before saving, so the preview and the saved data cannot
/// disagree. Works in whole paise, so there is never a rounding gap.
///
/// Example: S-0024 bill 13,740 / advance 20,000 (extra 6,260) and
/// S-0023 bill 34,100 / advance 20,000 (due 14,100) -> S-0024 gives
/// 6,260 to S-0023, which then collects 7,840.
class WaitDeliveryAllocator {
  WaitDeliveryAllocator._();

  static int _paise(double rupees) {
    if (rupees.isNaN || rupees.isInfinite) return 0;

    final nudge = rupees >= 0 ? 1e-9 : -1e-9;

    return ((rupees + nudge) * 100).round();
  }

  static double _rupees(int paise) => paise / 100.0;

  /// [bills] must be in the order the bookings appear on screen: donors
  /// are drawn on, and receivers are covered, in that order.
  static WaitDeliveryAllocation allocate(List<WaitDeliveryBill> bills) {
    final payable = <String, int>{};
    final advance = <String, int>{};
    final pool = <String, int>{}; // donor -> extra still unspent
    final extra = <String, int>{};
    final givenOut = <String, int>{};
    final takenIn = <String, int>{};
    final due = <String, int>{};

    for (final bill in bills) {
      final p = _paise(bill.payable);
      final a = _paise(bill.advancePaid);

      payable[bill.saleId] = p;
      advance[bill.saleId] = a;
      givenOut[bill.saleId] = 0;
      takenIn[bill.saleId] = 0;

      if (a > p) {
        extra[bill.saleId] = a - p;
        pool[bill.saleId] = a - p;
      } else {
        extra[bill.saleId] = 0;
      }

      due[bill.saleId] = a < p ? p - a : 0;
    }

    final transfers = <WaitDeliveryTransfer>[];

    for (final receiver in bills) {
      var need = due[receiver.saleId] ?? 0;

      if (need <= 0) continue;

      for (final donor in bills) {
        if (need <= 0) break;

        final available = pool[donor.saleId] ?? 0;

        if (available <= 0 || donor.saleId == receiver.saleId) continue;

        final take = available < need ? available : need;

        pool[donor.saleId] = available - take;
        need -= take;
        givenOut[donor.saleId] = (givenOut[donor.saleId] ?? 0) + take;
        takenIn[receiver.saleId] = (takenIn[receiver.saleId] ?? 0) + take;

        transfers.add(
          WaitDeliveryTransfer(
            fromSaleId: donor.saleId,
            toSaleId: receiver.saleId,
            amount: _rupees(take),
          ),
        );
      }
    }

    final bySale = <String, WaitDeliverySaleAllocation>{};

    for (final bill in bills) {
      final id = bill.saleId;
      final collect = (due[id] ?? 0) - (takenIn[id] ?? 0);

      bySale[id] = WaitDeliverySaleAllocation(
        saleId: id,
        payable: _rupees(payable[id] ?? 0),
        advancePaid: _rupees(advance[id] ?? 0),
        givenOut: _rupees(givenOut[id] ?? 0),
        takenIn: _rupees(takenIn[id] ?? 0),
        toCollect: _rupees(collect < 0 ? 0 : collect),
        leftoverExcess: _rupees(pool[id] ?? 0),
      );
    }

    return WaitDeliveryAllocation(transfers: transfers, bySale: bySale);
  }
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
    return sales.fold<int>(0, (sum, entry) => sum + entry.goatCount);
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

  /// Search across name, mobile, goat IDs, lot IDs and booking IDs.
  bool matches(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return true;

    if (name.toLowerCase().contains(q)) return true;
    if (mobile.toLowerCase().contains(q)) return true;

    for (final entry in sales) {
      if (entry.id.toLowerCase().contains(q)) return true;

      if (entry.isLotSale &&
          (entry.sale.lotDocId.toLowerCase().contains(q) ||
              entry.sale.lotDisplayId.toLowerCase().contains(q))) {
        return true;
      }

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
  /// An individual-goat sale only appears while it still has at least one goat that is
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

      // A lot sale has no goat records — it is held as a quantity in the
      // lot — so it is listed on its own merit instead of being skipped
      // as stale.
      if (sale.isLotSale) {
        if (sale.lotQuantity <= 0) continue;

        byCustomer
            .putIfAbsent(_keyFor(sale), () => <WaitDeliverySale>[])
            .add(WaitDeliverySale(sale: sale, goats: const <Goat>[]));
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