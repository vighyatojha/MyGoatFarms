import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/death_record.dart';
import '../models/expense_categories.dart';
import '../models/expense_model.dart';
import '../models/goat_model.dart';
import '../models/trading_purchase_model.dart';
import 'finance_service.dart';
import 'firestore_service.dart';

/// Implements the "Goat Death & Settlement" feature.
///
/// Covers all three cases from the spec:
///
/// * Customer Palai — [recordCustomerPalaiDeath]. The goat's owner is a
///   customer, so the death is settled against that customer's account
///   (credit or debit) — no Finance loss entry.
/// * Own Palai / Available Stock — [recordFarmGoatDeath]. The goat
///   belongs to the farm, so there is no customer settlement; the goat's
///   value is instead recorded as a "Goat Death Loss" expense in
///   Finance.
///
/// The one rule that holds across all three: the goat is never deleted.
/// It is marked dead (re-using the exact fields every other query in
/// this app already filters active goats by — `isCheckedOut` for
/// Customer Palai, `currentStatus` for Trading goats — so no future
/// billing, reminder, or stock query needs to change to stop generating
/// charges for it), its full history stays on the goat document, and a
/// permanent [DeathRecord] is written for the audit trail.
class DeathSettlementService {
  DeathSettlementService._();

  static final DeathSettlementService instance = DeathSettlementService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> get _farms =>
      _db.collection('farms');

  CollectionReference<Map<String, dynamic>> _customers(String farmId) =>
      _farms.doc(farmId).collection('palaiCustomers');

  CollectionReference<Map<String, dynamic>> _goats(
      String farmId,
      String customerId,
      ) =>
      _customers(farmId).doc(customerId).collection('goats');

