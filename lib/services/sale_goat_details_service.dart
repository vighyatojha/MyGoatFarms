import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sale_draft.dart';

/// One weight entry of a lot sale goat.
class SaleGoatWeight {
  final double weight;
  final DateTime? date;

  const SaleGoatWeight({required this.weight, this.date});
}

/// One health record of a lot sale goat.
class SaleGoatHealth {
  final String status;
  final String note;
  final DateTime? date;

  const SaleGoatHealth({required this.status, this.note = '', this.date});
}

/// An extra photo of a lot sale goat (besides its main photo).
class SaleGoatExtraPhoto {
  final String id;
  final Uint8List bytes;
  final DateTime? date;

  const SaleGoatExtraPhoto({required this.id, required this.bytes, this.date});
}

/// One goat of a lot sale ("Goat N"), as saved on Step 6 and updated from
/// its profile ([LotGoatProfileScreen]).
class SaleGoatDetail {
  final int index;
  final Uint8List? photo;
  final int ageMonths;
  final double weight;

  /// Stable key of this goat: its extra photos are filed under it, so
  /// they stay with the goat when a booking is split (and the goat gets a
  /// new number on the new booking).
  final String goatKey;

  final String healthStatus;
  final List<SaleGoatWeight> weightHistory;
  final List<SaleGoatHealth> healthRecords;

  /// False for a placeholder: a goat of the booking that has nothing saved
  /// yet (older bookings, or photos skipped).
  final bool exists;

  const SaleGoatDetail({
    required this.index,
    this.photo,
    this.ageMonths = 0,
    this.weight = 0,
    this.goatKey = '',
    this.healthStatus = '',
    this.weightHistory = const [],
    this.healthRecords = const [],
    this.exists = true,
  });

  /// Nothing saved yet for Goat [index].
  const SaleGoatDetail.empty(this.index)
      : photo = null,
        ageMonths = 0,
        weight = 0,
        goatKey = '',
        healthStatus = '',
        weightHistory = const [],
        healthRecords = const [],
        exists = false;

  /// "Goat 1", "Goat 2", ... — lot goats have no tag of their own.
  String get label => 'Goat $index';

  bool get hasPhoto => photo != null && photo!.isNotEmpty;
}

/// Photo, approximate age, weight and health of each goat of a LOT sale
/// (Sell from Lot → Step 6, for Deliver Now, Booking / Holding and Wait for
/// Delivery). A lot sale has no registered goats to put them on, so they
/// are kept per sale in farms/{farmId}/saleGoatDetails, one document per
/// goat ({saleId}_{n}); extra photos are in
/// farms/{farmId}/saleGoatDetailPhotos (one document per photo, filed by
/// the goat's key).
///
/// Shown on the Wait on Delivery / Booking & Holding goat list, the goat's
/// profile ([LotGoatProfileScreen]) and the customer's purchase history.
///
/// (Sales of registered goats save the photo and age on the goat itself —
/// see GoatPhotoService.)
class SaleGoatDetailsService {
  SaleGoatDetailsService._();

  static final SaleGoatDetailsService instance = SaleGoatDetailsService._();

  static const Duration _timeout = Duration(seconds: 30);

  /// Goats written per batch. Photos are compressed to the goat-photo
  /// budget (~350 KB), so 10 stays well under Firestore's request limit.
  static const int _batchSize = 10;

  final Map<String, Future<List<SaleGoatDetail>>> _cache = {};

