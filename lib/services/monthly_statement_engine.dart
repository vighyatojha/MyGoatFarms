import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/monthly_bill_model.dart';
import '../models/palai_models.dart';
import '../utils/billing_ledger.dart';
import '../utils/palai_proration.dart';
import 'firestore_service.dart';
import 'monthly_billing_service.dart';
import 'payment_allocation_service.dart';

// ===========================================================================
// RESULTS
// ===========================================================================

enum StatementOutcomeKind {
  /// A new statement was created.
  generated,

  /// This month (or a later one) already has a bill. Nothing changed.
  alreadyBilled,

  /// No Palai charges for this month. Any old balance simply carries to
  /// the next statement.
  nothingToBill,

  /// Something went wrong. Nothing was written for this month.
  failed,
}

class StatementOutcome {
  const StatementOutcome({
    required this.kind,
    required this.periodKey,
    this.billId,
    this.billNumber,
    this.currentCharges = 0,
    this.totalPayable = 0,
    this.message = '',
  });

  final StatementOutcomeKind kind;
  final String periodKey;
  final String? billId;
  final String? billNumber;
  final double currentCharges;
  final double totalPayable;
  final String message;
}

/// What a run will do for one customer, worked out before anything is
/// written, so the confirmation dialog can warn about catch-up months.
class CustomerBillingPlan {
  const CustomerBillingPlan({
    required this.customerId,
    required this.customerName,
    required this.lastBilledKey,
    required this.periods,
  });

  final String customerId;
  final String customerName;
  final String? lastBilledKey;

  /// Months to generate, oldest first. Empty when already billed.
  final List<String> periods;

  bool get isCatchUp => periods.length > 1;
}

class CustomerRunResult {
  const CustomerRunResult({
    required this.customerId,
    required this.customerName,
    required this.outcomes,
  });

  final String customerId;
  final String customerName;
  final List<StatementOutcome> outcomes;

  bool get hasFailure =>
      outcomes.any((o) => o.kind == StatementOutcomeKind.failed);

  bool get generatedAny =>
      outcomes.any((o) => o.kind == StatementOutcomeKind.generated);

  /// One kind summarising the customer for the Done pop-up.
  StatementOutcomeKind get summaryKind {
    if (hasFailure) return StatementOutcomeKind.failed;
    if (generatedAny) return StatementOutcomeKind.generated;
    if (outcomes.any((o) => o.kind == StatementOutcomeKind.nothingToBill)) {
      return StatementOutcomeKind.nothingToBill;
    }
    return StatementOutcomeKind.alreadyBilled;
  }
}

class BillingRunProgress {
  const BillingRunProgress({
    required this.index,
    required this.total,
    required this.customerName,
    this.periodKey,
  });

  /// 1-based position of the customer being processed.
  final int index;
  final int total;
  final String customerName;
  final String? periodKey;
}

class BillingRunSummary {
  const BillingRunSummary({
    required this.targetPeriodKey,
    required this.results,
    this.error,
  });

  final String targetPeriodKey;
  final List<CustomerRunResult> results;

  /// Set when the run could not start at all (e.g. no connection while
  /// listing customers). Nothing was written.
  final String? error;

  int _count(StatementOutcomeKind kind) =>
      results.where((r) => r.summaryKind == kind).length;

  int get generatedCustomers => _count(StatementOutcomeKind.generated);
  int get alreadyBilledCustomers => _count(StatementOutcomeKind.alreadyBilled);
  int get nothingToBillCustomers => _count(StatementOutcomeKind.nothingToBill);
  int get failedCustomers => _count(StatementOutcomeKind.failed);

  /// Total statements created (a catch-up customer can get several).
  int get billsGenerated => results.fold(
    0,
        (sum, r) =>
    sum +
        r.outcomes
            .where((o) => o.kind == StatementOutcomeKind.generated)
            .length,
  );

  List<CustomerRunResult> get failures =>
      results.where((r) => r.hasFailure).toList();

  List<String> get failedCustomerIds =>
      failures.map((r) => r.customerId).toList();
}

/// What the next statement for one customer will contain, worked out
/// with exactly the same calculation as [MonthlyStatementEngine
/// .generateStatement], but without writing anything.
class StatementPreview {
  const StatementPreview({
    required this.periodKey,
    required this.status,
    this.lines = const [],
    this.currentCharges = 0,
    this.previousOutstanding = 0,
    this.previousBreakdown = const [],
    this.earlierBalance = 0,
    this.advanceApplied = 0,
    this.totalPayable = 0,
    this.advanceAfter = 0,
    this.paidFromDeletedBill = 0,
    this.lastBilledKey,
    this.laterPeriods = const [],
  });

  /// Payment made on a deleted bill, used on this month.
  final double paidFromDeletedBill;

  /// The month this preview is for ('YYYY-MM').
  final String periodKey;

  final StatementPreviewStatus status;

  final List<GoatChargeLine> lines;
  final double currentCharges;
  final double previousOutstanding;
  final List<BreakdownLine> previousBreakdown;
  final double earlierBalance;
  final double advanceApplied;
  final double totalPayable;
  final double advanceAfter;

  final String? lastBilledKey;

  /// Further missed months that the same Generate press will bill after
  /// [periodKey], oldest first. Their figures depend on this month, so
  /// they are listed, not previewed.
  final List<String> laterPeriods;

  bool get canGenerate => status == StatementPreviewStatus.ready;
}

enum StatementPreviewStatus {
  /// A statement can be generated for [StatementPreview.periodKey].
  ready,

  /// Billed up to the target month already.
  alreadyBilled,

  /// No goat was on the farm (or every day was already charged) that
  /// month. Generating would create nothing.
  nothingToBill,
}

/// Internal result of the shared statement calculation.
class _StatementPlan {
  const _StatementPlan({
    required this.lines,
    required this.goatBilledThrough,
    required this.currentCharges,
    required this.breakdown,
    required this.totals,
    required this.advanceAllocation,
    required this.finalRemaining,
    required this.newOwnPaid,
    required this.newOwnRemaining,
    this.creditApplied = 0,
    this.creditLeft = 0,
  });

  final List<GoatChargeLine> lines;

  /// goatId -> new billedThroughDate.
  final Map<String, DateTime> goatBilledThrough;

  final double currentCharges;
  final PreviousOutstandingBreakdown breakdown;
  final StatementTotals totals;
  final AllocationResult advanceAllocation;

  /// billId -> ownRemaining after corrections and advance.
  final Map<String, double> finalRemaining;

  final double newOwnPaid;
  final double newOwnRemaining;

  /// Payment made on a DELETED bill for this customer (kept as a credit,
  /// see deleteLatestBill), used on this new month. Already income when it
  /// was received, so it is not income again.
  final double creditApplied;

  /// Credit still left after this bill (used on the next one).
  final double creditLeft;
}

// ===========================================================================
// SYNC (after bills were generated: new customers, new / removed goats)
// ===========================================================================

enum BillSyncKind {
  /// A month still to bill (e.g. a customer added after the run).
  generate,

  /// The latest bill no longer matches the goats on the farm; it will be
  /// deleted and generated again.
  rebuild,

  /// Something differs but can't be fixed automatically; shown with the
  /// reason and what to do.
  attention,
}

class BillSyncItem {
  const BillSyncItem({
    required this.customerId,
    required this.customerName,
    required this.kind,
    required this.periodKey,
    this.billId,
    this.billNumber,
    this.oldAmount = 0,
    this.newAmount = 0,
    this.changes = const [],
    this.note,
  });

  final String customerId;
  final String customerName;
  final BillSyncKind kind;

  /// Month concerned ('YYYY-MM'). For [BillSyncKind.generate], the first
  /// month that will be generated.
  final String periodKey;

  final String? billId;
  final String? billNumber;

  /// Palai charges on the bill now / as worked out from today's goats.
  final double oldAmount;
  final double newAmount;

  /// Plain-language lines: 'Added Gauri: 12–30 Sep (₹950)'.
  final List<String> changes;

  /// Why it needs attention / what to do.
  final String? note;

  bool get isAutomatic => kind != BillSyncKind.attention;
}

class BillSyncResult {
  const BillSyncResult({
    required this.customerName,
    required this.ok,
    required this.message,
  });

  final String customerName;
  final bool ok;
  final String message;
}

// ===========================================================================
// ENGINE
// ===========================================================================

/// Generates monthly STATEMENTS (see utils/billing_ledger.dart for the
/// model). Pressing Generate Bills in October bills September:
///
///   September charges + Previous Outstanding − Advance = Total Payable
///
/// Each customer-month is one all-or-nothing transaction, so a failure
/// never leaves a half-made bill and running again is always safe: a
/// month that already has a bill is skipped.
class MonthlyStatementEngine {
  MonthlyStatementEngine._();

