import 'package:cloud_firestore/cloud_firestore.dart';

/// A hoof-cutting (khud cutting) record for a Palai goat.
///
/// Stored under:
/// palaiCustomers/{customerId}/goats/{goatId}/hoofCuttingRecords/{recordId}
class HoofCuttingRecord {
  final String id;
  final String goatId;

  /// Date on which hoof cutting was performed.
  final DateTime cuttingDate;

  /// Next scheduled hoof-cutting date.
  ///
  /// This should normally be calculated from the customer's setting
  /// (for example, 30 or 45 days).
  final DateTime? nextDueDate;

  /// Person who performed the hoof cutting.
  final String performedBy;

  /// Optional notes about the hoof condition or treatment.
  final String note;

  /// When this record was created.
  final DateTime recordedAt;

  const HoofCuttingRecord({
    required this.id,
    required this.goatId,
    required this.cuttingDate,
    this.nextDueDate,
    this.performedBy = '',
    this.note = '',
    required this.recordedAt,
  });

  // ===========================================================================
  // COPY
  // ===========================================================================

  HoofCuttingRecord copyWith({
    String? id,
    String? goatId,
    DateTime? cuttingDate,
    DateTime? nextDueDate,
    bool clearNextDueDate = false,
    String? performedBy,
    String? note,
    DateTime? recordedAt,
  }) {
    return HoofCuttingRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      cuttingDate: cuttingDate ?? this.cuttingDate,
      nextDueDate: clearNextDueDate
          ? null
          : nextDueDate ?? this.nextDueDate,
      performedBy: performedBy ?? this.performedBy,
      note: note ?? this.note,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  // ===========================================================================
  // FIRESTORE → MODEL
  // ===========================================================================

  factory HoofCuttingRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return HoofCuttingRecord(
      id: doc.id,
      goatId: _readString(data['goatId']),
      cuttingDate: _readDateTime(
        data['cuttingDate'],
        fallback: _readDateTime(
          data['date'],
        ),
      ),
      nextDueDate: _readNullableDateTime(
        data['nextDueDate'],
      ),
      performedBy: _readString(
        data['performedBy'],
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
      'cuttingDate': Timestamp.fromDate(
        cuttingDate,
      ),
      'nextDueDate': nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),
      'performedBy': performedBy,
      'note': note,
      'recordedAt': Timestamp.fromDate(
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
      'cuttingDate': Timestamp.fromDate(
        cuttingDate,
      ),
      'nextDueDate': nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),
      'performedBy': performedBy,
      'note': note,
      'recordedAt': FieldValue.serverTimestamp(),
    };
  }

  // ===========================================================================
  // STATUS
  // ===========================================================================

  bool get hasNextDueDate => nextDueDate != null;

  bool get isOverdue {
    if (nextDueDate == null) {
      return false;
    }

    final today = _dateOnly(DateTime.now());
    final dueDate = _dateOnly(nextDueDate!);

    return dueDate.isBefore(today);
  }

  bool get isDueToday {
    if (nextDueDate == null) {
      return false;
    }

    final today = _dateOnly(DateTime.now());
    final dueDate = _dateOnly(nextDueDate!);

    return dueDate == today;
  }

  bool get isDue {
    if (nextDueDate == null) {
      return false;
    }

    final today = _dateOnly(DateTime.now());
    final dueDate = _dateOnly(nextDueDate!);

    return !dueDate.isAfter(today);
  }

  int? get daysUntilDue {
    if (nextDueDate == null) {
      return null;
    }

    final today = _dateOnly(DateTime.now());
    final dueDate = _dateOnly(nextDueDate!);

    return dueDate.difference(today).inDays;
  }

  String get dueStatus {
    if (nextDueDate == null) {
      return 'No due date';
    }

    if (isOverdue) {
      final days = daysUntilDue!.abs();

      return days == 1
          ? '1 day overdue'
          : '$days days overdue';
    }

    if (isDueToday) {
      return 'Due today';
    }

    final days = daysUntilDue!;

    return days == 1
        ? 'Due in 1 day'
        : 'Due in $days days';
  }

  // ===========================================================================
  // DISPLAY HELPERS
  // ===========================================================================

  String get formattedCuttingDate {
    return _formatDate(cuttingDate);
  }

  String get formattedNextDueDate {
    if (nextDueDate == null) {
      return 'Not scheduled';
    }

    return _formatDate(nextDueDate!);
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================

  static String _readString(dynamic value) {
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
      final parsed = DateTime.tryParse(value);

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
      return DateTime.tryParse(value);
    }

    return null;
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  @override
  String toString() {
    return 'HoofCuttingRecord('
        'id: $id, '
        'goatId: $goatId, '
        'cuttingDate: $cuttingDate, '
        'nextDueDate: $nextDueDate, '
        'performedBy: $performedBy, '
        'note: $note, '
        'recordedAt: $recordedAt'
        ')';
  }
}