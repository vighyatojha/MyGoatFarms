import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_bill_model.dart';
import 'payment_allocation_service.dart';

/// Reads monthly bills, takes payments from a bill's screen, and checks a
/// customer's figures.
///
/// STATEMENT BILLING: bills are created, corrected and voided by
/// MonthlyStatementEngine; payments are applied by
/// PaymentAllocationService (oldest unpaid month first). The old
/// bill-creation methods that used to live here (createMonthlyBill,
/// createManualMonthlyBill, createCurrentMonthMonthlyBill,
/// updateCurrentMonthMonthlyBill, voidUnpaidMonthlyBill, ...) followed
/// the previous accounting rules and were removed so they can't be used
/// by mistake.
class MonthlyBillPaymentResult {
  final String paymentId;
  final String paymentNumber;

  final String billId;
  final String billNumber;

  final double amountReceived;
  final double amountAppliedToBill;

  final double billRemainingAfter;
  final double pendingAfter;
  final double advanceAfter;

  final String paymentMethod;

  const MonthlyBillPaymentResult({
    required this.paymentId,
    required this.paymentNumber,
    required this.billId,
    required this.billNumber,
    required this.amountReceived,
    required this.amountAppliedToBill,
    required this.billRemainingAfter,
    required this.pendingAfter,
    required this.advanceAfter,
    required this.paymentMethod,
  });
}

class MonthlyBillingService {
  MonthlyBillingService._();

  static final MonthlyBillingService instance =
  MonthlyBillingService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // ===========================================================================
  // COLLECTIONS
  // ===========================================================================

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _customers(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('palaiCustomers');
  }

  CollectionReference<Map<String, dynamic>> _bills(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('monthlyBills');
  }

  // ===========================================================================
  // VALUE HELPERS
  // ===========================================================================

  double _doubleValue(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }

  double _money(
      dynamic value,
      ) {
    return double.parse(
      _doubleValue(value).toStringAsFixed(2),
    );
  }

  // ===========================================================================
  // RECEIVE MONTHLY BILL PAYMENT
  // ===========================================================================

  /// Receives a payment taken from a monthly bill's screen.
  ///
  /// Delegates to [PaymentAllocationService.receivePayment]: unpaid
  /// months oldest first, then other Palai dues, then goat sales, then
  /// advance. The bill is recorded on the payment for reference.
  Future<MonthlyBillPaymentResult>
  receiveMonthlyBillPayment({
    required String farmId,
    required String customerId,
    required String billId,
    required double paidAmount,
    required String paymentMethod,
    String note = '',
  }) async {
    // STATEMENT BILLING: a payment taken from a bill's screen follows the
    // same oldest-first rule as every other Palai payment. The bill shows
    // the customer's full Total Payable, so the money clears the oldest
    // unpaid month first instead of pushing anything above this one
    // month's charge into advance while older months stay unpaid.
    final billSnapshot =
    await _bills(farmId).doc(billId).get().timeout(_timeout);
    final billData = billSnapshot.data() ?? {};

    if (!billSnapshot.exists) {
      throw StateError('Monthly bill no longer exists.');
    }
    if (billData['type']?.toString() != 'monthly') {
      throw StateError('The selected document is not a monthly bill.');
    }
    if ((billData['customerId'] ?? '').toString() != customerId) {
      throw StateError(
        'This monthly bill does not belong to the selected customer.',
      );
    }

    final result = await PaymentAllocationService.instance.receivePayment(
      farmId: farmId,
      customerId: customerId,
      paidAmount: paidAmount,
      paymentMethod: paymentMethod,
      note: note,
      fromBillId: billId,
      paymentType: 'monthlyBillPayment',
      incomeCategory: 'Palai Monthly Bill Payment',
    );

    final after = await _bills(farmId).doc(billId).get().timeout(_timeout);

    return MonthlyBillPaymentResult(
      paymentId: result.paymentId,
      paymentNumber: result.paymentNumber,
      billId: billId,
      billNumber: (billData['billNumber'] ?? billId).toString(),
      amountReceived: result.amountReceived,
      amountAppliedToBill: result.amountAppliedToPending,
      billRemainingAfter: _money(after.data()?['remainingAmount']),
      pendingAfter: result.pendingAfter,
      advanceAfter: result.advanceAfter,
      paymentMethod: result.paymentMethod,
    );
  }

