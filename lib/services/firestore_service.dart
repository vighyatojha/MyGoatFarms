import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/bill_settings_model.dart';
import '../models/farm_model.dart';
import '../models/palai_models.dart';
import '../models/stock_model.dart';
import '../models/activity_model.dart';
import '../models/partner_model.dart';

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

  Stream<List<PartnerModel>> partnersStream(String farmId) {
    return _partners(farmId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PartnerModel.fromDoc).toList());
  }

  /// Adds a partner. The document id is deliberately the partner's own
  /// Firebase Auth uid (created beforehand via [PartnerAuthService]) rather
  /// than an auto-id — this lets Firestore security rules grant a partner
  /// access with a simple `exists()` check instead of a query.
  Future<void> addPartner(
      String farmId, {
        required String name,
        required String mobileNumber,
        required String email,
        required String authUid,
      }) async {
    await _partners(farmId).doc(authUid).set({
      'name': name.trim(),
      'mobileNumber': mobileNumber.trim(),
      'email': email.trim(),
      'authUid': authUid,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  Future<void> deletePartner(String farmId, String partnerId) async {
    await _partners(farmId).doc(partnerId).delete().timeout(timeout);
  }
}