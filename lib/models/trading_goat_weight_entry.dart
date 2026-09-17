import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// One weight-check entry for a Trading goat that has moved to Own
/// Palai — Feature 6, Task 3.2 (Growth Tracking).
///
/// Stored at:
/// farms/{farmId}/tradingGoats/{goatId}/weightHistory/{entryId}
///
/// A subcollection rather than an array field on the `tradingGoats`
/// doc, per the phase 3 plan (Section 1): weight history grows
/// indefinitely and arrays eventually hit Firestore's per-document
/// size limit, subcollections don't.
class GoatWeightEntry {
  final String id;
  final double weight;
  final DateTime date;

  /// Optional monthly photo for this entry — the plan's "Monthly
  /// Photos" requirement (Section 5: "a simple chronological gallery"
  /// with no one-per-month enforcement). Stored as a Firestore `Blob`
  /// directly on this document, matching every other goat-photo field
  /// in the Trading module (see `Goat.photo`) rather than a Storage
  /// URL — no Firebase Storage bucket is used for Trading goat photos.
  final Uint8List? photo;
  final String? photoContentType;

  final String notes;
  final DateTime? createdAt;

  const GoatWeightEntry({
    required this.id,
    required this.weight,
    required this.date,
    this.photo,
    this.photoContentType,
    this.notes = '',
    this.createdAt,
  });

  bool get hasPhoto => photo != null && photo!.isNotEmpty;

  factory GoatWeightEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final weightValue = data['weight'];
    final weight = weightValue is num
        ? weightValue.toDouble()
        : double.tryParse(weightValue?.toString() ?? '') ?? 0.0;

    final photoField = data['photo'];

    return GoatWeightEntry(
      id: doc.id,
      weight: weight,
      date: data['date'] is Timestamp
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
      photo: photoField is Blob ? photoField.bytes : null,
      photoContentType: data['photoContentType'] as String?,
      notes: (data['notes'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Does not write createdAt — the service adds
  /// FieldValue.serverTimestamp(), matching Goat.toMap().
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'weight': weight,
      'date': Timestamp.fromDate(date),
      'notes': notes.trim(),
    };

    if (photo != null) {
      map['photo'] = Blob(photo!);
      map['photoContentType'] = photoContentType ?? 'image/jpeg';
    }

    return map;
  }
}