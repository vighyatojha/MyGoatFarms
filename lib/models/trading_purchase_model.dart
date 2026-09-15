import 'package:cloud_firestore/cloud_firestore.dart';

/// One wholesale goat purchase, saved at the end of the Purchase Goats
/// wizard (see PurchaseDraft in trading_purchase_draft.dart, added in
/// Task 3.1).
///
/// Lives at `farms/{farmId}/tradingPurchases/{purchaseId}` — nested
/// under the farm, matching every other module's collection layout
/// (expenses, transactions, bills, ... all live the same way under
/// FinanceService/FirestoreService) rather than the flat top-level
/// `trading_purchases/{purchaseId}` the phase-1 plan sketched, which
/// would sit outside the farm-scoped security-rule pattern the rest of
/// the app already uses.
///
/// The "(calculated)" fields called out in the phase-1 plan
/// (purchaseAmount, weightLoss, totalTransportExpenses, grandTotal,
/// effectiveCostPerKg) are computed once in the wizard and stored
/// here as plain fields — not re-derived on every read — so the
/// dashboard, purchase list, and success screen never need the raw
/// inputs just to show a total.
class TradingPurchase {
  final String id; // e.g. 'PUR-0001'

  // --- Seller info ---
  final String sellerName;
  final String mobile;
  final String market;
  final String vehicleNumber;
  final DateTime purchaseDate;

  // --- Purchase details ---
  final String breed;
  final int totalGoats;
  final double totalWeightAtPurchase;
  final double pricePerKg;
  final double purchaseAmount; // calculated: totalWeightAtPurchase * pricePerKg

  // --- Receiving ---
  final DateTime dateReceivedAtFarm;
  final double totalWeightAfterArrival;
  final double weightLoss; // calculated: totalWeightAtPurchase - totalWeightAfterArrival
  final int mortality;
  final String remarks;

  // --- Transport ---
  final double transportCost;
  final double loadingCharges;
  final double unloadingCharges;
  final double otherExpenses;
  final double totalTransportExpenses; // calculated: sum of the four above

  // --- Derived totals ---
  final double grandTotal; // calculated: purchaseAmount + totalTransportExpenses
  final double effectiveCostPerKg; // calculated: grandTotal / totalWeightAfterArrival (0 if weight is 0)

  // --- Status tracking ---
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
    required this.breed,
    required this.totalGoats,
    required this.totalWeightAtPurchase,
    required this.pricePerKg,
    required this.purchaseAmount,
    required this.dateReceivedAtFarm,
    required this.totalWeightAfterArrival,
    required this.weightLoss,
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

  factory TradingPurchase.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    DateTime dateFrom(String key) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    double numFrom(String key) => (data[key] as num?)?.toDouble() ?? 0;
    int intFrom(String key) => (data[key] as num?)?.toInt() ?? 0;

    return TradingPurchase(
      id: doc.id,
      sellerName: data['sellerName'] ?? '',
      mobile: data['mobile'] ?? '',
      market: data['market'] ?? '',
      vehicleNumber: data['vehicleNumber'] ?? '',
      purchaseDate: dateFrom('purchaseDate'),
      breed: data['breed'] ?? '',
      totalGoats: intFrom('totalGoats'),
      totalWeightAtPurchase: numFrom('totalWeightAtPurchase'),
      pricePerKg: numFrom('pricePerKg'),
      purchaseAmount: numFrom('purchaseAmount'),
      dateReceivedAtFarm: dateFrom('dateReceivedAtFarm'),
      totalWeightAfterArrival: numFrom('totalWeightAfterArrival'),
      weightLoss: numFrom('weightLoss'),
      mortality: intFrom('mortality'),
      remarks: data['remarks'] ?? '',
      transportCost: numFrom('transportCost'),
      loadingCharges: numFrom('loadingCharges'),
      unloadingCharges: numFrom('unloadingCharges'),
      otherExpenses: numFrom('otherExpenses'),
      totalTransportExpenses: numFrom('totalTransportExpenses'),
      grandTotal: numFrom('grandTotal'),
      effectiveCostPerKg: numFrom('effectiveCostPerKg'),
      registeredCount: intFrom('registeredCount'),
      pendingCount: intFrom('pendingCount'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Does NOT include `createdAt` — callers write that separately as
  /// `FieldValue.serverTimestamp()` at save time (see stock/expense
  /// models for the same split).
  Map<String, dynamic> toMap() {
    return {
      'sellerName': sellerName,
      'mobile': mobile,
      'market': market,
      'vehicleNumber': vehicleNumber,
      'purchaseDate': Timestamp.fromDate(purchaseDate),
      'breed': breed,
      'totalGoats': totalGoats,
      'totalWeightAtPurchase': totalWeightAtPurchase,
      'pricePerKg': pricePerKg,
      'purchaseAmount': purchaseAmount,
      'dateReceivedAtFarm': Timestamp.fromDate(dateReceivedAtFarm),
      'totalWeightAfterArrival': totalWeightAfterArrival,
      'weightLoss': weightLoss,
      'mortality': mortality,
      'remarks': remarks,
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
  }
}