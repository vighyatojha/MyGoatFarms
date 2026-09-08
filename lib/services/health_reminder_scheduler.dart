import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/own_farm_models.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

/// Schedules the "7 days before / 1 day before / due today" health
/// reminder notifications described in the notification design doc.
///
/// Covers two record shapes:
///   * Own Farm's unified [HealthEvent] model (`scheduleForEvent`).
///   * Customer Palai's separate vaccination / hoof-cutting /
///     hair-trimming / medicine records, which don't share a model with
///     Own Farm (`scheduleCustomerHealthReminder`).
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

  // ---------------------------------------------------------------------
  // Own Farm
  // ---------------------------------------------------------------------

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
    await _scheduleThreeStageReminders(
      farmId: farmId,
      key: eventId,
      label: event.label,
      dueDate: event.nextDueDate,
      payloadExtras: {
        'category': 'health',
        'type': '${event.type.name}_due',
        'goatId': goatId,
        'eventId': eventId,
      },
      goatCode: goatCode,
      notificationTypePrefix: event.type.name,
      goatId: goatId,
      recordId: eventId,
    );
  }

  /// Re-derives and re-schedules reminders for every Own-Farm goat's
  /// open health events, and every Customer-Palai goat's vaccination /
  /// hoof-cutting / hair-trimming records, across the farm.
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
      debugPrint('HealthReminderScheduler: reschedule-all (own farm) failed: $e');
    }

    try {
      final upcomingCustomer =
          await FirestoreService.instance.upcomingCustomerHealthReminders(farmId, withinDays: 60);
      for (final reminder in upcomingCustomer) {
        await scheduleCustomerHealthReminder(
          farmId: farmId,
          customerId: reminder.goat.customerId,
          goatId: reminder.goat.id,
          goatCode: reminder.goat.goatCode,
          recordType: reminder.recordType,
          recordId: reminder.recordId,
          label: reminder.label,
          dueDate: reminder.dueDate,
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: reschedule-all (customer palai) failed: $e');
    }
  }

  /// Writes/updates a Firestore notification record for anything due
  /// today or already overdue — Own Farm health events AND Customer
  /// Palai vaccination/hoof-cutting/hair-trimming records — so
  /// NotificationScreen has something to show even if a scheduled OS
  /// alarm was missed (e.g. a reboot before [rescheduleAllForFarm] ran).
  /// Idempotent — safe to call every time the app opens.
  Future<void> runDueCheck(String farmId) async {
    try {
      final upcoming = await FirestoreService.instance.upcomingHealthReminders(
        farmId,
        withinDays: 0, // due today or already overdue only
      );

      for (final entry in upcoming) {
        final goat = entry.key;
        final event = entry.value;
        final dueDate = event.nextDueDate;
        if (dueDate == null) continue;

        await _writeDueOrOverdueNotification(
          farmId: farmId,
          docKey: 'health_${goat.id}_${event.id}',
          notificationType: event.type.name,
          label: event.label,
          goatCode: goat.goatCode,
          dueDate: dueDate,
          reference: {'goatId': goat.id, 'eventId': event.id},
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: due-check (own farm) failed: $e');
    }

    try {
      final upcomingCustomer =
          await FirestoreService.instance.upcomingCustomerHealthReminders(farmId, withinDays: 0);
      for (final reminder in upcomingCustomer) {
        await _writeDueOrOverdueNotification(
          farmId: farmId,
          docKey: 'health_${reminder.goat.id}_${reminder.recordType}_${reminder.recordId}',
          notificationType: reminder.recordType,
          label: reminder.label,
          goatCode: reminder.goat.goatCode,
          dueDate: reminder.dueDate,
          reference: {
            'customerId': reminder.goat.customerId,
            'goatId': reminder.goat.id,
            'recordId': reminder.recordId,
          },
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: due-check (customer palai) failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Customer Palai — vaccination / hoof cutting / hair trimming / medicine
  // ---------------------------------------------------------------------

  /// Schedules (or, if called again for the same record, replaces) the
  /// due-date reminders for one Customer-Palai health record.
  ///
  /// Call this right after saving a vaccination / hoof-cutting /
  /// hair-trimming (or medicine course-end) record. [recordType] should
  /// be a short stable key such as `'vaccination'`, `'hoofCutting'`,
  /// `'hairTrimming'`, or `'medicine'` — it's used both for the
  /// notification `type` field and to keep each record's scheduled
  /// alarms distinct. [dueDate] may be null (no reminder cadence set for
  /// this record) — in that case any previously-scheduled reminders for
  /// this record are simply cancelled.
  Future<void> scheduleCustomerHealthReminder({
    required String farmId,
    required String customerId,
    required String goatId,
    required String goatCode,
    required String recordType,
    required String recordId,
    required String label,
    required DateTime? dueDate,
  }) async {
    final key = 'cust_${customerId}_${goatId}_${recordType}_$recordId';
    await _scheduleThreeStageReminders(
      farmId: farmId,
      key: key,
      label: label,
      dueDate: dueDate,
      payloadExtras: {
        'category': 'health',
        'type': '${recordType}_due',
        'customerId': customerId,
        'goatId': goatId,
        'recordId': recordId,
      },
      goatCode: goatCode,
      notificationTypePrefix: recordType,
      goatId: goatId,
      recordId: recordId,
      customerId: customerId,
    );
  }

  /// Cancels all reminders previously scheduled for one Customer-Palai
  /// record — call this if the record is deleted or its due date is
  /// cleared. Uses the same composite key [scheduleCustomerHealthReminder]
  /// derives internally.
  Future<void> cancelForCustomerRecord({
    required String customerId,
    required String goatId,
    required String recordType,
    required String recordId,
  }) {
    return cancelForEvent('cust_${customerId}_${goatId}_${recordType}_$recordId');
  }

  // ---------------------------------------------------------------------
  // Shared internals
  // ---------------------------------------------------------------------

  /// Cancels all reminders previously scheduled under [key] — the raw
  /// event id for Own Farm, or the composite key for Customer Palai.
  Future<void> cancelForEvent(String key) async {
    for (final stage in _ReminderStage.values) {
      await _plugin.cancel(_notificationId(key, stage));
    }
  }

  /// Shared 7-days-before / 1-day-before / due-today scheduling used by
  /// both [scheduleForEvent] and [scheduleCustomerHealthReminder].
  Future<void> _scheduleThreeStageReminders({
    required String farmId,
    required String key,
    required String label,
    required DateTime? dueDate,
    required Map<String, String> payloadExtras,
    required String goatCode,
    required String notificationTypePrefix,
    required String goatId,
    required String recordId,
    String? customerId,
  }) async {
    // Cancel any existing schedule for this record first, so editing a
    // due date doesn't leave stale reminders behind alongside the new
    // ones.
    await cancelForEvent(key);

    if (dueDate == null) return; // No reminder cadence set for this record.

    final labelLower = label.toLowerCase();
    final payload = NotificationService.encodePayload(payloadExtras);

    await _scheduleIfFuture(
      id: _notificationId(key, _ReminderStage.sevenDaysBefore),
      when: dueDate.subtract(const Duration(days: 7)),
      title: '$label coming up',
      body: '$goatCode is due for $labelLower in 7 days.',
      payload: payload,
    );

    await _scheduleIfFuture(
      id: _notificationId(key, _ReminderStage.oneDayBefore),
      when: dueDate.subtract(const Duration(days: 1)),
      title: '$label tomorrow',
      body: '$goatCode is due for $labelLower tomorrow.',
      payload: payload,
    );

    // "Due today" is special: if the record's due date IS today (or
    // already overdue), `dueDate` — normally midnight of that day — has
    // already passed the moment it's later than 00:00, so a plain
    // schedule-for-the-future call would silently do nothing. Fire it
    // right away instead so adding a record with a same-day due date
    // still produces a notification immediately.
    final now = DateTime.now();
    if (!dueDate.isAfter(now)) {
      await _showNow(
        id: _notificationId(key, _ReminderStage.dueToday),
        title: '$label due today',
        body: '$goatCode is due for $labelLower today.',
        payload: payload,
      );
    } else {
      await _scheduleIfFuture(
        id: _notificationId(key, _ReminderStage.dueToday),
        when: dueDate,
        title: '$label due today',
        body: '$goatCode is due for $labelLower today.',
        payload: payload,
      );
    }

    // Mirror into the Firestore notification feed immediately if this
    // record is already due today or overdue, so NotificationScreen
    // reflects it right away instead of waiting for the next app-open
    // due-check.
    if (!dueDate.isAfter(DateTime(now.year, now.month, now.day))) {
      final reference = <String, String>{'goatId': goatId, 'recordId': recordId};
      if (customerId != null) reference['customerId'] = customerId;
      await _writeDueOrOverdueNotification(
        farmId: farmId,
        docKey: customerId != null
            ? 'health_${goatId}_${notificationTypePrefix}_$recordId'
            : 'health_${goatId}_$recordId',
        notificationType: notificationTypePrefix,
        label: label,
        goatCode: goatCode,
        dueDate: dueDate,
        reference: reference,
      );
    }
  }

  Future<void> _writeDueOrOverdueNotification({
    required String farmId,
    required String docKey,
    required String notificationType,
    required String label,
    required String goatCode,
    required DateTime dueDate,
    required Map<String, String> reference,
  }) async {
    final now = DateTime.now();
    final isOverdue = dueDate.isBefore(DateTime(now.year, now.month, now.day));
    final labelLower = label.toLowerCase();

    await FirestoreService.instance.addNotification(
      farmId: farmId,
      docId: '${docKey}_${isOverdue ? 'overdue' : 'due'}',
      type: '${notificationType}_${isOverdue ? 'overdue' : 'due'}',
      category: 'health',
      priority: isOverdue ? 'critical' : 'important',
      title: isOverdue ? '$label overdue' : '$label due today',
      message: isOverdue
          ? '$goatCode is overdue for $labelLower.'
          : '$goatCode is due for $labelLower today.',
      reference: reference,
    );
  }

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

  /// Fires a local notification immediately — used for the "due today"
  /// stage when the due date has already arrived (or passed) by the
  /// time the record is saved, so the person still gets a heads-up
  /// instead of a silently-skipped past-dated schedule.
  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.channelId,
          NotificationService.channelName,
          channelDescription: NotificationService.channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  /// Deterministic notification id per (key, stage) so scheduling the
  /// same record twice replaces rather than duplicates, and so
  /// [cancelForEvent] can find them again. flutter_local_notifications
  /// ids are 32-bit ints, so this is kept within that range.
  int _notificationId(String key, _ReminderStage stage) {
    final hash = key.hashCode & 0x0FFFFFFF; // keep well under 2^31
    return hash * 10 + stage.index;
  }
}

enum _ReminderStage { sevenDaysBefore, oneDayBefore, dueToday }
