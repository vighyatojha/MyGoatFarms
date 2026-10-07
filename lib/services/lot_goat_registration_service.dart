import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goat_model.dart';
import '../models/lot_transfer_models.dart';
import '../models/purchase_costing.dart';
import '../models/sale_model.dart';
import '../models/trading_lot_receiving_model.dart';
import '../models/trading_purchase_model.dart';
import 'firestore_service.dart';
import 'health_reminder_scheduler.dart';

/// One goat's details, entered on the Register Goats screen before it is
/// sold / booked: what the customer and the farm use to identify it.
class SaleGoatSpec {
  final String breed;
  final int ageMonths;
  final double weight;
  final String color;
  final String healthStatus;
  final String notes;
  final Uint8List? photo;
  final String? photoContentType;

  const SaleGoatSpec({
    required this.breed,
    required this.ageMonths,
    required this.weight,
    required this.color,
    required this.healthStatus,
    this.notes = '',
    this.photo,
    this.photoContentType,
  });

  /// First problem with these details, or null. Same rules as Goat
  /// Registration ([LotTransferGoat.validate]); a photo is required so the
  /// goat can be recognised at delivery.
  String? validate() {
    final problem = LotTransferGoat(
      breed: breed,
      ageMonths: ageMonths,
      weight: weight,
      color: color.trim().isEmpty ? '-' : color,
      healthStatus: healthStatus,
    ).validate();

    if (problem != null) return problem;
    if (!Goat.healthStatusValues.contains(healthStatus)) {
      return 'Choose a health status.';
    }
    if (photo == null || photo!.isEmpty) return 'Add a photo.';
    return null;
  }
}

/// A photo uploaded for a goat of a lot booking while the goats are still
/// at the supplier (they cannot be weighed or registered yet). Stored at
/// farms/{farmId}/saleGoatPhotos/{photoId} with the booking's `saleId` —
/// a first-level farm collection, which the farm's security rules already
/// allow (a sub-collection under a sale would need a rules change).
class SaleGoatPhoto {
  final String id;
  final Uint8List bytes;
  final String contentType;
  final String note;
  final DateTime? createdAt;

  const SaleGoatPhoto({
    required this.id,
    required this.bytes,
    required this.contentType,
    this.note = '',
    this.createdAt,
  });

