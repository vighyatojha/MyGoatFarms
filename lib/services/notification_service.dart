import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'firebase_messaging_background.dart';

/// Central, Android-only push-notification layer for MyGoatFarms.
///
/// This is intentionally the ONLY place in the app that talks to FCM /
/// flutter_local_notifications. Screens never send notifications
/// themselves — they just write the underlying data (a vaccination
/// schedule, a payment, a check-out) to Firestore as normal. From there,
/// two separate paths deliver a notification:
///
///   * Event-based, server-driven (payments, low stock, etc.) — a
///     backend (Cloud Functions — not part of this Flutter app) would
///     watch Firestore and call FCM. Not implemented yet; this service
///     only does the client-side half (token management) for that path.
///   * Health due-dates (vaccination / hoof cutting / hair trimming) —
///     scheduled entirely on-device by HealthReminderScheduler using
///     flutter_local_notifications, since there's no backend yet. This
///     is what actually fires while the app is closed today.
///
/// This service's own job is:
///
///   1. Ask for notification permission.
///   2. Get this device's FCM token and keep it saved + fresh in
///      Firestore, scoped to the current farm, so a future backend
///      knows where to send pushes for that farm.
///   3. Own the single FlutterLocalNotificationsPlugin instance + default
///      notification channel, shared with HealthReminderScheduler.
///   4. Show a local heads-up notification when an FCM message arrives
///      while the app is in the FOREGROUND (FCM does not do this on
///      Android by itself).
///   5. Expose a stream of "the user tapped a notification" payloads so
///      the app can deep-link to the right screen — covers taps on both
///      FCM messages and locally-scheduled health reminders, since both
///      go through the same FlutterLocalNotificationsPlugin instance.
///
/// iOS is explicitly out of scope for now.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId = 'mygoatfarms_default_channel';
  static const String channelName = 'MyGoatFarms Notifications';
  static const String channelDescription =
      'Health, payment, stock and farm activity alerts.';

  static const String _deviceIdPrefsKey = 'mgf_device_id';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  /// Shared with HealthReminderScheduler so both push through — and both
  /// tap-handle through — the exact same plugin instance/channel.
  FlutterLocalNotificationsPlugin get localNotificationsPlugin => _localNotifications;

  /// Emits the `data` payload of a notification whenever the user taps
  /// it — whether it was an FCM message (foreground, background, or
  /// terminated) or a locally-scheduled health reminder. Screens (e.g.
  /// MainShell) listen to this to navigate to the relevant goat/bill.
  final StreamController<Map<String, String>> _tapController =
  StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onNotificationTap => _tapController.stream;

  String? _farmId;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;

  /// Call once, as early as possible in main() — before runApp — so
  /// zonedSchedule() (used by HealthReminderScheduler) has timezone data
  /// to work with.
  ///
  /// Hardcoded to Asia/Kolkata since this app is India-only today. If
  /// MyGoatFarms ever ships outside India, replace this with the
  /// `flutter_timezone` package's device-detected zone instead.
  static void initializeTimeZoneData() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }

  /// Call once, as early as possible in main() — before runApp — so the
  /// background handler is registered and a terminated-state tap (the
  /// "cold start" case) isn't missed.
  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Call once the user is logged in and `farmId` is known (e.g. right
  /// after reaching MainShell). Safe to call again on every app start —
  /// it re-requests permission (a no-op if already granted/denied) and
  /// refreshes the saved token.
  Future<void> initForFarm(String farmId) async {
    if (!Platform.isAndroid) return; // Android-only for now.

    _farmId = farmId;

    if (!_initialized) {
      await _initLocalNotifications();
      _listenForForegroundMessages();
      _listenForNotificationOpens();
      _initialized = true;
    }

    await _requestPermissionAndSaveToken();
    await _requestExactAlarmPermission();

    // Keep Firestore's copy of the token current if FCM rotates it
    // (e.g. after an app reinstall or token expiry).
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      _saveToken(newToken);
    });
  }

  /// Call on logout so this device stops receiving pushes meant for the
  /// farm/user that just signed out (see doc section 7 — "Remove/disable
  /// current device token" before Firebase sign-out).
  Future<void> disableForCurrentFarm() async {
    if (_farmId == null) return;
    final deviceId = await _deviceId();
    try {
      await FirebaseFirestore.instance
          .collection('farms')
          .doc(_farmId)
          .collection('notificationTokens')
          .doc(deviceId)
          .update({'active': false, 'disabledAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('NotificationService: failed to disable token on logout: $e');
    }
    _farmId = null;
  }

  // -------------------------------------------------------------------
  // Setup
  // -------------------------------------------------------------------

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

  Future<void> _requestPermissionAndSaveToken() async {
    // On Android 13+ this triggers the POST_NOTIFICATIONS runtime prompt;
    // on older Android versions it resolves immediately as authorized.
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint(
      'NotificationService: permission status = ${settings.authorizationStatus}',
    );

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }
  }

  /// Asks the OS for permission to schedule EXACT alarms (Android 12+).
  ///
  /// Without this, HealthReminderScheduler's due-date reminders fall back
  /// to inexact scheduling, which the OS can delay arbitrarily. On
  /// Android 13+ this opens the system "Alarms & reminders" settings
  /// screen for the user to flip on manually — there's no in-app dialog
  /// for it, that's an OS restriction, not a bug here.
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

  /// Shows an immediate, real OS-level notification (heads-up banner +
  /// tray entry) — for "it just happened" events like a vaccination
  /// being logged. This is what was missing before: those events were
  /// only ever written to the in-app Firestore notification feed, so
  /// nothing appeared unless the user opened the Notifications screen.
  /// Call this from screens right alongside FirestoreService.addNotification.
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
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: data != null ? encodePayload(data) : null,
    );
  }

  // -------------------------------------------------------------------
  // Token persistence — farms/{farmId}/notificationTokens/{deviceId}
  //
  // Keyed by a per-install deviceId (not the token itself) so a single
  // physical device is one document across token rotations, matching the
  // doc's "User -> Devices -> Device A/B/C" model for multi-device farms.
  // -------------------------------------------------------------------

  Future<void> _saveToken(String token) async {
    final farmId = _farmId;
    if (farmId == null) return;

    final deviceId = await _deviceId();

    try {
      await FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId)
          .collection('notificationTokens')
          .doc(deviceId)
          .set({
        'token': token,
        'platform': 'android',
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('NotificationService: failed to save token: $e');
    }
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdPrefsKey);
    if (id == null) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString(_deviceIdPrefsKey, id);
    }
    return id;
  }

  // -------------------------------------------------------------------
  // Foreground display
  // -------------------------------------------------------------------

  void _listenForForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      _localNotifications.show(
        message.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: encodePayload(message.data),
      );
    });
  }

  // -------------------------------------------------------------------
  // Tap handling (background + terminated "cold start")
  // -------------------------------------------------------------------

  void _listenForNotificationOpens() {
    // App was backgrounded (not terminated) and the user tapped the
    // system notification.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _tapController.add(message.data.map((k, v) => MapEntry(k, '$v')));
    });

    // App was fully terminated and launched by tapping the notification.
    // Must be checked explicitly on startup — onMessageOpenedApp alone
    // misses this case.
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        _tapController.add(message.data.map((k, v) => MapEntry(k, '$v')));
      }
    });
  }

  // -------------------------------------------------------------------
  // payload <-> String helpers for flutter_local_notifications, which
  // only accepts a plain String payload (unlike RemoteMessage.data).
  // Public/static so HealthReminderScheduler encodes payloads the same
  // way for its scheduled notifications.
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