import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/health_reminder_settings_model.dart';
import '../models/trading_goat_health_record.dart';
import 'firestore_service.dart';
import 'goat_service.dart';
import 'notification_schedule.dart';
import 'notification_service.dart';

/// Health reminder notifications (vaccination / hoof cutting / hair
/// trimming / medicine).
///
/// HOW NOTIFICATIONS ARE DELIVERED NOW
/// -----------------------------------
/// Earlier, every record had its own OS alarms (7 days / 2 days / 1 day
/// before / due day, all at midnight) and anything already due fired
/// IMMEDIATELY — which happened on every app open, because app start
/// re-ran the scheduling for every due/overdue record.
///
/// Now there is ONE combined "daily digest" notification, delivered 3
/// times a day at RANDOM times picked by [NotificationSchedule.minutesFor]
/// — anywhere between 6 AM and 11 PM, at least 4 hours apart. Each
/// digest lists what is overdue, due today, tomorrow, in 2 days and in
/// 7 days. Opening the app only REBUILDS the upcoming digests from fresh
/// data; it never shows a notification. A day with nothing to report gets
/// no notification at all.
///
/// The in-app Notifications feed (Firestore) is still written as before.
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
/// The digests are scheduled on-device with flutter_local_notifications'
/// zonedSchedule (AlarmManager), so they fire even if the app is closed.
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

  /// Called on app start (MainShell). Rebuilds the next
  /// [NotificationSchedule.daysAhead] days of daily digests (3 a day, random times)
  /// from fresh data. Also re-arms them after a reboot cleared the OS
  /// alarms.
  ///
  /// Shows NO notification itself — this is the fix for "a notification
  /// every time the app is opened".
  Future<void> rescheduleAllForFarm(String farmId) async {
    // Make sure every Available, Own Palai and Wait on Delivery goat
    // carries the farm's current Health Reminder Settings before its
    // reminders are read back.
    await syncOwnPalaiFarmReminders(farmId);
    await refreshDailyDigest(farmId, force: true);
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

    // Keep the scheduled digests in step with what just changed. Cheap
    // when called repeatedly — see the cooldown in [refreshDailyDigest].
    await refreshDailyDigest(farmId);
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

  /// Shared handler used by both [scheduleCustomerHealthReminder] and
  /// [scheduleTradingHealthReminder].
  ///
  /// No longer schedules per-record OS alarms or fires anything
  /// immediately. It:
  ///   1. cancels this record's old-style per-record alarms (left over
  ///      from earlier app versions),
  ///   2. mirrors an already-due/overdue record into the in-app feed,
  ///   3. rebuilds the daily digests so the change shows up
  ///      in the next digest.
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
    await cancelForEvent(key);

    if (dueDate != null && !dueDate.isAfter(DateTime.now())) {
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

    // Many records can be (re)scheduled in a row (e.g. a farm-settings
    // sync); refreshDailyDigest coalesces those into one rebuild.
    unawaited(refreshDailyDigest(farmId, force: true));
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

  // ---------------------------------------------------------------------
  // Daily digest: 3 notifications a day, random times 6 AM - 11 PM, 4 h apart
  // ---------------------------------------------------------------------

  /// Notification ids reserved for the digest:
  /// `_digestIdBase + dayOffset * 10 + slotIndex`. Far away from the
  /// hashed per-record ids, which are multiples of 10 plus 0..3.
  static const int _digestIdBase = 2000000005;

  static const String _legacyCleanupPrefsKey = 'mgf_digest_migrated_v1';
  static const Duration _digestCooldown = Duration(minutes: 5);

  Future<void>? _digestInFlight;
  bool _digestDirty = false;
  DateTime? _digestBuiltAt;
  String? _digestFarmId;

  /// Rebuilds the scheduled digests for the next
  /// [NotificationSchedule.daysAhead] days from the farm's current health
  /// records. Never shows a notification immediately.
  ///
  /// Overlapping calls share one rebuild (with one follow-up if something
  /// changed meanwhile). Without [force], a call within 5 minutes of the
  /// last rebuild for the same farm is skipped. Never throws.
  Future<void> refreshDailyDigest(String farmId, {bool force = false}) {
    final running = _digestInFlight;
    if (running != null) {
      if (force) _digestDirty = true;
      return running;
    }

    if (!force &&
        _digestFarmId == farmId &&
        _digestBuiltAt != null &&
        DateTime.now().difference(_digestBuiltAt!) < _digestCooldown) {
      return Future.value();
    }

    final future = _rebuildDigest(farmId).whenComplete(() {
      _digestInFlight = null;
      _digestBuiltAt = DateTime.now();
      _digestFarmId = farmId;
      if (_digestDirty) {
        _digestDirty = false;
        unawaited(refreshDailyDigest(farmId, force: true));
      }
    });
    _digestInFlight = future;
    return future;
  }

  /// Cancels every scheduled digest — call on logout.
  Future<void> cancelDailyDigest() async {
    for (var day = 0; day <= NotificationSchedule.daysAhead; day++) {
      for (var slot = 0; slot < NotificationSchedule.perDay; slot++) {
        await _plugin.cancel(_digestId(day, slot));
      }
    }
    _digestBuiltAt = null;
  }

  Future<void> _rebuildDigest(String farmId) async {
    try {
      await _cleanUpLegacyAlarmsOnce();

      // Everything due up to 7 days after the last scheduled day, plus
      // everything already overdue (the queries include overdue).
      final horizon = NotificationSchedule.daysAhead + 8;
      final items = <_DigestItem>[];

      try {
        final customer = await FirestoreService.instance
            .upcomingCustomerHealthReminders(farmId, withinDays: horizon);
        for (final r in customer) {
          items.add(_DigestItem(r.goat.goatCode, r.label, r.dueDate));
        }
      } catch (e) {
        debugPrint('HealthReminderScheduler: digest (customer palai) failed: $e');
      }

      try {
        final trading = await FirestoreService.instance
            .upcomingTradingHealthReminders(farmId, withinDays: horizon);
        for (final r in trading) {
          // The trading goat's id doubles as its display code.
          items.add(_DigestItem(r.goat.id, r.recordType.label, r.dueDate));
        }
      } catch (e) {
        debugPrint('HealthReminderScheduler: digest (trading) failed: $e');
      }

      await cancelDailyDigest();

      final now = tz.TZDateTime.now(tz.local);
      final today = DateTime(now.year, now.month, now.day);

      for (var day = 0; day <= NotificationSchedule.daysAhead; day++) {
        final date = today.add(Duration(days: day));
        final content = _digestContentFor(date, items);
        if (content == null) continue; // nothing to report that day

        // Today's 3 random times (same every time for the same date).
        final minutes = NotificationSchedule.minutesFor(date);
        for (var slot = 0; slot < minutes.length; slot++) {
          final when = tz.TZDateTime(tz.local, date.year, date.month,
              date.day, minutes[slot] ~/ 60, minutes[slot] % 60);
          if (!when.isAfter(now)) continue; // slot already passed
          if (NotificationSchedule.isQuietTime(when)) continue; // safety net

          // Clear it 1 minute before the next one (or at 11 PM for the
          // last one), so only one shows in the tray at a time.
          final clearAt = slot + 1 < minutes.length
              ? tz.TZDateTime(tz.local, date.year, date.month, date.day,
              minutes[slot + 1] ~/ 60, minutes[slot + 1] % 60)
              : tz.TZDateTime(tz.local, date.year, date.month, date.day,
              NotificationSchedule.quietStartHour);

          await _scheduleDigest(
            id: _digestId(day, slot),
            when: when,
            visibleFor: clearAt.difference(when) - const Duration(minutes: 1),
            title: content.title,
            body: content.body,
            bigText: content.bigText,
          );
        }
      }
    } catch (e) {
      debugPrint('HealthReminderScheduler: digest rebuild failed: $e');
    }
  }

  /// Earlier versions scheduled up to 4 alarms per record, some at
  /// midnight. Remove them all once after updating so none of them can
  /// still fire. Runs only once per install.
  Future<void> _cleanUpLegacyAlarmsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyCleanupPrefsKey) == true) return;
    await _plugin.cancelAll();
    await prefs.setBool(_legacyCleanupPrefsKey, true);
  }

  int _digestId(int day, int slot) => _digestIdBase + day * 10 + slot;

  /// What the digest for [date] says, or null if there is nothing to say.
  /// Uses the same stages as before: overdue, today, tomorrow, in 2 days,
  /// in 7 days.
  _DigestContent? _digestContentFor(DateTime date, List<_DigestItem> items) {
    final overdue = <_DigestItem>[];
    final today = <_DigestItem>[];
    final tomorrow = <_DigestItem>[];
    final inTwo = <_DigestItem>[];
    final inSeven = <_DigestItem>[];

    for (final item in items) {
      final due = DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day);
      final diff = due.difference(date).inDays;
      if (diff < 0) {
        overdue.add(item);
      } else if (diff == 0) {
        today.add(item);
      } else if (diff == 1) {
        tomorrow.add(item);
      } else if (diff == 2) {
        inTwo.add(item);
      } else if (diff == 7) {
        inSeven.add(item);
      }
    }

    final lines = <String>[];
    void addLine(String heading, List<_DigestItem> list) {
      if (list.isEmpty) return;
      const maxNames = 3;
      final names = list
          .take(maxNames)
          .map((i) => '${i.goatCode} ${i.label.toLowerCase()}')
          .join(', ');
      final more = list.length > maxNames ? ' +${list.length - maxNames} more' : '';
      lines.add('$heading: $names$more');
    }

    addLine('Overdue', overdue);
    addLine('Due today', today);
    addLine('Tomorrow', tomorrow);
    addLine('In 2 days', inTwo);
    addLine('In 7 days', inSeven);
    if (lines.isEmpty) return null;

    final urgent = overdue.length + today.length;
    final title = urgent > 0
        ? '$urgent goat health task${urgent == 1 ? '' : 's'} need attention'
        : 'Upcoming goat health tasks';

    return _DigestContent(
      title: title,
      body: lines.first,
      bigText: lines.join('\n'),
    );
  }

  Future<void> _scheduleDigest({
    required int id,
    required tz.TZDateTime when,
    required Duration visibleFor,
    required String title,
    required String body,
    required String bigText,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationService.channelId,
        NotificationService.channelName,
        channelDescription: NotificationService.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(bigText),
        // Auto-remove before the next one arrives (see caller).
        timeoutAfter: visibleFor.inMilliseconds,
      ),
    );

    final payload = NotificationService.encodePayload(
      {'category': 'health', 'type': 'health_digest'},
    );

    // flutter_local_notifications silently drops an exact schedule when
    // the exact-alarm permission is missing, so pick the mode up front.
    final exactAllowed = await NotificationService.instance.canScheduleExactAlarms();
    final mode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: mode,
        payload: payload,
      );
    } catch (e) {
      debugPrint('HealthReminderScheduler: digest schedule failed ($mode): $e');
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }
    }
  }

  /// Id scheme of the OLD per-record alarms. Kept only so
  /// [cancelForEvent] can remove alarms an older app version scheduled.
  int _notificationId(String key, _ReminderStage stage) {
    final hash = key.hashCode & 0x0FFFFFFF; // keep well under 2^31
    return hash * 10 + stage.index;
  }
}

enum _ReminderStage { sevenDaysBefore, twoDaysBefore, oneDayBefore, dueToday }

class _DigestItem {
  final String goatCode;
  final String label;
  final DateTime dueDate;
  _DigestItem(this.goatCode, this.label, this.dueDate);
}

class _DigestContent {
  final String title;
  final String body;
  final String bigText;
  _DigestContent({required this.title, required this.body, required this.bigText});
}