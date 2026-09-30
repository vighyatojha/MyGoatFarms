import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity_model.dart';
import '../models/expense_categories.dart';
import '../models/expense_model.dart';
import '../models/goat_model.dart';
import '../models/legacy_conversion_plan.dart';
import '../models/purchase_costing.dart';
import '../models/sale_model.dart';
import '../models/trading_lot_payment_model.dart';
import '../models/trading_lot_receiving_model.dart';
import '../models/trading_lot_overview.dart';
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
/// Result of one convertLegacyPurchasesToLots() run.
class LegacyConversionReport {
  /// Ids of every purchase converted this run (empty if there was nothing
  /// left to convert).
  final List<String> convertedIds;

  /// Converted purchases whose `registeredCount` / `pendingCount` had to be
  /// corrected to match the goat records that really exist.
  final List<String> adjustedIds;

  /// Purchases NOT converted because they changed (or vanished) while the
  /// run was in progress. Nothing was written for them — run it again.
  final List<String> skippedIds;

  /// Purchases whose conversion threw an error, as "PUR-0003: message".
  /// Nothing was written for them (each purchase is one transaction).
  final List<String> failures;

  /// Things worth a human look, see [LegacyConversionPlan.warnings].
  final List<String> warnings;

  const LegacyConversionReport({
    required this.convertedIds,
    required this.adjustedIds,
    required this.skippedIds,
    required this.failures,
    required this.warnings,
  });

  int get convertedCount => convertedIds.length;

  /// Every purchase was converted and nothing needs a second look.
  bool get isClean =>
      skippedIds.isEmpty && failures.isEmpty && warnings.isEmpty;

  /// Some purchases still need another run.
  bool get needsRerun => skippedIds.isNotEmpty || failures.isNotEmpty;
}

