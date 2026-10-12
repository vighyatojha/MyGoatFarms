import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'firestore_service.dart';
import 'health_reminder_scheduler.dart';
import 'notification_schedule.dart';
import 'notification_service.dart';

/// Keeps notifications working while the app is CLOSED — without
/// Firebase Cloud Messaging or any server.
///
/// Android's WorkManager runs [backgroundRefreshDispatcher] about every
/// [BackgroundRefresh.frequency], even when the app has been swiped
/// away. Each run:
///
///   1. Rebuilds the health digest (HealthReminderScheduler), so
///      * the next 7 days are always scheduled, even if the app hasn't
///        been opened for weeks, and
///      * records added from ANOTHER device (a partner's phone) show up
///        in this phone's digest without opening the app.
///   2. Reads the farm's Firestore notification feed and shows anything
///      new as a phone notification (partner activity, etc.). Health
///      items are skipped there — the digest already covers them.
///
/// Respects the same quiet hours as the rest of the app
/// (NotificationSchedule: nothing between 11 PM and 6 AM).
///
/// Note: WorkManager timing is decided by Android (battery, network), so
/// a run can be late. The health digest itself still fires at its exact
/// times through AlarmManager — this job only keeps it up to date.
class BackgroundRefresh {
  BackgroundRefresh._();

  static const String taskName = 'mgf_background_refresh';
  static const Duration frequency = Duration(hours: 3);

  static const String _lastSeenKey = 'mgf_bg_last_seen_notification_ms';

  /// Call once in main(), before anything else uses Workmanager.
  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Workmanager().initialize(backgroundRefreshDispatcher);
    } catch (e) {
      debugPrint('BackgroundRefresh: initialize failed: $e');
    }
  }

  /// Call once the user is logged in (MainShell). Safe to call on every
  /// app start — `keep` leaves an already-registered job untouched.
  static Future<void> start() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: frequency,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('BackgroundRefresh: start failed: $e');
    }
  }

  /// Call on logout.
  static Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Workmanager().cancelByUniqueName(taskName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastSeenKey);
    } catch (e) {
      debugPrint('BackgroundRefresh: stop failed: $e');
    }
  }
}

/// Entry point Android calls in a separate background isolate.
///
/// MUST stay top-level and keep `@pragma('vm:entry-point')`, otherwise a
/// release build strips it out and the job silently never runs.
@pragma('vm:entry-point')
void backgroundRefreshDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // This isolate starts empty: no Firebase, no timezone data, no
      // initialized notification plugin. Set all of them up again.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      NotificationService.initializeTimeZoneData();
      await NotificationService.instance.initLocalOnly();

      // Wait for the saved login to be restored in this isolate.
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null) return true; // logged out → nothing to do

      final farm = await FirestoreService.instance.getFarmForUser(user.uid);
      if (farm == null) return true;
      final isOwner = farm.authUid == user.uid;

      // 1. Keep the 3-a-day health digest fresh.
      await HealthReminderScheduler.instance.rescheduleAllForFarm(farm.id);

      // 2. Show new non-health feed items.
      await _showNewFeedItems(farm.id, isOwner: isOwner);

      return true;
    } catch (e) {
      debugPrint('BackgroundRefresh: run failed: $e');
      return false; // Android retries later with backoff
    }
  });
}

Future<void> _showNewFeedItems(String farmId, {required bool isOwner}) async {
  final prefs = await SharedPreferences.getInstance();
  final lastSeen = prefs.getInt(BackgroundRefresh._lastSeenKey);
  final now = DateTime.now().millisecondsSinceEpoch;

  // First run on this install: only set a starting point, so the user
  // isn't flooded with every old notification at once.
  if (lastSeen == null) {
    await prefs.setInt(BackgroundRefresh._lastSeenKey, now);
    return;
  }

  // Quiet hours: don't notify and don't move lastSeen, so whatever came
  // in overnight is shown on the first run after 6 AM.
  if (NotificationSchedule.isQuietTime(tz.TZDateTime.now(tz.local))) return;

  final snap = await FirebaseFirestore.instance
      .collection('farms')
      .doc(farmId)
      .collection('notifications')
      .where('createdAt',
      isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastSeen))
      .orderBy('createdAt')
      .limit(20)
      .get();

  var newest = lastSeen;
  for (final doc in snap.docs) {
    final d = doc.data();
    final created = (d['createdAt'] as Timestamp?)?.millisecondsSinceEpoch;
    if (created != null && created > newest) newest = created;

    final category = (d['category'] ?? '').toString();

    // Health items are already in the daily digest — don't notify twice.
    if (category == 'health') continue;

    // Partner-activity entries are written FOR the owner. A partner's
    // own phone shouldn't be told about what that partner just did.
    if (category == 'activity' && !isOwner) continue;

    await NotificationService.instance.showNow(
      id: doc.id.hashCode & 0x7FFFFFFF,
      title: (d['title'] ?? 'MyGoatFarms').toString(),
      body: (d['message'] ?? '').toString(),
      data: {
        'category': category,
        'type': (d['type'] ?? '').toString(),
        'notificationId': doc.id,
      },
    );
  }

  await prefs.setInt(BackgroundRefresh._lastSeenKey, newest);
}