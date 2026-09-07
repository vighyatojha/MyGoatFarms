import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/own_farm_models.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

/// Schedules the "7 days before / 1 day before / due today" health
/// reminder notifications described in the notification design doc, for
/// vaccination, hoof cutting, hair trimming and any other [HealthEvent]
/// that carries a [HealthEvent.nextDueDate].
///
/// There is no backend (Cloud Functions) in this app yet, so these are
/// scheduled entirely on-device using flutter_local_notifications'
/// zonedSchedule — which uses Android's AlarmManager under the hood and
/// will fire even if the app is backgrounded or fully closed. (The one
/// gap this doesn't cover is a device reboot clearing pending alarms —
/// see the note on [rescheduleAllForFarm].)
class HealthReminderScheduler {
  HealthReminderScheduler._();
  static final HealthReminderScheduler instance = HealthReminderScheduler._();

  FlutterLocalNotificationsPlugin get _plugin =>
      NotificationService.instance.localNotificationsPlugin;

  /// Schedules (or, if called again for the same event, replaces) the
  /// due-date reminders for one health event.
  ///
  /// Call this right after [FirestoreService.addHealthEvent] succeeds,
  /// passing the event id it returned. [goatCode] is the goat's display
  /// code (e.g. "OF-1001"), used in the notification text.
  Future<void> scheduleForEvent({
    required String farmId,
    required String goatId,
    required String goatCode,
    required String eventId,
    required HealthEvent event,
  }) async {
    // Cancel any existing schedule for this event first, so editing an
    // event's due date doesn't leave stale reminders behind alongside
    // the new ones.
    await cancelForEvent(eventId);

    final dueDate = event.nextDueDate;
    if (dueDate == null) return; // No reminder cadence set for this event.

    final label = event.label.toLowerCase();

    final payload = NotificationService.encodePayload({
      'category': 'health',
      'type': '${event.type.name}_due',
      'goatId': goatId,
      'eventId': eventId,
    });

    await _scheduleIfFuture(
      id: _notificationId(eventId, _ReminderStage.sevenDaysBefore),
      when: dueDate.subtract(const Duration(days: 7)),
      title: '${event.label} coming up',
      body: '$goatCode is due for $label in 7 days.',
      payload: payload,
    );

    await _scheduleIfFuture(
      id: _notificationId(eventId, _ReminderStage.oneDayBefore),
      when: dueDate.subtract(const Duration(days: 1)),
      title: '${event.label} tomorrow',
      body: '$goatCode is due for $label tomorrow.',
      payload: payload,
    );

    await _scheduleIfFuture(
      id: _notificationId(eventId, _ReminderStage.dueToday),
      when: dueDate,
      title: '${event.label} due today',
      body: '$goatCode is due for $label today.',
      payload: payload,
    );
  }

  /// Cancels all reminders previously scheduled for one event — call
  /// this if the event/schedule is deleted.
  Future<void> cancelForEvent(String eventId) async {
    for (final stage in _ReminderStage.values) {
      await _plugin.cancel(_notificationId(eventId, stage));
    }
  }

  /// Re-derives and re-schedules reminders for every goat's open health
  /// events across the farm.
  ///
  /// flutter_local_notifications' scheduled alarms are cleared by
  /// Android when the phone reboots and are NOT automatically
  /// re-created — call this once after login / on app start (in
  /// addition to scheduling at creation time) so a reboot doesn't
  /// silently drop upcoming reminders.
  Future<void> rescheduleAllForFarm(String farmId) async {
    try {
      final upcoming = await FirestoreService.instance.upcomingHealthReminders(
        farmId,
        withinDays: 60,
      );
      for (final entry in upcoming) {
        final goat = entry.key;
        final event = entry.value;
        await scheduleForEvent(
          farmId: farmId,
          goatId: goat.id,
          goatCode: goat.goatCode,
          eventId: event.id,
          event: event,
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: reschedule-all failed: $e');
    }
  }

  /// Writes/updates a Firestore notification record for anything due
  /// today or already overdue, so NotificationScreen has something to
  /// show even if a scheduled OS alarm was missed (e.g. a reboot before
  /// [rescheduleAllForFarm] ran). Idempotent — safe to call every time
  /// the app opens.
  Future<void> runDueCheck(String farmId) async {
    try {
      final upcoming = await FirestoreService.instance.upcomingHealthReminders(
        farmId,
        withinDays: 0, // due today or already overdue only
      );
      final now = DateTime.now();

      for (final entry in upcoming) {
        final goat = entry.key;
        final event = entry.value;
        final dueDate = event.nextDueDate;
        if (dueDate == null) continue;

        final isOverdue = dueDate.isBefore(DateTime(now.year, now.month, now.day));
        final label = event.label.toLowerCase();

        await FirestoreService.instance.addNotification(
          farmId: farmId,
          docId: 'health_${goat.id}_${event.id}_${isOverdue ? 'overdue' : 'due'}',
          type: '${event.type.name}_${isOverdue ? 'overdue' : 'due'}',
          category: 'health',
          priority: isOverdue ? 'critical' : 'important',
          title: isOverdue ? '${event.label} overdue' : '${event.label} due today',
          message: isOverdue
              ? '${goat.goatCode} is overdue for $label.'
              : '${goat.goatCode} is due for $label today.',
          reference: {'goatId': goat.id, 'eventId': event.id},
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: due-check failed: $e');
    }
  }

  // ---------------------------------------------------------------------

  Future<void> _scheduleIfFuture({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (when.isBefore(DateTime.now())) return; // Already passed — skip.

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.channelId,
          NotificationService.channelName,
          channelDescription: NotificationService.channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Required by flutter_local_notifications 18.0.1's top-level
      // zonedSchedule() facade even for an Android-only call — it's an
      // iOS-specific setting (interpreted wall-clock vs. absolute time
      // across timezone/DST changes) that this app never uses on
      // Android, but the parameter is still mandatory at this version.
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      // Inexact timing avoids needing Android 12+'s SCHEDULE_EXACT_ALARM
      // permission — fine for a "due today" reminder that doesn't need
      // to fire at the exact minute.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  /// Deterministic notification id per (event, stage) so scheduling the
  /// same event twice replaces rather than duplicates, and so
  /// [cancelForEvent] can find them again. flutter_local_notifications
  /// ids are 32-bit ints, so this is kept within that range.
  int _notificationId(String eventId, _ReminderStage stage) {
    final hash = eventId.hashCode & 0x0FFFFFFF; // keep well under 2^31
    return hash * 10 + stage.index;
  }
}

enum _ReminderStage { sevenDaysBefore, oneDayBefore, dueToday }