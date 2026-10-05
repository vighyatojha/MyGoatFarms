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
 *     upcomingCustomerHealthReminders / upcomingTradingHealthReminders), and
 *     writes a notification doc the first time a record crosses into
 *     that window — which then triggers function #1 above to fan it out
 *     to every device. Covers two sources: Customer Palai's three
 *     `*Records` collections and Trading's single `healthRecords`
 *     collection for Own Palai goats.
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

  // -- Own Palai (Trading): farms/{farmId}/tradingGoats/{goatId}/healthRecords/{recordId}
  //
  // Phase 3, Task 1.3. Unlike Customer Palai above, Trading keeps all
  // four health types (vaccination, hoofCutting, hairTrimming,
  // medicine) in ONE `healthRecords` collection per goat, distinguished
  // by a `type` field — see the phase 3 plan (Section 1) and
  // GoatHealthRecord in the Flutter app. So this is a single
  // collectionGroup query rather than one per type.
  //
  // Trading goat docs have no separate `goatCode` field — the document
  // ID itself IS the display code (e.g. "G-0001"), so this skips the
  // extra goat-doc read the other two blocks need.
  const ownPalaiHealthSnap = await db.collectionGroup('healthRecords')
      .where('nextDueDate', '<=', horizon)
      .get();

  for (const doc of ownPalaiHealthSnap.docs) {
    const data = doc.data();
    const dueDate = data.nextDueDate;
    if (!dueDate) continue;

    // Path: farms/{farmId}/tradingGoats/{goatId}/healthRecords/{recordId}
    const goatRef = doc.ref.parent.parent;
    const farmId = goatRef.parent.parent.id;
    const goatCode = goatRef.id;
    const label = String(data.type || 'health').replace(/([A-Z])/g, ' $1').trim();
    const labelTitled = label.charAt(0).toUpperCase() + label.slice(1);

    for (const stage of STAGE_WINDOWS) {
      if (!isInStageWindow(dueDate, stage.daysBefore)) continue;

      await writeAdvanceReminder({
        farmId,
        docKey: `ownpalai_health_${goatRef.id}_${doc.id}_${stage.suffix}`,
        type: `ownPalai_${data.type}_${stage.suffix}`,
        title: stage.label(labelTitled),
        message: stage.body(goatCode, labelTitled),
        reference: {goatId: goatRef.id, recordId: doc.id},
      });
    }
  }

  logger.info('scheduledHealthReminderSweep complete.');
});

// ---------------------------------------------------------------------
// 3. Admin-only farm deletion
//
// Farm deletion is deliberately handled by a callable Cloud Function,
// not by a browser-side Firestore delete. This lets us verify the caller
// against /admins/{uid} and recursively remove the farm's subcollections
// without leaving the farm's operational data orphaned.
//
// The owner's Firebase Auth account is NOT deleted here. This removes the
// farm and its farm data; if the same email is registered again later, the
// normal registration flow can create a new farm.
// ---------------------------------------------------------------------

exports.deleteFarm = onCall(
    {
      region: 'us-central1',
      timeoutSeconds: 540,
      memory: '1GiB',
    },
    async (request) => {
      const uid = request.auth?.uid;
      const farmId = String(request.data?.farmId || '').trim();

      if (!uid) {
        throw new HttpsError(
            'unauthenticated',
            'Admin sign-in is required.',
        );
      }

      if (!farmId) {
        throw new HttpsError(
            'invalid-argument',
            'Farm ID is required.',
        );
      }

      let stage = 'ADMIN_CHECK';

      try {
        // Keep the same authorization source used by the admin website.
        const adminSnap = await db.collection('admins').doc(uid).get();
        if (!adminSnap.exists) {
          throw new HttpsError(
              'permission-denied',
              'This account is not authorized as an admin.',
          );
        }

        stage = 'FARM_LOOKUP';

        const farmRef = db.collection('farms').doc(farmId);
        const farmSnap = await farmRef.get();

        if (!farmSnap.exists) {
          throw new HttpsError(
              'not-found',
              'Farm ' + farmId + ' was not found.',
          );
        }

        const farmData = farmSnap.data() || {};
        const mobileNumber = String(
            farmData.mobileNumber ??
            farmData.ownerMobile ??
            farmData.phone ??
            '',
        ).trim();

        stage = 'PAYMENT_CLEANUP';

        const paymentsSnap = await db.collection('subscriptionPayments')
            .where('farmId', '==', farmId)
            .get();

        if (!paymentsSnap.empty) {
          // Use small batches so a large payment history cannot exceed
          // Firestore's 500-write batch limit.
          for (let i = 0; i < paymentsSnap.docs.length; i += 450) {
            const batch = db.batch();
            const chunk = paymentsSnap.docs.slice(i, i + 450);
            for (const payment of chunk) {
              batch.delete(payment.ref);
            }
            await batch.commit();
          }
        }

        stage = 'MOBILE_INDEX_CLEANUP';

        if (mobileNumber) {
          const mobileRef = db.collection('mobileIndex').doc(mobileNumber);
          const mobileSnap = await mobileRef.get();

          if (mobileSnap.exists &&
              mobileSnap.data()?.farmId === farmId) {
            await mobileRef.delete();
          }
        }

        stage = 'FARM_RECURSIVE_DELETE';

        // Admin SDK bypasses Firestore client rules here.
        // This removes the farm document and nested subcollections.
        await db.recursiveDelete(farmRef);

        logger.info('Farm deleted successfully', {
          farmId,
          adminUid: uid,
        });

        return {
          success: true,
          farmId,
        };
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }

        logger.error('deleteFarm failed', {
          stage,
          farmId,
          adminUid: uid,
          error: error?.message || String(error),
          stack: error?.stack || null,
        });

        throw new HttpsError(
            'internal',
            `Farm deletion failed at ${stage}: ` +
              (error?.message || 'Unknown server error.'),
        );
      }
    },
);
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

