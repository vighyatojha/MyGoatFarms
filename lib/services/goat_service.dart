import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goat_model.dart';
import '../models/lot_transfer_models.dart';
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

    /// Registers the goat directly into a non-default status (e.g. Own
    /// Palai) instead of Available. Used when a goat is being pulled out
    /// of a Purchase Lot straight into a Palai transfer (Step 6), so it
    /// never has to pass through Available first. Must be one of
    /// [Goat.statusValues]; null keeps the existing behaviour
    /// (Available).
    String? initialStatus,
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

    if (initialStatus != null && !Goat.statusValues.contains(initialStatus)) {
      throw ArgumentError(
        'Initial status must be one of ${Goat.statusValues}.',
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

        // A lot's farm goats can be promised to a customer (Booking /
        // Wait for Delivery). Those are still counted in pendingCount
        // (= farmQty) but must not be turned into individual goats.
        if (currentPurchase.isLot &&
            currentPurchase.farmAvailableQty <= 0) {
          throw StateError(
            'The goats left in ${currentPurchase.lotId} are reserved for '
                'a customer, so they cannot be registered.',
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
          initialStatus ?? Goat.statusAvailable,

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

        // Completion must be judged against the REGISTERABLE quantity
        // (survivors = totalGoats - mortality), not the original
        // totalGoats. pendingCount already tracks that (it's set from
        // survivingGoats in completeReceiving()/savePurchase() and
        // decremented once per registration here), so "no goats left to
        // register" is exactly newPendingCount <= 0. Comparing against
        // totalGoats directly meant a purchase with any mortality could
        // never reach 'Completed' — e.g. 10 goats, 2 dead, 8 survivors:
        // registering all 8 gives registeredCount == 8, and
        // 8 >= 10 is false forever.
        final justCompleted = newPendingCount <= 0;

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
  // LOT TRANSFERS (Step 6)
  // -----------------------------------------------------------------------
  //
  // Goats stay anonymous inside a Purchase Lot. They get an individual
  // record (G-0041 ...) only when they are transferred to Own Palai or to
  // a Customer Palai. A transfer only ever draws on goats physically at
  // the farm and not reserved for a customer (farmAvailableQty) — never
  // on supplier stock.
  //
  // The work is split in two so a bigger transaction can include it:
  //
  //   prepareLotTransferInTransaction  — READS only (lot + goat counter)
  //   writeLotTransferInTransaction    — WRITES only
  //
  // Firestore requires every read in a transaction to come before any
  // write, so a caller that also has its own reads (SalesService's
  // Customer Palai transfer) does: its reads -> prepare -> its writes ->
  // write. transferLotToOwnPalai below is the simple case with nothing
  // else in the transaction.

  /// READ phase of a lot transfer. Re-validates against the lot as it is
  /// right now, so a stale screen cannot over-transfer.
  Future<LotTransferPrep> prepareLotTransferInTransaction(
      Transaction transaction, {
        required String farmId,
        required String lotDocId,
        required List<LotTransferGoat> goats,
      }) async {
    if (goats.isEmpty) {
      throw ArgumentError('Enter how many goats to transfer.');
    }

    if (goats.length > LotTransferPlanner.maxGoatsPerTransfer) {
      throw ArgumentError(
        'Transfer at most ${LotTransferPlanner.maxGoatsPerTransfer} goats '
            'at a time.',
      );
    }

    for (var i = 0; i < goats.length; i++) {
      final problem = goats[i].validate();

      if (problem != null) {
        throw ArgumentError('Goat ${i + 1}: $problem');
      }
    }

    final lotSnap = await transaction.get(
      _tradingPurchases(farmId).doc(lotDocId),
    );

    if (!lotSnap.exists) {
      throw StateError('Lot $lotDocId was not found.');
    }

    final lot = TradingPurchase.fromDoc(lotSnap);

    final blocked = LotTransferPlanner.blockReason(lot, goats.length);

    if (blocked != null) {
      throw StateError(blocked);
    }

    final counterSnap = await transaction.get(_goatCounterDoc(farmId));

    final lastValue =
        (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;

    final ids = <String>[
      for (var i = 1; i <= goats.length; i++)
        'G-${(lastValue + i).toString().padLeft(4, '0')}',
    ];

    return LotTransferPrep(
      lot: lot,
      goatIds: ids,
      counterLastValue: lastValue,
      genderPlan: LotTransferPlanner.assignGenders(
        lot,
        goats.map((g) => g.gender).toList(),
      ),
    );
  }

  /// WRITE phase of a lot transfer. Creates one goat document per entry
  /// in [goats] with [status], moves them out of the lot
  /// (registeredCount +N; pendingCount, which mirrors farmQty, -N),
  /// advances the goat counter and lowers the dashboard's
  /// pendingRegistrations by N.
  ///
  /// It does NOT touch totalStock: goats going to Own Palai stay in
  /// stock, and the Customer Palai sale lowers it itself.
  ///
  /// [status] must be Own Palai or In Customer Palai. Pass [saleId] for a
  /// Customer Palai transfer so each goat links back to its sale.
  ///
  /// Returns the new goats in input order.
  List<Goat> writeLotTransferInTransaction(
      Transaction transaction, {
        required String farmId,
        required LotTransferPrep prep,
        required List<LotTransferGoat> goats,
        required String status,
        String? saleId,
      }) {
    if (status != Goat.statusOwnPalai &&
        status != Goat.statusInCustomerPalai) {
      throw ArgumentError(
        'A lot transfer must go to Own Palai or a Customer Palai.',
      );
    }

    if (goats.length != prep.goatIds.length) {
      throw StateError('Transfer details changed after they were checked.');
    }

    final lot = prep.lot;
    final count = goats.length;
    final now = DateTime.now();
    final created = <Goat>[];

    for (var i = 0; i < count; i++) {
      final spec = goats[i];

      final goat = Goat(
        id: prep.goatIds[i],
        breed: spec.breed.trim(),
        ageMonthsAtRecord: spec.ageMonths,
        ageRecordedAt: now,
        weight: spec.weight,
        height: spec.height,
        length: spec.length,
        color: spec.color.trim(),
        healthStatus: spec.healthStatus,
        gender: prep.genderPlan.genders[i],
        notes: spec.notes.trim(),
        purchaseId: lot.id,
        purchaseDate: lot.purchaseDate,
        currentStatus: status,
        saleId: saleId,
      );

      transaction.set(
        _goats(farmId).doc(goat.id),
        {
          ...goat.toMap(),
          'createdAt': FieldValue.serverTimestamp(),

          // The Own Palai list is ordered by this field, and Firestore
          // leaves documents without it out of an ordered query — so a
          // goat created straight into Own Palai must carry it, exactly
          // as moveToOwnPalai() stamps it.
          if (status == Goat.statusOwnPalai)
            'movedToOwnPalaiAt': FieldValue.serverTimestamp(),

          if (saleId != null) 'saleId': saleId,
        },
      );

      created.add(goat);
    }

    transaction.set(
      _goatCounterDoc(farmId),
      {'lastValue': prep.counterLastValue + count},
      SetOptions(merge: true),
    );

    final newRegistered = lot.registeredCount + count;

    // farmQty = receivedAliveQty - soldFromFarmQty - registeredCount, and
    // pendingCount mirrors it for lots (see TradingService.receiveLotBatch).
    final newPending =
        lot.receivedAliveQty - lot.soldFromFarmQty - newRegistered;

    final hasSplit = lot.maleGoats > 0 || lot.femaleGoats > 0;

    transaction.update(
      _tradingPurchases(farmId).doc(lot.id),
      {
        'registeredCount': newRegistered,
        'pendingCount': newPending < 0 ? 0 : newPending,
        if (hasSplit) ...{
          'maleRegistered': prep.genderPlan.maleRegisteredAfter,
          'femaleRegistered': prep.genderPlan.femaleRegisteredAfter,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    transaction.set(
      _summaryDoc(farmId),
      {'pendingRegistrations': FieldValue.increment(-count)},
      SetOptions(merge: true),
    );

    return created;
  }

  /// Transfers [goats] out of the lot into Own Palai: one individual goat
  /// record each, created directly with status Own Palai, in a single
  /// transaction. Either every goat is created and the lot updated, or
  /// nothing changes.
  Future<List<Goat>> transferLotToOwnPalai({
    required String farmId,
    required String lotDocId,
    required List<LotTransferGoat> goats,
  }) async {
    return _db.runTransaction<List<Goat>>(
          (transaction) async {
        final prep = await prepareLotTransferInTransaction(
          transaction,
          farmId: farmId,
          lotDocId: lotDocId,
          goats: goats,
        );

        return writeLotTransferInTransaction(
          transaction,
          farmId: farmId,
          prep: prep,
          goats: goats,
          status: Goat.statusOwnPalai,
        );
      },
    ).timeout(_timeout * 2);
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