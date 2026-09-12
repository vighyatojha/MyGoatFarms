import 'package:cloud_firestore/cloud_firestore.dart';

/// Farm-level Health Reminder Settings.
///
/// Configured ONCE per farm on Profile → Health Reminder Settings and
/// applied to every active goat in the farm — regardless of which
/// customer that goat is boarded under. There is no per-goat or
/// per-customer override for any of the three record types below.
///
/// - **Hoof Cutting** uses a reminder CADENCE, in days — see
///   [hoofCuttingReminderDays]. Each new hoof-cutting record's
///   `nextDueDate` is computed by the Add Hoof Cutting screen as
///   `cuttingDate + hoofCuttingReminderDays`.
/// - **Vaccination** and **Hair Trimming** each use a single farm-wide
///   CALENDAR DATE instead — see [vaccinationNextDueDate] and
///   [hairTrimmingNextDueDate]. Every new vaccination / hair-trimming
///   record logged for ANY goat in the farm, no matter which customer,
///   gets that exact date as its `nextDueDate`. It is NOT computed
///   relative to the record's own date, unlike Hoof Cutting.
///
/// This replaces the old per-customer "Health Settings" that used to
/// live on `PalaiCustomer` (`vaccinationReminderDays`,
/// `hoofCuttingReminderDays`, `hairTrimmingReminderDays`) and the
/// short-lived variant of this model where Vaccination/Hair Trimming
/// were picked manually per record with no farm setting at all. Those
/// are no longer read or written anywhere in the app; this model is
/// now the single source of truth for all three reminders.
///
/// A null field means "no reminder" for that record type — the
/// corresponding Add screen won't compute a `nextDueDate` for a new
/// record, and no due-date reminder will be scheduled for it. Use
/// [HealthReminderSettings.defaults] for a farm that hasn't opened
/// Health Reminder Settings yet.
class HealthReminderSettings {
  /// Days after a hoof-cutting before the next one is due. Null = off.
  final int? hoofCuttingReminderDays;

  /// The exact calendar date every new vaccination record (for every
  /// goat, in every customer) should show as its next-due date. Null =
  /// off — new records get no reminder.
  final DateTime? vaccinationNextDueDate;

  /// The exact calendar date every new hair-trimming record (for every
  /// goat, in every customer) should show as its next-due date. Null =
  /// off — new records get no reminder.
  final DateTime? hairTrimmingNextDueDate;

  const HealthReminderSettings({
    this.hoofCuttingReminderDays,
    this.vaccinationNextDueDate,
    this.hairTrimmingNextDueDate,
  });

  /// Starting values for a brand-new farm that hasn't configured
  /// anything yet. Hoof Cutting keeps the old default cadence; there is
  /// no sensible default *date* for Vaccination/Hair Trimming, so those
  /// start off (null) until the farm owner picks one from Profile.
  static const HealthReminderSettings defaults = HealthReminderSettings(
    hoofCuttingReminderDays: 45,
    vaccinationNextDueDate: null,
    hairTrimmingNextDueDate: null,
  );

  /// Parses the `healthReminderSettings` map stored on the farm
  /// document. Falls back to [defaults] when the farm hasn't saved
  /// anything yet (map is null/missing) — NOT when the farm has
  /// explicitly turned a reminder off (a saved `null` for one field is
  /// respected as "off" for that field only).
  factory HealthReminderSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return HealthReminderSettings.defaults;

    int? readDays(dynamic raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    }

    DateTime? readDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return HealthReminderSettings(
      hoofCuttingReminderDays: readDays(data['hoofCuttingReminderDays']),
      vaccinationNextDueDate: readDate(data['vaccinationNextDueDate']),
      hairTrimmingNextDueDate: readDate(data['hairTrimmingNextDueDate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hoofCuttingReminderDays': hoofCuttingReminderDays,
      'vaccinationNextDueDate': vaccinationNextDueDate != null
          ? Timestamp.fromDate(vaccinationNextDueDate!)
          : null,
      'hairTrimmingNextDueDate': hairTrimmingNextDueDate != null
          ? Timestamp.fromDate(hairTrimmingNextDueDate!)
          : null,
    };
  }

  HealthReminderSettings copyWith({
    int? hoofCuttingReminderDays,
    DateTime? vaccinationNextDueDate,
    DateTime? hairTrimmingNextDueDate,
    bool clearHoofCuttingReminder = false,
    bool clearVaccinationNextDueDate = false,
    bool clearHairTrimmingNextDueDate = false,
  }) {
    return HealthReminderSettings(
      hoofCuttingReminderDays: clearHoofCuttingReminder
          ? null
          : (hoofCuttingReminderDays ?? this.hoofCuttingReminderDays),
      vaccinationNextDueDate: clearVaccinationNextDueDate
          ? null
          : (vaccinationNextDueDate ?? this.vaccinationNextDueDate),
      hairTrimmingNextDueDate: clearHairTrimmingNextDueDate
          ? null
          : (hairTrimmingNextDueDate ?? this.hairTrimmingNextDueDate),
    );
  }
}