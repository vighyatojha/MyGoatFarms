import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A single goat registered out of a Trading purchase.
///
/// Stored at:
/// farms/{farmId}/tradingGoats/{goatId}
///
/// (Not `goats` — see the naming note in GoatService. Palai's
/// customer-boarded goats already use that collection name elsewhere
/// in the app, queried via `collectionGroup('goats')`.)
///
/// One document is created per goat during Feature 3 (Goat Registration).
/// [purchaseId] links back to the wholesale purchase it came from
/// (`farms/{farmId}/tradingPurchases/{purchaseId}`).
///
/// Phase 2 only ever writes [currentStatus] as [statusAvailable]. Later
/// phases (Own Palai, Sale) will move goats into other statuses — see
/// [statusValues] — but must never create a new goat document or a new
/// [id] for an existing goat: registration is the only place a goat ID
/// is ever generated (see GoatService).
class Goat {
  final String id;

  // ---------------------------------------------------------------------
  // DETAILS
  // ---------------------------------------------------------------------

  final String breed;

  /// Free-text age estimate (e.g. "8-10 months"), not a birth date —
  /// wholesale-purchased goats rarely come with a known date of birth,
  /// only whatever the seller states at purchase time.
  final String age;

  final double weight;
  final String color;

  /// One of [healthStatusValues]. Defaults to "Healthy", matching the
  /// options already used for Own Farm goats.
  final String healthStatus;

  final String notes;

  // ---------------------------------------------------------------------
  // ORIGIN
  // ---------------------------------------------------------------------

  final String purchaseId;
  final DateTime purchaseDate;

  // ---------------------------------------------------------------------
  // STATUS
  // ---------------------------------------------------------------------

  /// "Available" in phase 2. Later phases add: Sold, Booked,
  /// "In Customer Palai", etc.
  final String currentStatus;

  // ---------------------------------------------------------------------
  // PHOTO
  // ---------------------------------------------------------------------
  //
  // Stored as raw bytes directly on the document (Firestore `Blob`) —
  // the same pattern used for Own Farm goats and Palai goat photos
  // elsewhere in this app (see ImageService / OwnFarmGoat). No Firebase
  // Storage path/bucket is used for goat photos anywhere in the app, so
  // Trading goat photos follow suit rather than introducing a second
  // storage mechanism just for this module.

  final Uint8List? photo;
  final String? photoContentType;

  final DateTime? createdAt;

  // ---------------------------------------------------------------------
  // OWN PALAI (Phase 3, Feature 5)
  // ---------------------------------------------------------------------
  //
  // `currentStatus` is the single source of truth for whether a goat is
  // in Own Palai — there is deliberately no separate `ownPalai` boolean,
  // per the phase 3 plan's warning against tracking the same fact two
  // ways ("pick one, don't do both or they'll drift"). Moving a goat to
  // Own Palai only ever sets `currentStatus: statusOwnPalai` and
  // `movedToOwnPalaiAt` on this same document — see GoatService and the
  // "No duplicate Goat IDs" note below.

  /// Set the moment a goat's [currentStatus] becomes [statusOwnPalai].
  /// Null for goats that have never been moved to Own Palai.
  final DateTime? movedToOwnPalaiAt;

  const Goat({
    required this.id,
    required this.breed,
    required this.age,
    required this.weight,
    required this.color,
    required this.healthStatus,
    required this.notes,
    required this.purchaseId,
    required this.purchaseDate,
    required this.currentStatus,
    this.photo,
    this.photoContentType,
    this.createdAt,
    this.movedToOwnPalaiAt,
  });

  // ---------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------

  static const String statusAvailable = 'Available';
  static const String statusOwnPalai = 'Own Palai';
  static const String statusSold = 'Sold';
  static const String statusBooked = 'Booked';
  static const String statusInCustomerPalai = 'In Customer Palai';

  /// Centrally-defined status enum (phase 3 plan, Section 5): kept here
  /// so Phase 4 (Sale) doesn't have to guess what strings this phase
  /// used when it builds the "Available for Sale" list from Own Palai
  /// goats.
  static const List<String> statusValues = [
    statusAvailable,
    statusOwnPalai,
    statusSold,
    statusBooked,
    statusInCustomerPalai,
  ];

  static const List<String> healthStatusValues = [
    'Healthy',
    'Under Treatment',
    'Sick',
    'Quarantined',
  ];

  // ---------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------

  bool get isAvailable =>
      currentStatus.trim().toLowerCase() == statusAvailable.toLowerCase();

  bool get isOwnPalai =>
      currentStatus.trim().toLowerCase() == statusOwnPalai.toLowerCase();

  @override
  bool operator ==(Object other) => other is Goat && other.id == id;

  @override
  int get hashCode => id.hashCode;

  // ---------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------

  factory Goat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime dateFrom(String key) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    double numFrom(String key) {
      final value = data[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    final photoField = data['photo'];

    return Goat(
      id: doc.id,
      breed: (data['breed'] ?? '').toString(),
      age: (data['age'] ?? '').toString(),
      weight: numFrom('weight'),
      color: (data['color'] ?? '').toString(),
      healthStatus: (data['healthStatus'] ?? 'Healthy').toString(),
      notes: (data['notes'] ?? '').toString(),
      purchaseId: (data['purchaseId'] ?? '').toString(),
      purchaseDate: dateFrom('purchaseDate'),
      currentStatus: (data['currentStatus'] ?? statusAvailable).toString(),
      photo: photoField is Blob ? photoField.bytes : null,
      photoContentType: data['photoContentType'] as String?,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      movedToOwnPalaiAt: data['movedToOwnPalaiAt'] is Timestamp
          ? (data['movedToOwnPalaiAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Does not write createdAt — the service adds
  /// FieldValue.serverTimestamp(), matching the rest of the app.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'breed': breed.trim(),
      'age': age.trim(),
      'weight': weight,
      'color': color.trim(),
      'healthStatus': healthStatus,
      'notes': notes.trim(),
      'purchaseId': purchaseId,
      'purchaseDate': Timestamp.fromDate(purchaseDate),
      'currentStatus': currentStatus,
    };

    if (photo != null) {
      map['photo'] = Blob(photo!);
      map['photoContentType'] = photoContentType ?? 'image/jpeg';
    }

    return map;
  }
}