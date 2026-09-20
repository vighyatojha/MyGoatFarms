import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_model.dart';
import '../models/expense_categories.dart';
import '../models/goat_model.dart';
import '../models/palai_models.dart';
import '../models/sale_draft.dart';
import '../models/sale_model.dart';
import 'firestore_service.dart';

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

  /// Same aggregate doc TradingService writes `totalStock` /
  /// `pendingRegistrations` to (farms/{farmId}/tradingSummary/dashboard).
  /// SalesService only ever touches `totalStock`, `totalSold`, `booking`
  /// and `waitOnDelivery` here — never `pendingRegistrations` or
  /// `wholesalePurchased`, which belong to the Purchase flow.
  DocumentReference<Map<String, dynamic>> _summaryDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingSummary')
        .doc('dashboard');
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

  /// Writes one Sold Goat Revenue entry for one receipt of money. Safe to
  /// call twice for the same [receiptKey] (same doc, overwritten).
  Future<void> _recordSaleReceiptRevenue({
    required String farmId,
    required String saleId,
    required String receiptKey,
    required double amount,
    required DateTime date,
    required String customerName,
    String paymentMethod = FinancePaymentMethods.other,
    String? note,
  }) async {
    final rounded = SaleDraft.round2(amount);

    if (rounded <= 0) return;

    await _transactions(farmId)
        .doc(_saleRevenueDocId(saleId, receiptKey))
        .set({
      ..._saleRevenueData(
        saleId: saleId,
        amount: rounded,
        date: date,
        paymentMethod: paymentMethod,
        customerName: customerName,
        note: note ?? 'Sold Goat Revenue — Sale $saleId',
      ),
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
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
        sellingPricePerKg: draft.sellingPricePerKg,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        deliveryType: Sale.deliveryTypeDeliverNow,
        status: Sale.statusSold,
        transportCost:
        draft.transportCost > 0 ? draft.transportCost : null,
        amountReceived: draft.amountReceived,
        paymentMethod: draft.paymentMethod,
        paymentStatus: draft.paymentStatusDeliverNow,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every goat to Sold.
      // ---------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final gender = draft.genderFor(goat);

        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusSold,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
          if (gender.isNotEmpty) 'gender': gender,
        });
      }

      // ---------------------------------------------------------------
      // 5. Dashboard aggregate.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock':
          FieldValue.increment(-draft.selectedGoats.length),
          'totalSold':
          FieldValue.increment(draft.selectedGoats.length),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout * 2);

    // -----------------------------------------------------------------
    // FINANCE REVENUE — the goat is Sold immediately in this branch, so
    // the money received now is recorded right away. Only the part that
    // covers the goat sale counts; transport on the customer's bill is
    // never revenue — see the FINANCE INTEGRATION note above.
    // -----------------------------------------------------------------

    await _recordSaleReceiptRevenue(
      farmId: farmId,
      saleId: saleId,
      receiptKey: 'initial',
      amount: Sale.revenueFromPaid(
        paid: draft.amountReceived,
        revenueTotal: draft.totalSaleAmount,
      ),
      date: DateTime.now(),
      customerName: draft.customerName,
      paymentMethod: _methodOrOther(draft.paymentMethod),
    );

    return saleId;
  }

  // -----------------------------------------------------------------------
  // BRANCH B — BOOKING / HOLDING (Task 3.2)
  // -----------------------------------------------------------------------

  /// Saves a "Booking / Holding" sale: goat(s) kept here after an initial
  /// payment, picked up later. Only the creation form (Pair 5 of the
  /// plan's build order) — the "Complete Delivery" action that later
  /// recomputes `Goat Sale Amount + Holding Charges - Amount Already Paid`
  /// is out of scope for this phase (Pair 7 / Phase 5).
  ///
  /// Same re-check-then-write-in-one-transaction shape as
  /// [saveDeliverNow], for the same status-consistency reason.
  Future<String> saveBooking({
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
        sellingPricePerKg: draft.sellingPricePerKg,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        deliveryType: Sale.deliveryTypeBooking,
        status: Sale.statusBooked,
        bookingAmount: draft.bookingAmount,
        paymentMethod: draft.paymentMethod,
        expectedDeliveryDate: draft.expectedDeliveryDate,
        holdingDays: draft.holdingDays,
        holdingChargePerDay: draft.holdingChargePerDay,
        totalHoldingCharges: draft.totalHoldingCharges,
        transportCost: draft.bookingTransportCost > 0
            ? draft.bookingTransportCost
            : null,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every goat to Booked.
      // ---------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final gender = draft.genderFor(goat);

        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusBooked,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
          if (gender.isNotEmpty) 'gender': gender,
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

    return saleId;
  }

  // -----------------------------------------------------------------------
  // BRANCH C — WAIT FOR DELIVERY (Task 3.3)
  // -----------------------------------------------------------------------

  /// Saves a "Wait for Delivery" sale: price/kg and an advance are fixed
  /// now, at today's weight; the goat is weighed again and handed over
  /// later. Only the creation form — the "Complete Delivery" action
  /// (`Final Price = Current Weight x Booking Price/KG - advance`, always
  /// using [Sale.bookingPricePerKg], never the market rate on pickup day)
  /// is out of scope for this phase, same as Branch B.
  Future<String> saveWaitForDelivery({
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
        sellingPricePerKg: draft.sellingPricePerKg,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        deliveryType: Sale.deliveryTypeWaitForDelivery,
        status: Sale.statusWaitForDelivery,
        bookingPricePerKg: draft.bookingPricePerKg,
        bookingAdvanceAmount: draft.bookingAdvanceAmount,
        paymentMethod: draft.paymentMethod,
        bookingWeight: draft.bookingWeightTotal,
        transportCost: draft.waitForDeliveryTransportCost > 0
            ? draft.waitForDeliveryTransportCost
            : null,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every goat to Wait on Delivery.
      // ---------------------------------------------------------------

      for (final goat in draft.selectedGoats) {
        final gender = draft.genderFor(goat);

        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusWaitOnDelivery,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
          if (gender.isNotEmpty) 'gender': gender,
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

    return saleId;
  }

  // -----------------------------------------------------------------------
  // BRANCH D — TRANSFER TO PALAI (Task 3.4)
  // -----------------------------------------------------------------------

  /// Saves a "Transfer to Palai" sale: the customer keeps the goat
  /// boarded here instead of taking it away, so ongoing billing/health
  /// tracking hands off to the Customer Palai module.
  ///
  /// This is NOT fully atomic end-to-end, by necessity, and that
  /// tradeoff is deliberate:
  ///
  /// 1. Resolve/create the PalaiCustomer first, via the real
  ///    FirestoreService.addCustomer — not hand-rolled here — because
  ///    that method owns its own write shape (server timestamp, etc.)
  ///    that shouldn't be duplicated and risk drifting out of sync.
  ///    If this step fails, nothing else has happened yet.
  /// 2. Run the Trading-side transaction (sale doc + goat status +
  ///    stock decrement) — same re-check-then-write pattern as
  ///    saveDeliverNow.
  /// 3. Only after that commits, call the real
  ///    FirestoreService.checkInGoat per goat, so transferred goats
  ///    show up in the actual Palai goat lists.
  ///
  /// Steps 2 and 3 are sequenced this way — Trading-side status flip
  /// before the Palai check-in — so a goat can never end up BOTH still
  /// marked sellable in Trading AND checked into Palai at the same
  /// time. The cost is the reverse case: if checkInGoat fails after
  /// step 2 has already committed, the goat is marked
  /// "In Customer Palai" in Trading without an actual PalaiGoat record
  /// yet, and needs a manual retry/follow-up. Making this fully atomic
  /// would mean re-implementing checkInGoat's writes inside this
  /// transaction by hand, which risks silently diverging from whatever
  /// the Palai module actually relies on.
  Future<String> saveTransferToPalai({
    required String farmId,
    required SaleDraft draft,
  }) async {
    if (draft.selectedGoats.isEmpty) {
      throw StateError('Select at least one goat before saving.');
    }

    // -----------------------------------------------------------------
    // 1. Resolve/create the Palai customer.
    // -----------------------------------------------------------------

    String palaiCustomerId;

    if (draft.customerSource == CustomerMatchSource.palai) {
      palaiCustomerId = draft.customerId;
    } else {
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

      palaiCustomerId = await FirestoreService.instance.addCustomer(
        farmId,
        palaiCustomer,
      );
    }

    // -----------------------------------------------------------------
    // 2. Trading-side transaction.
    // -----------------------------------------------------------------

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

      // Palai branch has no customer write, but keep the same
      // read-then-write discipline.
      final saleNumber = await _readNextSaleNumber(transaction, farmId);
      saleId = _formatSaleId(saleNumber);
      _writeSaleCounter(transaction, farmId, saleNumber);

      final sale = Sale(
        id: saleId,
        goatIds: draft.goatIds,
        customerId: palaiCustomerId,
        customerName: draft.customerName.trim(),
        mobile: draft.mobile.trim(),
        address: draft.address.trim(),
        sellingPricePerKg: draft.sellingPricePerKg,
        sellingWeight: draft.totalSellingWeight,
        totalSaleAmount: draft.totalSaleAmount,
        deliveryType: Sale.deliveryTypePalai,
        status: Sale.statusTransferredToPalai,
        transferDate: draft.transferDate,
        palaiPackage: draft.palaiPackage.trim(),
        monthlyPalaiCharge: draft.monthlyPalaiCharge,
        palaiCustomerId: palaiCustomerId,
      );

      transaction.set(_sales(farmId).doc(saleId), {
        ...sale.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      for (final goat in draft.selectedGoats) {
        final gender = draft.genderFor(goat);

        transaction.update(_goats(farmId).doc(goat.id), {
          'currentStatus': Goat.statusInCustomerPalai,
          'saleId': saleId,
          'weight': draft.weightFor(goat),
          if (gender.isNotEmpty) 'gender': gender,
        });
      }

      // Not counted in totalSold — this isn't a cash sale, it's
      // boarding revenue going forward.
      transaction.set(
        _summaryDoc(farmId),
        {
          'totalStock':
          FieldValue.increment(-draft.selectedGoats.length),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout * 2);

    // -----------------------------------------------------------------
    // 3. Actually check each goat into the Customer Palai module.
    // -----------------------------------------------------------------

    for (final goat in draft.selectedGoats) {
      final gender = draft.genderFor(goat);

      await FirestoreService.instance.checkInGoat(
        farmId,
        palaiCustomerId,
        PalaiGoat(
          id: '',
          customerId: palaiCustomerId,
          breed: goat.breed,
          gender: gender.isEmpty ? 'Male' : gender,
          weightAtCheckIn: draft.weightFor(goat),
          healthStatus:
          goat.healthStatus.isEmpty ? 'Healthy' : goat.healthStatus,
          checkInDate: draft.transferDate ?? DateTime.now(),
          farmArrivalDate: draft.transferDate,
          monthlyPackage: draft.palaiPackage.trim(),
          pricing: draft.monthlyPalaiCharge,
          notes: 'Transferred from Trading sale $saleId.',
        ),
      );
    }

    return saleId;
  }

  // -----------------------------------------------------------------------
  // SALE LOOKUP (Phase 5 groundwork — Complete Delivery needs the sale
  // doc a Booked/Wait-for-Delivery goat is linked to via Goat.saleId)
  // -----------------------------------------------------------------------

  Future<Sale?> getSale(String farmId, String saleId) async {
    final doc =
    await _sales(farmId).doc(saleId).get().timeout(_timeout);

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
  /// Recomputes the final settlement using the *actual* elapsed holding
  /// days the caller supplies — never the original estimate made at
  /// booking time — per the plan's Task 1.2 note that a customer may
  /// pick up later or earlier than first expected:
  ///
  ///   Final Amount = Goat Sale Amount + (actualHoldingDays x Daily
  ///                  Charge) + Transportation Charge - Booking Amount
  ///                  already paid
  ///
  /// The stored [Sale.finalAmountAfterHolding] is what the customer
  /// still owes at pickup, so it includes the transportation charge
  /// billed to them. (Transportation is left out of the Finance
  /// revenue below — it is paid on to the transport team.)
  ///
  /// Same reads-then-writes transaction shape as the Phase 4 branch
  /// save methods, extended to also verify the sale is still in the
  /// state this action expects before touching anything.
  Future<void> completeBookingDelivery({
    required String farmId,
    required String saleId,
    required int actualHoldingDays,
  }) async {
    if (actualHoldingDays < 0) {
      throw StateError('Holding days cannot be negative.');
    }

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

      final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final goatId in sale.goatIds) {
        goatSnaps.add(
          await transaction.get(_goats(farmId).doc(goatId)),
        );
      }

      // ---------------------------------------------------------------
      // 2. Compute the final settlement.
      // ---------------------------------------------------------------

      final holdingChargePerDay = sale.holdingChargePerDay ?? 0;
      final bookingAmount = sale.bookingAmount ?? 0;
      final actualHoldingChargesValue =
          actualHoldingDays * holdingChargePerDay;

      final transportCost = sale.transportCost ?? 0;

      final rawFinalAmount = sale.totalSaleAmount +
          actualHoldingChargesValue +
          transportCost -
          bookingAmount;
      final finalAmount = rawFinalAmount < 0 ? 0.0 : rawFinalAmount;

      // Captured for the Finance revenue write after this transaction
      // commits: the gross sale value (not [finalAmount], which is the
      // remaining balance) and the booking amount already received,
      // which is the money that becomes revenue now that the goat has
      // left. The balance is recorded as it is collected.
      totalSaleAmount = sale.totalSaleAmount;
      actualHoldingCharges = actualHoldingChargesValue;
      bookingAmountPaid = bookingAmount;
      customerName = sale.customerName;
      initialMethod = _methodOrOther(sale.paymentMethod);

      // ---------------------------------------------------------------
      // 3. Update the sale doc.
      // ---------------------------------------------------------------

      transaction.update(saleRef, {
        'status': Sale.statusDeliveryCompleted,
        'actualHoldingDays': actualHoldingDays,
        'totalHoldingCharges': actualHoldingCharges,
        'finalAmountAfterHolding': finalAmount,
        'paymentStatus': _paymentStatusFor(
          balanceDue: finalAmount,
          paid: bookingAmount,
        ),
        'deliveryCompletedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every still-Booked goat in this sale to Sold — it has
      //    now actually left the farm. Skip any goat that's already
      //    moved on (defensive; shouldn't normally happen) rather than
      //    clobbering it.
      // ---------------------------------------------------------------

      var movedGoats = 0;

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
      //    deferred decrement lands now that it actually has.
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'booking': FieldValue.increment(-movedGoats),
          'totalSold': FieldValue.increment(movedGoats),
          'totalStock': FieldValue.increment(-movedGoats),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout * 2);

    // -----------------------------------------------------------------
    // FINANCE REVENUE — the goat has now actually left the farm, so
    // this is where the booking amount already received becomes Sold
    // Goat Revenue (not at saveBooking, when it was only a
    // reservation). The remaining balance is recorded as it is
    // collected — see the FINANCE INTEGRATION note above.
    // -----------------------------------------------------------------

    await _recordSaleReceiptRevenue(
      farmId: farmId,
      saleId: saleId,
      receiptKey: 'initial',
      amount: Sale.revenueFromPaid(
        paid: bookingAmountPaid,
        revenueTotal: totalSaleAmount + actualHoldingCharges,
      ),
      date: DateTime.now(),
      customerName: customerName,
      paymentMethod: initialMethod,
    );
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
  ///                 + Transportation Charge - Advance Paid
  ///
  /// The stored [Sale.finalPriceAfterPickup] is what the customer still
  /// owes at pickup, so it includes the transportation charge billed to
  /// them. (Transportation is left out of the Finance revenue below —
  /// it is paid on to the transport team.)
  ///
  /// Worked example from the plan (Section 2, Task 2.2), with no
  /// transportation charge: 34kg booked, 38kg at delivery, ₹520/kg
  /// fixed, ₹5,000 advance -> ₹14,760 remaining.
  /// 38 x 520 = 19,760; 19,760 - 5,000 = 14,760. ✓ With a ₹1,000
  /// transportation charge the customer owes ₹15,760.
  Future<void> completeWaitForDeliveryPickup({
    required String farmId,
    required String saleId,
    required double pickupWeight,
  }) async {
    if (pickupWeight <= 0) {
      throw StateError('Pickup weight must be greater than zero.');
    }

    // Not `late final`: Firestore may re-run the transaction closure on
    // contention, which would assign these more than once.
    double grossSaleValue = 0;
    double advancePaid = 0;
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

      if (!sale.isWaitForDelivery) {
        throw StateError('Sale $saleId is not a Wait for Delivery sale.');
      }

      if (sale.status != Sale.statusWaitForDelivery) {
        throw StateError(
          'Sale $saleId has already been completed or is in an '
              'unexpected state ("${sale.status}").',
        );
      }

      final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final goatId in sale.goatIds) {
        goatSnaps.add(
          await transaction.get(_goats(farmId).doc(goatId)),
        );
      }

      // ---------------------------------------------------------------
      // 2. Compute the final settlement — booking-time rate, pickup
      //    weight, never today's rate.
      // ---------------------------------------------------------------

      final bookingPricePerKg = sale.bookingPricePerKg ?? 0;
      final bookingAdvanceAmount = sale.bookingAdvanceAmount ?? 0;

      final transportCost = sale.transportCost ?? 0;

      final rawFinalPrice = pickupWeight * bookingPricePerKg +
          transportCost -
          bookingAdvanceAmount;
      final finalPrice = rawFinalPrice < 0 ? 0.0 : rawFinalPrice;

      // Captured for the Finance revenue write after this transaction
      // commits: the gross sale value (pickup weight × booking rate, not
      // [finalPrice], which is the remaining balance) and the advance
      // already received, which is the money that becomes revenue now
      // that the goat has left. The balance is recorded as it is
      // collected.
      grossSaleValue = pickupWeight * bookingPricePerKg;
      advancePaid = bookingAdvanceAmount;
      customerName = sale.customerName;
      initialMethod = _methodOrOther(sale.paymentMethod);

      // ---------------------------------------------------------------
      // 3. Update the sale doc.
      // ---------------------------------------------------------------

      transaction.update(saleRef, {
        'status': Sale.statusPickupCompleted,
        'pickupWeight': pickupWeight,
        'finalPriceAfterPickup': finalPrice,
        'paymentStatus': _paymentStatusFor(
          balanceDue: finalPrice,
          paid: bookingAdvanceAmount,
        ),
        'deliveryCompletedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // 4. Flip every still-Wait-on-Delivery goat in this sale to
      //    Sold — it has now actually left the farm. Skip any goat
      //    that's already moved on (defensive; shouldn't normally
      //    happen) rather than clobbering it.
      // ---------------------------------------------------------------

      var movedGoats = 0;

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
      //    first created (the goat hadn't left the farm yet).
      // ---------------------------------------------------------------

      transaction.set(
        _summaryDoc(farmId),
        {
          'waitOnDelivery': FieldValue.increment(-movedGoats),
          'totalSold': FieldValue.increment(movedGoats),
          'totalStock': FieldValue.increment(-movedGoats),
        },
        SetOptions(merge: true),
      );
    }).timeout(_timeout * 2);

    // -----------------------------------------------------------------
    // FINANCE REVENUE — the goat has now actually left the farm, so
    // this is where the advance already received becomes Sold Goat
    // Revenue: capped at pickup weight × booking rate, transport
    // excluded. The remaining balance is recorded as it is collected —
    // see the FINANCE INTEGRATION note above.
    // -----------------------------------------------------------------

    await _recordSaleReceiptRevenue(
      farmId: farmId,
      saleId: saleId,
      receiptKey: 'initial',
      amount: Sale.revenueFromPaid(
        paid: advancePaid,
        revenueTotal: grossSaleValue,
      ),
      date: DateTime.now(),
      customerName: customerName,
      paymentMethod: initialMethod,
    );
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

      final due = sale.billBalanceDue;

      if (due <= 0) {
        throw StateError('This sale has no balance due.');
      }

      if (paid > due) {
        throw StateError(
          'That is more than the balance due '
              '(₹${due.toStringAsFixed(2)}).',
        );
      }

      final payment = SalePayment(
        amount: paid,
        method: method,
        date: DateTime.now(),
        note: note,
      );

      // Rewrite the raw list (rather than arrayUnion) so the new entry is
      // always appended, even if an identical payment already exists.
      final existing = (saleSnap.data()?['payments'] as List?) ?? const [];
      final dueAfter = SaleDraft.round2(due - paid);

      // Revenue = the part of this payment that covers goat sale +
      // holding charges; anything past that is transportation.
      final revenueDelta = SaleDraft.round2(
        Sale.revenueFromPaid(
          paid: sale.billAmountPaid + paid,
          revenueTotal: sale.billRevenueTotal,
        ) -
            sale.billRevenueReceived,
      );

      transaction.update(saleRef, {
        'payments': [...existing, payment.toMap()],
        'paymentStatus': _paymentStatusFor(
          balanceDue: dueAfter,
          paid: sale.billAmountPaid + paid,
        ),
      });

      if (revenueDelta > 0) {
        final trimmedNote = note.trim();

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
    }).timeout(_timeout * 2);
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