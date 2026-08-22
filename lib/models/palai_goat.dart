import 'package:cloud_firestore/cloud_firestore.dart';

/// A goat belonging to a customer and managed under Customer Palai.
///
/// This is the core identity record for a goat.
///
/// Other records such as:
/// - weight
/// - health
/// - vaccination
/// - hoof cutting
/// - hair trimming
/// - medicine
/// - photos
/// - check-in / check-out
///
/// should reference this goat's [id] instead of storing duplicate goat data.
class PalaiGoat {
  final String id;

  /// Customer who owns this goat.
  final String customerId;

  /// Basic goat information.
  final String name;
  final String tagNumber;
  final String breed;
  final String gender;

  /// Optional physical information.
  final DateTime? dateOfBirth;
  final double? currentWeight;

  /// Current operational status.
  ///
  /// Examples:
  /// - active
  /// - checkedIn
  /// - checkedOut
  /// - inactive
  final String status;

  /// Optional image of the goat.
  final String? imageUrl;

  /// Additional notes about the goat.
  final String notes;

  /// When this goat was registered in the Palai system.
  final DateTime registrationDate;

  /// Last time this record was updated.
  final DateTime? updatedAt;

  const PalaiGoat({
    required this.id,
    required this.customerId,
    required this.name,
    required this.tagNumber,
    required this.breed,
    required this.gender,
    this.dateOfBirth,
    this.currentWeight,
    required this.status,
    this.imageUrl,
    required this.notes,
    required this.registrationDate,
    this.updatedAt,
  });

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  factory PalaiGoat.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PalaiGoat(
      id: doc.id,
      customerId:
      _readString(data['customerId']),
      name:
      _readString(data['name']),
      tagNumber:
      _readString(data['tagNumber']),
      breed:
      _readString(data['breed']),
      gender:
      _readString(data['gender']),
      dateOfBirth:
      _readDate(data['dateOfBirth']),
      currentWeight:
      _readDouble(data['currentWeight']),
      status:
      _readString(
        data['status'],
        fallback: 'active',
      ),
      imageUrl:
      _readNullableString(
        data['imageUrl'],
      ),
      notes:
      _readString(data['notes']),
      registrationDate:
      _readDate(
        data['registrationDate'],
      ) ??
          DateTime.now(),
      updatedAt:
      _readDate(data['updatedAt']),
    );
  }

  factory PalaiGoat.fromMap(
      Map<String, dynamic> data, {
        required String id,
      }) {
    return PalaiGoat(
      id: id,
      customerId:
      _readString(data['customerId']),
      name:
      _readString(data['name']),
      tagNumber:
      _readString(data['tagNumber']),
      breed:
      _readString(data['breed']),
      gender:
      _readString(data['gender']),
      dateOfBirth:
      _readDate(data['dateOfBirth']),
      currentWeight:
      _readDouble(data['currentWeight']),
      status:
      _readString(
        data['status'],
        fallback: 'active',
      ),
      imageUrl:
      _readNullableString(
        data['imageUrl'],
      ),
      notes:
      _readString(data['notes']),
      registrationDate:
      _readDate(
        data['registrationDate'],
      ) ??
          DateTime.now(),
      updatedAt:
      _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'name': name,
      'tagNumber': tagNumber,
      'breed': breed,
      'gender': gender,
      'dateOfBirth':
      dateOfBirth == null
          ? null
          : Timestamp.fromDate(
        dateOfBirth!,
      ),
      'currentWeight': currentWeight,
      'status': status,
      'imageUrl': imageUrl,
      'notes': notes,
      'registrationDate':
      Timestamp.fromDate(
        registrationDate,
      ),
      'updatedAt':
      updatedAt == null
          ? null
          : Timestamp.fromDate(
        updatedAt!,
      ),
    };
  }

  // ===========================================================================
  // COPY
  // ===========================================================================

  PalaiGoat copyWith({
    String? id,
    String? customerId,
    String? name,
    String? tagNumber,
    String? breed,
    String? gender,
    DateTime? dateOfBirth,
    double? currentWeight,
    String? status,
    String? imageUrl,
    String? notes,
    DateTime? registrationDate,
    DateTime? updatedAt,
  }) {
    return PalaiGoat(
      id: id ?? this.id,
      customerId:
      customerId ?? this.customerId,
      name: name ?? this.name,
      tagNumber:
      tagNumber ?? this.tagNumber,
      breed: breed ?? this.breed,
      gender: gender ?? this.gender,
      dateOfBirth:
      dateOfBirth ?? this.dateOfBirth,
      currentWeight:
      currentWeight ?? this.currentWeight,
      status: status ?? this.status,
      imageUrl:
      imageUrl ?? this.imageUrl,
      notes: notes ?? this.notes,
      registrationDate:
      registrationDate ??
          this.registrationDate,
      updatedAt:
      updatedAt ?? this.updatedAt,
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static String _readString(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    return value.toString();
  }

  static String? _readNullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  static double? _readDouble(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }

  static DateTime? _readDate(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}