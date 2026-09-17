import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goat_model.dart';
import '../models/trading_goat_health_record.dart';
import '../models/trading_goat_weight_entry.dart';
import '../models/trading_purchase_model.dart';

/// Handles the Trading module's Goat Registration (Feature 3) and Goat
/// Stock (Feature 4).
///
/// Collection layout:
///
/// farms/{farmId}/tradingGoats/{goatId}
/// farms/{farmId}/tradingCounters/goatCounter
///
/// Deliberately named `tradingGoats`, not `goats`: Palai's boarded-goat
/// records already live at `customers/{customerId}/goats/{goatId}` and
/// are queried farm-wide via `collectionGroup('goats')` in
/// FirestoreService (allActiveGoatsStream, dueHealthReminderGoatsStream,
/// upcomingCustomerHealthReminders, allCustomerHealthRecordSummaries).
/// A collection group query matches by collection ID regardless of
/// parent path, so a `farms/{farmId}/goats` collection would silently
/// join that same group. Today those queries also filter on `farmId`
/// and `isCheckedOut` — fields Trading goat docs never set — so they
/// wouldn't currently match, but that's relying on every future query
/// against `goats` remembering to add the same filters. Using a
/// distinct collection name removes the landmine entirely, and matches
/// this module's existing `trading*` naming (tradingPurchases,
/// tradingCounters, tradingSummary).
///
/// This mirrors TradingService's layout exactly — including reusing the
/// same `tradingCounters` collection that already holds
/// `purchaseCounter`, rather than introducing a separate top-level
/// `counters` collection, since every other Trading counter already
/// lives under `farms/{farmId}/tradingCounters`.
///
/// Goat IDs are sequential and zero-padded to 4 digits (G-0001, G-0002,
/// ...), matching the PUR-0001 style already used for purchase IDs.
///
/// IMPORTANT: registration is the only place a goat ID is ever created.
/// Nothing in later phases (Own Palai, Sale) should ever generate a new
/// goat ID when moving an existing goat between statuses — see the
/// "No duplicate Goat IDs" note in the phase 2 plan.
class GoatService {
  GoatService._();

  static final GoatService instance = GoatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _goats(String farmId) {
    return _farms().doc(farmId).collection('tradingGoats');
  }

  /// farms/{farmId}/tradingGoats/{goatId}/weightHistory (Task 1.2).
  CollectionReference<Map<String, dynamic>> _weightHistory(
      String farmId,
      String goatId,
      ) {
    return _goats(farmId).doc(goatId).collection('weightHistory');
  }

