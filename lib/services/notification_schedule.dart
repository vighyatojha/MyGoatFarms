/// Single source of truth for WHEN MyGoatFarms is allowed to notify.
///
/// Rules (Asia/Kolkata local time):
///   * The health digest is delivered EVERY 4 HOURS at fixed times:
///     6:00 AM, 10:00 AM, 2:00 PM, 6:00 PM and 10:00 PM.
///   * Nothing before 6:00 AM and nothing from 11:00 PM onwards.
///   * Opening the app never fires a notification by itself (except the
///     one-time catch-up of a missed digest, see HealthReminderScheduler).
///
/// To change the times, edit [firstHour] / [interval] below — everything
/// else (scheduling, ids, quiet hours) follows automatically.
class NotificationSchedule {
  NotificationSchedule._();

  /// First digest of the day (6 AM).
  static const int firstHour = 6;

  /// Time between two digests.
  static const Duration interval = Duration(hours: 4);

  /// Kept for older callers: the minimum gap is the fixed interval.
  static const Duration minGap = interval;

  /// No notifications from this hour (11 PM) ...
  static const int quietStartHour = 23;

  /// ... until this hour (6 AM).
  static const int quietEndHour = 6;

  /// Digests per day: every slot from [firstHour] that is still before
  /// [quietStartHour]. With 6 AM + every 4 h that is 5 (6, 10, 14, 18, 22).
  static final int perDay = _times().length;

  /// How many days ahead the notifications are pre-scheduled. The schedule
  /// is rebuilt every time the app is opened (and by the background job),
  /// so this only matters if the app stays closed for a long time.
  static const int daysAhead = 7;

  /// True between 11:00 PM and 5:59 AM.
  static bool isQuietTime(DateTime time) =>
      time.hour >= quietStartHour || time.hour < quietEndHour;

  /// The digest times for [date], as minutes after midnight, sorted.
  /// The same for every day.
  static List<int> minutesFor(DateTime date) => _times();

  static List<int> _times() {
    final step = interval.inMinutes;
    return [
      for (var m = firstHour * 60; m < quietStartHour * 60; m += step) m,
    ];
  }
}