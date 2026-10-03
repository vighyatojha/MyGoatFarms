import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_bill_model.dart';
import '../utils/billing_ledger.dart';
import 'firestore_service.dart';
import 'sales_service.dart';

// ===========================================================================
// LEDGER: reading and writing monthly bills as per-month debt
// ===========================================================================

/// A monthly bill as the ledger sees it: a month with an own charge that
/// may still be partly unpaid.
///
/// Statement bills (billingModel 'statementV2') keep the month's own
/// charge in ownPaid / ownRemaining. Older bills kept it in amountPaid /
/// remainingAmount. A legacy bill that was corrected once by the
/// statement engine also gets own* fields. [hasOwnFields] decides which
/// pair is the month's own balance.
class LedgerBill {
  LedgerBill(this.snapshot);

  final DocumentSnapshot<Map<String, dynamic>> snapshot;

  Map<String, dynamic> get data => snapshot.data() ?? const {};

  DocumentReference<Map<String, dynamic>> get ref => snapshot.reference;

  String get id => snapshot.id;

  bool get exists => snapshot.exists;

  bool get isMonthly => data['type']?.toString() == 'monthly';

  bool get isVoid =>
      data['isVoid'] == true || data['status']?.toString() == 'void';

  bool get isStatement =>
      data['billingModel']?.toString() == MonthlyBill.statementModel;

  bool get hasOwnFields => isStatement || data['ownRemaining'] is num;

  bool get locked => data['locked'] == true;

  /// A correction to an older month (see MonthlyStatementEngine
  /// .addAdjustment). Owed like any month when positive, but never
  /// "the latest bill" and never locked or carried like a bill.
  bool get isAdjustment => data['billingModel'] == 'adjustment';

  String get billNumber => (data['billNumber'] ?? id).toString();

  double _num(String key) => roundMoney((data[key] as num?)?.toDouble() ?? 0);

  double get ownPaid => hasOwnFields ? _num('ownPaid') : _num('amountPaid');

  double get ownRemaining =>
      hasOwnFields ? _num('ownRemaining') : _num('remainingAmount');

  String get periodKey {
    final explicit = (data['billingPeriodKey'] ?? data['periodMonth'])
        ?.toString();
    if (parsePeriodKey(explicit) != null) return explicit!;
    final month = data['billingMonth'];
    if (month is Timestamp) {
      final d = month.toDate();
      return periodKeyOf(d.year, d.month);
    }
    return '0000-00';
  }

  LedgerMonth get asMonth => LedgerMonth(
    billId: id,
    periodKey: periodKey,
    ownRemaining: ownRemaining,
    label: data['ledgerLabel']?.toString(),
  );
}

/// Every live (existing, monthly, not void) bill of one customer, read
/// inside a transaction.
class CustomerLedger {
  CustomerLedger(List<LedgerBill> bills)
      : bills = bills
      .where((b) => b.exists && b.isMonthly && !b.isVoid)
      .toList()
    ..sort((a, b) => a.periodKey.compareTo(b.periodKey));

  /// Oldest month first.
  final List<LedgerBill> bills;

  List<LedgerMonth> get openMonths => bills
      .where((b) => b.ownRemaining > kMoneyEpsilon)
      .map((b) => b.asMonth)
      .toList();

  double get openMonthsTotal => roundMoney(
    openMonths.fold<double>(0, (sum, m) => sum + m.ownRemaining),
  );

  /// Real monthly bills (and opening balances), oldest first, without
  /// adjustments. "Latest bill" decisions use this list.
  List<LedgerBill> get monthBills =>
      bills.where((b) => !b.isAdjustment).toList();

  String? get lastBilledKey {
    final months = monthBills;
    return months.isEmpty ? null : months.last.periodKey;
  }

  /// The newest bill, when it is a statement that is still open for
  /// statement-level payment tracking.
  LedgerBill? get latestStatement {
    final months = monthBills;
    if (months.isEmpty) return null;
    final latest = months.last;
    return latest.isStatement && !latest.locked ? latest : null;
  }

  LedgerBill? byId(String id) {
    for (final b in bills) {
      if (b.id == id) return b;
    }
    return null;
  }
}

/// Collects every field change per document so each bill is written once
/// per transaction, even when it receives both an own-month allocation
/// and a statement payment.
class LedgerWriter {
  final Map<String, DocumentReference<Map<String, dynamic>>> _refs = {};
  final Map<String, Map<String, dynamic>> _changes = {};

  void merge(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> fields,
      ) {
    _refs[ref.path] = ref;
    (_changes[ref.path] ??= <String, dynamic>{}).addAll(fields);
  }

  bool get isEmpty => _changes.isEmpty;

  int get documentCount => _changes.length;

