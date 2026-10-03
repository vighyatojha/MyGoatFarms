import 'package:cloud_firestore/cloud_firestore.dart';

import 'purchase_costing.dart';

/// Display text for a supplier payment status ('Unpaid' / 'Partial' /
/// 'Paid'). The stored / derived strings stay as they are — only what the
/// user reads changes, to match the spec wording (Unpaid / Partially Paid /
/// Fully Paid).
String supplierPaymentStatusLabel(String status) {
  switch (status) {
    case 'Paid':
      return 'Fully Paid';
    case 'Partial':
      return 'Partially Paid';
    default:
      return status;
  }
}

/// Where a lot's goats physically are right now.
enum LotLocation { atSupplier, partiallyAtFarm, atFarm }

extension LotLocationLabel on LotLocation {
  String get label {
    switch (this) {
      case LotLocation.atSupplier:
        return 'At Supplier';
      case LotLocation.partiallyAtFarm:
        return 'Partially at Farm';
      case LotLocation.atFarm:
        return 'At Farm';
    }
  }
}

/// A wholesale goat purchase in the Trading module.
///
/// Stored at:
/// farms/{farmId}/tradingPurchases/{purchaseId}
///
/// Receiving is intentionally optional when the purchase is first saved.
/// A purchase can therefore exist in one of two states:
///
/// 1. receivingStatus == 'completed'
///    Receiving information was entered during purchase.
///
/// 2. receivingStatus == 'pending'
///    Purchase was saved without receiving details and must be completed
///    later from the Trading Dashboard.
///
/// Payment methods for Trading purchases are intentionally limited to:
/// Cash
/// Online
///
/// ---------------------------------------------------------------------
/// LOT MODEL (lotSchema >= 1)
/// ---------------------------------------------------------------------
/// A purchase is now a **Purchase Lot** — the parent of everything that
/// happens to that batch of goats. The Firestore document id is
/// unchanged (PUR-0007); the lot's display id is the same number
/// (LOT-0007, see [lotId]) so nothing that already references a purchase
/// id (goats, finance entries) needs to change.
///
/// Goats stay anonymous in the lot until they need an individual
/// identity. The lot tracks quantities, not goat documents:
///
///   supplierQty = totalGoats - soldFromSupplierQty - (receivedAliveQty + mortality)
///   farmQty     = receivedAliveQty - soldFromFarmQty - registeredCount
///
/// * Receiving moves goats supplier -> farm. Goats sold while still at
///   the supplier are never received later, so they can't be counted
///   twice.
/// * [registeredCount] (existing field) now means "moved out of the lot
///   into individual goat records" — i.e. transferred to Own Palai /
///   Customer Palai (or registered under the legacy flow).
/// * Booking / Wait-for-Delivery sales only ever draw on farm stock;
///   [reservedFarmQty] holds goats promised to a customer but not yet
///   handed over.
///
/// Supplier payments live in `tradingPurchases/{id}/payments`; receiving
/// events in `tradingPurchases/{id}/receivings`. [paidAmount] is the sum
/// of the payments, maintained transactionally by TradingService.
///
/// Older (goat-first) purchases have lotSchema == 0 until
/// TradingService.convertLegacyPurchasesToLots() upgrades them in place.
class TradingPurchase {
  final String id;

  // -----------------------------------------------------------------------
  // SELLER DETAILS
  // -----------------------------------------------------------------------

  final String sellerName;
  final String mobile;
  final String market;
  final String vehicleNumber;
  final DateTime purchaseDate;

  // -----------------------------------------------------------------------
  // PURCHASE DETAILS
  // -----------------------------------------------------------------------

  final int totalGoats;
  final double totalWeightAtPurchase;
  final double pricePerKg;
  final double purchaseAmount;

  /// Gender split of [totalGoats], captured at purchase time (Step 2 —
  /// Purchase Details) rather than during individual Goat Registration.
  /// 0 / 0 on older records saved before this existed.
  final int maleGoats;
  final int femaleGoats;

