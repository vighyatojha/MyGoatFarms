import 'dart:math';

/// Single source of truth for WHEN MyGoatFarms is allowed to notify.
///
/// Rules (Asia/Kolkata local time):
///   * At most 3 notifications a day.
///   * Their times are NOT fixed — they are picked at random every day,
///     anywhere inside the allowed window (6:00 AM – 11:00 PM), with at
///     least 4 hours between two notifications.
///   * Nothing before 6:00 AM and nothing from 11:00 PM onwards.
///   * Opening the app never fires a notification by itself.
///
/// The random times for a given day are always the same (they are seeded
/// by the date), so reopening the app during the day does not move them.
class NotificationSchedule {
  NotificationSchedule._();

  /// Notifications per day.
  static const int perDay = 3;

  /// Minimum gap between two notifications on the same day.
  static const Duration minGap = Duration(hours: 4);

  /// No notifications from this hour (11 PM) ...
  static const int quietStartHour = 23;

  /// ... until this hour (6 AM).
  static const int quietEndHour = 6;

  /// How many days ahead the notifications are pre-scheduled. The schedule
  /// is rebuilt every time the app is opened, so this only matters if the
  /// app stays closed for a long time.
  static const int daysAhead = 7;

  /// True between 11:00 PM and 5:59 AM.
  static bool isQuietTime(DateTime time) =>
      time.hour >= quietStartHour || time.hour < quietEndHour;

  /// The [perDay] notification times for [date], as minutes after
  /// midnight, sorted, each at least [minGap] apart, all between
  /// 6:00 AM and 10:59 PM.
  ///
  /// Works by taking the free time in the window (17 h − 2 × 4 h gaps =
  /// about 9 h) and splitting it randomly before, between and after the
  /// three notifications, so every valid arrangement is possible.
  static List<int> minutesFor(DateTime date) {
    const windowStart = quietEndHour * 60; // 6:00 AM
    const windowEnd = quietStartHour * 60 - 1; // 10:59 PM, last allowed
    final gap = minGap.inMinutes;
    final slack = windowEnd - windowStart - gap * (perDay - 1);

    // Same date → same times, so a rebuild on app open never moves them.
    final random = Random(date.year * 10000 + date.month * 100 + date.day);

    final cuts = List<int>.generate(perDay, (_) => random.nextInt(slack + 1))
      ..sort();

    return [
      for (var i = 0; i < perDay; i++) windowStart + cuts[i] + gap * i,
    ];
  }
}