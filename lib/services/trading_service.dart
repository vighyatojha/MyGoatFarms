import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity_model.dart';
import '../models/expense_categories.dart';
import '../models/expense_model.dart';
import '../models/trading_purchase_model.dart';
import '../models/trading_summary_model.dart';
import 'firestore_service.dart';
import 'finance_service.dart';

/// Handles the Trading module:
///
/// - Wholesale goat purchases
/// - Purchase numbering
/// - Receiving status
/// - Pending receiving records
/// - Finance expense integration
/// - Trading dashboard summary reads
///
/// Collection layout:
///
/// farms/{farmId}/tradingPurchases/{purchaseId}
/// farms/{farmId}/tradingCounters/purchaseCounter
/// farms/{farmId}/tradingSummary/dashboard
///
/// A purchase can be saved before receiving information is entered.
/// In that case:
///
/// receivingStatus = "pending"
///
/// The Trading Dashboard can then show that purchase under
/// Pending Receiving and allow the user to complete receiving later.
///
/// IMPORTANT:
/// Trading payment methods are intentionally limited to:
///
/// Cash
/// Online
class TradingService {
  TradingService._();

  static final TradingService instance = TradingService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingPurchases');
  }

  DocumentReference<Map<String, dynamic>> _purchaseCounterDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingCounters')
        .doc('purchaseCounter');
  }

  DocumentReference<Map<String, dynamic>> _summaryDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingSummary')
        .doc('dashboard');
  }

  // -----------------------------------------------------------------------
  // DASHBOARD SUMMARY
  // -----------------------------------------------------------------------

  Stream<TradingSummary> dashboardSummaryStream(
      String farmId,
      ) {
    return _summaryDoc(farmId)
        .snapshots()
        .map(
          (doc) => TradingSummary.fromDoc(doc),
    );
  }

  // -----------------------------------------------------------------------
  // ALL PURCHASES
  // -----------------------------------------------------------------------

  Stream<List<TradingPurchase>> purchasesStream(
      String farmId,
      ) {
    return _tradingPurchases(farmId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
            (doc) => TradingPurchase.fromDoc(doc),
      )
          .toList(),
    );
  }

  // -----------------------------------------------------------------------
  // PENDING RECEIVING
  // -----------------------------------------------------------------------

  /// Streams only purchases where receiving has not yet been completed.
  ///
  /// This is used by the Trading Dashboard to show the
  /// "Pending Receiving" section.
  Stream<List<TradingPurchase>> pendingReceivingStream(
      String farmId,
      ) {
    return _tradingPurchases(farmId)
        .where(
      'receivingStatus',
      isEqualTo: 'pending',
    )
        .snapshots()
        .map(
          (snapshot) {
        final purchases = snapshot.docs
            .map(
              (doc) => TradingPurchase.fromDoc(doc),
        )
            .toList();

        purchases.sort(
              (a, b) => (b.createdAt ?? DateTime(2000))
              .compareTo(
            a.createdAt ?? DateTime(2000),
          ),
        );

        return purchases;
      },
    );
  }

  // -----------------------------------------------------------------------
  // GET PURCHASE
  // -----------------------------------------------------------------------

  Future<TradingPurchase?> getPurchase(
      String farmId,
      String purchaseId,
      ) async {
    final doc = await _tradingPurchases(farmId)
        .doc(purchaseId)
        .get()
        .timeout(_timeout);

    if (!doc.exists) {
      return null;
    }

    return TradingPurchase.fromDoc(doc);
  }

  // -----------------------------------------------------------------------
  // SAVE PURCHASE
  // -----------------------------------------------------------------------

  /// Saves a new Trading purchase.
  ///
  /// Receiving information is optional.
  ///
  /// If [receivingStatus] is "pending":
  ///
  /// - Purchase is saved immediately.
  /// - No receiving fields are required.
  /// - Dashboard can show the purchase as pending.
  ///
  /// If [receivingStatus] is "completed":
  ///
  /// - Receiving fields are saved with the purchase.
  ///
  /// A Finance expense is also created for the goat purchase amount.
  ///
  /// Payment method is restricted to:
  ///
  /// Cash
  /// Online
  Future<TradingPurchase> savePurchase({
    required String farmId,

    // Seller details
    required String sellerName,
    required String mobile,
    required String market,
    required String vehicleNumber,
    required DateTime purchaseDate,

    // Purchase details
    required int totalGoats,
    required double totalWeightAtPurchase,
    required double pricePerKg,

    // Payment
    required String paymentMethod,

    // Receiving
    String receivingStatus = 'pending',
    DateTime? dateReceivedAtFarm,
    double? totalWeightAfterArrival,
    int mortality = 0,
    String remarks = '',

    // Transport / additional costs
    double transportCost = 0,
    double loadingCharges = 0,
    double unloadingCharges = 0,
    double otherExpenses = 0,
  }) async {
    final normalizedPaymentMethod =
    _normalizePaymentMethod(paymentMethod);

    final normalizedReceivingStatus =
    _normalizeReceivingStatus(receivingStatus);

    if (sellerName.trim().isEmpty) {
      throw ArgumentError('Seller name is required.');
    }

    if (totalGoats <= 0) {
      throw ArgumentError('Total goats must be greater than zero.');
    }

    if (totalWeightAtPurchase <= 0) {
      throw ArgumentError(
        'Purchase weight must be greater than zero.',
      );
    }

    if (pricePerKg <= 0) {
      throw ArgumentError(
        'Price per kg must be greater than zero.',
      );
    }

    if (normalizedReceivingStatus == 'completed') {
      if (dateReceivedAtFarm == null) {
        throw ArgumentError(
          'Receiving date is required when receiving is completed.',
        );
      }

      if (totalWeightAfterArrival == null ||
          totalWeightAfterArrival <= 0) {
        throw ArgumentError(
          'Arrival weight is required when receiving is completed.',
        );
      }
    }

    if (mortality < 0) {
      throw ArgumentError(
        'Mortality cannot be negative.',
      );
    }

    if (mortality > totalGoats) {
      throw ArgumentError(
        'Mortality cannot be greater than total goats.',
      );
    }

    // ---------------------------------------------------------------------
    // CALCULATIONS
    // ---------------------------------------------------------------------

    final purchaseAmount =
        totalWeightAtPurchase * pricePerKg;

    final safeArrivalWeight =
        totalWeightAfterArrival ?? 0;

    final weightLoss =
    normalizedReceivingStatus == 'completed'
        ? totalWeightAtPurchase - safeArrivalWeight
        : null;

    final totalTransportExpenses =
        transportCost +
            loadingCharges +
            unloadingCharges +
            otherExpenses;

    final grandTotal =
        purchaseAmount + totalTransportExpenses;

    final effectiveCostPerKg =
    safeArrivalWeight > 0
        ? grandTotal / safeArrivalWeight
        : 0.0;

    // ---------------------------------------------------------------------
    // CREATE SEQUENTIAL PURCHASE ID
    // ---------------------------------------------------------------------

    final counterRef = _purchaseCounterDoc(farmId);

    final purchaseId =
    await _db.runTransaction<String>(
          (transaction) async {
        final counterSnap =
        await transaction.get(counterRef);

        final lastValue =
            (counterSnap.data()?['lastValue'] as num?)
                ?.toInt() ??
                0;

        final nextValue = lastValue + 1;

        final id =
            'PUR-${nextValue.toString().padLeft(4, '0')}';

        transaction.set(
          counterRef,
          {
            'lastValue': nextValue,
          },
          SetOptions(merge: true),
        );

        final purchase =
        TradingPurchase(
          id: id,

          sellerName: sellerName.trim(),
          mobile: mobile.trim(),
          market: market.trim(),
          vehicleNumber: vehicleNumber.trim(),
          purchaseDate: purchaseDate,

          totalGoats: totalGoats,
          totalWeightAtPurchase:
          totalWeightAtPurchase,
          pricePerKg: pricePerKg,
          purchaseAmount: purchaseAmount,

          paymentMethod: normalizedPaymentMethod,

          receivingStatus:
          normalizedReceivingStatus,

          dateReceivedAtFarm:
          normalizedReceivingStatus == 'completed'
              ? dateReceivedAtFarm
              : null,

          totalWeightAfterArrival:
          normalizedReceivingStatus == 'completed'
              ? safeArrivalWeight
              : null,

          weightLoss: weightLoss,

          mortality: mortality,
          remarks: remarks.trim(),

          transportCost: transportCost,
          loadingCharges: loadingCharges,
          unloadingCharges: unloadingCharges,
          otherExpenses: otherExpenses,

          totalTransportExpenses:
          totalTransportExpenses,

          grandTotal: grandTotal,

          effectiveCostPerKg:
          effectiveCostPerKg,

          registeredCount: 0,

          pendingCount: totalGoats,
        );

        transaction.set(
          _tradingPurchases(farmId).doc(id),
          {
            ...purchase.toMap(),
            'createdAt':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------
        // DASHBOARD SUMMARY
        // -------------------------------------------------------------
        //
        // Without this, farms/{farmId}/tradingSummary/dashboard never
        // gets written to by a purchase, so the dashboard's stat grid
        // (Total Stock, Wholesale Purchased, Pending Registrations,
        // etc.) stays at whatever it was initialized to — even after
        // saving new purchases.
        //
        // Wholesale Purchased counts every goat bought through
        // Trading, regardless of receiving status. Total Stock and
        // Pending Registrations only count goats once receiving is
        // confirmed (mortality already subtracted), since goats still
        // in transit aren't on-farm stock yet — see completeReceiving()
        // for the equivalent update once "Later" receiving finishes.
        final survivingGoatsAtCreation =
        normalizedReceivingStatus == 'completed'
            ? totalGoats - mortality
            : 0;

        transaction.set(
          _summaryDoc(farmId),
          {
            'wholesalePurchased':
            FieldValue.increment(totalGoats),
            if (survivingGoatsAtCreation > 0) ...{
              'totalStock': FieldValue.increment(
                survivingGoatsAtCreation,
              ),
              'pendingRegistrations': FieldValue.increment(
                survivingGoatsAtCreation,
              ),
            },
          },
          SetOptions(merge: true),
        );

        return id;
      },
    ).timeout(_timeout);

    // ---------------------------------------------------------------------
    // READ SAVED PURCHASE
    // ---------------------------------------------------------------------

    final saved =
    await getPurchase(
      farmId,
      purchaseId,
    );

    if (saved == null) {
      throw StateError(
        'Purchase $purchaseId was written but could not be read back.',
      );
    }

    // ---------------------------------------------------------------------
    // FINANCE EXPENSE
    // ---------------------------------------------------------------------
    //
    // Only the actual goat purchase amount is recorded as:
    //
    // Expense Category = Goat Purchase
    //
    // Transport/loading/unloading/other expenses remain part of the
    // Trading purchase totals and can be separately handled later if
    // the Finance design requires that.
    //
    // The referenceType/referenceId pair prevents the same purchase
    // from creating duplicate Finance expenses.

    await _ensurePurchaseFinanceExpense(
      farmId: farmId,
      purchase: saved,
    );

    return saved;
  }

  // -----------------------------------------------------------------------
  // FINANCE INTEGRATION
  // -----------------------------------------------------------------------

  /// Creates the Finance expense associated with a Trading purchase.
  ///
  /// A purchase is linked through:
  ///
  /// referenceType = tradingPurchase
  /// referenceId   = PUR-0001
  ///
  /// Before creating a new expense, existing expenses are checked so
  /// repeated calls can never create duplicate goat-purchase expenses.
  Future<void> _ensurePurchaseFinanceExpense({
    required String farmId,
    required TradingPurchase purchase,
  }) async {
    final existingSnapshot = await _db
        .collection('farms')
        .doc(farmId)
        .collection('expenses')
        .where(
      'referenceType',
      isEqualTo: 'tradingPurchase',
    )
        .where(
      'referenceId',
      isEqualTo: purchase.id,
    )
        .limit(1)
        .get()
        .timeout(_timeout);

    if (existingSnapshot.docs.isNotEmpty) {
      return;
    }

    final now = DateTime.now();

    final expense = ExpenseModel(
      id: '',
      title: 'Goat Purchase',
      category: ExpenseCategories.goatPurchase,
      amount: purchase.purchaseAmount,
      supplierName: purchase.sellerName,
      paymentMethod:
      _normalizePaymentMethod(
        purchase.paymentMethod,
      ),
      note:
      'Trading purchase ${purchase.id}',
      date: purchase.purchaseDate,
      createdAt: now,
      updatedAt: now,
      status: 'active',
      referenceType: 'tradingPurchase',
      referenceId: purchase.id,
    );

    await FinanceService.instance.addExpense(
      farmId,
      expense,
    );
  }

  // -----------------------------------------------------------------------
  // COMPLETE RECEIVING
  // -----------------------------------------------------------------------

  /// Completes receiving for a purchase that was originally saved with
  /// "Later".
  ///
  /// This updates the existing purchase instead of creating a second
  /// purchase.
  Future<TradingPurchase> completeReceiving({
    required String farmId,
    required String purchaseId,
    required DateTime dateReceivedAtFarm,
    required double totalWeightAfterArrival,
    required int mortality,
    String remarks = '',
  }) async {
    if (totalWeightAfterArrival <= 0) {
      throw ArgumentError(
        'Arrival weight must be greater than zero.',
      );
    }

    if (mortality < 0) {
      throw ArgumentError(
        'Mortality cannot be negative.',
      );
    }

    final purchase =
    await getPurchase(
      farmId,
      purchaseId,
    );

    if (purchase == null) {
      throw StateError(
        'Purchase $purchaseId was not found.',
      );
    }

    if (mortality > purchase.totalGoats) {
      throw ArgumentError(
        'Mortality cannot be greater than total goats.',
      );
    }

    final weightLoss =
        purchase.totalWeightAtPurchase -
            totalWeightAfterArrival;

    final effectiveCostPerKg =
    totalWeightAfterArrival > 0
        ? purchase.grandTotal /
        totalWeightAfterArrival
        : 0.0;

    final batch = _db.batch();

    batch.update(
      _tradingPurchases(farmId).doc(purchaseId),
      {
        'receivingStatus': 'completed',
        'dateReceivedAtFarm':
        Timestamp.fromDate(
          dateReceivedAtFarm,
        ),
        'totalWeightAfterArrival':
        totalWeightAfterArrival,
        'weightLoss': weightLoss,
        'mortality': mortality,
        'remarks': remarks.trim(),
        'effectiveCostPerKg':
        effectiveCostPerKg,
        'updatedAt':
        FieldValue.serverTimestamp(),
      },
    );

    // These goats were NOT counted in totalStock / pendingRegistrations
    // when the purchase was first saved (see savePurchase()), because
    // receiving was still pending then. Now that receiving is
    // confirmed, add the surviving goats (mortality subtracted) to the
    // dashboard summary.
    final survivingGoats = purchase.totalGoats - mortality;

    if (survivingGoats > 0) {
      batch.set(
        _summaryDoc(farmId),
        {
          'totalStock': FieldValue.increment(survivingGoats),
          'pendingRegistrations':
          FieldValue.increment(survivingGoats),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit().timeout(_timeout);

    final updated =
    await getPurchase(
      farmId,
      purchaseId,
    );

    if (updated == null) {
      throw StateError(
        'Receiving was updated but the purchase could not be read back.',
      );
    }

    return updated;
  }

  // -----------------------------------------------------------------------
  // BACKFILL DASHBOARD SUMMARY
  // -----------------------------------------------------------------------

  /// Recomputes the purchase-derived dashboard summary fields
  /// (wholesalePurchased, totalStock, pendingRegistrations) from every
  /// existing purchase document, and overwrites them on
  /// farms/{farmId}/tradingSummary/dashboard.
  ///
  /// This exists because savePurchase()/completeReceiving() only
  /// started updating the summary doc once that logic was added — any
  /// purchase saved BEFORE that fix never incremented the summary, so
  /// the dashboard undercounts until this is run once per farm.
  ///
  /// Safe to call more than once: it always recomputes totals from
  /// scratch (not incremental), so re-running it just gets the same
  /// correct numbers rather than double-counting.
  ///
  /// Only sets wholesalePurchased/totalStock/pendingRegistrations —
  /// totalSold, totalProfit, booking, and waitOnDelivery come from
  /// other modules (sales/bookings) and are left untouched via merge.
  Future<void> backfillDashboardSummary(String farmId) async {
    final snapshot =
    await _tradingPurchases(farmId).get().timeout(_timeout);

    var wholesalePurchased = 0;
    var totalStock = 0;

    for (final doc in snapshot.docs) {
      final purchase = TradingPurchase.fromDoc(doc);

      wholesalePurchased += purchase.totalGoats;

      if (purchase.isReceivingCompleted) {
        final surviving =
            purchase.totalGoats - purchase.mortality;

        if (surviving > 0) {
          totalStock += surviving;
        }
      }
    }

    await _summaryDoc(farmId).set(
      {
        'wholesalePurchased': wholesalePurchased,
        'totalStock': totalStock,
        // pendingRegistrations mirrors totalStock in this app: every
        // surviving, received goat still needs registering, and
        // nothing currently reduces this count (no registration flow
        // wired up yet).
        'pendingRegistrations': totalStock,
      },
      SetOptions(merge: true),
    ).timeout(_timeout);
  }

  // -----------------------------------------------------------------------
  // MARK RECEIVING AS PENDING
  // -----------------------------------------------------------------------

  /// Explicitly marks a purchase as pending receiving.
  ///
  /// This is useful if the user chooses "Later" before entering any
  /// receiving information.
  Future<void> markReceivingPending({
    required String farmId,
    required String purchaseId,
  }) async {
    await _tradingPurchases(farmId)
        .doc(purchaseId)
        .update({
      'receivingStatus': 'pending',
      'dateReceivedAtFarm':
      FieldValue.delete(),
      'totalWeightAfterArrival':
      FieldValue.delete(),
      'weightLoss':
      FieldValue.delete(),
      'updatedAt':
      FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  // -----------------------------------------------------------------------
  // DELETE / VOID SAFETY
  // -----------------------------------------------------------------------

  /// Trading purchases are financial records.
  ///
  /// Do not hard-delete them from the application flow.
  /// This method exists only as a safety guard for callers that might
  /// otherwise try to delete a purchase.
  Future<void> preventPurchaseDeletion({
    required String farmId,
    required String purchaseId,
  }) async {
    final purchase =
    await getPurchase(
      farmId,
      purchaseId,
    );

    if (purchase == null) {
      throw StateError(
        'Purchase $purchaseId was not found.',
      );
    }

    throw StateError(
      'Trading purchases are financial records and cannot be deleted.',
    );
  }

  // -----------------------------------------------------------------------
  // PAYMENT METHOD
  // -----------------------------------------------------------------------

  /// Trading supports ONLY:
  ///
  /// Cash
  /// Online
  ///
  /// No UPI
  /// No Bank Transfer
  /// No Cheque
  /// No Other
  /// No Credit
  static String _normalizePaymentMethod(
      String value,
      ) {
    final method =
    value.trim().toLowerCase();

    if (method == 'online') {
      return 'Online';
    }

    if (method == 'cash') {
      return 'Cash';
    }

    throw ArgumentError(
      'Trading payment method must be Cash or Online.',
    );
  }

  // -----------------------------------------------------------------------
  // RECEIVING STATUS
  // -----------------------------------------------------------------------

  static String _normalizeReceivingStatus(
      String value,
      ) {
    return value.trim().toLowerCase() ==
        'completed'
        ? 'completed'
        : 'pending';
  }
}