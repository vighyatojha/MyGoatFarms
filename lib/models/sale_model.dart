import 'package:cloud_firestore/cloud_firestore.dart';

/// One balance payment collected against a sale after the goat was
/// delivered (Booking / Wait for Delivery final balance, or the unpaid
/// part of a Deliver Now sale).
///
/// Stored inside the sale document itself, in its `payments` list, so the
/// receipt gets the full payment history from the one document it already
/// loads, and a payment is recorded in the same transaction that checks
/// the balance. Collecting a balance never creates Finance revenue: the
/// revenue for the sale was already recorded in full at delivery.
class SalePayment {
  final double amount;
  final String method;
  final DateTime date;
  final String note;

  const SalePayment({
    required this.amount,
    required this.method,
    required this.date,
    this.note = '',
  });

  factory SalePayment.fromMap(Map<String, dynamic> data) {
    final rawAmount = data['amount'];
    final rawDate = data['date'];

    return SalePayment(
      amount: rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse(rawAmount?.toString() ?? '') ?? 0.0,
      method: (data['method'] ?? '').toString(),
      date: rawDate is Timestamp
          ? rawDate.toDate()
          : rawDate is DateTime
          ? rawDate
          : DateTime.fromMillisecondsSinceEpoch(0),
      note: (data['note'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'method': method,
      'date': Timestamp.fromDate(date),
      if (note.trim().isNotEmpty) 'note': note.trim(),
    };
  }
}

/// A single Sale transaction, covering one or more goats.
///
/// Stored at:
/// farms/{farmId}/sales/{saleId}
///
/// Steps 1-4 (Section 2 of the Phase 4 plan) populate the shared fields.
/// Step 5 (Section 3) picks exactly one [deliveryType] and fills in that
/// branch's fields only — the other three branches' fields stay null.
/// This mirrors the plan's instruction to build each branch as its own
/// sub-task rather than one mega-form.
class Sale {
  final String id;

  // ---------------------------------------------------------------------
  // GOATS (Task 2.1)
  // ---------------------------------------------------------------------

  final List<String> goatIds;

  // ---------------------------------------------------------------------
  // CUSTOMER (Task 2.2)
  // ---------------------------------------------------------------------

  final String customerId;
  final String customerName;
  final String mobile;
  final String address;

  // ---------------------------------------------------------------------
  // SALE DETAILS (Task 2.4)
  // ---------------------------------------------------------------------

  /// Selling price/kg. For [statusWaitForDelivery], this is the price
  /// fixed at booking time — see [bookingPricePerKg] doc comment below
  /// for why that is tracked as a separate field instead of reusing
  /// this one when the final delivery is completed.
  final double sellingPricePerKg;

  final double sellingWeight;

  /// Auto-calculated: sellingPricePerKg * sellingWeight, summed across
  /// every goat in [goatIds]. Never manually overridden, same rule as
  /// the Purchase wizard's Purchase Amount.
  final double totalSaleAmount;

  final String deliveryType;

  // ---------------------------------------------------------------------
  // BRANCH A: DELIVER NOW (Task 3.1)
  // ---------------------------------------------------------------------

  final double? transportCost;
  final double? amountReceived;

  /// paymentStatus one of [paymentStatusValues].
  final String? paymentStatus;

  // ---------------------------------------------------------------------
  // BRANCH B: BOOKING / HOLDING (Task 3.2)
  // ---------------------------------------------------------------------

  final double? bookingAmount;

  /// Only for reference — when the customer said they would collect. It
  /// is NOT used to calculate anything: holding charges run until the
  /// day the delivery is actually completed.
  final DateTime? expectedDeliveryDate;

  /// Estimated holding days. Older bookings only — new bookings no longer
  /// ask for an estimate, because the days are counted from
  /// [holdingStartDate] to the delivery date when the delivery is
  /// completed.
  final int? holdingDays;
  final double? holdingChargePerDay;

  /// The day the goat's holding began (the booking day). Holding days are
  /// counted from here, this day included. Bookings made before this
  /// field existed fall back to their creation date — see [holdingStart].
  final DateTime? holdingStartDate;

  /// The delivery date the holding charges were counted up to (this day
  /// included). Set by the Complete Delivery action.
  final DateTime? holdingEndDate;

  /// Holding charges: [actualHoldingDays] x [holdingChargePerDay].
  /// Null until the delivery is completed — it is not known before then.
  final double? totalHoldingCharges;

  /// Holding days counted when the delivery was completed: start day and
  /// delivery day both included (booked 20 Sept, delivered 23 Sept = 4
  /// days). See [holdingDaysBetween].
  final int? actualHoldingDays;

  /// Set by the Complete Delivery action for Branch B: what the customer
  /// still owes at pickup — Goat Sale Amount + Holding Charges +
  /// Transportation - Booking Amount already paid.
  final double? finalAmountAfterHolding;

  final DateTime? deliveryCompletedAt;

  // ---------------------------------------------------------------------
  // BRANCH C: WAIT FOR DELIVERY (Task 3.3)
  // ---------------------------------------------------------------------

  /// Price/kg fixed at booking time. Kept separate from
  /// [sellingPricePerKg] so the "Complete Delivery" action can never
  /// accidentally re-price at the current market rate — it must always
  /// read this field, never today's price/kg. See the plan's Section 5
  /// note: this is flagged as the easiest thing in the phase to get
  /// backwards.
  final double? bookingPricePerKg;

  final double? bookingAdvanceAmount;

  /// Weight recorded at booking time (before the animal is picked up).
  final double? bookingWeight;

  /// Weight recorded at pickup, filled in by the Complete Delivery
  /// action. Final Price = pickupWeight * bookingPricePerKg (never the
  /// current rate) + transportation - bookingAdvanceAmount.
  final double? pickupWeight;
  final double? finalPriceAfterPickup;

  // ---------------------------------------------------------------------
  // BRANCH D: TRANSFER TO PALAI (Task 3.4)
  // ---------------------------------------------------------------------

  final DateTime? transferDate;
  final String? palaiPackage;
  final double? monthlyPalaiCharge;

  /// Set once the handoff into the Customer Palai module (a
  /// PalaiCustomer doc) is created — see SalesService.transferToPalai().
  final String? palaiCustomerId;

  // ---------------------------------------------------------------------
  // STATUS
  // ---------------------------------------------------------------------

  final String status;
  final DateTime? createdAt;

  // ---------------------------------------------------------------------
  // BALANCE PAYMENTS
  // ---------------------------------------------------------------------

  /// Payments collected after delivery, oldest first. Empty until the
  /// first one is received. See [SalePayment] and
  /// SalesService.receiveBalancePayment.
  final List<SalePayment> payments;

  /// How the initial payment (amount received / booking amount /
  /// advance) was made — Cash, UPI, Bank Transfer, ... Chosen in the
  /// Sell Goat form and used as the payment method of the Sold Goat
  /// Revenue entry for that money, so the Finance Cash / Online tracker
  /// is right. Later balance payments carry their own method in
  /// [SalePayment.method].
  final String? paymentMethod;

  const Sale({
    required this.id,
    required this.goatIds,
    required this.customerId,
    required this.customerName,
    required this.mobile,
    required this.address,
    required this.sellingPricePerKg,
    required this.sellingWeight,
    required this.totalSaleAmount,
    required this.deliveryType,
    required this.status,
    this.transportCost,
    this.amountReceived,
    this.paymentStatus,
    this.bookingAmount,
    this.expectedDeliveryDate,
    this.holdingDays,
    this.holdingChargePerDay,
    this.holdingStartDate,
    this.holdingEndDate,
    this.totalHoldingCharges,
    this.actualHoldingDays,
    this.finalAmountAfterHolding,
    this.deliveryCompletedAt,
    this.bookingPricePerKg,
    this.bookingAdvanceAmount,
    this.bookingWeight,
    this.pickupWeight,
    this.finalPriceAfterPickup,
    this.transferDate,
    this.palaiPackage,
    this.monthlyPalaiCharge,
    this.palaiCustomerId,
    this.createdAt,
    this.payments = const [],
    this.paymentMethod,
  });

  // ---------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------

  static const String deliveryTypeDeliverNow = 'DeliverNow';
  static const String deliveryTypeBooking = 'Booking';
  static const String deliveryTypeWaitForDelivery = 'WaitForDelivery';
  static const String deliveryTypePalai = 'Palai';

  static const List<String> deliveryTypeValues = [
    deliveryTypeDeliverNow,
    deliveryTypeBooking,
    deliveryTypeWaitForDelivery,
    deliveryTypePalai,
  ];

  static const String paymentStatusPaid = 'Paid';
  static const String paymentStatusPartial = 'Partial';
  static const String paymentStatusPending = 'Pending';

  static const List<String> paymentStatusValues = [
    paymentStatusPaid,
    paymentStatusPartial,
    paymentStatusPending,
  ];

  // Sale-record status (distinct from Goat.currentStatus, which mirrors
  // this per-goat). Kept as plain strings, one per branch's lifecycle.
  static const String statusSold = 'Sold';
  static const String statusBooked = 'Booked';
  static const String statusDeliveryCompleted = 'DeliveryCompleted';
  static const String statusWaitForDelivery = 'WaitForDelivery';
  static const String statusPickupCompleted = 'PickupCompleted';
  static const String statusTransferredToPalai = 'TransferredToPalai';

  // ---------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------

  bool get isDeliverNow =>
      deliveryType == deliveryTypeDeliverNow;

  bool get isBooking =>
      deliveryType == deliveryTypeBooking;

  bool get isWaitForDelivery =>
      deliveryType == deliveryTypeWaitForDelivery;

  bool get isPalaiTransfer =>
      deliveryType == deliveryTypePalai;

  bool get isMultiGoat => goatIds.length > 1;

  /// The first day of a Booking's holding: the saved start date, or the
  /// day the sale was created for bookings saved before that date was
  /// stored.
  DateTime get holdingStart => holdingStartDate ?? createdAt ?? DateTime.now();

  /// Holding days from [start] to [end], BOTH days counted: booked on the
  /// 20th and delivered on the 23rd = 20, 21, 22, 23 = 4 days. Booked and
  /// delivered on the same day = 1 day. Only the calendar day matters,
  /// not the time. Returns 0 if [end] is before [start].
  static int holdingDaysBetween(DateTime start, DateTime end) {
    final from = DateTime.utc(start.year, start.month, start.day);
    final to = DateTime.utc(end.year, end.month, end.day);

    if (to.isBefore(from)) return 0;

    return to.difference(from).inDays + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is Sale && other.id == id;

  @override
  int get hashCode => id.hashCode;

  // ---------------------------------------------------------------------
  // CUSTOMER BILL (used by the Sale Receipt screen and PDF)
  // ---------------------------------------------------------------------
  //
  //   Goat Sale              ₹20,000
  //   Holding Charges           ₹500   (Booking only)
  //   Transportation          ₹1,000   (Deliver Now only)
  //   ------------------------------
  //   Customer Total         ₹21,500
  //
  // Transportation is collected from the customer but passed on to the
  // transport team, so it is part of what the customer pays
  // ([billCustomerTotal]) and is NOT farm revenue. Sold Goat Revenue is
  // Customer Total - Transportation = Goat Sale + Holding Charges, and it
  // is recorded as the customer's money is received (see "FINANCE
  // REVENUE" below and SalesService._recordSaleReceiptRevenue).
  //
  // These getters deliberately do not read [finalAmountAfterHolding] or
  // [finalPriceAfterPickup]: SalesService stores both as the REMAINING
  // balance (already net of the booking amount / advance). Using them as
  // the gross total and then subtracting the amount paid again would
  // understate what is still owed, so the gross total is rebuilt here
  // from its parts.

  /// True once a Wait for Delivery sale has been picked up and its pickup
  /// weight recorded.
  bool get hasPickupSettlement =>
      isWaitForDelivery &&
          status == statusPickupCompleted &&
          pickupWeight != null;

  /// Goat sale value on the bill.
  ///
  /// Normally [totalSaleAmount]. After a Wait for Delivery pickup it is
  /// pickup weight x the booking-time rate (never today's rate), which is
  /// the same figure SalesService records as revenue at pickup. Note that
  /// [totalSaleAmount] itself keeps the booking-weight value.
  double get billGoatSale => hasPickupSettlement
      ? _round2(pickupWeight! * (bookingPricePerKg ?? sellingPricePerKg))
      : _round2(totalSaleAmount);

  /// Holding charges on the bill. Booking sales only; 0 otherwise.
  double get billHoldingCharges =>
      isBooking ? _nonNegative(totalHoldingCharges ?? 0) : 0.0;

  /// Transportation charge collected from the customer for the transport
  /// team. 0 when there is none.
  ///
  /// Only Deliver Now sales carry a transportation charge. Booking, Wait
  /// for Delivery and Transfer to Palai never do, so this is always 0 for
  /// them — even if an older record happens to have a `transportCost`
  /// stored on it.
  double get billTransportCharges =>
      isDeliverNow ? _nonNegative(transportCost ?? 0) : 0.0;

  /// Goat Sale + Holding Charges + Transportation.
  double get billCustomerTotal => _round2(
    billGoatSale + billHoldingCharges + billTransportCharges,
  );

  /// Money received when the sale was made: amount received (Deliver
  /// Now), booking amount (Booking) or advance (Wait for Delivery).
  double get billInitialPayment {
    if (isDeliverNow) return _nonNegative(amountReceived ?? 0);
    if (isBooking) return _nonNegative(bookingAmount ?? 0);
    if (isWaitForDelivery) return _nonNegative(bookingAdvanceAmount ?? 0);

    return 0.0;
  }

  /// Receipt label for [billInitialPayment].
  String get billInitialPaymentLabel {
    if (isBooking) return 'Booking Amount Paid';
    if (isWaitForDelivery) return 'Advance Paid';

    return 'Amount Received';
  }

  /// Sum of the balance payments collected after delivery.
  double get billBalancePayments => _nonNegative(
    payments.fold<double>(0.0, (sum, p) => sum + p.amount),
  );

  /// Everything received so far: the initial payment plus any balance
  /// payments collected after delivery.
  double get billAmountPaid =>
      _round2(billInitialPayment + billBalancePayments);

  /// Customer Total - Amount Paid. Never negative.
  double get billBalanceDue =>
      _nonNegative(billCustomerTotal - billAmountPaid);

  /// True once the goat(s) have actually left the farm: a Deliver Now
  /// sale, a completed Booking delivery, or a completed Wait for
  /// Delivery pickup.
  bool get isDelivered =>
      status == statusSold ||
          status == statusDeliveryCompleted ||
          status == statusPickupCompleted;

  /// A balance can be collected only after delivery, and only while
  /// something is still owed.
  bool get canCollectBalance => isDelivered && billBalanceDue > 0;

  // ---------------------------------------------------------------------
  // FINANCE REVENUE (Sold Goat Revenue)
  // ---------------------------------------------------------------------
  //
  // Finance works on money RECEIVED (Net Cash Flow, the Cash / Online
  // tracker, Palai payments), so Sold Goat Revenue is recorded as the
  // customer's money comes in rather than the whole sale up front. Each
  // receipt is its own Finance entry, linked to the sale by saleId.
  //
  // Transportation is the LAST part of the bill to be settled and is
  // never revenue (it is paid on to the transport team). So money
  // received counts as revenue until Goat Sale + Holding Charges is
  // covered; anything beyond that is transportation.
  //
  //   Bill: Goat Sale 20,000 + Holding 500 + Transportation 1,000
  //         = Customer Total 21,500
  //
  //   Paid  5,000  -> revenue  5,000
  //   Paid 20,500  -> revenue 20,500
  //   Paid 21,500  -> revenue 20,500  (the last 1,000 is transportation)

  /// The part of the bill that is farm revenue: Goat Sale + Holding
  /// Charges (everything except transportation).
  double get billRevenueTotal => _round2(billGoatSale + billHoldingCharges);

  /// Revenue earned so far from the money received so far.
  double get billRevenueReceived => revenueFromPaid(
    paid: billAmountPaid,
    revenueTotal: billRevenueTotal,
  );

  /// How much of [paid] counts as revenue given the sale's
  /// [revenueTotal] (Goat Sale + Holding Charges). Money past that is
  /// transportation, not revenue.
  static double revenueFromPaid({
    required double paid,
    required double revenueTotal,
  }) {
    final received = _nonNegative(paid);
    final cap = _nonNegative(revenueTotal);

    return received < cap ? received : cap;
  }

  /// Rounds to 2 decimals so floating-point drift (e.g.
  /// 27456.000000000004) never shows up in a figure or flips "PAID" to
  /// "PARTIALLY PAID". Same rounding as SaleDraft.round2.
  static double _round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;

    final nudge = value >= 0 ? 1e-9 : -1e-9;

    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  /// Never negative and never `-0.0` (which would print as "-₹0.00").
  static double _nonNegative(double value) {
    final rounded = _round2(value);

    return rounded <= 0 ? 0.0 : rounded;
  }

  // ---------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------

  factory Sale.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    DateTime? dateFrom(String key) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return null;
    }

    double numFrom(String key) {
      final value = data[key];

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    double? nullableNumFrom(String key) {
      if (!data.containsKey(key) || data[key] == null) {
        return null;
      }

      return numFrom(key);
    }

    int? nullableIntFrom(String key) {
      final value = data[key];

      if (value == null) {
        return null;
      }

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(value.toString());
    }

    return Sale(
      id: doc.id,

      goatIds: (data['goatIds'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
          const [],

      customerId:
      (data['customerId'] ?? '').toString(),

      customerName:
      (data['customerName'] ?? '').toString(),

      mobile:
      (data['mobile'] ?? '').toString(),

      address:
      (data['address'] ?? '').toString(),

      sellingPricePerKg:
      numFrom('sellingPricePerKg'),

      sellingWeight:
      numFrom('sellingWeight'),

      totalSaleAmount:
      numFrom('totalSaleAmount'),

      deliveryType:
      (data['deliveryType'] ?? '').toString(),

      status:
      (data['status'] ?? '').toString(),

      transportCost: nullableNumFrom('transportCost'),
      amountReceived: nullableNumFrom('amountReceived'),
      paymentStatus: data['paymentStatus'] as String?,

      bookingAmount: nullableNumFrom('bookingAmount'),
      expectedDeliveryDate: dateFrom('expectedDeliveryDate'),
      holdingDays: nullableIntFrom('holdingDays'),
      holdingChargePerDay: nullableNumFrom('holdingChargePerDay'),
      holdingStartDate: dateFrom('holdingStartDate'),
      holdingEndDate: dateFrom('holdingEndDate'),
      totalHoldingCharges: nullableNumFrom('totalHoldingCharges'),
      actualHoldingDays: nullableIntFrom('actualHoldingDays'),
      finalAmountAfterHolding:
      nullableNumFrom('finalAmountAfterHolding'),
      deliveryCompletedAt: dateFrom('deliveryCompletedAt'),

      bookingPricePerKg: nullableNumFrom('bookingPricePerKg'),
      bookingAdvanceAmount: nullableNumFrom('bookingAdvanceAmount'),
      bookingWeight: nullableNumFrom('bookingWeight'),
      pickupWeight: nullableNumFrom('pickupWeight'),
      finalPriceAfterPickup: nullableNumFrom('finalPriceAfterPickup'),

      transferDate: dateFrom('transferDate'),
      palaiPackage: data['palaiPackage'] as String?,
      monthlyPalaiCharge: nullableNumFrom('monthlyPalaiCharge'),
      palaiCustomerId: data['palaiCustomerId'] as String?,

      createdAt: dateFrom('createdAt'),

      paymentMethod: data['paymentMethod'] as String?,

      payments: (data['payments'] as List?)
          ?.whereType<Map>()
          .map(
            (e) => SalePayment.fromMap(
          Map<String, dynamic>.from(e),
        ),
      )
          .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'goatIds': goatIds,
      'customerId': customerId,
      'customerName': customerName.trim(),
      'mobile': mobile.trim(),
      'address': address.trim(),
      'sellingPricePerKg': sellingPricePerKg,
      'sellingWeight': sellingWeight,
      'totalSaleAmount': totalSaleAmount,
      'deliveryType': deliveryType,
      'status': status,
    };

    void putIfNotNull(String key, dynamic value) {
      if (value == null) return;

      if (value is DateTime) {
        map[key] = Timestamp.fromDate(value);
        return;
      }

      map[key] = value;
    }

    putIfNotNull('transportCost', transportCost);
    putIfNotNull('amountReceived', amountReceived);
    putIfNotNull('paymentStatus', paymentStatus);

    putIfNotNull('bookingAmount', bookingAmount);
    putIfNotNull('expectedDeliveryDate', expectedDeliveryDate);
    putIfNotNull('holdingDays', holdingDays);
    putIfNotNull('holdingChargePerDay', holdingChargePerDay);
    putIfNotNull('holdingStartDate', holdingStartDate);
    putIfNotNull('holdingEndDate', holdingEndDate);
    putIfNotNull('totalHoldingCharges', totalHoldingCharges);
    putIfNotNull('actualHoldingDays', actualHoldingDays);
    putIfNotNull(
      'finalAmountAfterHolding',
      finalAmountAfterHolding,
    );
    putIfNotNull(
      'deliveryCompletedAt',
      deliveryCompletedAt,
    );

    putIfNotNull('bookingPricePerKg', bookingPricePerKg);
    putIfNotNull(
      'bookingAdvanceAmount',
      bookingAdvanceAmount,
    );
    putIfNotNull('bookingWeight', bookingWeight);
    putIfNotNull('pickupWeight', pickupWeight);
    putIfNotNull(
      'finalPriceAfterPickup',
      finalPriceAfterPickup,
    );

    putIfNotNull('transferDate', transferDate);
    putIfNotNull('palaiPackage', palaiPackage);
    putIfNotNull('monthlyPalaiCharge', monthlyPalaiCharge);
    putIfNotNull('palaiCustomerId', palaiCustomerId);
    putIfNotNull('paymentMethod', paymentMethod);

    if (payments.isNotEmpty) {
      map['payments'] = payments.map((p) => p.toMap()).toList();
    }

    return map;
  }
}