import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:mygoatfarms/models/stock_model.dart';
import 'package:mygoatfarms/services/firestore_service.dart';

/// Edits an existing stock item (medicine or feed) from the Stock details
/// sheet.
///
/// What can be edited:
///  * name (checked so it can never clash with another item of the same
///    type, because Add Stock finds an item by name),
///  * low stock threshold,
///  * description,
///  * photo (replace or remove),
///  * the counted quantity, for correcting a wrong count. A correction is
///    saved as a stock movement ("Stock correction") so the Recent
///    Activity list shows who changed it and by how much.
///
/// The unit is not edited here: changing Bottle to Kg on stock that is
/// already counted would silently change its meaning.
class StockEditService {
  StockEditService._();

  static final StockEditService instance = StockEditService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> _items(String farmId) =>
      _db.collection('farms').doc(farmId).collection('stockItems');

  CollectionReference<Map<String, dynamic>> _movements(String farmId) =>
      _db.collection('farms').doc(farmId).collection('stockMovements');

  /// Saves the edits. Pass [newPhoto] to replace the photo, or set
  /// [removePhoto] to delete it. [newQuantity] is the corrected count in
  /// the item's own unit (bottles, units, kg or bags).
  Future<void> editItem({
    required String farmId,
    required StockItem item,
    required String name,
    required double lowStockThreshold,
    required String description,
    double? newQuantity,
    Uint8List? newPhoto,
    String? newPhotoContentType,
    bool removePhoto = false,
    String correctionNote = '',
  }) async {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError('Name cannot be empty.');
    }

    if (lowStockThreshold < 0) {
      throw ArgumentError('Low stock threshold cannot be negative.');
    }

    if (newQuantity != null && newQuantity < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }

    final typeStr = item.type == StockType.medicine ? 'medicine' : 'feed';

    // A renamed item must not collide with another item of the same type.
    if (trimmedName != item.name) {
      final clash = await _items(farmId)
          .where('name', isEqualTo: trimmedName)
          .where('type', isEqualTo: typeStr)
          .limit(2)
          .get()
          .timeout(_timeout);

      if (clash.docs.any((d) => d.id != item.id)) {
        throw StateError(
          'Another ${item.type == StockType.medicine ? 'medicine' : 'feed'} '
              'is already called "$trimmedName".',
        );
      }
    }

    final actor = await FirestoreService.instance.getCurrentActor();

    // The change in quantity actually applied, set inside the transaction
    // from the live value so a usage recorded a moment ago is respected.
    double appliedDelta = 0;
    double? appliedWeightPerBag;
    double? appliedKg;

    await _db.runTransaction((txn) async {
      final ref = _items(farmId).doc(item.id);
      final snap = await txn.get(ref);

      if (!snap.exists) {
        throw StateError('This item no longer exists.');
      }

      final data = snap.data()!;
      final unit = (data['unit'] ?? item.unit).toString();
      final isBag = unit.trim().toLowerCase() == 'bag';
      final currentQty = (data['quantity'] ?? 0).toDouble();
      final weightPerBag = (data['weightPerBag'] as num?)?.toDouble();

      final update = <String, dynamic>{
        'name': trimmedName,
        'lowStockThreshold': lowStockThreshold,
        'lastUpdated': FieldValue.serverTimestamp(),
        'description': description.trim().isEmpty
            ? FieldValue.delete()
            : description.trim(),
      };

      if (newQuantity != null && (newQuantity - currentQty).abs() > 0.000001) {
        if (isBag && (weightPerBag == null || weightPerBag <= 0)) {
          throw StateError(
            'Set the weight of one bag before correcting this quantity.',
          );
        }

        appliedDelta = newQuantity - currentQty;

        update['quantity'] = newQuantity;
        // For a bag item, totalKg is the authoritative figure; for every
        // other unit it equals the quantity.
        update['totalKg'] = isBag ? newQuantity * weightPerBag! : newQuantity;

        if (isBag) {
          appliedWeightPerBag = weightPerBag;
          appliedKg = appliedDelta.abs() * weightPerBag!;
        }
      }

      if (removePhoto) {
        update['photo'] = FieldValue.delete();
        update['photoContentType'] = FieldValue.delete();
      } else if (newPhoto != null) {
        update['photo'] = Blob(newPhoto);
        update['photoContentType'] = newPhotoContentType ?? 'image/jpeg';
      }

      txn.update(ref, update);
    }).timeout(_timeout * 2);

    // Movement history keeps the old name on old rows, as before. Only a
    // quantity change adds a new row.
    if (appliedDelta.abs() > 0.000001) {
      final note = correctionNote.trim().isEmpty
          ? 'Stock correction'
          : 'Stock correction: ${correctionNote.trim()}';

      await _movements(farmId).add(StockMovement(
        id: '',
        stockItemId: item.id,
        itemName: trimmedName,
        quantity: appliedDelta.abs(),
        unit: item.unit,
        isAddition: appliedDelta > 0,
        date: DateTime.now(),
        notes: note,
        actorUid: actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        weightPerBag: appliedWeightPerBag,
        kgAmount: appliedKg,
      ).toMap()).timeout(_timeout);
    }
  }
}