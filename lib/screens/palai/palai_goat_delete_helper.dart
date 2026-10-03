import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../services/health_reminder_scheduler.dart';

/// Deletes a Customer Palai goat and EVERYTHING that belongs to it:
///
///  1. On-device scheduled reminders (vaccination / hoof cutting / hair
///     trimming / medicine) — cancelled first, while the record ids are
///     still readable, so a deleted goat never raises an alert.
///  2. The goat document and every subcollection under it — health
///     checkups, vaccination, hoof cutting, hair trimming, medicine,
///     weight records, monthly photos, reports and health events
///     (see [FirestoreService.deletePalaiGoat]).
///  3. Notification-feed entries that reference the goat (best-effort —
///     deleting a notification is owner-only on the server).
///
/// Money records (monthly bills, payments, transactions, death
/// settlements) are the customer's accounting history and are
/// deliberately left untouched.
Future<void> deletePalaiGoatEverywhere(
    String farmId,
    PalaiGoat goat,
    ) async {
  final goatRef = FirebaseFirestore.instance
      .collection('farms')
      .doc(farmId)
      .collection('palaiCustomers')
      .doc(goat.customerId)
      .collection('goats')
      .doc(goat.id);

  // 1) Cancel on-device reminders (best-effort, never blocks the delete).
  const reminderCollections = <String, String>{
    'vaccinationRecords': 'vaccination',
    'hoofCuttingRecords': 'hoofCutting',
    'hairTrimmingRecords': 'hairTrimming',
    'medicineRecords': 'medicine',
  };

  for (final entry in reminderCollections.entries) {
    try {
      final snap = await goatRef
          .collection(entry.key)
          .get()
          .timeout(FirestoreService.timeout);
      for (final doc in snap.docs) {
        await HealthReminderScheduler.instance.cancelForCustomerRecord(
          customerId: goat.customerId,
          goatId: goat.id,
          recordType: entry.value,
          recordId: doc.id,
        );
      }
    } catch (e) {
      debugPrint('deletePalaiGoatEverywhere: reminder cleanup '
          '(${entry.key}) failed: $e');
    }
  }

  // Find notification-feed entries now; delete them after the goat is gone.
  List<String> notificationIds = const [];
  try {
    final notifSnap = await FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('notifications')
        .where('reference.goatId', isEqualTo: goat.id)
        .get()
        .timeout(FirestoreService.timeout);
    notificationIds = notifSnap.docs.map((d) => d.id).toList();
  } catch (e) {
    debugPrint('deletePalaiGoatEverywhere: notification lookup failed: $e');
  }

  // 2) The goat + all of its subcollections. Errors propagate.
  await FirestoreService.instance.deletePalaiGoat(
    farmId,
    goat.customerId,
    goat.id,
  );

  // 3) Notification-feed entries (owner-only on the server → best-effort).
  for (final id in notificationIds) {
    try {
      await FirestoreService.instance.deleteNotification(farmId, id);
    } catch (e) {
      debugPrint('deletePalaiGoatEverywhere: notification $id not '
          'removed: $e');
      break; // Most likely permission-denied for non-owners; stop trying.
    }
  }
}

/// Shared "delete a Customer Palai goat" flow, used by the Goat Profile
/// screen and the Customer Profile goat cards.
///
/// It asks for confirmation, shows a small progress dialog while the goat
/// and all of its saved records (health, vaccination, hoof, hair, medicine,
/// photos, reports) are removed through
/// [FirestoreService.deletePalaiGoat] — the same call the Palai goat list
/// screen uses — and then reports the result with a snackbar.
///
/// Returns `true` only when the goat was actually deleted.
Future<bool> confirmAndDeletePalaiGoat(
    BuildContext context, {
      required String farmId,
      required PalaiGoat goat,
    }) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  final label = goat.goatCode.trim().isNotEmpty
      ? goat.goatCode.trim()
      : (goat.name.trim().isNotEmpty ? goat.name.trim() : 'this goat');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          'Delete goat?',
          style: AppTheme.heading(size: 17),
        ),
        content: Text(
          'Delete $label permanently from the database? This will also '
              'remove all of its health, care, weight, photo and report records.',
          style: AppTheme.body(size: 13, color: AppColors.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTheme.body(
                size: 13,
                color: AppColors.textGrey,
                weight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return false;

  // Block the UI while the deletion runs so it can't be tapped twice.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  try {
    await deletePalaiGoatEverywhere(farmId, goat);

    navigator.pop(); // close progress dialog
    messenger.showSnackBar(
      const SnackBar(content: Text('Goat deleted successfully.')),
    );
    return true;
  } catch (e) {
    navigator.pop(); // close progress dialog
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not delete goat: ${FirestoreService.instance.describeError(e)}',
        ),
      ),
    );
    return false;
  }
}