enum _ConversionOutcome { converted, alreadyLot, changed, missing }

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

  CollectionReference<Map<String, dynamic>> _tradingGoats(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingGoats');
  }

  /// Owned by SalesService (farms/{farmId}/sales). Read-only here — used
  /// only by [backfillDashboardSummary] to recompute `totalProfit` from
  /// each finalized sale's stored goat-sale value.
  CollectionReference<Map<String, dynamic>> _sales(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('sales');
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
  // PENDING REGISTRATION
  // -----------------------------------------------------------------------

  /// Streams purchases that still have goats waiting to be registered
  /// (Feature 3 — Goat Registration).
  ///
  /// Deliberately restricted to `receivingStatus == 'completed'`: until
  /// receiving is confirmed, mortality isn't known yet, so the surviving
  /// goat count for that purchase isn't final. A purchase with receiving
  /// still pending shows up under "Pending Receiving" instead — once
  /// receiving is completed there, `pendingCount` becomes registerable
  /// here.
  ///
  /// Used by the Select Purchase screen (Task 2.1).
  Stream<List<TradingPurchase>> pendingRegistrationStream(
      String farmId,
      ) {
    return _tradingPurchases(farmId)
        .where(
      'receivingStatus',
      isEqualTo: 'completed',
    )
        .snapshots()
        .map(
          (snapshot) {
        final purchases = snapshot.docs
            .map(
              (doc) => TradingPurchase.fromDoc(doc),
        )
        // Lots register goats only through a Palai transfer
        // (GoatService.transferLotToOwnPalai /
        // saveLotTransferToCustomerPalai), never through this
        // one-by-one flow — a lot reaching here would offer a
        // "Register Goats" button that bypasses Palai tracking.
            .where(
              (purchase) => !purchase.isLot,
        )
            .where(
              (purchase) => purchase.pendingCount > 0,
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
  // LOT OVERVIEW (dashboard)
  // -----------------------------------------------------------------------

  /// One listener on the whole `tradingPurchases` collection, reduced to
  /// [TradingLotOverview] — every lot number the dashboard needs, derived
  /// live rather than read from a stored counter. See that class's doc
  /// comment for why.
  Stream<TradingLotOverview> lotOverviewStream(String farmId) {
    return _tradingPurchases(farmId).snapshots().map((snapshot) {
      final purchases = snapshot.docs.map(TradingPurchase.fromDoc).toList();
      return TradingLotOverview.fromPurchases(purchases);
    });
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

    // Gender split of totalGoats, captured at Purchase Details rather
    // than per-goat at Registration. Defaults to 0/0 for callers (like
    // the single-goat quick purchase) that don't collect this yet.
    int maleGoats = 0,
    int femaleGoats = 0,

    // Payment
    required String paymentMethod,

    // Supplier payment made at purchase time. null = paid in full (the
    // single-goat quick purchase); 0 = nothing paid yet. Later payments
    // go through addSupplierPayment().
    double? advanceAmount,
    String? advanceMethod,
    DateTime? advanceDate,
    String advanceNote = '',

    /// When the supplier is due to deliver the lot. Optional.
    DateTime? expectedDeliveryDate,

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

    if (maleGoats < 0 || femaleGoats < 0) {
      throw ArgumentError('Male and Female goat counts cannot be negative.');
    }

    // Only enforced once a gender split has actually been entered, so
    // callers that don't collect it yet (e.g. the single-goat quick
    // purchase) can keep passing 0 / 0 without tripping this check.
    if ((maleGoats > 0 || femaleGoats > 0) &&
        (maleGoats + femaleGoats) != totalGoats) {
      throw ArgumentError(
        'Male + Female goats must add up to the total goats purchased.',
      );
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

    if (advanceAmount != null && advanceAmount < 0) {
      throw ArgumentError('Amount paid now cannot be negative.');
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

      if (totalWeightAfterArrival > totalWeightAtPurchase) {
        throw ArgumentError(
          'Arrival weight cannot be greater than purchase weight.',
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

    // Aligned with completeReceiving()'s guard: at least one goat must
    // survive whenever receiving is being recorded as completed right
    // here. (Previously this only rejected mortality > totalGoats,
    // technically permitting 0 survivors at save time even though
    // completeReceiving() rejects that later — two different rules for
    // the same business concept.) When receiving is still "pending",
    // mortality isn't meaningful yet (costing ignores it, see
    // `isCompleted ? mortality : 0` below), so it isn't restricted here.
    if (normalizedReceivingStatus == 'completed' &&
        mortality >= totalGoats) {
      throw ArgumentError(
        'At least one goat must survive — mortality cannot equal or '
            'exceed total goats.',
      );
    }

    // ---------------------------------------------------------------------
    // CALCULATIONS
    // ---------------------------------------------------------------------

    // Same engine the wizard uses for its live numbers, so what was shown
    // on screen is exactly what gets saved (rounded to 2 decimals).
    final isCompleted = normalizedReceivingStatus == 'completed';

    final safeArrivalWeight =
    isCompleted ? (totalWeightAfterArrival ?? 0.0) : 0.0;

    final costing = PurchaseCosting(
      totalGoats: totalGoats,
      weightAtPurchase: totalWeightAtPurchase,
      pricePerKg: pricePerKg,
      weightAfterArrival: safeArrivalWeight,
      mortality: isCompleted ? mortality : 0,
      transportCost: transportCost,
      loadingCharges: loadingCharges,
      unloadingCharges: unloadingCharges,
      otherExpenses: otherExpenses,
    );

    final purchaseAmount = costing.purchaseAmount;

    final paidNow = PurchaseCosting.round2(advanceAmount ?? purchaseAmount);

    if (paidNow > purchaseAmount + 0.005) {
      throw ArgumentError(
        'Amount paid now cannot be more than the purchase amount.',
      );
    }

    final normalizedAdvanceMethod = _normalizePaymentMethod(
      advanceMethod ?? paymentMethod,
    );

    final actor = await FirestoreService.instance.getCurrentActor();

    final weightLoss = isCompleted ? costing.weightLoss : null;

    final totalTransportExpenses = costing.totalExpenses;

    final grandTotal = costing.grandTotal;

    final effectiveCostPerKg = costing.effectiveCostPerKg;

    // ---------------------------------------------------------------------
    // CREATE SEQUENTIAL PURCHASE ID
    // ---------------------------------------------------------------------

    final counterRef = _purchaseCounterDoc(farmId);

    // Set inside the transaction so the Finance cash entry below can be
    // linked to the exact payment document.
    String? paymentDocId;

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
          maleGoats: maleGoats,
          femaleGoats: femaleGoats,

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

          // While receiving is pending nothing has arrived, so mortality
          // must stay 0 — the lot's supplierQty counts it as received.
          mortality: isCompleted ? mortality : 0,
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

          // Only goats that actually arrived alive can be registered.
          // (This used to be totalGoats even after mortality, which forced
          // the person to "register" goats that had died.) While receiving
          // is still pending the survivors are unknown, so it starts at
          // totalGoats and completeReceiving() corrects it.
          // For a lot, pendingCount mirrors farmQty: goats at the farm.
          pendingCount: isCompleted ? costing.survivingGoats : 0,

          // Lot fields. Receiving at creation means every goat is
          // accounted for (arrived alive + died); otherwise all goats
          // are still at the supplier.
          lotSchema: 1,
          expectedDeliveryDate: expectedDeliveryDate,
          receivedAliveQty: isCompleted ? costing.survivingGoats : 0,
          paidAmount: paidNow,
        );

        final lotRef = _tradingPurchases(farmId).doc(id);

        transaction.set(
          lotRef,
          {
            ...purchase.toMap(),
            'createdAt':
            FieldValue.serverTimestamp(),
          },
        );

        // First supplier payment (append-only history).
        if (paidNow > 0) {
          final paymentRef = lotRef.collection('payments').doc();
          paymentDocId = paymentRef.id;

          transaction.set(paymentRef, {
            ...LotPayment(
              id: paymentRef.id,
              amount: paidNow,
              date: advanceDate ?? purchaseDate,
              method: normalizedAdvanceMethod,
              note: advanceNote,
              actorUid: actor?.uid,
              actorName: actor?.name,
            ).toMap(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // First receiving event, when the goats arrived with the purchase.
        if (isCompleted) {
          final receivingRef = lotRef.collection('receivings').doc();

          transaction.set(receivingRef, {
            ...LotReceiving(
              id: receivingRef.id,
              date: dateReceivedAtFarm!,
              arrivedQty: costing.survivingGoats,
              diedQty: mortality,
              arrivalWeight: safeArrivalWeight,
              note: remarks,
              actorUid: actor?.uid,
              actorName: actor?.name,
            ).toMap(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

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
        isCompleted ? costing.survivingGoats : 0;

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

    if (paymentDocId != null) {
      await _ensureLotPaymentExpense(
        farmId: farmId,
        lot: saved,
        paymentId: paymentDocId!,
        amount: paidNow,
        method: normalizedAdvanceMethod,
        date: advanceDate ?? purchaseDate,
        note: advanceNote,
      );
    }

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
      // Lots: the purchase itself is an audit-only Credit row (no cash
      // moved yet). Real cash is posted per supplier payment, see
      // _ensureLotPaymentExpense. Old purchases keep their cash row.
      paymentMethod: purchase.isLot
          ? 'Credit'
          : _normalizePaymentMethod(purchase.paymentMethod),
      note:
      'Trading purchase ${purchase.lotId}',
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

  /// Posts one cash / online Finance expense for a supplier payment.
  ///
  /// Idempotent through referenceType 'lotPayment' + referenceId
  /// (the payment doc id).
  Future<void> _ensureLotPaymentExpense({
    required String farmId,
    required TradingPurchase lot,
    required String paymentId,
    required double amount,
    required String method,
    required DateTime date,
    String note = '',
  }) async {
    final existing = await _db
        .collection('farms')
        .doc(farmId)
        .collection('expenses')
        .where('referenceType', isEqualTo: 'lotPayment')
        .where('referenceId', isEqualTo: paymentId)
        .limit(1)
        .get()
        .timeout(_timeout);

    if (existing.docs.isNotEmpty) return;

    final now = DateTime.now();
    final trimmed = note.trim();

    await FinanceService.instance.addExpense(
      farmId,
      ExpenseModel(
        id: '',
        title: 'Supplier Payment',
        category: ExpenseCategories.supplierPayment,
        amount: amount,
        supplierName: lot.sellerName,
        paymentMethod: _normalizePaymentMethod(method),
        note: trimmed.isEmpty
            ? 'Payment for ${lot.lotId}'
            : 'Payment for ${lot.lotId} — $trimmed',
        date: date,
        createdAt: now,
        updatedAt: now,
        status: 'active',
        referenceType: 'lotPayment',
        referenceId: paymentId,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // LOT STREAMS
  // -----------------------------------------------------------------------

  /// Every lot (lotSchema >= 1), newest first. Filter by
  /// [TradingPurchase.isActive] / [TradingPurchase.location] client-side.
  Stream<List<TradingPurchase>> lotsStream(String farmId) {
    return _tradingPurchases(farmId).snapshots().map((snapshot) {
      final lots = snapshot.docs
          .map((doc) => TradingPurchase.fromDoc(doc))
          .where((p) => p.isLot)
          .toList();

      lots.sort(
            (a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)),
      );

      return lots;
    });
  }

  /// Every sale made straight out of a Purchase Lot, newest first.
  ///
  /// A lot sale is any sale with a `lotId` (Sale.toMap writes `lotId`).
  /// Sorted here, not in the query, so no composite index is needed.
  Stream<List<Sale>> lotSalesStream(String farmId) {
    return _sales(farmId)
        .where('lotId', isGreaterThan: '')
        .snapshots()
        .map((snapshot) {
      final sales = snapshot.docs.map(Sale.fromDoc).toList();

      sales.sort(
            (a, b) => (b.saleDate ?? DateTime(2000))
            .compareTo(a.saleDate ?? DateTime(2000)),
      );

      return sales;
    });
  }

  /// Lots that still own goats.
  Stream<List<TradingPurchase>> activeLotsStream(String farmId) {
    return lotsStream(farmId).map(
          (lots) => lots.where((l) => l.isActive).toList(),
    );
  }

  Stream<TradingPurchase?> lotStream(String farmId, String lotDocId) {
    return _tradingPurchases(farmId).doc(lotDocId).snapshots().map(
          (doc) => doc.exists ? TradingPurchase.fromDoc(doc) : null,
    );
  }

  Stream<List<LotPayment>> lotPaymentsStream(
      String farmId,
      String lotDocId,
      ) {
    return _tradingPurchases(farmId)
        .doc(lotDocId)
        .collection('payments')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map(LotPayment.fromDoc).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Stream<List<LotReceiving>> lotReceivingsStream(
      String farmId,
      String lotDocId,
      ) {
    return _tradingPurchases(farmId)
        .doc(lotDocId)
        .collection('receivings')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map(LotReceiving.fromDoc).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  // -----------------------------------------------------------------------
  // ADD SUPPLIER PAYMENT
  // -----------------------------------------------------------------------

  /// Records one more payment to the supplier of a lot.
  ///
  /// Validates 0 < amount <= due inside the transaction, appends a
  /// payment doc and increments `paidAmount`, then posts the cash /
  /// online Finance expense (idempotent).
  Future<LotPayment> addSupplierPayment({
    required String farmId,
    required String lotDocId,
    required double amount,
    required String method,
    required DateTime date,
    String note = '',
  }) async {
    final rounded = PurchaseCosting.round2(amount);

    if (rounded <= 0) {
      throw ArgumentError('Payment must be greater than zero.');
    }

    final normalizedMethod = _normalizePaymentMethod(method);
    final actor = await FirestoreService.instance.getCurrentActor();

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);
    final paymentRef = lotRef.collection('payments').doc();

    late TradingPurchase lot;

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(lotRef);

      if (!snap.exists) {
        throw StateError('Lot $lotDocId was not found.');
      }

      lot = TradingPurchase.fromDoc(snap);

      if (!lot.isLot) {
        throw StateError(
          'Lot $lotDocId has not been converted to the lot format yet.',
        );
      }

      if (rounded > lot.dueAmount + 0.005) {
        throw ArgumentError(
          'Payment cannot be more than the balance due '
              '(${lot.dueAmount.toStringAsFixed(2)}).',
        );
      }

      transaction.set(paymentRef, {
        ...LotPayment(
          id: paymentRef.id,
          amount: rounded,
          date: date,
          method: normalizedMethod,
          note: note,
          actorUid: actor?.uid,
          actorName: actor?.name,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(lotRef, {
        'paidAmount': FieldValue.increment(rounded),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_timeout);

    await _ensureLotPaymentExpense(
      farmId: farmId,
      lot: lot,
      paymentId: paymentRef.id,
      amount: rounded,
      method: normalizedMethod,
      date: date,
      note: note,
    );

    final saved = await paymentRef.get().timeout(_timeout);

    return LotPayment.fromDoc(saved);
  }

  // -----------------------------------------------------------------------
  // RECEIVE LOT BATCH
  // -----------------------------------------------------------------------

  /// Records a batch of the lot's goats arriving at the farm.
  ///
  /// arrivedQty + diedQty must not exceed the goats still at the
  /// supplier. Goats already sold from the supplier are never received.
  /// When nothing is left at the supplier the lot's receiving is marked
  /// completed and its totals are recomputed.
  ///
  /// Optional transport-type costs are ADDED to what the lot already has.
  Future<TradingPurchase> receiveLotBatch({
    required String farmId,
    required String lotDocId,
    required int arrivedQty,
    required int diedQty,
    required double arrivalWeight,
    required DateTime date,
    String note = '',
    double transportCost = 0,
    double loadingCharges = 0,
    double unloadingCharges = 0,
    double otherExpenses = 0,
  }) async {
    if (arrivedQty < 0 || diedQty < 0) {
      throw ArgumentError('Quantities cannot be negative.');
    }

    if (arrivedQty + diedQty <= 0) {
      throw ArgumentError('Enter at least one goat.');
    }

    if (arrivedQty > 0 && arrivalWeight <= 0) {
      throw ArgumentError('Arrival weight must be greater than zero.');
    }

    if (arrivedQty == 0 && arrivalWeight != 0) {
      throw ArgumentError('Arrival weight must be 0 when no goat arrived.');
    }

    if (transportCost < 0 ||
        loadingCharges < 0 ||
        unloadingCharges < 0 ||
        otherExpenses < 0) {
      throw ArgumentError('Costs cannot be negative.');
    }

    final actor = await FirestoreService.instance.getCurrentActor();

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);
    final receivingRef = lotRef.collection('receivings').doc();

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(lotRef);

      if (!snap.exists) {
        throw StateError('Lot $lotDocId was not found.');
      }

      final lot = TradingPurchase.fromDoc(snap);

      if (!lot.isLot) {
        throw StateError(
          'Lot $lotDocId has not been converted to the lot format yet.',
        );
      }

      if (arrivedQty + diedQty > lot.supplierQty) {
        throw ArgumentError(
          'Only ${lot.supplierQty} goats are still at the supplier.',
        );
      }

      final newReceivedAlive = lot.receivedAliveQty + arrivedQty;
      final newMortality = lot.mortality + diedQty;
      final newReceivedTotal = newReceivedAlive + newMortality;

      final newSupplierQty = lot.totalGoats -
          lot.soldFromSupplierQty -
          newReceivedTotal;

      final newArrivalWeight = PurchaseCosting.round2(
        (lot.totalWeightAfterArrival ?? 0) + arrivalWeight,
      );

      // Pro-rated: goats sold at the supplier never travelled, so their
      // share of the purchase weight is not "lost".
      final expectedWeight =
          lot.totalWeightAtPurchase * newReceivedTotal / lot.totalGoats;

      final newFarmQty =
      (newReceivedAlive - lot.soldFromFarmQty - lot.registeredCount)
          .clamp(0, 1 << 30)
          .toInt();

      final newTransport = lot.transportCost + transportCost;
      final newLoading = lot.loadingCharges + loadingCharges;
      final newUnloading = lot.unloadingCharges + unloadingCharges;
      final newOther = lot.otherExpenses + otherExpenses;

      final costing = PurchaseCosting(
        totalGoats: lot.totalGoats,
        weightAtPurchase: lot.totalWeightAtPurchase,
        pricePerKg: lot.pricePerKg,
        weightAfterArrival: newArrivalWeight,
        mortality: newMortality,
        transportCost: newTransport,
        loadingCharges: newLoading,
        unloadingCharges: newUnloading,
        otherExpenses: newOther,
      );

      final completed = newSupplierQty <= 0;

      transaction.set(receivingRef, {
        ...LotReceiving(
          id: receivingRef.id,
          date: date,
          arrivedQty: arrivedQty,
          diedQty: diedQty,
          arrivalWeight: arrivalWeight,
          note: note,
          actorUid: actor?.uid,
          actorName: actor?.name,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(lotRef, {
        'receivedAliveQty': FieldValue.increment(arrivedQty),
        'mortality': FieldValue.increment(diedQty),
        'totalWeightAfterArrival': newArrivalWeight,
        'dateReceivedAtFarm': Timestamp.fromDate(date),
        'weightLoss': PurchaseCosting.round2(expectedWeight - newArrivalWeight),
        'pendingCount': newFarmQty,
        'transportCost': newTransport,
        'loadingCharges': newLoading,
        'unloadingCharges': newUnloading,
        'otherExpenses': newOther,
        'totalTransportExpenses': costing.totalExpenses,
        'grandTotal': costing.grandTotal,
        'effectiveCostPerKg': costing.effectiveCostPerKg,
        if (completed) 'receivingStatus': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (arrivedQty > 0) {
        transaction.set(
          _summaryDoc(farmId),
          {
            'totalStock': FieldValue.increment(arrivedQty),
            'pendingRegistrations': FieldValue.increment(arrivedQty),
          },
          SetOptions(merge: true),
        );
      }
    }).timeout(_timeout);

    final updated = await getPurchase(farmId, lotDocId);

    if (updated == null) {
      throw StateError(
        'Receiving was saved but the lot could not be read back.',
      );
    }

    return updated;
  }

  // -----------------------------------------------------------------------
  // LEGACY CONVERSION
  // -----------------------------------------------------------------------

  /// Builds the conversion plan for every purchase with `lotSchema == 0`.
  ///
  /// Reads the purchases once and the farm's `tradingGoats` once (grouped
  /// by `purchaseId`), so the number of goats that really exist decides
  /// each purchase's `registeredCount` — see [LegacyConversionPlanner].
  Future<List<LegacyConversionPlan>> _buildLegacyPlans(String farmId) async {
    final purchaseSnap =
    await _tradingPurchases(farmId).get().timeout(_timeout);

    final legacy = purchaseSnap.docs
        .map(TradingPurchase.fromDoc)
        .where((p) => !p.isLot)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (legacy.isEmpty) return const [];

    final goatSnap =
    await _tradingGoats(farmId).get().timeout(_timeout * 2);

    final goatsByPurchase = <String, int>{};

    for (final doc in goatSnap.docs) {
      final purchaseId = (doc.data()['purchaseId'] ?? '').toString();
      if (purchaseId.isEmpty) continue;
      goatsByPurchase[purchaseId] = (goatsByPurchase[purchaseId] ?? 0) + 1;
    }

    return [
      for (final purchase in legacy)
        LegacyConversionPlanner.plan(
          purchase,
          goatsByPurchase[purchase.id] ?? 0,
        ),
    ];
  }

  /// Dry run: exactly what [convertLegacyPurchasesToLots] would do right
  /// now, without writing anything.
  Future<LegacyConversionPreview> previewLegacyConversion(
      String farmId,
      ) async {
    return LegacyConversionPreview(await _buildLegacyPlans(farmId));
  }

  /// Converts every purchase with `lotSchema == 0` into the lot format, in
  /// place, doc id unchanged.
  ///
  /// Idempotent: only purchases that are still `lotSchema == 0` are
  /// touched, so running it twice (or on a farm with nothing to convert)
  /// is a no-op.
  ///
  /// Each purchase converts in its OWN transaction that first re-reads the
  /// purchase and refuses to write if it is already a lot or if its
  /// receiving status / counters no longer match the plan (someone
  /// registered a goat while this ran). Those are reported in
  /// [LegacyConversionReport.skippedIds] and picked up by the next run. A
  /// plain batch cannot make that check, which is why this is not batched.
  ///
  /// Per purchase (handover §7.3):
  /// - `receivedAliveQty`, `mortality`, `registeredCount`, `pendingCount`
  ///   come from [LegacyConversionPlanner].
  /// - `soldFromSupplierQty`, `soldFromFarmQty`, `reservedFarmQty` = 0:
  ///   nothing was ever sold or booked as a lot before now. Goats sold
  ///   earlier were individual goats and stay that way.
  /// - One `isLegacy: true` payment for the full `purchaseAmount` (every
  ///   old purchase was paid in full) and `paidAmount` to match.
  /// - One `isLegacy: true` receiving when receiving was completed.
  /// - NO Finance entry. The original cash `tradingPurchase` expense stays
  ///   as it is.
  ///
  /// Afterwards call [backfillDashboardSummary] once so the dashboard
  /// counters reflect the corrected figures.
  Future<LegacyConversionReport> convertLegacyPurchasesToLots(
      String farmId, {
        void Function(int done, int total)? onProgress,
      }) async {
    final actor = await FirestoreService.instance.getCurrentActor();
    final plans = await _buildLegacyPlans(farmId);

    final converted = <String>[];
    final adjusted = <String>[];
    final skipped = <String>[];
    final failures = <String>[];
    final warnings = <String>[];

    onProgress?.call(0, plans.length);

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final purchaseRef = _tradingPurchases(farmId).doc(plan.purchaseId);

      try {
        final outcome = await _db.runTransaction<_ConversionOutcome>(
              (transaction) async {
            final snap = await transaction.get(purchaseRef);

            if (!snap.exists) return _ConversionOutcome.missing;

            final current = TradingPurchase.fromDoc(snap);

            if (current.isLot) return _ConversionOutcome.alreadyLot;

            // Anything the plan was built from must still be true.
            if (current.receivingStatus != plan.storedReceivingStatus ||
                current.registeredCount != plan.storedRegisteredCount ||
                current.pendingCount != plan.storedPendingCount ||
                current.mortality != plan.storedMortality) {
              return _ConversionOutcome.changed;
            }

            transaction.update(purchaseRef, {
              'lotSchema': 1,
              'receivedAliveQty': plan.receivedAliveQty,
              'mortality': plan.mortality,
              'registeredCount': plan.registeredCount,
              'pendingCount': plan.pendingCount,
              'soldFromSupplierQty': 0,
              'soldFromFarmQty': 0,
              'reservedFarmQty': 0,
              'paidAmount': current.purchaseAmount,
              'legacyConvertedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            // The purchase was always paid in full when it was saved.
            if (current.purchaseAmount > 0) {
              final paymentRef = purchaseRef.collection('payments').doc();

              transaction.set(paymentRef, {
                ...LotPayment(
                  id: paymentRef.id,
                  amount: current.purchaseAmount,
                  date: current.purchaseDate,
                  method: current.paymentMethod,
                  note: 'Paid in full at purchase (converted)',
                  isLegacy: true,
                  actorUid: actor?.uid,
                  actorName: actor?.name,
                ).toMap(),
                'createdAt': FieldValue.serverTimestamp(),
              });
            }

            if (current.isReceivingCompleted) {
              final receivingRef =
              purchaseRef.collection('receivings').doc();

              transaction.set(receivingRef, {
                ...LotReceiving(
                  id: receivingRef.id,
                  date:
                  current.dateReceivedAtFarm ?? current.purchaseDate,
                  arrivedQty: plan.receivedAliveQty,
                  diedQty: plan.mortality,
                  arrivalWeight: current.totalWeightAfterArrival ?? 0,
                  note: 'Received before Purchase Lots (converted)',
                  isLegacy: true,
                  actorUid: actor?.uid,
                  actorName: actor?.name,
                ).toMap(),
                'createdAt': FieldValue.serverTimestamp(),
              });
            }

            return _ConversionOutcome.converted;
          },
        ).timeout(_timeout);

        switch (outcome) {
          case _ConversionOutcome.converted:
            converted.add(plan.purchaseId);
            if (plan.countersAdjusted) adjusted.add(plan.purchaseId);
            warnings.addAll(plan.warnings);
            break;
          case _ConversionOutcome.alreadyLot:
            break;
          case _ConversionOutcome.changed:
          case _ConversionOutcome.missing:
            skipped.add(plan.purchaseId);
            break;
        }
      } catch (error) {
        failures.add(
          '${plan.purchaseId}: '
              '${FirestoreService.instance.describeError(error)}',
        );
      }

      onProgress?.call(i + 1, plans.length);
    }

    return LegacyConversionReport(
      convertedIds: converted,
      adjustedIds: adjusted,
      skippedIds: skipped,
      failures: failures,
      warnings: warnings,
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

    // Transport / additional costs. A purchase saved with "receive later"
    // has none yet, so they are captured here, when the goats arrive.
    double transportCost = 0,
    double loadingCharges = 0,
    double unloadingCharges = 0,
    double otherExpenses = 0,
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

    // Lots (lotSchema >= 1) track quantities, so the legacy "receive
    // everything at once" call is routed through the same logic as
    // Receive Lot: everything still at the supplier arrives now, with
    // [mortality] of it dying in transit.
    final existing = await getPurchase(farmId, purchaseId);

    if (existing != null && existing.isLot) {
      if (mortality >= existing.supplierQty) {
        throw ArgumentError(
          'At least one goat must survive — mortality cannot equal or '
              'exceed the goats still at the supplier.',
        );
      }

      return receiveLotBatch(
        farmId: farmId,
        lotDocId: purchaseId,
        arrivedQty: existing.supplierQty - mortality,
        diedQty: mortality,
        arrivalWeight: totalWeightAfterArrival,
        date: dateReceivedAtFarm,
        note: remarks,
        transportCost: transportCost,
        loadingCharges: loadingCharges,
        unloadingCharges: unloadingCharges,
        otherExpenses: otherExpenses,
      );
    }

    final purchaseRef = _tradingPurchases(farmId).doc(purchaseId);

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Read first — a Firestore transaction requires every read to
      //    happen before any write.
      // ---------------------------------------------------------------

      final purchaseSnap = await transaction.get(purchaseRef);

      if (!purchaseSnap.exists) {
        throw StateError(
          'Purchase $purchaseId was not found.',
        );
      }

      final purchase = TradingPurchase.fromDoc(purchaseSnap);

      // Compare-and-swap guard: without this, a retry (e.g. the
      // read-back below timing out after the first commit already
      // succeeded) would re-run this whole method and increment the
      // dashboard summary a second time for goats already counted.
      if (!purchase.isReceivingPending) {
        throw StateError(
          'Receiving for purchase $purchaseId has already been '
              'completed or is in an unexpected state '
              '("${purchase.receivingStatus}").',
        );
      }

      // Aligned with complete_receiving_screen.dart's submit guard: at
      // least one goat must survive. (Previously this only rejected
      // mortality > totalGoats, technically permitting 0 survivors,
      // which disagreed with the UI's stricter rule.)
      if (mortality >= purchase.totalGoats) {
        throw ArgumentError(
          'At least one goat must survive — mortality cannot equal or '
              'exceed total goats.',
        );
      }

      if (totalWeightAfterArrival > purchase.totalWeightAtPurchase) {
        throw ArgumentError(
          'Arrival weight cannot be greater than purchase weight.',
        );
      }

      // ---------------------------------------------------------------
      // 2. Compute the costing.
      //    Grand total now includes the transport costs entered at
      //    receiving (before, it stayed at the bare purchase amount
      //    forever).
      // ---------------------------------------------------------------

      final costing = PurchaseCosting(
        totalGoats: purchase.totalGoats,
        weightAtPurchase: purchase.totalWeightAtPurchase,
        pricePerKg: purchase.pricePerKg,
        weightAfterArrival: totalWeightAfterArrival,
        mortality: mortality,
        transportCost: transportCost,
        loadingCharges: loadingCharges,
        unloadingCharges: unloadingCharges,
        otherExpenses: otherExpenses,
      );

      final weightLoss = costing.weightLoss;
      final effectiveCostPerKg = costing.effectiveCostPerKg;

      // ---------------------------------------------------------------
      // 3. Update the purchase doc.
      // ---------------------------------------------------------------

      transaction.update(
        purchaseRef,
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
          'transportCost': transportCost,
          'loadingCharges': loadingCharges,
          'unloadingCharges': unloadingCharges,
          'otherExpenses': otherExpenses,
          'totalTransportExpenses': costing.totalExpenses,
          'grandTotal': costing.grandTotal,
          'effectiveCostPerKg':
          effectiveCostPerKg,
          // Goats left to register = survivors minus any already registered.
          'pendingCount': costing.survivingGoats > purchase.registeredCount
              ? costing.survivingGoats - purchase.registeredCount
              : 0,
          'updatedAt':
          FieldValue.serverTimestamp(),
        },
      );

      // ---------------------------------------------------------------
      // 4. Dashboard aggregate. These goats were NOT counted in
      //    totalStock / pendingRegistrations when the purchase was
      //    first saved (see savePurchase()), because receiving was
      //    still pending then. Now that receiving is confirmed (and
      //    guarded above to run at most once), add the surviving
      //    goats (mortality subtracted) to the dashboard summary.
      // ---------------------------------------------------------------

      final survivingGoats = purchase.totalGoats - mortality;

      if (survivingGoats > 0) {
        transaction.set(
          _summaryDoc(farmId),
          {
            'totalStock': FieldValue.increment(survivingGoats),
            'pendingRegistrations':
            FieldValue.increment(survivingGoats),
          },
          SetOptions(merge: true),
        );
      }

    }).timeout(_timeout);

    // Read the committed doc back for the return value. This is safe to
    // retry on failure now: unlike the old batch-based version, a retry
    // re-enters the transaction above, which will see `receivingStatus`
    // already `'completed'` and throw via the guard instead of
    // incrementing the dashboard summary a second time.
    final updated = await getPurchase(
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
  /// --- totalStock vs. pendingRegistrations (Phase 2 note) ---
  ///
  /// `totalStock` means "goats physically on the farm, alive" —
  /// surviving count (totalGoats - mortality) as of receiving. Feature
  /// 3 (Goat Registration, see GoatService) deliberately never touches
  /// this: registering a goat doesn't move it onto or off the farm, it
  /// just creates its individual record, so totalStock stays correct
  /// through partial registration without any extra wiring. This is
  /// also why Task 3.3 in the phase 2 plan doesn't redefine totalStock
  /// as "count of tradingGoats with currentStatus == Available" — doing
  /// that would make the number dip during partial registration (e.g.
  /// 12/20 registered would show 12 instead of the 20 goats actually on
  /// the farm), which contradicts the plan's own requirement that
  /// partial registration must "work correctly everywhere."
  ///
  /// `pendingRegistrations`, on the other hand, DOES change as
  /// registration happens — GoatService.registerGoat() decrements it by
  /// 1 per goat, inside the same transaction as the goat write and the
  /// purchase's registeredCount/pendingCount update. So unlike
  /// totalStock, this backfill must NOT reset pendingRegistrations to
  /// the full surviving-goat count; it has to sum each purchase's
  /// current `pendingCount` (which already reflects registrations to
  /// date), or re-running backfill after registration has started would
  /// silently undo it.
  ///
  /// `totalStock`, `totalSold`, `booking`, `waitOnDelivery`, and
  /// `totalProfit` are additionally reconciled here (added when negative
  /// dashboard values turned up in production — a purchase from before
  /// this dashboard tracking existed had already thrown every
  /// increment/decrement pair off balance). Unlike the purchase-only
  /// totalStock estimate above, the first four are derived straight from
  /// each goat's actual `currentStatus` today, so they self-heal
  /// regardless of what drifted the stored counters in the first place:
  ///
  ///   totalStock = pendingRegistrations (received, not yet
  ///                individually registered — no tradingGoats doc yet)
  ///                + goats still on the farm (Available, Booked,
  ///                Wait on Delivery, Own Palai)
  ///   totalSold       = goats currently Sold
  ///   booking         = goats currently Booked
  ///   waitOnDelivery  = goats currently Wait on Delivery
  ///
  /// Goats currently Sold or In Customer Palai have left the farm and
  /// are excluded from totalStock, matching how every sale/transfer
  /// path already decrements it.
  ///
  /// `totalProfit` is rebuilt from the Sold / In Customer Palai goats
  /// found above: each one's `saleId` is grouped back to its Sale doc
  /// (farms/{farmId}/sales), and each one's `purchaseId` is priced via
  /// that purchase's [TradingPurchase.costPerSurvivingGoat] — same cost
  /// figure SalesService looks up live at sale time (see
  /// SalesService._costOfGoatsInTransaction). Revenue per sale is
  /// `sale.billGoatSale + sale.billHoldingCharges` — never
  /// transportation, which is not farm revenue — computed once per
  /// unique sale (not per goat) since that figure already covers every
  /// goat on that sale.
  Future<void> backfillDashboardSummary(String farmId) async {
    final snapshot =
    await _tradingPurchases(farmId).get().timeout(_timeout);

    var wholesalePurchased = 0;
    var pendingRegistrations = 0;
    var lotTotalSold = 0;
    final costPerSurvivingGoatByPurchaseId = <String, double>{};

    for (final doc in snapshot.docs) {
      final purchase = TradingPurchase.fromDoc(doc);

      wholesalePurchased += purchase.totalGoats;
      costPerSurvivingGoatByPurchaseId[purchase.id] =
          purchase.costPerSurvivingGoat;

      if (purchase.isLot) {
        // A lot's goats are at the farm — reserved or not — from the
        // moment they arrive, whether or not the lot has finished
        // receiving (a partially-received lot still has real goats
        // sitting at the farm waiting to be registered/transferred).
        pendingRegistrations += purchase.farmQty;

        // Sold straight out of the lot (Deliver Now, or a completed
        // Booking / Wait for Delivery) never creates a tradingGoats
        // doc, so it must be counted here — the goat-doc loop below
        // only sees goats that were individually registered.
        lotTotalSold += purchase.soldFromSupplierQty + purchase.soldFromFarmQty;
      } else if (purchase.isReceivingCompleted) {
        // Reflects goats from this purchase still awaiting individual
        // registration — kept in sync by GoatService.registerGoat() as
        // each goat is saved. Not the same as `surviving`: a partially
        // (or fully) registered purchase has a smaller pendingCount
        // than its surviving-goat count.
        if (purchase.pendingCount > 0) {
          pendingRegistrations += purchase.pendingCount;
        }
      }
    }

    final goatsSnapshot =
    await _tradingGoats(farmId).get().timeout(_timeout);

    var onFarmGoats = 0;
    var totalSold = 0;
    var booking = 0;
    var waitOnDelivery = 0;

    // Goats that have left the farm via a sale (Sold) or a Palai
    // transfer (In Customer Palai), grouped by the sale that moved
    // them — used below to compute totalProfit one sale at a time.
    final soldGoatsBySaleId = <String, List<Goat>>{};

    for (final doc in goatsSnapshot.docs) {
      final goat = Goat.fromDoc(doc);

      switch (goat.currentStatus) {
        case Goat.statusAvailable:
        case Goat.statusOwnPalai:
          onFarmGoats++;
          break;

        case Goat.statusBooked:
          onFarmGoats++;
          booking++;
          break;

        case Goat.statusWaitOnDelivery:
          onFarmGoats++;
          waitOnDelivery++;
          break;

        case Goat.statusSold: {
          totalSold++;
          final soldSaleId = (goat.saleId ?? '').trim();
          if (soldSaleId.isNotEmpty) {
            (soldGoatsBySaleId[soldSaleId] ??= []).add(goat);
          }
          break;
        }

        case Goat.statusInCustomerPalai: {
          // Left the farm via Branch D — not counted in totalStock or
          // totalSold, same as before, but its sale value still counts
          // toward totalProfit below.
          final palaiSaleId = (goat.saleId ?? '').trim();
          if (palaiSaleId.isNotEmpty) {
            (soldGoatsBySaleId[palaiSaleId] ??= []).add(goat);
          }
          break;
        }
      }
    }

    var totalProfit = 0.0;

    for (final entry in soldGoatsBySaleId.entries) {
      final saleSnap =
      await _sales(farmId).doc(entry.key).get().timeout(_timeout);

      if (!saleSnap.exists) continue;

      final sale = Sale.fromDoc(saleSnap);
      final revenue = sale.billGoatSale + sale.billHoldingCharges;

      // A goat carrying a cost snapshot came out of a lot (a Step 6
      // Customer Palai transfer) — its cost was fixed at the moment of
      // that transfer and must not drift with the lot's live cost
      // afterwards. A goat with no snapshot is an ordinary purchase-based
      // goat and still uses the live per-purchase figure.
      final cost = sale.costPerGoatSnapshot != null
          ? sale.costPerGoatSnapshot! * entry.value.length
          : entry.value.fold<double>(
        0,
            (sum, goat) =>
        sum + (costPerSurvivingGoatByPurchaseId[goat.purchaseId] ?? 0),
      );

      totalProfit += revenue - cost;
    }

    // ------------------------------------------------------------------
    // LOT SALES — Deliver Now / Booking / Wait for Delivery straight out
    // of a lot never create a tradingGoats doc, so none of the counting
    // above sees them. One extra query picks them all up: every sale
    // with a lotId is a lot sale (Sale.toMap writes `lotId`, not
    // `lotDocId` — see Sale.fromDoc/toMap).
    // ------------------------------------------------------------------

    final lotSalesSnapshot = await _sales(farmId)
        .where('lotId', isGreaterThan: '')
        .get()
        .timeout(_timeout);

    for (final doc in lotSalesSnapshot.docs) {
      final sale = Sale.fromDoc(doc);

      switch (sale.status) {
        case Sale.statusBooked:
          booking += sale.lotQuantity;
          break;

        case Sale.statusWaitForDelivery:
          waitOnDelivery += sale.lotQuantity;
          break;

        case Sale.statusSold:
        case Sale.statusDeliveryCompleted:
        case Sale.statusPickupCompleted:
          final revenue = sale.billGoatSale + sale.billHoldingCharges;
          final cost = (sale.costPerGoatSnapshot ?? 0) * sale.lotQuantity;
          totalProfit += revenue - cost;
          break;
      }
    }

    totalSold += lotTotalSold;

    final totalStock = pendingRegistrations + onFarmGoats;

    await _summaryDoc(farmId).set(
      {
        'wholesalePurchased': wholesalePurchased,
        'totalStock': totalStock,
        'pendingRegistrations': pendingRegistrations,
        'totalSold': totalSold,
        'booking': booking,
        'waitOnDelivery': waitOnDelivery,
        'totalProfit': PurchaseCosting.round2(totalProfit),
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