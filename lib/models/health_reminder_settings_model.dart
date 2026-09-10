/// Farm-level Health Reminder Day Settings.
///
/// Vaccination / Hoof Cutting / Hair Trimming reminder cadences (in
/// days), configured ONCE per farm on Profile → Health Reminder
/// Settings and applied to every active goat in the farm — regardless
/// of which customer that goat is boarded under.
///
/// This replaces the old per-customer "Health Settings" that used to
/// live on [PalaiCustomer] (`vaccinationReminderDays`,
/// `hoofCuttingReminderDays`, `hairTrimmingReminderDays`). Those fields
/// are no longer read or written anywhere in the app; this model is now
/// the single source of truth for all three cadences.
///
/// A null field means "no reminder" for that record type — the
/// corresponding Add screen (Add Vaccination / Add Hoof Cutting / Add
/// Hair Trimming) won't compute a `nextDueDate` for a new record, and
/// no due-date reminder will be scheduled for it. Use
/// [HealthReminderSettings.defaults] for a farm that hasn't opened
/// Health Reminder Settings yet — this is what every new goat gets
/// automatically, with no per-goat/per-customer setup required.
class HealthReminderSettings {
  /// Days after a vaccination before the next one is due. Null = off.
  final int? vaccinationReminderDays;

  /// Days after a hoof-cutting before the next one is due. Null = off.
  final int? hoofCuttingReminderDays;

  /// Days after a hair-trimming before the next one is due. Null = off.
  final int? hairTrimmingReminderDays;

  const HealthReminderSettings({
    this.vaccinationReminderDays,
    this.hoofCuttingReminderDays,
    this.hairTrimmingReminderDays,
  });

  /// Starting cadence for a brand-new farm that hasn't configured
  /// anything yet — matches the cadence the app used to suggest per
  /// customer before this became one farm-wide setting. Every new goat
  /// (and every customer) automatically gets these until the farm owner
  /// changes them from Profile.
  static const HealthReminderSettings defaults = HealthReminderSettings(
    vaccinationReminderDays: 30,
    hoofCuttingReminderDays: 45,
    hairTrimmingReminderDays: 30,
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

    return HealthReminderSettings(
      vaccinationReminderDays: readDays(data['vaccinationReminderDays']),
      hoofCuttingReminderDays: readDays(data['hoofCuttingReminderDays']),
      hairTrimmingReminderDays: readDays(data['hairTrimmingReminderDays']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vaccinationReminderDays': vaccinationReminderDays,
      'hoofCuttingReminderDays': hoofCuttingReminderDays,
      'hairTrimmingReminderDays': hairTrimmingReminderDays,
    };
  }

  HealthReminderSettings copyWith({
    int? vaccinationReminderDays,
    int? hoofCuttingReminderDays,
    int? hairTrimmingReminderDays,
    bool clearVaccinationReminder = false,
    bool clearHoofCuttingReminder = false,
    bool clearHairTrimmingReminder = false,
  }) {
    return HealthReminderSettings(
      vaccinationReminderDays: clearVaccinationReminder
          ? null
          : (vaccinationReminderDays ?? this.vaccinationReminderDays),
      hoofCuttingReminderDays: clearHoofCuttingReminder
          ? null
          : (hoofCuttingReminderDays ?? this.hoofCuttingReminderDays),
      hairTrimmingReminderDays: clearHairTrimmingReminder
          ? null
          : (hairTrimmingReminderDays ?? this.hairTrimmingReminderDays),
    );
  }
}