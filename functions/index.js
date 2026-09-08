/**
 * Cross-device push fan-out for MyGoatFarms health notifications.
 *
 * THE PROBLEM THIS SOLVES
 * ------------------------
 * flutter_local_notifications' zonedSchedule() only talks to the phone
 * that scheduled it — it's an on-device OS alarm, never written anywhere
 * Firestore-visible. So when Device A creates a vaccination record with a
 * due date, only Device A's AlarmManager ever learns about it. Device B,
 * even though it's logged into the exact same farm and already has an FCM
 * token saved under farms/{farmId}/notificationTokens/{deviceId}, never
 * gets told anything.
 *
 * These two functions close that gap:
 *
 *  1. onHealthNotificationCreated — the app already writes every "X
 *     recorded" / "X due today" / "X overdue" notification into
 *     farms/{farmId}/notifications/{notificationId} (see
 *     FirestoreService.addNotification / HealthReminderScheduler in the
 *     Flutter app). The moment one of those documents is CREATED (not
 *     updated — see the idempotency note below), this function reads
 *     every registered token for that farm and pushes the same
 *     notification to all of them via FCM. This alone covers "record
 *     just logged" and "due today / overdue at the moment the record was
 *     saved", since the app already writes those to Firestore instantly.
 *
 *  2. scheduledHealthReminderSweep — the ONE thing the app never writes
 *     to Firestore at all is the 7-days-before / 1-day-before advance
 *     reminder (those exist purely as local OS alarms on the creating
 *     device). This runs every 30 minutes, re-derives the same "is
 *     anything entering its 7-day/1-day window right now" check the
 *     Flutter app does client-side (HealthReminderScheduler /
 *     upcomingHealthReminders / upcomingCustomerHealthReminders), and
 *     writes a notification doc the first time a record crosses into
 *     that window — which then triggers function #1 above to fan it out
 *     to every device.
 *
 * IDEMPOTENCY
 * -----------
 * Every doc this writes uses `.create()` with a deterministic ID and
 * swallows the ALREADY_EXISTS error. That guarantees each real-world
 * event (e.g. "vaccination X entered its 7-day window") triggers exactly
 * one Firestore CREATE — and therefore exactly one push — no matter how
 * many times the 30-minute sweep re-checks it afterward. The app's own
 * addNotification() calls for "recorded"/"due today"/"overdue" already
 * follow the same discipline (a merge-write to a fixed docId is only
 * ever a CREATE the first time), so onHealthNotificationCreated will not
 * re-fire for those on later app opens either.
 *
 * DEPLOY
 * ------
 *   cd functions
 *   npm install
 *   firebase deploy --only functions
 *
 * Requires the Firebase project to be on the Blaze (pay-as-you-go) plan
 * — Cloud Scheduler (used by the `schedule` trigger below) isn't
 * available on the free Spark plan. Cost at this app's scale (a handful
 * of farms, a sweep every 30 minutes) is expected to stay within, or very
 * close to, Firebase's free monthly quota for Functions/Scheduler.
 */

const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {logger} = require('firebase-functions');

initializeApp();
const db = getFirestore();

// ---------------------------------------------------------------------
// Shared: push one notification doc's content to every device on a farm
// ---------------------------------------------------------------------