  static final MonthlyStatementEngine instance = MonthlyStatementEngine._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 60);

  /// Longest catch-up a single run will produce for one customer.
  static const int maxCatchUpMonths = 12;

  DocumentReference<Map<String, dynamic>> _farm(String farmId) =>
      _db.collection('farms').doc(farmId);

  CollectionReference<Map<String, dynamic>> _customers(String farmId) =>
      _farm(farmId).collection('palaiCustomers');

  CollectionReference<Map<String, dynamic>> _bills(String farmId) =>
      _farm(farmId).collection('monthlyBills');

  CollectionReference<Map<String, dynamic>> _goats(
      String farmId,
      String customerId,
      ) =>
      _customers(farmId).doc(customerId).collection('goats');

  /// Bill-number counter. Kept inside monthlyBills (a collection the
  /// app's security rules already allow) rather than a new 'counters'
  /// collection, which the rules blocked with permission-denied. It has no
  /// customerId and its type is 'counter', so no bill list or query ever
  /// picks it up.
  DocumentReference<Map<String, dynamic>> _counter(String farmId) =>
      _bills(farmId).doc('_billNumberCounter');

  static String billIdFor(String customerId, String periodKey) =>
      'monthly_${customerId}_$periodKey';

  /// The month a run today bills (always the previous month).
  String targetPeriodKey([DateTime? now]) =>
      targetPeriodKeyFor(now ?? DateTime.now());

  // =========================================================================
  // PLAN
  // =========================================================================

  /// Works out, for every Palai customer, which months a run would bill.
  /// Reads only; writes nothing.
  Future<List<CustomerBillingPlan>> planRun({
    required String farmId,
    String? targetKey,
    List<String>? onlyCustomerIds,
  }) async {
    final target = targetKey ?? targetPeriodKey();

    final customersSnap = await _customers(farmId).get().timeout(_timeout);
    final billsSnap = await _bills(farmId)
        .where('type', isEqualTo: 'monthly')
        .get()
        .timeout(_timeout);

    final lastByCustomer = <String, String>{};
    for (final doc in billsSnap.docs) {
      final bill = _QueryBill(doc.data());
      if (bill.isVoid) continue;
      final key = bill.periodKey;
      if (key == null) continue;
      final current = lastByCustomer[bill.customerId];
      if (current == null || key.compareTo(current) > 0) {
        lastByCustomer[bill.customerId] = key;
      }
    }

    final plans = <CustomerBillingPlan>[];
    for (final doc in customersSnap.docs) {
      if (onlyCustomerIds != null && !onlyCustomerIds.contains(doc.id)) {
        continue;
      }
      final data = doc.data();
      final last = _maxKey(
        lastByCustomer[doc.id],
        data['lastBilledPeriod']?.toString(),
      );
      plans.add(
        CustomerBillingPlan(
          customerId: doc.id,
          customerName: (data['name'] ?? '').toString().trim(),
          lastBilledKey: last,
          periods: periodsToGenerate(
            lastBilledKey: last,
            targetKey: target,
            maxMonths: maxCatchUpMonths,
          ),
        ),
      );
    }

    plans.sort(
          (a, b) => a.customerName.toLowerCase().compareTo(
        b.customerName.toLowerCase(),
      ),
    );
    return plans;
  }

  // =========================================================================
  // RUN (Generate Bills button)
  // =========================================================================

  /// Generates statements for every customer, one by one, reporting
  /// progress before each customer. One customer failing never stops the
  /// others. Pass [onlyCustomerIds] to retry just the failed ones.
  Future<BillingRunSummary> runAll({
    required String farmId,
    String? targetKey,
    List<String>? onlyCustomerIds,
    void Function(BillingRunProgress progress)? onProgress,
  }) async {
    final target = targetKey ?? targetPeriodKey();
    final plans = await planRun(
      farmId: farmId,
      targetKey: target,
      onlyCustomerIds: onlyCustomerIds,
    );

    final results = <CustomerRunResult>[];

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final name =
      plan.customerName.isEmpty ? 'Customer' : plan.customerName;

      onProgress?.call(
        BillingRunProgress(
          index: i + 1,
          total: plans.length,
          customerName: name,
          periodKey: plan.periods.isEmpty ? null : plan.periods.first,
        ),
      );

      results.add(
        CustomerRunResult(
          customerId: plan.customerId,
          customerName: name,
          outcomes: await _runPlan(farmId, plan, target),
        ),
      );
    }

    return BillingRunSummary(targetPeriodKey: target, results: results);
  }

  /// Generates every month in [plan] in order. Stops at the first failure,
  /// because a later month must never be billed before an earlier one.
  Future<List<StatementOutcome>> _runPlan(
      String farmId,
      CustomerBillingPlan plan,
      String target,
      ) async {
    if (plan.periods.isEmpty) {
      return [
        StatementOutcome(
          kind: StatementOutcomeKind.alreadyBilled,
          periodKey: target,
          message: plan.lastBilledKey == null
              ? 'Already billed.'
              : 'Already billed up to ${periodLabel(plan.lastBilledKey!)}.',
        ),
      ];
    }

    final outcomes = <StatementOutcome>[];
    for (final period in plan.periods) {
      StatementOutcome outcome;
      try {
        outcome = await generateStatement(
          farmId: farmId,
          customerId: plan.customerId,
          periodKey: period,
        );
      } catch (e) {
        outcome = StatementOutcome(
          kind: StatementOutcomeKind.failed,
          periodKey: period,
          message: FirestoreService.instance.describeError(e),
        );
      }
      outcomes.add(outcome);
      if (outcome.kind == StatementOutcomeKind.failed) break;
    }
    return outcomes;
  }

  /// Generates whatever months one customer is missing, up to [targetKey].
  Future<List<StatementOutcome>> generateForCustomer({
    required String farmId,
    required String customerId,
    String? targetKey,
  }) async {
    final target = targetKey ?? targetPeriodKey();
    final plans = await planRun(
      farmId: farmId,
      targetKey: target,
      onlyCustomerIds: [customerId],
    );
    if (plans.isEmpty) {
      throw StateError('Customer no longer exists.');
    }
    return _runPlan(farmId, plans.first, target);
  }

  // =========================================================================
  // ONE STATEMENT
  // =========================================================================

  /// Creates the statement for one customer and month [periodKey]
  /// ('YYYY-MM') in a single transaction.
  Future<StatementOutcome> generateStatement({
    required String farmId,
    required String customerId,
    required String periodKey,
    String notes = '',
  }) async {
    if (parsePeriodKey(periodKey) == null) {
      throw ArgumentError('Invalid billing month: $periodKey');
    }

    final customerRef = _customers(farmId).doc(customerId);
    final billId = billIdFor(customerId, periodKey);
    final billRef = _bills(farmId).doc(billId);
    final farmRef = _farm(farmId);
    final counterRef = _counter(farmId);
    final transactionsRef = _farm(farmId).collection('transactions');
    final activityRef = _farm(farmId).collection('activities').doc();

    // Queries cannot run inside a transaction: find the documents first,
    // then re-read each by reference inside it.
    final billRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);
    final goatRefs = (await _goats(farmId, customerId)
        .get()
        .timeout(_timeout))
        .docs
        .map((d) => d.reference)
        .toList();
    final actor = await FirestoreService.instance.getCurrentActor();

    final monthStart = periodStart(periodKey);
    final monthEnd = periodEnd(periodKey);

    return _db.runTransaction<StatementOutcome>((transaction) async {
      // =====================================================================
      // READS (all before any write)
      // =====================================================================
      final customerSnap = await transaction.get(customerRef);
      if (!customerSnap.exists) {
        throw StateError('Customer no longer exists.');
      }

      final existing = await transaction.get(billRef);
      if (existing.exists) {
        return StatementOutcome(
          kind: StatementOutcomeKind.alreadyBilled,
          periodKey: periodKey,
          billId: billId,
          billNumber: existing.data()?['billNumber']?.toString(),
          message: '${periodLabel(periodKey)} is already billed.',
        );
      }

      final ledger = await PalaiLedger.instance.read(transaction, billRefs);

      final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in goatRefs) {
        goatSnaps.add(await transaction.get(ref));
      }

      final farmSnap = await transaction.get(farmRef);
      final counterSnap = await transaction.get(counterRef);

      final customer = customerSnap.data() ?? {};
      final customerName = (customer['name'] ?? '').toString().trim();
      if (customerName.isEmpty) {
        throw StateError('Customer name is missing.');
      }

      final lastBilled = _maxKey(
        ledger.lastBilledKey,
        customer['lastBilledPeriod']?.toString(),
      );

      if (lastBilled != null && lastBilled.compareTo(periodKey) >= 0) {
        return StatementOutcome(
          kind: StatementOutcomeKind.alreadyBilled,
          periodKey: periodKey,
          message: 'Already billed up to ${periodLabel(lastBilled)}.',
        );
      }

      // =====================================================================
      // CALCULATION (shared with previewNext, so the preview always
      // matches what is generated)
      // =====================================================================
      final plan = _computePlan(
        periodKey: periodKey,
        billId: billId,
        customer: customer,
        ledger: ledger,
        goatSnaps: goatSnaps,
        lastBilled: lastBilled,
      );

      if (plan.currentCharges <= kMoneyEpsilon) {
        return StatementOutcome(
          kind: StatementOutcomeKind.nothingToBill,
          periodKey: periodKey,
          message: 'No Palai charges for ${periodLabel(periodKey)}.',
        );
      }

      final lines = plan.lines;
      final goatUpdates = <DocumentReference<Map<String, dynamic>>, DateTime>{
        for (final snap in goatSnaps)
          if (plan.goatBilledThrough.containsKey(snap.id))
            snap.reference: plan.goatBilledThrough[snap.id]!,
      };
      final currentCharges = plan.currentCharges;
      final breakdown = plan.breakdown;
      final totals = plan.totals;
      final advanceAllocation = plan.advanceAllocation;
      final finalRemaining = plan.finalRemaining;
      final newOwnPaid = plan.newOwnPaid;
      final newOwnRemaining = plan.newOwnRemaining;

      // =====================================================================
      // BILL NUMBER
      // =====================================================================
      final seqField = 'seq_$periodKey';
      final seq =
          ((counterSnap.data()?[seqField] as num?)?.toInt() ?? 0) + 1;
      final billNumber = 'MB-$periodKey-${seq.toString().padLeft(4, '0')}';

      final farm = farmSnap.data() ?? {};
      final now = DateTime.now();
      final statementStatus = totals.totalPayable <= kMoneyEpsilon
          ? 'paid'
          : 'unpaid';

      // =====================================================================
      // WRITES
      // =====================================================================
      final writer = LedgerWriter();

      // Earlier months: corrections and advance applied.
      for (final entry in finalRemaining.entries) {
        if (entry.key == billId) continue;
        final bill = ledger.byId(entry.key);
        if (bill == null) continue;

        final remaining = roundMoney(entry.value);
        final reducedBy = roundMoney(bill.ownRemaining - remaining);
        if (reducedBy <= 0) continue;

        final paid = roundMoney(bill.ownPaid + reducedBy);
        final status = paymentStatusFor(paid: paid, remaining: remaining);
        final normalized = breakdown.normalizedRemaining.containsKey(bill.id);

        if (bill.hasOwnFields || normalized) {
          writer.merge(bill.ref, {
            'ownPaid': paid,
            'ownRemaining': remaining,
            'ownStatus': status,
            if (normalized) 'ledgerNormalizedFrom': bill.ownRemaining,
            if (normalized) 'ledgerNormalizedByBillId': billId,
          });
        } else {
          writer.merge(bill.ref, {
            'amountPaid': paid,
            'remainingAmount': remaining,
            'status': status,
            'paymentStatus': status,
          });
        }
      }

      // Adjustments made since the last bill are listed on this one (they
      // are already inside Previous Outstanding; this just shows them).
      final adjustmentLines = <Map<String, dynamic>>[];
      for (final adj in ledger.bills) {
        if (!adj.isAdjustment) continue;
        if (adj.data['includedInStatementId'] != null) continue;
        adjustmentLines.add({
          'periodKey': adj.periodKey,
          'amount': roundMoney(
            (adj.data['adjustmentAmount'] as num?)?.toDouble() ?? 0,
          ),
          'label': (adj.data['ledgerLabel'] ?? 'Adjustment').toString(),
          'billId': adj.id,
          'reason': (adj.data['notes'] ?? '').toString(),
        });
        writer.merge(adj.ref, {'includedInStatementId': billId});
      }

      // The previous bill becomes history.
      final monthBills = ledger.monthBills;
      if (monthBills.isNotEmpty) {
        final previous = monthBills.last;
        final statementRemaining =
        roundMoney((previous.data['remainingAmount'] as num?)?.toDouble() ?? 0);
        writer.merge(previous.ref, {
          'locked': true,
          'lockedByBillId': billId,
          if (previous.isStatement && statementRemaining > kMoneyEpsilon)
            'carriedForward': true,
          if (previous.isStatement && statementRemaining > kMoneyEpsilon)
            'carriedForwardToBillId': billId,
        });
      }

      writer.flush(transaction);

      transaction.set(billRef, {
        'type': 'monthly',
        'billingModel': MonthlyBill.statementModel,
        'adjustmentLines': adjustmentLines,
        'billNumber': billNumber,
        'customerId': customerId,
        'customerName': customerName,

        'billingPeriodKey': periodKey,
        'periodMonth': periodKey,
        'month': monthStart.month,
        'year': monthStart.year,
        'billingMonth': Timestamp.fromDate(monthStart),
        'periodEnd': Timestamp.fromDate(monthEnd),

        // This month.
        'goatCount': lines.length,
        'goatBreakdown': lines
            .map((l) => GoatBillingLine.fromCharge(l).toMap())
            .toList(),
        'palaiCharges': currentCharges,
        'otherCharges': 0.0,
        'discount': 0.0,
        'newCharges': currentCharges,
        'currentBillAmount': currentCharges,

        // Carried forward (snapshot, never re-charged).
        'previousOutstanding': totals.previousOutstanding,
        'previousBreakdown':
        breakdown.lines.map((l) => l.toMap()).toList(),
        'earlierBalance': breakdown.earlierBalance,

        // Advance.
        'advanceApplied': totals.advanceApplied,
        'advanceAllocations': advanceAllocation.allocations
            .map(
              (a) => BreakdownLine(
            periodKey: a.periodKey,
            amount: a.amount,
            billId: a.billId,
          ).toMap(),
        )
            .toList(),

        // Statement (what the customer sees and pays against).
        'totalPayable': totals.totalPayable,
        'totalDue': totals.totalPayable,
        'amountPaid': 0.0,
        'remainingAmount': totals.totalPayable,
        'pendingAfter': totals.totalPayable,
        'status': statementStatus,
        'paymentStatus': statementStatus,
        'paidAt': statementStatus == 'paid' ? Timestamp.fromDate(now) : null,

        // This month's own charge (cleared oldest-first).
        'ownCharges': currentCharges,
        'ownPaid': newOwnPaid,
        'ownRemaining': newOwnRemaining,
        if (plan.creditApplied > 0) 'paidFromDeletedBill': plan.creditApplied,
        'ownStatus':
        paymentStatusFor(paid: newOwnPaid, remaining: newOwnRemaining),

        'locked': false,
        'notes': notes.trim(),

        'farmName': (farm['farmName'] ?? '').toString(),
        'farmAddress': (farm['address'] ?? '').toString(),
        'farmPhone': (farm['mobileNumber'] ?? '').toString(),
        'farmEmail': (farm['email'] ?? '').toString(),

        'generatedAt': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final entry in goatUpdates.entries) {
        transaction.update(entry.key, {
          'billedThroughDate': Timestamp.fromDate(entry.value),
          'lastBilledPeriod': periodKey,
        });
      }

      transaction.set(
        counterRef,
        {
          seqField: seq,
          'type': 'counter',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.update(customerRef, {
        'pendingAmount': totals.totalPayable,
        'advanceAmount': totals.advanceAfter,
        'lastBilledPeriod': periodKey,
        if (plan.creditApplied > 0) 'billPaymentCredit': plan.creditLeft,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (totals.advanceApplied > 0) {
        // Advance becomes income when a bill uses it (same rule as before).
        transaction.set(transactionsRef.doc('advuse_$billId'), {
          'amount': totals.advanceApplied,
          'isIncome': true,
          'category': 'Advance Applied to Bill',
          'customerId': customerId,
          'customerName': customerName,
          'billId': billId,
          'billNumber': billNumber,
          'paymentMethod': 'Advance',
          'note': 'Advance used on monthly statement $billNumber',
          'referenceType': 'advanceApplied',
          'referenceId': billId,
          'status': 'active',
          'date': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          customerRef.collection('advanceEntries').doc('bill_$billId'),
          {
            'amount': totals.advanceApplied,
            'type': 'debit',
            'source': 'monthlyBill',
            'billId': billId,
            'billNumber': billNumber,
            'periodKey': periodKey,
            'customerId': customerId,
            'customerName': customerName,
            'note': 'Advance used on monthly statement $billNumber',
            'date': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }

      transaction.set(activityRef, {
        'type': 'monthlyBillGenerated',
        'title': 'Monthly Bill Generated',
        'subtitle': '$customerName · ${periodLabel(periodKey)} · '
            'Payable ₹${totals.totalPayable.toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'billId': billId,
        'billNumber': billNumber,
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });

      return StatementOutcome(
        kind: StatementOutcomeKind.generated,
        periodKey: periodKey,
        billId: billId,
        billNumber: billNumber,
        currentCharges: currentCharges,
        totalPayable: totals.totalPayable,
      );
    }).timeout(_timeout);
  }

  // =========================================================================
  // UNBILLED DAYS (Final Checkout / death settlement)
  // =========================================================================

  /// The customer's last billed month, or null if never billed.
  Future<String?> lastBilledPeriod({
    required String farmId,
    required String customerId,
  }) async {
    final customer =
    await _customers(farmId).doc(customerId).get().timeout(_timeout);
    final bills = await _bills(farmId)
        .where('customerId', isEqualTo: customerId)
        .get()
        .timeout(_timeout);

    String? last = customer.data()?['lastBilledPeriod']?.toString();
    if (parsePeriodKey(last) == null) last = null;

    for (final doc in bills.docs) {
      final bill = _QueryBill(doc.data());
      if (bill.type != 'monthly' || bill.isVoid) continue;
      last = _maxKey(last, bill.periodKey);
    }
    return last;
  }

  /// Palai owed for [goat] from the day after it was last charged up to
  /// [upTo] (inclusive), across month boundaries.
  ///
  /// [lastBilledKey] comes from [lastBilledPeriod]. For a customer never
  /// billed under statement billing, only the current month is charged,
  /// which is what Final Checkout charged before.
  PalaiRangeCharge unbilledChargeFor({
    required PalaiGoat goat,
    required String? lastBilledKey,
    required DateTime upTo,
  }) {
    final end = palaiDateOnly(upTo);
    final billedThrough = effectiveBilledThrough(
      stored: goat.billedThroughDate,
      closedUnderOldCode: false,
      leaveDate: null,
      lastBilledKey: lastBilledKey,
      fallback: DateTime(end.year, end.month, 0),
    );

    var from = DateTime(
      billedThrough.year,
      billedThrough.month,
      billedThrough.day + 1,
    );
    final arrival = palaiDateOnly(goat.billingStartDate);
    if (arrival.isAfter(from)) from = arrival;

    return PalaiRangeCalculator.chargeForRange(
      monthlyCharge: goat.pricing < 0 ? 0.0 : goat.pricing.toDouble(),
      from: from,
      to: end,
    );
  }

  // =========================================================================
  // SHARED CALCULATION
  // =========================================================================

  /// The statement calculation used by both [generateStatement] and
  /// [previewNext]. Pure: reads nothing, writes nothing.
  _StatementPlan _computePlan({
    required String periodKey,
    required String billId,
    required Map<String, dynamic> customer,
    required CustomerLedger ledger,
    required List<DocumentSnapshot<Map<String, dynamic>>> goatSnaps,
    required String? lastBilled,
  }) {
    final monthStart = periodStart(periodKey);

    // This month's charges, goat by goat.
    final lines = <GoatChargeLine>[];
    final billedThrough = <String, DateTime>{};

    for (final goatSnap in goatSnaps) {
      if (!goatSnap.exists) continue;
      final input = _goatInput(
        goatSnap.id,
        goatSnap.data() ?? {},
        lastBilledKey: lastBilled,
        fallbackBilledThrough: DateTime(monthStart.year, monthStart.month, 0),
      );
      final line = chargeGoatForPeriod(input, periodKey);
      if (line == null) continue;
      lines.add(line);
      billedThrough[goatSnap.id] = line.toDate;
    }

    lines.sort((a, b) => a.label.compareTo(b.label));

    final currentCharges = roundMoney(
      lines.fold<double>(0, (sum, l) => sum + l.amount),
    );

    // Carry forward + advance.
    final pendingBefore =
    roundMoney((customer['pendingAmount'] as num?)?.toDouble() ?? 0);
    final advanceBefore =
    roundMoney((customer['advanceAmount'] as num?)?.toDouble() ?? 0);

    final breakdown = buildPreviousBreakdown(
      openMonths: ledger.openMonths,
      pending: pendingBefore,
    );

    final totals = computeStatement(
      previousOutstanding: pendingBefore,
      currentCharges: currentCharges,
      advanceAvailable: advanceBefore,
    );

    // Months as they really stand after correcting any left-over
    // inconsistency, plus this new month, for the advance to clear.
    final monthsForAdvance = <LedgerMonth>[
      for (final month in ledger.openMonths)
        LedgerMonth(
          billId: month.billId,
          periodKey: month.periodKey,
          ownRemaining:
          breakdown.normalizedRemaining[month.billId] ?? month.ownRemaining,
        ),
      LedgerMonth(
        billId: billId,
        periodKey: periodKey,
        ownRemaining: currentCharges,
      ),
    ];

    final advanceAllocation =
    allocateOldestFirst(monthsForAdvance, totals.advanceApplied);

    final finalRemaining = <String, double>{
      ...breakdown.normalizedRemaining,
      for (final a in advanceAllocation.allocations) a.billId: a.remainingAfter,
    };

    final advanceOnNewMonth = advanceAllocation.allocations
        .where((a) => a.billId == billId)
        .fold<double>(0, (sum, a) => sum + a.amount);
    final newOwnPaid = roundMoney(advanceOnNewMonth);

    // A payment made on a deleted bill is used on this month first; the
    // rest waits for the next bill.
    final credit =
    roundMoney((customer['billPaymentCredit'] as num?)?.toDouble() ?? 0);
    final ownRemainingAfterAdvance = roundMoney(currentCharges - newOwnPaid);
    final creditApplied = credit <= kMoneyEpsilon
        ? 0.0
        : roundMoney(credit < ownRemainingAfterAdvance
        ? credit
        : ownRemainingAfterAdvance);

    final adjustedTotals = creditApplied <= kMoneyEpsilon
        ? totals
        : StatementTotals(
      previousOutstanding: totals.previousOutstanding,
      currentCharges: totals.currentCharges,
      advanceApplied: totals.advanceApplied,
      totalPayable: roundMoney(totals.totalPayable - creditApplied),
      advanceAfter: totals.advanceAfter,
    );

    return _StatementPlan(
      lines: lines,
      goatBilledThrough: billedThrough,
      currentCharges: currentCharges,
      breakdown: breakdown,
      totals: adjustedTotals,
      advanceAllocation: advanceAllocation,
      finalRemaining: finalRemaining,
      newOwnPaid: roundMoney(newOwnPaid + creditApplied),
      newOwnRemaining: roundMoney(ownRemainingAfterAdvance - creditApplied),
      creditApplied: creditApplied,
      creditLeft: roundMoney(credit - creditApplied),
    );
  }

  // =========================================================================
  // PREVIEW (single-customer Generate screen)
  // =========================================================================

  /// Shows what pressing Generate would bill for one customer right now,
  /// without writing anything. Uses the same calculation as
  /// [generateStatement].
  Future<StatementPreview> previewNext({
    required String farmId,
    required String customerId,
    String? targetKey,
  }) async {
    final target = targetKey ?? targetPeriodKey();
    final plans = await planRun(
      farmId: farmId,
      targetKey: target,
      onlyCustomerIds: [customerId],
    );
    if (plans.isEmpty) {
      throw StateError('Customer no longer exists.');
    }

    final plan = plans.first;
    if (plan.periods.isEmpty) {
      return StatementPreview(
        periodKey: plan.lastBilledKey ?? target,
        status: StatementPreviewStatus.alreadyBilled,
        lastBilledKey: plan.lastBilledKey,
      );
    }

    final periodKey = plan.periods.first;
    final billId = billIdFor(customerId, periodKey);

    final customerSnap =
    await _customers(farmId).doc(customerId).get().timeout(_timeout);
    final billRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);
    final bills = (await Future.wait(billRefs.map((ref) => ref.get()))
        .timeout(_timeout))
        .map(LedgerBill.new)
        .toList();
    final ledger = CustomerLedger(bills);
    final goatSnaps = (await _goats(farmId, customerId)
        .get()
        .timeout(_timeout))
        .docs;

    final customer = customerSnap.data() ?? {};
    final lastBilled = _maxKey(
      ledger.lastBilledKey,
      customer['lastBilledPeriod']?.toString(),
    );

    final computed = _computePlan(
      periodKey: periodKey,
      billId: billId,
      customer: customer,
      ledger: ledger,
      goatSnaps: goatSnaps,
      lastBilled: lastBilled,
    );

    return StatementPreview(
      periodKey: periodKey,
      status: computed.currentCharges <= kMoneyEpsilon
          ? StatementPreviewStatus.nothingToBill
          : StatementPreviewStatus.ready,
      lines: computed.lines,
      currentCharges: computed.currentCharges,
      previousOutstanding: computed.totals.previousOutstanding,
      previousBreakdown: computed.breakdown.lines,
      earlierBalance: computed.breakdown.earlierBalance,
      advanceApplied: computed.totals.advanceApplied,
      totalPayable: computed.totals.totalPayable,
      advanceAfter: computed.totals.advanceAfter,
      paidFromDeletedBill: computed.creditApplied,
      lastBilledKey: lastBilled,
      laterPeriods: plan.periods.skip(1).toList(),
    );
  }

  // =========================================================================
  // SYNC: ANALYSE AND REBUILD BILLS
  // =========================================================================

  /// Looks at every customer and reports what Generate Bills alone would
  /// miss once bills already exist:
  ///
  /// * customers (or months) not billed yet → generate;
  /// * a latest bill whose goats changed since it was made (goat added
  ///   with days in that month, goat deleted, price changed, goat checked
  ///   out later) → rebuild: delete it and generate it fresh;
  /// * anything that can't be fixed safely by itself → attention, with
  ///   what to do.
  ///
  /// Nothing is written.
  Future<List<BillSyncItem>> analyseSync({
    required String farmId,
    void Function(int done, int total)? onProgress,
  }) async {
    final target = targetPeriodKey();
    final plans = await planRun(farmId: farmId, targetKey: target);
    final items = <BillSyncItem>[];

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      onProgress?.call(i, plans.length);

      if (plan.periods.isNotEmpty) {
        items.add(BillSyncItem(
          customerId: plan.customerId,
          customerName: plan.customerName,
          kind: BillSyncKind.generate,
          periodKey: plan.periods.first,
          changes: [
            plan.periods.length == 1
                ? 'Not billed for ${periodLabel(plan.periods.first)} yet.'
                : 'Not billed for ${plan.periods.map(periodLabel).join(', ')} yet.',
          ],
        ));
        continue;
      }

      try {
        final item = await _analyseLatestBill(
          farmId: farmId,
          customerId: plan.customerId,
          customerName: plan.customerName,
          target: target,
        );
        if (item != null) items.add(item);
      } catch (e) {
        items.add(BillSyncItem(
          customerId: plan.customerId,
          customerName: plan.customerName,
          kind: BillSyncKind.attention,
          periodKey: target,
          note: 'Could not check: ${FirestoreService.instance.describeError(e)}',
        ));
      }
    }
    onProgress?.call(plans.length, plans.length);
    return items;
  }

  /// Re-works the customer's latest bill from the goats on the farm now,
  /// exactly as Delete + Generate would, and compares. Null when it still
  /// matches.
  Future<BillSyncItem?> _analyseLatestBill({
    required String farmId,
    required String customerId,
    required String customerName,
    required String target,
  }) async {
    final bill = await latestBill(farmId: farmId, customerId: customerId);
    if (bill == null) return null;

    final periodKey = bill.billingPeriodKey;
    final monthStart = periodStart(periodKey);
    final dayBefore = DateTime(monthStart.year, monthStart.month, 0);
    final month = periodLabel(periodKey);

    final goatSnaps = (await _goats(farmId, customerId)
        .get()
        .timeout(_timeout))
        .docs;

    final billLines = <String, GoatBillingLine>{
      for (final line in bill.goatBreakdown)
        if (line.goatId.isNotEmpty) line.goatId: line,
    };

    // Each goat as if this bill did not exist yet.
    final recomputed = <String, GoatChargeLine>{};
    final earlierMissing = <String>[];

    // Goats billed again after this bill (checkout / death): their later
    // days were charged there, so this bill's line stays as it is.
    final kept = <String, double>{};

    for (final snap in goatSnaps) {
      final data = Map<String, dynamic>.from(snap.data());
      final line = billLines[snap.id];
      final stored = data['billedThroughDate'];
      final storedDate = stored is Timestamp ? palaiDateOnly(stored.toDate()) : null;

      if (line != null &&
          line.toDate != null &&
          storedDate != null &&
          storedDate != palaiDateOnly(line.toDate!)) {
        kept[snap.id] = line.palaiAmount;
        continue;
      }

      if (line?.fromDate != null) {
        final from = palaiDateOnly(line!.fromDate!);
        data['billedThroughDate'] =
            Timestamp.fromDate(DateTime(from.year, from.month, from.day - 1));
      } else if (storedDate == null && line == null) {
        // Not on this bill and never billed: a goat added after the bill.
        // Days before this month were never billed by anything.
        final input = _goatInput(
          snap.id,
          data,
          lastBilledKey: null,
          fallbackBilledThrough: dayBefore,
        );
        final arrival = input.billingStart == null
            ? null
            : palaiDateOnly(input.billingStart!);
        if (arrival != null && arrival.isBefore(monthStart)) {
          final missed = PalaiRangeCalculator.chargeForRange(
            monthlyCharge: input.monthlyRate < 0 ? 0.0 : input.monthlyRate,
            from: arrival,
            to: dayBefore,
          );
          if (missed.amount > kMoneyEpsilon) {
            earlierMissing.add(
              '${input.label} arrived ${DateFormat('d MMM yyyy').format(arrival)}: '
                  '${missed.totalDays} days before $month were never billed '
                  '(₹${missed.amount.toStringAsFixed(0)}).',
            );
          }
        }
      }

      final input = _goatInput(
        snap.id,
        data,
        lastBilledKey: previousPeriodKey(periodKey),
        fallbackBilledThrough: dayBefore,
      );
      final charge = chargeGoatForPeriod(input, periodKey);
      if (charge != null && charge.amount > kMoneyEpsilon) {
        recomputed[snap.id] = charge;
      }
    }

    // ---------------------------------------------------------- compare
    final changes = <String>[];
    final dayFmt = DateFormat('d MMM');
    String money(double v) => '₹${v.toStringAsFixed(0)}';

    for (final entry in recomputed.entries) {
      final old = billLines[entry.key];
      final now = entry.value;
      if (old == null) {
        changes.add(
          'Added ${now.label}: ${dayFmt.format(now.fromDate)} – '
              '${dayFmt.format(now.toDate)} (${money(now.amount)}).',
        );
      } else if ((old.palaiAmount - now.amount).abs() > 0.5) {
        changes.add(
          'Changed ${now.label}: ${money(old.palaiAmount)} → ${money(now.amount)}.',
        );
      }
    }
    for (final entry in billLines.entries) {
      if (recomputed.containsKey(entry.key)) continue;
      if (kept.containsKey(entry.key)) continue;
      if (entry.value.palaiAmount <= kMoneyEpsilon) continue;
      final exists = goatSnaps.any((g) => g.id == entry.key);
      changes.add(
        exists
            ? 'Removed ${entry.value.label}: no Palai due for $month any more '
            '(was ${money(entry.value.palaiAmount)}).'
            : 'Removed ${entry.value.label}: goat deleted '
            '(was ${money(entry.value.palaiAmount)}).',
      );
    }

    final newPalai = roundMoney(
      recomputed.values.fold<double>(0, (sum, l) => sum + l.amount) +
          kept.values.fold<double>(0, (sum, v) => sum + v),
    );
    final oldPalai = roundMoney(bill.palaiCharges);

    // Old bills without goat lines: compare totals only.
    if (billLines.isEmpty && (newPalai - oldPalai).abs() > 0.5) {
      changes.add(
        'Palai worked out from today\'s goats: ${money(newPalai)} '
            '(bill shows ${money(oldPalai)}).',
      );
    }

    final differs = (newPalai - oldPalai).abs() > 0.5 || changes.isNotEmpty;

    if (!differs && earlierMissing.isEmpty) return null;

    // ----------------------------------------------------- decide action
    String? blocked;
    if (!differs) {
      blocked = null;
    } else if (periodKey.compareTo(target) > 0) {
      blocked = 'This is an older-style bill for $month, made before the '
          'update. Bills are now made for the previous month, so it can\'t '
          'be rebuilt until ${DateFormat('d MMMM yyyy').format(periodStart(nextPeriodKey(periodKey)))}. '
          'Delete it in Monthly Bills if it should go now; $month will then '
          'be billed correctly on that date.';
    } else if (kept.isNotEmpty) {
      blocked = 'A goat on this bill was checked out or died after it was '
          'made, so the bill can\'t be rebuilt. Use an adjustment for the '
          'difference (${money((newPalai - oldPalai).abs())} '
          '${newPalai > oldPalai ? 'more' : 'less'}).';
    } else if (bill.isStatement && await _wasEditedByHand(farmId, bill.id)) {
      blocked = 'This bill was edited by hand, so it isn\'t rebuilt '
          'automatically (that would undo the edit). Check it in Monthly Bills.';
    }

    if (!differs) {
      return BillSyncItem(
        customerId: customerId,
        customerName: customerName,
        kind: BillSyncKind.attention,
        periodKey: periodKey,
        billId: bill.id,
        billNumber: bill.billNumber,
        oldAmount: oldPalai,
        newAmount: newPalai,
        changes: earlierMissing,
        note: 'Add an adjustment for these days in Monthly Bills.',
      );
    }

    return BillSyncItem(
      customerId: customerId,
      customerName: customerName,
      kind: blocked == null ? BillSyncKind.rebuild : BillSyncKind.attention,
      periodKey: periodKey,
      billId: bill.id,
      billNumber: bill.billNumber,
      oldAmount: oldPalai,
      newAmount: newPalai,
      changes: [...changes, ...earlierMissing],
      note: blocked ??
          (earlierMissing.isEmpty
              ? null
              : 'Earlier days are not part of the rebuild: add an '
              'adjustment for them in Monthly Bills.'),
    );
  }

  Future<bool> _wasEditedByHand(String farmId, String billId) async {
    final snap = await _bills(farmId).doc(billId).get().timeout(_timeout);
    final corrections = snap.data()?['corrections'];
    return corrections is List &&
        corrections.any((c) => c is Map && c['type'] == 'edit');
  }

  /// Carries out the automatic items from [analyseSync]: generates missing
  /// bills and rebuilds changed ones (delete, then generate fresh). Each
  /// customer is separate; one failure never stops the others.
  Future<List<BillSyncResult>> applySync({
    required String farmId,
    required List<BillSyncItem> items,
    void Function(int index, int total, String customerName)? onProgress,
  }) async {
    final todo = items.where((i) => i.isAutomatic).toList();
    final results = <BillSyncResult>[];

    for (var i = 0; i < todo.length; i++) {
      final item = todo[i];
      onProgress?.call(i + 1, todo.length, item.customerName);

      try {
        if (item.kind == BillSyncKind.rebuild) {
          await deleteLatestBill(
            farmId: farmId,
            customerId: item.customerId,
            billId: item.billId!,
            reason: 'Sync: goats changed after the bill was made.',
          );
        }

        final outcomes = await generateForCustomer(
          farmId: farmId,
          customerId: item.customerId,
        );
        final generated = outcomes
            .where((o) => o.kind == StatementOutcomeKind.generated)
            .toList();
        final failed = outcomes
            .where((o) => o.kind == StatementOutcomeKind.failed)
            .toList();

        if (failed.isNotEmpty) {
          results.add(BillSyncResult(
            customerName: item.customerName,
            ok: false,
            message: item.kind == BillSyncKind.rebuild
                ? 'Old bill removed, but the new one failed: '
                '${failed.first.message} Press Generate Bills to retry.'
                : failed.first.message,
          ));
        } else if (generated.isEmpty) {
          results.add(BillSyncResult(
            customerName: item.customerName,
            ok: true,
            message: item.kind == BillSyncKind.rebuild
                ? 'Old bill removed. Nothing to charge for '
                '${periodLabel(item.periodKey)} with the current goats.'
                : 'Nothing to bill.',
          ));
        } else {
          results.add(BillSyncResult(
            customerName: item.customerName,
            ok: true,
            message: generated
                .map((o) =>
            '${periodLabel(o.periodKey)}: ₹${o.totalPayable.toStringAsFixed(0)} '
                'payable')
                .join(', '),
          ));
        }
      } catch (e) {
        results.add(BillSyncResult(
          customerName: item.customerName,
          ok: false,
          message: FirestoreService.instance.describeError(e),
        ));
      }
    }
    return results;
  }

  // =========================================================================
  // NEW CUSTOMER: ENROLLMENT DATE + PENDING BEFORE THE FIRST BILL
  // =========================================================================

  /// Adds a customer and sets up where their billing starts, in one
  /// atomic write.
  ///
  /// [customer].joiningDate is the farm enrollment date. See
  /// [enrollmentBilling]: when the customer enrolled before the month the
  /// next run bills, the owner was asked whether those earlier months are
  /// fully paid. [pendingBeforeBilling] is the amount still owed for them
  /// (0 when fully paid). It is saved as an OPENING BALANCE:
  ///
  ///   * a record in monthlyBills (billingModel 'openingBalance') dated
  ///     the month before the first bill, so it is the oldest thing owed
  ///     and payments clear it first;
  ///   * shown on the first bill as 'Pending before September 2026';
  ///   * not income until it is paid.
  ///
  /// The app then bills this customer from the first billed month only;
  /// goats are never charged for days before it.
  Future<String> addCustomerWithEnrollment({
    required String farmId,
    required PalaiCustomer customer,
    double pendingBeforeBilling = 0,
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
    final enrolled = palaiDateOnly(customer.joiningDate);
    if (enrolled.isAfter(palaiDateOnly(now))) {
      throw ArgumentError('Enrollment date cannot be in the future.');
    }

    final plan = enrollmentBilling(enrollmentDate: enrolled, today: now);
    final amount = roundMoney(pendingBeforeBilling < 0 ? 0 : pendingBeforeBilling);
    if (amount > kMoneyEpsilon && !plan.asksAboutEarlierMonths) {
      throw ArgumentError(
        'There are no months before the first bill to carry a pending amount.',
      );
    }

    final customerRef = _customers(farmId).doc();
    final batch = _db.batch();

    batch.set(customerRef, {
      ...customer.toMap(),
      'joiningDate': Timestamp.fromDate(enrolled),
      'enrollmentDate': Timestamp.fromDate(enrolled),
      'pendingAmount': amount,
      'billingStartPeriod': plan.firstBilledKey,
      // Marks the months before the first bill as settled (paid, or
      // carried as the opening balance below), so the engine bills from
      // the first billed month, including catch-up if a run is missed.
      if (plan.asksAboutEarlierMonths)
        'lastBilledPeriod': previousPeriodKey(plan.firstBilledKey),
      if (plan.asksAboutEarlierMonths)
        'earlierMonths': plan.monthsBefore,
      if (plan.asksAboutEarlierMonths)
        'earlierMonthsPaid': amount <= kMoneyEpsilon,
    });

    if (amount > kMoneyEpsilon) {
      final through = previousPeriodKey(plan.firstBilledKey);
      final monthStart = periodStart(through);
      final shortId = customerRef.id.length > 6
          ? customerRef.id.substring(0, 6).toUpperCase()
          : customerRef.id.toUpperCase();

      batch.set(_bills(farmId).doc('opening_${customerRef.id}'), {
        'type': 'monthly',
        'billingModel': MonthlyBill.openingBalanceModel,
        'customerId': customerRef.id,
        'customerName': customer.name,
        'customerMobile': customer.mobileNumber,
        'billNumber': 'OB-$shortId',
        'ledgerLabel': plan.openingBalanceLabel,
        'openingMonths': plan.monthsBefore,
        'billingPeriodKey': through,
        'month': monthStart.month,
        'year': monthStart.year,
        'billingMonth': Timestamp.fromDate(monthStart),
        'periodEnd': Timestamp.fromDate(periodEnd(through)),
        'goatCount': 0,
        'goatBreakdown': const <Map<String, dynamic>>[],
        'palaiCharges': 0.0,
        'otherCharges': 0.0,
        'discount': 0.0,
        'newCharges': amount,
        'currentBillAmount': amount,
        'previousOutstanding': 0.0,
        'advanceApplied': 0.0,
        'totalDue': amount,
        'amountPaid': 0.0,
        'remainingAmount': amount,
        'pendingAfter': amount,
        'status': 'unpaid',
        'paymentStatus': 'unpaid',
        'notes': '${plan.monthsBeforeLabel} not fully paid when the '
            'customer was added. Carried forward, never charged again.',
        'generatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit().timeout(_timeout);
    return customerRef.id;
  }

  // =========================================================================
  // ADJUSTMENTS (corrections to older, already-billed months)
  // =========================================================================

  /// Months an adjustment can be made for: every billed month (and an
  /// opening balance's month) except the newest unlocked statement, which
  /// is corrected with Edit instead. Newest first.
  Future<List<String>> adjustableMonths({
    required String farmId,
    required String customerId,
  }) async {
    final snapshot = await _bills(farmId)
        .where('customerId', isEqualTo: customerId)
        .get()
        .timeout(_timeout);
    final bills = CustomerLedger([
      for (final doc in snapshot.docs)
        if (doc.data()['type']?.toString() == 'monthly') LedgerBill(doc),
    ]).monthBills;

    final keys = <String>{};
    for (var i = 0; i < bills.length; i++) {
      final bill = bills[i];
      final isNewest = i == bills.length - 1;
      if (isNewest && bill.isStatement && !bill.locked) continue;
      keys.add(bill.periodKey);
    }
    final list = keys.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Adds a correction for an older month, positive (charge more) or
  /// negative (credit). Takes effect immediately and is listed on the
  /// customer's next bill.
  ///
  /// * Positive: owed like that month (payments clear it in that month's
  ///   place, oldest first); pending goes up.
  /// * Negative: reduces what is owed, oldest month first; anything
  ///   beyond what is owed becomes advance. It is not a payment and not
  ///   income.
  Future<void> addAdjustment({
    required String farmId,
    required String customerId,
    required String periodKey,
    required double amount,
    required String reason,
  }) async {
    final value = roundMoney(amount);
    if (value.abs() <= kMoneyEpsilon) {
      throw ArgumentError('Enter an amount.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Add a reason for the adjustment.');
    }
    if (parsePeriodKey(periodKey) == null) {
      throw ArgumentError('Choose the month this adjustment is for.');
    }

    final allowed = await adjustableMonths(
      farmId: farmId,
      customerId: customerId,
    );
    if (!allowed.contains(periodKey)) {
      throw StateError(
        'Adjustments are for months that are already billed. Use Edit on '
            'the latest bill instead.',
      );
    }

    final customerRef = _customers(farmId).doc(customerId);
    final billRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);
    final adjustmentRef = _bills(farmId).doc(
      'adj_${customerId}_${DateTime.now().millisecondsSinceEpoch}',
    );
    final activityRef = _farm(farmId).collection('activities').doc();
    final actor = await FirestoreService.instance.getCurrentActor();

    final shortId = customerId.length > 6
        ? customerId.substring(0, 6).toUpperCase()
        : customerId.toUpperCase();
    final label = 'Adjustment for ${periodLabel(periodKey)}';

    await _db.runTransaction<void>((transaction) async {
      final customerSnap = await transaction.get(customerRef);
      if (!customerSnap.exists) {
        throw StateError('Customer no longer exists.');
      }
      final ledger = await PalaiLedger.instance.read(transaction, billRefs);

      final customer = customerSnap.data() ?? {};
      final pendingBefore =
      roundMoney((customer['pendingAmount'] as num?)?.toDouble() ?? 0);
      final advanceBefore =
      roundMoney((customer['advanceAmount'] as num?)?.toDouble() ?? 0);

      double pendingAfter;
      double advanceAfter = advanceBefore;
      double applied = 0;
      List<Map<String, dynamic>> allocations = const [];

      final writer = LedgerWriter();

      if (value > 0) {
        pendingAfter = roundMoney(pendingBefore + value);
      } else {
        final credit = -value;
        final reduction = PalaiLedger.instance.reduceDues(
          writer: writer,
          ledger: ledger,
          amount: credit,
          pendingBefore: pendingBefore,
          recordOnStatement: false,
        );
        applied = reduction.applied;
        allocations = [
          for (final a in reduction.allocations)
            {
              'billId': a.billId,
              'periodKey': a.periodKey,
              'amount': a.amount,
            },
        ];
        pendingAfter = roundMoney(pendingBefore - applied);
        advanceAfter = roundMoney(advanceBefore + (credit - applied));
      }

      final monthStart = periodStart(periodKey);
      writer.flush(transaction);

      transaction.set(adjustmentRef, {
        'type': 'monthly',
        'billingModel': MonthlyBill.adjustmentModel,
        'customerId': customerId,
        'customerName': (customer['name'] ?? '').toString(),
        'billNumber': 'ADJ-$periodKey-$shortId',
        'ledgerLabel': label,
        'billingPeriodKey': periodKey,
        'month': monthStart.month,
        'year': monthStart.year,
        'billingMonth': Timestamp.fromDate(monthStart),
        'periodEnd': Timestamp.fromDate(periodEnd(periodKey)),
        'adjustmentAmount': value,
        'goatCount': 0,
        'goatBreakdown': const <Map<String, dynamic>>[],
        'palaiCharges': 0.0,
        'newCharges': value > 0 ? value : 0.0,
        'currentBillAmount': value,
        'previousOutstanding': 0.0,
        'advanceApplied': 0.0,
        'totalDue': value > 0 ? value : 0.0,
        'amountPaid': 0.0,
        'remainingAmount': value > 0 ? value : 0.0,
        'status': value > 0 ? 'unpaid' : 'paid',
        'paymentStatus': value > 0 ? 'unpaid' : 'paid',
        'creditAppliedToDues': applied,
        'creditToAdvance': value < 0 ? roundMoney(-value - applied) : 0.0,
        'creditAllocations': allocations,
        'pendingAfter': pendingAfter,
        'locked': true,
        'notes': reason.trim(),
        'generatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (actor != null) 'createdBy': actor.name,
      });

      transaction.update(customerRef, {
        'pendingAmount': pendingAfter,
        'advanceAmount': advanceAfter,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(activityRef, {
        'type': 'monthlyBillUpdated',
        'title': value > 0 ? 'Adjustment Added' : 'Credit Adjustment Added',
        'subtitle': '${(customer['name'] ?? '').toString()} · $label · '
            '${value > 0 ? '+' : '−'}₹${value.abs().toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'billId': adjustmentRef.id,
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });
    }).timeout(_timeout);
  }

  // =========================================================================
  // CONSISTENCY CHECK (all customers)
  // =========================================================================

  /// Flags (never fixes) every customer whose figures disagree. Returns
  /// customer name → issues; customers without issues are left out.
  Future<Map<String, List<String>>> checkAllCustomers({
    required String farmId,
  }) async {
    final customers = await _customers(farmId).get().timeout(_timeout);
    final results = <String, List<String>>{};
    for (final doc in customers.docs) {
      final issues = await MonthlyBillingService.instance
          .checkCustomerConsistency(farmId: farmId, customerId: doc.id);
      if (issues.isNotEmpty) {
        final name = (doc.data()['name'] ?? doc.id).toString();
        results[name] = issues;
      }
    }
    return results;
  }

  // =========================================================================
  // CORRECTIONS: EDIT / VOID THE LATEST STATEMENT
  // =========================================================================

  /// Reads everything a correction needs and checks the bill is the
  /// customer's latest, unlocked statement. Must run inside [transaction].
  Future<({
  DocumentSnapshot<Map<String, dynamic>> customerSnap,
  CustomerLedger ledger,
  LedgerBill bill,
  })> _readLatestStatement(
      Transaction transaction, {
        required DocumentReference<Map<String, dynamic>> customerRef,
        required List<DocumentReference<Map<String, dynamic>>> billRefs,
        required String billId,
        required String customerId,
        bool allowOldStyle = false,
      }) async {
    final customerSnap = await transaction.get(customerRef);
    if (!customerSnap.exists) {
      throw StateError('Customer no longer exists.');
    }

    final ledger = await PalaiLedger.instance.read(transaction, billRefs);
    final bill = ledger.byId(billId);

    if (bill == null) {
      throw StateError('This bill no longer exists or is already void.');
    }
    if ((bill.data['customerId'] ?? '').toString() != customerId) {
      throw StateError('This bill does not belong to this customer.');
    }
    final model = bill.data['billingModel'];
    if (bill.isAdjustment || model == MonthlyBill.openingBalanceModel) {
      throw StateError(
        'Opening balances and adjustments are not bills, so they cannot be '
            'changed here. Add an adjustment instead.',
      );
    }
    if (!bill.isStatement && !allowOldStyle) {
      throw StateError(
        'Only bills made by Generate Bills can be edited. Delete this bill '
            'and generate it again instead.',
      );
    }
    if (bill.locked || ledger.monthBills.last.id != billId) {
      throw StateError(
        'Only the latest bill can be corrected. A newer bill already '
            'carries this month forward.',
      );
    }

    return (customerSnap: customerSnap, ledger: ledger, bill: bill);
  }

  /// Corrects the latest statement's charges.
  ///
  /// [goatAmounts] maps goatId → corrected Palai amount for that goat's
  /// line (days stay as billed). [otherCharges] and [discount] apply to
  /// the month. Only the difference between the new and old charge moves
  /// the customer's pending; the previous outstanding and the advance
  /// applied stay exactly as issued.
  Future<MonthlyBill> editStatement({
    required String farmId,
    required String customerId,
    required String billId,
    required Map<String, double> goatAmounts,
    double otherCharges = 0,
    double discount = 0,
    String? notes,
    String reason = '',
  }) async {
    if (otherCharges < 0 || discount < 0 ||
        goatAmounts.values.any((v) => v < 0)) {
      throw ArgumentError('Amounts cannot be negative.');
    }

    final customerRef = _customers(farmId).doc(customerId);
    final billRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);
    final activityRef = _farm(farmId).collection('activities').doc();
    final actor = await FirestoreService.instance.getCurrentActor();

    await _db.runTransaction<void>((transaction) async {
      final read = await _readLatestStatement(
        transaction,
        customerRef: customerRef,
        billRefs: billRefs,
        billId: billId,
        customerId: customerId,
      );
      final bill = read.bill;
      final data = bill.data;
      final customer = read.customerSnap.data() ?? {};

      // Corrected goat lines (unknown goat ids are ignored).
      final lines = <Map<String, dynamic>>[];
      double palai = 0;
      for (final raw in (data['goatBreakdown'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final line = Map<String, dynamic>.from(raw);
        final goatId = (line['goatId'] ?? '').toString();
        final amount = roundMoney(
          goatAmounts[goatId] ?? (line['palaiAmount'] as num?)?.toDouble() ?? 0,
        );
        line['palaiAmount'] = amount;
        palai = roundMoney(palai + amount);
        lines.add(line);
      }

      double num0(String key) =>
          roundMoney((data[key] as num?)?.toDouble() ?? 0);

      final newCharges = roundMoney(palai + otherCharges - discount);
      final edit = computeStatementEdit(
        oldCharges: num0('ownCharges'),
        newCharges: newCharges,
        ownPaid: bill.ownPaid,
        previousOutstanding: num0('previousOutstanding'),
        advanceApplied: num0('advanceApplied'),
        amountPaid: num0('amountPaid'),
      );

      final pendingBefore =
      roundMoney((customer['pendingAmount'] as num?)?.toDouble() ?? 0);
      final pendingAfter = roundMoney(pendingBefore + edit.pendingDelta);
      if (pendingAfter < -kMoneyEpsilon) {
        throw StateError(
          'The customer\'s pending would go below zero. Check their '
              'balance before correcting this bill.',
        );
      }

      final statementStatus = paymentStatusFor(
        paid: num0('amountPaid'),
        remaining: edit.remaining,
      );

      transaction.update(bill.ref, {
        'goatBreakdown': lines,
        'palaiCharges': palai,
        'otherCharges': roundMoney(otherCharges),
        'discount': roundMoney(discount),
        'newCharges': edit.newCharges,
        'currentBillAmount': edit.newCharges,
        'ownCharges': edit.newCharges,
        'ownRemaining': edit.ownRemaining,
        'ownStatus': paymentStatusFor(
          paid: bill.ownPaid,
          remaining: edit.ownRemaining,
        ),
        'totalPayable': edit.totalPayable,
        'totalDue': edit.totalPayable,
        'remainingAmount': edit.remaining,
        'pendingAfter': pendingAfter,
        'status': statementStatus,
        'paymentStatus': statementStatus,
        if (notes != null) 'notes': notes.trim(),
        'corrections': FieldValue.arrayUnion([
          {
            'type': 'edit',
            'fromCharges': num0('ownCharges'),
            'toCharges': edit.newCharges,
            'reason': reason.trim(),
            'at': Timestamp.now(),
            if (actor != null) 'by': actor.name,
          },
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(customerRef, {
        'pendingAmount': pendingAfter < 0 ? 0.0 : pendingAfter,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(activityRef, {
        'type': 'monthlyBillUpdated',
        'title': 'Monthly Bill Corrected',
        'subtitle': '${(customer['name'] ?? '').toString()} · '
            '${periodLabel(bill.periodKey)} · '
            '₹${num0('ownCharges').toStringAsFixed(0)} → '
            '₹${edit.newCharges.toStringAsFixed(0)}',
        'module': 'palai',
        'customerId': customerId,
        'billId': billId,
        'billNumber': bill.billNumber,
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });
    }).timeout(_timeout);

    final fresh = await _bills(farmId).doc(billId).get().timeout(_timeout);
    return MonthlyBill.fromDoc(fresh);
  }

  /// Voids the latest statement when nothing has been paid against it.
  ///
  /// * The bill is kept as a void record under a new id, which frees the
  ///   month so it can be generated again.
  /// * The month's charge comes off pending; the advance it used goes back
  ///   to advance, and the older months that advance cleared are owed
  ///   again.
  /// * Each goat's billedThroughDate goes back to the day before its line
  ///   started, so the next run charges those days again.
  /// * The previous bill is unlocked and becomes the latest again.
  ///
  /// Refused when a payment or waiver touched this month, or a goat was
  /// checked out / died after the bill (those days were charged there).
  @Deprecated('Use deleteLatestBill.')
  Future<void> voidStatement({
    required String farmId,
    required String customerId,
    required String billId,
    String reason = '',
  }) =>
      deleteLatestBill(
        farmId: farmId,
        customerId: customerId,
        billId: billId,
        reason: reason,
      ).then((_) {});

  /// DELETE BILL: removes the customer's latest bill so it can be
  /// generated again from the goats on the farm now. Works for bills made
  /// by Generate Bills and for bills made before statement billing.
  ///
  /// Typical use: a goat was deleted (or a price fixed) after the bill was
  /// made. Delete the bill, then Generate again: the new bill is worked
  /// out fresh, so the deleted goat is no longer charged.
  ///
  /// * The bill is kept only as a deleted record (status 'void') under a
  ///   new id; it disappears from the customer's bills.
  /// * Its own charge comes off pending; any advance it used goes back to
  ///   advance (and older months that advance cleared are owed again).
  /// * Payments that cleared OLDER months stay exactly as they are.
  /// * Each goat's billedThroughDate goes back to before this bill, so
  ///   those days are charged again on the next Generate.
  ///
  /// Refused when this month itself was paid or waived, or a goat on it
  /// was checked out / died after the bill (those days were charged
  /// there). Returns the deleted bill's month ('YYYY-MM').
  Future<String> deleteLatestBill({
    required String farmId,
    required String customerId,
    required String billId,
    String reason = '',
  }) async {
    final customerRef = _customers(farmId).doc(customerId);
    final billRefs =
    await PalaiLedger.instance.monthlyBillRefs(farmId, customerId);
    final goatsCol = _goats(farmId, customerId);
    final transactionsRef = _farm(farmId).collection('transactions');
    final activityRef = _farm(farmId).collection('activities').doc();
    final archiveRef = _bills(farmId)
        .doc('void_${billId}_${DateTime.now().millisecondsSinceEpoch}');
    final actor = await FirestoreService.instance.getCurrentActor();

    // Goat ids on the bill, so they can be re-read inside the transaction.
    final preview = await _bills(farmId).doc(billId).get().timeout(_timeout);
    final goatIds = <String>[
      for (final raw in (preview.data()?['goatBreakdown'] as List? ?? const []))
        if (raw is Map && (raw['goatId'] ?? '').toString().isNotEmpty)
          raw['goatId'].toString(),
    ];

    // Already deleted (an earlier try finished on the server after the
    // phone stopped waiting): nothing to do.
    if (!preview.exists) {
      final archived = await _bills(farmId)
          .where('voidedFromBillId', isEqualTo: billId)
          .limit(1)
          .get()
          .timeout(_timeout);
      if (archived.docs.isNotEmpty) {
        return LedgerBill(archived.docs.first).periodKey;
      }
      throw StateError('This bill no longer exists.');
    }
    final previewPeriod = LedgerBill(preview).periodKey;

    var deletedPeriod = '';
    try {
      await _db.runTransaction<void>((transaction) async {
        // ------------------------------------------------------------- READS
        final read = await _readLatestStatement(
          transaction,
          customerRef: customerRef,
          billRefs: billRefs,
          billId: billId,
          customerId: customerId,
          allowOldStyle: true,
        );
        final goatList = await Future.wait(
          goatIds.map((id) => transaction.get(goatsCol.doc(id))),
        );
        final goatSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{
          for (final snap in goatList) snap.id: snap,
        };

        final bill = read.bill;
        final data = bill.data;
        final ledger = read.ledger;
        deletedPeriod = bill.periodKey;
        final customer = read.customerSnap.data() ?? {};

        double num0(String key) =>
            roundMoney((data[key] as num?)?.toDouble() ?? 0);

        // ------------------------------------------------------------ CHECKS
        // A bill made before statement billing records its own payments in
        // amountPaid. A statement's amountPaid can include money that only
        // cleared OLDER months, which is fine: only this month's own
        // payments block deleting it (checked below via ownPaid).
        // Payments made for THIS month are not lost: they are kept as a
        // credit (billPaymentCredit) and used on the regenerated bill. Only
        // the unpaid part of the month comes off pending.

        final allocations = <BreakdownLine>[
          for (final raw in (data['advanceAllocations'] as List? ?? const []))
            if (raw is Map) BreakdownLine.fromMap(Map<String, dynamic>.from(raw)),
        ];
        final advanceOnThisMonth = roundMoney(
          allocations
              .where((a) => a.billId == billId)
              .fold<double>(0, (sum, a) => sum + a.amount),
        );
        // What was paid for this month (not counting advance the bill used).
        // Older-style bills: the month's own charge. Their amountPaid could
        // include money that really cleared older balances (the old app
        // recorded every payment on the newest bill), so at most the
        // month's own charge counts as paid for this month.
        final legacyCharge = num0('currentBillAmount') > 0
            ? num0('currentBillAmount')
            : (num0('newCharges') > 0 ? num0('newCharges') : num0('palaiCharges'));
        final legacyMax = roundMoney(legacyCharge - num0('advanceApplied'));
        final paidOnMonth = bill.isStatement
            ? roundMoney(bill.ownPaid - advanceOnThisMonth)
            : roundMoney(
          num0('amountPaid') < legacyMax
              ? num0('amountPaid')
              : (legacyMax < 0 ? 0.0 : legacyMax),
        );
        final creditFromPayments = paidOnMonth > kMoneyEpsilon ? paidOnMonth : 0.0;

        final goatRestore = <DocumentReference<Map<String, dynamic>>, DateTime>{};
        for (final raw in (data['goatBreakdown'] as List? ?? const [])) {
          if (raw is! Map) continue;
          final line = GoatBillingLine.fromMap(Map<String, dynamic>.from(raw));
          final snap = goatSnaps[line.goatId];
          if (snap == null || !snap.exists || line.fromDate == null ||
              line.toDate == null) {
            continue;
          }
          final stored = snap.data()?['billedThroughDate'];
          final current = stored is Timestamp ? palaiDateOnly(stored.toDate()) : null;
          if (current == null || current != palaiDateOnly(line.toDate!)) {
            throw StateError(
              '${line.label} was checked out, died or was billed again after '
                  'this bill (those days were charged there), so it cannot be '
                  'deleted. Use Edit or an adjustment instead.',
            );
          }
          final from = palaiDateOnly(line.fromDate!);
          goatRestore[snap.reference] =
              DateTime(from.year, from.month, from.day - 1);
        }

        final advanceApplied = num0('advanceApplied');
        final pendingBefore =
        roundMoney((customer['pendingAmount'] as num?)?.toDouble() ?? 0);

        // What this bill still adds to pending (the month's UNPAID part):
        //  * Statement: its charge minus the advance it used, minus what was
        //    paid on the month (that payment becomes a credit).
        //  * Older-style bill: its own charge minus advance minus paid. Some
        //    old bills stored a remaining amount that also included the
        //    previous outstanding; that part is NOT this month's, so the
        //    smaller figure is used and the old outstanding stays owed.
        double pendingDelta;
        if (bill.isStatement) {
          pendingDelta = roundMoney(
            voidPendingDelta(
              ownCharges: num0('ownCharges'),
              advanceApplied: advanceApplied,
            ) +
                creditFromPayments,
          );
        } else {
          final ownUnpaid =
          roundMoney(legacyCharge - advanceApplied - creditFromPayments);
          final stored = num0('remainingAmount');
          final unpaid = ownUnpaid < 0
              ? 0.0
              : (stored < ownUnpaid ? stored : ownUnpaid);
          pendingDelta = -unpaid;
        }

        final pendingAfter = roundMoney(pendingBefore + pendingDelta);
        // Never below zero: anything this month owed beyond the customer's
        // pending was already settled another way.
        final safePendingAfter = pendingAfter < 0 ? 0.0 : pendingAfter;
        final creditBefore = roundMoney(
          (customer['billPaymentCredit'] as num?)?.toDouble() ?? 0,
        );
        final advanceAfter = roundMoney(
          ((customer['advanceAmount'] as num?)?.toDouble() ?? 0) +
              advanceApplied,
        );

        final monthBills = ledger.monthBills;
        final previous = monthBills.length >= 2
            ? monthBills[monthBills.length - 2]
            : null;

        // With no earlier bill, go back to the customer's billing start
        // (set when they were added), so the first month is billed again
        // from the same place, never earlier.
        final startKey = customer['billingStartPeriod']?.toString();
        final Object startMarker = parsePeriodKey(startKey) != null
            ? previousPeriodKey(startKey!)
            : FieldValue.delete();

        // ------------------------------------------------------------ WRITES
        final writer = LedgerWriter();

        // Older months the advance cleared are owed again.
        for (final a in allocations) {
          if (a.billId == null || a.billId == billId || a.amount <= 0) continue;
          final older = ledger.byId(a.billId!);
          if (older == null) continue;
          final paid = roundMoney(older.ownPaid - a.amount);
          final remaining = roundMoney(older.ownRemaining + a.amount);
          final status = paymentStatusFor(
            paid: paid < 0 ? 0.0 : paid,
            remaining: remaining,
          );
          if (older.hasOwnFields) {
            writer.merge(older.ref, {
              'ownPaid': paid < 0 ? 0.0 : paid,
              'ownRemaining': remaining,
              'ownStatus': status,
            });
          } else {
            writer.merge(older.ref, {
              'amountPaid': paid < 0 ? 0.0 : paid,
              'remainingAmount': remaining,
              'status': status,
              'paymentStatus': status,
            });
          }
        }

        // The previous bill becomes the latest again.
        if (previous != null) {
          writer.merge(previous.ref, {
            'locked': false,
            'lockedByBillId': FieldValue.delete(),
            'carriedForward': FieldValue.delete(),
            'carriedForwardToBillId': FieldValue.delete(),
          });
        }
        writer.flush(transaction);

        // Keep the bill as a void record and free the month's id.
        transaction.set(archiveRef, {
          ...data,
          'status': 'void',
          'paymentStatus': 'void',
          'isVoid': true,
          'voidedFromBillId': billId,
          'voidReason': reason.trim(),
          'paymentKeptAsCredit': creditFromPayments,
          'deletedBill': true,
          'voidedAt': FieldValue.serverTimestamp(),
          if (actor != null) 'voidedBy': actor.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.delete(bill.ref);

        for (final entry in goatRestore.entries) {
          transaction.update(entry.key, {
            'billedThroughDate': Timestamp.fromDate(entry.value),
            'lastBilledPeriod': previous?.periodKey ?? startMarker,
          });
        }

        transaction.update(customerRef, {
          'pendingAmount': safePendingAfter,
          'advanceAmount': advanceAfter,
          if (creditFromPayments > 0)
            'billPaymentCredit': roundMoney(creditBefore + creditFromPayments),
          'lastBilledPeriod': previous?.periodKey ?? startMarker,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // The advance used by this bill was income; it is held again now.
        if (advanceApplied > 0) {
          transaction.delete(transactionsRef.doc('advuse_$billId'));
          transaction.delete(
            customerRef.collection('advanceEntries').doc('bill_$billId'),
          );
        }

        transaction.set(activityRef, {
          'type': 'monthlyBillDeleted',
          'title': 'Monthly Bill Deleted',
          'subtitle': '${(customer['name'] ?? '').toString()} · '
              '${periodLabel(bill.periodKey)} · ${bill.billNumber}',
          'module': 'palai',
          'customerId': customerId,
          'billId': archiveRef.id,
          'billNumber': bill.billNumber,
          'timestamp': FieldValue.serverTimestamp(),
          if (actor != null) 'actorUid': actor.uid,
          if (actor != null) 'actorName': actor.name,
          if (actor != null) 'actorRole': actor.role,
        });
      }).timeout(_timeout);
    } catch (e) {
      // On a slow connection the phone can stop waiting while the server
      // still finishes the delete. If the bill is gone, it worked.
      final again = await _bills(farmId).doc(billId).get().timeout(_timeout);
      if (!again.exists) {
        return deletedPeriod.isNotEmpty ? deletedPeriod : previewPeriod;
      }
      rethrow;
    }

    return deletedPeriod;
  }

  // =========================================================================
  // LATEST BILL (report screens)
  // =========================================================================

  /// The customer's newest monthly bill that is not void, or null.
  ///
  /// [preferStatement]: for reports. Returns the newest bill made by the
  /// new billing (Generate Bills) when there is one, so an older-style
  /// bill made for the current month before the update never hides it.
  /// Falls back to the newest older-style bill only when the customer has
  /// no new bill yet.
  Future<MonthlyBill?> latestBill({
    required String farmId,
    required String customerId,
    bool preferStatement = false,
  }) async {
    final snapshot = await _bills(farmId)
        .where('customerId', isEqualTo: customerId)
        .get()
        .timeout(_timeout);

    MonthlyBill? latest;
    String? latestKey;
    MonthlyBill? latestStatement;
    String? latestStatementKey;
    for (final doc in snapshot.docs) {
      final query = _QueryBill(doc.data());
      if (query.type != 'monthly' || query.isVoid) continue;
      final model = doc.data()['billingModel'];
      if (model == MonthlyBill.openingBalanceModel ||
          model == MonthlyBill.adjustmentModel) {
        continue;
      }
      final key = query.periodKey;
      if (key == null) continue;
      if (latestKey == null || key.compareTo(latestKey) > 0) {
        latestKey = key;
        latest = MonthlyBill.fromDoc(doc);
      }
      if (model == MonthlyBill.statementModel &&
          (latestStatementKey == null ||
              key.compareTo(latestStatementKey) > 0)) {
        latestStatementKey = key;
        latestStatement = MonthlyBill.fromDoc(doc);
      }
    }
    if (preferStatement && latestStatement != null) return latestStatement;
    return latest;
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  GoatChargeInput _goatInput(
      String goatId,
      Map<String, dynamic> data, {
        required String? lastBilledKey,
        required DateTime fallbackBilledThrough,
      }) {
    DateTime? date(String key) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final isDead = data['status']?.toString() == 'dead' ||
        data['isDead'] == true;
    final closed = data['isCheckedOut'] == true || isDead;
    final leave = closed
        ? (isDead ? (date('deathDate') ?? date('checkOutDate'))
        : (date('checkOutDate') ?? date('deathDate')))
        : null;

    final billingStart = date('farmArrivalDate') ??
        date('checkInDate') ??
        date('registrationDate');

    return GoatChargeInput(
      goatId: goatId,
      label: _goatLabel(data),
      monthlyRate: ((data['pricing'] as num?)?.toDouble() ?? 0),
      billingStart: billingStart,
      leaveDate: leave,
      billedThrough: effectiveBilledThrough(
        stored: date('billedThroughDate'),
        closedUnderOldCode: closed,
        leaveDate: leave,
        lastBilledKey: lastBilledKey,
        fallback: fallbackBilledThrough,
      ),
    );
  }

  String _goatLabel(Map<String, dynamic> data) {
    for (final key in ['name', 'goatCode', 'tagNumber']) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'Goat';
  }

  static String? _maxKey(String? a, String? b) {
    final validA = parsePeriodKey(a) != null ? a : null;
    final validB = parsePeriodKey(b) != null ? b : null;
    if (validA == null) return validB;
    if (validB == null) return validA;
    return validA.compareTo(validB) >= 0 ? validA : validB;
  }
}

/// Minimal view of a bill document read from a query (outside a
/// transaction), used for planning only.
class _QueryBill {
  _QueryBill(this.data);

  final Map<String, dynamic> data;

  String get customerId => (data['customerId'] ?? '').toString();

  String get type => (data['type'] ?? '').toString();

  bool get isVoid =>
      data['isVoid'] == true || data['status']?.toString() == 'void';

  String? get periodKey {
    final explicit =
    (data['billingPeriodKey'] ?? data['periodMonth'])?.toString();
    if (parsePeriodKey(explicit) != null) return explicit;
    final month = data['billingMonth'];
    if (month is Timestamp) {
      final d = month.toDate();
      return periodKeyOf(d.year, d.month);
    }
    return null;
  }
}