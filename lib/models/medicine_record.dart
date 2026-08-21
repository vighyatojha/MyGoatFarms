import 'package:cloud_firestore/cloud_firestore.dart';

/// A medicine/health-treatment record for a Palai goat.
///
/// Stored under:
/// palaiCustomers/{customerId}/goats/{goatId}/medicineRecords/{recordId}
class MedicineRecord {
  final String id;
  final String goatId;

  /// Date on which the medicine/treatment was given.
  final DateTime treatmentDate;

  /// Name of the medicine or treatment.
  final String medicineName;

  /// Optional dosage, for example "5 ml".
  final String dosage;

  /// Optional frequency, for example "Once daily".
  final String frequency;

  /// Number of days for which the treatment is planned.
  final int? durationDays;

  /// Optional reason for giving the medicine.
  final String reason;

  /// Person who administered/prescribed the medicine.
  final String administeredBy;

  /// Optional veterinarian name.
  final String veterinarian;

  /// Optional notes.
  final String note;

  /// When this record was created.
  final DateTime recordedAt;

  const MedicineRecord({
    required this.id,
    required this.goatId,
    required this.treatmentDate,
    required this.medicineName,
    this.dosage = '',
    this.frequency = '',
    this.durationDays,
    this.reason = '',
    this.administeredBy = '',
    this.veterinarian = '',
    this.note = '',
    required this.recordedAt,
  });

  // ===========================================================================
  // COPY
  // ===========================================================================

  MedicineRecord copyWith({
    String? id,
    String? goatId,
    DateTime? treatmentDate,
    String? medicineName,
    String? dosage,
    String? frequency,
    int? durationDays,
    bool clearDurationDays = false,
    String? reason,
    String? administeredBy,
    String? veterinarian,
    String? note,
    DateTime? recordedAt,
  }) {
    return MedicineRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      treatmentDate:
      treatmentDate ?? this.treatmentDate,
      medicineName:
      medicineName ?? this.medicineName,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      durationDays: clearDurationDays
          ? null
          : durationDays ?? this.durationDays,
      reason: reason ?? this.reason,
      administeredBy:
      administeredBy ?? this.administeredBy,
      veterinarian:
      veterinarian ?? this.veterinarian,
      note: note ?? this.note,
      recordedAt:
      recordedAt ?? this.recordedAt,
    );
  }

  // ===========================================================================
  // FIRESTORE → MODEL
  // ===========================================================================

  factory MedicineRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return MedicineRecord(
      id: doc.id,
      goatId: _readString(data['goatId']),
      treatmentDate: _readDateTime(
        data['treatmentDate'],
        fallback: _readDateTime(
          data['date'],
        ),
      ),
      medicineName: _readString(
        data['medicineName'],
      ),
      dosage: _readString(
        data['dosage'],
      ),
      frequency: _readString(
        data['frequency'],
      ),
      durationDays:
      _readNullableInt(
        data['durationDays'],
      ),
      reason: _readString(
        data['reason'],
      ),
      administeredBy: _readString(
        data['administeredBy'],
      ),
      veterinarian: _readString(
        data['veterinarian'],
      ),
      note: _readString(
        data['note'],
      ),
      recordedAt: _readDateTime(
        data['recordedAt'],
        fallback: _readDateTime(
          data['createdAt'],
        ),
      ),
    );
  }

  // ===========================================================================
  // MODEL → FIRESTORE
  // ===========================================================================

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,
      'treatmentDate':
      Timestamp.fromDate(treatmentDate),
      'medicineName': medicineName,
      'dosage': dosage,
      'frequency': frequency,
      'durationDays': durationDays,
      'reason': reason,
      'administeredBy': administeredBy,
      'veterinarian': veterinarian,
      'note': note,
      'recordedAt':
      Timestamp.fromDate(recordedAt),
    };
  }

  // ===========================================================================
  // CREATE MAP
  // ===========================================================================

  Map<String, dynamic> toCreateMap() {
    return {
      'goatId': goatId,
      'treatmentDate':
      Timestamp.fromDate(treatmentDate),
      'medicineName': medicineName,
      'dosage': dosage,
      'frequency': frequency,
      'durationDays': durationDays,
      'reason': reason,
      'administeredBy': administeredBy,
      'veterinarian': veterinarian,
      'note': note,
      'recordedAt':
      FieldValue.serverTimestamp(),
    };
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  bool get hasDuration {
    return durationDays != null &&
        durationDays! > 0;
  }

  bool get hasDosage {
    return dosage.trim().isNotEmpty;
  }

  bool get hasFrequency {
    return frequency.trim().isNotEmpty;
  }

  bool get hasReason {
    return reason.trim().isNotEmpty;
  }

  bool get hasVeterinarian {
    return veterinarian.trim().isNotEmpty;
  }

  bool get hasAdministeredBy {
    return administeredBy.trim().isNotEmpty;
  }

  String get formattedTreatmentDate {
    return _formatDate(treatmentDate);
  }

  String get durationText {
    if (!hasDuration) {
      return 'Not specified';
    }

    return durationDays == 1
        ? '1 day'
        : '$durationDays days';
  }

  String get treatmentSummary {
    final parts = <String>[];

    if (dosage.trim().isNotEmpty) {
      parts.add(dosage.trim());
    }

    if (frequency.trim().isNotEmpty) {
      parts.add(frequency.trim());
    }

    if (hasDuration) {
      parts.add(durationText);
    }

    if (parts.isEmpty) {
      return 'Treatment details not specified';
    }

    return parts.join(' • ');
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================

  static String _readString(
      dynamic value,
      ) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static int? _readNullableInt(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  static DateTime _readDateTime(
      dynamic value, {
        DateTime? fallback,
      }) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      final parsed =
      DateTime.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    return fallback ?? DateTime.now();
  }

  static String _formatDate(
      DateTime date,
      ) {
    final day =
    date.day.toString().padLeft(2, '0');

    final month =
    date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  @override
  String toString() {
    return 'MedicineRecord('
        'id: $id, '
        'goatId: $goatId, '
        'treatmentDate: $treatmentDate, '
        'medicineName: $medicineName, '
        'dosage: $dosage, '
        'frequency: $frequency, '
        'durationDays: $durationDays, '
        'reason: $reason, '
        'administeredBy: $administeredBy, '
        'veterinarian: $veterinarian, '
        'note: $note, '
        'recordedAt: $recordedAt'
        ')';
  }
}