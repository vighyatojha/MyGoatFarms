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
    /// When true, any existing customer advance balance is used to offset
    /// this bill (previous outstanding + this month's charges) before the
    /// remainder is added to the customer's pending amount. The advance
    /// balance itself is reduced by the amount applied.
    ///
    /// Defaults to false so existing callers keep their current behaviour
    /// (advance handling stays with the payment system for them).
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

        final advanceBefore =
        _doubleValue(
          customerData['advanceAmount'],
        );

        final totalBeforeAdvance =
            previousOutstanding + newCharges;

        // -------------------------------------------------------------------
        // NEW OUTSTANDING
        // -------------------------------------------------------------------
        //
        // By default, monthly billing does NOT automatically use advance —
        // advance handling stays with the payment system.
        //
        //     Monthly Bill
        //          ↓
        //     Add amount
        //          ↓
        //     Outstanding
        //
        // When the caller explicitly opts in via [applyAdvance], any
        // existing advance balance is used to offset the bill first
        // (read fresh, inside this transaction, so it can't race with a
        // concurrent update), and the advance balance itself is reduced by
        // the amount applied.
        // -------------------------------------------------------------------

        final advanceApplied = applyAdvance
            ? advanceBefore
            .clamp(0, totalBeforeAdvance)
            .toDouble()
            : 0.0;

        final totalDue =
        (totalBeforeAdvance - advanceApplied)
            .clamp(0, double.infinity)
            .toDouble();

        final advanceAfter =
        (advanceBefore - advanceApplied)
            .clamp(0, double.infinity)
            .toDouble();

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

            'advanceApplied': advanceApplied,

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
            if (applyAdvance)
              'advanceAmount': advanceAfter,
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

          advanceApplied:
          advanceApplied,

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
  // MANUAL / CUSTOMIZABLE BILL ENTRY
  // ===========================================================================
  //
  // Simple, fully-editable bill: the owner types the two numbers that
  // actually matter — Outstanding Amount and Advance Amount — and this
  // writes their difference straight into the customer's outstanding
  // balance. There is no separate "amount paid" here: nothing is being
  // marked as paid, so it is never shown or stored on bills created this
  // way (amountPaid is always 0).
  //
  //   Outstanding Amount  (typed by owner — replaces the old
  //                          Palai/Other/Discount math entirely)
  //   − Advance Amount    (typed by owner — capped at the customer's
  //                          real advance balance so it can't go negative)
  //   = Total Outstanding  (written to customer.pendingAmount)
  //
  // ===========================================================================

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
      throw ArgumentError('Outstanding amount cannot be negative.');
    }

    if (advanceAmount < 0) {
      throw ArgumentError('Advance amount cannot be negative.');
    }

    if (month < 1 || month > 12) {
      throw ArgumentError('Invalid billing month.');
    }

    final customerRef = _customers(farmId).doc(customerId);
    final farmRef = _farms().doc(farmId);
    final periodKey = _periodKey(year, month);
    final billId = _monthlyBillDocumentId(customerId, year, month);
    final billRef = _bills(farmId).doc(billId);
    final activityRef = _activities(farmId).doc();
    final billingMonth = _firstDayOfMonth(year, month);
    final periodEnd = _lastDayOfMonth(year, month);

    return _db.runTransaction<MonthlyBill>((transaction) async {
      // ---------------------------------------------------------------
      // READS FIRST
      // ---------------------------------------------------------------

      final customerSnapshot = await transaction.get(customerRef);

      if (!customerSnapshot.exists) {
        throw StateError('Customer no longer exists.');
      }

      final farmSnapshot = await transaction.get(farmRef);
      final existingBillSnapshot = await transaction.get(billRef);

      if (existingBillSnapshot.exists) {
        throw StateError('A monthly bill already exists for $periodKey.');
      }

      final customerData = customerSnapshot.data() ?? {};
      final farmData = farmSnapshot.data() ?? {};

      final customerName = (customerData['name'] ?? '').toString();
      if (customerName.trim().isEmpty) {
        throw StateError('Customer name is missing.');
      }

      // ---------------------------------------------------------------
      // ADVANCE — capped at what the customer actually has and at the
      // outstanding amount itself, so it never over-applies.
      // ---------------------------------------------------------------

      final advanceBefore = _doubleValue(customerData['advanceAmount']);

      final advanceApplied = advanceAmount
          .clamp(0, advanceBefore)
          .clamp(0, outstandingAmount)
          .toDouble();

      final totalDue =
      (outstandingAmount - advanceApplied).clamp(0, double.infinity).toDouble();

      final advanceAfter =
      (advanceBefore - advanceApplied).clamp(0, double.infinity).toDouble();

      final billNumber = _generateBillNumber(billId, year, month);

      final farmName = (farmData['farmName'] ?? '').toString();
      final farmAddress = (farmData['address'] ?? '').toString();
      final farmPhone = (farmData['mobileNumber'] ?? '').toString();
      final farmEmail = (farmData['email'] ?? '').toString();

      final now = DateTime.now();

      // ---------------------------------------------------------------
      // WRITE MONTHLY BILL
      //
      // No itemized Palai/Other/Discount here — the owner typed the
      // Outstanding Amount directly, so it's stored as-is in
      // previousOutstanding, and palaiCharges/otherCharges/discount all
      // stay at 0. amountPaid always stays 0 too: this only records what
      // is owed, never a payment.
      // ---------------------------------------------------------------

      transaction.set(billRef, {
        'type': 'monthly',
        'billNumber': billNumber,
        'customerId': customerId,
        'customerName': customerName,
        'billingPeriodKey': periodKey,
        'periodMonth': periodKey,
        'month': month,
        'year': year,
        'billingMonth': Timestamp.fromDate(billingMonth),
        'periodEnd': Timestamp.fromDate(periodEnd),
        'palaiCharges': 0,
        'otherCharges': 0,
        'discount': 0,
        'newCharges': 0,
        'currentBillAmount': 0,
        'previousOutstanding': outstandingAmount,
        'advanceApplied': advanceApplied,
        'totalDue': totalDue,
        'amountPaid': 0,
        'remainingAmount': totalDue,
        'pendingAfter': totalDue,
        'status': 'unpaid',
        'paymentStatus': 'unpaid',
        'paymentId': null,
        'paymentMethod': null,
        'paidAt': null,
        'goatCount': goatCount,
        'notes': notes.trim(),
        'farmName': farmName,
        'farmAddress': farmAddress,
        'farmPhone': farmPhone,
        'farmEmail': farmEmail,
        'generatedAt': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // UPDATE CUSTOMER OUTSTANDING
      // ---------------------------------------------------------------

      transaction.update(customerRef, {
        'pendingAmount': totalDue,
        'advanceAmount': advanceAfter,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // ACTIVITY
      // ---------------------------------------------------------------

      transaction.set(activityRef, {
        'type': 'monthlyBillGenerated',
        'title': 'Monthly Bill Generated',
        'subtitle': '$customerName · $periodKey · ₹${totalDue.toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'billId': billId,
        'billNumber': billNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return MonthlyBill(
        id: billId,
        customerId: customerId,
        customerName: customerName,
        billNumber: billNumber,
        billingMonth: billingMonth,
        periodEnd: periodEnd,
        goatCount: goatCount,
        palaiCharges: 0,
        otherCharges: 0,
        discount: 0,
        previousOutstanding: outstandingAmount,
        currentBillAmount: 0,
        advanceApplied: advanceApplied,
        totalDue: totalDue,
        amountPaid: 0,
        remainingAmount: totalDue,
        status: MonthlyBillStatus.unpaid,
        generatedAt: now,
        paidAt: null,
        notes: notes.trim(),
        farmName: farmName,
        farmAddress: farmAddress,
        farmPhone: farmPhone,
        farmEmail: farmEmail,
      );
    }).timeout(_timeout);
  }

  // ===========================================================================
  // CREATE CURRENT-MONTH MONTHLY BILL (goat-wise Palai + current state)
  // ===========================================================================
  //
  // This is the bill creation path for the Customer Goat Progress Report
  // and the goat-wise Monthly Billing screen.
  //
  // It keeps THREE numbers completely separate, exactly as the owner
  // enters them, and never reconstructs any of them from payment
  // history or old bills:
  //
  //   palaiCharges       — sum of this month's goat-wise Palai amounts
  //                         (each one editable per goat; see
  //                         [goatBreakdown]).
  //   currentOutstanding — the customer's CURRENT outstanding balance,
  //                         right now. Zero if there is none. Never
  //                         "previous bill + old payments" math.
  //   currentAdvance     — the customer's CURRENT advance balance,
  //                         right now. Zero if there is none.
  //
  //   Current Amount Due = palaiCharges + currentOutstanding − currentAdvance
  //
  // The three numbers are stored on the bill AS-IS (palaiCharges,
  // previousOutstanding, advanceApplied) so the bill is an honest,
  // permanent snapshot — later payments or balance changes never
  // silently rewrite it.
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
    if (palaiCharges < 0) {
      throw ArgumentError('Palai charges cannot be negative.');
    }
    if (currentOutstanding < 0) {
      throw ArgumentError('Current Outstanding cannot be negative.');
    }
    if (currentAdvance < 0) {
      throw ArgumentError('Current Advance cannot be negative.');
    }
    if (month < 1 || month > 12) {
      throw ArgumentError('Invalid billing month.');
    }

    final customerRef = _customers(farmId).doc(customerId);
    final farmRef = _farms().doc(farmId);
    final periodKey = _periodKey(year, month);
    final billId = _monthlyBillDocumentId(customerId, year, month);
    final billRef = _bills(farmId).doc(billId);
    final activityRef = _activities(farmId).doc();
    final billingMonth = _firstDayOfMonth(year, month);
    final periodEnd = _lastDayOfMonth(year, month);

    // ---------------------------------------------------------------
    // FIND ANY STILL-OPEN MONTHLY BILLS FROM EARLIER PERIODS
    //
    // `currentOutstanding` above is cumulative — it already represents
    // everything the customer owed from every earlier bill. Once it's
    // folded into this new bill's totalDue, an older bill still sitting
    // there with remainingAmount > 0 would be counted a SECOND time:
    // once inside this new bill, and once on its own. That double count
    // is exactly what made "Sync with Monthly Bills", the Monthly Bills
    // list, and Customer Profile disagree with each other.
    //
    // So every other open monthly bill for this customer is closed out
    // (remainingAmount -> 0) in the SAME transaction that creates this
    // one, leaving exactly one bill "live" per customer at a time.
    //
    // Firestore transactions can only re-read documents by reference,
    // not run a query, so the open bills are found here, before the
    // transaction starts, then re-read fresh (and closed) by reference
    // inside it — the same pattern already used in
    // [FirestoreService.receivePalaiPayment].
    // ---------------------------------------------------------------

    final earlierOpenBillsSnapshot = await _bills(farmId)
        .where('customerId', isEqualTo: customerId)
        .get()
        .timeout(_timeout);

    final earlierOpenBillRefs = earlierOpenBillsSnapshot.docs.where((doc) {
      final data = doc.data();
      if (data['type']?.toString() != 'monthly') return false;
      if (doc.id == billId) return false;
      return _doubleValue(data['remainingAmount']) > 0;
    }).map((doc) => doc.reference).toList();

    return _db.runTransaction<MonthlyBill>((transaction) async {
      // ---------------------------------------------------------------
      // READS FIRST
      // ---------------------------------------------------------------

      final customerSnapshot = await transaction.get(customerRef);

      if (!customerSnapshot.exists) {
        throw StateError('Customer no longer exists.');
      }

      final farmSnapshot = await transaction.get(farmRef);
      final existingBillSnapshot = await transaction.get(billRef);

      if (existingBillSnapshot.exists) {
        throw StateError('A monthly bill already exists for $periodKey.');
      }

      // Re-read every earlier open bill fresh, inside the transaction,
      // alongside every other read (Firestore requires all reads before
      // any writes in a transaction).
      final earlierOpenBillSnapshots =
      <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in earlierOpenBillRefs) {
        earlierOpenBillSnapshots.add(await transaction.get(ref));
      }

      final customerData = customerSnapshot.data() ?? {};
      final farmData = farmSnapshot.data() ?? {};

      final customerName = (customerData['name'] ?? '').toString();
      if (customerName.trim().isEmpty) {
        throw StateError('Customer name is missing.');
      }

      // ---------------------------------------------------------------
      // ADVANCE — capped at what the customer actually has and at the
      // total it's being applied against, so it never over-applies.
      // currentAdvance is owner-confirmed (usually the live balance,
      // but the owner may correct it), so we still guard it against
      // the customer's real advance balance to avoid over-draining it.
      // ---------------------------------------------------------------

      final advanceBefore = _doubleValue(customerData['advanceAmount']);

      final totalBeforeAdvance = palaiCharges + currentOutstanding;

      final advanceApplied = currentAdvance
          .clamp(0, advanceBefore)
          .clamp(0, totalBeforeAdvance)
          .toDouble();

      final totalDue =
      (totalBeforeAdvance - advanceApplied).clamp(0, double.infinity).toDouble();

      final advanceAfter =
      (advanceBefore - advanceApplied).clamp(0, double.infinity).toDouble();

      final billNumber = _generateBillNumber(billId, year, month);

      final farmName = (farmData['farmName'] ?? '').toString();
      final farmAddress = (farmData['address'] ?? '').toString();
      final farmPhone = (farmData['mobileNumber'] ?? '').toString();
      final farmEmail = (farmData['email'] ?? '').toString();

      final now = DateTime.now();

      // ---------------------------------------------------------------
      // WRITE MONTHLY BILL
      // ---------------------------------------------------------------

      transaction.set(billRef, {
        'type': 'monthly',
        'billNumber': billNumber,
        'customerId': customerId,
        'customerName': customerName,
        'billingPeriodKey': periodKey,
        'periodMonth': periodKey,
        'month': month,
        'year': year,
        'billingMonth': Timestamp.fromDate(billingMonth),
        'periodEnd': Timestamp.fromDate(periodEnd),

        // Current month's Palai only — goat-wise, never mixed with
        // outstanding.
        'palaiCharges': palaiCharges,
        'otherCharges': 0,
        'discount': 0,
        'newCharges': palaiCharges,
        'currentBillAmount': palaiCharges,

        // Current-state snapshot, exactly as entered — never
        // reconstructed from history.
        'previousOutstanding': currentOutstanding,
        'advanceApplied': advanceApplied,
        'totalDue': totalDue,

        'amountPaid': 0,
        'remainingAmount': totalDue,
        'pendingAfter': totalDue,

        'status': 'unpaid',
        'paymentStatus': 'unpaid',
        'paymentId': null,
        'paymentMethod': null,
        'paidAt': null,

        'goatCount': goatCount,
        'goatBreakdown': goatBreakdown.map((g) => g.toMap()).toList(),

        'notes': notes.trim(),
        'farmName': farmName,
        'farmAddress': farmAddress,
        'farmPhone': farmPhone,
        'farmEmail': farmEmail,
        'generatedAt': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // CLOSE OUT EARLIER OPEN BILLS
      //
      // Their balance now lives inside this new bill's totalDue above.
      // Leaving them at their old remainingAmount would double-count
      // that balance the next time anything sums bills for this
      // customer (Sync with Monthly Bills, a future report, etc.).
      // ---------------------------------------------------------------

      for (final snap in earlierOpenBillSnapshots) {
        if (!snap.exists) continue;
        transaction.update(snap.reference, {
          'remainingAmount': 0,
          'status': 'paid',
          'paymentStatus': 'paid',
          'carriedForwardIntoBillId': billId,
          'carriedForwardIntoPeriod': periodKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ---------------------------------------------------------------
      // UPDATE CUSTOMER OUTSTANDING
      // ---------------------------------------------------------------

      transaction.update(customerRef, {
        'pendingAmount': totalDue,
        'advanceAmount': advanceAfter,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // ACTIVITY
      // ---------------------------------------------------------------

      transaction.set(activityRef, {
        'type': 'monthlyBillGenerated',
        'title': 'Monthly Bill Generated',
        'subtitle': '$customerName · $periodKey · ₹${totalDue.toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'billId': billId,
        'billNumber': billNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return MonthlyBill(
        id: billId,
        customerId: customerId,
        customerName: customerName,
        billNumber: billNumber,
        billingMonth: billingMonth,
        periodEnd: periodEnd,
        goatCount: goatCount,
        palaiCharges: palaiCharges,
        otherCharges: 0,
        discount: 0,
        previousOutstanding: currentOutstanding,
        currentBillAmount: palaiCharges,
        advanceApplied: advanceApplied,
        totalDue: totalDue,
        amountPaid: 0,
        remainingAmount: totalDue,
        status: MonthlyBillStatus.unpaid,
        generatedAt: now,
        paidAt: null,
        notes: notes.trim(),
        farmName: farmName,
        farmAddress: farmAddress,
        farmPhone: farmPhone,
        farmEmail: farmEmail,
        goatBreakdown: goatBreakdown,
      );
    }).timeout(_timeout);
  }

  // ===========================================================================
  // UPDATE CURRENT-MONTH MONTHLY BILL (fix an existing bill in place)
  // ===========================================================================
  //
  // createCurrentMonthMonthlyBill() refuses to run a second time for the
  // same customer/month (it throws a StateError so a bill is never
  // silently duplicated). That's correct, but it means a bill that was
  // generated with a mistake in it — most commonly ₹0 Current Month
  // Palai because the progress report's goat-wise fields weren't filled
  // in yet — had no way to be corrected other than deleting Firestore
  // data by hand.
  //
  // This method edits that SAME bill document instead of creating a new
  // one:
  //   - the bill's old advance contribution is restored to the
  //     customer's advance balance before the new amount is re-applied,
  //     so editing a bill never permanently drains advance twice.
  //   - the customer's pendingAmount is adjusted by the difference
  //     between the bill's old totalDue and its new totalDue, not
  //     replaced outright, so it stays correct even if other bills
  //     exist.
  //   - amountPaid (any payment already recorded against this bill) is
  //     preserved exactly; only remainingAmount/status are recomputed
  //     against the corrected totalDue.
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
    if (palaiCharges < 0) {
      throw ArgumentError('Palai charges cannot be negative.');
    }
    if (currentOutstanding < 0) {
      throw ArgumentError('Current Outstanding cannot be negative.');
    }
    if (currentAdvance < 0) {
      throw ArgumentError('Current Advance cannot be negative.');
    }

    final customerRef = _customers(farmId).doc(customerId);
    final billRef = _bills(farmId).doc(billId);
    final activityRef = _activities(farmId).doc();

    return _db.runTransaction<MonthlyBill>((transaction) async {
      // ---------------------------------------------------------------
      // READS FIRST
      // ---------------------------------------------------------------

      final customerSnapshot = await transaction.get(customerRef);
      final billSnapshot = await transaction.get(billRef);

      if (!customerSnapshot.exists) {
        throw StateError('Customer no longer exists.');
      }
      if (!billSnapshot.exists) {
        throw StateError('Monthly bill no longer exists.');
      }

      final customerData = customerSnapshot.data() ?? {};
      final billData = billSnapshot.data() ?? {};

      if (billData['type']?.toString() != 'monthly') {
        throw StateError('This is not a monthly bill.');
      }
      if ((billData['customerId'] ?? '').toString() != customerId) {
        throw StateError('This monthly bill does not belong to this customer.');
      }

      final currentBill = MonthlyBill.fromDoc(billSnapshot);

      // ---------------------------------------------------------------
      // RESTORE OLD ADVANCE CONTRIBUTION, THEN RE-APPLY
      // ---------------------------------------------------------------

      final oldAdvanceApplied = _doubleValue(billData['advanceApplied']);
      final advanceBeforeEdit =
          _doubleValue(customerData['advanceAmount']) + oldAdvanceApplied;

      final totalBeforeAdvance = palaiCharges + currentOutstanding;

      final advanceApplied = currentAdvance
          .clamp(0, advanceBeforeEdit)
          .clamp(0, totalBeforeAdvance)
          .toDouble();

      final totalDue =
      (totalBeforeAdvance - advanceApplied).clamp(0, double.infinity).toDouble();

      final advanceAfter =
      (advanceBeforeEdit - advanceApplied).clamp(0, double.infinity).toDouble();

      // ---------------------------------------------------------------
      // AMOUNT PAID IS PRESERVED — only the remaining balance and
      // status are recomputed against the corrected total.
      // ---------------------------------------------------------------

      final amountPaid = _doubleValue(billData['amountPaid']);
      final remainingAmount =
      (totalDue - amountPaid).clamp(0, double.infinity).toDouble();

      final status = remainingAmount <= 0
          ? MonthlyBillStatus.paid
          : (amountPaid > 0 ? MonthlyBillStatus.partial : MonthlyBillStatus.unpaid);

      // ---------------------------------------------------------------
      // WRITE MONTHLY BILL (edit in place — same document)
      // ---------------------------------------------------------------

      transaction.update(billRef, {
        'palaiCharges': palaiCharges,
        'newCharges': palaiCharges,
        'currentBillAmount': palaiCharges,
        'previousOutstanding': currentOutstanding,
        'advanceApplied': advanceApplied,
        'totalDue': totalDue,
        'remainingAmount': remainingAmount,
        'pendingAfter': totalDue,
        'status': MonthlyBill.statusToString(status),
        'paymentStatus': MonthlyBill.statusToString(status),
        'goatCount': goatCount,
        'goatBreakdown': goatBreakdown.map((g) => g.toMap()).toList(),
        if (notes != null) 'notes': notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // UPDATE CUSTOMER — adjust pendingAmount by the delta this bill
      // makes, not by replacing it outright (other bills may exist).
      // ---------------------------------------------------------------

      final oldTotalDue = _doubleValue(billData['totalDue']);
      final currentPending = _doubleValue(customerData['pendingAmount']);
      final newPending =
      (currentPending - oldTotalDue + totalDue).clamp(0, double.infinity).toDouble();

      transaction.update(customerRef, {
        'pendingAmount': newPending,
        'advanceAmount': advanceAfter,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ---------------------------------------------------------------
      // ACTIVITY
      // ---------------------------------------------------------------

      transaction.set(activityRef, {
        'type': 'monthlyBillUpdated',
        'title': 'Monthly Bill Updated',
        'subtitle':
        '${currentBill.customerName} · ${currentBill.billingPeriodKey} · ₹${totalDue.toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'billId': billId,
        'billNumber': currentBill.billNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return currentBill.copyWith(
        palaiCharges: palaiCharges,
        currentBillAmount: palaiCharges,
        previousOutstanding: currentOutstanding,
        advanceApplied: advanceApplied,
        totalDue: totalDue,
        amountPaid: amountPaid,
        remainingAmount: remainingAmount,
        status: status,
        goatCount: goatCount,
        goatBreakdown: goatBreakdown,
        notes: notes?.trim() ?? currentBill.notes,
      );
    }).timeout(_timeout);
  }

  // ===========================================================================
// RECEIVE MONTHLY BILL PAYMENT
// ===========================================================================

  /// Receives a payment specifically against one Monthly Bill.
  ///
  /// This operation updates everything atomically:
  ///
  ///   Monthly Bill
  ///       ↓
  ///   amountPaid
  ///   remainingAmount
  ///   status
  ///
  ///   Customer
  ///       ↓
  ///   pendingAmount
  ///
  ///   Payment
  ///       ↓
  ///   payments collection
  ///
  ///   Transaction
  ///       ↓
  ///   transactions collection
  ///
  ///   Activity
  ///       ↓
  ///   activities collection
  ///
  /// Returns a result to the UI.
  ///
  /// Cancellation is NOT handled here.
  /// The UI simply does not call this method when the user cancels.
  Future<MonthlyBillPaymentResult>
  receiveMonthlyBillPayment({
    required String farmId,
    required String customerId,
    required String billId,
    required double paidAmount,
    required String paymentMethod,
    String note = '',
  }) async {
    // -------------------------------------------------------------------------
    // VALIDATION
    // -------------------------------------------------------------------------

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
        .runTransaction<MonthlyBillPaymentResult>(
          (transaction) async {
        // =====================================================================
        // READS
        // =====================================================================

        final customerSnapshot =
        await transaction.get(
          customerRef,
        );

        final billSnapshot =
        await transaction.get(
          billRef,
        );

        // =====================================================================
        // VALIDATE CUSTOMER
        // =====================================================================

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        // =====================================================================
        // VALIDATE BILL
        // =====================================================================

        if (!billSnapshot.exists) {
          throw StateError(
            'Monthly bill no longer exists.',
          );
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final billData =
            billSnapshot.data() ?? {};

        // =====================================================================
        // CUSTOMER INFORMATION
        // =====================================================================

        final customerName =
        (customerData['name'] ?? '')
            .toString();

        // =====================================================================
        // BILL INFORMATION
        // =====================================================================

        final billNumber =
        (billData['billNumber'] ?? billId)
            .toString();

        final billCustomerId =
        (billData['customerId'] ?? '')
            .toString();

        if (billCustomerId != customerId) {
          throw StateError(
            'This monthly bill does not belong to this customer.',
          );
        }

        // =====================================================================
        // CURRENT CUSTOMER BALANCE
        // =====================================================================

        final currentPending =
        _doubleValue(
          customerData['pendingAmount'],
        );

        final currentAdvance =
        _doubleValue(
          customerData['advanceAmount'],
        );

        // =====================================================================
        // CURRENT BILL BALANCE
        // =====================================================================

        final billRemaining =
        _doubleValue(
          billData['remainingAmount'],
        );

        final currentAmountPaid =
        _doubleValue(
          billData['amountPaid'],
        );

        if (billRemaining <= 0) {
          throw StateError(
            'This monthly bill is already paid.',
          );
        }

        // =====================================================================
        // CONSISTENCY GUARD
        //
        // A bill that is correctly the customer's current live bill has
        // remainingAmount == the customer's pendingAmount — that IS the
        // customer's outstanding balance. If the two disagree (e.g. data
        // from before older bills were closed out on creation, or a
        // payment applied straight to an old bill), fail loudly instead
        // of silently applying this payment against a stale number and
        // making the drift worse.
        // =====================================================================

        if ((billRemaining - currentPending).abs() > 0.5) {
          throw StateError(
            'This bill\'s remaining amount (₹${billRemaining.toStringAsFixed(0)}) '
                'does not match the customer\'s outstanding balance '
                '(₹${currentPending.toStringAsFixed(0)}). Open the customer\'s '
                'profile and tap "Sync with Monthly Bills" first, then try the '
                'payment again.',
          );
        }

        // =====================================================================
        // PAYMENT AMOUNT
        // =====================================================================

        final amountAppliedToBill =
        paidAmount > billRemaining
            ? billRemaining
            : paidAmount;

        final extraAmount =
            paidAmount -
                amountAppliedToBill;

        // =====================================================================
        // NEW BILL VALUES
        // =====================================================================

        final newAmountPaid =
            currentAmountPaid +
                amountAppliedToBill;

        final newBillRemaining =
        (billRemaining -
            amountAppliedToBill)
            .clamp(
          0,
          double.infinity,
        )
            .toDouble();

        final newBillStatus =
        newBillRemaining <= 0
            ? 'paid'
            : 'partial';

        // =====================================================================
        // NEW CUSTOMER VALUES
        // =====================================================================

        final newPending =
        (currentPending -
            amountAppliedToBill)
            .clamp(
          0,
          double.infinity,
        )
            .toDouble();

        final newAdvance =
            currentAdvance +
                extraAmount;

        // =====================================================================
        // UPDATE MONTHLY BILL
        // =====================================================================

        transaction.update(
          billRef,
          {
            'amountPaid': newAmountPaid,

            'remainingAmount':
            newBillRemaining,

            'status':
            newBillStatus,

            'paymentStatus':
            newBillStatus,

            'paymentId':
            paymentRef.id,

            'paymentMethod':
            paymentMethod.trim(),

            'paidAt':
            newBillRemaining <= 0
                ? FieldValue.serverTimestamp()
                : null,

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // =====================================================================
        // UPDATE CUSTOMER
        // =====================================================================

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

        // =====================================================================
        // PAYMENT RECORD
        // =====================================================================

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
            amountAppliedToBill,

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

        // =====================================================================
        // TRANSACTION RECORD
        // =====================================================================

        transaction.set(
          transactionRef,
          {
            'type':
            'income',

            'category':
            'Palai Monthly Bill Payment',

            'amount':
            paidAmount,

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
            amountAppliedToBill,

            'paymentMethod':
            paymentMethod.trim(),

            'note':
            note.trim().isEmpty
                ? 'Monthly bill payment from $customerName'
                : note.trim(),

            'date':
            FieldValue.serverTimestamp(),

            'createdAt':
            FieldValue.serverTimestamp(),
          },
        );

        // =====================================================================
        // ACTIVITY
        // =====================================================================

        transaction.set(
          activityRef,
          {
            'type':
            'paymentReceived',

            'title':
            'Monthly Bill Payment',

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

        // =====================================================================
        // RETURN RESULT
        // =====================================================================

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
          amountAppliedToBill,

          billRemainingAfter:
          newBillRemaining,

          pendingAfter:
          newPending,

          advanceAfter:
          newAdvance,

          paymentMethod:
          paymentMethod.trim(),
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
  // RECONCILE CUSTOMER OUTSTANDING WITH MONTHLY BILLS
  // ===========================================================================

  /// Fixes a customer whose profile balance has drifted out of sync with
  /// their actual Monthly Bills — specifically, more than one monthly
  /// bill left showing an open balance at the same time (bad data from
  /// before bills were closed out on creation, or a payment applied to
  /// an old bill directly). Only that specific, double-counted amount is
  /// removed from the customer's pendingAmount.
  ///
  /// IMPORTANT: this does NOT recompute pendingAmount from scratch as
  /// "whatever the latest bill says". pendingAmount can legitimately
  /// include debt that has nothing to do with any monthly bill at all —
  /// a manual "Add Outstanding" entry, a goat checkout charge, etc. —
  /// and blindly overwriting it with a bill's own number would silently
  /// erase that real debt. This only ever subtracts the exact stale
  /// amount it finds sitting in an older, superseded bill.
  Future<double> reconcileCustomerOutstanding({
    required String farmId,
    required String customerId,
  }) async {
    final customerRef = _customers(farmId).doc(customerId);

    // getMonthlyBills() already sorts newest billingMonth first.
    final bills = await getMonthlyBills(
      farmId: farmId,
      customerId: customerId,
    );

    // Every bill AFTER the most recent one that still shows an open
    // balance is stale: its balance is already folded into the latest
    // bill's totalDue (that's how previousOutstanding works), so it's
    // being counted twice. The most recent bill itself is never touched
    // here — it's the one bill whose remainingAmount is meant to be live.
    final staleBills = bills.length > 1
        ? bills.skip(1).where((bill) => bill.remainingAmount > 0).toList()
        : const <MonthlyBill>[];

    if (staleBills.isEmpty) {
      // Nothing double-counted — leave pendingAmount exactly as it is
      // (it may legitimately include non-bill charges) and just report
      // the customer's current balance back.
      final snapshot = await customerRef.get().timeout(_timeout);
      return _doubleValue(snapshot.data()?['pendingAmount']);
    }

    final staleTotal = staleBills.fold<double>(
      0,
          (sum, bill) => sum + bill.remainingAmount,
    );
    final latestBillId = bills.first.id;
    final latestPeriodKey = bills.first.billingPeriodKey;
    final staleBillRefs =
    staleBills.map((bill) => _bills(farmId).doc(bill.id)).toList();

    return _db.runTransaction<double>((transaction) async {
      // ---------------------------------------------------------------
      // READS FIRST
      // ---------------------------------------------------------------

      final customerSnapshot = await transaction.get(customerRef);

      final staleBillSnapshots =
      <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in staleBillRefs) {
        staleBillSnapshots.add(await transaction.get(ref));
      }

      final currentPending =
      _doubleValue(customerSnapshot.data()?['pendingAmount']);

      // Subtract ONLY the amount that was double-counted. Whatever else
      // is sitting in pendingAmount (a manual outstanding entry, a
      // checkout charge, etc.) is left completely untouched.
      final correctedPending =
      (currentPending - staleTotal).clamp(0, double.infinity).toDouble();

      // ---------------------------------------------------------------
      // CLOSE OUT THE STALE BILLS
      // ---------------------------------------------------------------

      for (final snap in staleBillSnapshots) {
        if (!snap.exists) continue;
        transaction.update(snap.reference, {
          'remainingAmount': 0,
          'status': 'paid',
          'paymentStatus': 'paid',
          'carriedForwardIntoBillId': latestBillId,
          'carriedForwardIntoPeriod': latestPeriodKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(customerRef, {
        'pendingAmount': correctedPending,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return correctedPending;
    }).timeout(_timeout);
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