  /// farms/{farmId}/tradingGoats/{goatId}/healthRecords (Task 1.2).
  CollectionReference<Map<String, dynamic>> _healthRecords(
      String farmId,
      String goatId,
      ) {
    return _goats(farmId).doc(goatId).collection('healthRecords');
  }

  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) {
    return _farms().doc(farmId).collection('tradingPurchases');
  }

  DocumentReference<Map<String, dynamic>> _summaryDoc(String farmId) {
    return _farms().doc(farmId).collection('tradingSummary').doc(
      'dashboard',
    );
  }

  DocumentReference<Map<String, dynamic>> _goatCounterDoc(String farmId) {
    return _farms().doc(farmId).collection('tradingCounters').doc(
      'goatCounter',
    );
  }

  // -----------------------------------------------------------------------
  // SEQUENTIAL GOAT ID
  // -----------------------------------------------------------------------

  /// Reads and increments `tradingCounters/goatCounter` inside an
  /// already-open [transaction], returning the next goat ID (e.g.
  /// "G-0001"). Called from within registerGoat()'s transaction — see
  /// that method's doc comment for why it must stay in the same
  /// transaction as the goat write and purchase count update.
  Future<String> nextGoatIdInTransaction(
      Transaction transaction,
      String farmId,
      ) async {
    final counterRef = _goatCounterDoc(farmId);

    final counterSnap = await transaction.get(counterRef);

    final lastValue =
        (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;

    final nextValue = lastValue + 1;

    transaction.set(
      counterRef,
      {'lastValue': nextValue},
      SetOptions(merge: true),
    );

    return 'G-${nextValue.toString().padLeft(4, '0')}';
  }

  // -----------------------------------------------------------------------
  // GET GOAT
  // -----------------------------------------------------------------------

  Future<Goat?> getGoat(String farmId, String goatId) async {
    final doc = await _goats(farmId).doc(goatId).get().timeout(_timeout);

    if (!doc.exists) {
      return null;
    }

    return Goat.fromDoc(doc);
  }

  /// All trading goats for [farmId], newest first. Used by Task 2.1's
  /// "Move to Own Palai" goat picker (filtered to Available goats by
  /// the caller) and can double as the Goat Stock list's data source
  /// once that Phase 2 screen exists.
  Stream<List<Goat>> goatsStream(String farmId) {
    return _goats(farmId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Goat.fromDoc).toList());
  }

  /// Own Palai goats only (Task 2.2's list screen), newest-moved first.
  Stream<List<Goat>> ownPalaiGoatsStream(String farmId) {
    return _goats(farmId)
        .where('currentStatus', isEqualTo: Goat.statusOwnPalai)
        .orderBy('movedToOwnPalaiAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Goat.fromDoc).toList());
  }

  // -----------------------------------------------------------------------
  // MOVE TO OWN PALAI (Task 2.1, Feature 5)
  // -----------------------------------------------------------------------

  /// Moves an existing goat into Own Palai by updating its
  /// `currentStatus` and `movedToOwnPalaiAt` fields in place.
  ///
  /// Deliberately just an update on `tradingGoats/{goatId}` — no new
  /// document, no new goat ID. See the "No duplicate Goat IDs" note on
  /// this class and in the phase 3 plan (Section 5): this is exactly
  /// the operation that note warns against getting wrong.
  ///
  /// Only goats currently [Goat.statusAvailable] can be moved — a goat
  /// that's Sold, Booked, or already in Own Palai/Customer Palai isn't
  /// a valid source state, so this throws rather than silently
  /// overwriting a status transition that doesn't make sense.
  Future<void> moveToOwnPalai({
    required String farmId,
    required String goatId,
  }) async {
    final ref = _goats(farmId).doc(goatId);

    await _db.runTransaction<void>((transaction) async {
      final snap = await transaction.get(ref);

      if (!snap.exists) {
        throw StateError('Goat $goatId was not found.');
      }

      final goat = Goat.fromDoc(snap);

      if (!goat.isAvailable) {
        throw StateError(
          'Only goats with status "${Goat.statusAvailable}" can be '
              'moved to Own Palai (this goat is "${goat.currentStatus}").',
        );
      }

      transaction.update(ref, {
        'currentStatus': Goat.statusOwnPalai,
        'movedToOwnPalaiAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_timeout);
  }

  // -----------------------------------------------------------------------
  // WEIGHT HISTORY (Task 1.2 / 3.2 — Growth Tracking)
  // -----------------------------------------------------------------------

  /// Logs one weight-check entry (+ optional monthly photo). Task 3.2's
  /// "log a new weight entry" form writes here; nothing else on the
  /// `tradingGoats/{goatId}` doc changes.
  Future<String> addWeightEntry({
    required String farmId,
    required String goatId,
    required GoatWeightEntry entry,
  }) async {
    final ref = await _weightHistory(farmId, goatId)
        .add({
      ...entry.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    })
        .timeout(_timeout);

    return ref.id;
  }

  /// Oldest-first, so the Growth Tracking chart/gain calculation can
  /// walk the list in chronological order without re-sorting.
  Stream<List<GoatWeightEntry>> weightHistoryStream({
    required String farmId,
    required String goatId,
  }) {
    return _weightHistory(farmId, goatId)
        .orderBy('date', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(GoatWeightEntry.fromDoc).toList());
  }

  // -----------------------------------------------------------------------
  // HEALTH RECORDS (Task 1.2 / 3.3 — Health Tracking)
  // -----------------------------------------------------------------------

  /// Logs one health entry — vaccination, hoof cutting, hair trimming,
  /// or medicine, per [GoatHealthRecord.type]. Task 3.3's "log a new
  /// entry per type" form writes here.
  Future<String> addHealthRecord({
    required String farmId,
    required String goatId,
    required GoatHealthRecord record,
  }) async {
    final ref = await _healthRecords(farmId, goatId)
        .add({
      ...record.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    })
        .timeout(_timeout);

    return ref.id;
  }

  /// All health records for one goat, newest first. Deliberately not
  /// filtered by type server-side (that would need a composite index
  /// per type) — Task 3.3's four sections filter this single stream by
  /// [GoatHealthRecord.type] client-side instead, matching the plan's
  /// "all in one place" design for this subcollection.
  Stream<List<GoatHealthRecord>> healthRecordsStream({
    required String farmId,
    required String goatId,
  }) {
    return _healthRecords(farmId, goatId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(GoatHealthRecord.fromDoc).toList());
  }

  // -----------------------------------------------------------------------
  // REGISTER GOAT (Task 2.4)
  // -----------------------------------------------------------------------

  /// Registers a single goat against [purchase] (Feature 3).
  ///
  /// Everything happens in ONE Firestore transaction, per the phase 2
  /// plan's explicit requirement:
  ///
  /// 1. Generate the next goat ID (tradingCounters/goatCounter).
  /// 2. Write the tradingGoats/{goatId} doc — currentStatus: Available.
  /// 3. Increment the purchase's registeredCount / decrement
  ///    pendingCount.
  /// 4. If that reaches totalGoats, mark the purchase
  ///    registrationStatus: 'Completed'.
  /// 5. Decrement the dashboard summary's `pendingRegistrations` (see
  ///    note below).
  ///
  /// Doing all five in the same transaction is what the plan's "must
  /// stay in sync" note is about — a dropped connection mid-way can
  /// never leave the counter, the purchase's counts, and the goats that
  /// actually exist out of sync with each other.
  ///
  /// The purchase is RE-READ inside the transaction (not trusted from
  /// [purchase], which the caller may be holding onto across multiple
  /// saves in the registration loop) so two concurrent registrations
  /// against the same purchase — e.g. two devices — can't both push
  /// pendingCount below zero.
  ///
  /// Also decrements `tradingSummary/dashboard`'s `pendingRegistrations`
  /// by 1. That field has existed since Phase 1 but — per the comment
  /// on TradingService.backfillDashboardSummary — nothing ever
  /// decremented it, because no registration flow existed yet. This is
  /// that flow, so it closes that gap. `totalStock` is deliberately
  /// left untouched here: it represents on-farm surviving goats
  /// (received, mortality already subtracted), which doesn't change
  /// just because a goat that was already on the farm gets individually
  /// registered.
  Future<Goat> registerGoat({
    required String farmId,
    required TradingPurchase purchase,
    required String breed,
    required String age,
    required double weight,
    required String color,
    required String healthStatus,
    String notes = '',
    Uint8List? photo,
    String? photoContentType,
  }) async {
    if (breed.trim().isEmpty) {
      throw ArgumentError('Breed is required.');
    }

    if (age.trim().isEmpty) {
      throw ArgumentError('Age is required.');
    }

    if (weight <= 0) {
      throw ArgumentError('Weight must be greater than zero.');
    }

    if (color.trim().isEmpty) {
      throw ArgumentError('Color is required.');
    }

    final purchaseRef = _tradingPurchases(farmId).doc(purchase.id);
    final summaryRef = _summaryDoc(farmId);

    final goat = await _db.runTransaction<Goat>(
          (transaction) async {
        // ---------------------------------------------------------------
        // READS (all reads must happen before any writes in a Firestore
        // transaction, so both gets below come before anything is set).
        // ---------------------------------------------------------------

        final purchaseSnap = await transaction.get(purchaseRef);

        if (!purchaseSnap.exists) {
          throw StateError('Purchase ${purchase.id} was not found.');
        }

        final currentPurchase = TradingPurchase.fromDoc(purchaseSnap);

        if (currentPurchase.pendingCount <= 0) {
          throw StateError(
            'This purchase has no goats left to register.',
          );
        }

        final goatId = await nextGoatIdInTransaction(transaction, farmId);

        // ---------------------------------------------------------------
        // WRITES
        // ---------------------------------------------------------------

        final goat = Goat(
          id: goatId,
          breed: breed.trim(),
          age: age.trim(),
          weight: weight,
          color: color.trim(),
          healthStatus: healthStatus,
          notes: notes.trim(),
          purchaseId: currentPurchase.id,
          purchaseDate: currentPurchase.purchaseDate,
          currentStatus: Goat.statusAvailable,
          photo: photo,
          photoContentType: photoContentType,
        );

        transaction.set(
          _goats(farmId).doc(goatId),
          {
            ...goat.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
          },
        );

        final newRegisteredCount = currentPurchase.registeredCount + 1;
        final newPendingCount = currentPurchase.pendingCount - 1;
        final justCompleted = newRegisteredCount >= currentPurchase.totalGoats;

        transaction.update(
          purchaseRef,
          {
            'registeredCount': newRegisteredCount,
            'pendingCount': newPendingCount,
            if (justCompleted) 'registrationStatus': 'Completed',
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );

        transaction.set(
          summaryRef,
          {
            'pendingRegistrations': FieldValue.increment(-1),
          },
          SetOptions(merge: true),
        );

        return goat;
      },
    ).timeout(_timeout);

    return goat;
  }
}