  factory SaleGoatPhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final blob = data['photo'];
    final created = data['createdAt'];
    return SaleGoatPhoto(
      id: doc.id,
      bytes: blob is Blob ? blob.bytes : Uint8List(0),
      contentType: (data['photoContentType'] ?? 'image/jpeg').toString(),
      note: (data['note'] ?? '').toString(),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

/// Gives goats sold out of a Purchase Lot an individual identity
/// (G-0041 …) so every sold / booked goat has its own photo, weight,
/// breed, age and profile.
///
/// The lot maths never changes meaning — this only uses moves the lot
/// already knows:
///   * registering moves goats out of the lot into goat records
///     (`registeredCount` +N; `pendingCount`, which mirrors farmQty, −N;
///     dashboard `pendingRegistrations` −N) — exactly like Goat
///     Registration and the Palai transfers;
///   * a lot booking that is converted gives back its reservation
///     (`reservedFarmQty` / `reservedSupplierQty` −N) because the goats
///     now exist as Booked / Wait-on-Delivery goat records instead;
///   * goats held at the supplier are first received at the farm (one
///     receiving event, same maths as Receive Lot), then registered.
///
/// After a conversion the sale is an ordinary individual-goat sale: the
/// existing delivery, payment, receipt and profit code handles it, and the
/// cost per goat it snapshotted at booking time is kept, so profit is
/// unchanged. Its lot is kept in `originLotId` for display.
///
/// Every method runs in ONE Firestore transaction: either every goat is
/// created and every counter moved, or nothing changes.
class LotGoatRegistrationService {
  LotGoatRegistrationService._();

  static final LotGoatRegistrationService instance =
  LotGoatRegistrationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 30);

  /// Most goats per call. Each goat is one document WITH its photo (up to
  /// ImageService.goatPhotoMaxStoredBytes, 350 KB) in a single transaction,
  /// and a Firestore commit is limited to about 10 MB — 20 goats keeps
  /// well inside that.
  static const int maxGoatsPerCall = 20;

  DocumentReference<Map<String, dynamic>> _farm(String farmId) =>
      _db.collection('farms').doc(farmId);

  DocumentReference<Map<String, dynamic>> _lotRef(String farmId, String id) =>
      _farm(farmId).collection('tradingPurchases').doc(id);

  DocumentReference<Map<String, dynamic>> _saleRef(String farmId, String id) =>
      _farm(farmId).collection('sales').doc(id);

  DocumentReference<Map<String, dynamic>> _goatRef(String farmId, String id) =>
      _farm(farmId).collection('tradingGoats').doc(id);

  DocumentReference<Map<String, dynamic>> _goatCounter(String farmId) =>
      _farm(farmId).collection('tradingCounters').doc('goatCounter');

  DocumentReference<Map<String, dynamic>> _summary(String farmId) =>
      _farm(farmId).collection('tradingSummary').doc('dashboard');

  CollectionReference<Map<String, dynamic>> _photos(String farmId) =>
      _farm(farmId).collection('saleGoatPhotos');

  void _check(List<SaleGoatSpec> goats) {
    if (goats.isEmpty) throw ArgumentError('Add at least one goat.');
    if (goats.length > maxGoatsPerCall) {
      throw ArgumentError(
        'Register at most $maxGoatsPerCall goats at a time.',
      );
    }
    for (var i = 0; i < goats.length; i++) {
      final problem = goats[i].validate();
      if (problem != null) throw ArgumentError('Goat ${i + 1}: $problem');
    }
  }

  // ===========================================================================
  // 1. SELL FROM LOT (farm): register first, then sell as goats
  // ===========================================================================

  /// Registers [goats] out of lot [lotDocId] as Available goats, ready to be
  /// sold with the normal Sell Goat flow. Only free goats at the farm
  /// (`farmAvailableQty`) can be registered. Returns the new goats in input
  /// order.
  Future<List<Goat>> registerForSale({
    required String farmId,
    required String lotDocId,
    required List<SaleGoatSpec> goats,
  }) async {
    _check(goats);

    return _db.runTransaction<List<Goat>>((transaction) async {
      // ---- reads ----------------------------------------------------------
      final lotSnap = await transaction.get(_lotRef(farmId, lotDocId));
      if (!lotSnap.exists) throw StateError('Lot $lotDocId was not found.');

      final lot = TradingPurchase.fromDoc(lotSnap);
      if (!lot.isLot) {
        throw StateError('${lot.lotId} has not been converted to a lot yet.');
      }
      if (goats.length > lot.farmAvailableQty) {
        throw StateError(
          'Only ${lot.farmAvailableQty} goats of ${lot.lotId} are free at '
              'the farm (goats already booked are not counted).',
        );
      }

      final counterSnap = await transaction.get(_goatCounter(farmId));
      final lastValue =
          (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;

      // ---- writes ---------------------------------------------------------
      final created = _writeGoats(
        transaction,
        farmId: farmId,
        lot: lot,
        goats: goats,
        firstNumber: lastValue + 1,
        status: Goat.statusAvailable,
      );

      transaction.update(_lotRef(farmId, lot.id), {
        ..._moveOutOfLotFields(
          lot: lot,
          count: goats.length,
          genders: created.map((g) => g.gender).toList(),
          receivedAliveAfter: lot.receivedAliveQty,
        ),
      });

      transaction.set(
        _summary(farmId),
        {'pendingRegistrations': FieldValue.increment(-goats.length)},
        SetOptions(merge: true),
      );

      return created;
    }).timeout(_timeout);
  }

  // ===========================================================================
  // 2. EXISTING LOT BOOKING → registered goats
  // ===========================================================================

  /// Turns an open lot Booking / Wait-for-Delivery sale into an individual-
  /// goat sale. [goats] must hold one entry per goat of the booking
  /// (`sale.lotQuantity`).
  ///
  /// Goats booked at the farm are registered straight away. Goats booked at
  /// the supplier must have arrived: they are received at the farm in the
  /// same transaction ([arrivalDate], arrival weight = the weights entered),
  /// then registered.
  Future<List<Goat>> convertLotBooking({
    required String farmId,
    required String saleId,
    required List<SaleGoatSpec> goats,
    DateTime? arrivalDate,
  }) async {
    _check(goats);

    final actor = await FirestoreService.instance.getCurrentActor();

    final created = await _db.runTransaction<List<Goat>>((transaction) async {
      // ---- reads ----------------------------------------------------------
      final saleSnap = await transaction.get(_saleRef(farmId, saleId));
      if (!saleSnap.exists) throw StateError('Booking $saleId was not found.');

      final sale = Sale.fromDoc(saleSnap);

      final open = (sale.isWaitForDelivery &&
          sale.status == Sale.statusWaitForDelivery) ||
          (sale.isBooking && sale.status == Sale.statusBooked);

      if (!open) {
        throw StateError(
          'Booking $saleId is no longer open (it may already be delivered '
              'or cancelled).',
        );
      }
      if (!sale.isLotSale) {
        throw StateError('Booking $saleId already has registered goats.');
      }
      if (goats.length != sale.lotQuantity) {
        throw StateError(
          'Booking $saleId holds ${sale.lotQuantity} goats — enter the '
              'details of every one.',
        );
      }

      final lotRef = _lotRef(farmId, sale.lotDocId);
      final lotSnap = await transaction.get(lotRef);
      if (!lotSnap.exists) {
        throw StateError('Lot ${sale.lotDocId} was not found.');
      }

      final lot = TradingPurchase.fromDoc(lotSnap);
      final atSupplier = sale.sourceLocation == Sale.sourceSupplier;
      final count = goats.length;

      final reserved =
      atSupplier ? lot.reservedSupplierQty : lot.reservedFarmQty;
      if (reserved < count) {
        throw StateError(
          '${lot.lotId} has only $reserved goats reserved '
              '${atSupplier ? 'at the supplier' : 'at the farm'} but this '
              'booking holds $count. Please check the lot first.',
        );
      }

      final counterSnap = await transaction.get(_goatCounter(farmId));
      final lastValue =
          (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;

      // Supplier goats arrive now: same checks as Receive Lot.
      final arrivalWeight = PurchaseCosting.round2(
        goats.fold<double>(0, (sum, g) => sum + g.weight),
      );
      final newArrivalWeight = PurchaseCosting.round2(
        (lot.totalWeightAfterArrival ?? 0) + arrivalWeight,
      );

      if (atSupplier && newArrivalWeight > lot.totalWeightAtPurchase + 0.005) {
        throw StateError(
          'The weights entered would make ${lot.lotId}\'s total arrival '
              'weight more than its purchase weight '
              '(${lot.totalWeightAtPurchase.toStringAsFixed(2)} kg). '
              'Check the weights.',
        );
      }

      // ---- writes ---------------------------------------------------------
      final waiting = sale.isWaitForDelivery;

      final newGoats = _writeGoats(
        transaction,
        farmId: farmId,
        lot: lot,
        goats: goats,
        firstNumber: lastValue + 1,
        status: waiting ? Goat.statusWaitOnDelivery : Goat.statusBooked,
        saleId: saleId,
      );

      final lotUpdate = <String, dynamic>{};
      var receivedAliveAfter = lot.receivedAliveQty;

      if (atSupplier) {
        receivedAliveAfter = lot.receivedAliveQty + count;
        lotUpdate.addAll(
          _receiveReservedSupplierGoatsFields(
            transaction,
            lotRef: lotRef,
            lot: lot,
            count: count,
            arrivalWeight: arrivalWeight,
            newArrivalWeight: newArrivalWeight,
            date: arrivalDate ?? DateTime.now(),
            saleId: saleId,
            actorUid: actor?.uid,
            actorName: actor?.name,
          ),
        );
      } else {
        lotUpdate['reservedFarmQty'] = FieldValue.increment(-count);
      }

      lotUpdate.addAll(
        _moveOutOfLotFields(
          lot: lot,
          count: count,
          genders: newGoats.map((g) => g.gender).toList(),
          receivedAliveAfter: receivedAliveAfter,
        ),
      );

      transaction.update(lotRef, lotUpdate);

      // Supplier goats arrive alive (stock +N, waiting for registration +N)
      // and are registered at once (waiting for registration −N). Farm
      // goats were already in stock, so only registration moves.
      transaction.set(
        _summary(farmId),
        {
          if (atSupplier) 'totalStock': FieldValue.increment(count),
          if (!atSupplier) 'pendingRegistrations': FieldValue.increment(-count),
        },
        SetOptions(merge: true),
      );

      // The sale becomes an individual-goat sale. Everything about its
      // money (price, booking amount / advance, discount, cost per goat
      // snapshot) stays exactly as it was.
      transaction.update(_saleRef(farmId, saleId), {
        'goatIds': newGoats.map((g) => g.id).toList(),
        'lotId': FieldValue.delete(),
        'lotQuantity': FieldValue.delete(),
        'originLotId': lot.id,
        'originSourceLocation': sale.sourceLocation,
        'registeredFromLotAt': FieldValue.serverTimestamp(),
      });

      return newGoats;
    }).timeout(_timeout);

    // The uploaded supplier photos are now on the goats themselves, so the
    // booking's upload copies are removed. Best effort: a failure here
    // only leaves unused photos behind.
    unawaited(_deleteUploadedPhotos(farmId, saleId));

    // Waiting goats stay on the farm and follow the farm's Health Reminder
    // Settings, like goats booked the normal way. Never throws.
    for (final goat in created) {
      if (goat.isWaitOnDelivery) {
        unawaited(
          HealthReminderScheduler.instance.syncOwnPalaiFarmReminders(
            farmId,
            goatId: goat.id,
            force: true,
          ),
        );
      }
    }

    return created;
  }

  // ===========================================================================
  // 3. PHOTOS while the goats are still at the supplier
  // ===========================================================================

  /// Photos of one booking, oldest first. One equality filter, so no
  /// composite index is needed; sorted here.
  Stream<List<SaleGoatPhoto>> photosStream(String farmId, String saleId) {
    return _photos(farmId)
        .where('saleId', isEqualTo: saleId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(SaleGoatPhoto.fromDoc).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(2100))
            .compareTo(b.createdAt ?? DateTime(2100)));
      return list;
    });
  }

