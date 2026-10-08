import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../models/activity_model.dart';
import '../models/customer_credit.dart';
import '../models/customer_model.dart';
import '../models/expense_categories.dart';
import '../models/goat_model.dart';
import '../models/lot_transfer_models.dart';
import '../models/palai_models.dart';
import '../models/sale_draft.dart';
import '../models/sale_model.dart';
import '../models/sale_settlement.dart';
import '../models/trading_purchase_model.dart';
import '../models/wait_delivery_group.dart';
import 'firestore_service.dart';
import 'goat_service.dart';
import 'health_reminder_scheduler.dart';

/// Handles the Trading module's Sell Goat flow (Phase 4: Feature 7 + 8).
///
/// Collection layout:
///
/// farms/{farmId}/sales/{saleId}
/// farms/{farmId}/customers/{customerId}      <- Sale-flow buyers
/// farms/{farmId}/tradingCounters/saleCounter
///
/// farms/{farmId}/palaiCustomers/{customerId} <- owned by the Customer
///                                                Palai module, read-only
///                                                from here. See
///                                                CustomerMatch below.
///
/// This class currently covers Section 1 (Data Model Additions) plus the
/// Task 2.2 customer-lookup groundwork. Branch save/transition logic
/// (Section 3) is added task-by-task on top of this.
class SalesService {
  SalesService._();

  static final SalesService instance = SalesService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _sales(
      String farmId,
      ) {
    return _farms().doc(farmId).collection('sales');
  }

  CollectionReference<Map<String, dynamic>> _customers(
      String farmId,
      ) {
    return _farms().doc(farmId).collection('customers');
  }

  /// Owned by the Customer Palai module. Read-only here — only used to
  /// power the merged lookup in [searchCustomerMatches] /
  /// [allCustomerMatchesStream], and to look a specific customer up when
  /// completing a Branch D (Transfer to Palai) handoff.
  CollectionReference<Map<String, dynamic>> _palaiCustomers(
      String farmId,
      ) {
    return _farms().doc(farmId).collection('palaiCustomers');
  }

  /// Also owned by the Customer Palai module — one customer's boarded
  /// goats (farms/{farmId}/palaiCustomers/{customerId}/goats). Written to
  /// only by [saveTransferToPalai], as part of the same transaction that
  /// creates the Palai customer and flips the Trading goat's status, so a
  /// transfer can never leave a goat checked into Trading's "In Customer
  /// Palai" state without an actual PalaiGoat record (or vice versa).
  /// Mirrors FirestoreService's own `_goats(farmId, customerId)` write
  /// shape exactly (see checkInGoat) — if that shape ever changes, this
  /// needs to change with it.
  CollectionReference<Map<String, dynamic>> _palaiGoats(
      String farmId,
      String customerId,
      ) {
    return _palaiCustomers(farmId).doc(customerId).collection('goats');
  }