  /// How many of [maleGoats] / [femaleGoats] have already been assigned to
  /// a registered goat. Kept in sync by GoatService.registerGoat(), which
  /// uses the difference (maleGoats - maleRegistered, femaleGoats -
  /// femaleRegistered) to decide each newly-registered goat's gender
  /// automatically, so Goat Registration never has to ask for it again.
  /// 0 / 0 on older records, and on purchases with no gender split (0 / 0
  /// maleGoats / femaleGoats) — those goats are registered with gender ''.
  final int maleRegistered;
  final int femaleRegistered;

  /// Trading purchase payment method.
  ///
  /// Only:
  /// - Cash
  /// - Online
  final String paymentMethod;

  // -----------------------------------------------------------------------
  // RECEIVING DETAILS
  // -----------------------------------------------------------------------

  /// 'pending' or 'completed'
  final String receivingStatus;

  final DateTime? dateReceivedAtFarm;
  final double? totalWeightAfterArrival;
  final double? weightLoss;
  final int mortality;
  final String remarks;

  // -----------------------------------------------------------------------
  // TRANSPORT / OTHER PURCHASE EXPENSES
  // -----------------------------------------------------------------------

  final double transportCost;
  final double loadingCharges;
  final double unloadingCharges;
  final double otherExpenses;

  final double totalTransportExpenses;

  // -----------------------------------------------------------------------
  // TOTALS
  // -----------------------------------------------------------------------

  final double grandTotal;
  final double effectiveCostPerKg;

  // -----------------------------------------------------------------------
  // GOAT REGISTRATION STATUS
  // -----------------------------------------------------------------------

  /// Goats moved out of the lot into individual goat records (Own Palai /
  /// Customer Palai transfers, or legacy registration).
  final int registeredCount;

  /// Legacy "waiting to be registered" counter. For lots this equals
  /// [farmQty]; kept only so the old registration screens keep working
  /// until they are retired.
  final int pendingCount;

  // -----------------------------------------------------------------------
  // LOT FIELDS
  // -----------------------------------------------------------------------

  /// 0 = legacy goat-first purchase (not yet converted), 1 = lot.
  final int lotSchema;

  final DateTime? expectedDeliveryDate;

  /// Goats that have physically arrived at the farm alive, summed across
  /// every receiving event. (Goats that died on arrival are [mortality].)
  final int receivedAliveQty;

  /// Of [mortality], how many died AT THE FARM after arriving (Record
  /// Death). Display-only: the counter maths never reads it. Recording such
  /// a death moves one goat from [receivedAliveQty] to [mortality], so
  /// "received alive" = receivedAliveQty + farmDeathQty and "died in
  /// transit" = mortality - farmDeathQty.
  final int farmDeathQty;

  /// Goats sold directly from the lot while still at the supplier.
  final int soldFromSupplierQty;

  /// Goats sold directly from the lot after arriving at the farm.
  final int soldFromFarmQty;

  /// Farm goats promised to a customer (Booking / Wait-for-Delivery) but
  /// not yet handed over. Still physically at the farm, but not
  /// available for a new sale.
  final int reservedFarmQty;

  /// Sum of all supplier payments recorded for this lot.
  final double paidAmount;

  // -----------------------------------------------------------------------
  // DEAL CANCELLED (goats never left the supplier)
  // -----------------------------------------------------------------------

  /// True once the deal was cancelled while every goat was still at the
  /// supplier. A cancelled lot owns no goats, owes the supplier nothing and
  /// is shown under Completed. Written only by
  /// TradingService.cancelLotDeal().
  final bool dealCancelled;

  /// Date the deal was cancelled.
  final DateTime? cancelledAt;

  /// What had been paid to the supplier when the deal was cancelled.
  final double cancelPaidAmount;

  /// What the supplier handed back.
  final double cancelRefundAmount;

