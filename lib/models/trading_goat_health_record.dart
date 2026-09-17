import 'package:cloud_firestore/cloud_firestore.dart';

/// The four health-tracking categories Feature 6 (Task 3.3) surfaces
/// on the Own Palai Goat Profile.
enum GoatHealthRecordType { vaccination, hoofCutting, hairTrimming, medicine }

extension GoatHealthRecordTypeLabel on GoatHealthRecordType {
  String get label {
    switch (this) {
      case GoatHealthRecordType.vaccination:
        return 'Vaccination';
      case GoatHealthRecordType.hoofCutting:
        return 'Hoof Cutting';
      case GoatHealthRecordType.hairTrimming:
        return 'Hair Trimming';
      case GoatHealthRecordType.medicine:
        return 'Medicine';
    }
  }
}

/// One health-tracking entry for an Own Palai goat — vaccination, hoof
/// cutting, hair trimming, or medicine — distinguished by [type]
/// rather than split across separate collections, per the phase 3
/// plan (Section 1): "all health tracking types in one place".
///
/// Stored at:
/// farms/{farmId}/tradingGoats/{goatId}/healthRecords/{entryId}
class GoatHealthRecord {
  final String id;
  final GoatHealthRecordType type;
  final DateTime date;
  final String notes;

  /// Feeds the reminder logic (Task 1.3 / 3.4) — null if this entry
  /// has no follow-up due.
  final DateTime? nextDueDate;

  final DateTime? createdAt;

  const GoatHealthRecord({
    required this.id,
    required this.type,
    required this.date,
    this.notes = '',
    this.nextDueDate,
    this.createdAt,
  });

  bool get isOverdue =>
      nextDueDate != null && nextDueDate!.isBefore(DateTime.now());

  /// True if [nextDueDate] falls within [window] from now (and hasn't
  /// already passed — use [isOverdue] for that). Used by Task 3.4's
  /// "due soon" badge.
  bool isDueWithin(Duration window) {
    if (nextDueDate == null) return false;
    final now = DateTime.now();
    return !nextDueDate!.isBefore(now) &&
        nextDueDate!.isBefore(now.add(window));
  }

  factory GoatHealthRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return GoatHealthRecord(
      id: doc.id,
      type: GoatHealthRecordType.values.firstWhere(
            (t) => t.name == data['type'],
        orElse: () => GoatHealthRecordType.medicine,
      ),
      date: data['date'] is Timestamp
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
      notes: (data['notes'] ?? '').toString(),
      nextDueDate: data['nextDueDate'] is Timestamp
          ? (data['nextDueDate'] as Timestamp).toDate()
          : null,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Does not write createdAt — the service adds
  /// FieldValue.serverTimestamp(), matching Goat.toMap().
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'date': Timestamp.fromDate(date),
      'notes': notes.trim(),
      'nextDueDate':
      nextDueDate != null ? Timestamp.fromDate(nextDueDate!) : null,
    };
  }
}