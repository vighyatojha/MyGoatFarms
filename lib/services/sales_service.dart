import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../models/customer_credit.dart';
import '../models/customer_model.dart';
import '../models/expense_categories.dart';
import '../models/goat_model.dart';
import '../models/lot_transfer_models.dart';
import '../models/palai_models.dart';
import '../models/sale_draft.dart';
import '../models/sale_model.dart';
import '../models/trading_purchase_model.dart';
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

  String _saleRevenueDocId(String saleId, String receiptKey) =>
      'sale_${saleId}_$receiptKey';

  Map<String, dynamic> _saleRevenueData({
    required String saleId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    required String customerName,
    required String note,
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
        ),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  String _paymentMethodOrCash(String? method) {
    final trimmed = (method ?? '').trim();

    return trimmed.isEmpty ? FinancePaymentMethods.cash : trimmed;
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
      fromSupplier ? lot.supplierQty : lot.farmAvailableQty;

      if (quantity > available) {
        throw StateError(
          fromSupplier
              ? 'Only $available goats are still at the supplier.'
              : 'Only $available goats are available at the farm '
              '(booked goats are not counted).',
        );
      }

      final costPerGoat = lot.lotCostPerGoat;
      final costOfGoodsSold = SaleDraft.round2(costPerGoat * quantity);

      final saleNumber = await _readNextSaleNumber(transaction, farmId);

      // ---------------------------------------------------------------
      // 2. WRITES — customer.
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
        fixedSalePrice: draft.isFixedPrice ? draft.fixedSalePrice : null,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        deliveryType: Sale.deliveryTypeDeliverNow,
        status: Sale.statusSold,
        transportCost: draft.transportCost > 0 ? draft.transportCost : null,
        amountReceived: draft.amountReceived,
        paymentMethod: draft.paymentMethod,
        paymentStatus: draft.paymentStatusDeliverNow,
        onCredit: draft.onCredit && draft.remainingBalanceDeliverNow > 0,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Lot quantities. `pendingCount` mirrors farmQty for lots, so a
      //    farm sale lowers it too. When a supplier sale leaves nothing at
      //    the supplier and something has already arrived, every goat is
      //    accounted for and receiving is complete.
      // ---------------------------------------------------------------

      final supplierAfter =
      fromSupplier ? lot.supplierQty - quantity : lot.supplierQty;

      final lotUpdate = <String, dynamic>{
        if (fromSupplier)
          'soldFromSupplierQty': FieldValue.increment(quantity)
        else ...{
          'soldFromFarmQty': FieldValue.increment(quantity),
          'pendingCount': FieldValue.increment(-quantity),
        },
        if (fromSupplier && supplierAfter <= 0 && lot.receivedTotalQty > 0)
          'receivingStatus': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      transaction.update(lotRef, lotUpdate);

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate. Goats sold at the supplier were never
      //    counted in stock (stock is added when goats arrive), so only a
      //    farm sale lowers totalStock / pendingRegistrations.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          if (!fromSupplier) ...{
            'totalStock': FieldValue.increment(-quantity),
            'pendingRegistrations': FieldValue.increment(-quantity),
          },
          'totalSold': FieldValue.increment(quantity),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(draft.totalSaleAmount - costOfGoodsSold),
          ),
        },
        SetOptions(merge: true),
      );

      // ---------------------------------------------------------------
      // 6. Finance revenue for the money received now (never transport).
      // ---------------------------------------------------------------

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

    return saleId;
  }

  // -----------------------------------------------------------------------
  // LOT BOOKING / WAIT FOR DELIVERY  (shared by Branch B and Branch C)
  // -----------------------------------------------------------------------

  /// Saves a Booking or Wait for Delivery sale made straight from a lot.
  ///
  /// Only for goats already AT THE FARM: a lot still at the supplier can
  /// never be held (the goats are not here to hold), so a supplier source
  /// is rejected outright even though the UI never offers it.
  ///
  /// The goats are held, not sold: the quantity goes into the lot's
  /// `reservedFarmQty` (which lowers `farmAvailableQty` so nobody else can
  /// sell it) and NOT into `soldFromFarmQty`. `farmQty`, `pendingCount`,
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

    if (draft.sourceLocation != Sale.sourceFarm) {
      throw ArgumentError(
        'Booking and Wait for Delivery are only available for goats '
            'already at the farm (source was "${draft.sourceLocation}"). '
            'Goats still at the supplier can only be sold with Deliver Now.',
      );
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

      final available = lot.farmAvailableQty;

      if (quantity > available) {
        throw StateError(
          'Only $available goats are available at the farm '
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
        sourceLocation: Sale.sourceFarm,
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
        'reservedFarmQty': FieldValue.increment(quantity),
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
  /// counted up to the delivery day when the delivery is completed. No
  /// receipt is generated here either — it comes with the delivery.
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
  }) async {
    if (transportCharges < 0) {
      throw StateError('The transportation charge cannot be negative.');
    }

    final transport = SaleDraft.round2(transportCharges);
    final method = _paymentMethodOrCash(paymentMethod);
    final now = DateTime.now();

    final deliveryDay = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
    );

    // Not `late final`: Firestore may re-run the transaction closure on
    // contention, which would assign these more than once.
    double totalSaleAmount = 0;
    double actualHoldingCharges = 0;
    double bookingAmountPaid = 0;
    String customerName = '';
    String initialMethod = FinancePaymentMethods.other;

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Reads first — a Firestore transaction requires every read
      //    to happen before any write.
      // ---------------------------------------------------------------

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

      // Lot sale: the lot doc is read here, in the read phase, and the
      // reservation is checked before anything is written.
      DocumentReference<Map<String, dynamic>>? lotRef;

      if (sale.isLotSale) {
        lotRef = _tradingPurchases(farmId).doc(sale.lotDocId);
        final lotSnap = await transaction.get(lotRef);

        if (!lotSnap.exists) {
          throw StateError('Lot ${sale.lotDocId} no longer exists.');
        }

        final lot = TradingPurchase.fromDoc(lotSnap);

        if (lot.reservedFarmQty < sale.lotQuantity) {
          throw StateError(
            'Lot ${sale.lotDocId} has only ${lot.reservedFarmQty} goats '
                'reserved but this sale holds ${sale.lotQuantity}. '
                'Please check the lot before completing.',
          );
        }

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

      // ---------------------------------------------------------------
      // 1a. Cost of Goods Sold — determine which of these goats will
      //     actually move to Sold below (same eligibility check step 4
      //     uses) and look up their cost now, still in the read phase.
      //     Firestore requires every read in a transaction to happen
      //     before any write, so this can't be deferred to step 4.
      // ---------------------------------------------------------------

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

      // ---------------------------------------------------------------
      // 2. Compute the final settlement.
      // ---------------------------------------------------------------

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

      final actualHoldingDays =
      Sale.holdingDaysBetween(startDay, deliveryDay);

      final holdingChargePerDay = sale.holdingChargePerDay ?? 0;
      final bookingAmount = sale.bookingAmount ?? 0;
      final actualHoldingChargesValue = SaleDraft.round2(
        actualHoldingDays * holdingChargePerDay,
      );

      final rawFinalAmount = SaleDraft.round2(
        sale.totalSaleAmount +
            actualHoldingChargesValue +
            transport -
            bookingAmount,
      );
      final finalAmount = rawFinalAmount < 0 ? 0.0 : rawFinalAmount;

      // Captured for the Finance revenue write later in this same
      // transaction (see _writeInitialRevenueInTransaction below): the
      // gross sale value (not [finalAmount], which is the remaining
      // balance) and the booking amount already received, which is the
      // money that becomes revenue now that the goat has left. The
      // balance is recorded as it is collected.
      totalSaleAmount = sale.totalSaleAmount;
      actualHoldingCharges = actualHoldingChargesValue;
      bookingAmountPaid = bookingAmount;
      customerName = sale.customerName;
      initialMethod = _methodOrOther(sale.paymentMethod);

      // The money received right now, checked against the final amount.
      final received = _checkCompletionPayment(
        finalAmount: finalAmount,
        amountReceivedNow: amountReceivedNow,
        onCredit: onCredit,
      );
      final existingPayments =
          (saleSnap.data()?['payments'] as List?) ?? const [];

      // ---------------------------------------------------------------
      // 3. Update the sale doc.
      // ---------------------------------------------------------------

      transaction.update(saleRef, {
        'status': Sale.statusDeliveryCompleted,
        'holdingStartDate': Timestamp.fromDate(startDay),
        'holdingEndDate': Timestamp.fromDate(deliveryDay),
        'actualHoldingDays': actualHoldingDays,
        'totalHoldingCharges': actualHoldingCharges,
        // Cleared when there is none, so a stale value can never linger
        // on the bill.
        'transportCost': transport > 0 ? transport : FieldValue.delete(),
        'finalAmountAfterHolding': finalAmount,
        ..._completionPaymentFields(
          existingPayments: existingPayments,
          received: received,
          method: method,
          when: now,
          onCredit: finalAmount > 0 && onCredit,
          finalAmount: finalAmount,
          paidBefore: bookingAmount,
        ),
        'deliveryCompletedAt': FieldValue.serverTimestamp(),
      });

      _writeCompletionRevenue(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        customerName: sale.customerName,
        received: received,
        paidBefore: bookingAmount,
        revenueTotal: sale.totalSaleAmount + actualHoldingChargesValue,
        existingPaymentCount: existingPayments.length,
        method: method,
        when: now,
      );

      // ---------------------------------------------------------------
      // 4. Flip every still-Booked goat in this sale to Sold — it has
      //    now actually left the farm. Skip any goat that's already
      //    moved on (defensive; shouldn't normally happen) rather than
      //    clobbering it.
      // ---------------------------------------------------------------

      var movedGoats = sale.isLotSale ? sale.lotQuantity : 0;

      if (sale.isLotSale) {
        // The reserved goats are now sold: reserved -> sold, and the farm
        // stock (mirrored by pendingCount) falls now, not at booking.
        transaction.update(lotRef!, {
          'reservedFarmQty': FieldValue.increment(-sale.lotQuantity),
          'soldFromFarmQty': FieldValue.increment(sale.lotQuantity),
          'pendingCount': FieldValue.increment(-sale.lotQuantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (final snap in goatSnaps) {
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

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate: Booking count decreases, Total Sold
      //    increases. totalStock also decreases here — Phase 4
      //    deliberately left it untouched when the booking was first
      //    created (the goat hadn't left the farm yet), so this
      //    deferred decrement lands now that it actually has. Realized
      //    profit = the goat-only sale value plus holding charges
      //    (never transport) minus what these goats cost to acquire —
      //    computed in step 1a, above the read/write boundary.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'booking': FieldValue.increment(-movedGoats),
          'totalSold': FieldValue.increment(movedGoats),
          'totalStock': FieldValue.increment(-movedGoats),
          if (sale.isLotSale)
            'pendingRegistrations': FieldValue.increment(-movedGoats),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(
              totalSaleAmount + actualHoldingCharges - costOfGoodsSold,
            ),
          ),
        },
        SetOptions(merge: true),
      );

      // -----------------------------------------------------------------
      // FINANCE REVENUE — the goat has now actually left the farm, so
      // this is where the booking amount already received becomes Sold
      // Goat Revenue (not at saveBooking, when it was only a
      // reservation), written in this same transaction. The remaining
      // balance is recorded as it is collected — see the FINANCE
      // INTEGRATION note above.
      // -----------------------------------------------------------------

      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: bookingAmountPaid,
        revenueTotal: totalSaleAmount + actualHoldingCharges,
        date: now,
        customerName: customerName,
        paymentMethod: initialMethod,
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
  /// A Fixed Price sale ([Sale.isFixedPrice]) is not re-priced by the
  /// pickup weight at all: the pickup weight is only recorded, and
  ///
  ///   Final Price = Fixed Price + Transportation - Advance Paid
  ///
  /// The goat value comes from [Sale.goatValueAtWeight].
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
  }) async {
    if (pickupWeight <= 0) {
      throw StateError('Pickup weight must be greater than zero.');
    }

    if (transportCharges < 0) {
      throw StateError('The transportation charge cannot be negative.');
    }

    final transport = SaleDraft.round2(transportCharges);
    final method = _paymentMethodOrCash(paymentMethod);
    final now = DateTime.now();

    // Not `late final`: Firestore may re-run the transaction closure on
    // contention, which would assign these more than once.
    double grossSaleValue = 0;
    double advancePaid = 0;
    String customerName = '';
    String initialMethod = FinancePaymentMethods.other;
    List<String> pickedUpGoatIds = const [];

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. Reads first — a Firestore transaction requires every read
      //    to happen before any write.
      // ---------------------------------------------------------------

      final saleRef = _sales(farmId).doc(saleId);
      final saleSnap = await transaction.get(saleRef);

      if (!saleSnap.exists) {
        throw StateError('Sale $saleId no longer exists.');
      }

      final sale = Sale.fromDoc(saleSnap);
      pickedUpGoatIds = List<String>.from(sale.goatIds);

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

      if (sale.isLotSale) {
        lotRef = _tradingPurchases(farmId).doc(sale.lotDocId);
        final lotSnap = await transaction.get(lotRef);

        if (!lotSnap.exists) {
          throw StateError('Lot ${sale.lotDocId} no longer exists.');
        }

        final lot = TradingPurchase.fromDoc(lotSnap);

        if (lot.reservedFarmQty < sale.lotQuantity) {
          throw StateError(
            'Lot ${sale.lotDocId} has only ${lot.reservedFarmQty} goats '
                'reserved but this sale holds ${sale.lotQuantity}. '
                'Please check the lot before completing.',
          );
        }

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

      // ---------------------------------------------------------------
      // 1a. Cost of Goods Sold — determine which of these goats will
      //     actually move to Sold below (same eligibility check step 4
      //     uses) and look up their cost now, still in the read phase.
      //     Firestore requires every read in a transaction to happen
      //     before any write, so this can't be deferred to step 4.
      // ---------------------------------------------------------------

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

      // ---------------------------------------------------------------
      // 2. Compute the final settlement — booking-time rate, pickup
      //    weight, never today's rate.
      // ---------------------------------------------------------------

      final bookingAdvanceAmount = sale.bookingAdvanceAmount ?? 0;

      // Per KG: pickup weight x the booking-time rate. Fixed price: the
      // agreed price, unchanged by the pickup weight.
      final goatValue = sale.goatValueAtWeight(pickupWeight);

      // Transportation is collected on top of the goat value; the advance
      // already paid is then taken off the whole.
      final rawFinalPrice = SaleDraft.round2(
        goatValue + transport - bookingAdvanceAmount,
      );
      final finalPrice = rawFinalPrice < 0 ? 0.0 : rawFinalPrice;

      // The money received right now, checked against the final amount.
      final received = _checkCompletionPayment(
        finalAmount: finalPrice,
        amountReceivedNow: amountReceivedNow,
        onCredit: onCredit,
      );
      final existingPayments =
          (saleSnap.data()?['payments'] as List?) ?? const [];

      // Captured for the Finance revenue write later in this same
      // transaction (see _writeInitialRevenueInTransaction below): the
      // gross sale value (pickup weight × booking rate, not
      // [finalPrice], which is the remaining balance; and not including
      // transportation, which is never revenue) and the advance
      // already received, which is the money that becomes revenue now
      // that the goat has left. The balance is recorded as it is
      // collected.
      grossSaleValue = goatValue;
      advancePaid = bookingAdvanceAmount;
      customerName = sale.customerName;
      initialMethod = _methodOrOther(sale.paymentMethod);

      // ---------------------------------------------------------------
      // 3. Update the sale doc.
      // ---------------------------------------------------------------

      transaction.update(saleRef, {
        'status': Sale.statusPickupCompleted,
        'pickupWeight': pickupWeight,
        // Cleared when there is none, so a stale value can never linger
        // on the bill.
        'transportCost':
        transport > 0 ? transport : FieldValue.delete(),
        'finalPriceAfterPickup': finalPrice,
        ..._completionPaymentFields(
          existingPayments: existingPayments,
          received: received,
          method: method,
          when: now,
          onCredit: finalPrice > 0 && onCredit,
          finalAmount: finalPrice,
          paidBefore: bookingAdvanceAmount,
        ),
        'deliveryCompletedAt': FieldValue.serverTimestamp(),
      });

      _writeCompletionRevenue(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        customerName: sale.customerName,
        received: received,
        paidBefore: bookingAdvanceAmount,
        revenueTotal: goatValue,
        existingPaymentCount: existingPayments.length,
        method: method,
        when: now,
      );

      // ---------------------------------------------------------------
      // 4. Flip every still-Wait-on-Delivery goat in this sale to
      //    Sold — it has now actually left the farm. Skip any goat
      //    that's already moved on (defensive; shouldn't normally
      //    happen) rather than clobbering it.
      // ---------------------------------------------------------------

      var movedGoats = sale.isLotSale ? sale.lotQuantity : 0;

      if (sale.isLotSale) {
        // The reserved goats are now sold: reserved -> sold, and the farm
        // stock (mirrored by pendingCount) falls now, not at booking.
        transaction.update(lotRef!, {
          'reservedFarmQty': FieldValue.increment(-sale.lotQuantity),
          'soldFromFarmQty': FieldValue.increment(sale.lotQuantity),
          'pendingCount': FieldValue.increment(-sale.lotQuantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (final snap in goatSnaps) {
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

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate: Wait on Delivery count decreases,
      //    Total Sold increases. totalStock also decreases here —
      //    same deferred-decrement reasoning as the Booking branch,
      //    since Branch C never touched totalStock when the sale was
      //    first created (the goat hadn't left the farm yet). Realized
      //    profit = the goat-only sale value (never transport) minus
      //    what these goats cost to acquire — computed in step 1a,
      //    above the read/write boundary.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'waitOnDelivery': FieldValue.increment(-movedGoats),
          'totalSold': FieldValue.increment(movedGoats),
          'totalStock': FieldValue.increment(-movedGoats),
          if (sale.isLotSale)
            'pendingRegistrations': FieldValue.increment(-movedGoats),
          'totalProfit': FieldValue.increment(
            SaleDraft.round2(grossSaleValue - costOfGoodsSold),
          ),
        },
        SetOptions(merge: true),
      );

      // -----------------------------------------------------------------
      // FINANCE REVENUE — the goat has now actually left the farm, so
      // this is where the advance already received becomes Sold Goat
      // Revenue, capped at pickup weight × booking rate, written in this
      // same transaction. The remaining balance is recorded as it is
      // collected — see the FINANCE INTEGRATION note above.
      // -----------------------------------------------------------------

      _writeInitialRevenueInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleId: saleId,
        paid: advancePaid,
        revenueTotal: grossSaleValue,
        date: now,
        customerName: customerName,
        paymentMethod: initialMethod,
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

/// Where a [CustomerMatch] came from.
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

  const CustomerMatch({
    required this.source,
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    this.palaiPackageName,
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