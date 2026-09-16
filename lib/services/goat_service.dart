import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goat_model.dart';

/// Handles the Trading module's Goat Registration (Feature 3) and Goat
/// Stock (Feature 4).
///
/// Collection layout:
///
/// farms/{farmId}/tradingGoats/{goatId}
/// farms/{farmId}/tradingCounters/goatCounter
///
/// Deliberately named `tradingGoats`, not `goats`: Palai's boarded-goat
/// records already live at `customers/{customerId}/goats/{goatId}` and
/// are queried farm-wide via `collectionGroup('goats')` in
/// FirestoreService (allActiveGoatsStream, dueHealthReminderGoatsStream,
/// upcomingCustomerHealthReminders, allCustomerHealthRecordSummaries).
/// A collection group query matches by collection ID regardless of
/// parent path, so a `farms/{farmId}/goats` collection would silently
/// join that same group. Today those queries also filter on `farmId`
/// and `isCheckedOut` — fields Trading goat docs never set — so they
/// wouldn't currently match, but that's relying on every future query
/// against `goats` remembering to add the same filters. Using a
/// distinct collection name removes the landmine entirely, and matches
/// this module's existing `trading*` naming (tradingPurchases,
/// tradingCounters, tradingSummary).
///
/// This mirrors TradingService's layout exactly — including reusing the
/// same `tradingCounters` collection that already holds
/// `purchaseCounter`, rather than introducing a separate top-level
/// `counters` collection, since every other Trading counter already
/// lives under `farms/{farmId}/tradingCounters`.
///
/// Goat IDs are sequential and zero-padded to 4 digits (G-0001, G-0002,
/// ...), matching the PUR-0001 style already used for purchase IDs.
///
/// IMPORTANT: registration is the only place a goat ID is ever created.
/// Nothing in later phases (Own Palai, Sale) should ever generate a new
/// goat ID when moving an existing goat between statuses — see the
/// "No duplicate Goat IDs" note in the phase 2 plan.
class GoatService {
  GoatService._();

  static final GoatService instance = GoatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _goats(String farmId) {
    return _farms().doc(farmId).collection('tradingGoats');
  }

  DocumentReference<Map<String, dynamic>> _goatCounterDoc(String farmId) {
    return _farms().doc(farmId).collection('tradingCounters').doc(
      'goatCounter',
    );
  }

  // -----------------------------------------------------------------------
  // SEQUENTIAL GOAT ID
  // -----------------------------------------------------------------------

  /// Reads and increments `tradingCounters/goatCounter` inside an
  /// already-open [transaction], returning the next goat ID (e.g.
  /// "G-0001").
  ///
  /// Must be called from within the SAME transaction that writes the
  /// goat document and updates the purchase's registeredCount/
  /// pendingCount (Task 2.4), so a failure mid-way never leaves the
  /// counter out of sync with the goats that actually exist. This will
  /// be wired into GoatService.registerGoat() in the next task.
  Future<String> nextGoatIdInTransaction(
      Transaction transaction,
      String farmId,
      ) async {
    final counterRef = _goatCounterDoc(farmId);

    final counterSnap = await transaction.get(counterRef);

    final lastValue =
        (counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0;

    final nextValue = lastValue + 1;

    transaction.set(
      counterRef,
      {'lastValue': nextValue},
      SetOptions(merge: true),
    );

    return 'G-${nextValue.toString().padLeft(4, '0')}';
  }

  // -----------------------------------------------------------------------
  // GET GOAT
  // -----------------------------------------------------------------------

  Future<Goat?> getGoat(String farmId, String goatId) async {
    final doc = await _goats(farmId).doc(goatId).get().timeout(_timeout);

    if (!doc.exists) {
      return null;
    }

    return Goat.fromDoc(doc);
  }
}