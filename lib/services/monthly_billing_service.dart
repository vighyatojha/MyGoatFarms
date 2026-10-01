import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_bill_model.dart';

/// Customer-level recurring monthly billing.
///
/// ACCOUNTING MODEL
/// ----------------
/// customer.pendingAmount = total customer outstanding balance.
///
/// A Monthly Bill contains ONLY its own current-period charge:
///
///   bill totalDue = current-period charges - advance applied to this bill
///   bill remainingAmount = bill totalDue - payments applied to this bill
///
/// Previous customer outstanding is stored only as a snapshot on the new
/// bill. It is NOT added to that bill's own remainingAmount.
///
/// Example:
///
///   Previous outstanding = ₹2,000
///   New bill             = ₹3,000
///   Advance applied      = ₹1,000
///
///   Customer pending = ₹2,000 + ₹3,000 - ₹1,000 = ₹4,000
///   Bill totalDue    = ₹3,000 - ₹1,000 = ₹2,000
///   Bill remaining   = ₹2,000
///
/// After paying ₹2,000:
///
///   Bill remaining   = ₹0
///   Customer pending = ₹2,000
///
/// This keeps historical/customer-level debt separate from the current bill.
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

  static const double _epsilon = 0.001;

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

  CollectionReference<Map<String, dynamic>> _payments(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('payments');
  }

  CollectionReference<Map<String, dynamic>> _transactions(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('transactions');
  }

  CollectionReference<Map<String, dynamic>> _activities(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('activities');
  }

  // ===========================================================================
  // MONTH HELPERS
  // ===========================================================================

  DateTime _firstDayOfMonth(
      int year,
      int month,
      ) {
    return DateTime(year, month, 1);
  }

  DateTime _lastDayOfMonth(
      int year,
      int month,
      ) {
    return DateTime(year, month + 1, 0);
  }

  String _periodKey(
      int year,
      int month,
      ) {
    return '$year-${month.toString().padLeft(2, '0')}';
  }

  String _monthlyBillDocumentId(
      String customerId,
      int year,
      int month,
      ) {
    return 'monthly_${customerId}_${_periodKey(year, month)}';
  }

  String _generateBillNumber(
      String billId,
      int year,
      int month,
      ) {
    final monthText = month.toString().padLeft(2, '0');

    final shortId = billId.length > 6
        ? billId.substring(0, 6)
        : billId;

    return 'MB-$year$monthText-${shortId.toUpperCase()}';
  }

  String _generatePaymentNumber(
      String paymentId,
      ) {
    final shortId = paymentId.length > 8
        ? paymentId.substring(0, 8)
        : paymentId;

    return 'PAY-${shortId.toUpperCase()}';
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

  DateTime _dateValue(
      dynamic value,
      DateTime fallback,
      ) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return fallback;
  }

  DateTime? _nullableDateValue(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  Map<String, dynamic> _farmSnapshot(
      Map<String, dynamic> data,
      ) {
    return {
      'farmName': (data['farmName'] ?? '').toString(),
      'farmAddress': (data['address'] ?? '').toString(),
      'farmPhone': (data['mobileNumber'] ?? '').toString(),
      'farmEmail': (data['email'] ?? '').toString(),
    };
  }

  // ===========================================================================
  // ADVANCE HELPERS
  // ===========================================================================

  void _writeAdvanceCreditEntry({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> customerRef,
    required String customerId,
    required String customerName,
    required String paymentId,
    required String paymentNumber,
    required String billId,
    required String billNumber,
    required double amount,
    required String source,
  }) {
    final value = _money(amount);

    if (value <= 0) {
      return;
    }

    transaction.set(
      customerRef
          .collection('advanceEntries')
          .doc('payment_$paymentId'),
      {
        'amount': value,
        'type': 'credit',
        'source': source,
        'paymentId': paymentId,
        'paymentNumber': paymentNumber,
        'billId': billId,
        'billNumber': billNumber,
        'customerId': customerId,
        'customerName': customerName,
        'note':
        'Extra amount received with payment $paymentNumber '
            '(bill $billNumber)',
        'date': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  void _writeAdvanceUsedEntry({
    required Transaction transaction,
    required String farmId,
    required DocumentReference<Map<String, dynamic>> customerRef,
    required String customerId,
    required String customerName,
    required String billId,
    required String billNumber,
    required String periodKey,
    required double amount,
  }) {
    final entryRef = customerRef
        .collection('advanceEntries')
        .doc('bill_$billId');

    final incomeRef =
    _transactions(farmId).doc('advuse_$billId');

    final value = _money(amount);

    if (value <= 0) {
      transaction.delete(entryRef);
      transaction.delete(incomeRef);
      return;
    }

    transaction.set(
      incomeRef,
      {
        'amount': value,
        'isIncome': true,
        'category': 'Advance Applied to Bill',
        'customerId': customerId,
        'customerName': customerName,
        'billId': billId,
        'billNumber': billNumber,
        'paymentMethod': 'Advance',
        'note': 'Advance used on monthly bill $billNumber',
        'referenceType': 'advanceApplied',
        'referenceId': billId,
        'status': 'active',
        'date': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    transaction.set(
      entryRef,
      {
        'amount': value,
        'type': 'debit',
        'source': 'monthlyBill',
        'billId': billId,
        'billNumber': billNumber,
        'periodKey': periodKey,
        'customerId': customerId,
        'customerName': customerName,
        'note': 'Advance used on monthly bill $billNumber',
        'date': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  // ===========================================================================
  // CREATE MONTHLY BILL
  // ===========================================================================

  /// Creates one monthly bill.
  ///
  /// IMPORTANT:
  ///
  /// previousOutstanding is NOT included in bill.totalDue.
  ///
  /// Example:
  ///
  /// Previous outstanding = 2000
  /// New charges         = 3000
  ///
  /// Customer pending    = 5000
  /// Bill totalDue       = 3000
  /// Bill remaining      = 3000
  Future<MonthlyBill> createMonthlyBill({
    required String farmId,
    required String customerId,
    required int year,
    required int month,
    required double palaiCharges,
    double otherCharges = 0,
    double discount = 0,
    int goatCount = 0,
    String notes = '',
    bool applyAdvance = false,
  }) async {
    if (palaiCharges < 0) {
      throw ArgumentError(
        'Palai charges cannot be negative.',
      );
    }

    if (otherCharges < 0) {
      throw ArgumentError(
        'Other charges cannot be negative.',
      );
    }

    if (discount < 0) {
      throw ArgumentError(
        'Discount cannot be negative.',
      );
    }

    if (month < 1 || month > 12) {
      throw ArgumentError(
        'Invalid billing month.',
      );
    }

    if (goatCount < 0) {
      throw ArgumentError(
        'Goat count cannot be negative.',
      );
    }

    final customerRef =
    _customers(farmId).doc(customerId);

    final farmRef =
    _farms().doc(farmId);

    final periodKey =
    _periodKey(year, month);

    final billId =
    _monthlyBillDocumentId(
      customerId,
      year,
      month,
    );

    final billRef =
    _bills(farmId).doc(billId);

    final activityRef =
    _activities(farmId).doc();

    final billingMonth =
    _firstDayOfMonth(year, month);

    final periodEnd =
    _lastDayOfMonth(year, month);

    final newCharges = _money(
      (palaiCharges + otherCharges - discount)
          .clamp(0, double.infinity),
    );

    return _db
        .runTransaction<MonthlyBill>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(customerRef);

        final farmSnapshot =
        await transaction.get(farmRef);

        final existingBillSnapshot =
        await transaction.get(billRef);

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        if (existingBillSnapshot.exists) {
          throw StateError(
            'A monthly bill already exists for $periodKey.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final farmData =
            farmSnapshot.data() ?? {};

        final customerName =
        (customerData['name'] ?? '')
            .toString()
            .trim();

        if (customerName.isEmpty) {
          throw StateError(
            'Customer name is missing.',
          );
        }

        // Existing customer-level debt.
        final previousOutstanding =
        _money(
          customerData['pendingAmount'],
        );

        // Existing customer advance.
        final advanceBefore =
        _money(
          customerData['advanceAmount'],
        );

        // IMPORTANT:
        // Advance can ONLY reduce this new bill.
        final advanceApplied = applyAdvance
            ? _money(
          advanceBefore
              .clamp(0, newCharges),
        )
            : 0.0;

        // This is ONLY the current bill.
        final billTotalDue =
        _money(
          (newCharges - advanceApplied)
              .clamp(0, double.infinity),
        );

        // Existing outstanding stays untouched and is added to
        // the new bill's remaining balance at customer level.
        final customerPendingAfter =
        _money(
          previousOutstanding + billTotalDue,
        );

        final advanceAfter =
        _money(
          advanceBefore - advanceApplied,
        );

        final billNumber =
        _generateBillNumber(
          billId,
          year,
          month,
        );

        final farm =
        _farmSnapshot(farmData);

        final now =
        DateTime.now();

        final isImmediatelyPaid =
            billTotalDue <= _epsilon;

        // ---------------------------------------------------------------------
        // CREATE BILL
        // ---------------------------------------------------------------------

        transaction.set(
          billRef,
          {
            'type': 'monthly',

            'billNumber': billNumber,

            'customerId': customerId,
            'customerName': customerName,

            'billingPeriodKey': periodKey,
            'periodMonth': periodKey,

            'month': month,
            'year': year,

            'billingMonth':
            Timestamp.fromDate(
              billingMonth,
            ),

            'periodEnd':
            Timestamp.fromDate(
              periodEnd,
            ),

            // CURRENT BILL ONLY
            'palaiCharges': palaiCharges,
            'otherCharges': otherCharges,
            'discount': discount,

            'newCharges': newCharges,

            'currentBillAmount': newCharges,

            // CUSTOMER DEBT SNAPSHOT
            'previousOutstanding':
            previousOutstanding,

            // ADVANCE
            'advanceApplied':
            advanceApplied,

            // CURRENT BILL BALANCE
            'totalDue':
            billTotalDue,

            'amountPaid': 0.0,

            'remainingAmount':
            billTotalDue,

            // CUSTOMER BALANCE AFTER BILL
            'pendingAfter':
            customerPendingAfter,

            // STATUS
            'status': isImmediatelyPaid
                ? 'paid'
                : 'unpaid',

            'paymentStatus': isImmediatelyPaid
                ? 'paid'
                : 'unpaid',

            'paymentId': null,
            'paymentMethod': null,

            'paidAt': isImmediatelyPaid
                ? Timestamp.fromDate(now)
                : null,

            'goatCount': goatCount,

            'notes': notes.trim(),

            ...farm,

            'generatedAt':
            Timestamp.fromDate(now),

            'createdAt':
            FieldValue.serverTimestamp(),

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------------
        // UPDATE CUSTOMER
        // ---------------------------------------------------------------------

        final customerUpdate =
        <String, dynamic>{
          'pendingAmount':
          customerPendingAfter,

          'updatedAt':
          FieldValue.serverTimestamp(),
        };

        if (applyAdvance) {
          customerUpdate[
          'advanceAmount'] =
              advanceAfter;
        }

        transaction.update(
          customerRef,
          customerUpdate,
        );

        // ---------------------------------------------------------------------
        // ADVANCE AUDIT
        // ---------------------------------------------------------------------

        if (advanceApplied > 0) {
          _writeAdvanceUsedEntry(
            transaction: transaction,
            farmId: farmId,
            customerRef: customerRef,
            customerId: customerId,
            customerName: customerName,
            billId: billId,
            billNumber: billNumber,
            periodKey: periodKey,
            amount: advanceApplied,
          );
        }

        // ---------------------------------------------------------------------
        // ACTIVITY
        // ---------------------------------------------------------------------

        transaction.set(
          activityRef,
          {
            'type':
            'monthlyBillGenerated',

            'title':
            'Monthly Bill Generated',

            'subtitle':
            '$customerName · '
                '$periodKey · '
                '₹${newCharges.toStringAsFixed(0)}',

            'module':
            'palai',

            'customerId':
            customerId,

            'billId':
            billId,

            'billNumber':
            billNumber,

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------------
        // RETURN
        // ---------------------------------------------------------------------

        return MonthlyBill(
          id: billId,

          customerId: customerId,

          customerName: customerName,

          billNumber: billNumber,

          billingMonth:
          billingMonth,

          periodEnd:
          periodEnd,

          goatCount:
          goatCount,

          palaiCharges:
          palaiCharges,

          otherCharges:
          otherCharges,

          discount:
          discount,

          previousOutstanding:
          previousOutstanding,

          currentBillAmount:
          newCharges,

          advanceApplied:
          advanceApplied,

          totalDue:
          billTotalDue,

          amountPaid:
          0,

          remainingAmount:
          billTotalDue,

          status:
          isImmediatelyPaid
              ? MonthlyBillStatus.paid
              : MonthlyBillStatus.unpaid,

          generatedAt:
          now,

          paidAt:
          isImmediatelyPaid
              ? now
              : null,

          notes:
          notes.trim(),

          farmName:
          farm['farmName']!.toString(),

          farmAddress:
          farm['farmAddress']!.toString(),

          farmPhone:
          farm['farmPhone']!.toString(),

          farmEmail:
          farm['farmEmail']!.toString(),
        );
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // MANUAL MONTHLY BILL
  // ===========================================================================

  /// Creates a manually entered monthly bill.
  ///
  /// IMPORTANT:
  ///
  /// outstandingAmount = NEW BILL AMOUNT.
  ///
  /// It does NOT replace the customer's existing pendingAmount.
  Future<MonthlyBill> createManualMonthlyBill({
    required String farmId,
    required String customerId,
    required int year,
    required int month,
    required double outstandingAmount,
    double advanceAmount = 0,
    int goatCount = 0,
    String notes = '',
  }) async {
    if (outstandingAmount < 0) {
      throw ArgumentError(
        'Outstanding amount cannot be negative.',
      );
    }

    if (advanceAmount < 0) {
      throw ArgumentError(
        'Advance amount cannot be negative.',
      );
    }

    if (month < 1 || month > 12) {
      throw ArgumentError(
        'Invalid billing month.',
      );
    }

    final customerRef =
    _customers(farmId).doc(customerId);

    final farmRef =
    _farms().doc(farmId);

    final periodKey =
    _periodKey(year, month);

    final billId =
    _monthlyBillDocumentId(
      customerId,
      year,
      month,
    );

    final billRef =
    _bills(farmId).doc(billId);

    final activityRef =
    _activities(farmId).doc();

    final billingMonth =
    _firstDayOfMonth(year, month);

    final periodEnd =
    _lastDayOfMonth(year, month);

    final billAmount =
    _money(outstandingAmount);

    return _db
        .runTransaction<MonthlyBill>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        final farmSnapshot =
        await transaction.get(
          farmRef,
        );

        final existingBillSnapshot =
        await transaction.get(
          billRef,
        );

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        if (existingBillSnapshot.exists) {
          throw StateError(
            'A monthly bill already exists for $periodKey.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final customerName =
        (customerData['name'] ?? '')
            .toString()
            .trim();

        if (customerName.isEmpty) {
          throw StateError(
            'Customer name is missing.',
          );
        }

        final previousOutstanding =
        _money(
          customerData['pendingAmount'],
        );

        final advanceBefore =
        _money(
          customerData['advanceAmount'],
        );

        final advanceApplied =
        _money(
          advanceAmount
              .clamp(0, advanceBefore)
              .clamp(0, billAmount),
        );

        final billTotalDue =
        _money(
          (billAmount - advanceApplied)
              .clamp(0, double.infinity),
        );

        final pendingAfter =
        _money(
          previousOutstanding +
              billTotalDue,
        );

        final advanceAfter =
        _money(
          advanceBefore -
              advanceApplied,
        );

        final billNumber =
        _generateBillNumber(
          billId,
          year,
          month,
        );

        final farm =
        _farmSnapshot(
          farmSnapshot.data() ?? {},
        );

        final now =
        DateTime.now();

        final isImmediatelyPaid =
            billTotalDue <= _epsilon;

        transaction.set(
          billRef,
          {
            'type': 'monthly',

            'billNumber':
            billNumber,

            'customerId':
            customerId,

            'customerName':
            customerName,

            'billingPeriodKey':
            periodKey,

            'periodMonth':
            periodKey,

            'month':
            month,

            'year':
            year,

            'billingMonth':
            Timestamp.fromDate(
              billingMonth,
            ),

            'periodEnd':
            Timestamp.fromDate(
              periodEnd,
            ),

            'palaiCharges':
            0.0,

            'otherCharges':
            0.0,

            'discount':
            0.0,

            'newCharges':
            billAmount,

            'currentBillAmount':
            billAmount,

            'previousOutstanding':
            previousOutstanding,

            'advanceApplied':
            advanceApplied,

            'totalDue':
            billTotalDue,

            'amountPaid':
            0.0,

            'remainingAmount':
            billTotalDue,

            'pendingAfter':
            pendingAfter,

            'status':
            isImmediatelyPaid
                ? 'paid'
                : 'unpaid',

            'paymentStatus':
            isImmediatelyPaid
                ? 'paid'
                : 'unpaid',

            'paymentId':
            null,

            'paymentMethod':
            null,

            'paidAt':
            isImmediatelyPaid
                ? Timestamp.fromDate(now)
                : null,

            'goatCount':
            goatCount,

            'notes':
            notes.trim(),

            ...farm,

            'generatedAt':
            Timestamp.fromDate(now),

            'createdAt':
            FieldValue.serverTimestamp(),

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            pendingAfter,

            'advanceAmount':
            advanceAfter,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        if (advanceApplied > 0) {
          _writeAdvanceUsedEntry(
            transaction: transaction,
            farmId: farmId,
            customerRef: customerRef,
            customerId: customerId,
            customerName: customerName,
            billId: billId,
            billNumber: billNumber,
            periodKey: periodKey,
            amount: advanceApplied,
          );
        }

        transaction.set(
          activityRef,
          {
            'type':
            'monthlyBillGenerated',

            'title':
            'Monthly Bill Generated',

            'subtitle':
            '$customerName · '
                '$periodKey · '
                '₹${billAmount.toStringAsFixed(0)}',

            'module':
            'palai',

            'customerId':
            customerId,

            'billId':
            billId,

            'billNumber':
            billNumber,

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        return MonthlyBill(
          id:
          billId,

          customerId:
          customerId,

          customerName:
          customerName,

          billNumber:
          billNumber,

          billingMonth:
          billingMonth,

          periodEnd:
          periodEnd,

          goatCount:
          goatCount,

          palaiCharges:
          0,

          otherCharges:
          0,

          discount:
          0,

          previousOutstanding:
          previousOutstanding,

          currentBillAmount:
          billAmount,

          advanceApplied:
          advanceApplied,

          totalDue:
          billTotalDue,

          amountPaid:
          0,

          remainingAmount:
          billTotalDue,

          status:
          isImmediatelyPaid
              ? MonthlyBillStatus.paid
              : MonthlyBillStatus.unpaid,

          generatedAt:
          now,

          paidAt:
          isImmediatelyPaid
              ? now
              : null,

          notes:
          notes.trim(),

          farmName:
          farm['farmName']!.toString(),

          farmAddress:
          farm['farmAddress']!.toString(),

          farmPhone:
          farm['farmPhone']!.toString(),

          farmEmail:
          farm['farmEmail']!.toString(),
        );
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // CURRENT MONTH BILL
  // ===========================================================================

  Future<MonthlyBill> createCurrentMonthMonthlyBill({
    required String farmId,
    required String customerId,
    required int year,
    required int month,
    required double palaiCharges,
    required double currentOutstanding,
    required double currentAdvance,
    List<GoatBillingLine> goatBreakdown = const [],
    int goatCount = 0,
    String notes = '',
  }) async {
    if (palaiCharges < 0 ||
        currentOutstanding < 0 ||
        currentAdvance < 0) {
      throw ArgumentError(
        'Billing amounts cannot be negative.',
      );
    }

    if (month < 1 || month > 12) {
      throw ArgumentError(
        'Invalid billing month.',
      );
    }

    final customerRef =
    _customers(farmId).doc(customerId);

    final farmRef =
    _farms().doc(farmId);

    final periodKey =
    _periodKey(year, month);

    final billId =
    _monthlyBillDocumentId(
      customerId,
      year,
      month,
    );

    final billRef =
    _bills(farmId).doc(billId);

    final activityRef =
    _activities(farmId).doc();

    final billingMonth =
    _firstDayOfMonth(year, month);

    final periodEnd =
    _lastDayOfMonth(year, month);

    return _db
        .runTransaction<MonthlyBill>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        final farmSnapshot =
        await transaction.get(
          farmRef,
        );

        final existingBillSnapshot =
        await transaction.get(
          billRef,
        );

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        if (existingBillSnapshot.exists) {
          throw StateError(
            'A monthly bill already exists for $periodKey.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final customerName =
        (customerData['name'] ?? '')
            .toString()
            .trim();

        if (customerName.isEmpty) {
          throw StateError(
            'Customer name is missing.',
          );
        }

        final livePending =
        _money(
          customerData['pendingAmount'],
        );

        final liveAdvance =
        _money(
          customerData['advanceAmount'],
        );

        // currentOutstanding is treated as a snapshot only.
        //
        // The live customer pendingAmount remains the authoritative
        // account balance.
        final previousOutstanding =
            livePending;

        final advanceApplied =
        _money(
          currentAdvance
              .clamp(0, liveAdvance)
              .clamp(0, palaiCharges),
        );

        final billTotalDue =
        _money(
          (palaiCharges - advanceApplied)
              .clamp(0, double.infinity),
        );

        final pendingAfter =
        _money(
          previousOutstanding +
              billTotalDue,
        );

        final advanceAfter =
        _money(
          liveAdvance -
              advanceApplied,
        );

        final billNumber =
        _generateBillNumber(
          billId,
          year,
          month,
        );

        final farm =
        _farmSnapshot(
          farmSnapshot.data() ?? {},
        );

        final now =
        DateTime.now();

        final isImmediatelyPaid =
            billTotalDue <= _epsilon;

        transaction.set(
          billRef,
          {
            'type':
            'monthly',

            'billNumber':
            billNumber,

            'customerId':
            customerId,

            'customerName':
            customerName,

            'billingPeriodKey':
            periodKey,

            'periodMonth':
            periodKey,

            'month':
            month,

            'year':
            year,

            'billingMonth':
            Timestamp.fromDate(
              billingMonth,
            ),

            'periodEnd':
            Timestamp.fromDate(
              periodEnd,
            ),

            'palaiCharges':
            palaiCharges,

            'otherCharges':
            0.0,

            'discount':
            0.0,

            'newCharges':
            palaiCharges,

            'currentBillAmount':
            palaiCharges,

            'previousOutstanding':
            previousOutstanding,

            'advanceApplied':
            advanceApplied,

            'totalDue':
            billTotalDue,

            'amountPaid':
            0.0,

            'remainingAmount':
            billTotalDue,

            'pendingAfter':
            pendingAfter,

            'status':
            isImmediatelyPaid
                ? 'paid'
                : 'unpaid',

            'paymentStatus':
            isImmediatelyPaid
                ? 'paid'
                : 'unpaid',

            'paymentId':
            null,

            'paymentMethod':
            null,

            'paidAt':
            isImmediatelyPaid
                ? Timestamp.fromDate(now)
                : null,

            'goatCount':
            goatCount,

            'goatBreakdown':
            goatBreakdown
                .map(
                  (g) => g.toMap(),
            )
                .toList(),

            'notes':
            notes.trim(),

            ...farm,

            'generatedAt':
            Timestamp.fromDate(now),

            'createdAt':
            FieldValue.serverTimestamp(),

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            pendingAfter,

            'advanceAmount':
            advanceAfter,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        if (advanceApplied > 0) {
          _writeAdvanceUsedEntry(
            transaction: transaction,
            farmId: farmId,
            customerRef: customerRef,
            customerId: customerId,
            customerName: customerName,
            billId: billId,
            billNumber: billNumber,
            periodKey: periodKey,
            amount: advanceApplied,
          );
        }

        transaction.set(
          activityRef,
          {
            'type':
            'monthlyBillGenerated',

            'title':
            'Monthly Bill Generated',

            'subtitle':
            '$customerName · '
                '$periodKey · '
                '₹${palaiCharges.toStringAsFixed(0)}',

            'module':
            'palai',

            'customerId':
            customerId,

            'billId':
            billId,

            'billNumber':
            billNumber,

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        return MonthlyBill(
          id:
          billId,

          customerId:
          customerId,

          customerName:
          customerName,

          billNumber:
          billNumber,

          billingMonth:
          billingMonth,

          periodEnd:
          periodEnd,

          goatCount:
          goatCount,

          palaiCharges:
          palaiCharges,

          otherCharges:
          0,

          discount:
          0,

          previousOutstanding:
          previousOutstanding,

          currentBillAmount:
          palaiCharges,

          advanceApplied:
          advanceApplied,

          totalDue:
          billTotalDue,

          amountPaid:
          0,

          remainingAmount:
          billTotalDue,

          status:
          isImmediatelyPaid
              ? MonthlyBillStatus.paid
              : MonthlyBillStatus.unpaid,

          generatedAt:
          now,

          paidAt:
          isImmediatelyPaid
              ? now
              : null,

          notes:
          notes.trim(),

          farmName:
          farm['farmName']!.toString(),

          farmAddress:
          farm['farmAddress']!.toString(),

          farmPhone:
          farm['farmPhone']!.toString(),

          farmEmail:
          farm['farmEmail']!.toString(),

          goatBreakdown:
          goatBreakdown,
        );
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // UPDATE CURRENT MONTH BILL
  // ===========================================================================

  Future<MonthlyBill> updateCurrentMonthMonthlyBill({
    required String farmId,
    required String customerId,
    required String billId,
    required double palaiCharges,
    required double currentOutstanding,
    required double currentAdvance,
    List<GoatBillingLine> goatBreakdown = const [],
    int goatCount = 0,
    String? notes,
  }) async {
    if (palaiCharges < 0 ||
        currentOutstanding < 0 ||
        currentAdvance < 0) {
      throw ArgumentError(
        'Billing amounts cannot be negative.',
      );
    }

    final customerRef =
    _customers(farmId).doc(customerId);

    final billRef =
    _bills(farmId).doc(billId);

    final activityRef =
    _activities(farmId).doc();

    return _db
        .runTransaction<MonthlyBill>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        final billSnapshot =
        await transaction.get(
          billRef,
        );

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        if (!billSnapshot.exists) {
          throw StateError(
            'Monthly bill no longer exists.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final billData =
            billSnapshot.data() ?? {};

        if (billData['type']?.toString() !=
            'monthly') {
          throw StateError(
            'This is not a monthly bill.',
          );
        }

        if ((billData['customerId'] ?? '')
            .toString() !=
            customerId) {
          throw StateError(
            'This monthly bill does not belong to this customer.',
          );
        }

        final currentBill =
        MonthlyBill.fromDoc(
          billSnapshot,
        );

        final oldRemaining =
        _money(
          billData['remainingAmount'],
        );

        final oldAmountPaid =
        _money(
          billData['amountPaid'],
        );

        final oldAdvanceApplied =
        _money(
          billData['advanceApplied'],
        );

        final liveAdvance =
        _money(
          customerData['advanceAmount'],
        );

        // Restore the old advance usage first.
        final availableAdvance =
        _money(
          liveAdvance +
              oldAdvanceApplied,
        );

        final newAdvanceApplied =
        _money(
          currentAdvance
              .clamp(0, availableAdvance)
              .clamp(0, palaiCharges),
        );

        final newBillTotal =
        _money(
          (palaiCharges -
              newAdvanceApplied)
              .clamp(0, double.infinity),
        );

        // Do not allow editing a bill into an amount lower than
        // money already paid against it.
        if (newBillTotal + _epsilon <
            oldAmountPaid) {
          throw StateError(
            'The new bill amount cannot be lower than '
                'the amount already paid on this bill '
                '(₹${oldAmountPaid.toStringAsFixed(2)}).',
          );
        }

        final newRemaining =
        _money(
          (newBillTotal -
              oldAmountPaid)
              .clamp(0, double.infinity),
        );

        final currentPending =
        _money(
          customerData['pendingAmount'],
        );

        // IMPORTANT:
        //
        // Customer pending contains the OLD BILL'S REMAINING BALANCE,
        // not its totalDue.
        //
        // Therefore:
        //
        // newPending =
        //     currentPending
        //     - oldRemaining
        //     + newRemaining
        final newPending =
        _money(
          (currentPending -
              oldRemaining +
              newRemaining)
              .clamp(0, double.infinity),
        );

        final newAdvanceAfter =
        _money(
          availableAdvance -
              newAdvanceApplied,
        );

        final isPaid =
            newRemaining <= _epsilon;

        final status = isPaid
            ? MonthlyBillStatus.paid
            : oldAmountPaid > _epsilon
            ? MonthlyBillStatus.partial
            : MonthlyBillStatus.unpaid;

        transaction.update(
          billRef,
          {
            'palaiCharges':
            palaiCharges,

            'newCharges':
            palaiCharges,

            'currentBillAmount':
            palaiCharges,

            'previousOutstanding':
            currentOutstanding,

            'advanceApplied':
            newAdvanceApplied,

            'totalDue':
            newBillTotal,

            'amountPaid':
            oldAmountPaid,

            'remainingAmount':
            newRemaining,

            'pendingAfter':
            newPending,

            'status':
            MonthlyBill.statusToString(
              status,
            ),

            'paymentStatus':
            MonthlyBill.statusToString(
              status,
            ),

            'goatCount':
            goatCount,

            'goatBreakdown':
            goatBreakdown
                .map(
                  (g) => g.toMap(),
            )
                .toList(),

            if (notes != null)
              'notes': notes.trim(),

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            newPending,

            'advanceAmount':
            newAdvanceAfter,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        _writeAdvanceUsedEntry(
          transaction: transaction,
          farmId: farmId,
          customerRef: customerRef,
          customerId: customerId,
          customerName:
          (customerData['name'] ?? '')
              .toString(),
          billId: billId,
          billNumber:
          (billData['billNumber'] ??
              billId)
              .toString(),
          periodKey:
          (billData['billingPeriodKey'] ??
              '')
              .toString(),
          amount:
          newAdvanceApplied,
        );

        transaction.set(
          activityRef,
          {
            'type':
            'monthlyBillUpdated',

            'title':
            'Monthly Bill Updated',

            'subtitle':
            '${currentBill.customerName} · '
                '${currentBill.billingPeriodKey} · '
                '₹${newBillTotal.toStringAsFixed(0)}',

            'module':
            'palai',

            'customerId':
            customerId,

            'billId':
            billId,

            'billNumber':
            currentBill.billNumber,

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        return currentBill.copyWith(
          palaiCharges:
          palaiCharges,

          currentBillAmount:
          palaiCharges,

          previousOutstanding:
          currentOutstanding,

          advanceApplied:
          newAdvanceApplied,

          totalDue:
          newBillTotal,

          amountPaid:
          oldAmountPaid,

          remainingAmount:
          newRemaining,

          status:
          status,

          goatCount:
          goatCount,

          goatBreakdown:
          goatBreakdown,

          notes:
          notes?.trim() ??
              currentBill.notes,
        );
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // RECEIVE MONTHLY BILL PAYMENT
  // ===========================================================================

  /// Receives a payment against a monthly bill.
  ///
  /// If payment > bill remaining:
  ///
  ///   bill portion  -> bill payment
  ///   extra portion -> customer advance
  ///
  /// Only the amount actually applied to the bill is recorded as revenue.
  /// The extra amount is stored as advance.
  Future<MonthlyBillPaymentResult>
  receiveMonthlyBillPayment({
    required String farmId,
    required String customerId,
    required String billId,
    required double paidAmount,
    required String paymentMethod,
    String note = '',
  }) async {
    if (paidAmount <= 0) {
      throw ArgumentError(
        'Payment amount must be greater than zero.',
      );
    }

    if (paymentMethod.trim().isEmpty) {
      throw ArgumentError(
        'Please select a payment method.',
      );
    }

    final customerRef =
    _customers(farmId).doc(customerId);

    final billRef =
    _bills(farmId).doc(billId);

    final paymentRef =
    _payments(farmId).doc();

    final transactionRef =
    _transactions(farmId).doc();

    final activityRef =
    _activities(farmId).doc();

    final paymentNumber =
    _generatePaymentNumber(
      paymentRef.id,
    );

    return _db
        .runTransaction<
        MonthlyBillPaymentResult>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        final billSnapshot =
        await transaction.get(
          billRef,
        );

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        if (!billSnapshot.exists) {
          throw StateError(
            'Monthly bill no longer exists.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final billData =
            billSnapshot.data() ?? {};

        if (billData['type']?.toString() !=
            'monthly') {
          throw StateError(
            'The selected document is not a monthly bill.',
          );
        }

        if ((billData['customerId'] ?? '')
            .toString() !=
            customerId) {
          throw StateError(
            'This monthly bill does not belong to the selected customer.',
          );
        }

        final customerName =
        (customerData['name'] ?? '')
            .toString();

        final billNumber =
        (billData['billNumber'] ??
            billId)
            .toString();

        final currentPending =
        _money(
          customerData['pendingAmount'],
        );

        final currentAdvance =
        _money(
          customerData['advanceAmount'],
        );

        final billRemaining =
        _money(
          billData['remainingAmount'],
        );

        final currentPaid =
        _money(
          billData['amountPaid'],
        );

        if (billRemaining <= _epsilon) {
          throw StateError(
            'This monthly bill is already paid.',
          );
        }

        // ---------------------------------------------------------------------
        // SPLIT PAYMENT
        // ---------------------------------------------------------------------

        final amountApplied =
        _money(
          paidAmount.clamp(
            0,
            billRemaining,
          ),
        );

        final extraAmount =
        _money(
          paidAmount -
              amountApplied,
        );

        if (amountApplied >
            currentPending + _epsilon) {
          throw StateError(
            'Customer outstanding is lower than '
                'the amount being applied to this bill.',
          );
        }

        final newAmountPaid =
        _money(
          currentPaid +
              amountApplied,
        );

        final newRemaining =
        _money(
          billRemaining -
              amountApplied,
        );

        final newPending =
        _money(
          currentPending -
              amountApplied,
        );

        final newAdvance =
        _money(
          currentAdvance +
              extraAmount,
        );

        final isFullyPaid =
            newRemaining <= _epsilon;

        final newStatus =
        isFullyPaid
            ? 'paid'
            : 'partial';

        // ---------------------------------------------------------------------
        // PAYMENT RECORD
        // ---------------------------------------------------------------------

        transaction.set(
          paymentRef,
          {
            'paymentNumber':
            paymentNumber,

            'type':
            'monthlyBillPayment',

            'customerId':
            customerId,

            'customerName':
            customerName,

            'billId':
            billId,

            'billNumber':
            billNumber,

            'amount':
            paidAmount,

            'amountReceived':
            paidAmount,

            'amountAppliedToBill':
            amountApplied,

            'advanceAdded':
            extraAmount,

            'pendingBefore':
            currentPending,

            'pendingAfter':
            newPending,

            'advanceBefore':
            currentAdvance,

            'advanceAfter':
            newAdvance,

            'billRemainingBefore':
            billRemaining,

            'billRemainingAfter':
            newRemaining,

            'billAmountPaidBefore':
            currentPaid,

            'billAmountPaidAfter':
            newAmountPaid,

            'paymentMethod':
            paymentMethod.trim(),

            'note':
            note.trim(),

            'date':
            FieldValue.serverTimestamp(),

            'createdAt':
            FieldValue.serverTimestamp(),

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------------
        // BILL UPDATE
        // ---------------------------------------------------------------------

        transaction.update(
          billRef,
          {
            'amountPaid':
            newAmountPaid,

            'remainingAmount':
            newRemaining,

            'status':
            newStatus,

            'paymentStatus':
            newStatus,

            'lastPaymentId':
            paymentRef.id,

            'lastPaymentNumber':
            paymentNumber,

            'lastPaymentAmount':
            paidAmount,

            'lastPaymentMethod':
            paymentMethod.trim(),

            'paymentId':
            isFullyPaid
                ? paymentRef.id
                : billData['paymentId'],

            'paymentMethod':
            isFullyPaid
                ? paymentMethod.trim()
                : billData['paymentMethod'],

            'paidAt':
            isFullyPaid
                ? FieldValue.serverTimestamp()
                : billData['paidAt'],

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------------
        // CUSTOMER UPDATE
        // ---------------------------------------------------------------------

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            newPending,

            'advanceAmount':
            newAdvance,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------------
        // ADVANCE CREDIT
        // ---------------------------------------------------------------------

        if (extraAmount > 0) {
          _writeAdvanceCreditEntry(
            transaction: transaction,
            customerRef: customerRef,
            customerId: customerId,
            customerName: customerName,
            paymentId: paymentRef.id,
            paymentNumber: paymentNumber,
            billId: billId,
            billNumber: billNumber,
            amount: extraAmount,
            source:
            'monthlyBillPayment',
          );
        }

        // ---------------------------------------------------------------------
        // INCOME TRANSACTION
        // ---------------------------------------------------------------------
        //
        // IMPORTANT:
        // Only amountAppliedToBill is revenue.
        //
        // Extra amount is advance and is NOT counted as revenue again when
        // it is later applied to another bill.
        // ---------------------------------------------------------------------

        if (amountApplied > 0) {
          transaction.set(
            transactionRef,
            {
              'type':
              'income',

              'isIncome':
              true,

              'category':
              'Palai Monthly Bill Payment',

              'amount':
              amountApplied,

              'customerId':
              customerId,

              'customerName':
              customerName,

              'billId':
              billId,

              'billNumber':
              billNumber,

              'paymentId':
              paymentRef.id,

              'paymentNumber':
              paymentNumber,

              'amountAppliedToBill':
              amountApplied,

              'advanceAmount':
              extraAmount,

              'paymentMethod':
              paymentMethod.trim(),

              'note':
              note.trim().isEmpty
                  ? 'Monthly bill payment from '
                  '$customerName'
                  : note.trim(),

              'date':
              FieldValue.serverTimestamp(),

              'createdAt':
              FieldValue.serverTimestamp(),
            },
          );
        }

        // ---------------------------------------------------------------------
        // ACTIVITY
        // ---------------------------------------------------------------------

        transaction.set(
          activityRef,
          {
            'type':
            'paymentReceived',

            'title':
            isFullyPaid
                ? 'Monthly Bill Paid'
                : 'Monthly Bill Partially Paid',

            'subtitle':
            '$customerName · '
                '$billNumber · '
                '₹${paidAmount.toStringAsFixed(0)}',

            'module':
            'palai',

            'customerId':
            customerId,

            'billId':
            billId,

            'paymentId':
            paymentRef.id,

            'timestamp':
            FieldValue.serverTimestamp(),

            'createdAt':
            FieldValue.serverTimestamp(),
          },
        );

        return MonthlyBillPaymentResult(
          paymentId:
          paymentRef.id,

          paymentNumber:
          paymentNumber,

          billId:
          billId,

          billNumber:
          billNumber,

          amountReceived:
          paidAmount,

          amountAppliedToBill:
          amountApplied,

          billRemainingAfter:
          newRemaining,

          pendingAfter:
          newPending,

          advanceAfter:
          newAdvance,

          paymentMethod:
          paymentMethod.trim(),
        );
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // APPLY PAYMENT - COMPATIBILITY METHOD
  // ===========================================================================

  /// Compatibility method used by existing Monthly Bills UI.
  ///
  /// It now follows exactly the same accounting logic as
  /// receiveMonthlyBillPayment().
  Future<MonthlyBill> applyPaymentToMonthlyBill({
    required String farmId,
    required String customerId,
    required String billId,
    required double paidAmount,
    required String paymentMethod,
    String note = '',
  }) async {
    await receiveMonthlyBillPayment(
      farmId: farmId,
      customerId: customerId,
      billId: billId,
      paidAmount: paidAmount,
      paymentMethod: paymentMethod,
      note: note,
    );

    final snapshot =
    await _bills(farmId)
        .doc(billId)
        .get()
        .timeout(_timeout);

    if (!snapshot.exists) {
      throw StateError(
        'Monthly bill disappeared after payment.',
      );
    }

    return MonthlyBill.fromDoc(
      snapshot,
    );
  }

  // ===========================================================================
  // GET / STREAM BILLS
  // ===========================================================================

  Future<bool> monthlyBillExists({
    required String farmId,
    required String customerId,
    required int year,
    required int month,
  }) async {
    final billId =
    _monthlyBillDocumentId(
      customerId,
      year,
      month,
    );

    final snapshot =
    await _bills(farmId)
        .doc(billId)
        .get()
        .timeout(_timeout);

    return snapshot.exists;
  }

  Future<MonthlyBill?> getMonthlyBill({
    required String farmId,
    required String billId,
  }) async {
    final snapshot =
    await _bills(farmId)
        .doc(billId)
        .get()
        .timeout(_timeout);

    if (!snapshot.exists) {
      return null;
    }

    if (snapshot.data()?['type']
        ?.toString() !=
        'monthly') {
      return null;
    }

    return MonthlyBill.fromDoc(
      snapshot,
    );
  }

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

  Stream<List<MonthlyBill>> monthlyBillsStream({
    required String farmId,
    required String customerId,
  }) {
    return _bills(farmId)
        .where(
      'customerId',
      isEqualTo: customerId,
    )
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

  Future<List<MonthlyBill>> getMonthlyBills({
    required String farmId,
    required String customerId,
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
  // RECONCILE CUSTOMER OUTSTANDING
  // ===========================================================================

  /// Non-destructive reconciliation.
  ///
  /// It NEVER closes old bills and NEVER replaces customer pendingAmount
  /// with the latest bill.
  ///
  /// If monthly bills contain more outstanding than customer.pendingAmount,
  /// pendingAmount is raised to at least the total live monthly-bill balance.
  ///
  /// Any existing amount above the monthly-bill total is preserved because it
  /// may belong to another source such as checkout/manual/other charges.
  Future<double> reconcileCustomerOutstanding({
    required String farmId,
    required String customerId,
  }) async {
    final customerRef =
    _customers(farmId).doc(customerId);

    final bills =
    await getMonthlyBills(
      farmId: farmId,
      customerId: customerId,
    );

    return _db
        .runTransaction<double>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        final currentPending =
        _money(
          customerSnapshot.data()?[
          'pendingAmount'],
        );

        double liveBillTotal = 0;

        for (final bill in bills) {
          final billRef =
          _bills(farmId).doc(
            bill.id,
          );

          final billSnapshot =
          await transaction.get(
            billRef,
          );

          if (!billSnapshot.exists) {
            continue;
          }

          final data =
              billSnapshot.data() ?? {};

          if (data['type']?.toString() !=
              'monthly') {
            continue;
          }

          liveBillTotal += _money(
            data['remainingAmount'],
          );
        }

        liveBillTotal =
            _money(liveBillTotal);

        final correctedPending =
        currentPending <
            liveBillTotal
            ? liveBillTotal
            : currentPending;

        if ((correctedPending -
            currentPending)
            .abs() >
            _epsilon) {
          transaction.update(
            customerRef,
            {
              'pendingAmount':
              correctedPending,

              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );
        }

        return correctedPending;
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // CLOSE OPEN BILLS AFTER EXTERNAL SETTLEMENT
  // ===========================================================================

  /// Synchronization helper for an external checkout/settlement flow.
  ///
  /// This method does not change customer.pendingAmount.
  ///
  /// It should only be called when the caller has genuinely settled the
  /// customer's complete outstanding balance.
  Future<void> closeOpenBillsIfCustomerSettled({
    required String farmId,
    required String customerId,
  }) async {
    final customerRef =
    _customers(farmId).doc(customerId);

    final customerSnapshot =
    await customerRef
        .get()
        .timeout(_timeout);

    if (!customerSnapshot.exists) {
      return;
    }

    final pending =
    _money(
      customerSnapshot.data()?[
      'pendingAmount'],
    );

    if (pending > _epsilon) {
      return;
    }

    final snapshot =
    await _bills(farmId)
        .where(
      'customerId',
      isEqualTo: customerId,
    )
        .get()
        .timeout(_timeout);

    final refs = snapshot.docs
        .where(
          (d) =>
      d.data()['type']
          ?.toString() ==
          'monthly' &&
          _money(
            d.data()[
            'remainingAmount'],
          ) >
              _epsilon,
    )
        .map(
          (d) => d.reference,
    )
        .toList();

    if (refs.isEmpty) {
      return;
    }

    await _db
        .runTransaction<void>(
          (transaction) async {
        final documents =
        <DocumentSnapshot<
            Map<String, dynamic>>>[];

        for (final ref in refs) {
          documents.add(
            await transaction.get(
              ref,
            ),
          );
        }

        for (final document
        in documents) {
          if (!document.exists) {
            continue;
          }

          final remaining =
          _money(
            document.data()?[
            'remainingAmount'],
          );

          if (remaining <=
              _epsilon) {
            continue;
          }

          transaction.update(
            document.reference,
            {
              'remainingAmount':
              0.0,

              'status':
              'paid',

              'paymentStatus':
              'paid',

              'closedByCheckout':
              true,

              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );
        }
      },
    )
        .timeout(_timeout);
  }

  // ===========================================================================
  // VOID UNPAID BILL
  // ===========================================================================

  /// Voids a monthly bill that has received no payment.
  ///
  /// Only this bill's remaining balance is removed from customer pending.
  ///
  /// Any advance previously applied to this bill is restored.
  Future<void> voidUnpaidMonthlyBill({
    required String farmId,
    required String customerId,
    required String billId,
  }) async {
    final customerRef =
    _customers(farmId).doc(customerId);

    final billRef =
    _bills(farmId).doc(billId);

    final activityRef =
    _activities(farmId).doc();

    await _db
        .runTransaction<void>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        final billSnapshot =
        await transaction.get(
          billRef,
        );

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        if (!billSnapshot.exists) {
          throw StateError(
            'Monthly bill no longer exists.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final billData =
            billSnapshot.data() ?? {};

        if (billData['type']?.toString() !=
            'monthly') {
          throw StateError(
            'The selected document is not a monthly bill.',
          );
        }

        if (billData['customerId']
            ?.toString() !=
            customerId) {
          throw StateError(
            'This bill does not belong to the selected customer.',
          );
        }

        final amountPaid =
        _money(
          billData['amountPaid'],
        );

        if (amountPaid > _epsilon) {
          throw StateError(
            'A monthly bill with payments cannot be voided.',
          );
        }

        final billRemaining =
        _money(
          billData['remainingAmount'],
        );

        final currentPending =
        _money(
          customerData['pendingAmount'],
        );

        final advanceApplied =
        _money(
          billData['advanceApplied'],
        );

        final currentAdvance =
        _money(
          customerData['advanceAmount'],
        );

        if (currentPending +
            _epsilon <
            billRemaining) {
          throw StateError(
            'Customer outstanding is inconsistent. '
                'The bill cannot be safely voided.',
          );
        }

        final newPending =
        _money(
          (currentPending -
              billRemaining)
              .clamp(
            0,
            double.infinity,
          ),
        );

        final newAdvance =
        _money(
          currentAdvance +
              advanceApplied,
        );

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            newPending,

            'advanceAmount':
            newAdvance,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // Remove advance audit records belonging to this bill.
        if (advanceApplied > 0) {
          _writeAdvanceUsedEntry(
            transaction: transaction,
            farmId: farmId,
            customerRef: customerRef,
            customerId: customerId,
            customerName:
            (customerData['name'] ?? '')
                .toString(),
            billId: billId,
            billNumber:
            (billData['billNumber'] ??
                billId)
                .toString(),
            periodKey:
            (billData[
            'billingPeriodKey'] ??
                '')
                .toString(),
            amount: 0,
          );
        }

        transaction.delete(
          billRef,
        );

        transaction.set(
          activityRef,
          {
            'type':
            'monthlyBillVoided',

            'title':
            'Monthly Bill Voided',

            'subtitle':
            '${customerData['name'] ?? ''} · '
                '${billData['billNumber'] ?? billId}',

            'module':
            'palai',

            'customerId':
            customerId,

            'billId':
            billId,

            'billNumber':
            billData['billNumber'],

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );
      },
    )
        .timeout(_timeout);
  }
}