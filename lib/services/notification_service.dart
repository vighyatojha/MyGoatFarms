import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'background_refresh.dart';

/// Central, Android-only notification layer for MyGoatFarms.
///
/// Everything here is ON-DEVICE. There is no Firebase Cloud Messaging and
/// no server push. Notifications reach the phone in three ways:
///
///   * Health digest (vaccination / hoof cutting / hair trimming /
///     medicine) — scheduled by HealthReminderScheduler with
///     flutter_local_notifications' zonedSchedule (Android AlarmManager),
///     so it fires even when the app is closed.
///   * "Just happened" events (a record was logged) — shown immediately
///     with [showNow].
///   * Everything written to the farm's Firestore notification feed by
///     ANOTHER device (partner activity, etc.) — picked up by the
///     workmanager job in background_refresh.dart, which runs every few
///     hours while the app is closed and shows them with [showNow]. The
///     same job also rebuilds the health digest so it never runs out
///     and includes records added from other devices.
///
/// This service's own job is:
///
///   1. Ask for notification (+ exact alarm) permission.
///   2. Own the single FlutterLocalNotificationsPlugin instance + default
///      notification channel, shared with HealthReminderScheduler and
///      the background job.
///   3. Expose a stream of "the user tapped a notification" payloads so
///      the app can deep-link to the right screen.
///
/// iOS is explicitly out of scope for now.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId = 'mygoatfarms_default_channel';
  static const String channelName = 'MyGoatFarms Notifications';
  static const String channelDescription =
      'Health, payment, stock and farm activity alerts.';

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  /// Shared with HealthReminderScheduler so both push through — and both
  /// tap-handle through — the exact same plugin instance/channel.
  FlutterLocalNotificationsPlugin get localNotificationsPlugin => _localNotifications;

  /// Emits the payload of a notification whenever the user taps it —
  /// while the app is running, or when the tap launched the app from a
  /// fully closed state. Screens (e.g. MainShell) can listen to this to
  /// navigate to the relevant goat/bill.
  final StreamController<Map<String, String>> _tapController =
  StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onNotificationTap => _tapController.stream;

  bool _initialized = false;

  /// Call once, as early as possible in main() — before runApp — so
  /// zonedSchedule() (used by HealthReminderScheduler) has timezone data
  /// to work with. Also called by the background job, which runs in its
  /// own isolate.
  ///
  /// Hardcoded to Asia/Kolkata since this app is India-only today. If
  /// MyGoatFarms ever ships outside India, replace this with the
  /// `flutter_timezone` package's device-detected zone instead.
  static void initializeTimeZoneData() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }

  /// Call once the user is logged in and `farmId` is known (e.g. right
  /// after reaching MainShell). Safe to call again on every app start —
  /// re-requesting permission is a no-op if already granted/denied.
  Future<void> initForFarm(String farmId) async {
    if (!Platform.isAndroid) return; // Android-only for now.

    await _ensureInitialized();
    await _handleLaunchFromNotification();
    await _requestNotificationPermission();
    await _requestExactAlarmPermission();
  }

  /// For the workmanager background isolate: sets up the plugin and the
  /// channel only. No permission prompts — those need the UI.
  Future<void> initLocalOnly() async {
    if (!Platform.isAndroid) return;
    await _ensureInitialized();
  }

  /// Call on logout so this device stops notifying for the farm/user
  /// that just signed out: cancels every scheduled digest and stops the
  /// background job.
  Future<void> disableForCurrentFarm() async {
    try {
      await _localNotifications.cancelAll();
    } catch (e) {
      debugPrint('NotificationService: failed to cancel scheduled notifications: $e');
    }
    await BackgroundRefresh.stop();
  }

  // -------------------------------------------------------------------
  // Setup
  // -------------------------------------------------------------------

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _initLocalNotifications();
    _initialized = true;
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _tapController.add(_decodePayload(payload));
      },
    );

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// When the app was fully closed and the user opened it by tapping one
  /// of our notifications, onDidReceiveNotificationResponse does NOT
  /// fire — the tap has to be read once on startup instead.
  bool _launchHandled = false;
  Future<void> _handleLaunchFromNotification() async {
    if (_launchHandled) return;
    _launchHandled = true;
    try {
      final details = await _localNotifications.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if ((details?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        _tapController.add(_decodePayload(payload));
      }
    } catch (e) {
      debugPrint('NotificationService: launch details failed: $e');
    }
  }

  /// On Android 13+ this shows the POST_NOTIFICATIONS runtime prompt;
  /// on older Android versions it resolves immediately as granted.
  Future<void> _requestNotificationPermission() async {
    try {
      final granted = await _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      debugPrint('NotificationService: notification permission = $granted');
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
    }
  }

  /// Asks the OS for permission to schedule EXACT alarms (Android 12+).
  ///
  /// Without this, HealthReminderScheduler's digests fall back to
  /// inexact scheduling, which the OS can delay. On Android 13+ this
  /// opens the system "Alarms & reminders" settings screen for the user
  /// to flip on manually — there's no in-app dialog for it, that's an OS
  /// restriction, not a bug here.
  Future<void> _requestExactAlarmPermission() async {
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.canScheduleExactNotifications();
      if (granted == false) {
        await androidPlugin?.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint('NotificationService: exact alarm permission check failed: $e');
    }
  }

  /// Live check of whether this device currently allows exact-alarm
  /// scheduling. HealthReminderScheduler MUST check this before every
  /// zonedSchedule() call and choose its AndroidScheduleMode accordingly
  /// — flutter_local_notifications does NOT throw a catchable error when
  /// exact mode is requested without the permission; it silently logs a
  /// native error and drops the schedule instead.
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return false;
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('NotificationService: canScheduleExactAlarms check failed: $e');
      return false;
    }
  }

  /// Shows an immediate, real OS-level notification (heads-up banner +
  /// tray entry) — for "it just happened" events like a vaccination
  /// being logged, and for new feed items found by the background job.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: data != null ? encodePayload(data) : null,
    );
  }

  // -------------------------------------------------------------------
  // payload <-> String helpers for flutter_local_notifications, which
  // only accepts a plain String payload. Public/static so
  // HealthReminderScheduler encodes payloads the same way for its
  // scheduled notifications.
  // -------------------------------------------------------------------

  static String encodePayload(Map<String, dynamic> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join('&');

  static Map<String, String> _decodePayload(String payload) {
    final result = <String, String>{};
    for (final pair in payload.split('&')) {
      final parts = pair.split('=');
      if (parts.length == 2) result[parts[0]] = parts[1];
    }
    return result;
  }
}