  /// Paid minus refunded: the money the farm lost because of the
  /// cancellation.
  final double cancelLossAmount;

  final String cancelNote;

  final DateTime? createdAt;

  const TradingPurchase({
    required this.id,

    required this.sellerName,
    required this.mobile,
    required this.market,
    required this.vehicleNumber,
    required this.purchaseDate,

    required this.totalGoats,
    required this.totalWeightAtPurchase,
    required this.pricePerKg,
    required this.purchaseAmount,
    this.maleGoats = 0,
    this.femaleGoats = 0,
    this.maleRegistered = 0,
    this.femaleRegistered = 0,
    required this.paymentMethod,

    required this.receivingStatus,
    this.dateReceivedAtFarm,
    this.totalWeightAfterArrival,
    this.weightLoss,
    required this.mortality,
    required this.remarks,

    required this.transportCost,
    required this.loadingCharges,
    required this.unloadingCharges,
    required this.otherExpenses,
    required this.totalTransportExpenses,

    required this.grandTotal,
    required this.effectiveCostPerKg,

    required this.registeredCount,
    required this.pendingCount,

    this.lotSchema = 0,
    this.expectedDeliveryDate,
    this.receivedAliveQty = 0,
    this.farmDeathQty = 0,
    this.soldFromSupplierQty = 0,
    this.soldFromFarmQty = 0,
    this.reservedFarmQty = 0,
    this.paidAmount = 0,

    this.dealCancelled = false,
    this.cancelledAt,
    this.cancelPaidAmount = 0,
    this.cancelRefundAmount = 0,
    this.cancelLossAmount = 0,
    this.cancelNote = '',

    this.createdAt,
  });

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------

  bool get isReceivingPending =>
      receivingStatus.trim().toLowerCase() == 'pending';

  bool get isReceivingCompleted =>
      receivingStatus.trim().toLowerCase() == 'completed';

  // ---- Lot helpers (meaningful when [isLot]) ----------------------------

  bool get isLot => lotSchema >= 1;

  /// Display id: PUR-0007 -> LOT-0007.
  String get lotId {
    final dash = id.indexOf('-');
    return dash < 0 ? id : 'LOT-${id.substring(dash + 1)}';
  }

  /// Goats already accounted for at receiving (arrived alive + died).
  int get receivedTotalQty => receivedAliveQty + mortality;

  /// Goats that arrived alive, counting ones that later died at the farm.
  int get arrivedAliveQty => receivedAliveQty + farmDeathQty;

  /// Goats that died in transit only (excludes farm deaths).
  int get transitDeathQty {
    final v = mortality - farmDeathQty;
    return v < 0 ? 0 : v;
  }

  /// Goats still at the supplier and available to sell from there.
  /// A cancelled deal has none: the goats were never taken.
  int get supplierQty {
    if (dealCancelled) return 0;

    final v = totalGoats - soldFromSupplierQty - receivedTotalQty;
    return v < 0 ? 0 : v;
  }

  /// Goats at the farm still owned by the lot (includes reserved ones).
  int get farmQty {
    final v = receivedAliveQty - soldFromFarmQty - registeredCount;
    return v < 0 ? 0 : v;
  }

  /// Farm goats free for a new sale or transfer.
  int get farmAvailableQty {
    final v = farmQty - reservedFarmQty;
    return v < 0 ? 0 : v;
  }

  int get soldQty => soldFromSupplierQty + soldFromFarmQty;

  /// Goats the lot still owns (supplier + farm), reserved included.
  int get remainingQty => supplierQty + farmQty;

  /// Goats that left the lot without being sold: every death (transit and
  /// farm) plus goats moved to Own / Customer Palai as individual goats.
  /// Display-only — it never feeds a counter. For a lot,
  /// totalGoats = soldQty + [unsoldOutQty] + remainingQty, which is how the
  /// "bought • sold • remaining" line reconciles.
  int get unsoldOutQty => mortality + registeredCount;

