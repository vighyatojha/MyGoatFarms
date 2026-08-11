import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/farm_model.dart';
import '../models/palai_models.dart';
import '../models/stock_model.dart';
import '../models/activity_model.dart';

/// Single point of contact with Firestore for the whole app.
///
/// Data layout (per farm):
///   farms/{farmId}
///   farms/{farmId}/palaiCustomers/{customerId}
///   farms/{farmId}/palaiCustomers/{customerId}/goats/{goatId}
///   farms/{farmId}/palaiCustomers/{customerId}/goats/{goatId}/healthRecords/{entryId}
///   farms/{farmId}/stockItems/{itemId}
///   farms/{farmId}/stockItems/{itemId}/movements/{movementId}
///   farms/{farmId}/transactions/{txnId}      (income / expense, used for dashboard totals)
///   farms/{farmId}/activities/{activityId}   (shared recent-activity feed)
///   counters/farms                            (sequential farm-id counter)
///
/// Notifications are NOT stored in Firestore — see NotificationScreen.
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

  /// Resolves the email linked to a mobile number, used for mobile-number
  /// login (Firebase Auth itself only signs in with email + password).
  Future<String?> findEmailByMobile(String mobileNumber) async {
    final query = await _farms
        .where('mobileNumber', isEqualTo: mobileNumber)
        .limit(1)
        .get()
        .timeout(timeout);
    if (query.docs.isEmpty) return null;
    return query.docs.first.data()['email'] as String?;
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

  /// Convenience getter used by every module to resolve the current
  /// farm's document id before reading/writing sub-collections.
  Future<String?> currentFarmId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final farm = await getFarmByAuthUid(uid);
    return farm?.id;
  }

  // ---------------------------------------------------------------------
  // Farm — ID generation & creation
  // ---------------------------------------------------------------------

  /// Atomically hands out the next sequential farm ID (FRM1, FRM2, FRM3...).
  ///
  /// Deliberately NOT using runTransaction() here. On a brand-new, never-
  /// written-to Firestore database, transactions can intermittently throw
  /// `not-found` the first time they touch a document, even with a plain
  /// set() and even though the doc is being created, not read. Firestore's
  /// FieldValue.increment() is the built-in atomic-counter primitive: it
  /// needs no prior read, no transaction, and works fine even if the field
  /// (or the whole document) has never existed — so it sidesteps that bug
  /// completely while still being safe for concurrent registrations.
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
    await _farms.doc(farmId).collection('activities').add(activity.toMap());
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

  // ---------------------------------------------------------------------
  // Palai — customers
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _customers(String farmId) =>
      _farms.doc(farmId).collection('palaiCustomers');

  Future<String> addCustomer(String farmId, PalaiCustomer customer) async {
    final ref = await _customers(farmId).add(customer.toMap());
    return ref.id;
  }

  Stream<List<PalaiCustomer>> customersStream(String farmId) {
    return _customers(farmId)
        .orderBy('joiningDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PalaiCustomer.fromDoc).toList());
  }

  Future<void> updateCustomerPendingAmount(String farmId, String customerId, double newPending) {
    return _customers(farmId).doc(customerId).update({'pendingAmount': newPending});
  }

  // ---------------------------------------------------------------------
  // Palai — goats
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _goats(String farmId, String customerId) =>
      _customers(farmId).doc(customerId).collection('goats');

  /// All goats currently boarded in Palai, across every customer.
  Stream<List<PalaiGoat>> allActiveGoatsStream(String farmId) {
    return _db
        .collectionGroup('goats')
        .where('isCheckedOut', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs
        .where((d) => d.reference.path.startsWith('farms/$farmId/'))
        .map(PalaiGoat.fromDoc)
        .toList());
  }

  Stream<List<PalaiGoat>> goatsForCustomerStream(String farmId, String customerId) {
    return _goats(farmId, customerId)
        .orderBy('checkInDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PalaiGoat.fromDoc).toList());
  }

  Future<String> checkInGoat(String farmId, String customerId, PalaiGoat goat) async {
    final ref = await _goats(farmId, customerId).add(goat.toMap());
    return ref.id;
  }

  Future<void> checkOutGoat(
      String farmId,
      String customerId,
      String goatId, {
        required double finalWeight,
        required String healthStatus,
      }) {
    return _goats(farmId, customerId).doc(goatId).update({
      'isCheckedOut': true,
      'checkOutDate': FieldValue.serverTimestamp(),
      'currentWeight': finalWeight,
      'healthStatus': healthStatus,
    });
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
    await _goats(farmId, customerId).doc(goatId).update({'currentWeight': entry.weight});
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
  // Stock — feed & medicine
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _stockItems(String farmId) =>
      _farms.doc(farmId).collection('stockItems');

  Stream<List<StockItem>> stockItemsStream(String farmId, {StockType? type}) {
    Query<Map<String, dynamic>> q = _stockItems(farmId);
    if (type != null) {
      q = q.where('type', isEqualTo: type == StockType.medicine ? 'medicine' : 'feed');
    }
    return q.snapshots().map((s) => s.docs.map(StockItem.fromDoc).toList());
  }

  /// Adds stock (creates the item if it doesn't exist yet) and logs the movement.
  Future<void> addStock(
      String farmId, {
        required String itemName,
        required StockType type,
        required double quantity,
        required String unit,
        double lowStockThreshold = 0,
        String notes = '',
      }) async {
    final existing = await _stockItems(farmId).where('name', isEqualTo: itemName).limit(1).get();

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
      ).toMap());
      itemId = ref.id;
    } else {
      itemId = existing.docs.first.id;
      final currentQty = (existing.docs.first.data()['quantity'] ?? 0).toDouble();
      await _stockItems(farmId).doc(itemId).update({
        'quantity': currentQty + quantity,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    await _stockItems(farmId).doc(itemId).collection('movements').add(StockMovement(
      id: '',
      stockItemId: itemId,
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      isAddition: true,
      date: DateTime.now(),
      notes: notes,
    ).toMap());
  }

  /// Deducts stock used (e.g. "Feed Used Today") and logs the movement.
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
    });

    await _stockItems(farmId).doc(itemId).collection('movements').add(StockMovement(
      id: '',
      stockItemId: itemId,
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      isAddition: false,
      date: DateTime.now(),
      notes: notes,
    ).toMap());
  }

  Stream<List<StockMovement>> stockMovementsStream(String farmId, {int limit = 20}) {
    return _db
        .collectionGroup('movements')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
        .where((d) => d.reference.path.startsWith('farms/$farmId/'))
        .map(StockMovement.fromDoc)
        .toList());
  }
}