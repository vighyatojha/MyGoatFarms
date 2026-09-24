import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/health_reminder_settings_model.dart';
import '../models/trading_goat_health_record.dart';
import 'firestore_service.dart';
import 'goat_service.dart';
import 'notification_service.dart';

/// Schedules the "7 days before / 1 day before / due today" health
///
/// reminder notifications described in the notification design doc.
///
/// Covers two record shapes:
///   * Customer Palai's separate vaccination / hoof-cutting /
///     hair-trimming / medicine records (`scheduleCustomerHealthReminder`).
///   * Trading module's Own Palai goats — vaccination / hoof-cutting /
///     hair-trimming / medicine kept in one `healthRecords`
///     subcollection distinguished by a `type` field
///     (`scheduleTradingHealthReminder`). Deliberately reuses this same
///     scheduler and the same farm-wide notification feed instead of a
///     separate mechanism — see the phase 3 plan's Task 1.3.
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
  // Own Palai: apply the farm's Health Reminder Settings to every goat
  // ---------------------------------------------------------------------

  /// Sync passes currently running, keyed by `farmId|goatId-or-*`, so two
  /// callers that overlap (app start fires [rescheduleAllForFarm] and
  /// [runDueCheck] together) share one pass instead of racing.
  final Map<String, Future<void>> _syncInFlight = {};

  /// When each key last finished, used to skip redundant non-forced passes
  /// (app resume, opening a list) that would find nothing new to do.
  final Map<String, DateTime> _syncFinishedAt = {};

  static const Duration _syncCooldown = Duration(seconds: 30);

  /// Puts the farm's Health Reminder Settings (Profile > Health Reminder
  /// Settings) onto every Own Palai goat's Vaccination / Hoof Cutting /
  /// Hair Trimming schedule, then (re)schedules the on-device alarms for
  /// whatever changed and cancels the ones that were switched off.
  ///
  /// This is what makes a date the owner picks in Health Reminder Settings
  /// actually appear on an Own Palai goat's profile, in the Notifications
  /// feed, and in the Pending / Upcoming health lists — see
  /// [FirestoreService.syncOwnPalaiFarmReminders] for the rules.
  ///
  /// Safe to call as often as you like: it is idempotent, overlapping
  /// calls share one pass, and a non-[force]d call within 30 seconds of the
  /// previous one for the same scope is skipped.
  ///
  ///  * [goatId] — sync just that goat (after moving it to Own Palai, or
  ///    when its profile opens). Omit for the whole farm.
  ///  * [force] — bypass the cooldown. Use right after the settings were
  ///    saved or a goat was moved, when there is definitely something new.
  ///    If a pass is already running it finishes first and a fresh one
  ///    follows, so the latest settings always win.
  ///  * [settings] — the just-saved values, to avoid re-reading them.
  ///
  /// Never throws.
  Future<void> syncOwnPalaiFarmReminders(
      String farmId, {
        String? goatId,
        bool force = false,
        HealthReminderSettings? settings,
      }) {
    final key = '$farmId|${goatId ?? '*'}';

    final running = _syncInFlight[key];
    if (running != null) {
      if (!force) return running;
      return running.then((_) => syncOwnPalaiFarmReminders(
        farmId,
        goatId: goatId,
        force: true,
        settings: settings,
      ));
    }

    if (!force) {
      final finished = _syncFinishedAt[key];
      if (finished != null &&
          DateTime.now().difference(finished) < _syncCooldown) {
        return Future.value();
      }
    }

    final future = _runOwnPalaiSync(farmId, goatId, settings).whenComplete(() {
      _syncInFlight.remove(key);
      _syncFinishedAt[key] = DateTime.now();
    });
    _syncInFlight[key] = future;
    return future;
  }

  Future<void> _runOwnPalaiSync(
      String farmId,
      String? goatId,
      HealthReminderSettings? settings,
      ) async {
    try {
      final result = await FirestoreService.instance.syncOwnPalaiFarmReminders(
        farmId,
        onlyGoatId: goatId,
        settings: settings,
      );

      for (final ref in result.cleared) {
        await cancelForTradingRecord(
          goatId: ref.goatId,
          recordType: ref.recordType.name,
          recordId: ref.recordId,
        );
      }

      for (final reminder in result.armed) {
        await scheduleTradingHealthReminder(
          farmId: farmId,
          goatId: reminder.goat.id,
          goatCode: reminder.goat.id, // trading goat id doubles as its code
          recordType: reminder.recordType.name,
          recordId: reminder.recordId,
          label: reminder.recordType.label,
          dueDate: reminder.dueDate,
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: own-palai farm sync failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Farm-wide: re-schedule + due-check across every module
  // ---------------------------------------------------------------------

  /// Re-derives and re-schedules reminders for every Customer-Palai goat's
  /// vaccination / hoof-cutting / hair-trimming records and every Own-Palai
  /// and Wait-on-Delivery (Trading) goat's health records, across the
  /// farm.
  ///
  /// flutter_local_notifications' scheduled alarms are cleared by
  /// Android when the phone reboots and are NOT automatically
  /// re-created — call this once after login / on app start (in
  /// addition to scheduling at creation time) so a reboot doesn't
  /// silently drop upcoming reminders.
  Future<void> rescheduleAllForFarm(String farmId) async {
    // Make sure every Own Palai and Wait on Delivery goat carries the
    // farm's current Health Reminder Settings before its reminders are
    // read back and scheduled.
    await syncOwnPalaiFarmReminders(farmId);

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

    try {
      final upcomingTrading =
      await FirestoreService.instance.upcomingTradingHealthReminders(farmId, withinDays: 60);
      for (final reminder in upcomingTrading) {
        await scheduleTradingHealthReminder(
          farmId: farmId,
          goatId: reminder.goat.id,
          goatCode: reminder.goat.id, // the trading goat's id doubles as its display code (e.g. "G-0001")
          recordType: reminder.recordType.name,
          recordId: reminder.recordId,
          label: reminder.recordType.label,
          dueDate: reminder.dueDate,
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: reschedule-all (trading) failed: $e');
    }
  }

  /// Writes/updates a Firestore notification record for anything due
  /// today or already overdue — Customer Palai and Own Palai (Trading)
  /// health records — so
  /// NotificationScreen has something to show even if a scheduled OS
  /// alarm was missed (e.g. a reboot before [rescheduleAllForFarm] ran).
  /// Idempotent — safe to call every time the app opens.
  Future<void> runDueCheck(String farmId) async {
    // Same reasoning as rescheduleAllForFarm: arm the farm's schedule on
    // every Own Palai goat first, so a due/overdue one gets a notification.
    await syncOwnPalaiFarmReminders(farmId);

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

    try {
      final upcomingTrading =
      await FirestoreService.instance.upcomingTradingHealthReminders(farmId, withinDays: 0);
      for (final reminder in upcomingTrading) {
        await _writeDueOrOverdueNotification(
          farmId: farmId,
          docKey: 'health_trading_${reminder.goat.id}_${reminder.recordType.name}_${reminder.recordId}',
          notificationType: reminder.recordType.name,
          label: reminder.recordType.label,
          goatCode: reminder.goat.id,
          dueDate: reminder.dueDate,
          reference: {'goatId': reminder.goat.id, 'recordId': reminder.recordId},
        );
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: due-check (trading) failed: $e');
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
  // Trading — Own Palai goats (vaccination / hoof cutting / hair
  // trimming / medicine, kept in one `healthRecords` subcollection)
  // ---------------------------------------------------------------------

  /// Schedules (or, if called again for the same record, replaces) the
  /// due-date reminders for one Trading (Own Palai) health record.
  ///
  /// Call this right after [GoatService.addHealthRecord] succeeds,
  /// passing the record id it returned. [recordType] should be
  /// `GoatHealthRecordType.name` — `'vaccination'`, `'hoofCutting'`,
  /// `'hairTrimming'`, or `'medicine'` — matching the Customer Palai
  /// convention above. [dueDate] may be null (no reminder for this
  /// entry) — any previously-scheduled reminders for this record are
  /// then simply cancelled.
  Future<void> scheduleTradingHealthReminder({
    required String farmId,
    required String goatId,
    required String goatCode,
    required String recordType,
    required String recordId,
    required String label,
    required DateTime? dueDate,
  }) async {
    final key = 'trade_${goatId}_${recordType}_$recordId';
    await _scheduleThreeStageReminders(
      farmId: farmId,
      key: key,
      label: label,
      dueDate: dueDate,
      payloadExtras: {
        'category': 'health',
        'type': '${recordType}_due',
        'goatId': goatId,
        'recordId': recordId,
        'source': 'trading',
      },
      goatCode: goatCode,
      notificationTypePrefix: recordType,
      goatId: goatId,
      recordId: recordId,
      notificationDocKeyPrefix: 'health_trading',
    );
  }

  /// Cancels all reminders previously scheduled for one Trading record —
  /// call this if the record is deleted or its due date is cleared.
  Future<void> cancelForTradingRecord({
    required String goatId,
    required String recordType,
    required String recordId,
  }) {
    return cancelForEvent('trade_${goatId}_${recordType}_$recordId');
  }

  /// Cancels every on-device reminder of one Trading goat: its farm-
  /// schedule records and every record logged for it. Call this once the
  /// goat has left the farm (a Wait on Delivery goat that has been picked
  /// up), so a sold goat never raises a vaccination / hoof / hair alert.
  ///
  /// Best-effort and never throws — a record that cannot be read is
  /// skipped, and the farm-schedule ids are always cancelled.
  Future<void> cancelForTradingGoat({
    required String farmId,
    required String goatId,
  }) async {
    final keys = <(String, String)>{
      for (final type in GoatHealthRecordType.values)
        if (GoatHealthRecord.followsFarmSettings(type))
          (type.name, GoatHealthRecord.farmScheduleId(type)),
    };

    try {
      final records = await GoatService.instance
          .healthRecordsStream(farmId: farmId, goatId: goatId)
          .first
          .timeout(const Duration(seconds: 10));

      for (final record in records) {
        keys.add((record.type.name, record.id));
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: could not list records of '
          '$goatId to cancel: $e');
    }

    for (final (recordType, recordId) in keys) {
      try {
        await cancelForTradingRecord(
          goatId: goatId,
          recordType: recordType,
          recordId: recordId,
        );
      } catch (e) {
        debugPrint('HealthReminderScheduler: cancel $goatId/$recordId '
            'failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------
  // Shared internals
  // ---------------------------------------------------------------------

  /// Cancels all reminders previously scheduled under [key] — the
  /// composite key of a Customer Palai or Trading (Own Palai) record.
  Future<void> cancelForEvent(String key) async {
    for (final stage in _ReminderStage.values) {
      await _plugin.cancel(_notificationId(key, stage));
    }
  }

  /// Shared 7-days-before / 1-day-before / due-today scheduling used by
  /// both [scheduleCustomerHealthReminder] and
  /// [scheduleTradingHealthReminder].
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
    // Notification-feed doc key prefix. Defaults to 'health' (Customer
    // Palai); Trading (Own Palai) records pass 'health_trading'.
    String? notificationDocKeyPrefix,
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
      id: _notificationId(key, _ReminderStage.twoDaysBefore),
      when: dueDate.subtract(const Duration(days: 2)),
      title: '$label in 2 days',
      body: '$goatCode is due for $labelLower in 2 days.',
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
        title: "Time for $goatCode's $label",
        body: '$goatCode is due for $labelLower now.',
        payload: payload,
      );
    } else {
      await _scheduleIfFuture(
        id: _notificationId(key, _ReminderStage.dueToday),
        when: dueDate,
        title: "Time for $goatCode's $label",
        body: '$goatCode is due for $labelLower now.',
        payload: payload,
      );
    }

    // Mirror into the Firestore notification feed immediately if this
    // record is already due (including "due earlier today") or overdue,
    // so NotificationScreen reflects it right away instead of waiting
    // for the next app-open due-check. Compared against `now`, not
    // midnight-of-today — due dates can carry a specific time (e.g.
    // "due at 9:42 AM"), and comparing against midnight was the actual
    // bug that delayed this mirror until the day after the due moment
    // had already passed.
    if (!dueDate.isAfter(now)) {
      final reference = <String, String>{'goatId': goatId, 'recordId': recordId};
      if (customerId != null) reference['customerId'] = customerId;
      await _writeDueOrOverdueNotification(
        farmId: farmId,
        docKey:
        '${notificationDocKeyPrefix ?? 'health'}_${goatId}_${notificationTypePrefix}_$recordId',
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
      title: isOverdue ? '$label overdue' : "Time for $goatCode's $label",
      message: isOverdue
          ? '$goatCode is overdue for $labelLower.'
          : '$goatCode is due for $labelLower now.',
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

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationService.channelId,
        NotificationService.channelName,
        channelDescription: NotificationService.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final scheduledTime = tz.TZDateTime.from(when, tz.local);

    // IMPORTANT: flutter_local_notifications does NOT throw a catchable
    // Dart exception when exact scheduling is requested without the
    // exact-alarm permission granted — it logs a native error and
    // silently drops the schedule instead. A try/catch around
    // zonedSchedule() cannot detect that. Checking the live permission
    // status first and picking the matching mode is the only reliable
    // way to make sure the reminder actually gets scheduled either way.
    final exactAllowed = await NotificationService.instance.canScheduleExactAlarms();
    final mode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTime,
        details,
        // Required by flutter_local_notifications 18.0.1's top-level
        // zonedSchedule() facade even for an Android-only call — it's an
        // iOS-specific setting (interpreted wall-clock vs. absolute time
        // across timezone/DST changes) that this app never uses on
        // Android, but the parameter is still mandatory at this version.
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: mode,
        payload: payload,
      );
    } catch (e) {
      // Belt-and-suspenders only — the permission check above is what
      // actually prevents the silent-drop case. If scheduling still
      // throws for some other reason, fall back to inexact rather than
      // losing the reminder entirely.
      debugPrint('HealthReminderScheduler: zonedSchedule failed ($mode), retrying inexact: $e');
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTime,
          details,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }
    }
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

enum _ReminderStage { sevenDaysBefore, twoDaysBefore, oneDayBefore, dueToday }