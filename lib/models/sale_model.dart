import 'package:cloud_firestore/cloud_firestore.dart';

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
  final DateTime? expectedDeliveryDate;
  final int? holdingDays;
  final double? holdingChargePerDay;

  /// Auto-calculated: holdingDays * holdingChargePerDay.
  final double? totalHoldingCharges;

  /// Actual elapsed holding days, recorded by the Complete Delivery
  /// action (Phase 5, Section 1). Kept separate from [holdingDays] (the
  /// original estimate made at booking time in Step 5) because the
  /// customer may pick up later or earlier than expected — the plan's
  /// Task 1.2 requires the final settlement to use real elapsed time,
  /// not the original quote.
  final int? actualHoldingDays;

  /// Set by the (future, Task "Complete Delivery" for Branch B) action:
  /// Goat Sale Amount + Holding Charges - Amount Already Paid.
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
  /// current rate) - bookingAdvanceAmount.
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

  @override
  bool operator ==(Object other) =>
      other is Sale && other.id == id;

  @override
  int get hashCode => id.hashCode;

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

    return map;
  }
}