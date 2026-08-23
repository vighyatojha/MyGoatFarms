import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_bill_model.dart';

/// Handles the Customer-level Monthly Billing system.
///
/// IMPORTANT:
/// This service is separate from the goat Check-Out / Final Bill system.
///
/// Monthly Bill:
///   Customer-level recurring charge.
///   Adds the generated amount to customer pending/outstanding.
///
/// Final Bill:
///   Goat check-out settlement.
///   Remains handled by the existing check-out billing flow.
class MonthlyBillingService {
  MonthlyBillingService._();

  static final MonthlyBillingService instance =
  MonthlyBillingService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // COLLECTIONS
  // ---------------------------------------------------------------------------

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
    // Shares the same collection MonthlyBillsScreen reads from, so a
    // bill created here shows up there and vice versa. This used to
    // point at `bills` — the same collection the goat check-out
    // "Final Bill" flow (FirestoreService.createMonthlyBill) writes
    // to — which meant a bill generated here would silently never
    // appear in the customer's own Monthly Bills screen.
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
  // CREATE MONTHLY BILL
  // ===========================================================================

  /// Creates one monthly bill for a customer.
  ///
  /// The bill is initially UNPAID.
  ///
  /// The generated bill amount is immediately added to the customer's
  /// pendingAmount/outstanding amount.
  ///
  /// No payment is created here.
  ///
  /// This is intentional.
  ///
  /// Payment happens later from the Monthly Bills screen:
  ///
  ///   UNPAID
  ///      ↓
  ///   Add Payment
  ///      ↓
  ///   PAID / PARTIAL


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

    final newCharges =
    (palaiCharges + otherCharges - discount)
        .clamp(0, double.infinity)
        .toDouble();