  /// "Died 2 • Moved to Palai 1" (only the non-zero parts), or '' when
  /// nothing left the lot that way.
  String get unsoldOutLabel {
    final parts = <String>[
      if (mortality > 0) 'Died $mortality',
      if (registeredCount > 0) 'Moved to Palai $registeredCount',
    ];
    return parts.join(' • ');
  }

  /// Goats that can be sold right now, from either location.
  int get availableForSaleQty => supplierQty + farmAvailableQty;

  bool get isActive => !dealCancelled && remainingQty > 0;

  LotLocation get location {
    if (receivedTotalQty == 0) return LotLocation.atSupplier;
    if (supplierQty > 0) return LotLocation.partiallyAtFarm;
    return LotLocation.atFarm;
  }

  // Supplier payment ------------------------------------------------------

  double get dueAmount {
    // A cancelled deal owes the supplier nothing, whatever was paid.
    if (dealCancelled) return 0;

    final v = purchaseAmount - paidAmount;
    return v < 0 ? 0 : v;
  }

  /// 'Unpaid' / 'Partial' / 'Paid' — always derived from [paidAmount],
  /// never typed in.
  String get paymentStatus {
    if (dealCancelled) return 'Cancelled';
    if (paidAmount <= 0) return 'Unpaid';
    if (dueAmount < 0.01) return 'Paid';
    return 'Partial';
  }

  // Edit / cancel ----------------------------------------------------------

  /// A deal can only be cancelled while every goat is still at the supplier:
  /// nothing received, nothing sold, nothing moved or reserved.
  bool get canCancelDeal =>
      isLot &&
          !dealCancelled &&
          receivedTotalQty == 0 &&
          soldQty == 0 &&
          registeredCount == 0 &&
          reservedFarmQty == 0;

  /// Fewest goats the lot can be edited down to: the goats that already
  /// left the supplier (sold from it, or received at the farm).
  int get minEditableTotalGoats => soldFromSupplierQty + receivedTotalQty;

  // Weights ---------------------------------------------------------------

  /// What the goats received so far would have weighed at purchase
  /// (purchase weight pro-rated by quantity).
  double get expectedWeightOfReceived => totalGoats <= 0
      ? 0
      : totalWeightAtPurchase * receivedTotalQty / totalGoats;

  /// Received weight minus the pro-rated purchase weight. Negative =
  /// weight lost in transit. 0 until something has been received.
  double get receivingWeightDifference => receivedTotalQty == 0
      ? 0
      : (totalWeightAfterArrival ?? 0) - expectedWeightOfReceived;

  /// Costing rebuilt from the stored figures, using the same engine as the
  /// wizard so cost numbers shown anywhere in the app match what was
  /// calculated at entry time.
  PurchaseCosting get costing => PurchaseCosting(
    totalGoats: totalGoats,
    weightAtPurchase: totalWeightAtPurchase,
    pricePerKg: pricePerKg,
    weightAfterArrival: totalWeightAfterArrival ?? 0,
    mortality: mortality,
    transportCost: transportCost,
    loadingCharges: loadingCharges,
    unloadingCharges: unloadingCharges,
    otherExpenses: otherExpenses,
  );

  /// Goats that arrived alive (totalGoats - mortality). This is how many
  /// goats can actually be registered.
  int get survivingGoats => costing.survivingGoats;

  /// Grand Total / surviving goats. 0 until receiving is completed.
  double get costPerSurvivingGoat => costing.costPerSurvivingGoat;

