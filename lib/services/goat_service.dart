import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goat_model.dart';
import '../models/trading_goat_health_record.dart';
import '../models/trading_goat_weight_entry.dart';
import '../models/trading_purchase_model.dart';

/// Handles the Trading module's Goat Registration and Goat Stock.
///
/// Collection layout:
///
/// farms/{farmId}/tradingGoats/{goatId}
/// farms/{farmId}/tradingCounters/goatCounter
///
/// Goat age is stored as:
///
///   ageMonths
///   ageRecordedAt
///
/// The Goat model calculates the current age dynamically from those values.
class GoatService {
  GoatService._();

  static final GoatService instance =
  GoatService._();

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  static const Duration _timeout =
  Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _goats(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingGoats');
  }

  CollectionReference<Map<String, dynamic>> _weightHistory(
      String farmId,
      String goatId,
      ) {
    return _goats(farmId)
        .doc(goatId)
        .collection('weightHistory');
  }

  CollectionReference<Map<String, dynamic>> _healthRecords(
      String farmId,
      String goatId,
      ) {
    return _goats(farmId)
        .doc(goatId)
        .collection('healthRecords');
  }

  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingPurchases');
  }

  DocumentReference<Map<String, dynamic>> _summaryDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingSummary')
        .doc('dashboard');
  }

  DocumentReference<Map<String, dynamic>> _goatCounterDoc(
      String farmId,
      ) {
    return _farms()
        .doc(farmId)
        .collection('tradingCounters')
        .doc('goatCounter');
  }

  // -----------------------------------------------------------------------
  // SEQUENTIAL GOAT ID
  // -----------------------------------------------------------------------

  Future<String> nextGoatIdInTransaction(
      Transaction transaction,
      String farmId,
      ) async {
    final counterRef =
    _goatCounterDoc(farmId);

    final counterSnap =
    await transaction.get(counterRef);

    final lastValue =
        (counterSnap.data()?['lastValue']
        as num?)
            ?.toInt() ??
            0;

    final nextValue =
        lastValue + 1;

    transaction.set(
      counterRef,
      {
        'lastValue': nextValue,
      },
      SetOptions(
        merge: true,
      ),
    );

    return 'G-${nextValue.toString().padLeft(4, '0')}';
  }

  // -----------------------------------------------------------------------
  // GET GOAT
  // -----------------------------------------------------------------------

  Future<Goat?> getGoat(
      String farmId,
      String goatId,
      ) async {
    final doc = await _goats(farmId)
        .doc(goatId)
        .get()
        .timeout(_timeout);

    if (!doc.exists) {
      return null;
    }

    return Goat.fromDoc(doc);
  }

  // -----------------------------------------------------------------------
  // GOAT STOCK
  // -----------------------------------------------------------------------

  Stream<List<Goat>> goatsStream(
      String farmId,
      ) {
    return _goats(farmId)
        .orderBy(
      'createdAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snap) =>
          snap.docs.map(Goat.fromDoc).toList(),
    );
  }

  /// Number of registered goats whose status is exactly Available.
  ///
  /// Used by the Trading Dashboard's "Available Stock" card. This is NOT
  /// the same as TradingSummary.totalStock, which also counts received-
  /// but-unregistered goats and goats that are Booked / Wait on Delivery /
  /// in Own Palai.
  ///
  /// Uses a server-side count aggregate, so no goat documents (and none
  /// of their photo blobs) are downloaded. It is a one-shot read, not a
  /// live stream — callers re-run it when something may have changed.
  Future<int> availableGoatCount(
      String farmId,
      ) async {
    final snapshot = await _goats(farmId)
        .where(
      'currentStatus',
      isEqualTo: Goat.statusAvailable,
    )
        .count()
        .get()
        .timeout(_timeout);

    return snapshot.count ?? 0;
  }

  // -----------------------------------------------------------------------
  // OWN PALAI
  // -----------------------------------------------------------------------

  Stream<List<Goat>> ownPalaiGoatsStream(
      String farmId,
      ) {
    return _goats(farmId)
        .where(
      'currentStatus',
      isEqualTo: Goat.statusOwnPalai,
    )
        .orderBy(
      'movedToOwnPalaiAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snap) =>
          snap.docs.map(Goat.fromDoc).toList(),
    );
  }

  /// Goats currently in [Goat.statusWaitOnDelivery] that originated
  /// from Own Palai (Phase 5, Section 4 / Task 4.2).
  ///
  /// [Goat.movedToOwnPalaiAt] is stamped once, by [moveToOwnPalai], and
  /// nothing in the Sell Goat flow ever clears it when the goat is
  /// later sold — so it doubles as a reliable "did this goat pass
  /// through Own Palai" marker even after `currentStatus` has moved on
  /// to Wait on Delivery. `orderBy` on that field is what does the
  /// actual filtering: Firestore excludes documents missing the
  /// ordered-on field, so a Wait-on-Delivery goat that was sold
  /// straight from Stock (never Own Palai) is never included here.
  /// Same composite index as [ownPalaiGoatsStream] above covers this
  /// query too, since only the equality value on `currentStatus`
  /// differs.
  Stream<List<Goat>> ownPalaiWaitOnDeliveryGoatsStream(
      String farmId,
      ) {
    return _goats(farmId)
        .where(
      'currentStatus',
      isEqualTo: Goat.statusWaitOnDelivery,
    )
        .orderBy(
      'movedToOwnPalaiAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snap) =>
          snap.docs.map(Goat.fromDoc).toList(),
    );
  }

  // -----------------------------------------------------------------------
  // MOVE TO OWN PALAI
  // -----------------------------------------------------------------------

  Future<void> moveToOwnPalai({
    required String farmId,
    required String goatId,
  }) async {
    final ref =
    _goats(farmId).doc(goatId);

    await _db.runTransaction<void>(
          (transaction) async {
        final snap =
        await transaction.get(ref);

        if (!snap.exists) {
          throw StateError(
            'Goat $goatId was not found.',
          );
        }

        final goat =
        Goat.fromDoc(snap);

        if (!goat.isAvailable) {
          throw StateError(
            'Only goats with status '
                '"${Goat.statusAvailable}" '
                'can be moved to Own Palai '
                '(this goat is '
                '"${goat.currentStatus}").',
          );
        }

        transaction.update(
          ref,
          {
            'currentStatus':
            Goat.statusOwnPalai,
            'movedToOwnPalaiAt':
            FieldValue.serverTimestamp(),
          },
        );
      },
    ).timeout(_timeout);
  }

  // -----------------------------------------------------------------------
  // WEIGHT HISTORY
  // -----------------------------------------------------------------------

  Future<String> addWeightEntry({
    required String farmId,
    required String goatId,
    required GoatWeightEntry entry,
  }) async {
    final ref =
    await _weightHistory(
      farmId,
      goatId,
    )
        .add(
      {
        ...entry.toMap(),
        'createdAt':
        FieldValue.serverTimestamp(),
      },
    )
        .timeout(_timeout);

    return ref.id;
  }

  Stream<List<GoatWeightEntry>>
  weightHistoryStream({
    required String farmId,
    required String goatId,
  }) {
    return _weightHistory(
      farmId,
      goatId,
    )
        .orderBy(
      'date',
      descending: false,
    )
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
        GoatWeightEntry.fromDoc,
      )
          .toList(),
    );
  }

  // -----------------------------------------------------------------------
  // HEALTH RECORDS
  // -----------------------------------------------------------------------

  Future<String> addHealthRecord({
    required String farmId,
    required String goatId,
    required GoatHealthRecord record,
  }) async {
    final ref =
    await _healthRecords(
      farmId,
      goatId,
    )
        .add(
      {
        ...record.toMap(),
        'createdAt':
        FieldValue.serverTimestamp(),
      },
    )
        .timeout(_timeout);

    // Logging a real vaccination / hoof cutting / hair trimming fulfils the
    // farm-schedule reminder for that care type (see
    // FirestoreService.syncOwnPalaiFarmReminders): the new record now
    // carries the next due date, so the schedule record is switched off
    // rather than left as a second, competing due date. Best-effort — if
    // the goat has no schedule record yet there is simply nothing to
    // switch off, and a failure here must never fail the log itself.
    if (GoatHealthRecord.followsFarmSettings(record.type)) {
      try {
        await _healthRecords(farmId, goatId)
            .doc(GoatHealthRecord.farmScheduleId(record.type))
            .update({'nextDueDate': null}).timeout(_timeout);
      } catch (_) {
        // not-found (no schedule record) or transient — safe to ignore.
      }
    }

    return ref.id;
  }

  Stream<List<GoatHealthRecord>>
  healthRecordsStream({
    required String farmId,
    required String goatId,
  }) {
    return _healthRecords(
      farmId,
      goatId,
    )
        .orderBy(
      'date',
      descending: true,
    )
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
        GoatHealthRecord.fromDoc,
      )
          .toList(),
    );
  }

  // -----------------------------------------------------------------------
  // REGISTER GOAT
  // -----------------------------------------------------------------------

  /// Registers a single goat against a wholesale purchase.
  ///
  /// [ageMonths] is the age in complete months at the time of registration.
  ///
  /// [gender] is optional. Goat Registration no longer asks for it — the
  /// Male/Female split is captured once, in the lot, at purchase time (see
  /// TradingPurchase.maleGoats / femaleGoats). Leave [gender] null and this
  /// method works out each goat's gender itself, from however much of that
  /// split is still unassigned (TradingPurchase.maleRegistered /
  /// femaleRegistered), so the two always add back up to the purchase's
  /// totals. Pass [gender] explicitly only when a single, specific goat's
  /// gender is being recorded directly, outside of a lot split — e.g. the
  /// Individual Goat Purchase screen.
  ///
  /// Firestore stores:
  ///
  ///   ageMonths
  ///   ageRecordedAt
  ///
  /// The current age is then calculated by Goat.age.
  Future<Goat> registerGoat({
    required String farmId,
    required TradingPurchase purchase,
    required String breed,
    required int ageMonths,
    required double weight,
    required String color,
    required String healthStatus,
    String? gender,

    /// Height in cm. Optional — 0 means "not recorded".
    double height = 0,

    /// Body length in cm. Optional — 0 means "not recorded".
    double length = 0,
    String notes = '',
    Uint8List? photo,
    String? photoContentType,
  }) async {
    // -------------------------------------------------------------------
    // VALIDATION
    // -------------------------------------------------------------------

    if (breed.trim().isEmpty) {
      throw ArgumentError(
        'Breed is required.',
      );
    }

    if (ageMonths <= 0) {
      throw ArgumentError(
        'Age must be greater than zero months.',
      );
    }

    if (weight <= 0) {
      throw ArgumentError(
        'Weight must be greater than zero.',
      );
    }

    if (height < 0 || height > Goat.maxHeightCm) {
      throw ArgumentError(
        'Height must be between 0 and '
            '${Goat.maxHeightCm.toStringAsFixed(0)} cm.',
      );
    }

    if (length < 0 || length > Goat.maxLengthCm) {
      throw ArgumentError(
        'Length must be between 0 and '
            '${Goat.maxLengthCm.toStringAsFixed(0)} cm.',
      );
    }

    if (color.trim().isEmpty) {
      throw ArgumentError(
        'Color is required.',
      );
    }

    // A caller-supplied gender (Individual Goat Purchase) is validated
    // up front like every other field. When null (Goat Registration), the
    // gender is worked out per-goat inside the transaction below, from the
    // purchase's remaining Male/Female split, so it always sees the latest
    // counts.
    if (gender != null && !Goat.genderValues.contains(gender)) {
      throw ArgumentError(
        'Gender must be one of ${Goat.genderValues}.',
      );
    }

    // -------------------------------------------------------------------
    // REFERENCES
    // -------------------------------------------------------------------

    final purchaseRef =
    _tradingPurchases(
      farmId,
    ).doc(purchase.id);

    final summaryRef =
    _summaryDoc(farmId);

    // -------------------------------------------------------------------
    // TRANSACTION
    // -------------------------------------------------------------------

    final goat =
    await _db.runTransaction<Goat>(
          (transaction) async {
        // ---------------------------------------------------------------
        // READ PURCHASE
        // ---------------------------------------------------------------

        final purchaseSnap =
        await transaction.get(
          purchaseRef,
        );

        if (!purchaseSnap.exists) {
          throw StateError(
            'Purchase ${purchase.id} was not found.',
          );
        }

        final currentPurchase =
        TradingPurchase.fromDoc(
          purchaseSnap,
        );

        if (currentPurchase.pendingCount <= 0) {
          throw StateError(
            'This purchase has no goats left to register.',
          );
        }

        // ---------------------------------------------------------------
        // RESOLVE GENDER
        // ---------------------------------------------------------------
        //
        // Explicit gender (Individual Goat Purchase): use it as-is, and
        // don't touch the purchase's Male/Female counters — that flow
        // doesn't set maleGoats/femaleGoats in the first place.
        //
        // No explicit gender (Goat Registration): assign whichever of
        // Male/Female still has quota left in the purchase's split,
        // keeping pace with the overall ratio so one gender doesn't run
        // out long before the other. Purchases with no split recorded
        // (maleGoats == femaleGoats == 0, e.g. older purchases) register
        // with gender '', same as before this field existed.

        final resolvedGender =
            gender ??
                _resolveGenderFromSplit(
                  currentPurchase,
                );

        // ---------------------------------------------------------------
        // GENERATE GOAT ID
        // ---------------------------------------------------------------

        final goatId =
        await nextGoatIdInTransaction(
          transaction,
          farmId,
        );

        // ---------------------------------------------------------------
        // CREATE GOAT
        // ---------------------------------------------------------------

        final ageRecordedAt =
        DateTime.now();

        final goat = Goat(
          id: goatId,

          breed:
          breed.trim(),

          ageMonthsAtRecord:
          ageMonths,

          ageRecordedAt:
          ageRecordedAt,

          weight:
          weight,

          height:
          height,

          length:
          length,

          color:
          color.trim(),

          healthStatus:
          healthStatus,

          gender:
          resolvedGender,

          notes:
          notes.trim(),

          purchaseId:
          currentPurchase.id,

          purchaseDate:
          currentPurchase.purchaseDate,

          currentStatus:
          Goat.statusAvailable,

          photo:
          photo,

          photoContentType:
          photoContentType,
        );

        // ---------------------------------------------------------------
        // WRITE GOAT
        // ---------------------------------------------------------------

        transaction.set(
          _goats(farmId)
              .doc(goatId),
          {
            ...goat.toMap(),

            'createdAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------
        // UPDATE PURCHASE
        // ---------------------------------------------------------------

        final newRegisteredCount =
            currentPurchase
                .registeredCount +
                1;

        final newPendingCount =
            currentPurchase
                .pendingCount -
                1;

        final justCompleted =
            newRegisteredCount >=
                currentPurchase.totalGoats;

        // Only advance the gender counters when this goat's gender came
        // from the purchase's own split (gender was null going in) — an
        // explicit gender (Individual Goat Purchase) isn't drawn from
        // maleGoats/femaleGoats, so it must not decrement them.
        final usedSplit = gender == null;

        transaction.update(
          purchaseRef,
          {
            'registeredCount':
            newRegisteredCount,

            'pendingCount':
            newPendingCount,

            if (usedSplit && resolvedGender == Goat.genderValues[0])
              'maleRegistered':
              currentPurchase.maleRegistered + 1,

            if (usedSplit && resolvedGender == Goat.genderValues[1])
              'femaleRegistered':
              currentPurchase.femaleRegistered + 1,

            if (justCompleted)
              'registrationStatus':
              'Completed',

            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );

        // ---------------------------------------------------------------
        // UPDATE DASHBOARD SUMMARY
        // ---------------------------------------------------------------

        transaction.set(
          summaryRef,
          {
            'pendingRegistrations':
            FieldValue.increment(-1),
          },
          SetOptions(
            merge: true,
          ),
        );

        return goat;
      },
    ).timeout(_timeout);

    return goat;
  }

  // -----------------------------------------------------------------------
  // GENDER SPLIT
  // -----------------------------------------------------------------------

  /// Picks the next goat's gender from what's left of [purchase]'s
  /// Male/Female split (maleGoats/femaleGoats minus what's already been
  /// registered). See registerGoat()'s doc comment.
  String _resolveGenderFromSplit(
      TradingPurchase purchase,
      ) {
    // No split recorded on this purchase (0/0) — nothing to assign from.
    if (purchase.maleGoats <= 0 && purchase.femaleGoats <= 0) {
      return '';
    }

    final remainingMale =
        purchase.maleGoats - purchase.maleRegistered;

    final remainingFemale =
        purchase.femaleGoats - purchase.femaleRegistered;

    if (remainingMale <= 0) {
      return Goat.genderValues[1]; // Female
    }

    if (remainingFemale <= 0) {
      return Goat.genderValues[0]; // Male
    }

    // Both still have quota: assign whichever has the larger share of its
    // own total left, so registrations track the overall Male/Female
    // ratio instead of exhausting one gender before touching the other.
    final maleShareLeft =
        remainingMale / purchase.maleGoats;

    final femaleShareLeft =
        remainingFemale / purchase.femaleGoats;

    return maleShareLeft >= femaleShareLeft
        ? Goat.genderValues[0] // Male
        : Goat.genderValues[1]; // Female
  }
}