    return _db.runTransaction<MonthlyBill>(
          (transaction) async {
        // -------------------------------------------------------------------
        // READS FIRST
        // -------------------------------------------------------------------

        final customerSnapshot =
        await transaction.get(customerRef);

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        final farmSnapshot =
        await transaction.get(farmRef);

        final existingBillSnapshot =
        await transaction.get(billRef);

        // -------------------------------------------------------------------
        // DUPLICATE PROTECTION
        // -------------------------------------------------------------------

        if (existingBillSnapshot.exists) {
          throw StateError(
            'A monthly bill already exists for '
                '$periodKey.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final farmData =
            farmSnapshot.data() ?? {};

        final customerName =
        (customerData['name'] ?? '')
            .toString();

        if (customerName.trim().isEmpty) {
          throw StateError(
            'Customer name is missing.',
          );
        }

        // -------------------------------------------------------------------
        // CURRENT CUSTOMER OUTSTANDING
        // -------------------------------------------------------------------

        final previousOutstanding =
        _doubleValue(
          customerData['pendingAmount'],
        );

        // -------------------------------------------------------------------
        // NEW OUTSTANDING
        // -------------------------------------------------------------------
        //
        // IMPORTANT:
        //
        // Monthly billing does NOT automatically use advance.
        //
        // The user's requirement is:
        //
        //     Monthly Bill
        //          ↓
        //     Add amount
        //          ↓
        //     Outstanding
        //
        // Advance handling remains part of the payment system.
        // -------------------------------------------------------------------

        final totalDue =
            previousOutstanding + newCharges;

        // -------------------------------------------------------------------
        // BILL NUMBER
        // -------------------------------------------------------------------

        final billNumber =
        _generateBillNumber(
          billId,
          year,
          month,
        );

        // -------------------------------------------------------------------
        // FARM PROFILE SNAPSHOT
        // -------------------------------------------------------------------
        //
        // These values are stored with the bill so an old PDF remains
        // historically accurate even if the farm profile changes later.
        // -------------------------------------------------------------------

        final farmName =
        (farmData['farmName'] ?? '')
            .toString();

        final farmAddress =
        (farmData['address'] ?? '')
            .toString();

        final farmPhone =
        (farmData['mobileNumber'] ?? '')
            .toString();

        final farmEmail =
        (farmData['email'] ?? '')
            .toString();

        final now =
        DateTime.now();

        // -------------------------------------------------------------------
        // WRITE MONTHLY BILL
        // -------------------------------------------------------------------

        transaction.set(
          billRef,
          {
            'type': 'monthly',

            'billNumber': billNumber,

            'customerId': customerId,
            'customerName': customerName,

            // ---------------------------------------------------------------
            // BILLING PERIOD
            // ---------------------------------------------------------------

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

            // ---------------------------------------------------------------
            // BILL AMOUNTS
            // ---------------------------------------------------------------

            'palaiCharges': palaiCharges,

            'otherCharges': otherCharges,

            'discount': discount,

            'newCharges': newCharges,

            'currentBillAmount': newCharges,

            // ---------------------------------------------------------------
            // OUTSTANDING SNAPSHOT
            // ---------------------------------------------------------------

            'previousOutstanding':
            previousOutstanding,

            'totalDue': totalDue,

            'amountPaid': 0,

            'remainingAmount': newCharges,

            'pendingAfter': totalDue,

            // ---------------------------------------------------------------
            // PAYMENT STATUS
            // ---------------------------------------------------------------

            'status': 'unpaid',

            'paymentStatus': 'unpaid',

            'paymentId': null,

            'paymentMethod': null,

            'paidAt': null,

            // ---------------------------------------------------------------
            // OTHER
            // ---------------------------------------------------------------

            'goatCount': goatCount,

            'notes': notes.trim(),

            // ---------------------------------------------------------------
            // FARM SNAPSHOT
            // ---------------------------------------------------------------

            'farmName': farmName,

            'farmAddress': farmAddress,

            'farmPhone': farmPhone,

            'farmEmail': farmEmail,

            // ---------------------------------------------------------------
            // DATES
            // ---------------------------------------------------------------

            'generatedAt':
            Timestamp.fromDate(now),

            'createdAt':
            FieldValue.serverTimestamp(),

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------------
        // UPDATE CUSTOMER OUTSTANDING
        // -------------------------------------------------------------------

        transaction.update(
          customerRef,
          {
            'pendingAmount': totalDue,
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------------
        // ACTIVITY
        // -------------------------------------------------------------------

        transaction.set(
          activityRef,
          {
            'type': 'monthlyBillGenerated',

            'title':
            'Monthly Bill Generated',

            'subtitle':
            '$customerName · '
                '$periodKey · '
                '₹${newCharges.toStringAsFixed(0)}',

            'module': 'palai',

            'customerId': customerId,

            'billId': billId,

            'billNumber': billNumber,

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------------
        // RETURN MODEL
        // -------------------------------------------------------------------

        return MonthlyBill(
          id: billId,

          customerId: customerId,

          customerName: customerName,

          billNumber: billNumber,

          billingMonth: billingMonth,

          periodEnd: periodEnd,

          goatCount: goatCount,

          palaiCharges: palaiCharges,

          otherCharges: otherCharges,

          discount: discount,

          previousOutstanding:
          previousOutstanding,

          currentBillAmount:
          newCharges,

          totalDue:
          totalDue,

          amountPaid: 0,

          remainingAmount:
          newCharges,

          status:
          MonthlyBillStatus.unpaid,

          generatedAt: now,

          paidAt: null,

          notes: notes.trim(),

          farmName: farmName,

          farmAddress: farmAddress,

          farmPhone: farmPhone,

          farmEmail: farmEmail,
        );
      },
    ).timeout(_timeout);
  }



  // ===========================================================================
  // CHECK IF BILL EXISTS
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

  // ===========================================================================
  // GET ONE MONTHLY BILL
  // ===========================================================================

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

    final data =
        snapshot.data() ?? {};

    // Prevent this service from accidentally treating the checkout
    // Final Bill as a Monthly Bill.
    if (data['type']?.toString() != 'monthly') {
      return null;
    }

    return MonthlyBill.fromDoc(snapshot);
  }

  // ===========================================================================
  // CUSTOMER MONTHLY BILL STREAM
  // ===========================================================================

  /// Realtime stream of monthly bills for one customer.
  ///
  /// We intentionally only filter by customerId here and sort in Dart.
  /// This avoids introducing a new composite Firestore index just for the
  /// monthly billing screen.
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
              (doc) =>
          doc.data()['type']?.toString() ==
              'monthly',
        )
            .map(
          MonthlyBill.fromDoc,
        )
            .toList();

        bills.sort(
              (a, b) => b.billingMonth.compareTo(
            a.billingMonth,
          ),
        );

        return bills;
      },
    );
  }

  // ===========================================================================
  // GET CUSTOMER MONTHLY BILLS
  // ===========================================================================

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
          (doc) =>
      doc.data()['type']?.toString() ==
          'monthly',
    )
        .map(
      MonthlyBill.fromDoc,
    )
        .toList();

    bills.sort(
          (a, b) => b.billingMonth.compareTo(
        a.billingMonth,
      ),
    );

    return bills;
  }

  // ===========================================================================
  // APPLY PAYMENT TO MONTHLY BILL
  // ===========================================================================

