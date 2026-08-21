import 'package:cloud_firestore/cloud_firestore.dart';

/// A vaccination record for a Palai goat.
///
/// Stored under:
/// palaiCustomers/{customerId}/goats/{goatId}/vaccinationRecords/{recordId}
class VaccinationRecord {
  final String id;
  final String goatId;

  /// Name of the vaccine.
  final String vaccineName;

  /// Optional disease/protection information.
  final String disease;

  /// Date on which vaccination was given.
  final DateTime vaccinationDate;

  /// Next vaccination due date.
  ///
  /// This is calculated using the customer's vaccination setting.
  final DateTime? nextDueDate;

  /// Optional vaccine batch number.
  final String batchNumber;

  /// Optional dosage information.
  final String dosage;

  /// Optional veterinarian/doctor name.
  final String veterinarian;

  /// Optional notes.
  final String note;

  /// When this record was created.
  final DateTime recordedAt;

  const VaccinationRecord({
    required this.id,
    required this.goatId,
    required this.vaccineName,
    this.disease = '',
    required this.vaccinationDate,
    this.nextDueDate,
    this.batchNumber = '',
    this.dosage = '',
    this.veterinarian = '',
    this.note = '',
    required this.recordedAt,
  });

  // ===========================================================================
  // COPY
  // ===========================================================================

  VaccinationRecord copyWith({
    String? id,
    String? goatId,
    String? vaccineName,
    String? disease,
    DateTime? vaccinationDate,
    DateTime? nextDueDate,
    bool clearNextDueDate = false,
    String? batchNumber,
    String? dosage,
    String? veterinarian,
    String? note,
    DateTime? recordedAt,
  }) {
    return VaccinationRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      vaccineName:
      vaccineName ?? this.vaccineName,
      disease: disease ?? this.disease,
      vaccinationDate:
      vaccinationDate ?? this.vaccinationDate,
      nextDueDate: clearNextDueDate
          ? null
          : nextDueDate ?? this.nextDueDate,
      batchNumber:
      batchNumber ?? this.batchNumber,
      dosage: dosage ?? this.dosage,
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

  factory VaccinationRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return VaccinationRecord(
      id: doc.id,
      goatId: _readString(
        data['goatId'],
      ),
      vaccineName: _readString(
        data['vaccineName'],
      ),
      disease: _readString(
        data['disease'],
      ),
      vaccinationDate: _readDateTime(
        data['vaccinationDate'],
      ),
      nextDueDate: _readNullableDateTime(
        data['nextDueDate'],
      ),
      batchNumber: _readString(
        data['batchNumber'],
      ),
      dosage: _readString(
        data['dosage'],
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
      'vaccineName': vaccineName,
      'disease': disease,
      'vaccinationDate':
      Timestamp.fromDate(
        vaccinationDate,
      ),
      'nextDueDate': nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),
      'batchNumber': batchNumber,
      'dosage': dosage,
      'veterinarian': veterinarian,
      'note': note,
      'recordedAt':
      Timestamp.fromDate(
        recordedAt,
      ),
    };
  }

  // ===========================================================================
  // CREATE MAP
  // ===========================================================================

  Map<String, dynamic> toCreateMap() {
    return {
      'goatId': goatId,
      'vaccineName': vaccineName,
      'disease': disease,
      'vaccinationDate':
      Timestamp.fromDate(
        vaccinationDate,
      ),
      'nextDueDate': nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),
      'batchNumber': batchNumber,
      'dosage': dosage,
      'veterinarian': veterinarian,
      'note': note,
      'recordedAt':
      FieldValue.serverTimestamp(),
    };
  }

  // ===========================================================================
  // STATUS HELPERS
  // ===========================================================================

  bool get hasNextDueDate =>
      nextDueDate != null;

  bool get isDue {
    if (nextDueDate == null) {
      return false;
    }

    final today = _dateOnly(
      DateTime.now(),
    );

    final dueDate = _dateOnly(
      nextDueDate!,
    );

    return !dueDate.isAfter(today);
  }

  bool get isOverdue {
    if (nextDueDate == null) {
      return false;
    }

    final today = _dateOnly(
      DateTime.now(),
    );

    final dueDate = _dateOnly(
      nextDueDate!,
    );

    return dueDate.isBefore(today);
  }

  bool get isDueToday {
    if (nextDueDate == null) {
      return false;
    }

    final today = _dateOnly(
      DateTime.now(),
    );

    final dueDate = _dateOnly(
      nextDueDate!,
    );

    return dueDate == today;
  }

  int? get daysUntilDue {
    if (nextDueDate == null) {
      return null;
    }

    final today = _dateOnly(
      DateTime.now(),
    );

    final dueDate = _dateOnly(
      nextDueDate!,
    );

    return dueDate
        .difference(today)
        .inDays;
  }

  String get dueStatus {
    if (nextDueDate == null) {
      return 'No due date';
    }

    if (isOverdue) {
      final days =
      daysUntilDue!.abs();

      return days == 1
          ? '1 day overdue'
          : '$days days overdue';
    }

    if (isDueToday) {
      return 'Due today';
    }

    final days =
    daysUntilDue!;

    return days == 1
        ? 'Due in 1 day'
        : 'Due in $days days';
  }

  // ===========================================================================
  // DISPLAY HELPERS
  // ===========================================================================

  String get formattedVaccinationDate {
    return _formatDate(
      vaccinationDate,
    );
  }

  String get formattedNextDueDate {
    if (nextDueDate == null) {
      return 'Not scheduled';
    }

    return _formatDate(
      nextDueDate!,
    );
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

  static DateTime? _readNullableDateTime(
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
      return DateTime.tryParse(
        value,
      );
    }

    return null;
  }

  static DateTime _dateOnly(
      DateTime date,
      ) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  static String _formatDate(
      DateTime date,
      ) {
    final day =
    date.day.toString().padLeft(
      2,
      '0',
    );

    final month =
    date.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${date.year}';
  }

  @override
  String toString() {
    return 'VaccinationRecord('
        'id: $id, '
        'goatId: $goatId, '
        'vaccineName: $vaccineName, '
        'disease: $disease, '
        'vaccinationDate: $vaccinationDate, '
        'nextDueDate: $nextDueDate, '
        'batchNumber: $batchNumber, '
        'dosage: $dosage, '
        'veterinarian: $veterinarian, '
        'note: $note, '
        'recordedAt: $recordedAt'
        ')';
  }
}