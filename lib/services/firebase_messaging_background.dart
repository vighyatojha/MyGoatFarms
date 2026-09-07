import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Background/terminated-state FCM handler.
///
/// IMPORTANT — this function:
///   * MUST be a top-level (or static) function, not a class method.
///   * MUST be annotated with `@pragma('vm:entry-point')` so the Flutter
///     tool doesn't tree-shake it out of a release build — it's only
///     ever called by the Android OS from a separate background isolate,
///     never directly from Dart code, so without the pragma it looks
///     "unused" to the compiler.
///   * Runs in its OWN isolate with no access to any state from the
///     running app (no BuildContext, no existing Firebase app instance,
///     no NotificationService singleton) — that's why it re-initializes
///     Firebase itself below.
///
/// When the message is a plain FCM *notification* message (the normal
/// case for this app — see NotificationService docs), Android already
/// displays the system notification on its own before this handler even
/// runs; this handler is only for reacting to the *data* payload (e.g.
/// updating local state, logging, silent data sync). It intentionally
/// does NOT show its own notification to avoid a duplicate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase.initializeApp() is idempotent — safe to call again here even
  // though the foreground isolate already initialized it, since this
  // handler runs in a separate isolate that starts with no Firebase app.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint(
    'Background FCM message received: '
        'messageId=${message.messageId}, data=${message.data}',
  );

  // Nothing else to do here for now — the notification itself (title,
  // body, tap deep-link) is stored in the message's `notification` /
  // `data` payload and handled by the OS + NotificationService's
  // onMessageOpenedApp listener when the user taps it.
}