  CollectionReference<Map<String, dynamic>> _col(String farmId) =>
      FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId)
          .collection('saleGoatDetails');

  CollectionReference<Map<String, dynamic>> _photoCol(String farmId) =>
      FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId)
          .collection('saleGoatDetailPhotos');

  static String docId(String saleId, int index) => '${saleId}_$index';

  // ===========================================================================
  // SALE (Step 6)
  // ===========================================================================

  /// Saves [goats] for [saleId]. Safe to call again after a failure: each
  /// goat has a fixed document id, so nothing is duplicated.
  Future<void> saveForSale({
    required String farmId,
    required String saleId,
    required String lotDisplayId,
    required List<LotGoatDetail> goats,
  }) async {
    final col = _col(farmId);

    for (var start = 0; start < goats.length; start += _batchSize) {
      final end = (start + _batchSize) > goats.length
          ? goats.length
          : start + _batchSize;
      final batch = FirebaseFirestore.instance.batch();

      for (var i = start; i < end; i++) {
        final g = goats[i];
        final n = i + 1;
        final id = docId(saleId, n);
        batch.set(col.doc(id), {
          'saleId': saleId,
          'index': n,
          'goatKey': id,
          'lotId': lotDisplayId,
          if (g.hasPhoto) 'photo': Blob(g.photo!),
          'photoContentType': g.photoContentType,
          'ageMonths': g.ageMonths,
          'weight': g.weight,
          'weightHistory': [
            if (g.weight > 0)
              {'weight': g.weight, 'date': Timestamp.now()},
          ],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit().timeout(_timeout);
    }

    _cache.remove('$farmId/$saleId');
  }

  // ===========================================================================
  // READ
  // ===========================================================================

  /// Live goats saved for [saleId], in order.
  Stream<List<SaleGoatDetail>> streamForSale(String farmId, String saleId) {
    return _col(farmId)
        .where('saleId', isEqualTo: saleId)
        .snapshots()
        .map((snap) => [
      for (final doc in snap.docs) _fromDoc(doc.id, doc.data()),
    ]..sort((a, b) => a.index.compareTo(b.index)));
  }

  /// Goat 1..[count] of [saleId]: what is saved, plus a placeholder for
  /// every goat that has nothing saved yet — so each goat of the booking
  /// can be opened and filled in.
  static List<SaleGoatDetail> withPlaceholders(
      List<SaleGoatDetail> saved,
      int count,
      ) {
    final byIndex = {for (final g in saved) g.index: g};
    final last = saved.isEmpty ? 0 : saved.last.index;
    final n = count > last ? count : last;
    return [
      for (var i = 1; i <= n; i++) byIndex[i] ?? SaleGoatDetail.empty(i),
    ];
  }

  /// Live Goat [index] of [saleId] (its profile).
  Stream<SaleGoatDetail> goatStream(String farmId, String saleId, int index) {
    return _col(farmId).doc(docId(saleId, index)).snapshots().map(
          (doc) => doc.exists
          ? _fromDoc(doc.id, doc.data()!)
          : SaleGoatDetail.empty(index),
    );
  }

  /// Extra photos of the goat with [goatKey], newest first.
  Stream<List<SaleGoatExtraPhoto>> extraPhotosStream(
      String farmId,
      String goatKey,
      ) {
    return _photoCol(farmId)
        .where('goatKey', isEqualTo: goatKey)
        .snapshots()
        .map((snap) {
      final list = <SaleGoatExtraPhoto>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final photo = d['photo'];
        if (photo is! Blob) continue;
        list.add(SaleGoatExtraPhoto(
          id: doc.id,
          bytes: photo.bytes,
          date: _date(d['createdAt']),
        ));
      }
      list.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
      return list;
    });
  }

  /// The goats saved for [saleId], in order. Loaded once per sale.
  Future<List<SaleGoatDetail>> forSale(String farmId, String saleId) {
    final key = '$farmId/$saleId';
    final cached = _cache[key];
    if (cached != null) return cached;

    final future = _load(farmId, saleId);
    _cache[key] = future;
    // A failed load is not kept, so opening the sale again retries.
    future.then<void>((_) {}, onError: (Object _) {
      _cache.remove(key);
    });
    return future;
  }

  Future<List<SaleGoatDetail>> _load(String farmId, String saleId) async {
    final snap = await _col(farmId)
        .where('saleId', isEqualTo: saleId)
        .get()
        .timeout(_timeout);

    return [
      for (final doc in snap.docs) _fromDoc(doc.id, doc.data()),
    ]..sort((a, b) => a.index.compareTo(b.index));
  }

  // ===========================================================================
  // PROFILE UPDATES (any goat of the booking, saved or not yet)
  // ===========================================================================

  /// Fields every goat document carries. [goatKey] is written only when
  /// the document is new or older than the key (it must never change).
  Future<Map<String, dynamic>> _base(
      DocumentReference<Map<String, dynamic>> ref, {
        required String saleId,
        required int index,
        required String lotDisplayId,
      }) async {
    final snap = await ref.get().timeout(_timeout);
    final hasKey =
        snap.exists && (snap.data()?['goatKey'] ?? '').toString().isNotEmpty;
    return {
      'saleId': saleId,
      'index': index,
      'lotId': lotDisplayId,
      if (!hasKey) 'goatKey': ref.id,
      if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<String> _write({
    required String farmId,
    required String saleId,
    required int index,
    required String lotDisplayId,
    required Map<String, dynamic> fields,
  }) async {
    final ref = _col(farmId).doc(docId(saleId, index));
    final base = await _base(
      ref,
      saleId: saleId,
      index: index,
      lotDisplayId: lotDisplayId,
    );
    await ref
        .set({...base, ...fields}, SetOptions(merge: true))
        .timeout(_timeout);
    _cache.remove('$farmId/$saleId');
    return ref.id;
  }

  /// Sets the goat's main photo.
  Future<void> setPhoto({
    required String farmId,
    required String saleId,
    required int index,
    required String lotDisplayId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) =>
      _write(
        farmId: farmId,
        saleId: saleId,
        index: index,
        lotDisplayId: lotDisplayId,
        fields: {
          'photo': Blob(bytes),
          'photoContentType': contentType,
        },
      );

  /// Adds another photo of the goat (kept apart from the main photo).
  Future<void> addExtraPhoto({
    required String farmId,
    required String saleId,
    required int index,
    required String lotDisplayId,
    required String goatKey,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    // Make sure the goat document (and its key) exists first.
    final key = goatKey.isNotEmpty
        ? goatKey
        : await _write(
      farmId: farmId,
      saleId: saleId,
      index: index,
      lotDisplayId: lotDisplayId,
      fields: const {},
    );
    await _photoCol(farmId).add({
      'goatKey': key,
      'saleId': saleId,
      'photo': Blob(bytes),
      'photoContentType': contentType,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  Future<void> deleteExtraPhoto(String farmId, String photoId) =>
      _photoCol(farmId).doc(photoId).delete().timeout(_timeout);

  /// Records a new weight (also kept in the weight history).
  Future<void> updateWeight({
    required String farmId,
    required String saleId,
    required int index,
    required String lotDisplayId,
    required double weight,
    required DateTime date,
  }) =>
      _write(
        farmId: farmId,
        saleId: saleId,
        index: index,
        lotDisplayId: lotDisplayId,
        fields: {
          'weight': weight,
          'weightHistory': FieldValue.arrayUnion([
            {'weight': weight, 'date': Timestamp.fromDate(date)},
          ]),
        },
      );

  Future<void> setAgeMonths({
    required String farmId,
    required String saleId,
    required int index,
    required String lotDisplayId,
    required int months,
  }) =>
      _write(
        farmId: farmId,
        saleId: saleId,
        index: index,
        lotDisplayId: lotDisplayId,
        fields: {'ageMonths': months},
      );

  /// Adds a health record; the goat's health status becomes [status].
  Future<void> addHealthRecord({
    required String farmId,
    required String saleId,
    required int index,
    required String lotDisplayId,
    required String status,
    required String note,
    required DateTime date,
  }) =>
      _write(
        farmId: farmId,
        saleId: saleId,
        index: index,
        lotDisplayId: lotDisplayId,
        fields: {
          'healthStatus': status,
          'healthRecords': FieldValue.arrayUnion([
            {
              'status': status,
              'note': note.trim(),
              'date': Timestamp.fromDate(date),
              'recordedAt': Timestamp.now(),
            },
          ]),
        },
      );

  // ===========================================================================
  // BOOKING SPLIT
  // ===========================================================================

  /// After a lot booking was split ([WaitBookingSplitService]): the
  /// booking [saleId] keeps Goat 1..[keepCount]; Goat keepCount+1.. move to
  /// the new booking [toSaleId] as its Goat 1, 2, ... — or are removed when
  /// the leftover goats went back to stock ([toSaleId] null). Extra photos
  /// follow the goat (they are filed by its key).
  Future<void> splitTail({
    required String farmId,
    required String saleId,
    required int keepCount,
    String? toSaleId,
  }) async {
    final col = _col(farmId);
    final snap = await col
        .where('saleId', isEqualTo: saleId)
        .get()
        .timeout(_timeout);

    final tail = snap.docs
        .where((d) => ((d.data()['index'] as num?)?.toInt() ?? 0) > keepCount)
        .toList();

    for (var start = 0; start < tail.length; start += _batchSize) {
      final end = (start + _batchSize) > tail.length
          ? tail.length
          : start + _batchSize;
      final batch = FirebaseFirestore.instance.batch();

      for (var i = start; i < end; i++) {
        final doc = tail[i];
        final data = doc.data();
        if (toSaleId != null) {
          final n = ((data['index'] as num?)?.toInt() ?? 0) - keepCount;
          final key = (data['goatKey'] ?? '').toString();
          batch.set(col.doc(docId(toSaleId, n)), {
            ...data,
            'saleId': toSaleId,
            'index': n,
            'goatKey': key.isEmpty ? doc.id : key,
            'movedFromSaleId': saleId,
          });
        }
        batch.delete(doc.reference);
      }

      await batch.commit().timeout(_timeout);
    }

    _cache.remove('$farmId/$saleId');
    if (toSaleId != null) _cache.remove('$farmId/$toSaleId');
  }

  // ===========================================================================
  // PARSING
  // ===========================================================================

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  static SaleGoatDetail _fromDoc(String id, Map<String, dynamic> d) {
    final photo = d['photo'];

    final weights = <SaleGoatWeight>[
      for (final w in (d['weightHistory'] as List?) ?? const [])
        if (w is Map)
          SaleGoatWeight(
            weight: (w['weight'] as num?)?.toDouble() ?? 0,
            date: _date(w['date']),
          ),
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));

    final health = <SaleGoatHealth>[
      for (final h in (d['healthRecords'] as List?) ?? const [])
        if (h is Map)
          SaleGoatHealth(
            status: (h['status'] ?? '').toString(),
            note: (h['note'] ?? '').toString(),
            date: _date(h['date']),
          ),
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));

    final key = (d['goatKey'] ?? '').toString();

    return SaleGoatDetail(
      index: (d['index'] as num?)?.toInt() ?? 0,
      photo: photo is Blob ? photo.bytes : null,
      ageMonths: (d['ageMonths'] as num?)?.toInt() ?? 0,
      weight: (d['weight'] as num?)?.toDouble() ?? 0,
      goatKey: key.isEmpty ? id : key,
      healthStatus: (d['healthStatus'] ?? '').toString(),
      weightHistory: weights,
      healthRecords: health,
    );
  }
}