  /// Applies a payment to one specific monthly bill.
  ///
  /// This supports:
  ///
  /// UNPAID
  ///    ↓
  /// PARTIALLY PAID
  ///    ↓
  /// PAID
  ///
  /// The payment cannot exceed the bill's remaining amount.
  ///
  /// This is intentional because the payment screen is opened specifically
  /// for the selected monthly bill.
  ///
  /// If the farmer wants to make a general payment or add an advance, the
  /// existing standalone "Receive Payment" flow should be used instead.
  Future<MonthlyBill> applyPaymentToMonthlyBill({
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

    return _db.runTransaction<MonthlyBill>(
          (transaction) async {
        // -------------------------------------------------------------------
        // READS
        // -------------------------------------------------------------------

        final customerSnapshot =
        await transaction.get(customerRef);

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        final billSnapshot =
        await transaction.get(billRef);

        if (!billSnapshot.exists) {
          throw StateError(
            'Monthly bill no longer exists.',
          );
        }

        final billData =
            billSnapshot.data() ?? {};

        if (billData['type']?.toString() !=
            'monthly') {
          throw StateError(
            'The selected document is not a monthly bill.',
          );
        }

        final billCustomerId =
            billData['customerId']?.toString() ?? '';

        if (billCustomerId != customerId) {
          throw StateError(
            'This bill does not belong to the selected customer.',
          );
        }

        // -------------------------------------------------------------------
        // CURRENT BILL VALUES
        // -------------------------------------------------------------------

        final currentPaid =
        _doubleValue(
          billData['amountPaid'],
        );

        final currentRemaining =
        _doubleValue(
          billData['remainingAmount'],
        );

        if (currentRemaining <= 0) {
          throw StateError(
            'This monthly bill is already fully paid.',
          );
        }

        // -------------------------------------------------------------------
        // PREVENT OVERPAYING THIS BILL
        // -------------------------------------------------------------------

        if (paidAmount >
            currentRemaining + 0.001) {
          throw StateError(
            'Payment amount cannot be greater than '
                'the remaining amount of this bill '
                '(₹${currentRemaining.toStringAsFixed(2)}).',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final currentPending =
        _doubleValue(
          customerData['pendingAmount'],
        );

        // The monthly bill amount was added to the customer's outstanding
        // when it was generated. Therefore the customer's pending balance
        // must have at least the payment amount available to reduce it.
        if (currentPending + 0.001 <
            paidAmount) {
          throw StateError(
            'Customer outstanding is lower than '
                'the payment being applied to this bill.',
          );
        }

        // -------------------------------------------------------------------
        // CALCULATE
        // -------------------------------------------------------------------

        final newAmountPaid =
            currentPaid + paidAmount;

        final newRemaining =
        (currentRemaining - paidAmount)
            .clamp(0, double.infinity)
            .toDouble();

        final newPending =
        (currentPending - paidAmount)
            .clamp(0, double.infinity)
            .toDouble();

        final isFullyPaid =
            newRemaining <= 0.001;

        final newStatus =
        isFullyPaid
            ? MonthlyBillStatus.paid
            : MonthlyBillStatus.partial;

        final now =
        DateTime.now();

        final customerName =
        (customerData['name'] ?? '')
            .toString();

        final billNumber =
            billData['billNumber']?.toString() ??
                billId;

        final paymentNumber =
        _generatePaymentNumber(
          paymentRef.id,
        );

        // -------------------------------------------------------------------
        // PAYMENT RECORD
        // -------------------------------------------------------------------

        transaction.set(
          paymentRef,
          {
            'paymentNumber': paymentNumber,

            'type': 'monthlyBillPayment',

            'customerId': customerId,

            'customerName':
            customerName,

            'billId': billId,

            'billNumber':
            billNumber,

            'amount':
            paidAmount,

            'amountReceived':
            paidAmount,

            'amountAppliedToBill':
            paidAmount,

            'amountAppliedToPending':
            paidAmount,

            'pendingBefore':
            currentPending,

            'pendingAfter':
            newPending,

            'billRemainingBefore':
            currentRemaining,

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

        // -------------------------------------------------------------------
        // INCOME TRANSACTION
        // -------------------------------------------------------------------

        transaction.set(
          transactionRef,
          {
            'amount':
            paidAmount,

            'isIncome':
            true,

            'category':
            'Monthly Bill Payment',

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

            'paymentMethod':
            paymentMethod.trim(),

            'note':
            note.trim().isNotEmpty
                ? note.trim()
                : 'Monthly bill payment from '
                '$customerName',

            'date':
            FieldValue.serverTimestamp(),

            'createdAt':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------------
        // UPDATE BILL
        // -------------------------------------------------------------------

        transaction.update(
          billRef,
          {
            'amountPaid':
            newAmountPaid,

            'remainingAmount':
            newRemaining,

            'status':
            MonthlyBill.statusToString(
              newStatus,
            ),

            'paymentStatus':
            MonthlyBill.statusToString(
              newStatus,
            ),

            // Keep the most recent payment for quick UI access.
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

        // -------------------------------------------------------------------
        // UPDATE CUSTOMER OUTSTANDING
        // -------------------------------------------------------------------

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            newPending,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------------
        // ACTIVITY
        // -------------------------------------------------------------------

        transaction.set(
          activityRef,
          {
            'type':
            'monthlyBillPayment',

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

            'billNumber':
            billNumber,

            'paymentId':
            paymentRef.id,

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        // -------------------------------------------------------------------
        // RETURN UPDATED BILL
        // -------------------------------------------------------------------

        return MonthlyBill(
          id: billId,

          customerId: customerId,

          customerName: customerName,

          billNumber: billNumber,

          billingMonth: _dateValue(
            billData['billingMonth'],
            now,
          ),

          periodEnd: _dateValue(
            billData['periodEnd'],
            now,
          ),

          goatCount:
          (billData['goatCount'] as num?)?.toInt() ?? 0,

          palaiCharges:
          _doubleValue(
            billData['palaiCharges'],
          ),

          otherCharges:
          _doubleValue(
            billData['otherCharges'],
          ),

          discount:
          _doubleValue(
            billData['discount'],
          ),

          previousOutstanding:
          _doubleValue(
            billData['previousOutstanding'],
          ),

          currentBillAmount:
          _doubleValue(
            billData['currentBillAmount'] ??
                billData['newCharges'],
          ),

          totalDue:
          _doubleValue(
            billData['totalDue'],
          ),

          amountPaid:
          newAmountPaid,

          remainingAmount:
          newRemaining,

          status:
          newStatus,

          generatedAt: _dateValue(
            billData['generatedAt'],
            now,
          ),

          paidAt: isFullyPaid
              ? now
              : _nullableDateValue(
            billData['paidAt'],
          ),

          notes:
          billData['notes']?.toString() ?? '',

          farmName:
          billData['farmName']?.toString() ?? '',

          farmAddress:
          billData['farmAddress']?.toString() ?? '',

          farmPhone:
          billData['farmPhone']?.toString() ?? '',

          farmEmail:
          billData['farmEmail']?.toString() ?? '',
        );
      },
    ).timeout(_timeout);
  }

  // ===========================================================================
  // DELETE / VOID MONTHLY BILL
  // ===========================================================================

  /// Voids a monthly bill that has not received any payment.
  ///
  /// We intentionally do NOT allow deleting a paid/partially-paid bill.
  /// Financial records should remain auditable.
  ///
  /// The original outstanding amount is also restored.
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

    await _db.runTransaction<void>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(customerRef);

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        final billSnapshot =
        await transaction.get(billRef);

        if (!billSnapshot.exists) {
          throw StateError(
            'Monthly bill no longer exists.',
          );
        }

        final billData =
            billSnapshot.data() ?? {};

        if (billData['type']?.toString() !=
            'monthly') {
          throw StateError(
            'The selected document is not a monthly bill.',
          );
        }

        if (billData['customerId']?.toString() !=
            customerId) {
          throw StateError(
            'This bill does not belong to the selected customer.',
          );
        }

        final amountPaid =
        _doubleValue(
          billData['amountPaid'],
        );

        if (amountPaid > 0) {
          throw StateError(
            'A monthly bill with payments cannot be voided.',
          );
        }

        final currentPending =
        _doubleValue(
          (customerSnapshot.data() ?? {})
          ['pendingAmount'],
        );

        final billAmount =
        _doubleValue(
          billData['currentBillAmount'] ??
              billData['newCharges'],
        );

        if (currentPending < billAmount) {
          throw StateError(
            'Customer outstanding is inconsistent. '
                'The bill cannot be safely voided.',
          );
        }

        final newPending =
            currentPending - billAmount;

        final customerName =
        ((customerSnapshot.data() ??
            {})['name'] ??
            '')
            .toString();

        transaction.update(
          customerRef,
          {
            'pendingAmount':
            newPending,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

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
            '$customerName · '
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
    ).timeout(_timeout);
  }

  // ===========================================================================
  // PRIVATE HELPERS
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
}

/// Creates a temporary snapshot containing the original document data plus
/// the values that have just been written.
///
/// Firestore's Transaction object does not return the updated snapshot after
/// transaction.update(), so the model returned by applyPaymentToMonthlyBill
/// is constructed from this temporary snapshot.