import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_categories.dart';
import '../models/expense_model.dart';
import '../models/goat_model.dart';
import '../models/legacy_conversion_plan.dart';
import '../models/purchase_costing.dart';
import '../models/sale_model.dart';
import '../models/trading_lot_death_model.dart';
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
  // PENDING REGISTRATION
  // -----------------------------------------------------------------------


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

    /// Remarks about the purchase itself (entered on the Supplier step).
    /// Stored on the lot whether or not receiving is completed; when empty,
    /// the lot keeps the arrival [remarks] as before.
    String purchaseRemarks = '',

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
          remarks: purchaseRemarks.trim().isNotEmpty
              ? purchaseRemarks.trim()
              : remarks.trim(),

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
              expenseId: _lotPaymentExpenseDocId(paymentRef.id),
              actorUid: actor?.uid,
              actorName: actor?.name,
            ).toMap(),
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Finance cash entry for this payment — same transaction, so a
          // payment can never exist without its Finance row.
          FinanceService.instance.writeExpenseInTransaction(
            transaction,
            farmId,
            _lotPaymentExpense(
              lot: purchase,
              amount: paidNow,
              method: normalizedAdvanceMethod,
              date: advanceDate ?? purchaseDate,
              note: advanceNote,
              paymentId: paymentRef.id,
            ),
            expenseDocId: _lotPaymentExpenseDocId(paymentRef.id),
            actor: actor,
          );
        }

        // Audit-only Credit row for the full purchase amount (no cash
        // moves), also inside the same transaction.
        FinanceService.instance.writeExpenseInTransaction(
          transaction,
          farmId,
          _lotPurchaseExpense(purchase),
          expenseDocId: _lotPurchaseExpenseDocId(id),
          actor: actor,
        );

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

    // Finance rows were written inside the transaction above. Only the
    // fire-and-forget partner notifications happen after commit.
    FinanceService.instance.notifyExpenseAdded(
      farmId,
      _lotPurchaseExpense(saved),
      actor,
    );

    if (paymentDocId != null) {
      FinanceService.instance.notifyExpenseAdded(
        farmId,
        _lotPaymentExpense(
          lot: saved,
          amount: paidNow,
          method: normalizedAdvanceMethod,
          date: advanceDate ?? purchaseDate,
          note: advanceNote,
          paymentId: paymentDocId!,
        ),
        actor,
      );
    }

    return saved;
  }

  // -----------------------------------------------------------------------
  // FINANCE INTEGRATION
  // -----------------------------------------------------------------------

  /// Deterministic Finance document ids: writing the same purchase or payment
  /// twice overwrites the same expense, never adds a second one.
  String _lotPurchaseExpenseDocId(String lotDocId) =>
      'lotpurchase_$lotDocId';

  String _lotPaymentExpenseDocId(String paymentId) => 'lotpay_$paymentId';

  /// The audit-only Credit expense for a lot's full purchase amount.
  ExpenseModel _lotPurchaseExpense(TradingPurchase purchase) {
    final now = DateTime.now();

    return ExpenseModel(
      id: '',
      title: 'Goat Purchase',
      category: ExpenseCategories.goatPurchase,
      amount: purchase.purchaseAmount,
      supplierName: purchase.sellerName,
      // Lots: the purchase itself is an audit-only Credit row (no cash
      // moved yet). Real cash is posted per supplier payment.
      paymentMethod: purchase.isLot
          ? 'Credit'
          : _normalizePaymentMethod(purchase.paymentMethod),
      note: 'Trading purchase ${purchase.lotId}',
      date: purchase.purchaseDate,
      createdAt: now,
      updatedAt: now,
      status: 'active',
      referenceType: 'tradingPurchase',
      referenceId: purchase.id,
    );
  }

  /// The cash / online Finance expense for ONE supplier payment.
  ExpenseModel _lotPaymentExpense({
    required TradingPurchase lot,
    required double amount,
    required String method,
    required DateTime date,
    required String paymentId,
    String note = '',
  }) {
    final now = DateTime.now();
    final trimmed = note.trim();

    return ExpenseModel(
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
      lotId: lot.id,
    );
  }

  /// Repairs Finance rows that older, non-atomic saves may have missed.
  ///
  /// Before payments and their Finance rows were written in one
  /// transaction, a dropped connection could leave a lot (or a supplier
  /// payment) with no Finance entry. This looks for exactly those gaps and
  /// writes the missing row, with the same deterministic id the live code
  /// uses — so it is safe to run any number of times and never duplicates.
  /// Voided expenses still have their referenceId, so they stay voided.
  ///
  /// Returns how many Finance rows were created.
  Future<int> reconcileLotFinance(String farmId) async {
    final expensesSnap = await _db
        .collection('farms')
        .doc(farmId)
        .collection('expenses')
        .where('referenceType', whereIn: ['tradingPurchase', 'lotPayment'])
        .get()
        .timeout(_timeout);

    final purchaseRefs = <String>{};
    final paymentRefs = <String>{};

    for (final doc in expensesSnap.docs) {
      final data = doc.data();
      final ref = (data['referenceId'] ?? '').toString();

      if (data['referenceType'] == 'tradingPurchase') {
        purchaseRefs.add(ref);
      } else {
        paymentRefs.add(ref);
      }
    }

    final lotsSnap = await _tradingPurchases(farmId).get().timeout(_timeout);
    final actor = await FirestoreService.instance.getCurrentActor();

    var created = 0;

    for (final doc in lotsSnap.docs) {
      final lot = TradingPurchase.fromDoc(doc);

      if (!lot.isLot) continue;

      if (!purchaseRefs.contains(lot.id)) {
        await _db.runTransaction((transaction) async {
          FinanceService.instance.writeExpenseInTransaction(
            transaction,
            farmId,
            _lotPurchaseExpense(lot),
            expenseDocId: _lotPurchaseExpenseDocId(lot.id),
            actor: actor,
          );
        }).timeout(_timeout);
        created++;
      }

      if (lot.paidAmount <= 0) continue;

      final paymentsSnap =
      await doc.reference.collection('payments').get().timeout(_timeout);

      for (final paymentDoc in paymentsSnap.docs) {
        final payment = LotPayment.fromDoc(paymentDoc);

        // Legacy payments already have their original purchase expense.
        if (payment.isLegacy || payment.amount <= 0) continue;
        // A voided payment is deliberately not counted — never re-post it.
        if (payment.voided) continue;
        if (paymentRefs.contains(payment.id)) continue;

        await _db.runTransaction((transaction) async {
          FinanceService.instance.writeExpenseInTransaction(
            transaction,
            farmId,
            _lotPaymentExpense(
              lot: lot,
              amount: payment.amount,
              method: payment.method,
              date: payment.date,
              note: payment.note,
              paymentId: payment.id,
            ),
            expenseDocId: _lotPaymentExpenseDocId(payment.id),
            actor: actor,
          );
          transaction.update(paymentDoc.reference, {
            'expenseId': _lotPaymentExpenseDocId(payment.id),
          });
        }).timeout(_timeout);
        created++;
      }
    }

    return created;
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

  /// Every sale made from ONE lot (newest first) — the lot's sales history.
  ///
  /// `Sale.toMap` stores the lot's Firestore doc id (PUR-0007) in `lotId`,
  /// so this is an equality filter on a single field: no composite index
  /// needed. Sorted here, not in the query.
  Stream<List<Sale>> salesForLotStream(String farmId, String lotDocId) {
    return _sales(farmId)
        .where('lotId', isEqualTo: lotDocId)
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

  Stream<List<LotDeath>> lotDeathsStream(
      String farmId,
      String lotDocId,
      ) {
    return _tradingPurchases(farmId)
        .doc(lotDocId)
        .collection('deaths')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map(LotDeath.fromDoc).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  // -----------------------------------------------------------------------
  // RECORD DEATH (goats at the farm, still in the lot)
  // -----------------------------------------------------------------------

  /// Records [qty] goats of the lot that died at the farm.
  ///
  /// Only goats that are at the farm and not reserved for a Booking / Wait
  /// sale can be recorded ([TradingPurchase.farmAvailableQty]); goats still
  /// at the supplier are handled by Receive Lot, and individually
  /// registered goats have their own death flow.
  ///
  /// Counter maths, chosen so no existing formula changes:
  ///   receivedAliveQty  - qty
  ///   mortality         + qty   (receivedTotalQty, hence supplierQty, is
  ///                              unchanged)
  ///   farmDeathQty      + qty   (display only)
  ///   farmQty / pendingCount fall by qty automatically / explicitly
  ///
  /// Because mortality rises, the lot's cost per surviving goat rises: the
  /// loss is carried by the goats that are left. No Finance entry is
  /// written — the money was spent at purchase; nothing is paid or received
  /// when a goat dies.
  ///
  /// The loss shown on the event is qty x cost per goat BEFORE the death.
  Future<LotDeath> recordLotFarmDeath({
    required String farmId,
    required String lotDocId,
    required int qty,
    required String reason,
    required DateTime date,
    String note = '',
  }) async {
    if (qty <= 0) {
      throw ArgumentError('Enter at least one goat.');
    }

    final actor = await FirestoreService.instance.getCurrentActor();

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);
    final deathRef = lotRef.collection('deaths').doc();

    late LotDeath event;

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

      if (qty > lot.farmAvailableQty) {
        throw ArgumentError(
          'Only ${lot.farmAvailableQty} goats at the farm can be recorded '
              'as dead (goats reserved for a booking are excluded).',
        );
      }

      // Same basis a sale snapshots (TradingPurchase.lotCostPerGoat): after
      // receiving is completed it is grand total / survivors; before that
      // it is (purchase + expenses so far) / goats bought.
      final perGoat = lot.lotCostPerGoat;

      event = LotDeath(
        id: deathRef.id,
        date: date,
        qty: qty,
        reason: reason.trim().isEmpty ? 'Unknown' : reason.trim(),
        note: note,
        costPerGoat: perGoat,
        lossAmount: PurchaseCosting.round2(perGoat * qty),
        actorUid: actor?.uid,
        actorName: actor?.name,
      );

      final newFarmQty = (lot.receivedAliveQty -
          qty -
          lot.soldFromFarmQty -
          lot.registeredCount)
          .clamp(0, 1 << 30)
          .toInt();

      transaction.set(deathRef, {
        ...event.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(lotRef, {
        'receivedAliveQty': FieldValue.increment(-qty),
        'mortality': FieldValue.increment(qty),
        'farmDeathQty': FieldValue.increment(qty),
        'pendingCount': newFarmQty,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock': FieldValue.increment(-qty),
          'pendingRegistrations': FieldValue.increment(-qty),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout);

    return event;
  }

  // -----------------------------------------------------------------------
  // UNDO DEATH (reverse a Record Death event)
  // -----------------------------------------------------------------------

  /// Reverses a death recorded with [recordLotFarmDeath].
  ///
  /// Exact mirror of the original counter changes:
  ///   receivedAliveQty  + qty
  ///   mortality         - qty
  ///   farmDeathQty      - qty
  ///   pendingCount      recomputed (= farmQty)
  ///   summary totalStock / pendingRegistrations + qty
  ///
  /// The event doc is NOT deleted: it is marked `reversed` with who / when,
  /// so there is an audit trail. Already-reversed events are rejected, and
  /// the reversal is refused if it would push a counter below zero (which
  /// means the lot data was changed by hand).
  ///
  /// Sales made after the death keep the cost snapshot they took; only
  /// future sales use the (now lower) cost per goat again.
  Future<void> undoLotFarmDeath({
    required String farmId,
    required String lotDocId,
    required String deathId,
  }) async {
    final actor = await FirestoreService.instance.getCurrentActor();

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);
    final deathRef = lotRef.collection('deaths').doc(deathId);

    await _db.runTransaction((transaction) async {
      final lotSnap = await transaction.get(lotRef);
      final deathSnap = await transaction.get(deathRef);

      if (!lotSnap.exists) {
        throw StateError('Lot $lotDocId was not found.');
      }
      if (!deathSnap.exists) {
        throw StateError('This death record was not found.');
      }

      final lot = TradingPurchase.fromDoc(lotSnap);
      final death = LotDeath.fromDoc(deathSnap);

      if (death.reversed) {
        throw StateError('This death record was already undone.');
      }

      final qty = death.qty;

      if (qty <= 0 || qty > lot.farmDeathQty || qty > lot.mortality) {
        throw StateError(
          'This death cannot be undone because the lot counters no longer '
              'match it. Please check the lot.',
        );
      }

      final newFarmQty = (lot.receivedAliveQty +
          qty -
          lot.soldFromFarmQty -
          lot.registeredCount)
          .clamp(0, 1 << 30)
          .toInt();

      transaction.update(deathRef, {
        'reversed': true,
        'reversedAt': FieldValue.serverTimestamp(),
        if (actor?.uid != null) 'reversedByUid': actor!.uid,
        if (actor?.name != null) 'reversedByName': actor!.name,
      });

      transaction.update(lotRef, {
        'receivedAliveQty': FieldValue.increment(qty),
        'mortality': FieldValue.increment(-qty),
        'farmDeathQty': FieldValue.increment(-qty),
        'pendingCount': newFarmQty,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock': FieldValue.increment(qty),
          'pendingRegistrations': FieldValue.increment(qty),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout);
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

      if (lot.dealCancelled) {
        throw StateError('This deal was cancelled, so it takes no payments.');
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
          expenseId: _lotPaymentExpenseDocId(paymentRef.id),
          actorUid: actor?.uid,
          actorName: actor?.name,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(lotRef, {
        'paidAmount': FieldValue.increment(rounded),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Finance cash entry in the SAME transaction: the payment and its
      // Finance row commit together or not at all.
      FinanceService.instance.writeExpenseInTransaction(
        transaction,
        farmId,
        _lotPaymentExpense(
          lot: lot,
          amount: rounded,
          method: normalizedMethod,
          date: date,
          note: note,
          paymentId: paymentRef.id,
        ),
        expenseDocId: _lotPaymentExpenseDocId(paymentRef.id),
        actor: actor,
      );
    }).timeout(_timeout);

    FinanceService.instance.notifyExpenseAdded(
      farmId,
      _lotPaymentExpense(
        lot: lot,
        amount: rounded,
        method: normalizedMethod,
        date: date,
        note: note,
        paymentId: paymentRef.id,
      ),
      actor,
    );

    final saved = await paymentRef.get().timeout(_timeout);

    return LotPayment.fromDoc(saved);
  }

  // -----------------------------------------------------------------------
  // VOID SUPPLIER PAYMENT
  // -----------------------------------------------------------------------

  /// Voids one supplier payment that was entered by mistake.
  ///
  /// In ONE transaction:
  ///  * the payment doc is kept for audit and marked `voided` (who, when,
  ///    why), never deleted;
  ///  * the lot's `paidAmount` goes down by the payment amount, so Paid /
  ///    Balance Due / Status are correct again;
  ///  * the payment's Finance expense and its cash-flow transaction are
  ///    voided, so Trading Finance stops counting it.
  ///
  /// To CORRECT a payment, void it and add the right one.
  ///
  /// Refused for: an already voided payment, a payment synthesized from an
  /// old goat-first purchase (its original purchase expense is not tied to
  /// this record), and a lot whose paid amount is lower than the payment
  /// (counters no longer match — check the lot).
  Future<void> voidSupplierPayment({
    required String farmId,
    required String lotDocId,
    required String paymentId,
    String reason = '',
  }) async {
    final actor = await FirestoreService.instance.getCurrentActor();

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);
    final paymentRef = lotRef.collection('payments').doc(paymentId);
    final expenseRef = FinanceService.instance
        .expenseDocRef(farmId, _lotPaymentExpenseDocId(paymentId));

    late String lotLabel;
    late double voidedAmount;

    await _db.runTransaction((transaction) async {
      // All reads first.
      final lotSnap = await transaction.get(lotRef);
      final paymentSnap = await transaction.get(paymentRef);
      final expenseSnap = await transaction.get(expenseRef);

      if (!lotSnap.exists) {
        throw StateError('Lot $lotDocId was not found.');
      }
      if (!paymentSnap.exists) {
        throw StateError('This payment was not found.');
      }

      final lot = TradingPurchase.fromDoc(lotSnap);
      final payment = LotPayment.fromDoc(paymentSnap);

      if (lot.dealCancelled) {
        throw StateError(
          'This deal was cancelled and settled, so its payments cannot be '
              'voided.',
        );
      }

      if (payment.voided) {
        throw StateError('This payment was already voided.');
      }
      if (payment.isLegacy) {
        throw StateError(
          'This payment comes from the original goat purchase and cannot '
              'be voided here. Void the purchase expense in Finance instead.',
        );
      }
      if (payment.amount <= 0 || payment.amount > lot.paidAmount + 0.005) {
        throw StateError(
          'This payment cannot be voided because the lot totals no longer '
              'match it. Please check the lot.',
        );
      }

      lotLabel = lot.lotId;
      voidedAmount = payment.amount;

      transaction.update(paymentRef, {
        'voided': true,
        'voidedAt': FieldValue.serverTimestamp(),
        if (actor?.uid != null) 'voidedByUid': actor!.uid,
        if (actor?.name != null) 'voidedByName': actor!.name,
        'voidReason': reason.trim(),
      });

      final newPaid = PurchaseCosting.round2(lot.paidAmount - payment.amount);

      transaction.update(lotRef, {
        // Set (not increment) so rounding drift can never leave dust.
        'paidAmount': newPaid < 0 ? 0 : newPaid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      FinanceService.instance.voidExpenseInTransaction(
        transaction,
        farmId,
        expenseSnap: expenseSnap,
        title: 'Supplier Payment ($lotLabel)',
        amount: payment.amount,
        actor: actor,
      );
    }).timeout(_timeout);

    FinanceService.instance.notifyExpenseVoided(
      farmId,
      title: 'Supplier Payment ($lotLabel)',
      amount: voidedAmount,
      actor: actor,
    );
  }

  // -----------------------------------------------------------------------
  // EDIT LOT
  // -----------------------------------------------------------------------

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Edits a lot's supplier details, purchase figures and extra costs — at
  /// the supplier or at the farm, whatever has been received or sold so far.
  ///
  /// Every figure derived from them is recomputed with [PurchaseCosting]
  /// (the same engine the purchase wizard and receiving use), so Purchase
  /// Amount, Grand Total, Effective Cost / Kg, weight loss and the supplier
  /// balance stay consistent. In ONE transaction:
  ///  * the lot document is updated;
  ///  * the lot's audit-only Credit purchase row in Finance follows the new
  ///    amount / supplier / date;
  ///  * the dashboard's "wholesale purchased" counter moves by the change in
  ///    goats bought.
  ///
  /// Refused (nothing is written) when the edit would break the lot:
  ///  * fewer goats than have already left the supplier (sold from it or
  ///    received — see [TradingPurchase.minEditableTotalGoats]);
  ///  * a male / female split that no longer adds up, or is below the goats
  ///    already registered per gender;
  ///  * a purchase weight below the weight that already arrived;
  ///  * a new purchase amount below what has already been paid (void a
  ///    payment first);
  ///  * a purchase date after an existing payment or the receiving date;
  ///  * a cancelled lot.
  ///
  /// Sales already made keep the cost they were saved with; only later
  /// sales use the new cost per goat.
  Future<TradingPurchase> editLot({
    required String farmId,
    required String lotDocId,

    // Supplier
    required String sellerName,
    required String mobile,
    required String market,
    required String vehicleNumber,
    required DateTime purchaseDate,
    required String remarks,
    DateTime? expectedDeliveryDate,

    // Purchase
    required int totalGoats,
    required int maleGoats,
    required int femaleGoats,
    required double totalWeightAtPurchase,
    required double pricePerKg,

    // Extra costs
    required double transportCost,
    required double loadingCharges,
    required double unloadingCharges,
    required double otherExpenses,
  }) async {
    if (sellerName.trim().isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }

    if (totalGoats <= 0) {
      throw ArgumentError('Total goats must be greater than zero.');
    }

    if (maleGoats < 0 || femaleGoats < 0) {
      throw ArgumentError('Male and Female goat counts cannot be negative.');
    }

    if ((maleGoats > 0 || femaleGoats > 0) &&
        (maleGoats + femaleGoats) != totalGoats) {
      throw ArgumentError(
        'Male + Female goats must add up to the total goats.',
      );
    }

    if (totalWeightAtPurchase <= 0) {
      throw ArgumentError('Purchase weight must be greater than zero.');
    }

    if (pricePerKg <= 0) {
      throw ArgumentError('Price per kg must be greater than zero.');
    }

    if (transportCost < 0 ||
        loadingCharges < 0 ||
        unloadingCharges < 0 ||
        otherExpenses < 0) {
      throw ArgumentError('Costs cannot be negative.');
    }

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);

    // Payments are read once, outside the transaction (a transaction cannot
    // run a query): they are only needed to keep the purchase date before
    // the first real payment and to refresh the supplier name on their
    // Finance rows.
    final paymentsSnap =
    await lotRef.collection('payments').get().timeout(_timeout);

    final payments = paymentsSnap.docs.map(LotPayment.fromDoc).toList();

    final purchaseDay = _dayOnly(purchaseDate);

    for (final payment in payments) {
      if (payment.voided || payment.isLegacy) continue;

      if (purchaseDay.isAfter(_dayOnly(payment.date))) {
        throw ArgumentError(
          'Purchase date cannot be after a payment already made on '
              '${payment.date.day.toString().padLeft(2, '0')}/'
              '${payment.date.month.toString().padLeft(2, '0')}/'
              '${payment.date.year}.',
        );
      }
    }

    final purchaseExpenseRef = FinanceService.instance
        .expenseDocRef(farmId, _lotPurchaseExpenseDocId(lotDocId));

    late String previousSupplierName;

    await _db.runTransaction((transaction) async {
      // All reads first.
      final snap = await transaction.get(lotRef);
      final expenseSnap = await transaction.get(purchaseExpenseRef);

      if (!snap.exists) {
        throw StateError('Lot $lotDocId was not found.');
      }

      final lot = TradingPurchase.fromDoc(snap);

      if (!lot.isLot) {
        throw StateError(
          'Lot $lotDocId has not been converted to the lot format yet.',
        );
      }

      if (lot.dealCancelled) {
        throw StateError('This deal was cancelled, so it cannot be edited.');
      }

      previousSupplierName = lot.sellerName;

      if (totalGoats < lot.minEditableTotalGoats) {
        throw ArgumentError(
          'Total goats cannot be less than ${lot.minEditableTotalGoats} — '
              'that many have already been sold from the supplier or '
              'received at the farm.',
        );
      }

      if (maleGoats > 0 || femaleGoats > 0) {
        if (maleGoats < lot.maleRegistered) {
          throw ArgumentError(
            'Male goats cannot be less than ${lot.maleRegistered} — '
                'already registered.',
          );
        }

        if (femaleGoats < lot.femaleRegistered) {
          throw ArgumentError(
            'Female goats cannot be less than ${lot.femaleRegistered} — '
                'already registered.',
          );
        }
      }

      final arrivedWeight = lot.totalWeightAfterArrival ?? 0;

      if (arrivedWeight > totalWeightAtPurchase + 0.005) {
        throw ArgumentError(
          'Purchase weight cannot be less than the weight that already '
              'arrived (${PurchaseCosting.formatNumber(arrivedWeight)} kg).',
        );
      }

      final received = lot.dateReceivedAtFarm;

      if (received != null && purchaseDay.isAfter(_dayOnly(received))) {
        throw ArgumentError(
          'Purchase date cannot be after the date goats were received.',
        );
      }

      final costing = PurchaseCosting(
        totalGoats: totalGoats,
        weightAtPurchase: totalWeightAtPurchase,
        pricePerKg: pricePerKg,
        weightAfterArrival: arrivedWeight,
        mortality: lot.mortality,
        transportCost: transportCost,
        loadingCharges: loadingCharges,
        unloadingCharges: unloadingCharges,
        otherExpenses: otherExpenses,
      );

      final newPurchaseAmount = costing.purchaseAmount;

      if (lot.paidAmount > newPurchaseAmount + 0.005) {
        throw ArgumentError(
          'The new purchase amount (${newPurchaseAmount.toStringAsFixed(2)}) '
              'is less than the ${lot.paidAmount.toStringAsFixed(2)} already '
              'paid to the supplier. Void a payment first, or raise the '
              'weight / price.',
        );
      }

      final newSupplierQty =
          totalGoats - lot.soldFromSupplierQty - lot.receivedTotalQty;

      final String? newReceivingStatus;

      if (lot.isReceivingCompleted && newSupplierQty > 0) {
        newReceivingStatus = 'pending';
      } else if (!lot.isReceivingCompleted &&
          lot.receivedTotalQty > 0 &&
          newSupplierQty <= 0) {
        newReceivingStatus = 'completed';
      } else {
        newReceivingStatus = null;
      }

      final expectedWeight =
          totalWeightAtPurchase * lot.receivedTotalQty / totalGoats;

      transaction.update(lotRef, {
        'sellerName': sellerName.trim(),
        'mobile': mobile.trim(),
        'market': market.trim(),
        'vehicleNumber': vehicleNumber.trim(),
        'purchaseDate': Timestamp.fromDate(purchaseDate),
        'remarks': remarks.trim(),
        'expectedDeliveryDate': expectedDeliveryDate == null
            ? FieldValue.delete()
            : Timestamp.fromDate(expectedDeliveryDate),
        'totalGoats': totalGoats,
        'maleGoats': maleGoats,
        'femaleGoats': femaleGoats,
        'totalWeightAtPurchase': totalWeightAtPurchase,
        'pricePerKg': pricePerKg,
        'purchaseAmount': newPurchaseAmount,
        'transportCost': transportCost,
        'loadingCharges': loadingCharges,
        'unloadingCharges': unloadingCharges,
        'otherExpenses': otherExpenses,
        'totalTransportExpenses': costing.totalExpenses,
        'grandTotal': costing.grandTotal,
        'effectiveCostPerKg': costing.effectiveCostPerKg,
        if (lot.receivedTotalQty > 0)
          'weightLoss': PurchaseCosting.round2(expectedWeight - arrivedWeight),
        if (newReceivingStatus != null) 'receivingStatus': newReceivingStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // The lot's audit-only Credit purchase row follows the edit. Skipped
      // when it does not exist (older converted lots) or was voided.
      if (expenseSnap.exists && expenseSnap.data()?['status'] != 'voided') {
        transaction.update(purchaseExpenseRef, {
          'amount': newPurchaseAmount,
          'supplierName': sellerName.trim(),
          'date': Timestamp.fromDate(purchaseDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      final goatDelta = totalGoats - lot.totalGoats;

      if (goatDelta != 0) {
        transaction.set(
          _summaryDoc(farmId),
          {'wholesalePurchased': FieldValue.increment(goatDelta)},
          SetOptions(merge: true),
        );
      }
    }).timeout(_timeout);

    // Supplier name on the payments' Finance rows — metadata only, so a
    // failure here must never undo or fail the edit itself.
    if (previousSupplierName.trim() != sellerName.trim()) {
      for (final payment in payments) {
        if (payment.voided || payment.isLegacy) continue;

        try {
          await FinanceService.instance
              .expenseDocRef(farmId, _lotPaymentExpenseDocId(payment.id))
              .update({'supplierName': sellerName.trim()}).timeout(_timeout);
        } catch (_) {
          // Row missing or offline: harmless.
        }
      }
    }

    final updated = await getPurchase(farmId, lotDocId);

    if (updated == null) {
      throw StateError('The lot was saved but could not be read back.');
    }

    return updated;
  }

  // -----------------------------------------------------------------------
  // CANCEL DEAL (goats still at the supplier)
  // -----------------------------------------------------------------------

  /// Cancels a lot's deal while every goat is still at the supplier, and
  /// settles what was already paid.
  ///
  /// [refundAmount] is what the supplier actually handed back. The rest of
  /// the paid amount is the farm's loss:
  ///
  ///   loss = paid - refund        (paid 5000, refund 4500 -> loss 500)
  ///
  /// In ONE transaction:
  ///  * the lot is marked `dealCancelled` with the paid / refund / loss
  ///    figures. It then owns no goats, owes the supplier nothing and moves
  ///    to Completed;
  ///  * the refund is posted to Finance as income (Supplier Refund), while
  ///    the original supplier payments stay as the money that went out — so
  ///    the net cash effect is exactly the loss;
  ///  * the lot's audit-only Credit purchase row is voided (nothing was
  ///    bought);
  ///  * the dashboard's "wholesale purchased" counter drops by the lot's
  ///    goats.
  ///
  /// Refused when anything has been received, sold, moved or reserved
  /// ([TradingPurchase.canCancelDeal]), when the refund is more than what
  /// was paid, or when the deal is already cancelled.
  Future<TradingPurchase> cancelLotDeal({
    required String farmId,
    required String lotDocId,
    required double refundAmount,
    required String refundMethod,
    required DateTime date,
    String note = '',
  }) async {
    final refund = PurchaseCosting.round2(refundAmount);

    if (refund < 0) {
      throw ArgumentError('Refund cannot be negative.');
    }

    final method = _normalizePaymentMethod(refundMethod);
    final actor = await FirestoreService.instance.getCurrentActor();

    final lotRef = _tradingPurchases(farmId).doc(lotDocId);
    final purchaseExpenseRef = FinanceService.instance
        .expenseDocRef(farmId, _lotPurchaseExpenseDocId(lotDocId));

    late TradingPurchase lot;

    await _db.runTransaction((transaction) async {
      // All reads first.
      final snap = await transaction.get(lotRef);
      final expenseSnap = await transaction.get(purchaseExpenseRef);

      if (!snap.exists) {
        throw StateError('Lot $lotDocId was not found.');
      }

      lot = TradingPurchase.fromDoc(snap);

      if (!lot.isLot) {
        throw StateError(
          'Lot $lotDocId has not been converted to the lot format yet.',
        );
      }

      if (lot.dealCancelled) {
        throw StateError('This deal was already cancelled.');
      }

      if (!lot.canCancelDeal) {
        throw StateError(
          'A deal can only be cancelled while all goats are still at the '
              'supplier — nothing received, sold or moved yet.',
        );
      }

      final paid = lot.paidAmount;

      if (refund > paid + 0.005) {
        throw ArgumentError(
          'Refund cannot be more than the ${paid.toStringAsFixed(2)} paid '
              'to the supplier.',
        );
      }

      if (_dayOnly(date).isBefore(_dayOnly(lot.purchaseDate))) {
        throw ArgumentError('Cancellation date cannot be before the purchase.');
      }

      final rawLoss = PurchaseCosting.round2(paid - refund);
      final loss = rawLoss < 0 ? 0.0 : rawLoss;

      transaction.update(lotRef, {
        'dealCancelled': true,
        'cancelledAt': Timestamp.fromDate(date),
        'cancelPaidAmount': paid,
        'cancelRefundAmount': refund,
        'cancelLossAmount': loss,
        'cancelRefundMethod': method,
        'cancelNote': note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      FinanceService.instance.writeLotRefundIncomeInTransaction(
        transaction,
        farmId,
        docId: 'lotrefund_$lotDocId',
        amount: refund,
        paymentMethod: method,
        date: date,
        lotId: lot.id,
        lotLabel: lot.lotId,
        supplierName: lot.sellerName,
        note: note,
        actor: actor,
      );

      // Nothing was bought, so the audit-only purchase row stops counting.
      FinanceService.instance.voidExpenseInTransaction(
        transaction,
        farmId,
        expenseSnap: expenseSnap,
        title: 'Goat Purchase (${lot.lotId})',
        amount: lot.purchaseAmount,
        actor: actor,
      );

      transaction.set(
        _summaryDoc(farmId),
        {'wholesalePurchased': FieldValue.increment(-lot.totalGoats)},
        SetOptions(merge: true),
      );
    }).timeout(_timeout);

    FinanceService.instance.notifyExpenseVoided(
      farmId,
      title: 'Goat Purchase (${lot.lotId})',
      amount: lot.purchaseAmount,
      actor: actor,
    );

    FinanceService.instance.notifyLotRefundRecorded(
      farmId,
      lotLabel: lot.lotId,
      amount: refund,
      actor: actor,
    );

    final updated = await getPurchase(farmId, lotDocId);

    if (updated == null) {
      throw StateError('The deal was cancelled but the lot could not be read.');
    }

    return updated;
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

      final previousArrivalWeight = lot.totalWeightAfterArrival ?? 0;
      final newArrivalWeight = PurchaseCosting.round2(
        previousArrivalWeight + arrivalWeight,
      );

      // Receiving can happen in multiple batches. Never allow the cumulative
      // received weight to exceed the original purchase weight; otherwise a
      // partial receiving entry could create negative weight loss and corrupt
      // the lot's effective cost calculations.
      if (newArrivalWeight > lot.totalWeightAtPurchase + 0.005) {
        throw ArgumentError(
          'Cumulative arrival weight cannot be greater than the purchase '
              'weight (${lot.totalWeightAtPurchase.toStringAsFixed(2)}).',
        );
      }

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

      // A cancelled deal bought no goats.
      if (!purchase.dealCancelled) wholesalePurchased += purchase.totalGoats;
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