  DocumentReference<Map<String, dynamic>> _saleCounterDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingCounters')
        .doc('saleCounter');
  }

  /// Owned by GoatService/Phase 3. Written to here (status transitions,
  /// saleId) rather than read as a stream — SalesService only ever
  /// updates specific goats it already has in the draft.
  CollectionReference<Map<String, dynamic>> _goats(
      String farmId,
      ) {
    return _farms().doc(farmId).collection('tradingGoats');
  }

  /// Owned by TradingService (farms/{farmId}/tradingPurchases). Read-only
  /// here — used only to look up a sold goat's originating purchase for
  /// its per-goat cost (see [_costOfGoatsInTransaction] /
  /// [TradingPurchase.costPerSurvivingGoat]), so profit can be computed
  /// at the moment a sale is finalized.
  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) {
    return _farms().doc(farmId).collection('tradingPurchases');
  }

  /// Same aggregate doc TradingService writes `totalStock` /
  /// `pendingRegistrations` to (farms/{farmId}/tradingSummary/dashboard).
  /// SalesService only ever touches `totalStock`, `totalSold`,
  /// `totalProfit`, `booking` and `waitOnDelivery` here — never
  /// `pendingRegistrations` or `wholesalePurchased`, which belong to the
  /// Purchase flow.
  DocumentReference<Map<String, dynamic>> _summaryDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingSummary')
        .doc('dashboard');
  }

  /// The Cost of Goods Sold for a set of goats — used alongside a sale's
  /// goat-only revenue to compute the profit added to
  /// [TradingSummary.totalProfit] the moment each sale/transfer is
  /// finalized (a goat's cost is fixed once its purchase's receiving is
  /// completed, so reading it at sale time is always safe/current).
  ///
  /// MUST be called during a transaction's read phase, before any write
  /// — it issues its own `transaction.get()` calls, and Firestore
  /// requires every read in a transaction to happen before any write.
  ///
  /// Reads each distinct originating purchase once (a multi-goat sale is
  /// very often all drawn from the same purchase batch) and sums that
  /// purchase's `costPerSurvivingGoat` once per goat drawn from it. A
  /// goat with a blank/missing `purchaseId`, or whose purchase doc can't
  /// be found (data from before Trading tracked this), contributes 0
  /// cost rather than failing the sale — understating profit for that
  /// one goat is far better than blocking a sale over it.
  Future<double> _costOfGoatsInTransaction({
    required Transaction transaction,
    required String farmId,
    required List<String> purchaseIds,
  }) async {
    final uniqueIds =
    purchaseIds.where((id) => id.trim().isNotEmpty).toSet();
    final costByPurchaseId = <String, double>{};

    for (final id in uniqueIds) {
      final snap = await transaction.get(_tradingPurchases(farmId).doc(id));

      if (snap.exists) {
        costByPurchaseId[id] =
            TradingPurchase.fromDoc(snap).costPerSurvivingGoat;
      }
    }

    return SaleDraft.round2(
      purchaseIds.fold<double>(
        0,
            (sum, id) => sum + (costByPurchaseId[id] ?? 0),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // SEQUENTIAL SALE ID
  // -----------------------------------------------------------------------

  /// IMPORTANT — Firestore transactions require EVERY read to happen
  /// before ANY write. Calling a `transaction.set/update` and only then
  /// reading the counter throws:
  ///   "Transactions require all reads to be executed before all writes."
  ///
  /// So sale-ID generation is split in two:
  ///   1. [_readNextSaleNumber]  -> READ  (call with the other reads)
  ///   2. [_writeSaleCounter]    -> WRITE (call with the other writes)

  /// READ step. Returns the next sequential sale number.
  Future<int> _readNextSaleNumber(
      Transaction transaction,
      String farmId,
      ) async {
    final counterSnap = await transaction.get(_saleCounterDoc(farmId));

    final lastValue =
        (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;

    return lastValue + 1;
  }

  /// WRITE step. Persists the number returned by [_readNextSaleNumber].
  void _writeSaleCounter(
      Transaction transaction,
      String farmId,
      int saleNumber,
      ) {
    transaction.set(
      _saleCounterDoc(farmId),
      {'lastValue': saleNumber},
      SetOptions(merge: true),
    );
  }

  String _formatSaleId(int saleNumber) =>
      'S-${saleNumber.toString().padLeft(4, '0')}';

  // -----------------------------------------------------------------------
  // FINANCE INTEGRATION — SOLD GOAT REVENUE
  // -----------------------------------------------------------------------
  //
  // Finance is cash-based: Net Cash Flow, the Cash / Online tracker and
  // every Palai customer payment all count money when it is RECEIVED. So
  // Sold Goat Revenue follows the customer's money too — one `transactions`
  // income doc per receipt, each with its own amount, date and payment
  // method — instead of booking the whole sale up front:
  //
  //   Deliver Now            -> the amount received at the sale
  //   Booking / Wait         -> the booking amount / advance, recorded at
  //                             Complete Delivery (the goat hasn't left
  //                             the farm before that)
  //   later balance payments -> one entry each, written by
  //                             receiveBalancePayment
  //
  // Every entry links back to the sale:
  //
  //   referenceType = tradingSale
  //   referenceId   = S-0001 (the saleId)
  //
  // and has a deterministic doc id (sale_S-0001_initial, sale_S-0001_pay1,
  // ...), so writing the same receipt twice overwrites the same doc — it
  // can never create a duplicate.
  //
  // Transportation is NEVER revenue: it is collected from the customer on
  // the bill but paid on to the transport team. Money counts as revenue
  // until Goat Sale + Holding Charges is covered and anything past that
  // is transportation (see Sale.revenueFromPaid). No transport expense
  // entry is created either.

  CollectionReference<Map<String, dynamic>> _transactions(String farmId) {
    return _farms().doc(farmId).collection('transactions');
  }

  CollectionReference<Map<String, dynamic>> _expenses(String farmId) {
    return _farms().doc(farmId).collection('expenses');
  }

  String _saleRevenueDocId(String saleId, String receiptKey) =>
      'sale_${saleId}_$receiptKey';

  Map<String, dynamic> _saleRevenueData({
    required String saleId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    required String customerName,
    required String note,

    // Lot sales only (additive; empty = field not written, so every
    // other flow's Finance rows are byte-for-byte what they were).
    String lotId = '',
    String customerId = '',
  }) {
    return {
      'amount': amount,
      'isIncome': true,
      'category': RevenueCategories.soldGoatRevenue,
      if (customerName.trim().isNotEmpty) 'customerName': customerName.trim(),
      'note': note,
      'paymentMethod': paymentMethod,
      'date': Timestamp.fromDate(date),
      'status': 'active',
      'referenceType': 'tradingSale',
      'referenceId': saleId,
      if (lotId.isNotEmpty) 'lotId': lotId,
      if (customerId.isNotEmpty) 'customerId': customerId,
    };
  }

  /// The payment method saved on a sale, or Other when none was saved.
  String _methodOrOther(String? method) {
    final trimmed = (method ?? '').trim();

    return trimmed.isEmpty ? FinancePaymentMethods.other : trimmed;
  }

  /// Payment status of a sale from what is still owed and what has been
  /// received so far.
  String _paymentStatusFor({
    required double balanceDue,
    required double paid,
  }) {
    if (SaleDraft.round2(balanceDue) <= 0) return Sale.paymentStatusPaid;

    return paid > 0
        ? Sale.paymentStatusPartial
        : Sale.paymentStatusPending;
  }

  // -----------------------------------------------------------------------
  // PAYMENT TAKEN WHEN A BOOKING / WAIT FOR DELIVERY IS COMPLETED
  // -----------------------------------------------------------------------
  //
  // At completion the final amount is known, so the person says how much
  // the customer pays right now and how:
  //
  //  * whole amount received -> Paid, nothing on credit
  //  * part / none received  -> Sell on Credit must be on; the unpaid part
  //    stays as the customer's outstanding balance (Finance > Customers on
  //    Credit) and is collected later with [receiveBalancePayment].
  //
  // The money received now is stored exactly like a later balance payment
  // (an entry in the sale's `payments` list plus a Sold Goat Revenue entry
  // in Finance), so the receipt, the balance and Finance all agree.

  /// Checks the payment given at completion and returns the amount that is
  /// actually being received now (0 when nothing more is owed).
  ///
  /// Throws a [StateError] with a message fit to show to the person.
  double _checkCompletionPayment({
    required double finalAmount,
    required double amountReceivedNow,
    required bool onCredit,
  }) {
    // Nothing left to pay (the advance / booking amount covered it all).
    if (finalAmount <= 0) return 0.0;

    final received = SaleDraft.round2(amountReceivedNow);

    if (received < 0) {
      throw StateError('The amount received cannot be negative.');
    }

    if (received > finalAmount) {
      throw StateError(
        'That is more than the final amount due '
            '(₹${finalAmount.toStringAsFixed(2)}).',
      );
    }

    if (!onCredit && received < finalAmount) {
      throw StateError(
        'The full ₹${finalAmount.toStringAsFixed(2)} must be received, '
            'or turn on Sell on Credit.',
      );
    }

    return received;
  }

  /// Sale-doc fields for the payment taken at completion.
  Map<String, dynamic> _completionPaymentFields({
    required List existingPayments,
    required double received,
    required String method,
    required DateTime when,
    required bool onCredit,
    required double finalAmount,
    required double paidBefore,
  }) {
    final payments = [...existingPayments];

    if (received > 0) {
      payments.add(
        SalePayment(
          amount: received,
          method: method,
          date: when,
          note: '',
        ).toMap(),
      );
    }

    return {
      'payments': payments,
      'onCredit': onCredit,
      'paymentStatus': _paymentStatusFor(
        balanceDue: finalAmount - received,
        paid: paidBefore + received,
      ),
    };
  }

  /// Writes the Sold Goat Revenue entry for the money received at
  /// completion, inside the same transaction. Only the part that covers
  /// goat sale + holding charges is revenue (see Sale.revenueFromPaid).
  void _writeCompletionRevenue({
    required Transaction transaction,
    required String farmId,
    required String saleId,
    required String customerName,
    required double received,
    required double paidBefore,
    required double revenueTotal,
    required int existingPaymentCount,
    required String method,
    required DateTime when,
    String lotId = '',
    String customerId = '',
  }) {
    if (received <= 0) return;

    final delta = SaleDraft.round2(
      Sale.revenueFromPaid(
        paid: paidBefore + received,
        revenueTotal: revenueTotal,
      ) -
          Sale.revenueFromPaid(
            paid: paidBefore,
            revenueTotal: revenueTotal,
          ),
    );

    if (delta <= 0) return;

    transaction.set(
      _transactions(farmId).doc(
        _saleRevenueDocId(saleId, 'pay${existingPaymentCount + 1}'),
      ),
      {
        ..._saleRevenueData(
          saleId: saleId,
          amount: delta,
          date: when,
          paymentMethod: method,
          customerName: customerName,
          note: 'Sold Goat Revenue — received at delivery, Sale $saleId',
          lotId: lotId,
          customerId: customerId,
        ),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  String _paymentMethodOrCash(String? method) {
    final trimmed = (method ?? '').trim();

    return trimmed.isEmpty ? FinancePaymentMethods.cash : trimmed;
  }

  // -----------------------------------------------------------------------
  // EXCESS ADVANCE AT DELIVERY
  // -----------------------------------------------------------------------
  //
  // When the customer paid more up front than the final bill comes to
  // (for example 85 kg x 620 = 52,700 against a 60,000 advance), the extra
  // 7,300 must not just vanish. The person chooses at delivery:
  //
  //  * Add to advance -> the amount goes onto the customer's profile as an
  //    advance balance (customers/{id}.advanceBalance, with an entry in
  //    customers/{id}/advanceEntries so it can be traced back to the sale).
  //  * Return to customer -> the refund is a Finance outflow
  //    (category Customer Refund, linked to the sale).
  //
  // Either way it is NEVER farm revenue: Sold Goat Revenue stays capped at
  // the discounted goat value (+ holding charges).
  //
  // Both are written inside the delivery's own transaction, with
  // deterministic doc ids, so a retried transaction cannot add the money
  // twice.

  /// READ step — call before the transaction's first write.
  ///
  /// Works out WHERE an "add to advance" excess should be stored:
  ///
  ///  * a Sale-flow buyer  -> farms/{farm}/customers/{id}
  ///  * a Palai customer   -> farms/{farm}/palaiCustomers/{id}
  ///  * a brand-new buyer  -> created inside this same transaction, so
  ///    there is nothing to read yet ([customerCreatedInTransaction]).
  ///
  /// Throws only when the sale really has no customer record anywhere to
  /// hold the money. For a refund, or when there is no excess, nothing is
  /// read and [_AdvanceTarget.none] is returned.
  Future<_AdvanceTarget> _checkExcessInTransaction({
    required Transaction transaction,
    required String farmId,
    required String customerId,
    required double excess,
    required ExcessAction action,
    bool customerCreatedInTransaction = false,
  }) async {
    if (excess <= 0 || action != ExcessAction.carryToAdvance) {
      return _AdvanceTarget.none;
    }

    // A new buyer is written by the same transaction, so the advance can
    // safely be put straight onto that new document.
    if (customerCreatedInTransaction) return _AdvanceTarget.trading;

    final id = customerId.trim();

    if (id.isNotEmpty) {
      final tradingSnap = await transaction.get(_customers(farmId).doc(id));

      if (tradingSnap.exists) return _AdvanceTarget.trading;

      final palaiSnap = await transaction.get(_palaiCustomers(farmId).doc(id));

      if (palaiSnap.exists) return _AdvanceTarget.palai;
    }

    throw StateError(
      'This sale has no customer record to hold the extra '
          '₹${excess.toStringAsFixed(2)} as an advance. Choose Return to '
          'customer instead.',
    );
  }

  /// WRITE step — records the extra money as chosen. Does nothing when
  /// there is no excess.
  ///
  /// Advance:
  ///   * Sale customer  -> customers/{id}.advanceBalance += excess
  ///   * Palai customer -> palaiCustomers/{id}.advanceAmount += excess
  ///   * both get an audit row at {customer}/advanceEntries/sale_{saleId}
  ///
  /// Refund:
  ///   * a Finance outflow (Customer Refund) linked to the sale.
  ///
  /// The money is NEVER written as revenue. Deterministic doc ids make a
  /// retried transaction idempotent.
  void _writeExcessInTransaction({
    required Transaction transaction,
    required String farmId,
    required String saleId,
    required String customerId,
    required String customerName,
    required double excess,
    required ExcessAction action,
    required String method,
    required DateTime when,
    _AdvanceTarget target = _AdvanceTarget.trading,
  }) {
    if (excess <= 0) return;

    if (action == ExcessAction.carryToAdvance) {
      final id = customerId.trim();

      if (id.isEmpty || target == _AdvanceTarget.none) {
        throw StateError(
          'No customer record is available to hold the extra advance.',
        );
      }

      final isPalai = target == _AdvanceTarget.palai;

      final customerRef = isPalai
          ? _palaiCustomers(farmId).doc(id)
          : _customers(farmId).doc(id);

      // set(merge) + increment works whether the document was just created
      // earlier in this transaction (new customer) or already existed.
      transaction.set(
        customerRef,
        {
          isPalai ? 'advanceAmount' : 'advanceBalance':
          FieldValue.increment(excess),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.set(
        customerRef.collection('advanceEntries').doc('sale_$saleId'),
        {
          'amount': excess,
          'type': 'credit',
          'source': 'tradingSale',
          'saleId': saleId,
          'customerId': id,
          if (customerName.trim().isNotEmpty)
            'customerName': customerName.trim(),
          'note': 'Extra amount left after delivery, Sale $saleId',
          'date': Timestamp.fromDate(when),
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      return;
    }

    // Finance reads outflows from the `expenses` collection (Expense list,
    // totals, Recent Transactions), so the refund must exist there too —
    // otherwise it would only be a hidden cash-flow row. Deterministic id,
    // linked to the mirrored `transactions` doc below, so a retry or a
    // later void finds the same two documents.
    transaction.set(
      _expenses(farmId).doc('refund_$saleId'),
      {
        'title': 'Customer Refund — Sale $saleId',
        'category': ExpenseCategories.customerRefund,
        'amount': excess,
        'paymentMethod': method,
        'note': 'Refund of extra amount at delivery, Sale $saleId',
        if (customerName.trim().isNotEmpty)
          'supplierName': customerName.trim(),
        'date': Timestamp.fromDate(when),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': '',
        'createdByName': 'System',
        'createdByRole': '',
        'status': 'active',
        'referenceType': 'customerRefund',
        'referenceId': saleId,
        'transactionId': 'sale_${saleId}_refund',
      },
    );

    transaction.set(
      _transactions(farmId).doc('sale_${saleId}_refund'),
      {
        'amount': excess,
        'isIncome': false,
        'category': ExpenseCategories.customerRefund,
        if (customerName.trim().isNotEmpty)
          'customerName': customerName.trim(),
        if (customerId.trim().isNotEmpty) 'customerId': customerId.trim(),
        'note': 'Refund of extra amount at delivery, Sale $saleId',
        'paymentMethod': method,
        'date': Timestamp.fromDate(when),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'referenceType': 'customerRefund',
        'referenceId': saleId,
      },
    );
  }

  /// The initial Sold Goat Revenue entry for a sale — whatever was
  /// already received toward the goat's price by the time the sale (or,
  /// for Booking/Wait for Delivery, its completed delivery) is written.
  /// Written inside the CALLER's transaction, alongside the sale doc
  /// itself, using the same 'initial' doc-id slot each of these flows
  /// has always used (see [_saleRevenueDocId]) — so a retried
  /// transaction can't create a duplicate, exactly like
  /// [_writeCompletionRevenue] already does for money received at
  /// completion.
  ///
  /// Previously each flow (saveDeliverNow, completeBookingDelivery,
  /// completeWaitForDeliveryPickup, saveTransferToPalai) wrote this via
  /// a separate awaited call to [_recordSaleReceiptRevenue] AFTER its
  /// own transaction had already committed. If that separate call
  /// failed — a dropped connection, the app being killed — the sale
  /// existed (goat already Sold / delivered / transferred) with no
  /// matching Sold Goat Revenue entry, and nothing retried it. Folding
  /// it into the same transaction makes the sale and its initial
  /// revenue entry succeed or fail together.
  void _writeInitialRevenueInTransaction({
    required Transaction transaction,
    required String farmId,
    required String saleId,
    required double paid,
    required double revenueTotal,
    required DateTime date,
    required String customerName,
    required String paymentMethod,
    String lotId = '',
    String customerId = '',
  }) {
    final rounded = SaleDraft.round2(
      Sale.revenueFromPaid(paid: paid, revenueTotal: revenueTotal),
    );

    if (rounded <= 0) return;

    transaction.set(
      _transactions(farmId).doc(_saleRevenueDocId(saleId, 'initial')),
      {
        ..._saleRevenueData(
          saleId: saleId,
          amount: rounded,
          date: date,
          paymentMethod: paymentMethod,
          customerName: customerName,
          note: 'Sold Goat Revenue — Sale $saleId',
          lotId: lotId,
          customerId: customerId,
        ),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  // -----------------------------------------------------------------------
  // BRANCH A — DELIVER NOW (Task 3.1)
  // -----------------------------------------------------------------------

  /// Saves a "Deliver Now" sale: goat(s) handed over today, paid on the
  /// spot (fully, partially, or not yet).
  ///
  /// Everything Firestore-side happens in one transaction — re-checking
  /// every goat is still sellable, writing the sale doc, flipping each
  /// goat to Sold, resolving/updating the customer, and updating the
  /// dashboard aggregate — so a partially-updated multi-goat sale (some
  /// goats Sold, others still Available) can't happen, per the plan's
  /// Section 5 status-consistency note.
  Future<String> saveDeliverNow({
    required String farmId,
    required SaleDraft draft,
  }) async {
    if (draft.selectedGoats.isEmpty) {
      throw StateError('Select at least one goat before saving.');
    }

    // Not `late final`: Firestore may re-run the transaction closure
    // on contention, which would assign this more than once.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Re-check every goat is still sellable. Sequential reads —
      //    a Firestore transaction's Dart API isn't safe to call
      //    concurrently against.
      // ---------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final snap = await transaction.get(_goats(farmId).doc(goat.id));

        if (!snap.exists) {
          throw StateError(
            'Goat ${goat.id} no longer exists.',
          );
        }

        final fresh = Goat.fromDoc(snap);

        if (!fresh.isSellable) {
          throw StateError(
            'Goat ${goat.id} is no longer available '
                '(now "${fresh.currentStatus}").',
          );
        }
      }

      // ---------------------------------------------------------------
      // 1a. Cost of Goods Sold for this sale's goats — must happen here,
      //     still in the read phase, before any of the writes below.
      // ---------------------------------------------------------------

      final costOfGoodsSold = await _costOfGoatsInTransaction(
        transaction: transaction,
        farmId: farmId,
        purchaseIds: draft.selectedGoats.map((g) => g.purchaseId).toList(),
      );

      // ---------------------------------------------------------------
      // 1b. Read the sale counter NOW, while we are still in the
      //     read phase. Every write below happens after this point.
      // ---------------------------------------------------------------

      final saleNumber = await _readNextSaleNumber(transaction, farmId);

      // ---------------------------------------------------------------
      // 2. Resolve the customer.
      //    - Brand new -> create a `customers` doc.
      //    - Existing Sale customer -> increment totalPurchases.
      //    - Existing Palai customer -> leave palaiCustomers untouched;
      //      just use their details on the sale record. They don't get
      //      a `totalPurchases` counter — that stat belongs to Sale
      //      customers, not Palai boarding customers.
      // ---------------------------------------------------------------

      String customerId = draft.customerId;

      if (draft.customerSource == null) {
        final customerRef = _customers(farmId).doc();

        final newCustomer = Customer(
          id: customerRef.id,
          name: draft.customerName.trim(),
          mobile: draft.mobile.trim(),
          address: draft.address.trim(),
          totalPurchases: 1,
        );

        transaction.set(customerRef, {
          ...newCustomer.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        customerId = customerRef.id;
      } else if (draft.customerSource == CustomerMatchSource.sale) {
        transaction.update(_customers(farmId).doc(draft.customerId), {
          'name': draft.customerName.trim(),
          'address': draft.address.trim(),
          'totalPurchases': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ---------------------------------------------------------------
      // 3. Create the sale doc.
      // ---------------------------------------------------------------

      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      final sale = Sale(
        id: saleId,
        goatIds: draft.goatIds,
        customerId: customerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice:
        draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        deliveryType: Sale.deliveryTypeDeliverNow,
        status: Sale.statusSold,
        transportCost:
        draft.transportCost > 0 ? draft.transportCost : null,
        amountReceived: draft.amountReceived,
        paymentMethod: draft.paymentMethod,
        paymentStatus: draft.paymentStatusDeliverNow,
        // Only a credit sale if something is really left unpaid.
        onCredit: draft.onCredit && draft.remainingBalanceDeliverNow > 0,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every goat to Sold.
      // ---------------------------------------------------------------

      // Gender is captured once at registration and is fixed by the time
      // a goat reaches this point — nothing to write back here.
      for (final goat in draft.selectedGoats) {
        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusSold,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
        });
      }

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate. Realized profit = the goat-only sale
      //    value (never transport) minus what those goats cost to
      //    acquire — recognized now, regardless of how much of the
      //    sale price has actually been collected (a credit sale still
      //    realizes its profit; the cash just hasn't arrived yet).
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock':
          FieldValue.increment(-draft.selectedGoats.length),
          'totalSold':
          FieldValue.increment(draft.selectedGoats.length),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(draft.totalSaleAmount - costOfGoodsSold),
          ),
        },
        SetOptions(merge: true),
      );

      // -----------------------------------------------------------------
      // FINANCE REVENUE — the goat is Sold immediately in this branch, so
      // the money received now is recorded right away, in this same
      // transaction. Only the part that covers the goat sale counts;
      // transport on the customer's bill is never revenue — see the
      // FINANCE INTEGRATION note above.
      // -----------------------------------------------------------------

      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: draft.amountReceived,
        revenueTotal: draft.totalSaleAmount,
        date: DateTime.now(),
        customerName: draft.customerName,
        paymentMethod: _methodOrOther(draft.paymentMethod),
      );
    }).timeout(_timeout * 2);

    _stopFarmHealthReminders(farmId, draft.selectedGoats);

    return saleId;
  }

  /// After supplier-held goats were handed over: a lot with nothing left
  /// at the supplier (and something already received) is fully received,
  /// same rule as a Deliver Now sale from the supplier.
  void _markSupplierEmptyLotsReceived(
      Transaction transaction,
      String farmId,
      Map<String, TradingPurchase> lotsBefore,
      Map<String, int> supplierDoneByLot,
      ) {
    supplierDoneByLot.forEach((lotDocId, done) {
      final lot = lotsBefore[lotDocId];
      if (lot == null) return;

      if (lot.supplierQty - done <= 0 && lot.receivedTotalQty > 0) {
        transaction.update(_tradingPurchases(farmId).doc(lotDocId), {
          'receivingStatus': 'completed',
        });
      }
    });
  }

  // -----------------------------------------------------------------------
  // SELL FROM LOT — DELIVER NOW
  // -----------------------------------------------------------------------

  /// Saves a Deliver Now sale made straight from a Purchase Lot.
  ///
  /// The goats are anonymous, so instead of flipping goat records this
  /// consumes lot quantity:
  ///   - source `supplier` -> `soldFromSupplierQty` (checked against
  ///     `supplierQty`); the goats never reach the farm.
  ///   - source `farm`     -> `soldFromFarmQty` (checked against
  ///     `farmAvailableQty`, i.e. not reserved by a booking).
  ///
  /// The quantity is validated INSIDE the transaction against the lot as it
  /// is right now, so two people selling at once can never oversell.
  /// Every read happens before the first write (Firestore requirement).
  ///
  /// Profit uses a cost-per-goat snapshot taken from the lot at sale time
  /// ([TradingPurchase.lotCostPerGoat]) and stored on the sale.
  Future<String> saveLotDeliverNow({
    required String farmId,
    required SaleDraft draft,
  }) async {
    if (!draft.isLotSale) {
      throw StateError('This sale is not linked to a lot.');
    }

    final quantity = draft.lotQuantity;

    if (quantity <= 0) {
      throw ArgumentError('Enter how many goats are being sold.');
    }

    final fromSupplier = draft.sourceLocation == Sale.sourceSupplier;

    if (!fromSupplier && draft.sourceLocation != Sale.sourceFarm) {
      throw ArgumentError('Choose where the goats are being sold from.');
    }

    if (draft.totalSellingWeight <= 0) {
      throw ArgumentError('Enter the total selling weight.');
    }

    if (draft.totalSaleAmount <= 0) {
      throw ArgumentError('Enter the selling price.');
    }

    // ---------------------------------------------------------------
    // EXCESS VALIDATION
    // ---------------------------------------------------------------
    //
    // For a Deliver Now lot sale, extra money is:
    //
    //   Amount Received - Customer Total
    //
    // When there is an excess, the UI must have already selected either:
    //
    //   1. Add to customer Advance
    //   2. Return to customer
    //
    // No choice is required when there is no excess.
    final excess = SaleDraft.round2(draft.extraReceivedDeliverNow);

    if (excess > 0 && draft.excessAction == null) {
      throw StateError(
        'The customer paid ₹${excess.toStringAsFixed(2)} more than '
            'the amount due. Choose whether to add the extra amount to '
            'the customer Advance or return it to the customer.',
      );
    }

    // Not `late final`: Firestore may re-run the closure on contention.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. READS — lot first, then the sale counter.
      //
      // IMPORTANT:
      // Every transaction read must happen before the first transaction
      // write. This is especially important for the excess-to-advance
      // customer check below.
      // ---------------------------------------------------------------

      final lotRef = _tradingPurchases(farmId).doc(draft.lotDocId);
      final lotSnap = await transaction.get(lotRef);

      if (!lotSnap.exists) {
        throw StateError('Lot ${draft.lotDocId} no longer exists.');
      }

      final lot = TradingPurchase.fromDoc(lotSnap);

      if (!lot.isLot) {
        throw StateError(
          'Lot ${draft.lotDocId} has not been converted to the lot format.',
        );
      }

      final available =
      fromSupplier ? lot.supplierAvailableQty : lot.farmAvailableQty;

      if (quantity > available) {
        throw StateError(
          fromSupplier
              ? 'Only $available goats are available at the supplier '
              '(booked goats are not counted).'
              : 'Only $available goats are available at the farm '
              '(booked goats are not counted).',
        );
      }

      final costPerGoat = lot.lotCostPerGoat;
      final costOfGoodsSold =
      SaleDraft.round2(costPerGoat * quantity);

      final saleNumber = await _readNextSaleNumber(
        transaction,
        farmId,
      );

      // ---------------------------------------------------------------
      // 1a. CUSTOMER READ / VALIDATION
      // ---------------------------------------------------------------
      //
      // Decides where an "add to advance" excess will be stored. A new
      // customer is created further down in THIS transaction, so it is
      // accepted here (nothing to read yet). A Sale customer or a Palai
      // customer is looked up in its own collection.
      //
      // This MUST stay before any write.
      final advanceTarget = await _checkExcessInTransaction(
        transaction: transaction,
        farmId: farmId,
        customerId: draft.customerId,
        excess: excess,
        action: draft.excessAction ?? ExcessAction.refundToCustomer,
        customerCreatedInTransaction: draft.customerSource == null,
      );

      // ---------------------------------------------------------------
      // 2. CUSTOMER
      // ---------------------------------------------------------------

      String customerId = draft.customerId;

      if (draft.customerSource == null) {
        final customerRef = _customers(farmId).doc();

        final newCustomer = Customer(
          id: customerRef.id,
          name: draft.customerName.trim(),
          mobile: draft.mobile.trim(),
          address: draft.address.trim(),
          totalPurchases: 1,
        );

        transaction.set(customerRef, {
          ...newCustomer.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        customerId = customerRef.id;
      } else if (draft.customerSource == CustomerMatchSource.sale) {
        transaction.update(
          _customers(farmId).doc(draft.customerId),
          {
            'name': draft.customerName.trim(),
            'address': draft.address.trim(),
            'totalPurchases': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      // ---------------------------------------------------------------
      // 3. SALE DOCUMENT
      // ---------------------------------------------------------------

      saleId = _formatSaleId(saleNumber);

      _writeSaleCounter(
        transaction,
        farmId,
        saleNumber,
      );

      final sale = Sale(
        id: saleId,
        goatIds: const [],
        lotDocId: draft.lotDocId,
        lotQuantity: quantity,
        sourceLocation: draft.sourceLocation,
        costPerGoatSnapshot: costPerGoat,
        customerId: customerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice:
        draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        deliveryType: Sale.deliveryTypeDeliverNow,
        status: Sale.statusSold,
        transportCost:
        draft.transportCost > 0 ? draft.transportCost : null,
        amountReceived: draft.amountReceived,
        paymentMethod: draft.paymentMethod,
        paymentStatus: draft.paymentStatusDeliverNow,

        // Only a credit sale if something is really left unpaid.
        onCredit:
        draft.onCredit &&
            draft.remainingBalanceDeliverNow > 0,
      );

      transaction.set(
        _sales(farmId).doc(saleId),
        {
          ...sale.toMap(),
          'createdAt': FieldValue.serverTimestamp(),

          // Store the chosen excess action/result directly on the sale
          // so the receipt/history can understand what happened.
          if (excess > 0 &&
              draft.excessAction == ExcessAction.carryToAdvance)
            'excessToAdvance': excess,

          if (excess > 0 &&
              draft.excessAction == ExcessAction.refundToCustomer)
            'excessRefunded': excess,
        },
      );

      // ---------------------------------------------------------------
      // 4. LOT QUANTITIES
      // ---------------------------------------------------------------
      //
      // `pendingCount` mirrors farmQty for lots, so a farm sale lowers
      // it too.
      //
      // Supplier sales never entered farm stock, therefore they only
      // increase soldFromSupplierQty.
      // ---------------------------------------------------------------

      final supplierAfter =
      fromSupplier
          ? lot.supplierQty - quantity
          : lot.supplierQty;

      final lotUpdate = <String, dynamic>{
        if (fromSupplier)
          'soldFromSupplierQty':
          FieldValue.increment(quantity)
        else
          ...{
            'soldFromFarmQty':
            FieldValue.increment(quantity),
            'pendingCount':
            FieldValue.increment(-quantity),
          },

        if (fromSupplier &&
            supplierAfter <= 0 &&
            lot.receivedTotalQty > 0)
          'receivingStatus': 'completed',

        'updatedAt': FieldValue.serverTimestamp(),
      };

      transaction.update(
        lotRef,
        lotUpdate,
      );

      // ---------------------------------------------------------------
      // 5. DASHBOARD AGGREGATE
      // ---------------------------------------------------------------
      //
      // Supplier-sale goats were never counted in farm stock.
      // Farm-sale goats were counted, so they reduce stock and pending
      // registrations.
      //
      // Profit is based on the full goat sale value minus the lot's
      // cost of goods sold. Transport and excess customer money are
      // NOT included as revenue.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          if (!fromSupplier)
            ...{
              'totalStock':
              FieldValue.increment(-quantity),
              'pendingRegistrations':
              FieldValue.increment(-quantity),
            },

          'totalSold':
          FieldValue.increment(quantity),

          'totalProfit':
          FieldValue.increment(
            SaleDraft.round2(
              draft.totalSaleAmount -
                  costOfGoodsSold,
            ),
          ),
        },
        SetOptions(merge: true),
      );

      // ---------------------------------------------------------------
      // 6. FINANCE — SOLD GOAT REVENUE
      // ---------------------------------------------------------------
      //
      // Only the amount received that belongs to the actual goat sale
      // is revenue.
      //
      // Transportation is deliberately excluded.
      //
      // IMPORTANT:
      // The excess is NOT passed separately into revenue. Therefore,
      // money carried to customer advance or refunded cannot be counted
      // twice as farm revenue.
      // ---------------------------------------------------------------

      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: draft.amountReceived,
        revenueTotal: draft.totalSaleAmount,
        date: DateTime.now(),
        customerName: draft.customerName,
        paymentMethod: _methodOrOther(
          draft.paymentMethod,
        ),
        lotId: draft.lotDocId,
        customerId: customerId,
      );

      // ---------------------------------------------------------------
      // 7. EXCESS MONEY
      // ---------------------------------------------------------------
      //
      // This is deliberately written AFTER all required reads and after
      // the sale/customer/lot writes have been prepared.
      //
      // carryToAdvance:
      //   customers/{customerId}.advanceBalance += excess
      //   customers/{customerId}/advanceEntries/sale_{saleId}
      //
      // refundToCustomer:
      //   transactions/sale_{saleId}_refund
      //   isIncome = false
      //   category = Customer Refund
      //
      // Both use deterministic document IDs, so a retried transaction
      // cannot create duplicate history rows.
      // ---------------------------------------------------------------

      _writeExcessInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        customerId: customerId,
        customerName: draft.customerName,
        excess: excess,
        action:
        draft.excessAction ??
            ExcessAction.refundToCustomer,
        method: _paymentMethodOrCash(
          draft.paymentMethod,
        ),
        when: DateTime.now(),
        target: advanceTarget,
      );
    }).timeout(_timeout * 2);

    return saleId;
  }

  // -----------------------------------------------------------------------
  // LOT BOOKING / WAIT FOR DELIVERY  (shared by Branch B and Branch C)
  // -----------------------------------------------------------------------

  /// Saves a Booking or Wait for Delivery sale made straight from a lot.
  ///
  /// Works for both sources:
  ///  - farm: the quantity goes into the lot's `reservedFarmQty` (which
  ///    lowers `farmAvailableQty` so nobody else can sell it);
  ///  - supplier: the quantity goes into `reservedSupplierQty` (which
  ///    lowers `supplierAvailableQty`, and keeps those goats out of
  ///    Receive Lot). They are handed over straight from the supplier
  ///    when the delivery is completed.
  ///
  /// The goats are held, not sold: nothing goes into `soldFrom*Qty`. `farmQty`, `pendingCount`,
  /// `totalStock` and `totalSold` are untouched until the delivery is
  /// completed. No revenue is written now either, exactly like the
  /// individual-goat flow.
  ///
  /// The quantity is validated inside the transaction against the lot as
  /// it is right now, so a stale screen cannot over-reserve. The cost per
  /// goat is snapshotted now and reused at completion.
  Future<String> _saveLotHold({
    required String farmId,
    required SaleDraft draft,
    required bool waitForDelivery,
  }) async {
    final quantity = draft.lotQuantity;

    if (quantity <= 0) {
      throw ArgumentError('Enter how many goats are being held.');
    }

    final fromSupplier = draft.sourceLocation == Sale.sourceSupplier;

    if (!fromSupplier && draft.sourceLocation != Sale.sourceFarm) {
      throw ArgumentError('Choose where the goats are being sold from.');
    }

    if (draft.totalSellingWeight <= 0) {
      throw ArgumentError('Enter the total selling weight.');
    }

    if (draft.totalSaleAmount <= 0) {
      throw ArgumentError('Enter the selling price.');
    }

    // Not `late final`: Firestore may re-run the closure on contention.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. READS — lot first, then the sale counter.
      // ---------------------------------------------------------------

      final lotRef = _tradingPurchases(farmId).doc(draft.lotDocId);
      final lotSnap = await transaction.get(lotRef);

      if (!lotSnap.exists) {
        throw StateError('Lot ${draft.lotDocId} no longer exists.');
      }

      final lot = TradingPurchase.fromDoc(lotSnap);

      if (!lot.isLot) {
        throw StateError(
          'Lot ${draft.lotDocId} has not been converted to the lot format.',
        );
      }

      final available =
      fromSupplier ? lot.supplierAvailableQty : lot.farmAvailableQty;

      if (quantity > available) {
        throw StateError(
          'Only $available goats are available '
              '${fromSupplier ? 'at the supplier' : 'at the farm'} '
              '(goats already booked are not counted).',
        );
      }

      final costPerGoat = lot.lotCostPerGoat;

      final saleNumber = await _readNextSaleNumber(transaction, farmId);

      // ---------------------------------------------------------------
      // 2. WRITES — customer (same three-way rule as saveDeliverNow).
      // ---------------------------------------------------------------

      String customerId = draft.customerId;

      if (draft.customerSource == null) {
        final customerRef = _customers(farmId).doc();

        final newCustomer = Customer(
          id: customerRef.id,
          name: draft.customerName.trim(),
          mobile: draft.mobile.trim(),
          address: draft.address.trim(),
          totalPurchases: 1,
        );

        transaction.set(customerRef, {
          ...newCustomer.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        customerId = customerRef.id;
      } else if (draft.customerSource == CustomerMatchSource.sale) {
        transaction.update(_customers(farmId).doc(draft.customerId), {
          'name': draft.customerName.trim(),
          'address': draft.address.trim(),
          'totalPurchases': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ---------------------------------------------------------------
      // 3. Sale doc — no goat ids, a lot reference and quantity instead.
      // ---------------------------------------------------------------

      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      final today = DateTime.now();

      final sale = Sale(
        id: saleId,
        goatIds: const [],
        lotDocId: draft.lotDocId,
        lotQuantity: quantity,
        sourceLocation: fromSupplier ? Sale.sourceSupplier : Sale.sourceFarm,
        costPerGoatSnapshot: costPerGoat,
        customerId: customerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice: draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        paymentMethod: draft.paymentMethod,
        onCredit: draft.onCredit,
        deliveryType: waitForDelivery
            ? Sale.deliveryTypeWaitForDelivery
            : Sale.deliveryTypeBooking,
        status: waitForDelivery
            ? Sale.statusWaitForDelivery
            : Sale.statusBooked,
        // Booking (Branch B)
        bookingAmount: waitForDelivery ? null : draft.bookingAmount,
        holdingChargePerDay:
        waitForDelivery ? null : draft.holdingChargePerDay,
        holdingStartDate: waitForDelivery
            ? null
            : DateTime(today.year, today.month, today.day),
        // Wait for Delivery (Branch C)
        bookingPricePerKg:
        waitForDelivery ? draft.bookingPricePerKg : null,
        bookingAdvanceAmount:
        waitForDelivery ? draft.bookingAdvanceAmount : null,
        bookingWeight: waitForDelivery ? draft.bookingWeightTotal : null,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Reserve the goats in the lot. NOT soldFromFarmQty.
      // ---------------------------------------------------------------

      transaction.update(lotRef, {
        (fromSupplier ? 'reservedSupplierQty' : 'reservedFarmQty'):
        FieldValue.increment(quantity),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate: only the Booking / Wait on Delivery
      //    counter moves. The goats are still on the farm, so totalStock
      //    and totalSold wait for the completed delivery.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          (waitForDelivery ? 'waitOnDelivery' : 'booking'):
          FieldValue.increment(quantity),
        },
        SetOptions(merge: true),
      );

      // Booking money is actually received on the booking day, so record
      // that receipt in Finance now. Wait for Delivery is deliberately left
      // alone here because its final goat value is not known until pickup.
      // Recording its advance as goat revenue before pickup could overstate
      // revenue if the pickup weight changes the final goat value.
      if (!waitForDelivery) {
        _writeInitialRevenueInTransaction(
          transaction: transaction,
          farmId: farmId,
          saleId: saleId,
          paid: draft.bookingAmount ?? 0,
          revenueTotal: draft.totalSaleAmount,
          date: DateTime.now(),
          customerName: draft.customerName,
          paymentMethod: _methodOrOther(draft.paymentMethod),
          lotId: draft.lotDocId,
          customerId: customerId,
        );
      }
    }).timeout(_timeout * 2);

    return saleId;
  }

  // -----------------------------------------------------------------------
  // BRANCH B — BOOKING / HOLDING (Task 3.2)
  // -----------------------------------------------------------------------

  /// Saves a "Booking / Holding" sale: goat(s) kept here after an initial
  /// payment, picked up later. Only the creation form — the "Complete
  /// Delivery" action ([completeBookingDelivery]) later works out
  /// `Goat Sale Amount + Holding Charges - Amount Already Paid`.
  ///
  /// No transportation charge is taken, and no holding days or holding
  /// charges are stored now: the start day is recorded, and the days are
  /// counted up to the delivery day when the delivery is completed. Any
  /// booking money received now is recorded in Finance on the booking date;
  /// the later delivery payment is recorded when the delivery is completed.
  ///
  /// Same re-check-then-write-in-one-transaction shape as
  /// [saveDeliverNow], for the same status-consistency reason.
  Future<String> saveBooking({
    required String farmId,
    required SaleDraft draft,
  }) async {
    if (draft.isLotSale) {
      return _saveLotHold(
        farmId: farmId,
        draft: draft,
        waitForDelivery: false,
      );
    }

    if (draft.selectedGoats.isEmpty) {
      throw StateError('Select at least one goat before saving.');
    }

    // Not `late final`: Firestore may re-run the transaction closure
    // on contention, which would assign this more than once.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Re-check every goat is still sellable.
      // ---------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final snap = await transaction.get(_goats(farmId).doc(goat.id));

        if (!snap.exists) {
          throw StateError(
            'Goat ${goat.id} no longer exists.',
          );
        }

        final fresh = Goat.fromDoc(snap);

        if (!fresh.isSellable) {
          throw StateError(
            'Goat ${goat.id} is no longer available '
                '(now "${fresh.currentStatus}").',
          );
        }
      }

      // ---------------------------------------------------------------
      // 1b. Read the sale counter NOW, while we are still in the
      //     read phase. Every write below happens after this point.
      // ---------------------------------------------------------------

      final saleNumber = await _readNextSaleNumber(transaction, farmId);

      // ---------------------------------------------------------------
      // 2. Resolve the customer. Same three-way rule as saveDeliverNow.
      // ---------------------------------------------------------------

      String customerId = draft.customerId;

      if (draft.customerSource == null) {
        final customerRef = _customers(farmId).doc();

        final newCustomer = Customer(
          id: customerRef.id,
          name: draft.customerName.trim(),
          mobile: draft.mobile.trim(),
          address: draft.address.trim(),
          totalPurchases: 1,
        );

        transaction.set(customerRef, {
          ...newCustomer.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        customerId = customerRef.id;
      } else if (draft.customerSource == CustomerMatchSource.sale) {
        transaction.update(_customers(farmId).doc(draft.customerId), {
          'name': draft.customerName.trim(),
          'address': draft.address.trim(),
          'totalPurchases': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ---------------------------------------------------------------
      // 3. Create the sale doc.
      // ---------------------------------------------------------------

      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      final sale = Sale(
        id: saleId,
        goatIds: draft.goatIds,
        customerId: customerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice:
        draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        deliveryType: Sale.deliveryTypeBooking,
        status: Sale.statusBooked,
        bookingAmount: draft.bookingAmount,
        paymentMethod: draft.paymentMethod,
        onCredit: draft.onCredit,
        holdingChargePerDay: draft.holdingChargePerDay,
        // Holding starts today (the booking day) and counts this day.
        // The days and the charges are worked out when the delivery is
        // completed, not now.
        holdingStartDate: DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        ),
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every goat to Booked.
      // ---------------------------------------------------------------

      // Gender is captured once at registration and is fixed by the time
      // a goat reaches this point — nothing to write back here.
      for (final goat in draft.selectedGoats) {
        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusBooked,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
        });
      }

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate. Booked goats haven't left the farm yet,
      //    so totalStock is untouched — only `booking` moves. totalSold
      //    likewise doesn't move until the eventual Complete Delivery.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'booking': FieldValue.increment(draft.selectedGoats.length),
        },
        SetOptions(merge: true),
      );

      // The booking payment is real money received today. Record it in
      // Finance on the booking date rather than waiting for pickup.
      // Holding charges are not included here because they are only known
      // when the booking is completed.
      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: draft.bookingAmount ?? 0,
        revenueTotal: draft.totalSaleAmount,
        date: DateTime.now(),
        customerName: draft.customerName,
        paymentMethod: _methodOrOther(draft.paymentMethod),
      );
    }).timeout(_timeout * 2);

    _stopFarmHealthReminders(farmId, draft.selectedGoats);

    return saleId;
  }

  // -----------------------------------------------------------------------
  // BRANCH C — WAIT FOR DELIVERY (Task 3.3)
  // -----------------------------------------------------------------------

  /// Saves a "Wait for Delivery" sale: price/kg and an advance are fixed
  /// now, at today's weight; the goat is weighed again and handed over
  /// later. Only the creation form — the "Complete Delivery" action
  /// (`Final Price = Pickup Weight x Booking Price/KG - advance`, always
  /// using [Sale.bookingPricePerKg], never the market rate on pickup day)
  /// is [completeWaitForDeliveryPickup].
  ///
  /// No transportation charge is taken here — it is not known until the
  /// goat is picked up, so it is entered in
  /// [completeWaitForDeliveryPickup]. No receipt is generated here either:
  /// the sale record is only kept. The receipt is generated when the
  /// delivery is completed.
  Future<String> saveWaitForDelivery({
    required String farmId,
    required SaleDraft draft,
  }) async {
    if (draft.isLotSale) {
      return _saveLotHold(
        farmId: farmId,
        draft: draft,
        waitForDelivery: true,
      );
    }

    if (draft.selectedGoats.isEmpty) {
      throw StateError('Select at least one goat before saving.');
    }

    // Not `late final`: Firestore may re-run the transaction closure
    // on contention, which would assign this more than once.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Re-check every goat is still sellable.
      // ---------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final snap = await transaction.get(_goats(farmId).doc(goat.id));

        if (!snap.exists) {
          throw StateError(
            'Goat ${goat.id} no longer exists.',
          );
        }

        final fresh = Goat.fromDoc(snap);

        if (!fresh.isSellable) {
          throw StateError(
            'Goat ${goat.id} is no longer available '
                '(now "${fresh.currentStatus}").',
          );
        }
      }

      // ---------------------------------------------------------------
      // 1b. Read the sale counter NOW, while we are still in the
      //     read phase. Every write below happens after this point.
      // ---------------------------------------------------------------

      final saleNumber = await _readNextSaleNumber(transaction, farmId);

      // ---------------------------------------------------------------
      // 2. Resolve the customer. Same three-way rule as saveDeliverNow.
      // ---------------------------------------------------------------

      String customerId = draft.customerId;

      if (draft.customerSource == null) {
        final customerRef = _customers(farmId).doc();

        final newCustomer = Customer(
          id: customerRef.id,
          name: draft.customerName.trim(),
          mobile: draft.mobile.trim(),
          address: draft.address.trim(),
          totalPurchases: 1,
        );

        transaction.set(customerRef, {
          ...newCustomer.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        customerId = customerRef.id;
      } else if (draft.customerSource == CustomerMatchSource.sale) {
        transaction.update(_customers(farmId).doc(draft.customerId), {
          'name': draft.customerName.trim(),
          'address': draft.address.trim(),
          'totalPurchases': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ---------------------------------------------------------------
      // 3. Create the sale doc.
      // ---------------------------------------------------------------

      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      final sale = Sale(
        id: saleId,
        goatIds: draft.goatIds,
        customerId: customerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice:
        draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        deliveryType: Sale.deliveryTypeWaitForDelivery,
        status: Sale.statusWaitForDelivery,
        bookingPricePerKg: draft.bookingPricePerKg,
        bookingAdvanceAmount: draft.bookingAdvanceAmount,
        paymentMethod: draft.paymentMethod,
        onCredit: draft.onCredit,
        bookingWeight: draft.bookingWeightTotal,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every goat to Wait on Delivery.
      // ---------------------------------------------------------------

      // Gender is captured once at registration and is fixed by the time
      // a goat reaches this point — nothing to write back here.
      for (final goat in draft.selectedGoats) {
        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusWaitOnDelivery,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
          // The Hoof Cutting cadence of the farm's Health Reminder
          // Settings is counted from this day.
          'waitOnDeliveryAt': FieldValue.serverTimestamp(),
        });
      }

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate. Same reasoning as Branch B: the goat is
      //    still on the farm, so totalStock stays put — only
      //    `waitOnDelivery` moves.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'waitOnDelivery':
          FieldValue.increment(draft.selectedGoats.length),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout * 2);

    // The goats are still on the farm until they are picked up, so they
    // follow the farm's Health Reminder Settings (Profile > Health
    // Reminder Settings) like Own Palai goats do: their vaccination /
    // hoof cutting / hair trimming dates are armed now, and raise
    // notifications when due. Not awaited — the sale is already saved and
    // this never throws.
    for (final goat in draft.selectedGoats) {
      unawaited(
        HealthReminderScheduler.instance.syncOwnPalaiFarmReminders(
          farmId,
          goatId: goat.id,
          force: true,
        ),
      );
    }

    return saleId;
  }

  // -----------------------------------------------------------------------
  // BRANCH D — TRANSFER TO PALAI (Task 3.4)
  // -----------------------------------------------------------------------

  /// Saves a "Transfer to Palai" sale: the customer keeps the goat
  /// boarded here instead of taking it away, so ongoing billing/health
  /// tracking hands off to the Customer Palai module.
  ///
  /// Fully atomic: creating (or reusing) the Palai customer, the sale
  /// doc, the Trading goat status flips, the stock decrement, the
  /// initial Sold Goat Revenue entry, and each goat's Palai check-in all
  /// happen inside ONE Firestore transaction. Previously this was three
  /// separate steps — addCustomer, then a Trading transaction, then a
  /// per-goat checkInGoat loop after that — so a failure partway through
  /// could leave an orphaned Palai customer (created but never used), or
  /// goats Trading had already marked "In Customer Palai" with no actual
  /// PalaiGoat record behind them (or a partial set of them, if the loop
  /// died on goat 2 of 3). Folding every write into one transaction
  /// makes the whole transfer succeed or fail as a unit — Firestore
  /// itself guarantees that, the same way it already guarantees the sale
  /// doc, goat status updates and stock decrement can't partially apply.
  ///
  /// The customer/goat writes below deliberately mirror
  /// FirestoreService.addCustomer's and .checkInGoat's write shape
  /// exactly (same toMap(), same `farmId` denormalization) rather than
  /// calling those methods, since a Firestore transaction can only
  /// contain its own reads/writes — if either of those methods' shape
  /// changes, this needs to change with it.
  Future<String> saveTransferToPalai({
    required String farmId,
    required SaleDraft draft,
  }) async {
    if (draft.selectedGoats.isEmpty) {
      throw StateError('Select at least one goat before saving.');
    }

    // ONE DEBT, ONE RECORD.
    //
    // Whatever the customer has not paid toward the goat's price stays on
    // the SALE (see Sale.billBalanceDue) and is deliberately NOT copied
    // into the Palai customer's `pendingAmount`. Copying it would create
    // a second figure for the same debt, and every later payment would
    // have to be applied to both to keep them equal. Instead the Palai
    // side reads the debt from the sale (Goat sale credit on the customer
    // profile) and Palai payments that go beyond the Palai outstanding
    // are applied to the sale (see [settleSalesInTransaction]), so the two
    // views can never disagree and the monthly Palai bill never carries a
    // Trading debt inside it.

    final createNewCustomer =
        draft.customerSource != CustomerMatchSource.palai;

    // Doc refs with a client-generated ID cost no network round trip and
    // need no read, so these can be created before the transaction and
    // written inside it.
    final palaiCustomerRef = createNewCustomer
        ? _palaiCustomers(farmId).doc()
        : _palaiCustomers(farmId).doc(draft.customerId);
    final palaiCustomerId = palaiCustomerRef.id;

    // Not `late final`: Firestore may re-run the transaction closure
    // on contention, which would assign this more than once.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      for (final goat in draft.selectedGoats) {
        final snap = await transaction.get(_goats(farmId).doc(goat.id));

        if (!snap.exists) {
          throw StateError(
            'Goat ${goat.id} no longer exists.',
          );
        }

        final fresh = Goat.fromDoc(snap);

        if (!fresh.isSellable) {
          throw StateError(
            'Goat ${goat.id} is no longer available '
                '(now "${fresh.currentStatus}").',
          );
        }
      }

      // Cost of Goods Sold — must happen here, still in the read phase,
      // before any of the writes below.
      final costOfGoodsSold = await _costOfGoatsInTransaction(
        transaction: transaction,
        farmId: farmId,
        purchaseIds: draft.selectedGoats.map((g) => g.purchaseId).toList(),
      );

      final saleNumber = await _readNextSaleNumber(transaction, farmId);
      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      if (createNewCustomer) {
        final palaiCustomer = PalaiCustomer(
          id: '',
          name: draft.customerName.trim(),
          mobileNumber: draft.mobile.trim(),
          address: draft.address.trim(),
          package: draft.palaiPackage.trim(),
          joiningDate: draft.transferDate ?? DateTime.now(),
          pendingAmount: 0,
          price: draft.monthlyPalaiCharge,
        );

        transaction.set(palaiCustomerRef, palaiCustomer.toMap());
      }

      final sale = Sale(
        id: saleId,
        goatIds: draft.goatIds,
        customerId: palaiCustomerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice:
        draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        deliveryType: Sale.deliveryTypePalai,
        status: Sale.statusTransferredToPalai,
        transferDate: draft.transferDate,
        palaiPackage: draft.palaiPackage.trim(),
        monthlyPalaiCharge: draft.monthlyPalaiCharge,
        palaiCustomerId: palaiCustomerId,
        // What was paid toward the goat's price, and how. Anything short
        // of the total is the customer's outstanding balance.
        amountReceived: draft.palaiAmountReceived,
        paymentMethod: draft.paymentMethod,
        paymentStatus: draft.paymentStatusPalai,
        onCredit: draft.onCredit && draft.remainingBalancePalai > 0,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Gender is captured once at registration and is fixed by the time
      // a goat reaches this point — nothing to write back here.
      for (final goat in draft.selectedGoats) {
        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusInCustomerPalai,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
        });
      }

      // Not counted in totalSold — this isn't a cash sale, it's
      // boarding revenue going forward. The goat's price is still
      // realized profit though, same as any other sale: the goat-only
      // price (never the monthly Palai charge, which the Palai module
      // bills separately over time) minus what it cost to acquire.
      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock':
          FieldValue.increment(-draft.selectedGoats.length),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(draft.totalSaleAmount - costOfGoodsSold),
          ),
        },
        SetOptions(merge: true),
      );

      // -----------------------------------------------------------------
      // FINANCE REVENUE — the money received toward the goat's price is
      // Sold Goat Revenue, recorded in the same transaction as the sale.
      // Whatever is left unpaid is the customer's credit and is recorded
      // as it is collected (SalesService.receiveBalancePayment). The
      // monthly Palai charge is not part of this: the Palai module bills
      // it later.
      // -----------------------------------------------------------------

      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: draft.palaiAmountReceived,
        revenueTotal: draft.totalSaleAmount,
        date: DateTime.now(),
        customerName: draft.customerName,
        paymentMethod: _methodOrOther(draft.paymentMethod),
      );

      // -----------------------------------------------------------------
      // Check each goat into the Customer Palai module, in the same
      // transaction as the Trading-side status flip above — a goat can
      // never end up marked "In Customer Palai" in Trading without a
      // matching PalaiGoat record, or vice versa.
      // -----------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final gender = draft.genderFor(goat);

        final palaiGoat = PalaiGoat(
          id: '',
          customerId: palaiCustomerId,
          breed: goat.breed,
          gender: gender.isEmpty ? 'Male' : gender,
          weightAtCheckIn: draft.weightFor(goat),
          heightAtCheckIn: goat.height,
          lengthAtCheckIn: goat.length,
          ageMonthsAtCheckIn: goat.currentAgeMonths,
          healthStatus:
          goat.healthStatus.isEmpty ? 'Healthy' : goat.healthStatus,
          checkInDate: draft.transferDate ?? DateTime.now(),
          farmArrivalDate: draft.transferDate,
          monthlyPackage: draft.palaiPackage.trim(),
          pricing: draft.monthlyPalaiCharge,
          notes: 'Transferred from Trading sale $saleId.',
        );

        // Denormalize farmId, exactly as checkInGoat does — required by
        // the collectionGroup('goats') security rule / query.
        final data = palaiGoat.toMap()..['farmId'] = farmId;

        transaction.set(_palaiGoats(farmId, palaiCustomerId).doc(), data);
      }
    }).timeout(_timeout * 2);

    _stopFarmHealthReminders(farmId, draft.selectedGoats);

    return saleId;
  }

  // -----------------------------------------------------------------------
  // LOT -> CUSTOMER PALAI TRANSFER (Step 6)
  // -----------------------------------------------------------------------

  /// Transfers goats from a Purchase Lot straight into a customer's Palai
  /// as a sale.
  ///
  /// The lot's goats are anonymous, so this is where they get individual
  /// records: each one in [goats] is created directly with status "In
  /// Customer Palai" (GoatService.writeLotTransferInTransaction) and
  /// checked into the Palai customer, all in ONE transaction together with
  /// the sale, the Palai customer (new or existing), the lot's quantity
  /// update, the dashboard counters and the first Sold Goat Revenue
  /// entry. Either all of it happens or none of it does.
  ///
  /// The resulting sale is an ordinary goat sale (goatIds = the new goat
  /// ids), so receipts, the Palai module and customer lists treat it
  /// exactly like a goat that was sold with "Transfer to Palai" from Goat
  /// Stock. It is NOT a lot sale ([Sale.isLotSale] is false): the goats
  /// exist individually from this moment.
  ///
  /// Only goats at the farm and not reserved can be transferred — the lot
  /// is re-read inside the transaction, so a stale screen cannot
  /// over-transfer. Cost of goods is the lot's cost per goat at this
  /// moment, snapshotted on the sale and never re-read.
  ///
  /// [draft] must carry the customer, pricing and Palai fields; its
  /// goat count must equal [goats].length.
  Future<String> saveLotTransferToCustomerPalai({
    required String farmId,
    required String lotDocId,
    required List<LotTransferGoat> goats,
    required SaleDraft draft,
  }) async {
    if (goats.isEmpty) {
      throw StateError('Enter how many goats to transfer.');
    }

    if (draft.isLotSale) {
      throw StateError(
        'A Palai transfer creates individual goats, so it cannot be saved '
            'as a lot sale.',
      );
    }

    if (draft.saleGoatCount != goats.length) {
      throw StateError(
        'The sale was priced for ${draft.saleGoatCount} goats but '
            '${goats.length} are being transferred. Go back and check the '
            'goat details.',
      );
    }

    if (draft.totalSaleAmount <= 0) {
      throw ArgumentError('Enter the selling price.');
    }

    // Same "one debt, one record" rule as saveTransferToPalai: whatever
    // is unpaid stays on the SALE and is not copied into the Palai
    // customer's pendingAmount.

    final createNewCustomer =
        draft.customerSource != CustomerMatchSource.palai;

    final palaiCustomerRef = createNewCustomer
        ? _palaiCustomers(farmId).doc()
        : _palaiCustomers(farmId).doc(draft.customerId);
    final palaiCustomerId = palaiCustomerRef.id;

    // Not `late final`: Firestore may re-run the closure on contention.
    String saleId = '';

    await _db.runTransaction((transaction) async {
      // -----------------------------------------------------------------
      // 1. READS — lot + goat counter (inside prepare), then the sale
      //    counter. No write may happen before this block ends.
      // -----------------------------------------------------------------

      final prep = await GoatService.instance.prepareLotTransferInTransaction(
        transaction,
        farmId: farmId,
        lotDocId: lotDocId,
        goats: goats,
      );

      final saleNumber = await _readNextSaleNumber(transaction, farmId);

      final costPerGoat = prep.lot.lotCostPerGoat;
      final costOfGoodsSold = SaleDraft.round2(costPerGoat * goats.length);

      // -----------------------------------------------------------------
      // 2. WRITES
      // -----------------------------------------------------------------

      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      // The new goats, moved out of the lot: status In Customer Palai,
      // linked to this sale. Also lowers pendingRegistrations.
      final created = GoatService.instance.writeLotTransferInTransaction(
        transaction,
        farmId: farmId,
        prep: prep,
        goats: goats,
        status: Goat.statusInCustomerPalai,
        saleId: saleId,
      );

      if (createNewCustomer) {
        final palaiCustomer = PalaiCustomer(
          id: '',
          name: draft.customerName.trim(),
          mobileNumber: draft.mobile.trim(),
          address: draft.address.trim(),
          package: draft.palaiPackage.trim(),
          joiningDate: draft.transferDate ?? DateTime.now(),
          pendingAmount: 0,
          price: draft.monthlyPalaiCharge,
        );

        transaction.set(palaiCustomerRef, palaiCustomer.toMap());
      }

      final sale = Sale(
        id: saleId,
        goatIds: created.map((g) => g.id).toList(),
        costPerGoatSnapshot: costPerGoat,
        customerId: palaiCustomerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.effectivePricePerKg,
        pricingMode: draft.pricingMode,
        fixedSalePrice: draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        discount: draft.appliedDiscount,
        deliveryType: Sale.deliveryTypePalai,
        status: Sale.statusTransferredToPalai,
        transferDate: draft.transferDate,
        palaiPackage: draft.palaiPackage.trim(),
        monthlyPalaiCharge: draft.monthlyPalaiCharge,
        palaiCustomerId: palaiCustomerId,
        amountReceived: draft.palaiAmountReceived,
        paymentMethod: draft.paymentMethod,
        paymentStatus: draft.paymentStatusPalai,
        onCredit: draft.onCredit && draft.remainingBalancePalai > 0,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // The goats leave the farm's stock (they board here for the
      // customer now) and the goat price is realized profit, exactly as
      // in saveTransferToPalai. Not counted in totalSold.
      // pendingRegistrations was already lowered by the transfer write.
      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock': FieldValue.increment(-goats.length),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(draft.totalSaleAmount - costOfGoodsSold),
          ),
        },
        SetOptions(merge: true),
      );

      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: draft.palaiAmountReceived,
        revenueTotal: draft.totalSaleAmount,
        date: DateTime.now(),
        customerName: draft.customerName,
        paymentMethod: _methodOrOther(draft.paymentMethod),
        lotId: lotDocId,
        customerId: palaiCustomerId,
      );

      // Check every goat into the Customer Palai module in the same
      // transaction, so a goat can never be "In Customer Palai" here
      // without its PalaiGoat record, or the other way round.
      for (final goat in created) {
        final palaiGoat = PalaiGoat(
          id: '',
          customerId: palaiCustomerId,
          breed: goat.breed,
          gender: goat.gender.isEmpty ? 'Male' : goat.gender,
          weightAtCheckIn: goat.weight,
          heightAtCheckIn: goat.height,
          lengthAtCheckIn: goat.length,
          ageMonthsAtCheckIn: goat.currentAgeMonths,
          healthStatus:
          goat.healthStatus.isEmpty ? 'Healthy' : goat.healthStatus,
          checkInDate: draft.transferDate ?? DateTime.now(),
          farmArrivalDate: draft.transferDate,
          monthlyPackage: draft.palaiPackage.trim(),
          pricing: draft.monthlyPalaiCharge,
          notes: 'Transferred from ${prep.lot.lotId} (sale $saleId).',
        );

        // farmId is denormalized, exactly as checkInGoat does — required
        // by the collectionGroup('goats') security rule / query.
        final data = palaiGoat.toMap()..['farmId'] = farmId;

        transaction.set(_palaiGoats(farmId, palaiCustomerId).doc(), data);
      }
    }).timeout(_timeout * 2);

    return saleId;
  }

  /// Available stock, Own Palai and Wait on Delivery goats follow the
  /// farm's Health Reminder Settings. A goat that is sold outright, booked
  /// or transferred to a customer's Palai is no longer on that schedule,
  /// so its on-device vaccination / hoof / hair alarms are switched off.
  /// Not awaited; never throws.
  void _stopFarmHealthReminders(String farmId, Iterable<Goat> goats) {
    for (final goat in goats) {
      unawaited(
        HealthReminderScheduler.instance.cancelForTradingGoat(
          farmId: farmId,
          goatId: goat.id,
        ),
      );
    }
  }

  // -----------------------------------------------------------------------
  // SALE LOOKUP (Phase 5 groundwork — Complete Delivery needs the sale
  // doc a Booked/Wait-for-Delivery goat is linked to via Goat.saleId)
  // -----------------------------------------------------------------------

  /// Reads one sale.
  ///
  /// Firestore reports `unavailable` (or a timeout) when the phone's
  /// connection to it blips for a moment — typically right after a save,
  /// when the receipt is opened straight away. Its own error message says
  /// to retry with a backoff, so that is what happens here: up to three
  /// more attempts, waiting a little longer each time. If the server
  /// still can't be reached, the local cache is tried as a last resort
  /// before the error is given up on.
  Future<Sale?> getSale(String farmId, String saleId) async {
    final ref = _sales(farmId).doc(saleId);

    const backoff = [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
      Duration(milliseconds: 3000),
    ];

    Object? lastError;
    DocumentSnapshot<Map<String, dynamic>>? doc;

    for (var attempt = 0; attempt <= backoff.length; attempt++) {
      try {
        doc = await ref.get().timeout(_timeout);
        break;
      } on FirebaseException catch (e) {
        if (e.code != 'unavailable' && e.code != 'deadline-exceeded') {
          rethrow;
        }

        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      }

      if (attempt < backoff.length) {
        await Future<void>.delayed(backoff[attempt]);
      }
    }

    if (doc == null) {
      try {
        final cached = await ref.get(
          const GetOptions(source: Source.cache),
        );

        if (cached.exists) {
          doc = cached;
        }
      } catch (_) {
        // Nothing cached — fall through and report the real error.
      }
    }

    if (doc == null) {
      throw lastError ?? StateError('Could not load sale $saleId.');
    }

    if (!doc.exists) {
      return null;
    }

    return Sale.fromDoc(doc);
  }

  // -----------------------------------------------------------------------
  // COMPLETE DELIVERY — BOOKING (Phase 5, Section 1)
  // -----------------------------------------------------------------------

  /// Finishes a Branch B (Booking/Holding) sale once the customer
  /// actually picks the goat up.
  ///
  /// The holding days and holding charges are worked out HERE, when the
  /// delivery is completed — not at booking time. The days run from the
  /// booking day to [deliveryDate], both days counted (booked 20 Sept,
  /// delivered 23 Sept = 20, 21, 22, 23 = 4 days):
  ///
  ///   Holding Charges = holding days x Daily Charge
  ///   Final Amount    = Goat Sale Amount + Holding Charges
  ///                     + Transportation - Booking Amount already paid
  ///
  /// [transportCharges] is the optional transportation charge collected
  /// from the customer at delivery (0 when there is none). It is added to
  /// what the customer owes and saved as [Sale.transportCost] so the bill
  /// shows it, but it is never farm revenue: it is paid on to the
  /// transport team, so the Sold Goat Revenue written here stays capped at
  /// Goat Sale + Holding Charges. The stored
  /// [Sale.finalAmountAfterHolding] is what the customer still owes at
  /// pickup.
  ///
  /// If the booking amount already paid is MORE than the final bill, the
  /// extra is kept as the customer's advance or refunded, as chosen with
  /// [excessAction] (see EXCESS ADVANCE AT DELIVERY above). A discount, if
  /// there is one, was given when the booking was made and is already part
  /// of [Sale.totalSaleAmount].
  ///
  /// [discount] is an EXTRA discount given at delivery, on top of any
  /// booking discount. It comes off the goat value only (never holding
  /// charges or transport). When it is above 0 the sale's [Sale.discount]
  /// and [Sale.totalSaleAmount] are updated so the bill shows it, and if the
  /// booking amount had already been counted as Sold Goat Revenue for more
  /// than the discounted sale now allows, that revenue entry is lowered to
  /// match (see "REVENUE CORRECTION" below).
  ///
  /// [holdingChargePerDay] lets the owner EDIT the daily holding charge at
  /// delivery (for example to give a customer a cheaper rate, or to waive
  /// it with 0). When null, the rate agreed at booking
  /// ([Sale.holdingChargePerDay]) is used. When given, it replaces the
  /// booking rate for the whole holding period and is saved on the sale so
  /// the bill shows the rate that was actually charged.
  ///
  /// Same reads-then-writes transaction shape as the Phase 4 branch
  /// save methods, extended to also verify the sale is still in the
  /// state this action expects before touching anything.
  Future<void> completeBookingDelivery({
    required String farmId,
    required String saleId,
    required DateTime deliveryDate,
    double transportCharges = 0,
    double amountReceivedNow = 0,
    String? paymentMethod,
    bool onCredit = false,
    ExcessAction excessAction = ExcessAction.carryToAdvance,
    double discount = 0,
    double? holdingChargePerDay,
  }) {
    // A single booking is just a group of one: same code path, no
    // transfers.
    return completeBookingDeliveryGroup(
      farmId: farmId,
      deliveryDate: deliveryDate,
      paymentMethod: paymentMethod,
      items: [
        BookingPickupInput(
          saleId: saleId,
          transportCharges: transportCharges,
          amountReceivedNow: amountReceivedNow,
          onCredit: onCredit,
          excessAction: excessAction,
          discount: discount,
          holdingChargePerDay: holdingChargePerDay,
        ),
      ],
    );
  }

  /// Completes several Booking / Holding sales of ONE customer as one
  /// settlement, in ONE Firestore transaction, against one shared
  /// [deliveryDate].
  ///
  /// Each booking is settled exactly as in [completeBookingDelivery]
  /// (holding charges for the days held, delivery discount, transport,
  /// revenue correction). On top of that, [WaitDeliveryAllocator] nets the
  /// bookings against each other: the extra booking amount of a booking
  /// whose booking amount is more than its final bill pays the due of a
  /// booking whose booking amount is less. See
  /// [completeWaitForDeliveryGroup] for how the donor and the receiver are
  /// recorded — it is the same here:
  ///
  ///  * Donor: `excessTransferred` / `excessTransferredTo`; the bill reads
  ///    paid in full; nothing goes to the advance or a refund for that part.
  ///  * Receiver: a payment line "Adjusted from S-xxxx extra" (no new cash
  ///    entry) plus a Sold Goat Revenue entry for the part of the
  ///    transferred money that is revenue (capped at the goat sale +
  ///    holding charges; transport is never revenue), on a fixed id so a
  ///    retry cannot count it twice.
  ///
  /// All reads happen before any write, and a failure on any booking
  /// leaves every booking in the group untouched.
  ///
  /// [items] must be in the order the bookings are shown on screen: that
  /// is the order dues are covered in.
  Future<void> completeBookingDeliveryGroup({
    required String farmId,
    required DateTime deliveryDate,
    required List<BookingPickupInput> items,
    String? paymentMethod,
  }) async {
    if (items.isEmpty) return;

    final seenIds = <String>{};

    for (final item in items) {
      if (!seenIds.add(item.saleId)) {
        throw StateError('Booking ${item.saleId} is listed twice.');
      }

      if (item.transportCharges < 0) {
        throw StateError('The transportation charge cannot be negative.');
      }

      if (item.holdingChargePerDay != null && item.holdingChargePerDay! < 0) {
        throw StateError('The holding charge per day cannot be negative.');
      }

      if (item.discount < 0) {
        throw StateError('The discount cannot be negative.');
      }

      if (item.pickupWeight != null && item.pickupWeight! <= 0) {
        throw StateError('Pickup weight must be greater than zero.');
      }
    }

    final method = _paymentMethodOrCash(paymentMethod);
    final now = DateTime.now();

    final deliveryDay = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
    );

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Reads first — a Firestore transaction requires every read
      //    to happen before any write, across ALL bookings.
      // ---------------------------------------------------------------

      final plans = <_BookingPickupPlan>[];

      for (final item in items) {
        final saleId = item.saleId;
        final saleRef = _sales(farmId).doc(saleId);
        final saleSnap = await transaction.get(saleRef);

        if (!saleSnap.exists) {
          throw StateError('Sale $saleId no longer exists.');
        }

        final sale = Sale.fromDoc(saleSnap);

        if (!sale.isBooking) {
          throw StateError('Sale $saleId is not a Booking sale.');
        }

        if (sale.status != Sale.statusBooked) {
          throw StateError(
            'Sale $saleId has already been completed or is in an '
                'unexpected state ("${sale.status}").',
          );
        }

        DocumentReference<Map<String, dynamic>>? lotRef;
        TradingPurchase? lotBefore;

        if (sale.isLotSale) {
          lotRef = _tradingPurchases(farmId).doc(sale.lotDocId);
          final lotSnap = await transaction.get(lotRef);

          if (!lotSnap.exists) {
            throw StateError('Lot ${sale.lotDocId} no longer exists.');
          }

          final lot = TradingPurchase.fromDoc(lotSnap);

          final reservedHere = sale.sourceLocation == Sale.sourceSupplier
              ? lot.reservedSupplierQty
              : lot.reservedFarmQty;

          if (reservedHere < sale.lotQuantity) {
            throw StateError(
              'Lot ${sale.lotDocId} has only $reservedHere goats '
                  'reserved but this sale holds ${sale.lotQuantity}. '
                  'Please check the lot before completing.',
            );
          }

          lotBefore = lot;

          if (sale.costPerGoatSnapshot == null) {
            throw StateError(
              'Sale $saleId has no stored cost per goat, so its profit '
                  'cannot be worked out.',
            );
          }
        }

        final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];

        for (final goatId in sale.goatIds) {
          goatSnaps.add(
            await transaction.get(_goats(farmId).doc(goatId)),
          );
        }

        // Cost of Goods Sold, still in the read phase.
        final eligiblePurchaseIds = <String>[];

        for (final snap in goatSnaps) {
          if (!snap.exists) continue;

          final goat = Goat.fromDoc(snap);

          if (goat.currentStatus != Goat.statusBooked ||
              goat.saleId != saleId) {
            continue;
          }

          eligiblePurchaseIds.add(goat.purchaseId);
        }

        final costOfGoodsSold = sale.isLotSale
            ? SaleDraft.round2(
          (sale.costPerGoatSnapshot ?? 0) * sale.lotQuantity,
        )
            : await _costOfGoatsInTransaction(
          transaction: transaction,
          farmId: farmId,
          purchaseIds: eligiblePurchaseIds,
        );

        // The booking on its own: holding days counted inclusively.
        final holdingStart = sale.holdingStart;
        final startDay = DateTime(
          holdingStart.year,
          holdingStart.month,
          holdingStart.day,
        );

        if (deliveryDay.isBefore(startDay)) {
          throw StateError(
            'The delivery date cannot be before the day the holding '
                'started (${startDay.day}/${startDay.month}/${startDay.year}).',
          );
        }

        final holdingDays = Sale.holdingDaysBetween(startDay, deliveryDay);

        // The rate edited at delivery wins; otherwise the booking's rate.
        final holdingRate = SaleDraft.round2(
          item.holdingChargePerDay ?? sale.holdingChargePerDay ?? 0,
        );
        final holdingCharges = SaleDraft.round2(holdingDays * holdingRate);
        final bookingAmount = sale.bookingAmount ?? 0;

        // Goat Sale + Holding Charges + Transportation, against the
        // booking amount already paid.
        //
        // WEIGHT-BASED PRICE: with a pickup weight the goat value is the
        // agreed amount x pickup weight / booked weight
        // ([Sale.goatValueAtWeight]) less the discount given at booking.
        // Without one (older screens) it is the booked amount, already
        // after any booking discount.
        final pickupWeight = item.pickupWeight;
        final goatAmountAtPickup = pickupWeight == null
            ? null
            : sale.goatValueAtWeight(pickupWeight);

        final settlement = SaleSettlement.fromAmount(
          goatAmount: sale.bookingGoatAmountAt(pickupWeight),
          discount: item.discount,
          holdingCharges: holdingCharges,
          transportCharge: SaleDraft.round2(item.transportCharges),
          advancePaid: bookingAmount,
          excessAction: item.excessAction,
        );

        // REVENUE CORRECTION — read step (see completeBookingDelivery).
        final initialRevenueRef = _transactions(farmId)
            .doc(_saleRevenueDocId(saleId, 'initial'));
        DocumentSnapshot<Map<String, dynamic>>? initialRevenueSnap;

        // A delivery discount, or a lower pickup weight, can bring the
        // sale below what the booking amount was counted as.
        if (settlement.appliedDiscount > 0 || goatAmountAtPickup != null) {
          initialRevenueSnap = await transaction.get(initialRevenueRef);
        }

        plans.add(
          _BookingPickupPlan(
            item: item,
            saleRef: saleRef,
            sale: sale,
            saleSnap: saleSnap,
            lotRef: lotRef,
            lotBefore: lotBefore,
            goatSnaps: goatSnaps,
            costOfGoodsSold: costOfGoodsSold,
            bookingAmount: bookingAmount,
            startDay: startDay,
            holdingDays: holdingDays,
            holdingRate: holdingRate,
            holdingCharges: holdingCharges,
            settlement: settlement,
            initialRevenueRef: initialRevenueRef,
            initialRevenueSnap: initialRevenueSnap,
            pickupWeight: pickupWeight,
            goatAmountAtPickup: goatAmountAtPickup,
          ),
        );
      }

      // ---------------------------------------------------------------
      // 2. Net the bookings against each other. Same function the screen
      //    shows, so what was previewed is what gets saved.
      // ---------------------------------------------------------------

      final allocation = WaitDeliveryAllocator.allocate([
        for (final plan in plans)
          WaitDeliveryBill(
            saleId: plan.item.saleId,
            payable: plan.settlement.payable,
            advancePaid: plan.bookingAmount,
          ),
      ]);

      // ---------------------------------------------------------------
      // 3. Remaining reads and the payment check, per booking, still
      //    before the first write.
      // ---------------------------------------------------------------

      for (final plan in plans) {
        final alloc = allocation.bySale[plan.item.saleId]!;

        plan.alloc = alloc;
        plan.transfersIn = allocation.transfersInto(plan.item.saleId);
        plan.transfersOut = allocation.transfersFrom(plan.item.saleId);

        plan.advanceTarget = await _checkExcessInTransaction(
          transaction: transaction,
          farmId: farmId,
          customerId: plan.sale.customerId,
          excess: alloc.leftoverExcess,
          action: plan.item.excessAction,
        );

        plan.received = _checkCompletionPayment(
          finalAmount: alloc.toCollect,
          amountReceivedNow: plan.item.amountReceivedNow,
          onCredit: plan.item.onCredit,
        );
      }

      // ---------------------------------------------------------------
      // 4. Writes — one booking after the other, same transaction.
      // ---------------------------------------------------------------

      var totalMovedGoats = 0;
      var totalLotGoats = 0;

      // Goats handed over straight from the supplier (held there by a
      // supplier-sourced booking): never farm stock.
      var supplierLotGoats = 0;
      final supplierDoneByLot = <String, int>{};
      final lotsBefore = <String, TradingPurchase>{};
      var totalProfit = 0.0;

      for (final plan in plans) {
        final item = plan.item;
        final sale = plan.sale;
        final saleId = item.saleId;
        final alloc = plan.alloc;
        final settlement = plan.settlement;

        final transport = SaleDraft.round2(item.transportCharges);
        final finalAmount = alloc.toCollect;
        final leftover = alloc.leftoverExcess;
        final deliveryDiscount = settlement.appliedDiscount;

        final existingPayments =
            (plan.saleSnap.data()?['payments'] as List?) ?? const [];

        final transferLines = <Map<String, dynamic>>[
          for (final t in plan.transfersIn)
            SalePayment(
              amount: t.amount,
              method: method,
              date: now,
              note: '${SalePayment.bookingTransferPrefix}'
                  '${t.fromSaleId} extra',
            ).toMap(),
        ];

        final paidBefore =
        SaleDraft.round2(plan.bookingAmount + alloc.takenIn);

        final givenOut = alloc.givenOut;
        final givenTo = plan.transfersOut
            .map((t) => t.toSaleId)
            .toSet()
            .join(', ');

        transaction.update(plan.saleRef, {
          'status': Sale.statusDeliveryCompleted,
          'holdingStartDate': Timestamp.fromDate(plan.startDay),
          'holdingEndDate': Timestamp.fromDate(deliveryDay),
          'actualHoldingDays': plan.holdingDays,
          'totalHoldingCharges': plan.holdingCharges,
          // The daily rate actually charged (it may have been edited at
          // delivery), so the bill and the numbers always agree.
          'holdingChargePerDay': plan.holdingRate,
          'transportCost': transport > 0 ? transport : FieldValue.delete(),
          'finalAmountAfterHolding': finalAmount,
          if (deliveryDiscount > 0)
            'discount':
            SaleDraft.round2(sale.appliedDiscount + deliveryDiscount),
          if (deliveryDiscount > 0 || plan.goatAmountAtPickup != null)
            'totalSaleAmount': settlement.netGoatAmount,
          if (plan.pickupWeight != null) ...{
            'pickupWeight': plan.pickupWeight,
            'goatAmountAtPickup': plan.goatAmountAtPickup,
          },
          'excessToAdvance':
          item.excessAction == ExcessAction.carryToAdvance &&
              leftover > 0
              ? leftover
              : FieldValue.delete(),
          'excessRefunded':
          item.excessAction == ExcessAction.refundToCustomer &&
              leftover > 0
              ? leftover
              : FieldValue.delete(),
          'excessTransferred':
          givenOut > 0 ? givenOut : FieldValue.delete(),
          'excessTransferredTo':
          givenOut > 0 ? givenTo : FieldValue.delete(),
          ..._completionPaymentFields(
            existingPayments: [...existingPayments, ...transferLines],
            received: plan.received,
            method: method,
            when: now,
            onCredit: finalAmount > 0 && item.onCredit,
            finalAmount: finalAmount,
            paidBefore: paidBefore,
          ),
          'deliveryCompletedAt': FieldValue.serverTimestamp(),
        });

        // REVENUE CORRECTION — write step.
        final initialSnap = plan.initialRevenueSnap;

        if (initialSnap != null && initialSnap.exists) {
          final recorded = SaleDraft.round2(
            ((initialSnap.data()?['amount']) as num?)?.toDouble() ?? 0,
          );
          final allowed = SaleDraft.round2(
            Sale.revenueFromPaid(
              paid: plan.bookingAmount,
              revenueTotal: settlement.netRevenue,
            ),
          );

          if (recorded > allowed) {
            if (allowed <= 0) {
              transaction.delete(plan.initialRevenueRef);
            } else {
              transaction.update(plan.initialRevenueRef, {
                'amount': allowed,
                'note': 'Sold Goat Revenue — Sale $saleId '
                    '(lowered to the delivered goat value)',
              });
            }
          }
        }

        // Extra booking amount moved in from other bookings: the part of
        // it that is revenue is recorded now, on this booking, on a fixed
        // id (the slot of its first transfer line), so a retry cannot
        // count it twice. The donor's own revenue is untouched, so the
        // money is counted once.
        if (alloc.takenIn > 0) {
          final transferRevenue = SaleDraft.round2(
            Sale.revenueFromPaid(
              paid: paidBefore,
              revenueTotal: settlement.netRevenue,
            ) -
                Sale.revenueFromPaid(
                  paid: plan.bookingAmount,
                  revenueTotal: settlement.netRevenue,
                ),
          );

          if (transferRevenue > 0) {
            transaction.set(
              _transactions(farmId).doc(
                _saleRevenueDocId(
                  saleId,
                  'pay${existingPayments.length + 1}',
                ),
              ),
              {
                ..._saleRevenueData(
                  saleId: saleId,
                  amount: transferRevenue,
                  date: now,
                  paymentMethod: method,
                  customerName: sale.customerName,
                  note: 'Sold Goat Revenue — extra booking amount '
                      'adjusted from another booking, Sale $saleId',
                  lotId: sale.lotDocId,
                  customerId: sale.isLotSale ? sale.customerId : '',
                ),
                'createdAt': FieldValue.serverTimestamp(),
              },
            );
          }
        }

        _writeCompletionRevenue(
          transaction: transaction,
          farmId: farmId,
          saleId: saleId,
          customerName: sale.customerName,
          received: plan.received,
          paidBefore: paidBefore,
          revenueTotal: settlement.netRevenue,
          existingPaymentCount:
          existingPayments.length + transferLines.length,
          method: method,
          when: now,
          lotId: sale.lotDocId,
          customerId: sale.isLotSale ? sale.customerId : '',
        );

        _writeExcessInTransaction(
          transaction: transaction,
          farmId: farmId,
          saleId: saleId,
          customerId: sale.customerId,
          customerName: sale.customerName,
          excess: leftover,
          action: item.excessAction,
          method: method,
          when: now,
          target: plan.advanceTarget,
        );

        // Flip every still-Booked goat in this sale to Sold.
        var movedGoats = sale.isLotSale ? sale.lotQuantity : 0;

        if (sale.isLotSale) {
          if (sale.sourceLocation == Sale.sourceSupplier) {
            // Held at the supplier: handed over straight from there. These
            // goats were never farm stock, so totalStock /
            // pendingRegistrations do not move for them.
            transaction.update(plan.lotRef!, {
              'reservedSupplierQty': FieldValue.increment(-sale.lotQuantity),
              'soldFromSupplierQty': FieldValue.increment(sale.lotQuantity),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            supplierLotGoats += sale.lotQuantity;
            supplierDoneByLot[sale.lotDocId] =
                (supplierDoneByLot[sale.lotDocId] ?? 0) + sale.lotQuantity;
            if (plan.lotBefore != null) {
              lotsBefore[sale.lotDocId] ??= plan.lotBefore!;
            }
          } else {
            // The reserved goats are now sold: reserved -> sold, and the
            // farm stock (mirrored by pendingCount) falls now, not at
            // booking.
            transaction.update(plan.lotRef!, {
              'reservedFarmQty': FieldValue.increment(-sale.lotQuantity),
              'soldFromFarmQty': FieldValue.increment(sale.lotQuantity),
              'pendingCount': FieldValue.increment(-sale.lotQuantity),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            totalLotGoats += sale.lotQuantity;
          }
        }

        for (final snap in plan.goatSnaps) {
          if (!snap.exists) continue;

          final goat = Goat.fromDoc(snap);

          if (goat.currentStatus != Goat.statusBooked ||
              goat.saleId != saleId) {
            continue;
          }

          transaction.update(snap.reference, {
            'currentStatus': Goat.statusSold,
          });

          movedGoats++;
        }

        totalMovedGoats += movedGoats;
        totalProfit += SaleDraft.round2(
          settlement.netGoatAmount +
              plan.holdingCharges -
              plan.costOfGoodsSold,
        );
      }

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate, written once for the whole group:
      //    Booking count decreases, Total Sold increases, totalStock
      //    decreases (the deferred decrement). Realized profit = goat-only
      //    sale value plus holding charges (never transport) minus what
      //    the goats cost to acquire.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'booking': FieldValue.increment(-totalMovedGoats),
          'totalSold': FieldValue.increment(totalMovedGoats),
          'totalStock':
          FieldValue.increment(-(totalMovedGoats - supplierLotGoats)),
          if (totalLotGoats > 0)
            'pendingRegistrations': FieldValue.increment(-totalLotGoats),
          'totalProfit': FieldValue.increment(SaleDraft.round2(totalProfit)),
        },
        SetOptions(merge: true),
      );
      _markSupplierEmptyLotsReceived(
        transaction,
        farmId,
        lotsBefore,
        supplierDoneByLot,
      );
    }).timeout(_timeout * 2);
  }

  // -----------------------------------------------------------------------
  // COMPLETE DELIVERY — WAIT FOR DELIVERY (Phase 5, Section 2)
  // -----------------------------------------------------------------------

  /// Finishes a Branch C (Wait for Delivery) sale once the customer
  /// actually picks the goat up.
  ///
  /// The rate is always the one fixed at booking time
  /// ([Sale.bookingPricePerKg]) — this method never reads
  /// [Sale.sellingPricePerKg] (today's rate) for the settlement, per
  /// the plan's explicit warning in Section 5 that re-pricing at the
  /// current market rate is the easiest mistake to make here. Only
  /// the weight is taken fresh, at pickup:
  ///
  ///   Final Price = Pickup Weight x Booking Price/Kg
  ///                 + Transportation - Advance Paid
  ///
  /// A Fixed Price sale ([Sale.isFixedPrice]) is converted to a locked
  /// rate per KG and repriced the same way:
  ///
  ///   Final Price = Fixed Price x Pickup Weight / Booked Weight
  ///                 + Transportation - Advance Paid
  ///
  /// The goat value comes from [Sale.goatValueAtWeight] and is saved on
  /// the sale as `goatAmountAtPickup`.
  ///
  /// [transportCharges] is the optional transportation charge collected
  /// from the customer at pickup (0 when there is none). It is added to
  /// what the customer owes, and saved on the sale as
  /// [Sale.transportCost] so the bill shows it, but it is never farm
  /// revenue: it is paid on to the transport team, so the Sold Goat
  /// Revenue written here is still capped at the goat value.
  ///
  /// The stored [Sale.finalPriceAfterPickup] is what the customer still
  /// owes at pickup.
  ///
  /// [discount] is taken off the goat value (never off transport). When it
  /// is null the discount given at booking time ([Sale.discount]) stands.
  /// Revenue and profit use the discounted goat value.
  ///
  /// If the advance already paid is MORE than the final bill, the extra is
  /// kept as the customer's advance or refunded, as chosen with
  /// [excessAction] (see EXCESS ADVANCE AT DELIVERY above). Example: 85 kg
  /// x 620 = 52,700 against a 60,000 advance leaves 7,300 extra.
  ///
  /// Worked example from the plan (Section 2, Task 2.2): 34kg booked,
  /// 38kg at delivery, ₹520/kg fixed, ₹5,000 advance -> ₹14,760
  /// remaining. 38 x 520 = 19,760; 19,760 - 5,000 = 14,760. ✓
  Future<void> completeWaitForDeliveryPickup({
    required String farmId,
    required String saleId,
    required double pickupWeight,
    double transportCharges = 0,
    double amountReceivedNow = 0,
    String? paymentMethod,
    bool onCredit = false,
    double? discount,
    ExcessAction excessAction = ExcessAction.carryToAdvance,
  }) {
    // A single booking is just a group of one: same code path, no
    // transfers.
    return completeWaitForDeliveryGroup(
      farmId: farmId,
      paymentMethod: paymentMethod,
      items: [
        WaitPickupInput(
          saleId: saleId,
          pickupWeight: pickupWeight,
          transportCharges: transportCharges,
          amountReceivedNow: amountReceivedNow,
          onCredit: onCredit,
          discount: discount,
          excessAction: excessAction,
        ),
      ],
    );
  }

  /// Completes several Wait for Delivery bookings of ONE customer as one
  /// settlement, in ONE Firestore transaction.
  ///
  /// Each booking is settled exactly as in [completeWaitForDeliveryPickup]
  /// (booking-time rate or fixed price, discount, transport, revenue capped
  /// at the goat value). On top of that, [WaitDeliveryAllocator] nets the
  /// bookings against each other: the extra advance of a booking whose
  /// advance is more than its bill pays the due of a booking whose advance
  /// is less.
  ///
  ///  * Donor: `excessTransferred` / `excessTransferredTo` record the money
  ///    moved. It is counted in the bill's excess figure, so the bill reads
  ///    paid in full. Nothing goes to the customer's advance and nothing is
  ///    refunded for this part.
  ///  * Receiver: a payment line "Adjusted from S-xxxx extra" is added to
  ///    its `payments` (see [SalePayment.isBookingTransfer]). It counts as
  ///    paid, but creates no new cash entry — the money was already
  ///    received as the donor's advance.
  ///  * Revenue: still capped at each booking's goat value; transport is
  ///    never revenue. The transferred money becomes revenue on the
  ///    receiver (its "initial" Sold Goat Revenue is written on advance +
  ///    transferred amount), never on the donor, so it is counted once.
  ///  * Only the extra left after every due is covered goes to the
  ///    advance / refund choice ([WaitPickupInput.excessAction]).
  ///
  /// All reads happen before any write. Because everything is one
  /// transaction, a failure on any booking leaves every booking in the
  /// group untouched.
  ///
  /// [items] must be in the order the bookings are shown on screen: that
  /// is the order dues are covered in.
  ///
  /// Throws a [StateError] with a message fit to show to the person.
  Future<void> completeWaitForDeliveryGroup({
    required String farmId,
    required List<WaitPickupInput> items,
    String? paymentMethod,
  }) async {
    if (items.isEmpty) return;

    final seenIds = <String>{};

    for (final item in items) {
      if (!seenIds.add(item.saleId)) {
        throw StateError('Booking ${item.saleId} is listed twice.');
      }

      if (item.pickupWeight <= 0) {
        throw StateError('Pickup weight must be greater than zero.');
      }

      if (item.discount != null && item.discount! < 0) {
        throw StateError('The discount cannot be negative.');
      }

      if (item.transportCharges < 0) {
        throw StateError('The transportation charge cannot be negative.');
      }
    }

    final method = _paymentMethodOrCash(paymentMethod);
    final now = DateTime.now();

    // Not `late final`: Firestore may re-run the transaction closure on
    // contention, which would assign these more than once.
    var pickedUpGoatIds = <String>[];

    await _db.runTransaction((transaction) async {
      pickedUpGoatIds = <String>[];

      // ---------------------------------------------------------------
      // 1. Reads first — a Firestore transaction requires every read
      //    to happen before any write, across ALL bookings.
      // ---------------------------------------------------------------

      final plans = <_WaitPickupPlan>[];

      for (final item in items) {
        final saleId = item.saleId;
        final saleRef = _sales(farmId).doc(saleId);
        final saleSnap = await transaction.get(saleRef);

        if (!saleSnap.exists) {
          throw StateError('Sale $saleId no longer exists.');
        }

        final sale = Sale.fromDoc(saleSnap);
        pickedUpGoatIds.addAll(sale.goatIds);

        if (!sale.isWaitForDelivery) {
          throw StateError('Sale $saleId is not a Wait for Delivery sale.');
        }

        if (sale.status != Sale.statusWaitForDelivery) {
          throw StateError(
            'Sale $saleId has already been completed or is in an '
                'unexpected state ("${sale.status}").',
          );
        }

        // Lot sale: the lot doc is read here, in the read phase, and the
        // reservation is checked before anything is written.
        DocumentReference<Map<String, dynamic>>? lotRef;
        TradingPurchase? lotBefore;

        if (sale.isLotSale) {
          lotRef = _tradingPurchases(farmId).doc(sale.lotDocId);
          final lotSnap = await transaction.get(lotRef);

          if (!lotSnap.exists) {
            throw StateError('Lot ${sale.lotDocId} no longer exists.');
          }

          final lot = TradingPurchase.fromDoc(lotSnap);

          final reservedHere = sale.sourceLocation == Sale.sourceSupplier
              ? lot.reservedSupplierQty
              : lot.reservedFarmQty;

          if (reservedHere < sale.lotQuantity) {
            throw StateError(
              'Lot ${sale.lotDocId} has only $reservedHere goats '
                  'reserved but this sale holds ${sale.lotQuantity}. '
                  'Please check the lot before completing.',
            );
          }

          lotBefore = lot;

          if (sale.costPerGoatSnapshot == null) {
            throw StateError(
              'Sale $saleId has no stored cost per goat, so its profit '
                  'cannot be worked out.',
            );
          }
        }

        final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];

        for (final goatId in sale.goatIds) {
          goatSnaps.add(
            await transaction.get(_goats(farmId).doc(goatId)),
          );
        }

        // Cost of Goods Sold — which of these goats will actually move to
        // Sold (same eligibility check the write phase uses) and what they
        // cost, still in the read phase.
        final eligiblePurchaseIds = <String>[];

        for (final snap in goatSnaps) {
          if (!snap.exists) continue;

          final goat = Goat.fromDoc(snap);

          if (goat.currentStatus != Goat.statusWaitOnDelivery ||
              goat.saleId != saleId) {
            continue;
          }

          eligiblePurchaseIds.add(goat.purchaseId);
        }

        // A lot sale uses the cost per goat snapshotted when the sale was
        // made — never the lot's current figure, which may have moved on.
        final costOfGoodsSold = sale.isLotSale
            ? SaleDraft.round2(
          (sale.costPerGoatSnapshot ?? 0) * sale.lotQuantity,
        )
            : await _costOfGoatsInTransaction(
          transaction: transaction,
          farmId: farmId,
          purchaseIds: eligiblePurchaseIds,
        );

        // The booking on its own: booking-time rate, pickup weight, never
        // today's rate. The discount comes off the goat value, never off
        // transport.
        final advance = sale.bookingAdvanceAmount ?? 0;

        final settlement = SaleSettlement.fromAmount(
          goatAmount: sale.goatValueAtWeight(item.pickupWeight),
          discount: item.discount ?? sale.appliedDiscount,
          transportCharge: SaleDraft.round2(item.transportCharges),
          advancePaid: advance,
          excessAction: item.excessAction,
        );

        plans.add(
          _WaitPickupPlan(
            item: item,
            saleRef: saleRef,
            sale: sale,
            saleSnap: saleSnap,
            lotRef: lotRef,
            lotBefore: lotBefore,
            goatSnaps: goatSnaps,
            costOfGoodsSold: costOfGoodsSold,
            advance: advance,
            settlement: settlement,
          ),
        );
      }

      // ---------------------------------------------------------------
      // 2. Net the bookings against each other. Same function the screen
      //    shows, so what was previewed is what gets saved.
      // ---------------------------------------------------------------

      final allocation = WaitDeliveryAllocator.allocate([
        for (final plan in plans)
          WaitDeliveryBill(
            saleId: plan.item.saleId,
            payable: plan.settlement.payable,
            advancePaid: plan.advance,
          ),
      ]);

      // ---------------------------------------------------------------
      // 3. Remaining reads (customer record for a kept advance) and the
      //    payment check, per booking, still before the first write.
      // ---------------------------------------------------------------

      for (final plan in plans) {
        final alloc = allocation.bySale[plan.item.saleId]!;

        plan.alloc = alloc;
        plan.transfersIn = allocation.transfersInto(plan.item.saleId);
        plan.transfersOut = allocation.transfersFrom(plan.item.saleId);

        plan.advanceTarget = await _checkExcessInTransaction(
          transaction: transaction,
          farmId: farmId,
          customerId: plan.sale.customerId,
          excess: alloc.leftoverExcess,
          action: plan.item.excessAction,
        );

        // The money received right now, checked against what is really
        // still due AFTER the transfers.
        plan.received = _checkCompletionPayment(
          finalAmount: alloc.toCollect,
          amountReceivedNow: plan.item.amountReceivedNow,
          onCredit: plan.item.onCredit,
        );
      }

      // ---------------------------------------------------------------
      // 4. Writes — one booking after the other, same transaction.
      // ---------------------------------------------------------------

      var totalMovedGoats = 0;
      var totalLotGoats = 0;

      // Goats handed over straight from the supplier (held there by a
      // supplier-sourced booking): never farm stock.
      var supplierLotGoats = 0;
      final supplierDoneByLot = <String, int>{};
      final lotsBefore = <String, TradingPurchase>{};
      var totalProfit = 0.0;

      for (final plan in plans) {
        final item = plan.item;
        final sale = plan.sale;
        final saleId = item.saleId;
        final alloc = plan.alloc;
        final settlement = plan.settlement;

        // Revenue and profit are based on the goat value AFTER the
        // discount.
        final goatValue = settlement.netGoatAmount;
        final appliedDiscount = settlement.appliedDiscount;
        final transport = SaleDraft.round2(item.transportCharges);

        final finalPrice = alloc.toCollect;
        final leftover = alloc.leftoverExcess;

        final existingPayments =
            (plan.saleSnap.data()?['payments'] as List?) ?? const [];

        // Extra advance moved in from other bookings becomes a payment
        // line on this one. No cash entry: the money was received as the
        // other booking's advance.
        final transferLines = <Map<String, dynamic>>[
          for (final t in plan.transfersIn)
            SalePayment(
              amount: t.amount,
              method: method,
              date: now,
              note: '${SalePayment.bookingTransferPrefix}'
                  '${t.fromSaleId} extra',
            ).toMap(),
        ];

        final paidBefore = SaleDraft.round2(plan.advance + alloc.takenIn);

        final givenOut = alloc.givenOut;
        final givenTo = plan.transfersOut
            .map((t) => t.toSaleId)
            .toSet()
            .join(', ');

        transaction.update(plan.saleRef, {
          'status': Sale.statusPickupCompleted,
          'pickupWeight': item.pickupWeight,
          // Goat value at the pickup weight (agreed amount x pickup weight
          // / booked weight), so the bill keeps the figure charged.
          'goatAmountAtPickup': settlement.goatAmount,
          // Cleared when there is none, so a stale value can never linger
          // on the bill.
          'transportCost':
          transport > 0 ? transport : FieldValue.delete(),
          'finalPriceAfterPickup': finalPrice,
          'discount':
          appliedDiscount > 0 ? appliedDiscount : FieldValue.delete(),
          'excessToAdvance':
          item.excessAction == ExcessAction.carryToAdvance &&
              leftover > 0
              ? leftover
              : FieldValue.delete(),
          'excessRefunded':
          item.excessAction == ExcessAction.refundToCustomer &&
              leftover > 0
              ? leftover
              : FieldValue.delete(),
          'excessTransferred':
          givenOut > 0 ? givenOut : FieldValue.delete(),
          'excessTransferredTo':
          givenOut > 0 ? givenTo : FieldValue.delete(),
          ..._completionPaymentFields(
            existingPayments: [...existingPayments, ...transferLines],
            received: plan.received,
            method: method,
            when: now,
            onCredit: finalPrice > 0 && item.onCredit,
            finalAmount: finalPrice,
            paidBefore: paidBefore,
          ),
          'deliveryCompletedAt': FieldValue.serverTimestamp(),
        });

        _writeCompletionRevenue(
          transaction: transaction,
          farmId: farmId,
          saleId: saleId,
          customerName: sale.customerName,
          received: plan.received,
          paidBefore: paidBefore,
          revenueTotal: goatValue,
          // The transfer lines take positions in the payments list, so the
          // numbering of the Finance entry follows them.
          existingPaymentCount:
          existingPayments.length + transferLines.length,
          method: method,
          when: now,
          lotId: sale.lotDocId,
          customerId: sale.isLotSale ? sale.customerId : '',
        );

        // Only the extra left after every due was covered.
        _writeExcessInTransaction(
          transaction: transaction,
          farmId: farmId,
          saleId: saleId,
          customerId: sale.customerId,
          customerName: sale.customerName,
          excess: leftover,
          action: item.excessAction,
          method: method,
          when: now,
          target: plan.advanceTarget,
        );

        // Flip every still-Wait-on-Delivery goat in this sale to Sold —
        // it has now actually left the farm. Skip any goat that has
        // already moved on rather than clobbering it.
        var movedGoats = sale.isLotSale ? sale.lotQuantity : 0;

        if (sale.isLotSale) {
          if (sale.sourceLocation == Sale.sourceSupplier) {
            // Held at the supplier: handed over straight from there. These
            // goats were never farm stock, so totalStock /
            // pendingRegistrations do not move for them.
            transaction.update(plan.lotRef!, {
              'reservedSupplierQty': FieldValue.increment(-sale.lotQuantity),
              'soldFromSupplierQty': FieldValue.increment(sale.lotQuantity),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            supplierLotGoats += sale.lotQuantity;
            supplierDoneByLot[sale.lotDocId] =
                (supplierDoneByLot[sale.lotDocId] ?? 0) + sale.lotQuantity;
            if (plan.lotBefore != null) {
              lotsBefore[sale.lotDocId] ??= plan.lotBefore!;
            }
          } else {
            // The reserved goats are now sold: reserved -> sold, and the
            // farm stock (mirrored by pendingCount) falls now, not at
            // booking.
            transaction.update(plan.lotRef!, {
              'reservedFarmQty': FieldValue.increment(-sale.lotQuantity),
              'soldFromFarmQty': FieldValue.increment(sale.lotQuantity),
              'pendingCount': FieldValue.increment(-sale.lotQuantity),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            totalLotGoats += sale.lotQuantity;
          }
        }

        for (final snap in plan.goatSnaps) {
          if (!snap.exists) continue;

          final goat = Goat.fromDoc(snap);

          if (goat.currentStatus != Goat.statusWaitOnDelivery ||
              goat.saleId != saleId) {
            continue;
          }

          transaction.update(snap.reference, {
            'currentStatus': Goat.statusSold,
          });

          movedGoats++;
        }

        totalMovedGoats += movedGoats;
        totalProfit += SaleDraft.round2(goatValue - plan.costOfGoodsSold);

        // ---------------------------------------------------------------
        // FINANCE REVENUE — the goat has now actually left the farm, so
        // this is where the advance already received (plus any extra
        // advance moved in from another booking) becomes Sold Goat
        // Revenue, capped at the goat value, written in this same
        // transaction. The remaining balance is recorded as it is
        // collected — see the FINANCE INTEGRATION note above.
        // ---------------------------------------------------------------

        _writeInitialRevenueInTransaction(
          transaction: transaction,
          farmId: farmId,
          saleId: saleId,
          paid: paidBefore,
          revenueTotal: goatValue,
          date: now,
          customerName: sale.customerName,
          paymentMethod: _methodOrOther(sale.paymentMethod),
          lotId: sale.lotDocId,
          customerId: sale.isLotSale ? sale.customerId : '',
        );
      }

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate, written once for the whole group: Wait
      //    on Delivery count decreases, Total Sold increases, totalStock
      //    decreases (the deferred decrement of Branch C). Realized
      //    profit = goat-only sale value (never transport) minus what
      //    the goats cost to acquire.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'waitOnDelivery': FieldValue.increment(-totalMovedGoats),
          'totalSold': FieldValue.increment(totalMovedGoats),
          'totalStock':
          FieldValue.increment(-(totalMovedGoats - supplierLotGoats)),
          if (totalLotGoats > 0)
            'pendingRegistrations': FieldValue.increment(-totalLotGoats),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(totalProfit),
          ),
        },
        SetOptions(merge: true),
      );
      _markSupplierEmptyLotsReceived(
        transaction,
        farmId,
        lotsBefore,
        supplierDoneByLot,
      );
    }).timeout(_timeout * 2);

    // -----------------------------------------------------------------
    // HEALTH REMINDERS — the goats have left the farm, so their on-device
    // vaccination / hoof cutting / hair trimming alarms are switched off
    // (the Firestore due-checks already skip a goat that is no longer on
    // the farm). Not awaited; never throws.
    // -----------------------------------------------------------------

    for (final goatId in pickedUpGoatIds) {
      unawaited(
        HealthReminderScheduler.instance.cancelForTradingGoat(
          farmId: farmId,
          goatId: goatId,
        ),
      );
    }
  }

  // -----------------------------------------------------------------------
  // COLLECT BALANCE — after delivery
  // -----------------------------------------------------------------------

  /// Records a payment against the balance still owed on a delivered sale:
  /// the final amount of a completed Booking / Wait for Delivery sale, or
  /// the unpaid part of a Deliver Now sale.
  ///
  /// The payment is appended to the sale's `payments` list (see
  /// [SalePayment]) and `paymentStatus` is refreshed (Paid / Partial), all
  /// in ONE transaction that re-reads the sale and re-checks the balance
  /// first. That is what stops a double-tap, or two devices collecting at
  /// the same moment, from taking more than the customer actually owes.
  ///
  /// The same transaction also writes the Finance entry for this money
  /// (Sold Goat Revenue, with the payment method chosen here, dated now,
  /// linked to [saleId]) — but only the part that covers the goat sale
  /// and holding charges. Money that goes toward transportation is passed
  /// on to the transport team and is never revenue, so a payment that
  /// only settles transport writes no Finance entry at all.
  ///
  /// Throws a [StateError] whose message is fit to show to the person for
  /// anything they can fix (nothing due, amount too high, goat not
  /// delivered yet).
  Future<void> receiveBalancePayment({
    required String farmId,
    required String saleId,
    required double amount,
    required String paymentMethod,
    String note = '',
  }) async {
    final paid = SaleDraft.round2(amount);

    if (paid <= 0) {
      throw StateError('Enter an amount greater than zero.');
    }

    final method = paymentMethod.trim().isEmpty
        ? FinancePaymentMethods.cash
        : paymentMethod.trim();

    await _db.runTransaction((transaction) async {
      final saleRef = _sales(farmId).doc(saleId);
      final saleSnap = await transaction.get(saleRef);

      if (!saleSnap.exists) {
        throw StateError('This sale could not be found.');
      }

      final sale = Sale.fromDoc(saleSnap);

      if (!sale.isDelivered) {
        throw StateError(
          'A balance can only be collected after the goat has been '
              'delivered.',
        );
      }

      // canCollectBalance also rules out a Transfer to Palai saved before
      // the goat's price payment was tracked: nothing was recorded as
      // received for it, so no balance is claimed.
      final due = sale.canCollectBalance ? sale.billBalanceDue : 0.0;

      if (due <= 0) {
        throw StateError('This sale has no balance due.');
      }

      if (paid > due) {
        throw StateError(
          'That is more than the balance due '
              '(₹${due.toStringAsFixed(2)}).',
        );
      }

      // The sale is the ONLY record of this debt, so this is all there is
      // to update: the customer's Palai pending balance is a different
      // debt and is never touched here.
      _writeBalancePayment(
        transaction: transaction,
        farmId: farmId,
        saleSnap: saleSnap,
        sale: sale,
        paid: paid,
        method: method,
        note: note,
        when: DateTime.now(),
      );
    }).timeout(_timeout * 2);
  }

  /// Voids ONE balance payment of a sale (entered by mistake). To correct
  /// it: void it, then receive the right amount.
  ///
  /// In ONE transaction (re-reading the sale first) it:
  ///  * marks the entry in the sale's `payments` list as voided (the entry
  ///    is kept, so the history and the `sale_<id>_pay<N>` numbering never
  ///    change),
  ///  * refreshes `paymentStatus` from the money that still counts (a
  ///    voided payment is ignored by [Sale.billBalancePayments], so the
  ///    balance due, revenue received and customer credit all follow),
  ///  * voids the matching Sold Goat Revenue entry in Finance, if that
  ///    payment wrote one (a payment that only paid transportation wrote
  ///    none), and
  ///  * logs a "Revenue Voided" activity.
  ///
  /// [paymentIndex] is the position of the payment in [Sale.payments].
  ///
  /// Refused (with a message fit to show) for: an already voided payment;
  /// any payment except the newest one that still counts (void the newest
  /// first, otherwise the revenue split of the later payments would be
  /// wrong); a payment received through Customer Palai "Receive Payment"
  /// (its money also sits in the Palai payment). The first payment taken
  /// when the sale was made is not part of this list and cannot be voided
  /// here.
  Future<void> voidBalancePayment({
    required String farmId,
    required String saleId,
    required int paymentIndex,
    String reason = '',
  }) async {
    final actor = await FirestoreService.instance.getCurrentActor();

    final saleRef = _sales(farmId).doc(saleId);
    final revenueRef = _transactions(farmId).doc(
      _saleRevenueDocId(saleId, 'pay${paymentIndex + 1}'),
    );

    late double voidedAmount;

    await _db.runTransaction((transaction) async {
      // All reads first.
      final saleSnap = await transaction.get(saleRef);
      final revenueSnap = await transaction.get(revenueRef);

      if (!saleSnap.exists) {
        throw StateError('This sale could not be found.');
      }

      final sale = Sale.fromDoc(saleSnap);
      final raw = [
        ...((saleSnap.data()?['payments'] as List?) ?? const []),
      ];

      if (paymentIndex < 0 || paymentIndex >= raw.length) {
        throw StateError('This payment could not be found.');
      }

      final payment = sale.payments[paymentIndex];

      if (payment.voided) {
        throw StateError('This payment was already voided.');
      }

      if (payment.isPalaiSettlement) {
        throw StateError(
          'This payment was received through a Customer Palai payment, so '
              'it cannot be voided here.',
        );
      }

      if (payment.isBookingTransfer) {
        throw StateError(
          'This line is extra advance moved over from another booking at '
              'delivery, so it cannot be voided on its own.',
        );
      }

      if (paymentIndex != sale.latestActivePaymentIndex) {
        throw StateError(
          'Only the most recent payment can be voided. Void the newer '
              'payment first.',
        );
      }

      voidedAmount = payment.amount;

      final voidedEntry = SalePayment(
        amount: payment.amount,
        method: payment.method,
        date: payment.date,
        note: payment.note,
        voided: true,
        voidedAt: DateTime.now(),
        voidReason: reason,
        voidedByName: actor?.name ?? '',
      ).toMap();

      // Keep any other fields already stored on the entry.
      final original = raw[paymentIndex];
      raw[paymentIndex] = {
        if (original is Map) ...Map<String, dynamic>.from(original),
        ...voidedEntry,
      };

      final paidAfter = SaleDraft.round2(
        sale.billInitialPayment +
            sale.payments
                .asMap()
                .entries
                .where((e) => !e.value.voided && e.key != paymentIndex)
                .fold<double>(0.0, (sum, e) => sum + e.value.amount),
      );
      final dueAfter = SaleDraft.round2(sale.billCustomerTotal - paidAfter);

      transaction.update(saleRef, {
        'payments': raw,
        'paymentStatus': _paymentStatusFor(
          balanceDue: dueAfter < 0 ? 0.0 : dueAfter,
          paid: paidAfter,
        ),
      });

      if (revenueSnap.exists && revenueSnap.data()?['status'] != 'voided') {
        transaction.update(revenueRef, {
          'status': 'voided',
          'voidedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(_farms().doc(farmId).collection('activities').doc(), {
        'type': ActivityType.revenueVoided.name,
        'title': 'Revenue Voided',
        'subtitle':
        'Sale $saleId · customer payment · ₹${payment.amount.toStringAsFixed(0)}',
        'module': 'finance',
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });
    }).timeout(_timeout * 2);

    unawaited(
      FirestoreService.instance.notifyPartnerActivity(
        farmId: farmId,
        type: ActivityType.revenueVoided,
        title: 'Revenue Voided',
        subtitle:
        'Sale $saleId · customer payment · ₹${voidedAmount.toStringAsFixed(0)}',
        module: 'finance',
        actor: actor,
      ),
    );
  }

  /// The writes for ONE balance payment against ONE sale, inside a
  /// caller's transaction: the payment appended to the sale's `payments`,
  /// its `paymentStatus` refreshed, and the Sold Goat Revenue entry for
  /// the part that is revenue (never transportation). The caller has
  /// already read [saleSnap] and checked that [paid] does not exceed the
  /// balance due.
  ///
  /// Shared by [receiveBalancePayment] (a payment taken on the sale) and
  /// [settleSalesInTransaction] (a Customer Palai payment that also
  /// settles goat sales), so both leave the sale and Finance in exactly
  /// the same state.
  void _writeBalancePayment({
    required Transaction transaction,
    required String farmId,
    required DocumentSnapshot<Map<String, dynamic>> saleSnap,
    required Sale sale,
    required double paid,
    required String method,
    required String note,
    required DateTime when,
  }) {
    final payment = SalePayment(
      amount: paid,
      method: method,
      date: when,
      note: note,
    );

    // Rewrite the raw list (rather than arrayUnion) so the new entry is
    // always appended, even if an identical payment already exists.
    final existing = (saleSnap.data()?['payments'] as List?) ?? const [];
    final dueAfter = SaleDraft.round2(sale.billBalanceDue - paid);

    // Revenue = the part of this payment that covers goat sale +
    // holding charges; anything past that is transportation.
    final revenueDelta = SaleDraft.round2(
      Sale.revenueFromPaid(
        paid: sale.billAmountPaid + paid,
        revenueTotal: sale.billRevenueTotal,
      ) -
          sale.billRevenueReceived,
    );

    transaction.update(saleSnap.reference, {
      'payments': [...existing, payment.toMap()],
      'paymentStatus': _paymentStatusFor(
        balanceDue: dueAfter,
        paid: sale.billAmountPaid + paid,
      ),
    });

    if (revenueDelta > 0) {
      final trimmedNote = note.trim();
      final saleId = saleSnap.id;

      transaction.set(
        _transactions(farmId).doc(
          _saleRevenueDocId(saleId, 'pay${existing.length + 1}'),
        ),
        {
          ..._saleRevenueData(
            saleId: saleId,
            amount: revenueDelta,
            date: payment.date,
            paymentMethod: method,
            customerName: sale.customerName,
            lotId: sale.lotDocId,
            customerId: sale.isLotSale ? sale.customerId : '',
            note: trimmedNote.isEmpty
                ? 'Sold Goat Revenue — balance payment, Sale $saleId'
                : 'Sold Goat Revenue — balance payment, Sale $saleId '
                '· $trimmedNote',
          ),
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    }
  }

  // -----------------------------------------------------------------------
  // GOAT SALE CREDIT SETTLED FROM A CUSTOMER PALAI PAYMENT
  // -----------------------------------------------------------------------
  //
  // A customer can owe money in two places: the Palai outstanding on their
  // profile (boarding charges) and the unpaid part of a goat sale. The
  // sale stays the only record of its own debt. When money comes in
  // through Customer Palai "Receive Payment", it goes to the Palai
  // outstanding first; only what is left over goes to the customer's open
  // goat sales, oldest first, and only what is left after THAT is stored
  // as advance. The same payment therefore never counts twice: the Palai
  // part is Palai income, and the goat-sale part is Sold Goat Revenue on
  // the sale it settled.

  /// The unpaid goat sales of one person, grouped exactly like the Goat
  /// sale credit card on their profile (by mobile number, else customer
  /// id, else name). Null when they owe nothing on any sale.
  Future<CustomerCredit?> creditForPerson(
      String farmId, {
        required String customerId,
        String mobile = '',
        String name = '',
      }) async {
    final snap = await _sales(farmId)
        .where(
      'paymentStatus',
      whereIn: [
        Sale.paymentStatusPartial,
        Sale.paymentStatusPending,
      ],
    )
        .get()
        .timeout(_timeout);

    return CustomerCredit.find(
      CustomerCredit.group(snap.docs.map(Sale.fromDoc)),
      customerId: customerId,
      mobile: mobile,
      name: name,
    );
  }

  /// Step 1 of settling sales from inside another transaction: re-reads
  /// every sale in [saleIds] through [transaction] (Firestore needs all
  /// reads before any write). Pass the result to [settleSalesInTransaction].
  Future<List<DocumentSnapshot<Map<String, dynamic>>>>
  readSalesForSettlement(
      Transaction transaction,
      String farmId,
      List<String> saleIds,
      ) async {
    final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];

    for (final id in saleIds) {
      snaps.add(await transaction.get(_sales(farmId).doc(id)));
    }

    return snaps;
  }

  /// Step 2: applies up to [amount] to the sales read by
  /// [readSalesForSettlement], oldest first, each through the same writes
  /// as [receiveBalancePayment]. Only sales that can still collect a
  /// balance are used, and no sale is paid more than it owes. Writes
  /// only — no reads — so it is safe after the caller's own reads.
  ///
  /// Returns what was actually applied; anything that could not be
  /// applied (no open sale, or more than they owe) is left for the caller.
  GoatSaleSettlement settleSalesInTransaction({
    required Transaction transaction,
    required String farmId,
    required List<DocumentSnapshot<Map<String, dynamic>>> saleSnapshots,
    required double amount,
    required String paymentMethod,
    String note = '',
    DateTime? when,
  }) {
    var remaining = SaleDraft.round2(amount);

    if (remaining <= 0 || saleSnapshots.isEmpty) {
      return const GoatSaleSettlement([]);
    }

    final method = paymentMethod.trim().isEmpty
        ? FinancePaymentMethods.cash
        : paymentMethod.trim();
    final at = when ?? DateTime.now();

    final open = <MapEntry<Sale, DocumentSnapshot<Map<String, dynamic>>>>[];

    for (final snap in saleSnapshots) {
      if (!snap.exists) continue;

      final sale = Sale.fromDoc(snap);

      if (!sale.canCollectBalance) continue;

      open.add(MapEntry(sale, snap));
    }

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);

    open.sort(
          (a, b) => (a.key.saleDate ?? epoch).compareTo(b.key.saleDate ?? epoch),
    );

    final lines = <GoatSaleSettlementLine>[];

    for (final entry in open) {
      if (remaining <= 0) break;

      final due = entry.key.billBalanceDue;
      final apply = SaleDraft.round2(remaining < due ? remaining : due);

      if (apply <= 0) continue;

      _writeBalancePayment(
        transaction: transaction,
        farmId: farmId,
        saleSnap: entry.value,
        sale: entry.key,
        paid: apply,
        method: method,
        note: note,
        when: at,
      );

      lines.add(GoatSaleSettlementLine(saleId: entry.value.id, amount: apply));
      remaining = SaleDraft.round2(remaining - apply);
    }

    return GoatSaleSettlement(lines);
  }

  // -----------------------------------------------------------------------
  // CUSTOMERS ON CREDIT — who still owes money on goat sales
  // -----------------------------------------------------------------------

  /// Live list of every customer who still owes money on goat sales,
  /// biggest balance first.
  ///
  /// Nothing extra is stored for this. A sale that is delivered and not
  /// paid in full carries a Partial / Pending `paymentStatus` (set when a
  /// Deliver Now or Transfer to Palai sale is saved, and when a Booking /
  /// Wait for Delivery is completed), so this reads only those and adds
  /// their balances up per customer ([CustomerCredit.group]). Because the
  /// balance is worked out from the payments themselves, receiving a
  /// payment ([receiveBalancePayment]) is all it takes to bring it down —
  /// there is no second figure to keep in step. It is the same source the
  /// Finance Receivables total uses.
  Stream<List<CustomerCredit>> creditCustomersStream(String farmId) {
    return _sales(farmId)
        .where(
      'paymentStatus',
      whereIn: [
        Sale.paymentStatusPartial,
        Sale.paymentStatusPending,
      ],
    )
        .snapshots()
        .map(
          (snap) => CustomerCredit.group(
        snap.docs.map(Sale.fromDoc),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // CUSTOMERS (Task 2.2 groundwork)
  // -----------------------------------------------------------------------

  Future<Customer?> getCustomer(
      String farmId,
      String customerId,
      ) async {
    final doc =
    await _customers(farmId).doc(customerId).get().timeout(_timeout);

    if (!doc.exists) {
      return null;
    }

    return Customer.fromDoc(doc);
  }

  Stream<List<Customer>> customersStream(
      String farmId,
      ) {
    return _customers(farmId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(Customer.fromDoc).toList());
  }

  /// Exact-match lookup by mobile number, restricted to the Sale
  /// customers collection. Kept separate from [searchCustomerMatches]
  /// because Step 2 (Task 2.2) needs a single definite match to
  /// pre-fill from when the number belongs to a *Sale* customer, vs. a
  /// broader "is this person known at all" search.
  Future<Customer?> findCustomerByMobile(
      String farmId,
      String mobile,
      ) async {
    final trimmed = mobile.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    final snap = await _customers(farmId)
        .where('mobile', isEqualTo: trimmed)
        .limit(1)
        .get()
        .timeout(_timeout);

    if (snap.docs.isEmpty) {
      return null;
    }

    return Customer.fromDoc(snap.docs.first);
  }

  Future<String> addCustomer(
      String farmId,
      Customer customer,
      ) async {
    final ref = await _customers(farmId)
        .add({
      ...customer.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    })
        .timeout(_timeout);

    return ref.id;
  }

  Future<void> updateCustomer(
      String farmId,
      Customer customer,
      ) async {
    await _customers(farmId)
        .doc(customer.id)
        .set(
      {
        ...customer.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    )
        .timeout(_timeout);
  }

  // -----------------------------------------------------------------------
  // DYNAMIC PALAI-AWARE CUSTOMER LOOKUP
  // -----------------------------------------------------------------------
  //
  // A person can already be a Palai customer (farms/{farmId}/palaiCustomers)
  // the first time they show up here as a goat buyer. Step 2's lookup
  // (Task 2.2) should surface that immediately by name/mobile instead of
  // only ever searching the newer, Sale-only `customers` collection —
  // otherwise the same real person quietly ends up as two disconnected
  // records. These two collections are still kept separate (see
  // Customer's doc comment for why), so this is a *merge at read time*,
  // not a shared collection.

  /// One entry in a merged customer search result. `source` tells the UI
  /// (and SalesService.saveSale) whether this match came from the Sale
  /// customers collection or from the Palai module, so it knows which
  /// collection to write back to / link against.
  Future<List<CustomerMatch>> searchCustomerMatches(
      String farmId,
      String query,
      ) async {
    final trimmed = query.trim().toLowerCase();

    if (trimmed.isEmpty) {
      return const [];
    }

    final results = await Future.wait([
      _customers(farmId).get().timeout(_timeout),
      _palaiCustomers(farmId).get().timeout(_timeout),
    ]);

    final customerMatches = results[0]
        .docs
        .map(Customer.fromDoc)
        .map(CustomerMatch.fromCustomer)
        .where((m) => m._matches(trimmed));

    final palaiMatches = results[1]
        .docs
        .map(PalaiCustomer.fromDoc)
        .map(CustomerMatch.fromPalaiCustomer)
        .where((m) => m._matches(trimmed));

    final merged = [...customerMatches, ...palaiMatches]
      ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    return merged;
  }

  /// What this customer has bought before, for the "previous activity"
  /// card on the customer step (PDF §10). One single-field query on the
  /// sales collection, so no composite index is needed. Works for a Sale
  /// customer and for a Palai customer alike, because every sale stores
  /// the id of whichever record the customer was picked from.
  ///
  /// Pending is the same figure the Credit screen uses: the balance of
  /// delivered sales that still have something to collect.
  Future<CustomerHistory> getCustomerHistory(
      String farmId,
      String customerId,
      ) async {
    final id = customerId.trim();

    if (id.isEmpty) return CustomerHistory.empty;

    final snap = await _sales(farmId)
        .where('customerId', isEqualTo: id)
        .get()
        .timeout(_timeout);

    var pending = 0.0;
    DateTime? last;

    for (final doc in snap.docs) {
      final sale = Sale.fromDoc(doc);

      if (sale.canCollectBalance) pending += sale.billBalanceDue;

      final date = sale.saleDate;
      if (date != null && (last == null || date.isAfter(last))) last = date;
    }

    return CustomerHistory(
      saleCount: snap.docs.length,
      lastSaleDate: last,
      pendingDue: SaleDraft.round2(pending),
    );
  }

  /// Saves an address edited on the customer step back to the customer's
  /// own Palai record.
  ///
  /// A sale already stores the edited details on the sale itself, and for a
  /// Sale customer the sale transaction updates the `customers` doc. A Palai
  /// customer's doc belongs to the Palai module, so it is left alone while
  /// the sale is saved and only the ADDRESS is written here afterwards —
  /// never the name or mobile (those identify the customer) and never a
  /// blank (an empty field means "not filled in", not "delete").
  ///
  /// Best effort and never throws: the sale is already saved, and a failed
  /// address update must not look like a failed sale.
  Future<void> syncPalaiCustomerAddress(
      String farmId,
      SaleDraft draft,
      ) async {
    if (draft.customerSource != CustomerMatchSource.palai) return;

    final id = draft.customerId.trim();
    final address = draft.address.trim();

    if (id.isEmpty || address.isEmpty) return;

    try {
      final ref = _palaiCustomers(farmId).doc(id);
      final snap = await ref.get().timeout(_timeout);

      if (!snap.exists) return;

      final current = (snap.data()?['address'] ?? '').toString().trim();

      if (current == address) return;

      await ref.update({'address': address}).timeout(_timeout);
    } catch (_) {
      // Ignored on purpose — see above.
    }
  }

  /// Live merged stream of every known name across both collections, for
  /// an as-you-type suggestions list in Step 2. Hand-rolled combineLatest
  /// (no rxdart dependency in this project): re-emits the merged list
  /// whenever either underlying collection changes.
  Stream<List<CustomerMatch>> allCustomerMatchesStream(
      String farmId,
      ) {
    final controller = StreamController<List<CustomerMatch>>.broadcast();

    List<CustomerMatch>? latestCustomers;
    List<CustomerMatch>? latestPalaiCustomers;

    void emitIfReady() {
      if (latestCustomers == null || latestPalaiCustomers == null) {
        return;
      }

      final merged = [
        ...latestCustomers!,
        ...latestPalaiCustomers!,
      ]..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      if (!controller.isClosed) {
        controller.add(merged);
      }
    }

    final sub1 = _customers(farmId).snapshots().listen(
          (snap) {
        latestCustomers = snap.docs
            .map(Customer.fromDoc)
            .map(CustomerMatch.fromCustomer)
            .toList();

        emitIfReady();
      },
      onError: controller.addError,
    );

    final sub2 = _palaiCustomers(farmId).snapshots().listen(
          (snap) {
        latestPalaiCustomers = snap.docs
            .map(PalaiCustomer.fromDoc)
            .map(CustomerMatch.fromPalaiCustomer)
            .toList();

        emitIfReady();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
    };

    return controller.stream;
  }
}

/// What to record for one booking when Wait for Delivery bookings are
/// completed together (see SalesService.completeWaitForDeliveryGroup).
class WaitPickupInput {
  final String saleId;
  final double pickupWeight;

  /// Optional transportation charge collected at pickup. Never revenue.
  final double transportCharges;

  /// Received now, out of what is still due after the bookings were netted
  /// against each other.
  final double amountReceivedNow;

  /// Whatever is left after [amountReceivedNow] goes onto the customer's
  /// outstanding balance.
  final bool onCredit;

  /// Null keeps the discount given at booking time.
  final double? discount;

  /// What to do with any extra advance left after every due is covered.
  final ExcessAction excessAction;

  const WaitPickupInput({
    required this.saleId,
    required this.pickupWeight,
    this.transportCharges = 0,
    this.amountReceivedNow = 0,
    this.onCredit = false,
    this.discount,
    this.excessAction = ExcessAction.carryToAdvance,
  });
}

/// What to record for one booking when Booking / Holding sales are
/// completed together (see SalesService.completeBookingDeliveryGroup).
class BookingPickupInput {
  final String saleId;

  /// Optional transportation charge collected at delivery. Never revenue.
  final double transportCharges;

  /// Received now, out of what is still due after the bookings were netted
  /// against each other.
  final double amountReceivedNow;

  /// Whatever is left after [amountReceivedNow] goes onto the customer's
  /// outstanding balance.
  final bool onCredit;

  /// What to do with any extra left after every due is covered.
  final ExcessAction excessAction;

  /// Extra discount given at delivery, on top of the booking discount.
  final double discount;

  /// Holding charge per day edited at delivery. Null keeps the booking's
  /// rate.
  final double? holdingChargePerDay;

  /// Total weight of the booking's goats at delivery. When given, the goat
  /// value is repriced by weight ([Sale.goatValueAtWeight]); null keeps
  /// the amount agreed at booking.
  final double? pickupWeight;

  const BookingPickupInput({
    required this.saleId,
    this.transportCharges = 0,
    this.amountReceivedNow = 0,
    this.onCredit = false,
    this.excessAction = ExcessAction.carryToAdvance,
    this.discount = 0,
    this.holdingChargePerDay,
    this.pickupWeight,
  });
}

/// Everything read for one booking before the group's first write.
class _BookingPickupPlan {
  final BookingPickupInput item;
  final DocumentReference<Map<String, dynamic>> saleRef;
  final Sale sale;
  final DocumentSnapshot<Map<String, dynamic>> saleSnap;
  final DocumentReference<Map<String, dynamic>>? lotRef;

  /// The lot as read in this transaction (lot sales only).
  final TradingPurchase? lotBefore;
  final List<DocumentSnapshot<Map<String, dynamic>>> goatSnaps;
  final double costOfGoodsSold;
  final double bookingAmount;
  final DateTime startDay;
  final int holdingDays;
  final double holdingRate;
  final double holdingCharges;

  /// The booking on its own, before any transfer between bookings.
  final SaleSettlement settlement;

  final DocumentReference<Map<String, dynamic>> initialRevenueRef;
  final DocumentSnapshot<Map<String, dynamic>>? initialRevenueSnap;

  /// Weight at delivery (null when the screen did not ask for one).
  final double? pickupWeight;

  /// Goat value at [pickupWeight], before any discount.
  final double? goatAmountAtPickup;

  late WaitDeliverySaleAllocation alloc;
  List<WaitDeliveryTransfer> transfersIn = const [];
  List<WaitDeliveryTransfer> transfersOut = const [];
  _AdvanceTarget advanceTarget = _AdvanceTarget.none;
  double received = 0;

  _BookingPickupPlan({
    required this.item,
    required this.saleRef,
    required this.sale,
    required this.saleSnap,
    required this.lotRef,
    this.lotBefore,
    required this.goatSnaps,
    required this.costOfGoodsSold,
    required this.bookingAmount,
    required this.startDay,
    required this.holdingDays,
    required this.holdingRate,
    required this.holdingCharges,
    required this.settlement,
    required this.initialRevenueRef,
    required this.initialRevenueSnap,
    this.pickupWeight,
    this.goatAmountAtPickup,
  });
}

/// Everything read for one booking before the group's first write.
class _WaitPickupPlan {
  final WaitPickupInput item;
  final DocumentReference<Map<String, dynamic>> saleRef;
  final Sale sale;
  final DocumentSnapshot<Map<String, dynamic>> saleSnap;
  final DocumentReference<Map<String, dynamic>>? lotRef;

  /// The lot as read in this transaction (lot sales only).
  final TradingPurchase? lotBefore;
  final List<DocumentSnapshot<Map<String, dynamic>>> goatSnaps;
  final double costOfGoodsSold;
  final double advance;

  /// The booking on its own, before any transfer between bookings.
  final SaleSettlement settlement;

  // Filled in once every booking has been read.
  late WaitDeliverySaleAllocation alloc;
  List<WaitDeliveryTransfer> transfersIn = const [];
  List<WaitDeliveryTransfer> transfersOut = const [];
  _AdvanceTarget advanceTarget = _AdvanceTarget.none;
  double received = 0;

  _WaitPickupPlan({
    required this.item,
    required this.saleRef,
    required this.sale,
    required this.saleSnap,
    required this.lotRef,
    this.lotBefore,
    required this.goatSnaps,
    required this.costOfGoodsSold,
    required this.advance,
    required this.settlement,
  });
}

/// A customer's earlier goat sales, shown on the customer step.
class CustomerHistory {
  final int saleCount;
  final DateTime? lastSaleDate;

  /// Goat-sale balance still owed (delivered sales only).
  final double pendingDue;

  const CustomerHistory({
    this.saleCount = 0,
    this.lastSaleDate,
    this.pendingDue = 0,
  });

  static const CustomerHistory empty = CustomerHistory();
}

/// Where a [CustomerMatch] came from.
/// Where an "extra amount -> advance" credit is stored.
enum _AdvanceTarget {
  /// No advance is being written (refund, or no excess).
  none,

  /// farms/{farm}/customers/{id}.advanceBalance
  trading,

  /// farms/{farm}/palaiCustomers/{id}.advanceAmount
  palai,
}

enum CustomerMatchSource {
  /// farms/{farmId}/customers — a Sale-flow buyer.
  sale,

  /// farms/{farmId}/palaiCustomers — an existing Palai boarding customer.
  palai,
}

/// A single, source-tagged result from the merged customer lookup.
///
/// Step 2 (Task 2.2) uses [source] to decide what to show alongside the
/// name — e.g. a "Palai customer" badge — and SalesService.saveSale()
/// uses it to know whether [id] refers to a `customers` doc or a
/// `palaiCustomers` doc when linking the sale.
class CustomerMatch {
  final CustomerMatchSource source;
  final String id;
  final String name;
  final String mobile;
  final String address;

  /// Only set when [source] is [CustomerMatchSource.palai] — lets Step 2
  /// show e.g. "Palai · Basic Package" next to the name so it's obvious
  /// this isn't a plain first-time buyer.
  final String? palaiPackageName;

  /// Only set for a Palai customer: what they currently owe on their
  /// Palai account (separate from any goat-sale balance).
  final double palaiPendingAmount;

  const CustomerMatch({
    required this.source,
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    this.palaiPackageName,
    this.palaiPendingAmount = 0,
  });

  factory CustomerMatch.fromCustomer(Customer customer) {
    return CustomerMatch(
      source: CustomerMatchSource.sale,
      id: customer.id,
      name: customer.name,
      mobile: customer.mobile,
      address: customer.address,
    );
  }

  factory CustomerMatch.fromPalaiCustomer(PalaiCustomer customer) {
    return CustomerMatch(
      source: CustomerMatchSource.palai,
      id: customer.id,
      name: customer.name,
      mobile: customer.mobileNumber,
      address: customer.address,
      palaiPackageName: customer.package,
      palaiPendingAmount: customer.pendingAmount,
    );
  }

  bool _matches(String lowercaseQuery) {
    return name.toLowerCase().contains(lowercaseQuery) ||
        mobile.toLowerCase().contains(lowercaseQuery);
  }
}

/// How much of one payment was applied to one goat sale.
class GoatSaleSettlementLine {
  final String saleId;
  final double amount;

  const GoatSaleSettlementLine({
    required this.saleId,
    required this.amount,
  });

  Map<String, dynamic> toMap() => {'saleId': saleId, 'amount': amount};
}

/// What [SalesService.settleSalesInTransaction] applied to goat sales.
class GoatSaleSettlement {
  final List<GoatSaleSettlementLine> lines;

  const GoatSaleSettlement(this.lines);

  double get total {
    var sum = 0.0;

    for (final line in lines) {
      sum += line.amount;
    }

    return SaleDraft.round2(sum);
  }

  bool get isEmpty => lines.isEmpty;
}