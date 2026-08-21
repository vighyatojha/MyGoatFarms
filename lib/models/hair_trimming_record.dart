import 'package:cloud_firestore/cloud_firestore.dart';

/// A hair-trimming record for a Palai goat.
///
/// Stored under:
/// palaiCustomers/{customerId}/goats/{goatId}/hairTrimmingRecords/{recordId}
class HairTrimmingRecord {
  final String id;
  final String goatId;

  /// Date on which hair trimming was performed.
  final DateTime trimmingDate;

  /// Next scheduled hair-trimming date.
  ///
  /// This will eventually be calculated from the customer's
  /// hair-trimming reminder setting.
  final DateTime? nextDueDate;

  /// Person who performed the hair trimming.
  final String performedBy;

  /// Optional notes about the trimming.
  final String note;

  /// When this record was created.
  final DateTime recordedAt;

  const HairTrimmingRecord({
    required this.id,
    required this.goatId,
    required this.trimmingDate,
    this.nextDueDate,
    this.performedBy = '',
    this.note = '',
    required this.recordedAt,
  });

  // ===========================================================================
  // COPY
  // ===========================================================================

  HairTrimmingRecord copyWith({
    String? id,
    String? goatId,
    DateTime? trimmingDate,
    DateTime? nextDueDate,
    bool clearNextDueDate = false,
    String? performedBy,
    String? note,
    DateTime? recordedAt,
  }) {
    return HairTrimmingRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      trimmingDate: trimmingDate ?? this.trimmingDate,
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

  factory HairTrimmingRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return HairTrimmingRecord(
      id: doc.id,
      goatId: _readString(data['goatId']),
      trimmingDate: _readDateTime(
        data['trimmingDate'],
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
      'trimmingDate': Timestamp.fromDate(
        trimmingDate,
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
      'trimmingDate': Timestamp.fromDate(
        trimmingDate,
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

  bool get hasNextDueDate {
    return nextDueDate != null;
  }

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

  String get formattedTrimmingDate {
    return _formatDate(trimmingDate);
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
    return 'HairTrimmingRecord('
        'id: $id, '
        'goatId: $goatId, '
        'trimmingDate: $trimmingDate, '
        'nextDueDate: $nextDueDate, '
        'performedBy: $performedBy, '
        'note: $note, '
        'recordedAt: $recordedAt'
        ')';
  }
}