import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_bill_model.dart';
import 'payment_allocation_service.dart';

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

    // Bill IDs are 'monthly_<customerId>_<YYYY-MM>'. Taking the first 6
    // characters of the whole ID gave every bill the same 'MONTHL'
    // suffix, so use the customer part instead.
    final customerPart = billId.startsWith('monthly_')
        ? billId.substring('monthly_'.length)
        : billId;
    final shortId = customerPart.length > 6
        ? customerPart.substring(0, 6)
        : customerPart;

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

  // ===========================================================================
  // CLOSE OPEN BILLS AFTER EXTERNAL SETTLEMENT
  // ===========================================================================

  /// NO-OP since statement billing. Final Checkout now applies its
  /// payment and advance to the customer's unpaid months itself (oldest
  /// first), so there is nothing left to close here. Zeroing bills here
  /// also left them with amountPaid + remainingAmount ≠ totalDue.
  @Deprecated('Final Checkout settles monthly bills itself.')
  Future<void> closeOpenBillsIfCustomerSettled({
    required String farmId,
    required String customerId,
  }) async {}

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