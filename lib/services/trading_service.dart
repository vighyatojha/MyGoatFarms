import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trading_purchase_model.dart';
import '../models/trading_summary_model.dart';

/// Handles the Trading module: wholesale purchases and the Trading
/// Dashboard summary.
///
/// A separate service file rather than more additions to
/// `firestore_service.dart`, following the same precedent
/// [MonthlyBillingService] and `FinanceService` already set.
///
/// Collection layout (nested under the farm, matching every other
/// module — see FinanceService's `_expenses`/`_transactions`/etc.):
///   farms/{farmId}/tradingPurchases/{purchaseId}
///   farms/{farmId}/tradingCounters/purchaseCounter   (single doc)
///   farms/{farmId}/tradingSummary/dashboard           (single doc)
///
/// `tradingSummary/dashboard` is written by a Cloud Function trigger on
/// `tradingPurchases` writes (see functions/index.js), not by this
/// service — Task 1.3 chose the trigger over a client-side batched
/// update so the aggregate stays correct even if a client write fails
/// partway or two clients write at once. This service only *reads* it.
class TradingService {
  TradingService._();

  static final TradingService instance = TradingService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------
  // COLLECTIONS
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() =>
      _db.collection('farms');

  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) =>
      _farms().doc(farmId).collection('tradingPurchases');

  DocumentReference<Map<String, dynamic>> _purchaseCounterDoc(
      String farmId,
      ) =>
      _farms()
          .doc(farmId)
          .collection('tradingCounters')
          .doc('purchaseCounter');

  DocumentReference<Map<String, dynamic>> _summaryDoc(String farmId) =>
      _farms().doc(farmId).collection('tradingSummary').doc('dashboard');

  // ---------------------------------------------------------------------
  // DASHBOARD
  // ---------------------------------------------------------------------

  /// Streams the 7 dashboard numbers. Phase 1 only populates
  /// wholesalePurchased/pendingRegistrations — the rest read as 0 until
  /// later phases (Registration, Stock, Own Palai, Sale) start writing
  /// them, rather than faking data in the meantime.
  Stream<TradingSummary> dashboardSummaryStream(String farmId) {
    return _summaryDoc(farmId)
        .snapshots()
        .map((doc) => TradingSummary.fromDoc(doc));
  }

  // ---------------------------------------------------------------------
  // PURCHASES
  // ---------------------------------------------------------------------

  Stream<List<TradingPurchase>> purchasesStream(String farmId) {
    return _tradingPurchases(farmId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map((doc) => TradingPurchase.fromDoc(doc))
          .toList(),
    );
  }

  Future<TradingPurchase?> getPurchase(String farmId, String purchaseId) async {
    final doc = await _tradingPurchases(farmId).doc(purchaseId).get().timeout(_timeout);
    if (!doc.exists) return null;
    return TradingPurchase.fromDoc(doc);
  }

  /// Saves a new purchase, generating its sequential `PUR-0001`-style id
  /// in the same transaction as the purchase write — this is what Task
  /// 3.6 (Save Purchase) calls once the 4-step wizard's shared
  /// `PurchaseDraft` is complete.
  ///
  /// A single Firestore transaction (not a plain read-then-write) is
  /// required here: two purchases saved at nearly the same time must
  /// never be able to read the same counter value and collide on the
  /// same id.
  ///
  /// `registeredCount` starts at 0 and `pendingCount` starts at
  /// `totalGoats` — later phases (Goat Registration) will move goats
  /// from pending to registered on this same doc.
  Future<TradingPurchase> savePurchase({
    required String farmId,
    required String sellerName,
    required String mobile,
    required String market,
    required String vehicleNumber,
    required DateTime purchaseDate,
    required String breed,
    required int totalGoats,
    required double totalWeightAtPurchase,
    required double pricePerKg,
    required DateTime dateReceivedAtFarm,
    required double totalWeightAfterArrival,
    required int mortality,
    required String remarks,
    required double transportCost,
    required double loadingCharges,
    required double unloadingCharges,
    required double otherExpenses,
  }) async {
    final purchaseAmount = totalWeightAtPurchase * pricePerKg;
    final weightLoss = totalWeightAtPurchase - totalWeightAfterArrival;
    final totalTransportExpenses =
        transportCost + loadingCharges + unloadingCharges + otherExpenses;
    final grandTotal = purchaseAmount + totalTransportExpenses;

    // Guard against divide-by-zero (Section 5 note) if weight after
    // arrival wasn't entered / arrived at zero.
    final effectiveCostPerKg =
    totalWeightAfterArrival > 0 ? grandTotal / totalWeightAfterArrival : 0.0;

    final counterRef = _purchaseCounterDoc(farmId);

    final purchaseId = await _db.runTransaction<String>((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final lastValue = (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;
      final nextValue = lastValue + 1;
      final id = 'PUR-${nextValue.toString().padLeft(4, '0')}';

      transaction.set(
        counterRef,
        {'lastValue': nextValue},
        SetOptions(merge: true),
      );

      final purchase = TradingPurchase(
        id: id,
        sellerName: sellerName.trim(),
        mobile: mobile.trim(),
        market: market.trim(),
        vehicleNumber: vehicleNumber.trim(),
        purchaseDate: purchaseDate,
        breed: breed.trim(),
        totalGoats: totalGoats,
        totalWeightAtPurchase: totalWeightAtPurchase,
        pricePerKg: pricePerKg,
        purchaseAmount: purchaseAmount,
        dateReceivedAtFarm: dateReceivedAtFarm,
        totalWeightAfterArrival: totalWeightAfterArrival,
        weightLoss: weightLoss,
        mortality: mortality,
        remarks: remarks.trim(),
        transportCost: transportCost,
        loadingCharges: loadingCharges,
        unloadingCharges: unloadingCharges,
        otherExpenses: otherExpenses,
        totalTransportExpenses: totalTransportExpenses,
        grandTotal: grandTotal,
        effectiveCostPerKg: effectiveCostPerKg,
        registeredCount: 0,
        pendingCount: totalGoats,
      );

      transaction.set(_tradingPurchases(farmId).doc(id), {
        ...purchase.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      return id;
    }).timeout(_timeout);

    // Re-read so the returned model carries the server-resolved
    // createdAt timestamp (the transaction above only has the sentinel
    // FieldValue, not an actual DateTime, at the point it returns).
    final saved = await getPurchase(farmId, purchaseId);
    if (saved == null) {
      throw StateError('Purchase $purchaseId was written but could not be read back.');
    }
    return saved;
  }
}