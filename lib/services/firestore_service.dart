import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/farm_model.dart';

/// All Firestore reads/writes for farm data go through here, so the
/// collection name, field names, and ID scheme are defined in exactly one
/// place instead of being retyped in every screen that touches `farms`.
class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;

  /// How long any single Firestore call is allowed to hang before we give
  /// up and surface an error instead of spinning forever.
  static const timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> get _farmsCol => _db.collection('farms');

  DocumentReference<Map<String, dynamic>> get _farmCounterDoc =>
      _db.collection('counters').doc('farms');

  // ── Lookups ──────────────────────────────────────────────────────────────

  /// True if a farm is already registered with this mobile number.
  Future<bool> isMobileNumberTaken(String mobileNumber) async {
    final query = await _farmsCol
        .where('mobileNumber', isEqualTo: mobileNumber)
        .limit(1)
        .get()
        .timeout(timeout);
    return query.docs.isNotEmpty;
  }

  /// Resolves the email linked to a mobile number, used for mobile-number
  /// login (Firebase Auth itself only signs in with email + password).
  Future<String?> findEmailByMobile(String mobileNumber) async {
    final query = await _farmsCol
        .where('mobileNumber', isEqualTo: mobileNumber)
        .limit(1)
        .get()
        .timeout(timeout);
    if (query.docs.isEmpty) return null;
    return query.docs.first.data()['email'] as String?;
  }

  /// Fetches the farm linked to a signed-in user's Auth UID.
  Future<FarmModel?> getFarmByAuthUid(String authUid) async {
    try {
      final query = await _farmsCol
          .where('authUid', isEqualTo: authUid)
          .limit(1)
          .get()
          .timeout(timeout);
      if (query.docs.isEmpty) return null;
      final doc = query.docs.first;
      return FarmModel.fromFirestore(doc.id, doc.data());
    } catch (e) {
      debugPrint('FirestoreService.getFarmByAuthUid error: $e');
      return null;
    }
  }

  // ── Farm ID generation ───────────────────────────────────────────────────

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

  // ── Writes ───────────────────────────────────────────────────────────────

  /// Creates a new farm document with a fresh sequential ID and returns it.
  Future<FarmModel> createFarm({
    required String authUid,
    required String farmName,
    required String ownerName,
    required String mobileNumber,
    required String email,
  }) async {
    final farmId = await _nextFarmId();

    final farm = FarmModel(
      farmId: farmId,
      authUid: authUid,
      farmName: farmName,
      ownerName: ownerName,
      mobileNumber: mobileNumber,
      email: email,
    );

    await _farmsCol.doc(farmId).set({
      ...farm.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);

    return farm;
  }

  // ── Error messages ───────────────────────────────────────────────────────

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
}