async function pushToFarm(farmId, notification) {
  const tokensSnap = await db
      .collection('farms').doc(farmId)
      .collection('notificationTokens')
      .where('active', '==', true)
      .get();

  const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);

  if (tokens.length === 0) {
    logger.info(`No active tokens for farm ${farmId}, skipping push.`);
    return;
  }

  const message = {
    tokens,
    notification: {
      title: notification.title || 'New notification',
      body: notification.message || 'You have new notifications from the farm.',
    },
    data: {
      category: notification.category || '',
      type: notification.type || '',
      // NotificationService.encodePayload() on the client expects a flat
      // string map — reference fields are already strings, so this
      // round-trips cleanly into the same payload shape the app already
      // decodes when a push notification is tapped.
      ...Object.fromEntries(
          Object.entries(notification.reference || {}).map(([k, v]) => [k, String(v)]),
      ),
    },
    android: {
      notification: {
        channelId: 'mygoatfarms_default_channel',
      },
    },
  };

  const response = await getMessaging().sendEachForMulticast(message);
  logger.info(
      `Farm ${farmId}: pushed to ${tokens.length} device(s), ` +
      `${response.successCount} succeeded, ${response.failureCount} failed.`,
  );

  // Deactivate tokens FCM says are dead (uninstalled app, expired, etc.)
  // so future sweeps stop wasting sends on them.
  const deadTokenDocs = [];
  response.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token') {
      deadTokenDocs.push(tokensSnap.docs[i].ref);
    }
  });
  await Promise.all(deadTokenDocs.map((ref) => ref.set({active: false}, {merge: true})));
}

// ---------------------------------------------------------------------
// 1. Fan out every notification the app already writes to Firestore
// ---------------------------------------------------------------------

exports.onHealthNotificationCreated = onDocumentCreated(
    'farms/{farmId}/notifications/{notificationId}',
    async (event) => {
      const farmId = event.params.farmId;
      const data = event.data.data();
      if (!data) return;

      try {
        await pushToFarm(farmId, data);
      } catch (e) {
        logger.error(`Failed to push notification for farm ${farmId}:`, e);
      }
    },
);

// ---------------------------------------------------------------------
// 2. Advance (7-day / 1-day before) reminders — the one thing that only
//    ever existed as a local, single-device OS alarm until now.
// ---------------------------------------------------------------------

const STAGE_WINDOWS = [
  {suffix: '7d', daysBefore: 7, label: (l) => `${l} coming up`, body: (goat, l) => `${goat} is due for ${l.toLowerCase()} in 7 days.`},
  {suffix: '1d', daysBefore: 1, label: (l) => `${l} tomorrow`, body: (goat, l) => `${goat} is due for ${l.toLowerCase()} tomorrow.`},
];

