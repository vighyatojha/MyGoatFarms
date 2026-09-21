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
///
/// Two kinds of record live in that collection:
///
///  * **Logged records** — created by the farm owner from the Log button
///    on the profile's Vaccination / Hoof Cutting / Hair Trimming /
///    Medicine tabs. They describe something that actually happened.
///
///  * **Farm-schedule records** ([isAuto] == true) — created and kept up to
///    date by `FirestoreService.syncOwnPalaiFarmReminders` straight from
///    the farm's Health Reminder Settings (Profile → Health Reminder
///    Settings). There is at most one per goat per care type, always with
///    the fixed id [farmScheduleId]. They hold the goat's *next due date*
///    for that care type — they are a schedule, not an event that already
///    happened — which is what lets an Own Palai goat show the farm's
///    dates automatically, without anyone having to log anything first.
class GoatHealthRecord {
  final String id;
  final GoatHealthRecordType type;

  /// For a logged record: the day the care was done. For a farm-schedule
  /// record ([isAuto]): the reference day the schedule was counted from
  /// (the goat's Own Palai start date, or its last logged hoof cutting) —
  /// NOT a completed event, so UI must not present it as "Last Done".
  final DateTime date;
  final String notes;

  /// Feeds the reminder logic (Task 1.3 / 3.4) — null if this entry
  /// has no follow-up due.
  final DateTime? nextDueDate;

  final DateTime? createdAt;

  /// True for the farm-schedule record maintained automatically from the
  /// farm's Health Reminder Settings. See the class docs.
  final bool isAuto;

  /// Fingerprint of the farm setting this schedule record was last armed
  /// for (`d:2026-11-15` for a fixed date, `n:45` for a day-cadence,
  /// `off` when the farm turned the reminder off). The sync compares it
  /// with the CURRENT setting: equal means "already up to date — leave it
  /// alone" (so a schedule the owner marked as completed stays completed),
  /// different means the farm changed its setting and every goat must be
  /// re-armed with the new date. Only set when [isAuto].
  final String? seededFor;

  const GoatHealthRecord({
    required this.id,
    required this.type,
    required this.date,
    this.notes = '',
    this.nextDueDate,
    this.createdAt,
    this.isAuto = false,
    this.seededFor,
  });

  /// Deterministic doc id of the farm-schedule record for [type], so the
  /// sync (and anything that has to switch it off) can address it without
  /// a query, and so it can never be duplicated.
  static String farmScheduleId(GoatHealthRecordType type) =>
      'farm_${type.name}';

  /// The three care types the farm's Health Reminder Settings govern.
  /// Medicine has no farm-wide schedule.
  static bool followsFarmSettings(GoatHealthRecordType type) =>
      type != GoatHealthRecordType.medicine;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// True once the due DAY is before today. A reminder due today is not
  /// overdue yet — farm dates are stored at midnight, so comparing raw
  /// timestamps would flag them overdue from 00:01 on the day itself.
  bool get isOverdue =>
      nextDueDate != null &&
          _dayOf(nextDueDate!).isBefore(_dayOf(DateTime.now()));

  /// True if [nextDueDate] falls today or within [window] from today (and
  /// hasn't already passed — use [isOverdue] for that). Used by Task 3.4's
  /// "due soon" badge.
  bool isDueWithin(Duration window) {
    if (nextDueDate == null) return false;
    final today = _dayOf(DateTime.now());
    final dueDay = _dayOf(nextDueDate!);
    return !dueDay.isBefore(today) &&
        !dueDay.isAfter(today.add(window));
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
      isAuto: data['auto'] == true,
      seededFor: data['seededFor']?.toString(),
    );
  }

  /// Does not write createdAt — the service adds
  /// FieldValue.serverTimestamp(), matching Goat.toMap().
  ///
  /// `auto` / `seededFor` are only written for farm-schedule records, so
  /// ordinary logged records keep exactly the shape they always had.
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'date': Timestamp.fromDate(date),
      'notes': notes.trim(),
      'nextDueDate':
      nextDueDate != null ? Timestamp.fromDate(nextDueDate!) : null,
      if (isAuto) 'auto': true,
      if (isAuto && seededFor != null) 'seededFor': seededFor,
    };
  }
}