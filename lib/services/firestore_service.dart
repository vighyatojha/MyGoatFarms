import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/bill_settings_model.dart';
import '../models/farm_model.dart';
import '../models/palai_models.dart';
import '../models/report_models.dart';
import '../models/stock_model.dart';
import '../models/activity_model.dart';
import '../models/partner_model.dart';
import '../models/own_farm_models.dart';

class MonthlyBillResult {
  final String billId;
  final String billNumber;

  final double previousPending;
  final double advanceBefore;

  final double newCharges;
  final double advanceApplied;

  final double totalDue;

  final double paid;
  final double amountAppliedToBill;

  final double pendingAfter;
  final double advanceAfter;

  final String paymentMethod;

  const MonthlyBillResult({
    required this.billId,
    required this.billNumber,
    required this.previousPending,
    required this.advanceBefore,
    required this.newCharges,
    required this.advanceApplied,
    required this.totalDue,
    required this.paid,
    required this.amountAppliedToBill,
    required this.pendingAfter,
    required this.advanceAfter,
    required this.paymentMethod,
  });
}

class StandalonePaymentResult {
  final String paymentId;
  final String paymentNumber;

  final String customerName;

  final double pendingBefore;
  final double amountReceived;
  final double amountAppliedToPending;
  final double pendingAfter;

  final double advanceBefore;
  final double advanceAdded;
  final double advanceAfter;

  final String paymentMethod;

  const StandalonePaymentResult({
    required this.paymentId,
    required this.paymentNumber,
    required this.customerName,
    required this.pendingBefore,
    required this.amountReceived,
    required this.amountAppliedToPending,
    required this.pendingAfter,
    required this.advanceBefore,
    required this.advanceAdded,
    required this.advanceAfter,
    required this.paymentMethod,
  });
}