  Future<void> addPhoto({
    required String farmId,
    required String saleId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String note = '',
  }) {
    return _photos(farmId).add({
      'saleId': saleId,
      'photo': Blob(bytes),
      'photoContentType': contentType,
      'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  Future<void> _deleteUploadedPhotos(String farmId, String saleId) async {
    try {
      final snap = await _photos(farmId)
          .where('saleId', isEqualTo: saleId)
          .get()
          .timeout(_timeout);
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    } catch (_) {
      // Leftover photos are harmless.
    }
  }

  Future<void> deletePhoto({
    required String farmId,
    required String saleId,
    required String photoId,
  }) {
    return _photos(farmId).doc(photoId).delete().timeout(_timeout);
  }

  // ===========================================================================
  // SHARED WRITES
  // ===========================================================================

  List<Goat> _writeGoats(
      Transaction transaction, {
        required String farmId,
        required TradingPurchase lot,
        required List<SaleGoatSpec> goats,
        required int firstNumber,
        required String status,
        String? saleId,
      }) {
    final plan = LotTransferPlanner.assignGenders(
      lot,
      List<String>.filled(goats.length, ''),
    );
    final now = DateTime.now();
    final created = <Goat>[];

    for (var i = 0; i < goats.length; i++) {
      final spec = goats[i];
      final id = 'G-${(firstNumber + i).toString().padLeft(4, '0')}';

      final goat = Goat(
        id: id,
        breed: spec.breed.trim(),
        ageMonthsAtRecord: spec.ageMonths,
        ageRecordedAt: now,
        weight: spec.weight,
        color: spec.color.trim(),
        healthStatus: spec.healthStatus,
        gender: plan.genders[i],
        notes: spec.notes.trim(),
        purchaseId: lot.id,
        purchaseDate: lot.purchaseDate,
        currentStatus: status,
        saleId: saleId,
        photo: spec.photo,
        photoContentType: spec.photoContentType,
      );

      transaction.set(_goatRef(farmId, id), {
        ...goat.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        if (saleId != null) 'saleId': saleId,
        if (status == Goat.statusWaitOnDelivery)
          'waitOnDeliveryAt': FieldValue.serverTimestamp(),
      });

      created.add(goat);
    }

    transaction.set(
      _goatCounter(farmId),
      {'lastValue': firstNumber + goats.length - 1},
      SetOptions(merge: true),
    );

    return created;
  }

  /// Lot fields for moving [count] goats out of the lot into goat records:
  /// registeredCount +N, pendingCount (= farmQty) recomputed, gender
  /// counters. Same as the lot transfers in GoatService. (The dashboard's
  /// pendingRegistrations is moved by the caller.)
  Map<String, dynamic> _moveOutOfLotFields({
    required TradingPurchase lot,
    required int count,
    required List<String> genders,
    required int receivedAliveAfter,
  }) {
    final newRegistered = lot.registeredCount + count;
    final newPending = receivedAliveAfter - lot.soldFromFarmQty - newRegistered;
    final hasSplit = lot.maleGoats > 0 || lot.femaleGoats > 0;

    return {
      'registeredCount': newRegistered,
      'pendingCount': newPending < 0 ? 0 : newPending,
      if (hasSplit) ...{
        'maleRegistered': lot.maleRegistered +
            genders.where((g) => g == Goat.genderValues[0]).length,
        'femaleRegistered': lot.femaleRegistered +
            genders.where((g) => g == Goat.genderValues[1]).length,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Receives [count] goats that were booked at the supplier: writes one
  /// receiving event and returns the lot fields for it — the same lot maths
  /// as TradingService.receiveLotBatch — with the reservation moving off the
  /// supplier.
  Map<String, dynamic> _receiveReservedSupplierGoatsFields(
      Transaction transaction, {
        required DocumentReference<Map<String, dynamic>> lotRef,
        required TradingPurchase lot,
        required int count,
        required double arrivalWeight,
        required double newArrivalWeight,
        required DateTime date,
        required String saleId,
        String? actorUid,
        String? actorName,
      }) {
    final receivingRef = lotRef.collection('receivings').doc();

    final newReceivedAlive = lot.receivedAliveQty + count;
    final newReceivedTotal = newReceivedAlive + lot.mortality;
    final newSupplierQty =
        lot.totalGoats - lot.soldFromSupplierQty - newReceivedTotal;

    final expectedWeight =
        lot.totalWeightAtPurchase * newReceivedTotal / lot.totalGoats;

    final costing = PurchaseCosting(
      totalGoats: lot.totalGoats,
      weightAtPurchase: lot.totalWeightAtPurchase,
      pricePerKg: lot.pricePerKg,
      fixedPurchaseAmount: lot.isFixedPrice ? lot.fixedPurchaseAmount : 0,
      weightAfterArrival: newArrivalWeight,
      mortality: lot.mortality,
      transportCost: lot.transportCost,
      loadingCharges: lot.loadingCharges,
      unloadingCharges: lot.unloadingCharges,
      otherExpenses: lot.otherExpenses,
    );

    transaction.set(receivingRef, {
      ...LotReceiving(
        id: receivingRef.id,
        date: date,
        arrivedQty: count,
        arrivalWeight: arrivalWeight,
        note: 'Booked goats of $saleId arrived and were registered',
        actorUid: actorUid,
        actorName: actorName,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return {
      'reservedSupplierQty': FieldValue.increment(-count),
      'receivedAliveQty': FieldValue.increment(count),
      'totalWeightAfterArrival': newArrivalWeight,
      'dateReceivedAtFarm': Timestamp.fromDate(date),
      'weightLoss': PurchaseCosting.round2(expectedWeight - newArrivalWeight),
      'totalTransportExpenses': costing.totalExpenses,
      'grandTotal': costing.grandTotal,
      'effectiveCostPerKg': costing.effectiveCostPerKg,
      if (newSupplierQty <= 0) 'receivingStatus': 'completed',
    };
  }
}