  CollectionReference<Map<String, dynamic>> _tradingGoats(String farmId) =>
      _farms.doc(farmId).collection('tradingGoats');

  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) =>
      _farms.doc(farmId).collection('tradingPurchases');

  CollectionReference<Map<String, dynamic>> _deathRecords(String farmId) =>
      _farms.doc(farmId).collection('deathRecords');

  CollectionReference<Map<String, dynamic>> _activities(String farmId) =>
      _farms.doc(farmId).collection('activities');

  CollectionReference<Map<String, dynamic>> _bills(String farmId) =>
      _farms.doc(farmId).collection('bills');

  // =========================================================================
  // CUSTOMER PALAI
  // =========================================================================

  /// Records the death of a Customer Palai goat and settles the
  /// customer's account.
  ///
  /// [settlementAmount] may be 0 (no money moves either way — the death
  /// is only recorded). When it is > 0, [direction] must be
  /// [DeathRecord.directionCredit] (customer owes less) or
  /// [DeathRecord.directionDebit] (customer owes more).
  Future<void> recordCustomerPalaiDeath({
    required String farmId,
    required String customerId,
    required String goatId,
    required DateTime deathDate,
    required String reason,
    String notes = '',
    double settlementAmount = 0,
    String? direction,
  }) async {
    if (settlementAmount < 0) {
      throw ArgumentError('Settlement amount cannot be negative.');
    }
    if (settlementAmount > 0 &&
        direction != DeathRecord.directionCredit &&
        direction != DeathRecord.directionDebit) {
      throw ArgumentError(
        'Select whether the settlement is a credit or a debit.',
      );
    }

    final goatRef = _goats(farmId, customerId).doc(goatId);
    final customerRef = _customers(farmId).doc(customerId);
    final deathRecordRef = _deathRecords(farmId).doc();
    final activityRef = _activities(farmId).doc();
    final billRef = settlementAmount > 0 ? _bills(farmId).doc() : null;

    final actor = await FirestoreService.instance.getCurrentActor();

    await _db.runTransaction<void>((transaction) async {
      final goatSnapshot = await transaction.get(goatRef);
      if (!goatSnapshot.exists) {
        throw StateError('Goat no longer exists.');
      }

      final goatData = goatSnapshot.data() ?? {};

      if (goatData['status'] == 'dead') {
        throw StateError('This goat has already been marked dead.');
      }
      if (goatData['isCheckedOut'] == true) {
        throw StateError(
          'This goat has already been checked out and cannot be marked dead.',
        );
      }

      final goatLabel = _customerGoatLabel(goatData);

      final customerSnapshot = await transaction.get(customerRef);
      if (!customerSnapshot.exists) {
        throw StateError('Customer no longer exists.');
      }

      final customerData = customerSnapshot.data() ?? {};
      final customerName = (customerData['name'] ?? '').toString();
      final currentPending =
      (customerData['pendingAmount'] ?? 0).toDouble();

      final isCredit = direction == DeathRecord.directionCredit;
      final newPending = settlementAmount <= 0
          ? currentPending
          : (isCredit
          ? currentPending - settlementAmount
          : currentPending + settlementAmount);

      // ---------------------------------------------------------------
      // Mark the goat dead. Setting isCheckedOut: true re-uses the exact
      // flag every billing/reminder query already filters active goats
      // by (see FirestoreService.allActiveGoatsStream and friends), so
      // this alone stops all future charges for this goat — nothing
      // else in the billing pipeline needs to change.
      // ---------------------------------------------------------------
      transaction.update(goatRef, {
        'status': 'dead',
        'isCheckedOut': true,
        'checkOutDate': Timestamp.fromDate(deathDate),
        'isDead': true,
        'deathDate': Timestamp.fromDate(deathDate),
        'deathReason': reason.trim(),
        'deathNotes': notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (settlementAmount > 0) {
        transaction.update(customerRef, {
          'pendingAmount': newPending,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final now = DateTime.now();
        final billNumber = '${isCredit ? 'DTC' : 'DTD'}-${now.year}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}'
            '-${billRef!.id.substring(0, 6).toUpperCase()}';

        transaction.set(billRef, {
          'billNumber': billNumber,
          'type': isCredit
              ? 'deathSettlementCredit'
              : 'deathSettlementDebit',
          'customerId': customerId,
          'customerName': customerName,
          'goatId': goatId,
          'goatLabel': goatLabel,
          // Credits reduce what the customer owes, so they are recorded
          // as a negative charge — mirrors the pendingAmount arithmetic
          // above and keeps this bill's `newCharges` consistent with
          // every other bill type in this collection.
          'newCharges': isCredit ? -settlementAmount : settlementAmount,
          'amount': settlementAmount,
          'previousPending': currentPending,
          'pendingAfter': newPending,
          'amountPaid': 0,
          'status': 'pending',
          'note': notes.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(deathRecordRef, {
        'goatType': DeathRecord.typeCustomerPalai,
        'goatId': goatId,
        'goatLabel': goatLabel,
        'customerId': customerId,
        'customerName': customerName,
        'deathDate': Timestamp.fromDate(deathDate),
        'reason': reason.trim(),
        'notes': notes.trim(),
        'settlementAmount': settlementAmount,
        if (settlementAmount > 0) 'settlementDirection': direction,
        'customerPendingBefore': currentPending,
        'customerPendingAfter': newPending,
        'farmLossAmount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });

      transaction.set(activityRef, {
        'type': 'goatDeathRecorded',
        'title': 'Goat Death Recorded',
        'subtitle': '$goatLabel · $customerName',
        'module': 'palai',
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });
    }).timeout(_timeout);
  }

  String _customerGoatLabel(Map<String, dynamic> goatData) {
    final tagNumber = (goatData['tagNumber'] ?? '').toString().trim();
    if (tagNumber.isNotEmpty) return tagNumber;

    final goatCode = (goatData['goatCode'] ?? '').toString().trim();
    if (goatCode.isNotEmpty) return goatCode;

    final name = (goatData['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    return 'Goat';
  }

  // =========================================================================
  // OWN PALAI / AVAILABLE STOCK (shared — same Goat model + collection)
  // =========================================================================

  /// Records the death of a farm-owned goat (Own Palai or Available
  /// Stock). There is no customer settlement; the goat's value (its
  /// originating purchase's cost-per-surviving-goat) is instead recorded
  /// as a "Goat Death Loss" expense in Finance.
  Future<void> recordFarmGoatDeath({
    required String farmId,
    required String goatId,
    required DateTime deathDate,
    required String reason,
    String notes = '',
  }) async {
    final goatRef = _tradingGoats(farmId).doc(goatId);
    final deathRecordRef = _deathRecords(farmId).doc();
    final activityRef = _activities(farmId).doc();

    final actor = await FirestoreService.instance.getCurrentActor();

    String goatType = DeathRecord.typeAvailableStock;
    String goatLabel = '';
    double farmLossAmount = 0;

    await _db.runTransaction<void>((transaction) async {
      final goatSnapshot = await transaction.get(goatRef);
      if (!goatSnapshot.exists) {
        throw StateError('Goat no longer exists.');
      }

      final goat = Goat.fromDoc(goatSnapshot);

      if (goat.currentStatus == Goat.statusDead) {
        throw StateError('This goat has already been marked dead.');
      }
      if (!goat.isSellable) {
        throw StateError(
          'Only Available Stock or Own Palai goats can be recorded here.',
        );
      }

      goatType = goat.isOwnPalai
          ? DeathRecord.typeOwnPalai
          : DeathRecord.typeAvailableStock;

      goatLabel = goat.breed.trim().isNotEmpty
          ? '${goat.breed} · ${goatId.substring(0, goatId.length < 6 ? goatId.length : 6).toUpperCase()}'
          : goatId.substring(0, goatId.length < 6 ? goatId.length : 6).toUpperCase();

      if (goat.purchaseId.trim().isNotEmpty) {
        final purchaseSnapshot = await transaction.get(
          _tradingPurchases(farmId).doc(goat.purchaseId),
        );
        if (purchaseSnapshot.exists) {
          final purchase = TradingPurchase.fromDoc(purchaseSnapshot);
          farmLossAmount = purchase.costPerSurvivingGoat;
        }
      }

      // ---------------------------------------------------------------
      // Mark the goat dead. Dead is deliberately NOT in Goat.statusValues
      // (see goat_model.dart), so this goat automatically stops matching
      // isAvailable / isOwnPalai / isSellable / followsFarmHealthSchedule
      // — every stock list, the Sell Goat wizard, and the farm health
      // reminder query already filter on those, so nothing else needs to
      // change for "no future charges" to hold.
      // ---------------------------------------------------------------
      transaction.update(goatRef, {
        'currentStatus': Goat.statusDead,
        'deathDate': Timestamp.fromDate(deathDate),
        'deathReason': reason.trim(),
        'deathNotes': notes.trim(),
      });

      transaction.set(deathRecordRef, {
        'goatType': goatType,
        'goatId': goatId,
        'goatLabel': goatLabel,
        'deathDate': Timestamp.fromDate(deathDate),
        'reason': reason.trim(),
        'notes': notes.trim(),
        'settlementAmount': 0,
        'farmLossAmount': farmLossAmount,
        'createdAt': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });

      transaction.set(activityRef, {
        'type': 'goatDeathRecorded',
        'title': 'Goat Death Recorded',
        'subtitle':
        '$goatLabel · ${goatType == DeathRecord.typeOwnPalai ? 'Own Palai' : 'Available Stock'}',
        'module': 'trading',
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });
    }).timeout(_timeout);

    // Recorded as a separate step, same pattern as
    // TradingService._ensurePurchaseFinanceExpense: FinanceService.addExpense
    // does its own batch (actor lookup + duplicate-check query don't fit
    // inside the transaction above). referenceType/referenceId make this
    // idempotent — safe even if this step is retried.
    if (farmLossAmount > 0) {
      final now = DateTime.now();
      await FinanceService.instance.addExpense(
        farmId,
        ExpenseModel(
          id: '',
          title: 'Goat Death Loss — $goatLabel',
          category: ExpenseCategories.goatDeathLoss,
          amount: farmLossAmount,
          // Not a real cash payment — no money actually left the farm,
          // the goat's value was simply lost. FinancePaymentMethods.credit
          // is exactly the flag every Net Cash Flow / Cash-Online
          // calculation in finance_service.dart already excludes for
          // this reason (see ExpenseModel.isUnpaidCredit).
          paymentMethod: FinancePaymentMethods.credit,
          note: reason.trim(),
          date: deathDate,
          createdAt: now,
          updatedAt: now,
          status: 'active',
          referenceType: 'goatDeath',
          referenceId: deathRecordRef.id,
        ),
      );
    }
  }

  // =========================================================================
  // HISTORY
  // =========================================================================

  /// Farm-wide death history across all three goat types, newest first.
  Stream<List<DeathRecord>> deathHistoryStream(String farmId) {
    return _deathRecords(farmId)
        .orderBy('deathDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DeathRecord.fromDoc).toList());
  }

  /// A single customer's death history (Customer Palai only). Filters
  /// client-side after a plain equality fetch so this never needs a new
  /// composite index.
  Stream<List<DeathRecord>> customerDeathHistoryStream(
      String farmId,
      String customerId,
      ) {
    return _deathRecords(farmId)
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((s) {
      final records = s.docs.map(DeathRecord.fromDoc).toList();
      records.sort((a, b) => b.deathDate.compareTo(a.deathDate));
      return records;
    });
  }
}