  // ===========================================================================
  // GET / STREAM BILLS
  // ===========================================================================

  Stream<List<MonthlyBill>> allBillsStream(
      String farmId,
      ) {
    return _bills(farmId)
        .snapshots()
        .map(
          (snapshot) {
        final bills = snapshot.docs
            .where(
              (d) =>
          d.data()['type']
              ?.toString() ==
              'monthly',
        )
            .map(
          MonthlyBill.fromDoc,
        )
            .toList();

        bills.sort(
              (a, b) =>
              b.billingMonth
                  .compareTo(
                a.billingMonth,
              ),
        );

        return bills;
      },
    );
  }

  /// The customer's monthly bills, newest first. Deleted bills (void
  /// records kept when a bill is deleted) are never included, so a month
  /// that was deleted and generated again is not counted twice.
  ///
  /// [billsOnly]: leave out opening balances and adjustments, for the
  /// goat screens that read each bill's goat lines.
  Future<List<MonthlyBill>> getMonthlyBills({
    required String farmId,
    required String customerId,
    bool billsOnly = false,
  }) async {
    final snapshot =
    await _bills(farmId)
        .where(
      'customerId',
      isEqualTo: customerId,
    )
        .get()
        .timeout(_timeout);

    final bills = snapshot.docs
        .where(
          (d) =>
      d.data()['type']
          ?.toString() ==
          'monthly',
    )
        .map(
      MonthlyBill.fromDoc,
    )
        .where((bill) => !bill.isVoid)
        .where((bill) =>
    !billsOnly || !(bill.isOpeningBalance || bill.isAdjustment))
        .toList();

    bills.sort(
          (a, b) =>
          b.billingMonth.compareTo(
            a.billingMonth,
          ),
    );

    return bills;
  }

  // ===========================================================================
  // RECONCILE / CHECK
  // ===========================================================================

  /// READ-ONLY since statement billing.
  ///
  /// This used to RAISE pendingAmount to the total of open bill balances.
  /// That silently re-charged amounts that had been waived (goat death)
  /// or settled outside a bill, so it no longer writes anything. It
  /// returns the customer's pendingAmount unchanged; use
  /// [checkCustomerConsistency] to find customers whose figures disagree.
  Future<double> reconcileCustomerOutstanding({
    required String farmId,
    required String customerId,
  }) async {
    final snapshot = await _customers(farmId)
        .doc(customerId)
        .get()
        .timeout(_timeout);

    if (!snapshot.exists) {
      throw StateError('Customer no longer exists.');
    }

    return _money(snapshot.data()?['pendingAmount']);
  }

  /// Flags (never fixes) a customer whose Palai figures disagree:
  /// unpaid months adding up to more than pendingAmount, or a customer
  /// holding both an outstanding balance and an unused advance.
  Future<List<String>> checkCustomerConsistency({
    required String farmId,
    required String customerId,
  }) async {
    final customer = await _customers(farmId)
        .doc(customerId)
        .get()
        .timeout(_timeout);
    final data = customer.data() ?? {};
    final pending = _money(data['pendingAmount']);
    final advance = _money(data['advanceAmount']);

    final bills = await getMonthlyBills(
      farmId: farmId,
      customerId: customerId,
    );
    final openMonths = bills
        .where((b) => !b.isVoid)
        .fold<double>(0, (sum, b) => sum + b.effectiveOwnRemaining);

    final issues = <String>[];
    if (openMonths > pending + 0.5) {
      issues.add(
        'Unpaid months total ₹${openMonths.toStringAsFixed(2)} but the '
            'customer\'s pending is ₹${pending.toStringAsFixed(2)}.',
      );
    }
    if (pending > 0.5 && advance > 0.5) {
      issues.add(
        'Customer has both pending ₹${pending.toStringAsFixed(2)} and '
            'advance ₹${advance.toStringAsFixed(2)}.',
      );
    }
    return issues;
  }
}