/** Writes one advance-reminder notification doc exactly once. */
async function writeAdvanceReminder({farmId, docKey, type, title, message, reference}) {
  const ref = db.collection('farms').doc(farmId).collection('notifications').doc(`${docKey}_advance`);
  try {
    await ref.create({
      type,
      category: 'health',
      title,
      message,
      priority: 'normal',
      reference,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    // .create() succeeding means this is a brand-new doc — Firestore's
    // own onDocumentCreated trigger above will pick it up and push it.
  } catch (e) {
    if (e.code === 6 /* ALREADY_EXISTS */) return; // Already sent — normal.
    throw e;
  }
}

/** True if `dueDate` falls inside the [daysBefore] stage window (same
 * calendar day as `today + daysBefore`). */
function isInStageWindow(dueDate, daysBefore) {
  const now = new Date();
  const target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysBefore);
  const due = dueDate.toDate();
  return due.getFullYear() === target.getFullYear() &&
      due.getMonth() === target.getMonth() &&
      due.getDate() === target.getDate();
}

exports.scheduledHealthReminderSweep = onSchedule('every 30 minutes', async () => {
  const horizon = Timestamp.fromDate(new Date(Date.now() + 8 * 24 * 60 * 60 * 1000)); // 8 days out

  // -- Own Farm: farms/{farmId}/ownFarmGoats/{goatId}/healthEvents/{eventId}
  const eventsSnap = await db.collectionGroup('healthEvents')
      .where('nextDueDate', '<=', horizon)
      .get();

  for (const doc of eventsSnap.docs) {
    const data = doc.data();
    const dueDate = data.nextDueDate;
    if (!dueDate) continue;

    for (const stage of STAGE_WINDOWS) {
      if (!isInStageWindow(dueDate, stage.daysBefore)) continue;

      // Path: farms/{farmId}/ownFarmGoats/{goatId}/healthEvents/{eventId}
      const goatRef = doc.ref.parent.parent;
      const farmId = goatRef.parent.parent.id;
      const goatSnap = await goatRef.get();
      const goatCode = goatSnap.data()?.goatCode || 'A goat';
      const label = String(data.type || 'health').replace(/([A-Z])/g, ' $1').trim();
      const labelTitled = label.charAt(0).toUpperCase() + label.slice(1);

      await writeAdvanceReminder({
        farmId,
        docKey: `health_${goatRef.id}_${doc.id}_${stage.suffix}`,
        type: `${data.type}_${stage.suffix}`,
        title: stage.label(labelTitled),
        message: stage.body(goatCode, labelTitled),
        reference: {goatId: goatRef.id, eventId: doc.id},
      });
    }
  }

  // -- Customer Palai: farms/{farmId}/palaiCustomers/{customerId}/goats/{goatId}/{type}Records/{recordId}
  const recordTypes = [
    {collection: 'vaccinationRecords', type: 'vaccination', label: 'Vaccination'},
    {collection: 'hoofCuttingRecords', type: 'hoofCutting', label: 'Hoof cutting'},
    {collection: 'hairTrimmingRecords', type: 'hairTrimming', label: 'Hair trimming'},
  ];

  for (const rt of recordTypes) {
    const recSnap = await db.collectionGroup(rt.collection)
        .where('nextDueDate', '<=', horizon)
        .get();

    for (const doc of recSnap.docs) {
      const data = doc.data();
      const dueDate = data.nextDueDate;
      if (!dueDate) continue;

      for (const stage of STAGE_WINDOWS) {
        if (!isInStageWindow(dueDate, stage.daysBefore)) continue;

        // Path: farms/{farmId}/palaiCustomers/{customerId}/goats/{goatId}/{collection}/{recordId}
        const goatRef = doc.ref.parent.parent;
        const customerRef = goatRef.parent.parent;
        const farmId = customerRef.parent.parent.id;
        const goatSnap = await goatRef.get();
        const goatCode = goatSnap.data()?.goatCode || 'A goat';

        await writeAdvanceReminder({
          farmId,
          docKey: `health_${goatRef.id}_${rt.type}_${doc.id}_${stage.suffix}`,
          type: `${rt.type}_${stage.suffix}`,
          title: stage.label(rt.label),
          message: stage.body(goatCode, rt.label),
          reference: {customerId: customerRef.id, goatId: goatRef.id, recordId: doc.id},
        });
      }
    }
  }

  logger.info('scheduledHealthReminderSweep complete.');
});

// ---------------------------------------------------------------------
// 3. Owner-only notification delete
//
// Server-enforced — not just a hidden button in the UI. A partner
// calling this directly (e.g. by reverse-engineering the app) gets a
// `permission-denied` error no matter what, because the role check
// happens here using the farm document's `authUid` field, which the
// client never controls.
// ---------------------------------------------------------------------

exports.deleteNotification = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const {farmId, notificationId} = request.data || {};
  if (!farmId || !notificationId) {
    throw new HttpsError('invalid-argument', 'farmId and notificationId are required.');
  }

  const farmSnap = await db.collection('farms').doc(farmId).get();
  if (!farmSnap.exists) {
    throw new HttpsError('not-found', 'Farm not found.');
  }

  const isOwner = farmSnap.data().authUid === uid;
  if (!isOwner) {
    throw new HttpsError(
        'permission-denied',
        'Only the farm owner can delete notifications.',
    );
  }

  const notifRef = db.collection('farms').doc(farmId)
      .collection('notifications').doc(notificationId);

  const notifSnap = await notifRef.get();
  if (!notifSnap.exists) {
    throw new HttpsError('not-found', 'Notification not found.');
  }

  await notifRef.delete();
  return {success: true};
});

