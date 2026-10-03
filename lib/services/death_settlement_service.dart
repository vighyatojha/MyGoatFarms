import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/death_record.dart';
import '../models/expense_categories.dart';
import '../models/expense_model.dart';
import '../models/goat_model.dart';
import '../models/trading_purchase_model.dart';
import 'finance_service.dart';
import 'firestore_service.dart';
import 'image_service.dart';
import 'payment_allocation_service.dart';
import '../utils/billing_ledger.dart';
import '../utils/palai_proration.dart';

/// Implements the "Goat Death & Settlement" feature.
///
/// Covers all three cases from the spec:
///
/// * Customer Palai — [recordCustomerPalaiDeath]. The goat's owner is a
///   customer; the farm owner enters what was pending for this specific
///   goat and what the customer will actually pay, and any waived gap
///   is posted as a "Goat Death Loss" expense in Finance — same as the
///   farm-goat case below.
/// * Own Palai / Available Stock — [recordFarmGoatDeath]. The goat
///   belongs to the farm, so there is no customer settlement; a
///   manually-entered loss amount is instead recorded as a "Goat Death
///   Loss" expense in Finance.
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
  /// customer's account against this one goat specifically.
  ///
  /// [goatPendingCharge] is what was owed for this particular goat (the
  /// farm owner enters this — the customer's combined `pendingAmount`
  /// may cover other goats too, so it isn't read automatically).
  /// [customerAmountToPay] is what the customer is actually being asked
  /// to pay for it. Whatever gap is waived between the two
  /// (`goatPendingCharge - customerAmountToPay`, floored at 0) is
  /// recorded as a "Goat Death Loss" expense in Finance — paying in
  /// full means no loss; paying nothing means the whole charge is lost.
  ///
  /// STATEMENT BILLING: [unbilledCharge] is the Palai for the days since
  /// this goat was last charged, up to its death date (worked out by
  /// MonthlyStatementEngine.unbilledChargeFor and editable by the owner).
  /// It is added to what the customer owes, the goat's billedThroughDate
  /// moves to the death date so no statement charges those days again,
  /// and any waived amount reduces the customer's unpaid months oldest
  /// first, so the monthly bills and pendingAmount always agree.
  Future<void> recordCustomerPalaiDeath({
    required String farmId,
    required String customerId,
    required String goatId,
    required DateTime deathDate,
    required String reason,
    String notes = '',
    double goatPendingCharge = 0,
    double customerAmountToPay = 0,
    double unbilledCharge = 0,
  }) async {
    if (unbilledCharge < 0) {
      throw ArgumentError('Unbilled charge cannot be negative.');
    }
    if (goatPendingCharge < 0) {
      throw ArgumentError('Pending charge cannot be negative.');
    }
    if (customerAmountToPay < 0) {
      throw ArgumentError('Amount to pay cannot be negative.');
    }

    final goatRef = _goats(farmId, customerId).doc(goatId);
    final customerRef = _customers(farmId).doc(customerId);
    final deathRecordRef = _deathRecords(farmId).doc();
    final activityRef = _activities(farmId).doc();
    final hasSettlement = goatPendingCharge > 0 ||
        customerAmountToPay > 0 ||
        unbilledCharge > 0;
    final billRef = hasSettlement ? _bills(farmId).doc() : null;

    // Found before the transaction, re-read inside it (see PalaiLedger).
    final ledgerBillRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);

    final actor = await FirestoreService.instance.getCurrentActor();

    String goatLabel = '';
    double currentPending = 0;
    double newPending = 0;
    double farmLossAmount = 0;
    List<Map<String, dynamic>> waiverAllocations = const [];

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

      goatLabel = _customerGoatLabel(goatData);

      final customerSnapshot = await transaction.get(customerRef);
      if (!customerSnapshot.exists) {
        throw StateError('Customer no longer exists.');
      }

      final ledger =
      await PalaiLedger.instance.read(transaction, ledgerBillRefs);

      final customerData = customerSnapshot.data() ?? {};
      final customerName = (customerData['name'] ?? '').toString();
      currentPending = (customerData['pendingAmount'] ?? 0).toDouble();

      // The goat's own charge comes out of the customer's combined
      // balance in full, and whatever the customer is actually being
      // asked to pay for it goes back in — the gap between the two is
      // what gets waived (see farmLossAmount below). Every other goat
      // the customer has, and every other charge already in their
      // pendingAmount, is untouched.
      //
      // The goat's total = what was already billed for it and still
      // pending + its unbilled days. Adding the unbilled days and taking
      // off the waived part nets out to the same formula as before.
      final goatTotal = goatPendingCharge + unbilledCharge;
      final waived = roundMoney(goatTotal - customerAmountToPay);

      newPending = roundMoney(
        (currentPending - goatPendingCharge + customerAmountToPay)
            .clamp(0, double.infinity)
            .toDouble(),
      );

      farmLossAmount = waived > 0 ? waived : 0.0;

      // The waiver first cancels the unbilled days (never on any bill);
      // only the rest reduces billed months, oldest first. A waiver is not
      // a payment, so it is not recorded on the statement's Paid amount.
      final waivedFromBills = roundMoney(
        (waived - unbilledCharge).clamp(0, double.infinity).toDouble(),
      );
      final ledgerWriter = LedgerWriter();
      final waiver = waivedFromBills > 0
          ? PalaiLedger.instance.reduceDues(
        writer: ledgerWriter,
        ledger: ledger,
        amount: waivedFromBills,
        pendingBefore: currentPending,
        recordOnStatement: false,
      )
          : null;
      waiverAllocations =
          waiver?.allocations.map((a) => a.toMap()).toList() ?? const [];
      ledgerWriter.flush(transaction);

      // Never move billedThroughDate backwards (a statement may already
      // cover days past the death date if the death is recorded late).
      final death = palaiDateOnly(deathDate);
      final storedBilled = goatData['billedThroughDate'] is Timestamp
          ? (goatData['billedThroughDate'] as Timestamp).toDate()
          : null;
      final billedThrough =
      storedBilled != null && storedBilled.isAfter(death)
          ? palaiDateOnly(storedBilled)
          : death;

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
        'billedThroughDate': Timestamp.fromDate(billedThrough),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (hasSettlement) {
        transaction.update(customerRef, {
          'pendingAmount': newPending,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final now = DateTime.now();
        final billNumber = 'DTH-${now.year}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}'
            '-${billRef!.id.substring(0, 6).toUpperCase()}';

        transaction.set(billRef, {
          'billNumber': billNumber,
          'type': 'deathSettlement',
          'customerId': customerId,
          'customerName': customerName,
          'goatId': goatId,
          'goatLabel': goatLabel,
          // Removing this goat's full charge and adding back only what
          // the customer will actually pay nets out to the same delta
          // as (customerAmountToPay - goatPendingCharge) — negative
          // when part of the charge was waived, keeping this bill's
          // `newCharges` consistent with every other bill type in this
          // collection.
          'newCharges': customerAmountToPay - goatPendingCharge,
          'goatPendingCharge': goatPendingCharge,
          'unbilledCharge': unbilledCharge,
          'customerAmountToPay': customerAmountToPay,
          'farmLossAmount': farmLossAmount,
          'waiverAllocations': waiverAllocations,
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
        'goatPendingCharge': goatPendingCharge,
        'unbilledCharge': unbilledCharge,
        'customerAmountToPay': customerAmountToPay,
        'customerPendingBefore': currentPending,
        'customerPendingAfter': newPending,
        'farmLossAmount': farmLossAmount,
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

    // Recorded as a separate step, same pattern as recordFarmGoatDeath
    // below (and TradingService._ensurePurchaseFinanceExpense):
    // FinanceService.addExpense does its own batch (actor lookup +
    // duplicate-check query don't fit inside the transaction above).
    // referenceType/referenceId make this idempotent — safe even if
    // this step is retried.
    if (farmLossAmount > 0) {
      final now = DateTime.now();
      await FinanceService.instance.addExpense(
        farmId,
        ExpenseModel(
          id: '',
          title: 'Goat Death Loss — $goatLabel',
          category: ExpenseCategories.goatDeathLoss,
          amount: farmLossAmount,
          // Not a real cash payment — the customer simply isn't being
          // asked to pay this part. FinancePaymentMethods.credit is
          // exactly the flag Net Cash Flow / Cash-Online calculations
          // already exclude for this reason, while Total Expenses /
          // Net Income still count it — see the EXCEPTION note on
          // ExpenseModel.isUnpaidCredit.
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
  /// Stock). There is no customer settlement; [farmLossAmount] — entered
  /// manually by the farm owner when recording the death (see
  /// RecordFarmGoatDeathScreen; [suggestedFarmLossAmount] below gives it
  /// a starting figure to prefill and edit) — is instead recorded as a
  /// "Goat Death Loss" expense in Finance.
  Future<void> recordFarmGoatDeath({
    required String farmId,
    required String goatId,
    required DateTime deathDate,
    required String reason,
    String notes = '',
    double farmLossAmount = 0,
  }) async {
    if (farmLossAmount < 0) {
      throw ArgumentError('Loss amount cannot be negative.');
    }

    final goatRef = _tradingGoats(farmId).doc(goatId);
    final deathRecordRef = _deathRecords(farmId).doc();
    final activityRef = _activities(farmId).doc();

    final actor = await FirestoreService.instance.getCurrentActor();

    String goatType = DeathRecord.typeAvailableStock;
    String goatLabel = '';

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

  /// A starting figure for [recordFarmGoatDeath]'s manual loss-amount
  /// field — the goat's originating purchase's cost-per-surviving-goat,
  /// when one can be found. Purely a UI convenience; the farm owner can
  /// (and per the spec, should be free to) edit it before saving. 0 when
  /// no purchase can be traced, in which case the field simply starts
  /// blank and must be entered by hand.
  Future<double> suggestedFarmLossAmount({
    required String farmId,
    required String goatId,
  }) async {
    final goatSnapshot = await _tradingGoats(farmId).doc(goatId).get();
    if (!goatSnapshot.exists) return 0;

    final goat = Goat.fromDoc(goatSnapshot);
    if (goat.purchaseId.trim().isEmpty) return 0;

    final purchaseSnapshot =
    await _tradingPurchases(farmId).doc(goat.purchaseId).get();
    if (!purchaseSnapshot.exists) return 0;

    return TradingPurchase.fromDoc(purchaseSnapshot).costPerSurvivingGoat;
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

  // =========================================================================
  // MANUAL FARM LOSS (fire, theft, disease, spoiled feed, storm damage...)
  // =========================================================================
  //
  // Not tied to any one goat's death. The farm owner logs it directly:
  // a category, a title/description in their own words, an amount, and
  // whether real cash left the farm or the loss was purely value lost.
  // Proof photos are supported but never required — see [addLossProof]
  // below; a record can be saved with zero photos
  // and have them attached later.
  //
  // Written into the same `deathRecords` collection as every goat death
  // (goatType: DeathRecord.typeManualLoss) so DeathHistoryScreen's single
  // stream already shows everything together — no second query, no
  // migration needed.

  /// Records a manual, non-goat farm loss and posts the matching Finance
  /// expense. Returns the new record's id (useful if the caller wants to
  /// attach proof photos immediately after via [addLossProof]).
  ///
  /// [isCashLoss] decides which FinancePaymentMethods gets posted:
  /// `true` when money genuinely left the farm (e.g. repairing fire
  /// damage, replacing stolen equipment), `false` when it's a pure
  /// value loss with no cash outflow (e.g. spoiled feed thrown away) —
  /// mirroring exactly how goat-death losses are already posted as
  /// FinancePaymentMethods.credit.
  Future<String> recordManualLoss({
    required String farmId,
    required String category,
    required DateTime lossDate,
    required String title,
    String description = '',
    required double amount,
    bool isCashLoss = false,
  }) async {
    if (amount < 0) {
      throw ArgumentError('Loss amount cannot be negative.');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError('Title is required.');
    }
    if (!DeathRecord.manualLossCategories.contains(category)) {
      throw ArgumentError('Unknown loss category: $category');
    }

    final deathRecordRef = _deathRecords(farmId).doc();
    final activityRef = _activities(farmId).doc();
    final actor = await FirestoreService.instance.getCurrentActor();
    final categoryLabel = DeathRecord.categoryLabelFor(category);

    await _db.runTransaction<void>((transaction) async {
      transaction.set(deathRecordRef, {
        'goatType': DeathRecord.typeManualLoss,
        'goatId': '',
        'goatLabel': title.trim(),
        'category': category,
        'title': title.trim(),
        'description': description.trim(),
        // Mirrored into `reason` too so any older UI reading `reason`
        // directly (rather than the new `description` field) still
        // shows something sensible.
        'deathDate': Timestamp.fromDate(lossDate),
        'reason': description.trim(),
        'notes': '',
        'farmLossAmount': amount,
        'isCashLoss': isCashLoss,
        'proofCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });

      transaction.set(activityRef, {
        'type': 'farmLossRecorded',
        'title': 'Farm Loss Recorded',
        'subtitle': '$categoryLabel · ${title.trim()}',
        'module': 'finance',
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });
    }).timeout(_timeout);

    // Same pattern as recordCustomerPalaiDeath / recordFarmGoatDeath
    // above: posted as a separate step since FinanceService.addExpense
    // does its own batch, made idempotent via referenceType/referenceId.
    if (amount > 0) {
      final now = DateTime.now();
      await FinanceService.instance.addExpense(
        farmId,
        ExpenseModel(
          id: '',
          title: '$categoryLabel — ${title.trim()}',
          // NOTE: reusing the existing "Goat Death Loss" expense
          // category for every manual loss too, since it already flows
          // correctly through Net Income / Total Expenses either way.
          // If a distinct line item in Finance reports is wanted,
          // add a dedicated ExpenseCategories.farmLoss constant and
          // swap it in here.
          category: ExpenseCategories.goatDeathLoss,
          amount: amount,
          // Cash losses hit the same tracker a normal cash expense
          // would; non-cash losses use `credit` exactly like goat
          // deaths, so Cash Flow / Cash-Online correctly excludes them
          // while Net Income still counts them.
          paymentMethod: isCashLoss
              ? FinancePaymentMethods.cash
              : FinancePaymentMethods.credit,
          note: description.trim(),
          date: lossDate,
          createdAt: now,
          updatedAt: now,
          status: 'active',
          referenceType: 'farmLoss',
          referenceId: deathRecordRef.id,
        ),
      );
    }

    return deathRecordRef.id;
  }

  // -------------------------------------------------------------------------
  // LOSS PROOF PHOTOS
  // -------------------------------------------------------------------------
  //
  // Proof is always optional. Photos are compressed by ImageService and
  // stored as Firestore `Blob`s in `deathRecords/{id}/proofs` — the same
  // no-Storage-bucket approach used for profile, goat and stock photos.
  // One document per photo keeps every write far below Firestore's
  // 1 MiB limit no matter how many photos a record collects.

  CollectionReference<Map<String, dynamic>> _lossProofs(
      String farmId,
      String lossId,
      ) =>
      _deathRecords(farmId).doc(lossId).collection('proofs');

  /// Attaches one proof photo to a loss record and bumps its
  /// `proofCount` in the same batch. Safe to call any number of times,
  /// including long after the record was created.
  Future<void> addLossProof({
    required String farmId,
    required String lossId,
    required PickedImage image,
  }) async {
    final proofRef = _lossProofs(farmId, lossId).doc();
    final batch = _db.batch();

    batch.set(proofRef, {
      'bytes': Blob(image.bytes),
      'contentType': image.contentType,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_deathRecords(farmId).doc(lossId), {
      'proofCount': FieldValue.increment(1),
    });

    await batch.commit().timeout(_timeout);
  }

  /// All proof photos for a loss record, oldest first.
  Stream<List<LossProof>> lossProofsStream(String farmId, String lossId) {
    return _lossProofs(farmId, lossId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(LossProof.fromDoc).toList());
  }
}

/// One stored proof photo for a loss record.
class LossProof {
  final String id;
  final Uint8List bytes;
  final String contentType;

  const LossProof({
    required this.id,
    required this.bytes,
    required this.contentType,
  });

  factory LossProof.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final field = data['bytes'];
    return LossProof(
      id: doc.id,
      bytes: field is Blob ? field.bytes : Uint8List(0),
      contentType: (data['contentType'] ?? 'image/jpeg').toString(),
    );
  }
}