  void flush(Transaction transaction) {
    for (final entry in _changes.entries) {
      transaction.update(_refs[entry.key]!, {
        ...entry.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    _changes.clear();
    _refs.clear();
  }
}

/// Shared read/write rules for Palai dues. Used by payments, the statement
/// engine, Final Checkout and death settlement, so every flow moves money
/// through the months in exactly the same way.
class PalaiLedger {
  PalaiLedger._();

  static final PalaiLedger instance = PalaiLedger._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> monthlyBills(String farmId) =>
      _db.collection('farms').doc(farmId).collection('monthlyBills');

  /// Finds the customer's monthly bills BEFORE a transaction (Firestore
  /// transactions can only re-read documents by reference, not query).
  Future<List<DocumentReference<Map<String, dynamic>>>> monthlyBillRefs(
      String farmId,
      String customerId,
      ) async {
    final snapshot = await monthlyBills(farmId)
        .where('customerId', isEqualTo: customerId)
        .get()
        .timeout(timeout);

    return snapshot.docs
        .where((d) => d.data()['type']?.toString() == 'monthly')
        .map((d) => d.reference)
        .toList();
  }

  /// Re-reads [refs] inside [transaction] so every decision uses fresh data.
  Future<CustomerLedger> read(
      Transaction transaction,
      List<DocumentReference<Map<String, dynamic>>> refs,
      ) async {
    // Read together, not one by one: on a slow connection sequential
    // reads made bigger customers time out.
    final snaps = await Future.wait(refs.map(transaction.get));
    return CustomerLedger(snaps.map(LedgerBill.new).toList());
  }

  /// Applies month allocations (from [allocateOldestFirst]) to the bills.
  void writeMonthAllocations(
      LedgerWriter writer,
      CustomerLedger ledger,
      List<MonthAllocation> allocations, {
        String? paymentId,
      }) {
    for (final allocation in allocations) {
      final bill = ledger.byId(allocation.billId);
      if (bill == null || allocation.amount <= 0) continue;

      final newPaid = roundMoney(bill.ownPaid + allocation.amount);
      final newRemaining = roundMoney(allocation.remainingAfter);
      final status = paymentStatusFor(paid: newPaid, remaining: newRemaining);

      if (bill.hasOwnFields) {
        writer.merge(bill.ref, {
          'ownPaid': newPaid,
          'ownRemaining': newRemaining,
          'ownStatus': status,
        });
      } else {
        writer.merge(bill.ref, {
          'amountPaid': newPaid,
          'remainingAmount': newRemaining,
          'status': status,
          'paymentStatus': status,
          if (newRemaining <= kMoneyEpsilon)
            'paidAt': FieldValue.serverTimestamp(),
          if (paymentId != null) 'lastPaymentId': paymentId,
        });
      }
    }
  }

  /// Records [amount] as received against the latest open statement, so
  /// the statement's own Paid / Remaining match what the customer was
  /// shown. Capped at what that statement still shows as remaining.
  /// Returns the amount recorded.
  double writeStatementPayment(
      LedgerWriter writer,
      CustomerLedger ledger,
      double amount, {
        String? paymentId,
        String? paymentNumber,
        String? paymentMethod,
      }) {
    final statement = ledger.latestStatement;
    if (statement == null || amount <= kMoneyEpsilon) return 0;

    final totalDue = statement._num('totalDue');
    final paid = statement._num('amountPaid');
    final remaining = roundMoney(totalDue - paid);
    if (remaining <= kMoneyEpsilon) return 0;

    final take = roundMoney(amount < remaining ? amount : remaining);
    final newPaid = roundMoney(paid + take);
    final newRemaining = roundMoney(totalDue - newPaid);
    final status = paymentStatusFor(paid: newPaid, remaining: newRemaining);

    writer.merge(statement.ref, {
      'amountPaid': newPaid,
      'remainingAmount': newRemaining < 0 ? 0.0 : newRemaining,
      'status': status,
      'paymentStatus': status,
      if (newRemaining <= kMoneyEpsilon) 'paidAt': FieldValue.serverTimestamp(),
      if (paymentId != null) 'lastPaymentId': paymentId,
      if (paymentNumber != null) 'lastPaymentNumber': paymentNumber,
      if (paymentMethod != null) 'lastPaymentMethod': paymentMethod,
    });

    return take;
  }

  /// Reduces the customer's Palai dues by [amount] (a payment, advance
  /// or waiver): oldest unpaid month first, then dues not tied to a bill.
  /// Never reduces more than [pendingBefore]. Returns the plan; nothing is
  /// written until [writer] is flushed.
  DuesReduction reduceDues({
    required LedgerWriter writer,
    required CustomerLedger ledger,
    required double amount,
    required double pendingBefore,
    bool recordOnStatement = true,
    String? paymentId,
    String? paymentNumber,
    String? paymentMethod,
  }) {
    final cappedPending = pendingBefore < 0 ? 0.0 : pendingBefore;
    final applied = roundMoney(
      amount < cappedPending ? (amount < 0 ? 0.0 : amount) : cappedPending,
    );

    final result = allocateOldestFirst(ledger.openMonths, applied);
    writeMonthAllocations(
      writer,
      ledger,
      result.allocations,
      paymentId: paymentId,
    );

    final onStatement = recordOnStatement
        ? writeStatementPayment(
      writer,
      ledger,
      applied,
      paymentId: paymentId,
      paymentNumber: paymentNumber,
      paymentMethod: paymentMethod,
    )
        : 0.0;

    return DuesReduction(
      applied: applied,
      allocations: result.allocations,
      appliedToOtherDues: result.leftover,
      recordedOnStatement: onStatement,
      excess: roundMoney(amount - applied),
    );
  }
}

class DuesReduction {
  const DuesReduction({
    required this.applied,
    required this.allocations,
    required this.appliedToOtherDues,
    required this.recordedOnStatement,
    required this.excess,
  });

  /// Total taken off pendingAmount.
  final double applied;

  /// Which months it paid.
  final List<MonthAllocation> allocations;

  /// Part that paid Palai dues not tied to a monthly bill.
  final double appliedToOtherDues;

  /// Part recorded against the latest statement's Paid / Remaining.
  final double recordedOnStatement;

  /// What was more than the customer owed on Palai.
  final double excess;
}

// ===========================================================================
// PAYMENTS
// ===========================================================================

/// The ONE rule for money received from a Palai customer, used by
/// Receive Payment, the customer profile and the Monthly Bills screen:
///
///   1. unpaid Palai months, oldest first, then Palai dues not tied to a
///      bill (checkout charges, older balances);
///   2. unpaid goat sales, oldest first (existing Trading settlement);
///   3. anything left becomes the customer's advance.
///
/// Only the part in step 1 is written as Palai income. Goat sales write
/// their own Sold Goat Revenue. Advance is not income until a bill uses it.
class PaymentAllocationService {
  PaymentAllocationService._();

  static final PaymentAllocationService instance =
  PaymentAllocationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  Future<StandalonePaymentResult> receivePayment({
    required String farmId,
    required String customerId,
    required double paidAmount,
    required String paymentMethod,
    String note = '',

    /// Monthly bill the payment was taken from, if any. Recorded on the
    /// payment for reference only; the money is still applied oldest
    /// first, because the bill shows the customer's full Total Payable.
    String? fromBillId,
    String paymentType = 'standalone',
    String incomeCategory = 'Payment Received',
  }) async {
    if (paidAmount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    if (paymentMethod.trim().isEmpty) {
      throw ArgumentError('Please select a payment method.');
    }

    final farmRef = _db.collection('farms').doc(farmId);
    final customerRef =
    farmRef.collection('palaiCustomers').doc(customerId);
    final paymentRef = farmRef.collection('payments').doc();
    final transactionRef = farmRef.collection('transactions').doc();
    final activityRef = farmRef.collection('activities').doc();
    final paymentNumber =
        'PAY-${paymentRef.id.substring(0, 8).toUpperCase()}';
    final method = paymentMethod.trim();

    final billRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);

    // Goat sales owed by the same person. A failed lookup must never block
    // a Palai payment: the excess then simply becomes advance.
    var goatSaleIds = const <String>[];
    try {
      final before = (await customerRef.get().timeout(_timeout)).data() ?? {};
      final credit = await SalesService.instance.creditForPerson(
        farmId,
        customerId: customerId,
        mobile: (before['mobileNumber'] ?? '').toString(),
        name: (before['name'] ?? '').toString(),
      );
      goatSaleIds =
          credit?.sales.map((sale) => sale.id).toList() ?? const <String>[];
    } catch (_) {
      goatSaleIds = const <String>[];
    }

    final actor = await FirestoreService.instance.getCurrentActor();

    return _db.runTransaction<StandalonePaymentResult>((transaction) async {
      // ---------------------------------------------------------------
      // READS
      // ---------------------------------------------------------------
      final customerSnapshot = await transaction.get(customerRef);
      if (!customerSnapshot.exists) {
        throw StateError('Customer no longer exists.');
      }

      final ledger = await PalaiLedger.instance.read(transaction, billRefs);

      final saleSnapshots =
      await SalesService.instance.readSalesForSettlement(
        transaction,
        farmId,
        goatSaleIds,
      );

      final customer = customerSnapshot.data() ?? {};
      final customerName = (customer['name'] ?? '').toString();
      final pendingBefore =
      roundMoney((customer['pendingAmount'] as num?)?.toDouble() ?? 0);
      final advanceBefore =
      roundMoney((customer['advanceAmount'] as num?)?.toDouble() ?? 0);

      // ---------------------------------------------------------------
      // 1. PALAI DUES, OLDEST MONTH FIRST
      // ---------------------------------------------------------------
      final writer = LedgerWriter();
      final reduction = PalaiLedger.instance.reduceDues(
        writer: writer,
        ledger: ledger,
        amount: paidAmount,
        pendingBefore: pendingBefore,
        paymentId: paymentRef.id,
        paymentNumber: paymentNumber,
        paymentMethod: method,
      );
      writer.flush(transaction);

      final appliedToPending = reduction.applied;
      final pendingAfter = roundMoney(pendingBefore - appliedToPending);

      // ---------------------------------------------------------------
      // 2. GOAT SALES, 3. ADVANCE
      // ---------------------------------------------------------------
      final goatSettlement = reduction.excess > 0
          ? SalesService.instance.settleSalesInTransaction(
        transaction: transaction,
        farmId: farmId,
        saleSnapshots: saleSnapshots,
        amount: reduction.excess,
        paymentMethod: method,
        note: 'Received with Customer Palai payment $paymentNumber',
      )
          : const GoatSaleSettlement([]);

      final appliedToGoatSales = roundMoney(goatSettlement.total);
      final advanceAdded =
      roundMoney(reduction.excess - appliedToGoatSales);
      final advanceAfter = roundMoney(
        advanceBefore + (advanceAdded > 0 ? advanceAdded : 0),
      );

      // ---------------------------------------------------------------
      // WRITES
      // ---------------------------------------------------------------
      transaction.set(paymentRef, {
        'paymentNumber': paymentNumber,
        'type': paymentType,
        'customerId': customerId,
        'customerName': customerName,
        if (fromBillId != null) 'billId': fromBillId,
        if (fromBillId != null)
          'billNumber': ledger.byId(fromBillId)?.billNumber ?? fromBillId,
        'amount': paidAmount,
        'amountReceived': paidAmount,
        'amountAppliedToPending': appliedToPending,
        'amountAppliedToBill': appliedToPending,
        'allocations':
        reduction.allocations.map((a) => a.toMap()).toList(),
        'amountAppliedToOtherDues': reduction.appliedToOtherDues,
        'amountAppliedToGoatSales': appliedToGoatSales,
        'goatSalesSettled':
        goatSettlement.lines.map((line) => line.toMap()).toList(),
        'advanceAmount': advanceAdded,
        'advanceAdded': advanceAdded,
        'pendingBefore': pendingBefore,
        'pendingAfter': pendingAfter,
        'advanceBefore': advanceBefore,
        'advanceAfter': advanceAfter,
        'billsUpdated': reduction.allocations.length,
        'paymentMethod': method,
        'note': note.trim(),
        'date': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (appliedToPending > 0) {
        transaction.set(transactionRef, {
          'amount': appliedToPending,
          'isIncome': true,
          'category': incomeCategory,
          'customerId': customerId,
          'customerName': customerName,
          'paymentId': paymentRef.id,
          'paymentNumber': paymentNumber,
          if (fromBillId != null) 'billId': fromBillId,
          'amountAppliedToPending': appliedToPending,
          'advanceAmount': advanceAdded,
          'paymentMethod': method,
          'note': note.trim().isNotEmpty
              ? note.trim()
              : 'Payment received from $customerName',
          'date': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(customerRef, {
        'pendingAmount': pendingAfter,
        'advanceAmount': advanceAfter,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (advanceAdded > 0) {
        transaction.set(
          customerRef.collection('advanceEntries').doc('payment_${paymentRef.id}'),
          {
            'amount': advanceAdded,
            'type': 'credit',
            'source': 'palaiPayment',
            'paymentId': paymentRef.id,
            'paymentNumber': paymentNumber,
            'customerId': customerId,
            'customerName': customerName,
            'note': 'Extra amount received with payment $paymentNumber',
            'date': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }

      transaction.set(activityRef, {
        'type': 'paymentReceived',
        'title': 'Payment Received',
        'subtitle': '$customerName · ₹${paidAmount.toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'paymentId': paymentRef.id,
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });

      return StandalonePaymentResult(
        paymentId: paymentRef.id,
        paymentNumber: paymentNumber,
        customerName: customerName,
        pendingBefore: pendingBefore,
        amountReceived: paidAmount,
        amountAppliedToPending: appliedToPending,
        pendingAfter: pendingAfter,
        amountAppliedToGoatSales: appliedToGoatSales,
        advanceBefore: advanceBefore,
        advanceAdded: advanceAdded,
        advanceAfter: advanceAfter,
        paymentMethod: method,
        billsUpdated: reduction.allocations.length,
      );
    }).timeout(_timeout);
  }
}