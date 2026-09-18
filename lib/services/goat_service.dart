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

    if (color.trim().isEmpty) {
      throw ArgumentError(
        'Color is required.',
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

          color:
          color.trim(),

          healthStatus:
          healthStatus,

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

        transaction.update(
          purchaseRef,
          {
            'registeredCount':
            newRegisteredCount,

            'pendingCount':
            newPendingCount,

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
}