class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// How long any single Firestore call is allowed to hang before we give
  /// up and surface an error instead of spinning forever.
  static const timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> get _farms =>
      _db.collection('farms');

  DocumentReference<Map<String, dynamic>> get _farmCounterDoc =>
      _db.collection('counters').doc('farms');

  // ---------------------------------------------------------------------
  // Farm — lookups
  // ---------------------------------------------------------------------

  /// True if a farm is already registered with this mobile number.
  Future<bool> isMobileNumberTaken(String mobileNumber) async {
    final query = await _farms
        .where('mobileNumber', isEqualTo: mobileNumber)
        .limit(1)
        .get()
        .timeout(timeout);
    return query.docs.isNotEmpty;
  }

  Stream<List<Map<String, dynamic>>>
  customerPaymentHistoryStream(
      String farmId,
      String customerId,
      ) {
    return _farms
        .doc(farmId)
        .collection('payments')
        .where(
      'customerId',
      isEqualTo: customerId,
    )
        .orderBy(
      'date',
      descending: true,
    )
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
            (doc) => {
          'id': doc.id,
          ...doc.data(),
        },
      )
          .toList(),
    );
  }

  Future<void> addOutstandingAmount({
    required String farmId,
    required String customerId,
    required double amount,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw ArgumentError(
        'Outstanding amount must be greater than zero.',
      );
    }

    final customerRef =
    _customers(farmId).doc(customerId);

    final billsCollection =
    _farms.doc(farmId).collection('bills');

    final activitiesCollection =
    _farms.doc(farmId).collection('activities');

    final billRef =
    billsCollection.doc();

    final activityRef =
    activitiesCollection.doc();

    await _db.runTransaction<void>(
          (transaction) async {
        final customerSnapshot =
        await transaction.get(customerRef);

        if (!customerSnapshot.exists) {
          throw StateError(
            'Customer no longer exists.',
          );
        }

        final data =
            customerSnapshot.data() ?? {};

        final customerName =
        (data['name'] ?? '').toString();

        final currentPending =
        (data['pendingAmount'] ?? 0)
            .toDouble();

        final newPending =
            currentPending + amount;

        final now = DateTime.now();

        final billNumber =
            'OUT-${now.year}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}'
            '-${billRef.id.substring(0, 6).toUpperCase()}';

        // ------------------------------------------------------------
        // Create outstanding record.
        //
        // This is NOT an income transaction because money has not
        // actually been received.
        // ------------------------------------------------------------

        transaction.set(
          billRef,
          {
            'billNumber': billNumber,
            'type': 'manualOutstanding',

            'customerId': customerId,
            'customerName': customerName,

            'newCharges': amount,
            'amount': amount,
            'totalAmount': amount,

            'previousPending': currentPending,
            'pendingAfter': newPending,

            'amountPaid': 0,
            'status': 'pending',

            'note': note.trim(),

            'createdAt':
            FieldValue.serverTimestamp(),
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ------------------------------------------------------------
        // Update customer
        // ------------------------------------------------------------

        transaction.update(
          customerRef,
          {
            'pendingAmount': newPending,
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ------------------------------------------------------------
        // Activity
        // ------------------------------------------------------------

        transaction.set(
          activityRef,
          {
            'type': 'outstandingAdded',

            'title':
            'Outstanding Amount Added',

            'subtitle':
            '$customerName · ₹${amount.toStringAsFixed(0)}',

            'module': 'palai',

            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );
      },
    ).timeout(FirestoreService.timeout);
  }

  /// Creates a complete monthly Palai bill.
  ///
  /// This is the ONLY operation the Billing screen should use to create
  /// financial data.
  ///
  /// Atomically creates:
  /// - bill
  /// - payment (when payment > 0)
  /// - income transaction (when payment > 0)
  /// - customer balance update
  /// - activity log
  ///
  /// It also correctly handles customer advances.
  Future<MonthlyBillResult> createMonthlyBill({
    required String farmId,
    required String customerId,
    required double monthlyCharges,
    required double transportCharges,
    required double discount,
    required double paidAmount,
    required String paymentMethod,
    String note = '',
  }) async {
    if (monthlyCharges < 0 ||
        transportCharges < 0 ||
        discount < 0 ||
        paidAmount < 0) {
      throw ArgumentError('Amounts cannot be negative.');
    }

    if (paidAmount > 0 && paymentMethod.trim().isEmpty) {
      throw ArgumentError(
        'Please select a payment method.',
      );
    }

    final customerRef = _customers(farmId).doc(customerId);

    final billsCollection =
    _farms.doc(farmId).collection('bills');

    final paymentsCollection =
    _farms.doc(farmId).collection('payments');

    final transactionsCollection =
    _farms.doc(farmId).collection('transactions');

    final activitiesCollection =
    _farms.doc(farmId).collection('activities');

    // Generate references before the transaction.
    // They remain the same if Firestore retries the transaction.
    final billRef = billsCollection.doc();

    final paymentRef = paidAmount > 0
        ? paymentsCollection.doc()
        : null;

    final transactionRef = paidAmount > 0
        ? transactionsCollection.doc()
        : null;

    final activityRef = activitiesCollection.doc();

    final now = DateTime.now();

    final billNumber =
        'PAL-${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-${billRef.id.substring(0, 6).toUpperCase()}';

    return _db.runTransaction<MonthlyBillResult>(
          (transaction) async {
        // ------------------------------------------------------------
        // READ FIRST
        // ------------------------------------------------------------

        final customerSnapshot =
        await transaction.get(customerRef);

        if (!customerSnapshot.exists) {
          throw StateError('Customer no longer exists.');
        }

        final customerData =
            customerSnapshot.data() ?? {};

        final customerName =
        (customerData['name'] ?? '').toString();

        final previousPending =
        (customerData['pendingAmount'] ?? 0)
            .toDouble();

        final advanceBefore =
        (customerData['advanceAmount'] ?? 0)
            .toDouble();

        // ------------------------------------------------------------
        // CALCULATE
        // ------------------------------------------------------------

        final newCharges =
        (monthlyCharges +
            transportCharges -
            discount)
            .clamp(0, double.infinity)
            .toDouble();

        final totalBeforeAdvance =
            previousPending + newCharges;

        // Apply any existing customer advance.
        final advanceApplied =
        advanceBefore
            .clamp(0, totalBeforeAdvance)
            .toDouble();

        final totalDue =
        (totalBeforeAdvance -
            advanceApplied)
            .clamp(0, double.infinity)
            .toDouble();

        // Payment first clears the bill.
        final amountAppliedToBill =
        paidAmount
            .clamp(0, totalDue)
            .toDouble();

        // Anything above the amount due becomes advance.
        final newAdvanceFromPayment =
        (paidAmount - totalDue)
            .clamp(0, double.infinity)
            .toDouble();

        final pendingAfter =
        (totalDue - paidAmount)
            .clamp(0, double.infinity)
            .toDouble();

        final advanceAfter =
        (advanceBefore -
            advanceApplied +
            newAdvanceFromPayment)
            .clamp(0, double.infinity)
            .toDouble();

        final status = totalDue == 0
            ? 'paid'
            : pendingAfter == 0
            ? 'paid'
            : paidAmount > 0
            ? 'partial'
            : 'pending';

        // ------------------------------------------------------------
        // WRITE BILL
        // ------------------------------------------------------------

        transaction.set(billRef, {
          'billNumber': billNumber,

          'type': 'monthly',
          'customerId': customerId,
          'customerName': customerName,

          'periodMonth':
          '${now.year}-${now.month.toString().padLeft(2, '0')}',

          'monthlyCharges': monthlyCharges,
          'transportCharges': transportCharges,
          'discount': discount,

          'newCharges': newCharges,

          'previousPending': previousPending,
          'advanceBefore': advanceBefore,
          'advanceApplied': advanceApplied,

          'totalDue': totalDue,

          'amountPaid': paidAmount,
          'amountAppliedToBill':
          amountAppliedToBill,

          'pendingAfter': pendingAfter,
          'advanceAfter': advanceAfter,

          'paymentId': paymentRef?.id,
          'paymentMethod':
          paidAmount > 0
              ? paymentMethod
              : null,

          'note': note.trim(),

          'status': status,

          'createdAt':
          FieldValue.serverTimestamp(),
          'updatedAt':
          FieldValue.serverTimestamp(),
        });

        // ------------------------------------------------------------
        // WRITE PAYMENT
        // ------------------------------------------------------------

        if (paymentRef != null) {
          transaction.set(paymentRef, {
            // ----------------------------------------------------------
            // PAYMENT IDENTITY
            // ----------------------------------------------------------
            'paymentNumber':
            'PAY-${paymentRef.id.substring(0, 8).toUpperCase()}',

            'type': 'billPayment',

            'customerId': customerId,
            'customerName': customerName,

            'billId': billRef.id,
            'billNumber': billNumber,

            // ----------------------------------------------------------
            // PAYMENT AMOUNT
            // ----------------------------------------------------------
            'amount': paidAmount,

            'amountReceived': paidAmount,

            // Amount of the payment actually used against this bill.
            'amountAppliedToBill': amountAppliedToBill,

            // Alias used by the Customer Profile payment details.
            'amountAppliedToPending': amountAppliedToBill,

            // ----------------------------------------------------------
            // BILL SNAPSHOT
            //
            // These values MUST be stored on the payment itself.
            // Do not calculate them later from the customer's current
            // balance because the customer balance may change.
            // ----------------------------------------------------------

            // Amount due immediately before this payment.
            //
            // Example:
            // Previous pending = ₹6500
            // New charges     = ₹3000
            // Total due       = ₹9500
            //
            // Therefore payment pendingBefore = ₹9500.
            'pendingBefore': totalDue,

            'pendingAfter': pendingAfter,

            // Keep the original previous balance too.
            'previousPending': previousPending,

            'newCharges': newCharges,

            // ----------------------------------------------------------
            // ADVANCE SNAPSHOT
            // ----------------------------------------------------------

            'advanceBefore': advanceBefore,

            // Existing advance used against this bill.
            'advanceApplied': advanceApplied,

            // New advance created by THIS payment.
            //
            // Example:
            // Payment = ₹10000
            // Due     = ₹9500
            // New advance = ₹500
            'advanceAmount': newAdvanceFromPayment,

            'advanceAdded': newAdvanceFromPayment,

            // Final advance balance after this payment.
            'advanceAfter': advanceAfter,

            // ----------------------------------------------------------
            // PAYMENT METHOD
            // ----------------------------------------------------------

            'paymentMethod': paymentMethod,

            'note': note.trim(),

            // ----------------------------------------------------------
            // DATES
            // ----------------------------------------------------------

            'date': FieldValue.serverTimestamp(),

            'createdAt': FieldValue.serverTimestamp(),

            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // ------------------------------------------------------------
        // WRITE INCOME TRANSACTION
        // ------------------------------------------------------------

        if (transactionRef != null) {
          transaction.set(transactionRef, {
            'amount': paidAmount,
            'isIncome': true,

            'category': 'Palai Payment',

            'customerId': customerId,
            'customerName': customerName,

            'billId': billRef.id,
            'billNumber': billNumber,

            'paymentId': paymentRef?.id,

            'paymentMethod':
            paymentMethod,

            'note': note.trim().isNotEmpty
                ? note.trim()
                : 'Payment received from $customerName',

            'date':
            FieldValue.serverTimestamp(),

            'createdAt':
            FieldValue.serverTimestamp(),
          });
        }

        // ------------------------------------------------------------
        // UPDATE CUSTOMER BALANCE
        // ------------------------------------------------------------

        transaction.update(customerRef, {
          'pendingAmount': pendingAfter,
          'advanceAmount': advanceAfter,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // ------------------------------------------------------------
        // ACTIVITY
        // ------------------------------------------------------------

        transaction.set(activityRef, {
          'type': 'paymentReceived',
          'title': 'Monthly Bill Generated',

          'subtitle':
          '$customerName · Bill $billNumber · '
              'Total ₹${totalDue.toStringAsFixed(0)}',

          'module': 'palai',

          'timestamp':
          FieldValue.serverTimestamp(),
        });

        return MonthlyBillResult(
          billId: billRef.id,
          billNumber: billNumber,

          previousPending:
          previousPending,

          advanceBefore:
          advanceBefore,

          newCharges:
          newCharges,

          advanceApplied:
          advanceApplied,

          totalDue:
          totalDue,

          paid:
          paidAmount,

          amountAppliedToBill:
          amountAppliedToBill,

          pendingAfter:
          pendingAfter,

          advanceAfter:
          advanceAfter,

          paymentMethod:
          paymentMethod,
        );
      },
    ).timeout(timeout);
  }



  /// Records a standalone payment from a Palai customer.
  ///
  /// This operation is atomic:
  /// - reads current pending + advance
  /// - applies payment to pending first
  /// - stores excess payment as advance
  /// - creates payment record
  /// - creates income transaction
  /// - updates customer balance
  /// - creates activity
  ///
  /// This is intentionally separate from createMonthlyBill() because
  /// Receive Payment is a payment without generating a new bill.
  Future<StandalonePaymentResult> receivePalaiPayment({
    required String farmId,
    required String customerId,
    required double paidAmount,
    required String paymentMethod,
    String note = '',
  }) async {
    if (paidAmount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }

    if (paymentMethod.trim().isEmpty) {
      throw ArgumentError('Please select a payment method.');
    }

    final customerRef = _customers(farmId).doc(customerId);

    final paymentsCollection =
    _farms.doc(farmId).collection('payments');

    final transactionsCollection =
    _farms.doc(farmId).collection('transactions');

    final activitiesCollection =
    _farms.doc(farmId).collection('activities');

    final paymentRef = paymentsCollection.doc();
    final transactionRef = transactionsCollection.doc();
    final activityRef = activitiesCollection.doc();

    final now = DateTime.now();

    return _db.runTransaction<StandalonePaymentResult>(
          (transaction) async {
        // ============================================================
        // READ CURRENT CUSTOMER
        // ============================================================

        final customerSnapshot =
        await transaction.get(customerRef);

        if (!customerSnapshot.exists) {
          throw StateError('Customer no longer exists.');
        }

        final data = customerSnapshot.data() ?? {};

        final customerName =
        (data['name'] ?? '').toString();

        final pendingBefore =
        (data['pendingAmount'] ?? 0).toDouble();

        final advanceBefore =
        (data['advanceAmount'] ?? 0).toDouble();

        // ============================================================
        // CALCULATE PAYMENT
        // ============================================================

        // Existing advance does not need to be changed by a standalone
        // payment. A new payment first clears pending and then creates
        // additional advance if it exceeds pending.
        final amountAppliedToPending =
        paidAmount
            .clamp(0, pendingBefore)
            .toDouble();

        final excessPayment =
        (paidAmount - amountAppliedToPending)
            .clamp(0, double.infinity)
            .toDouble();

        final pendingAfter =
        (pendingBefore - amountAppliedToPending)
            .clamp(0, double.infinity)
            .toDouble();

        final advanceAfter =
        (advanceBefore + excessPayment)
            .clamp(0, double.infinity)
            .toDouble();

        final paymentNumber =
            'PAY-${paymentRef.id.substring(0, 8).toUpperCase()}';

        // ============================================================
        // PAYMENT RECORD
        // ============================================================

        transaction.set(paymentRef, {
          'paymentNumber': paymentNumber,

          'type': 'standalone',

          'customerId': customerId,
          'customerName': customerName,

          'amount': paidAmount,

          'amountAppliedToPending':
          amountAppliedToPending,

          'advanceAmount':
          excessPayment,

          'pendingBefore':
          pendingBefore,

          'pendingAfter':
          pendingAfter,

          'advanceBefore':
          advanceBefore,

          'advanceAfter':
          advanceAfter,

          'paymentMethod':
          paymentMethod.trim(),

          'note':
          note.trim(),

          'date':
          FieldValue.serverTimestamp(),

          'createdAt':
          FieldValue.serverTimestamp(),
        });

        // ============================================================
        // INCOME TRANSACTION
        // ============================================================

        transaction.set(transactionRef, {
          'amount': paidAmount,

          'isIncome': true,

          'category': 'Payment Received',

          'customerId': customerId,

          'customerName': customerName,

          'paymentId': paymentRef.id,

          'paymentNumber': paymentNumber,

          'amountAppliedToPending':
          amountAppliedToPending,

          'advanceAmount':
          excessPayment,

          'paymentMethod':
          paymentMethod.trim(),

          'note': note.trim().isNotEmpty
              ? note.trim()
              : 'Payment received from $customerName',

          'date':
          FieldValue.serverTimestamp(),

          'createdAt':
          FieldValue.serverTimestamp(),
        });

        // ============================================================
        // UPDATE CUSTOMER
        // ============================================================

        transaction.update(customerRef, {
          'pendingAmount': pendingAfter,

          'advanceAmount': advanceAfter,

          'updatedAt':
          FieldValue.serverTimestamp(),
        });

        // ============================================================
        // ACTIVITY
        // ============================================================

        transaction.set(activityRef, {
          'type': 'paymentReceived',

          'title': 'Payment Received',

          'subtitle':
          '$customerName · ₹${paidAmount.toStringAsFixed(0)}',

          'module': 'palai',

          'timestamp':
          FieldValue.serverTimestamp(),
        });

        // ============================================================
        // RETURN RESULT
        // ============================================================

        return StandalonePaymentResult(
          paymentId: paymentRef.id,
          paymentNumber: paymentNumber,

          customerName: customerName,

          pendingBefore: pendingBefore,

          amountReceived: paidAmount,

          amountAppliedToPending:
          amountAppliedToPending,

          pendingAfter: pendingAfter,

          advanceBefore: advanceBefore,

          advanceAdded: excessPayment,

          advanceAfter: advanceAfter,

          paymentMethod: paymentMethod.trim(),
        );
      },
    ).timeout(timeout);
  }



  /// Resolves the email linked to a mobile number, used for mobile-number
  /// login (Firebase Auth itself only signs in with email + password).
  ///
  /// Checks farm OWNER accounts first, then falls back to PARTNER
  /// accounts (`farms/{farmId}/partners`) — previously this only looked
  /// at farm owners, so a partner logging in with their mobile number
  /// always got "No farm account found", never their email resolved.
  Future<String?> findEmailByMobile(String mobileNumber) async {
    final query = await _farms
        .where('mobileNumber', isEqualTo: mobileNumber)
        .limit(1)
        .get()
        .timeout(timeout);
    if (query.docs.isNotEmpty) {
      return query.docs.first.data()['email'] as String?;
    }

    try {
      final partnerQuery = await FirebaseFirestore.instance
          .collectionGroup('partners')
          .where('mobileNumber', isEqualTo: mobileNumber)
          .limit(1)
          .get()
          .timeout(timeout);
      if (partnerQuery.docs.isEmpty) return null;
      return partnerQuery.docs.first.data()['email'] as String?;
    } catch (e) {
      debugPrint('FirestoreService.findEmailByMobile partner lookup error: $e');
      return null;
    }
  }

  Future<FarmModel?> getFarmByAuthUid(String uid) async {
    try {
      final query = await _farms
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get()
          .timeout(timeout);
      if (query.docs.isEmpty) return null;
      return FarmModel.fromDoc(query.docs.first);
    } catch (e) {
      debugPrint('FirestoreService.getFarmByAuthUid error: $e');
      return null;
    }
  }

  /// Looks up the partner record (if any) linked to [uid] across every
  /// farm's `partners` subcollection, using a `collectionGroup` query.
  ///
  /// Returns null both when [uid] simply isn't a partner anywhere, AND
  /// when the query itself fails (e.g. missing Firestore security rule
  /// or index) — in both cases the caller should fall back to treating
  /// this as "no linked account" rather than hanging indefinitely.
  Future<PartnerModel?> getPartnerByAuthUid(String uid) async {
    try {
      final query = await FirebaseFirestore.instance
          .collectionGroup('partners')
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get()
          .timeout(timeout);
      if (query.docs.isEmpty) return null;
      return PartnerModel.fromDoc(query.docs.first);
    } catch (e) {
      debugPrint('FirestoreService.getPartnerByAuthUid error: $e');
      return null;
    }
  }

  /// Resolves the farm that [uid] should land on after login, regardless
  /// of whether they are the farm owner or a partner.
  ///
  /// 1. First tries [uid] as a farm OWNER (`farms.authUid == uid`).
  /// 2. If that finds nothing, tries [uid] as a PARTNER — looks up their
  ///    partner record via [getPartnerByAuthUid], then loads the farm
  ///    that partner record belongs to.
  ///
  /// Returns null if [uid] isn't linked to any farm as either role.
  Future<FarmModel?> getFarmForUser(String uid) async {
    final ownerFarm = await getFarmByAuthUid(uid);
    if (ownerFarm != null) return ownerFarm;

    final partner = await getPartnerByAuthUid(uid);
    if (partner == null || partner.farmId.isEmpty) return null;

    return getFarmById(partner.farmId);
  }

  /// Convenience getter used by every module to resolve the current
  /// farm's document id before reading/writing sub-collections. Works
  /// for both farm owners and partners — see [getFarmForUser].
  Future<String?> currentFarmId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final farm = await getFarmForUser(uid);
    return farm?.id;
  }

  /// One-off fetch of a farm document by its id (as opposed to
  /// [farmDocStream], which stays subscribed). Used where a screen just
  /// needs a snapshot of current settings — e.g. reading [BillSettings]
  /// before generating a check-out bill PDF.
  Future<FarmModel?> getFarmById(String farmId) async {
    try {
      final doc = await _farms.doc(farmId).get().timeout(timeout);
      if (!doc.exists) return null;
      return FarmModel.fromDoc(doc);
    } catch (e) {
      debugPrint('FirestoreService.getFarmById error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Farm — ID generation & creation
  // ---------------------------------------------------------------------

  Future<String> _nextFarmId() async {
    await _farmCounterDoc
        .set({'lastId': FieldValue.increment(1)}, SetOptions(merge: true))
        .timeout(timeout);

    final snapshot = await _farmCounterDoc.get().timeout(timeout);
    final lastId = (snapshot.data()?['lastId'] as int?) ?? 1;
    return 'FRM$lastId';
  }

  /// Creates a new farm document with a fresh sequential ID and returns it.
  Future<FarmModel> createFarm({
    required String authUid,
    required String farmName,
    required String ownerName,
    required String mobileNumber,
    required String email,
    String address = '',
    String logoUrl = '',
  }) async {
    final farmId = await _nextFarmId();

    final farm = FarmModel(
      id: farmId,
      authUid: authUid,
      farmName: farmName,
      ownerName: ownerName,
      mobileNumber: mobileNumber,
      email: email,
      address: address,
      logoUrl: logoUrl,
    );

    await _farms.doc(farmId).set({
      ...farm.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);

    return farm;
  }

  // ---------------------------------------------------------------------
  // Error messages
  // ---------------------------------------------------------------------

  /// Turns raw Firestore errors into messages that actually tell the user
  /// what to do, instead of a generic failure or a raw stack trace.
  String describeError(Object e) {
    final message = e.toString();
    debugPrint('Firestore raw error: $e'); // always log the real error

    if (message.contains('NOT_FOUND') && message.contains('database')) {
      return 'Firestore database not reachable yet. If you just created it, '
          'wait a minute and try again.';
    }
    if (message.contains('PERMISSION_DENIED')) {
      return 'Firestore security rules are blocking this request.';
    }
    if (e is FirebaseException) {
      // Surface the actual plugin error code (unavailable, deadline-exceeded,
      // unauthenticated, resource-exhausted, etc.) instead of a generic
      // message that hides what's actually going wrong.
      return 'Could not reach Firestore [${e.code}]: ${e.message ?? 'no details'}';
    }
    return 'Could not reach Firestore: $message';
  }

  // ---------------------------------------------------------------------
  // Activities (shared recent-activity feed for Home / Palai / Stock)
  // ---------------------------------------------------------------------

  Future<void> logActivity(String farmId, ActivityLog activity) async {
    await _farms
        .doc(farmId)
        .collection('activities')
        .add(activity.toMap())
        .timeout(timeout);
  }

  Stream<List<ActivityLog>> activitiesStream(String farmId, {String? module, int limit = 20}) {
    Query<Map<String, dynamic>> q = _farms
        .doc(farmId)
        .collection('activities')
        .orderBy('timestamp', descending: true)
        .limit(limit);
    if (module != null) {
      q = _farms
          .doc(farmId)
          .collection('activities')
          .where('module', isEqualTo: module)
          .orderBy('timestamp', descending: true)
          .limit(limit);
    }
    return q.snapshots().map((s) => s.docs.map(ActivityLog.fromDoc).toList());
  }

  // ---------------------------------------------------------------------
  // Transactions (income / expense — used for dashboard totals)
  // ---------------------------------------------------------------------

  Future<void> addTransaction(
      String farmId, {
        required double amount,
        required bool isIncome,
        required String category, // e.g. "Palai Payment", "Feed Purchase"
        required String note,
      }) async {
    await _farms.doc(farmId).collection('transactions').add({
      'amount': amount,
      'isIncome': isIncome,
      'category': category,
      'note': note,
      'date': FieldValue.serverTimestamp(),
    });
  }

  /// Streams today's net income (sum of income - expense for today).
  Stream<double> todaysIncomeStream(String farmId) {
    final start = DateTime.now();
    final startOfDay = DateTime(start.year, start.month, start.day);
    return _farms
        .doc(farmId)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .snapshots()
        .map((snap) {
      double total = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        total += (data['isIncome'] == true) ? amount : -amount;
      }
      return total;
    });
  }

  /// Streams total pending payments across all Palai customers.
  Stream<double> totalPendingPaymentsStream(String farmId) {
    return _farms
        .doc(farmId)
        .collection('palaiCustomers')
        .snapshots()
        .map((snap) => snap.docs.fold<double>(
      0,
          (total, doc) => total + ((doc.data()['pendingAmount'] ?? 0) as num).toDouble(),
    ));
  }

  /// Streams total payments received (income only) so far this calendar
  /// month, across all transactions for the farm.
  Stream<double> monthlyPaymentsReceivedStream(String farmId) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

    return _farms
        .doc(farmId)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThan: Timestamp.fromDate(startOfNextMonth))
        .snapshots()
        .map((snap) {
      double total = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isIncome'] == true) {
          total += (data['amount'] ?? 0).toDouble();
        }
      }
      return total;
    });
  }

  // ---------------------------------------------------------------------
  // Palai — customers
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _customers(String farmId) =>
      _farms.doc(farmId).collection('palaiCustomers');

  Future<String> addCustomer(String farmId, PalaiCustomer customer) async {
    final ref = await _customers(farmId).add(customer.toMap()).timeout(timeout);
    return ref.id;
  }

  Stream<List<PalaiCustomer>> customersStream(String farmId) {
    return _customers(farmId)
        .orderBy('joiningDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PalaiCustomer.fromDoc).toList());
  }

  /// Fetches a single customer once (not a stream) — used to prefill the
  /// edit form when opening a customer straight from a deep link.
  Future<PalaiCustomer?> getCustomer(String farmId, String customerId) async {
    final doc = await _customers(farmId).doc(customerId).get().timeout(timeout);
    if (!doc.exists) return null;
    return PalaiCustomer.fromDoc(doc);
  }

  Future<void> updateCustomerPendingAmount(String farmId, String customerId, double newPending) {
    return _customers(farmId).doc(customerId).update({'pendingAmount': newPending}).timeout(timeout);
  }

  /// Updates every editable field on a customer (name, mobile, address,
  /// package, pending amount). Leaves `joiningDate` untouched.
  Future<void> updateCustomer(String farmId, PalaiCustomer customer) {
    return _customers(farmId).doc(customer.id).update(customer.toUpdateMap()).timeout(timeout);
  }

  /// True if this customer currently has any goat checked into Palai and
  /// not yet checked out. Used to block deletion until goats are checked
  /// out, since a customer record is what check-out/billing hangs off of.
  Future<bool> customerHasActiveGoats(String farmId, String customerId) async {
    final snap = await _goats(farmId, customerId)
        .where('isCheckedOut', isEqualTo: false)
        .limit(1)
        .get()
        .timeout(timeout);
    return snap.docs.isNotEmpty;
  }

  /// Removes a customer record entirely. Past bills/activity referencing
  /// them by name stay in the activity log; only the live customer
  /// document (and their checked-out goat history under it) is deleted.
  Future<void> deleteCustomer(String farmId, String customerId) async {
    // Clean up the goats subcollection first — deleting a Firestore
    // document does NOT cascade-delete its subcollections.
    final goatsSnap = await _goats(farmId, customerId).get().timeout(timeout);
    final batch = _db.batch();
    for (final doc in goatsSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_customers(farmId).doc(customerId));
    await batch.commit().timeout(timeout);
  }

  // ---------------------------------------------------------------------
  // Palai — goats
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _goats(String farmId, String customerId) =>
      _customers(farmId).doc(customerId).collection('goats');

  /// All goats currently boarded in Palai, across every customer.
  ///
  /// FIX: filters by `farmId` *in the query itself*, not just client-side
  /// after the fetch. Cloud Firestore security rules aren't a post-hoc
  /// filter for `list`/collection-group requests — the rule is checked
  /// against every document the query could *possibly* match, not just
  /// the ones actually returned. The old version only had
  /// `.where('isCheckedOut', isEqualTo: false)`, so Firestore couldn't
  /// prove that *every* checked-in goat across the whole database — from
  /// any farm — would satisfy `isOwnerOrPartner(resource.data.farmId)`,
  /// and rejected the entire request with `permission-denied`, even for
  /// the caller's own farm. Adding the `farmId` equality filter here lets
  /// Firestore verify every possible result has `farmId == farmId`, which
  /// the rule can then check deterministically. Relies on `checkInGoat`
  /// denormalizing `farmId` onto the goat document (see below).
  Stream<List<PalaiGoat>> allActiveGoatsStream(String farmId) {
    return _db
        .collectionGroup('goats')
        .where('farmId', isEqualTo: farmId)
        .where('isCheckedOut', isEqualTo: false)
        .orderBy('isCheckedOut', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(PalaiGoat.fromDoc)
          .toList(),
    );
  }

  Stream<List<PalaiGoat>> goatsForCustomerStream(String farmId, String customerId) {
    return _goats(farmId, customerId)
        .orderBy('checkInDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PalaiGoat.fromDoc).toList());
  }

  Future<String> checkInGoat(String farmId, String customerId, PalaiGoat goat) async {
    // Denormalize farmId onto the goat document itself. This is required
    // for the Firestore security rule that guards the collectionGroup
    // ('goats') query (used by allActiveGoatsStream / the "Goats in
    // Palai" list) — Firebase's documented pattern for collection-group
    // rules checks a field stored directly on the document
    // (`resource.data.farmId`), not a value parsed out of its path. It's
    // also now required by the query itself (see allActiveGoatsStream),
    // which filters `.where('farmId', isEqualTo: farmId)` so Firestore
    // can prove the collection-group query is safe under that rule.
    final data = goat.toMap()..['farmId'] = farmId;
    final ref = await _goats(farmId, customerId).add(data);
    return ref.id;
  }

  /// Self-healing repair step for `allActiveGoatsStream`'s collection-group
  /// query. That query (and the security rule guarding it) only matches
  /// goat documents that have `farmId` denormalized onto them — any goat
  /// missing that field (added before `checkInGoat` started stamping it,
  /// imported by hand, edited directly in the console, etc.) silently
  /// disappears from "Goats in Palai" and the Health Records goat picker
  /// forever, with no error shown, because the query itself excludes it.
  ///
  /// This walks every customer's `goats` subcollection for [farmId] and
  /// patches any document whose `farmId` is missing or wrong. It's cheap,
  /// idempotent, and safe to call every time the goat list screen opens —
  /// on a farm where everything is already correct it does a handful of
  /// reads and zero writes.
  Future<void> backfillMissingGoatFarmIds(String farmId) async {
    final customersSnap = await _customers(farmId).get().timeout(timeout);
    final batch = _db.batch();
    var needsCommit = false;
    for (final customerDoc in customersSnap.docs) {
      final goatsSnap = await _goats(farmId, customerDoc.id).get().timeout(timeout);
      for (final goatDoc in goatsSnap.docs) {
        if (goatDoc.data()['farmId'] != farmId) {
          batch.update(goatDoc.reference, {'farmId': farmId});
          needsCommit = true;
        }
      }
    }
    if (needsCommit) {
      await batch.commit().timeout(timeout);
    }
  }

  /// Records a goat's check-out. When an "After Palai" [afterImage] is
  /// supplied, it's stored as a Firestore `Blob` directly on the goat
  /// document — the same way the "Before Palai" (check-in) photo and the
  /// farm profile photo are stored, with no Storage bucket required.
  Future<void> checkOutGoat(
      String farmId,
      String customerId,
      String goatId, {
        required double finalWeight,
        required String healthStatus,
        Uint8List? afterImage,
        String? afterImageContentType,
      }) {
    final data = <String, dynamic>{
      'isCheckedOut': true,
      'checkOutDate': FieldValue.serverTimestamp(),
      'currentWeight': finalWeight,
      'healthStatus': healthStatus,
    };
    if (afterImage != null) {
      data['afterImage'] = Blob(afterImage);
      data['afterImageContentType'] = afterImageContentType ?? 'image/jpeg';
    }
    return _goats(farmId, customerId).doc(goatId).update(data);
  }

  Future<void> addHealthRecord(
      String farmId,
      String customerId,
      String goatId,
      HealthRecordEntry entry,
      ) async {
    await _goats(farmId, customerId)
        .doc(goatId)
        .collection('healthRecords')
        .add(entry.toMap());
    // Reflect the latest weight and health status directly on the goat
    // document too, so the goat list badge / filters (which read
    // PalaiGoat.healthStatus, not the health-records subcollection)
    // immediately show this update.
    await _goats(farmId, customerId).doc(goatId).update({
      'currentWeight': entry.weight,
      'healthStatus': entry.healthStatus,
    });
  }

  Stream<List<HealthRecordEntry>> healthRecordsStream(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(farmId, customerId)
        .doc(goatId)
        .collection('healthRecords')
        .orderBy('recordedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(HealthRecordEntry.fromDoc).toList());
  }

  // ---------------------------------------------------------------------
  // Palai — health events (vaccination, deworming, hoof cutting / khud
  // cutting, hair trimming, medicine, checkup) with reminder due-dates.
  // Reuses the same [HealthEvent] model as the Own Farm herd so the two
  // modules stay consistent.
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _palaiHealthEvents(
      String farmId, String customerId, String goatId) =>
      _goats(farmId, customerId).doc(goatId).collection('healthEvents');

  Future<void> addPalaiHealthEvent(
      String farmId,
      String customerId,
      String goatId,
      HealthEvent event,
      ) async {
    await _palaiHealthEvents(farmId, customerId, goatId).add(event.toMap()).timeout(timeout);
  }

  Stream<List<HealthEvent>> palaiHealthEventsStream(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _palaiHealthEvents(farmId, customerId, goatId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(HealthEvent.fromDoc).toList());
  }

  // ---------------------------------------------------------------------
  // Palai — monthly progress photos
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _monthlyPhotos(
      String farmId, String customerId, String goatId) =>
      _goats(farmId, customerId).doc(goatId).collection('monthlyPhotos');

  Future<void> addMonthlyPhoto(
      String farmId,
      String customerId,
      String goatId,
      MonthlyPhoto photo,
      ) async {
    await _monthlyPhotos(farmId, customerId, goatId).add(photo.toMap()).timeout(timeout);
  }

  Stream<List<MonthlyPhoto>> monthlyPhotosStream(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _monthlyPhotos(farmId, customerId, goatId)
        .orderBy('month', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MonthlyPhoto.fromDoc).toList());
  }

  Future<void> deleteMonthlyPhoto(
      String farmId,
      String customerId,
      String goatId,
      String photoId,
      ) async {
    await _monthlyPhotos(farmId, customerId, goatId).doc(photoId).delete().timeout(timeout);
  }

  // ---------------------------------------------------------------------
  // Palai — goat reports (Generate Report)
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _reports(String farmId, String customerId, String goatId) =>
      _goats(farmId, customerId).doc(goatId).collection('reports');

  /// Saves a newly generated [report] under the goat, then updates the
  /// goat document's `reportStatus` / `lastReportType` / `lastReportDate`
  /// / `reportsCount` fields so the "Report" badge on the goat card (and
  /// anywhere else the goat is shown) reflects it immediately — without
  /// touching any of the goat's other check-in data.
  Future<void> saveGoatReport(
      String farmId,
      String customerId,
      String goatId,
      GoatReport report,
      ) async {
    await _reports(farmId, customerId, goatId).add(report.toMap()).timeout(timeout);
    await _goats(farmId, customerId).doc(goatId).update({
      'reportStatus': report.type.statusLabel,
      'lastReportType': report.type.storageValue,
      'lastReportDate': FieldValue.serverTimestamp(),
      'reportsCount': FieldValue.increment(1),
    }).timeout(timeout);
  }

  /// Every report generated for this goat so far, most recent first —
  /// used by a goat's report history (if/when shown).
  Stream<List<GoatReport>> goatReportsStream(String farmId, String customerId, String goatId) {
    return _reports(farmId, customerId, goatId)
        .orderBy('generatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(GoatReport.fromDoc).toList());
  }

  /// One-time fetch of the most recently generated report for this goat,
  /// or null if none exists yet. Used by CustomerGoatsProgressReportScreen
  /// to decide the "previous" photo for a goat: the last report's photo
  /// if one exists, otherwise the goat's check-in photo.
  Future<GoatReport?> getLatestGoatReport(
      String farmId,
      String customerId,
      String goatId,
      ) async {
    final snap = await _reports(farmId, customerId, goatId)
        .orderBy('generatedAt', descending: true)
        .limit(1)
        .get()
        .timeout(timeout);
    if (snap.docs.isEmpty) return null;
    return GoatReport.fromDoc(snap.docs.first);
  }

  /// One-time fetch of the most recently logged health record for this
  /// goat, or null if none exists yet. Used the same way as
  /// [getLatestGoatReport] — a single read instead of opening a stream,
  /// since the caller just needs the latest values, not live updates.
  Future<HealthRecordEntry?> getLatestHealthRecord(
      String farmId,
      String customerId,
      String goatId,
      ) async {
    final snap = await _goats(farmId, customerId)
        .doc(goatId)
        .collection('healthRecords')
        .orderBy('recordedAt', descending: true)
        .limit(1)
        .get()
        .timeout(timeout);
    if (snap.docs.isEmpty) return null;
    return HealthRecordEntry.fromDoc(snap.docs.first);
  }

  // ---------------------------------------------------------------------
  // Stock — feed & medicine
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _stockItems(String farmId) =>
      _farms.doc(farmId).collection('stockItems');

  /// Flat, farm-level movement log (`farms/{farmId}/stockMovements/{id}`).
  ///
  /// Movements used to live nested under each stock item
  /// (`stockItems/{itemId}/movements`) and were read back with a
  /// `collectionGroup('movements')` query filtered by farm *after* Firestore
  /// applied `limit()`. That silently dropped or missed this farm's most
  /// recent movements whenever any other farm also had `movements` docs, and
  /// needed a composite index this project never configured. A flat
  /// per-farm collection can be queried directly with a single `orderBy`,
  /// which Firestore indexes automatically — no composite index needed.
  CollectionReference<Map<String, dynamic>> _stockMovements(String farmId) =>
      _farms.doc(farmId).collection('stockMovements');

  Stream<List<StockItem>> stockItemsStream(String farmId, {StockType? type}) {
    Query<Map<String, dynamic>> q = _stockItems(farmId);
    if (type != null) {
      q = q.where('type', isEqualTo: type == StockType.medicine ? 'medicine' : 'feed');
    }
    return q.snapshots().map((s) => s.docs.map(StockItem.fromDoc).toList());
  }

  /// Adds stock (creates the item if it doesn't exist yet, matching on name
  /// + type so a feed item and a medicine item can share the same name) and
  /// logs the movement.
  Future<void> addStock(
      String farmId, {
        required String itemName,
        required StockType type,
        required double quantity,
        required String unit,
        double lowStockThreshold = 0,
        String notes = '',
      }) async {
    final typeStr = type == StockType.medicine ? 'medicine' : 'feed';
    final existing = await _stockItems(farmId)
        .where('name', isEqualTo: itemName)
        .where('type', isEqualTo: typeStr)
        .limit(1)
        .get()
        .timeout(timeout);

    String itemId;
    if (existing.docs.isEmpty) {
      final ref = await _stockItems(farmId).add(StockItem(
        id: '',
        name: itemName,
        type: type,
        quantity: quantity,
        unit: unit,
        lowStockThreshold: lowStockThreshold,
        lastUpdated: DateTime.now(),
      ).toMap()).timeout(timeout);
      itemId = ref.id;
    } else {
      itemId = existing.docs.first.id;
      final currentQty = (existing.docs.first.data()['quantity'] ?? 0).toDouble();
      await _stockItems(farmId).doc(itemId).update({
        'quantity': currentQty + quantity,
        // Keep the latest threshold/unit if the person changes them next
        // time they add stock for this item.
        'lowStockThreshold': lowStockThreshold,
        'unit': unit,
        'lastUpdated': FieldValue.serverTimestamp(),
      }).timeout(timeout);
    }

    await _stockMovements(farmId).add(StockMovement(
      id: '',
      stockItemId: itemId,
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      isAddition: true,
      date: DateTime.now(),
      notes: notes,
    ).toMap()).timeout(timeout);
  }

  /// Deducts stock used (e.g. "Feed Used Today" / "Medicine Used") and logs
  /// the movement. Runs as a transaction so concurrent usage entries can't
  /// race each other and corrupt the running quantity.
  Future<void> useStock(
      String farmId, {
        required String itemId,
        required String itemName,
        required double quantity,
        required String unit,
        String notes = '',
      }) async {
    await _db.runTransaction((txn) async {
      final ref = _stockItems(farmId).doc(itemId);
      final snap = await txn.get(ref);
      final currentQty = (snap.data()?['quantity'] ?? 0).toDouble();
      txn.update(ref, {
        'quantity': (currentQty - quantity).clamp(0, double.infinity),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }).timeout(timeout);

    await _stockMovements(farmId).add(StockMovement(
      id: '',
      stockItemId: itemId,
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      isAddition: false,
      date: DateTime.now(),
      notes: notes,
    ).toMap()).timeout(timeout);
  }

  /// Removes a stock item entirely (e.g. discontinued feed/medicine). Past
  /// movement history is kept for the activity log.
  Future<void> deleteStockItem(String farmId, String itemId) {
    return _stockItems(farmId).doc(itemId).delete().timeout(timeout);
  }

  Stream<List<StockMovement>> stockMovementsStream(String farmId, {int limit = 20}) {
    return _stockMovements(farmId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(StockMovement.fromDoc).toList());
  }

  // ---------------------------------------------------------------------
  // Profile — realtime farm doc, basic details, and photo storage
  // ---------------------------------------------------------------------

  /// Realtime farm document. Home (for the completion popup) and Profile
  /// both listen to this so a change on either screen shows up instantly
  /// on the other, with no manual refresh.
  Stream<FarmModel?> farmDocStream(String farmId) {
    return _farms.doc(farmId).snapshots().map((doc) => doc.exists ? FarmModel.fromDoc(doc) : null);
  }

  Future<void> updateFarmBasics(
      String farmId, {
        String? farmName,
        String? ownerName,
        String? address,
      }) async {
    final updates = <String, dynamic>{};
    if (farmName != null && farmName.trim().isNotEmpty) updates['farmName'] = farmName.trim();
    if (ownerName != null && ownerName.trim().isNotEmpty) updates['ownerName'] = ownerName.trim();
    if (address != null) updates['address'] = address.trim();
    if (updates.isEmpty) return;
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _farms.doc(farmId).update(updates).timeout(timeout);
  }

  /// Stores the already-compressed photo as raw bytes directly on the farm
  /// document, using Firestore's native `Blob` type — no Storage bucket,
  /// no public URL, just binary data scoped to this farm/owner. Retrieving
  /// it later (on any device, once signed in as the same user) is just a
  /// normal document read; see [farmDocStream] / [FarmModel.fromDoc].
  Future<void> updateProfileImage(String farmId, Uint8List bytes, String contentType) async {
    await _farms.doc(farmId).update({
      'profileImage': Blob(bytes),
      'profileImageContentType': contentType,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  Future<void> removeProfileImage(String farmId) async {
    await _farms.doc(farmId).update({
      'profileImage': FieldValue.delete(),
      'profileImageContentType': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  Future<void> updatePreferredLanguage(String farmId, String languageCode) async {
    await _farms.doc(farmId).update({
      'preferredLanguage': languageCode,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  /// Saves the customizable fields that get printed on the Palai
  /// check-out bill — see Profile > Bill Details.
  Future<void> updateBillSettings(String farmId, BillSettings settings) async {
    await _farms.doc(farmId).update({
      'billSettings': settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  // ---------------------------------------------------------------------
  // Partners
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _partners(String farmId) =>
      _farms.doc(farmId).collection('partners');


  // ---------------------------------------------------------------------
// Farm Partners
// ---------------------------------------------------------------------

  Stream<List<PartnerModel>> partnersStream(String farmId) {
    return _farms
        .doc(farmId)
        .collection('partners')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map((doc) => PartnerModel.fromDoc(doc))
          .toList(),
    );
  }

  Future<String> createPartner(
      String farmId, {
        required String name,
        required String mobileNumber,
        required String email,
        required String authUid,
      }) async {
    final partnerRef = _farms
        .doc(farmId)
        .collection('partners')
        .doc(authUid);

    await partnerRef.set({
      'name': name.trim(),
      'mobileNumber': mobileNumber.trim(),
      'email': email.trim(),
      'authUid': authUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);

    return partnerRef.id;
  }

  Future<void> deletePartner({
    required String farmId,
    required String partnerId,
  }) async {
    await _farms
        .doc(farmId)
        .collection('partners')
        .doc(partnerId)
        .delete();
  }

  /// Adds a partner. The document id is deliberately the partner's own
  /// Firebase Auth uid (created beforehand via [PartnerAuthService]) rather
  /// than an auto-id — this lets Firestore security rules grant a partner
  /// access with a simple `exists()` check instead of a query.
  Future<void> addPartner({
    required String farmId,
    required String name,
    required String mobileNumber,
    required String email,
    required String authUid,
  }) async {
    final ref = _farms
        .doc(farmId)
        .collection('partners')
        .doc(authUid);

    await ref.set({
      'name': name.trim(),
      'mobileNumber': mobileNumber.trim(),
      'email': email.trim(),
      'authUid': authUid,

      'role': 'partner',
      'status': 'pending',

      'permissions': PartnerPermissions.none().toMap(),

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> approvePartner({
    required String farmId,
    required String partnerId,
    required String adminUid,
    required PartnerPermissions permissions,
  }) async {
    await _farms
        .doc(farmId)
        .collection('partners')
        .doc(partnerId)
        .update({
      'status': 'active',
      'permissions': permissions.toMap(),
      'approvedBy': adminUid,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectPartner({
    required String farmId,
    required String partnerId,
  }) async {
    await _farms
        .doc(farmId)
        .collection('partners')
        .doc(partnerId)
        .update({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> disablePartner({
    required String farmId,
    required String partnerId,
  }) async {
    await _farms
        .doc(farmId)
        .collection('partners')
        .doc(partnerId)
        .update({
      'status': 'disabled',
      'disabledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> enablePartner({
    required String farmId,
    required String partnerId,
    required String adminUid,
    required PartnerPermissions permissions,
  }) async {
    await _farms
        .doc(farmId)
        .collection('partners')
        .doc(partnerId)
        .update({
      'status': 'active',
      'permissions': permissions.toMap(),
      'approvedBy': adminUid,
      'disabledAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePartnerPermissions({
    required String farmId,
    required String partnerId,
    required PartnerPermissions permissions,
  }) async {
    await _farms
        .doc(farmId)
        .collection('partners')
        .doc(partnerId)
        .update({
      'permissions': permissions.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  // ---------------------------------------------------------------------
  // Own Farm Palai — goats owned by the farm itself
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _ownFarmGoats(String farmId) =>
      _farms.doc(farmId).collection('ownFarmGoats');

  CollectionReference<Map<String, dynamic>> _growthRecords(String farmId, String goatId) =>
      _ownFarmGoats(farmId).doc(goatId).collection('growthRecords');

  CollectionReference<Map<String, dynamic>> _healthEvents(String farmId, String goatId) =>
      _ownFarmGoats(farmId).doc(goatId).collection('healthEvents');

  CollectionReference<Map<String, dynamic>> _breedingRecords(String farmId, String goatId) =>
      _ownFarmGoats(farmId).doc(goatId).collection('breedingRecords');

  /// Flat, farm-level expense log — mirrors the stockMovements pattern so
  /// "all expenses this month" can be queried with a single `orderBy`
  /// instead of a collectionGroup query across every goat.
  CollectionReference<Map<String, dynamic>> _ownFarmExpenses(String farmId) =>
      _farms.doc(farmId).collection('ownFarmExpenses');

  Future<String> addOwnFarmGoat(String farmId, OwnFarmGoat goat) async {
    final ref = await _ownFarmGoats(farmId).add(goat.toMap()).timeout(timeout);
    return ref.id;
  }

  Stream<List<OwnFarmGoat>> ownFarmGoatsStream(String farmId, {bool activeOnly = true}) {
    Query<Map<String, dynamic>> q = _ownFarmGoats(farmId);
    if (activeOnly) {
      q = q.where('isActive', isEqualTo: true);
    }
    return q
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(OwnFarmGoat.fromDoc).toList());
  }

  Future<OwnFarmGoat?> getOwnFarmGoat(String farmId, String goatId) async {
    final doc = await _ownFarmGoats(farmId).doc(goatId).get().timeout(timeout);
    if (!doc.exists) return null;
    return OwnFarmGoat.fromDoc(doc);
  }

  Future<void> updateOwnFarmGoat(String farmId, OwnFarmGoat goat) {
    return _ownFarmGoats(farmId).doc(goat.id).update(goat.toUpdateMap()).timeout(timeout);
  }

  Future<void> removeOwnFarmGoat(String farmId, String goatId) {
    // Soft-delete: keeps growth/health/breeding/expense history intact for
    // reporting even after a goat is sold or leaves the herd.
    return _ownFarmGoats(farmId).doc(goatId).update({'isActive': false}).timeout(timeout);
  }

  // -- Weight / growth tracking -------------------------------------------

  Future<void> addGrowthRecord(String farmId, String goatId, GrowthRecord record) async {
    await _growthRecords(farmId, goatId).add(record.toMap()).timeout(timeout);
    await _ownFarmGoats(farmId).doc(goatId).update({'currentWeight': record.weight}).timeout(timeout);
  }

  Stream<List<GrowthRecord>> growthRecordsStream(String farmId, String goatId) {
    return _growthRecords(farmId, goatId)
        .orderBy('recordedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(GrowthRecord.fromDoc).toList());
  }

  // -- Health, vaccination, hoof cutting, hair trimming --------------------

  Future<void> addHealthEvent(String farmId, String goatId, HealthEvent event) async {
    await _healthEvents(farmId, goatId).add(event.toMap()).timeout(timeout);
  }

  Stream<List<HealthEvent>> healthEventsStream(String farmId, String goatId) {
    return _healthEvents(farmId, goatId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(HealthEvent.fromDoc).toList());
  }

  /// All farm goats with a hoof-cutting (khud cutting) reminder due within
  /// [withinDays] days (default 45 — matches the 30/45-day khud cutting
  /// cadence) or already overdue. Reminders for other event types
  /// (vaccination, hair trimming) follow the same `nextDueDate` field and
  /// can reuse this same query with a different [type].
  Future<List<MapEntry<OwnFarmGoat, HealthEvent>>> upcomingHealthReminders(
      String farmId, {
        HealthEventType? type,
        int withinDays = 45,
      }) async {
    final goatsSnap = await _ownFarmGoats(farmId).where('isActive', isEqualTo: true).get().timeout(timeout);
    final cutoff = DateTime.now().add(Duration(days: withinDays));
    final results = <MapEntry<OwnFarmGoat, HealthEvent>>[];

    for (final goatDoc in goatsSnap.docs) {
      final goat = OwnFarmGoat.fromDoc(goatDoc);
      Query<Map<String, dynamic>> q = _healthEvents(farmId, goat.id).orderBy('date', descending: true);
      if (type != null) {
        q = q.where('type', isEqualTo: type.name);
      }
      final eventsSnap = await q.limit(5).get().timeout(timeout);
      for (final eventDoc in eventsSnap.docs) {
        final event = HealthEvent.fromDoc(eventDoc);
        if (event.nextDueDate != null && event.nextDueDate!.isBefore(cutoff)) {
          results.add(MapEntry(goat, event));
        }
      }
    }
    results.sort((a, b) => a.value.nextDueDate!.compareTo(b.value.nextDueDate!));
    return results;
  }

  // -- Breeding --------------------------------------------------------

  Future<void> addBreedingRecord(String farmId, String goatId, BreedingRecord record) async {
    await _breedingRecords(farmId, goatId).add(record.toMap()).timeout(timeout);
  }

  Stream<List<BreedingRecord>> breedingRecordsStream(String farmId, String goatId) {
    return _breedingRecords(farmId, goatId)
        .orderBy('matingDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(BreedingRecord.fromDoc).toList());
  }

  // -- Feed / health expense tracking --------------------------------------

  Future<void> addOwnFarmExpense(String farmId, OwnFarmExpense expense) async {
    await _ownFarmExpenses(farmId).add(expense.toMap()).timeout(timeout);
  }

  Stream<List<OwnFarmExpense>> ownFarmExpensesStream(String farmId, {String? goatId}) {
    Query<Map<String, dynamic>> q = _ownFarmExpenses(farmId).orderBy('date', descending: true);
    if (goatId != null) {
      q = q.where('goatId', isEqualTo: goatId);
    }
    return q.snapshots().map((s) => s.docs.map(OwnFarmExpense.fromDoc).toList());
  }

  Stream<double> ownFarmExpensesThisMonthStream(String farmId) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return _ownFarmExpenses(farmId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .snapshots()
        .map((s) => s.docs.fold<double>(0, (total, d) => total + ((d.data()['amount'] ?? 0) as num).toDouble()));
  }
}