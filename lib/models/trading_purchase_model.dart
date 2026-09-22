import 'package:cloud_firestore/cloud_firestore.dart';

import 'purchase_costing.dart';

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

  final int registeredCount;
  final int pendingCount;

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

    this.createdAt,
  });

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------

  bool get isReceivingPending =>
      receivingStatus.trim().toLowerCase() == 'pending';

  bool get isReceivingCompleted =>
      receivingStatus.trim().toLowerCase() == 'completed';

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
    };

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