  /// Cost of ONE goat of this lot, used as the cost basis of a sale.
  ///
  /// Before every goat is accounted for, arrivals and losses are not final,
  /// so the cost is spread over all purchased goats:
  ///   (purchase amount + expenses so far) / total goats.
  /// Once receiving is completed it switches to the survivor-based figure
  /// (grand total / goats that did not die), which carries the cost of any
  /// goats lost in transit onto the survivors.
  ///
  /// A sale snapshots this at sale time, so it never changes afterwards.
  double get lotCostPerGoat {
    if (totalGoats <= 0) return 0;

    if (isReceivingCompleted && costPerSurvivingGoat > 0) {
      return PurchaseCosting.round2(costPerSurvivingGoat);
    }

    return PurchaseCosting.round2(
      (costing.purchaseAmount + costing.totalExpenses) / totalGoats,
    );
  }

  /// Purchase value of goats lost in transit (already inside grandTotal).
  double get mortalityLoss => costing.mortalityLoss;

  // -----------------------------------------------------------------------
  // FIRESTORE
  // -----------------------------------------------------------------------

  factory TradingPurchase.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    DateTime? nullableDateFrom(String key) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return null;
    }

    DateTime dateFrom(String key) {
      return nullableDateFrom(key) ?? DateTime.now();
    }

    double numFrom(String key) {
      final value = data[key];

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    double? nullableNumFrom(String key) {
      final value = data[key];

      if (value == null) {
        return null;
      }

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value.toString());
    }

    int intFrom(String key) {
      final value = data[key];

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return TradingPurchase(
      id: doc.id,

      sellerName: (data['sellerName'] ?? '').toString(),
      mobile: (data['mobile'] ?? '').toString(),
      market: (data['market'] ?? '').toString(),
      vehicleNumber: (data['vehicleNumber'] ?? '').toString(),
      purchaseDate: dateFrom('purchaseDate'),

      totalGoats: intFrom('totalGoats'),
      totalWeightAtPurchase: numFrom('totalWeightAtPurchase'),
      pricePerKg: numFrom('pricePerKg'),
      purchaseAmount: numFrom('purchaseAmount'),

      // Absent on purchases saved before the gender split existed.
      maleGoats: intFrom('maleGoats'),
      femaleGoats: intFrom('femaleGoats'),

      // Absent on purchases saved before auto gender assignment existed.
      maleRegistered: intFrom('maleRegistered'),
      femaleRegistered: intFrom('femaleRegistered'),

      // Backward-safe default.
      paymentMethod: _normalisePaymentMethod(
        (data['paymentMethod'] ?? 'Cash').toString(),
      ),

      // Old records did not have this field.
      // Such records are treated as completed only if receiving data exists.
      receivingStatus: _normaliseReceivingStatus(data),

      dateReceivedAtFarm: nullableDateFrom('dateReceivedAtFarm'),
      totalWeightAfterArrival:
      nullableNumFrom('totalWeightAfterArrival'),
      weightLoss: nullableNumFrom('weightLoss'),

      mortality: intFrom('mortality'),
      remarks: (data['remarks'] ?? '').toString(),

      transportCost: numFrom('transportCost'),
      loadingCharges: numFrom('loadingCharges'),
      unloadingCharges: numFrom('unloadingCharges'),
      otherExpenses: numFrom('otherExpenses'),

      totalTransportExpenses: numFrom('totalTransportExpenses'),

      grandTotal: numFrom('grandTotal'),
      effectiveCostPerKg: numFrom('effectiveCostPerKg'),

      registeredCount: intFrom('registeredCount'),
      pendingCount: intFrom('pendingCount'),

      lotSchema: intFrom('lotSchema'),
      expectedDeliveryDate: nullableDateFrom('expectedDeliveryDate'),
      receivedAliveQty: intFrom('receivedAliveQty'),
      farmDeathQty: intFrom('farmDeathQty'),
      soldFromSupplierQty: intFrom('soldFromSupplierQty'),
      soldFromFarmQty: intFrom('soldFromFarmQty'),
      reservedFarmQty: intFrom('reservedFarmQty'),
      paidAmount: numFrom('paidAmount'),

      dealCancelled: data['dealCancelled'] == true,
      cancelledAt: nullableDateFrom('cancelledAt'),
      cancelPaidAmount: numFrom('cancelPaidAmount'),
      cancelRefundAmount: numFrom('cancelRefundAmount'),
      cancelLossAmount: numFrom('cancelLossAmount'),
      cancelNote: (data['cancelNote'] ?? '').toString(),

      createdAt: nullableDateFrom('createdAt'),
    );
  }

  /// Does not write createdAt.
  ///
  /// The service adds:
  /// FieldValue.serverTimestamp()
  ///
  /// This keeps server timestamps consistent with the rest of the app.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'sellerName': sellerName.trim(),
      'mobile': mobile.trim(),
      'market': market.trim(),
      'vehicleNumber': vehicleNumber.trim(),
      'purchaseDate': Timestamp.fromDate(purchaseDate),

      'totalGoats': totalGoats,
      'totalWeightAtPurchase': totalWeightAtPurchase,
      'pricePerKg': pricePerKg,
      'purchaseAmount': purchaseAmount,
      'maleGoats': maleGoats,
      'femaleGoats': femaleGoats,
      'maleRegistered': maleRegistered,
      'femaleRegistered': femaleRegistered,

      'paymentMethod': _normalisePaymentMethod(paymentMethod),

      'receivingStatus': _normaliseReceivingStatusValue(receivingStatus),

      'mortality': mortality,
      'remarks': remarks.trim(),

      'transportCost': transportCost,
      'loadingCharges': loadingCharges,
      'unloadingCharges': unloadingCharges,
      'otherExpenses': otherExpenses,

      'totalTransportExpenses': totalTransportExpenses,

      'grandTotal': grandTotal,
      'effectiveCostPerKg': effectiveCostPerKg,

      'registeredCount': registeredCount,
      'pendingCount': pendingCount,

      'lotSchema': lotSchema,
      'receivedAliveQty': receivedAliveQty,
      'farmDeathQty': farmDeathQty,
      'soldFromSupplierQty': soldFromSupplierQty,
      'soldFromFarmQty': soldFromFarmQty,
      'reservedFarmQty': reservedFarmQty,
      'paidAmount': paidAmount,
    };

    if (expectedDeliveryDate != null) {
      map['expectedDeliveryDate'] =
          Timestamp.fromDate(expectedDeliveryDate!);
    }

    if (dateReceivedAtFarm != null) {
      map['dateReceivedAtFarm'] =
          Timestamp.fromDate(dateReceivedAtFarm!);
    }

    if (totalWeightAfterArrival != null) {
      map['totalWeightAfterArrival'] = totalWeightAfterArrival;
    }

    if (weightLoss != null) {
      map['weightLoss'] = weightLoss;
    }

    return map;
  }

  // -----------------------------------------------------------------------
  // NORMALISATION
  // -----------------------------------------------------------------------

  static String _normalisePaymentMethod(String value) {
    final method = value.trim().toLowerCase();

    if (method == 'online') {
      return 'Online';
    }

    // Trading purchases intentionally default to Cash.
    //
    // This also protects older / malformed records from introducing
    // additional payment methods into the new Trading UI.
    return 'Cash';
  }

  static String _normaliseReceivingStatus(Map<String, dynamic> data) {
    final explicit = data['receivingStatus'];

    if (explicit != null) {
      return _normaliseReceivingStatusValue(explicit.toString());
    }

    // Backward compatibility for purchases created before receivingStatus
    // existed.
    final hasReceivingDate = data['dateReceivedAtFarm'] is Timestamp;
    final hasReceivingWeight =
        data['totalWeightAfterArrival'] != null;

    if (hasReceivingDate || hasReceivingWeight) {
      return 'completed';
    }

    return 'pending';
  }

  static String _normaliseReceivingStatusValue(String value) {
    return value.trim().toLowerCase() == 'completed'
        ? 'completed'
        : 'pending';
  }
}