// ---------------------------------------------------------------------
// 4. One-time backfill: mobileIndex/{mobileNumber} -> {farmId}
//
// Farms registered before createFarm started writing mobileIndex have no
// index entry, so the "mobile number already registered" check misses
// them. Admin-only, idempotent, and never overwrites an existing entry.
//
//   data: { dryRun: true }   (default) -> only counts, writes nothing
//   data: { dryRun: false }             -> creates the missing entries
//
// Farms whose number is already indexed to a DIFFERENT farm are reported
// as `conflicts` (real duplicate numbers) and left untouched.
// ---------------------------------------------------------------------

exports.backfillMobileIndex = onCall(
    {
      region: 'us-central1',
      timeoutSeconds: 540,
      memory: '512MiB',
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) {
        throw new HttpsError('unauthenticated', 'Admin sign-in is required.');
      }

      const adminSnap = await db.collection('admins').doc(uid).get();
      if (!adminSnap.exists) {
        throw new HttpsError(
            'permission-denied',
            'This account is not authorized as an admin.',
        );
      }

      // Only an explicit `false` writes anything.
      const dryRun = !(request.data && request.data.dryRun === false);

      const stats = {
        dryRun,
        farmsScanned: 0,
        created: 0,
        alreadyIndexed: 0,
        skippedNoMobile: 0,
        conflicts: [],
      };

      const PAGE = 300;
      let lastDoc = null;

      for (;;) {
        let q = db.collection('farms')
            .orderBy('__name__')
            .limit(PAGE);
        if (lastDoc) q = q.startAfter(lastDoc);

        const page = await q.get();
        if (page.empty) break;

        const batch = db.batch();
        let batchWrites = 0;

        for (const farmDoc of page.docs) {
          stats.farmsScanned++;
          const data = farmDoc.data() || {};
          const mobile = String(
              data.mobileNumber ?? data.ownerMobile ?? data.phone ?? '',
          ).trim();

          if (!mobile) {
            stats.skippedNoMobile++;
            continue;
          }

          const indexRef = db.collection('mobileIndex').doc(mobile);
          const indexSnap = await indexRef.get();

          if (indexSnap.exists) {
            if (indexSnap.data()?.farmId === farmDoc.id) {
              stats.alreadyIndexed++;
            } else if (stats.conflicts.length < 50) {
              stats.conflicts.push({
                mobile,
                farmId: farmDoc.id,
                indexedTo: indexSnap.data()?.farmId ?? null,
              });
            }
            continue;
          }

          stats.created++;
          if (!dryRun) {
            batch.set(indexRef, {
              farmId: farmDoc.id,
              authUid: data.authUid ?? null,
              createdAt: FieldValue.serverTimestamp(),
              backfilled: true,
            });
            batchWrites++;
          }
        }

        if (batchWrites > 0) await batch.commit();
        lastDoc = page.docs[page.docs.length - 1];
        if (page.size < PAGE) break;
      }

      logger.info('backfillMobileIndex finished', {adminUid: uid, ...stats});
      return stats;
    },
);
// ---------------------------------------------------------------------
// 5. Login / sign-up lookups by mobile number (no sign-in required)
//
// Replace the public Firestore queries the app used before sign-in:
//   farms.where('mobileNumber', ==, n).limit(1)
//   collectionGroup('partners').where('mobileNumber', ==, n).limit(1)
//   mobileIndex/{n}.get()
// Those needed public security rules, and a public `list` rule can be
// abused to page through every farm and partner document. These
// functions run with admin access and return ONLY the single value the
// login / sign-up screen needs — never the farm or partner document.
//
// The number must be an exact match (same as the old queries), and is
// only accepted as 6–15 digits (an optional leading '+' is allowed), so
// a caller cannot send ranges or wildcards.
// ---------------------------------------------------------------------

const MOBILE_PATTERN = /^\+?[0-9]{6,15}$/;

function readMobile(request) {
  const raw = request.data && request.data.mobileNumber;
  const mobile = typeof raw === 'string' ? raw.trim() : '';

  if (!MOBILE_PATTERN.test(mobile)) {
    throw new HttpsError('invalid-argument', 'Enter a valid mobile number.');
  }

  return mobile;
}

// Login: mobile number -> the email to sign in with, or null.
// Owners first, then partners — exactly the order the app used before.
exports.resolveLoginEmail = onCall(
    {region: 'us-central1'},
    async (request) => {
      const mobile = readMobile(request);

      const ownerSnap = await db.collection('farms')
          .where('mobileNumber', '==', mobile)
          .limit(1)
          .get();

      if (!ownerSnap.empty) {
        const email = String(ownerSnap.docs[0].get('email') || '').trim();
        if (email) return {email};
      }

      const partnerSnap = await db.collectionGroup('partners')
          .where('mobileNumber', '==', mobile)
          .limit(1)
          .get();

      if (!partnerSnap.empty) {
        const email = String(partnerSnap.docs[0].get('email') || '').trim();
        if (email) return {email};
      }

      return {email: null};
    },
);

// Sign-up: is this mobile number already registered to a farm?
exports.isMobileRegistered = onCall(
    {region: 'us-central1'},
    async (request) => {
      const mobile = readMobile(request);
      const snap = await db.collection('mobileIndex').doc(mobile).get();
      return {registered: snap.exists};
    },
);