/// Pure calculation rules for statement billing.
///
/// Nothing in this file touches Firestore, so every rule here can be unit
/// tested on its own (see test/billing_ledger_test.dart). The services
/// only read documents, call these functions, and write the results.
///
/// THE MODEL
/// ---------
/// A monthly bill is a STATEMENT for the previous month:
///
///   Total Payable = this month's charges
///                 + Previous Outstanding (carried forward, never re-charged)
///                 − Advance applied
///
/// Underneath the statement, every bill also tracks its OWN month's charge
/// (ownCharges / ownPaid / ownRemaining). Payments, advance and waivers
/// always clear the oldest unpaid month first. The customer's
/// pendingAmount is the single source of truth for the total owed.
library;

import 'palai_proration.dart';

const double kMoneyEpsilon = 0.005;

double roundMoney(num value) => (value * 100).roundToDouble() / 100;

double _max0(double v) => v < 0 ? 0.0 : v;

// ===========================================================================
// PERIODS
// ===========================================================================

String periodKeyOf(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

/// Parses 'YYYY-MM'. Returns null for anything else.
({int year, int month})? parsePeriodKey(String? key) {
  if (key == null) return null;
  final parts = key.split('-');
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return null;
  return (year: year, month: month);
}

/// The month a run on [now] bills: always the previous calendar month.
/// Generating on 3 Oct 2026 bills September 2026.
String targetPeriodKeyFor(DateTime now) {
  final previous = DateTime(now.year, now.month - 1, 1);
  return periodKeyOf(previous.year, previous.month);
}

String nextPeriodKey(String key) {
  final p = parsePeriodKey(key)!;
  final next = DateTime(p.year, p.month + 1, 1);
  return periodKeyOf(next.year, next.month);
}

DateTime periodStart(String key) {
  final p = parsePeriodKey(key)!;
  return DateTime(p.year, p.month, 1);
}

DateTime periodEnd(String key) {
  final p = parsePeriodKey(key)!;
  return DateTime(p.year, p.month + 1, 0);
}

/// Months still to bill, oldest first.
///
/// * Never billed before → only [targetKey]. A first statement never
///   back-bills older months; anything owed from before is already in the
///   customer's pendingAmount and is carried forward.
/// * Already billed up to or past [targetKey] → nothing.
/// * Otherwise every month after [lastBilledKey] up to [targetKey], capped
///   at [maxMonths] so one run can never produce a surprise year of bills.
List<String> periodsToGenerate({
  required String? lastBilledKey,
  required String targetKey,
  int maxMonths = 12,
}) {
  if (lastBilledKey == null) return [targetKey];
  if (lastBilledKey.compareTo(targetKey) >= 0) return const [];

  final result = <String>[];
  var cursor = nextPeriodKey(lastBilledKey);
  while (cursor.compareTo(targetKey) <= 0 && result.length < maxMonths) {
    result.add(cursor);
    cursor = nextPeriodKey(cursor);
  }
  return result;
}

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// 'September 2026'
String periodLabel(String key) {
  final p = parsePeriodKey(key);
  if (p == null) return key;
  return '${_monthNames[p.month - 1]} ${p.year}';
}

// ===========================================================================
// OLDEST-FIRST ALLOCATION
// ===========================================================================

/// One month's unpaid own charge, as read from a bill.
class LedgerMonth {
  const LedgerMonth({
    required this.billId,
    required this.periodKey,
    required this.ownRemaining,
  });

  final String billId;
  final String periodKey;
  final double ownRemaining;
}

class MonthAllocation {
  const MonthAllocation({
    required this.billId,
    required this.periodKey,
    required this.amount,
    required this.remainingAfter,
  });

  final String billId;
  final String periodKey;
  final double amount;
  final double remainingAfter;

  Map<String, dynamic> toMap() => {
    'billId': billId,
    'periodKey': periodKey,
    'amount': amount,
  };
}

class AllocationResult {
  const AllocationResult({
    required this.allocations,
    required this.applied,
    required this.leftover,
  });

  final List<MonthAllocation> allocations;

  /// Total put against months.
  final double applied;

  /// What could not be put against any month. For a payment this is the
  /// part that pays Palai dues not tied to a bill (checkout charges, older
  /// manual balances) or goes further down the line.
  final double leftover;
}

/// Puts [amount] against [months], oldest month first, never paying a
/// month more than it still owes. [months] may be in any order.
AllocationResult allocateOldestFirst(
    List<LedgerMonth> months,
    double amount,
    ) {
  var remaining = roundMoney(_max0(amount));
  final sorted = [...months]
    ..sort((a, b) => a.periodKey.compareTo(b.periodKey));

  final allocations = <MonthAllocation>[];
  for (final month in sorted) {
    if (remaining <= kMoneyEpsilon) break;
    final owed = roundMoney(_max0(month.ownRemaining));
    if (owed <= kMoneyEpsilon) continue;

    final take = owed < remaining ? owed : remaining;
    remaining = roundMoney(remaining - take);
    allocations.add(
      MonthAllocation(
        billId: month.billId,
        periodKey: month.periodKey,
        amount: roundMoney(take),
        remainingAfter: roundMoney(owed - take),
      ),
    );
  }

  final applied = roundMoney(
    allocations.fold<double>(0, (sum, a) => sum + a.amount),
  );

  return AllocationResult(
    allocations: allocations,
    applied: applied,
    leftover: remaining,
  );
}

// ===========================================================================
// PREVIOUS OUTSTANDING (CARRY FORWARD)
// ===========================================================================

class BreakdownLine {
  const BreakdownLine({
    required this.periodKey,
    required this.amount,
    this.billId,
  });

  final String periodKey;
  final double amount;
  final String? billId;

  Map<String, dynamic> toMap() => {
    'periodKey': periodKey,
    'amount': amount,
    if (billId != null) 'billId': billId,
  };

  factory BreakdownLine.fromMap(Map<String, dynamic> map) => BreakdownLine(
    periodKey: map['periodKey']?.toString() ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0,
    billId: map['billId']?.toString(),
  );
}

class PreviousOutstandingBreakdown {
  const PreviousOutstandingBreakdown({
    required this.lines,
    required this.earlierBalance,
    required this.normalizedRemaining,
  });

  /// Unpaid amount per month, oldest first.
  final List<BreakdownLine> lines;

  /// Part of the outstanding not tied to any monthly bill (checkout
  /// charges, manual balances, or debt from before statement billing).
  final double earlierBalance;

  /// Months whose recorded ownRemaining was MORE than the customer can
  /// actually still owe (left over from the old billing code, which could
  /// reduce pendingAmount without touching the bills). Maps billId → the
  /// corrected ownRemaining so the ledger matches pendingAmount again.
  final Map<String, double> normalizedRemaining;
}

/// Splits the customer's [pending] into per-month lines.
///
/// pendingAmount is the source of truth. If the open months add up to
/// more than [pending], the extra must already have been paid, and since
/// payments clear the oldest month first, the debt that is really left is
/// the NEWEST months' — so months are covered newest-first, and anything
/// older that the pending amount cannot cover is normalized down.
PreviousOutstandingBreakdown buildPreviousBreakdown({
  required List<LedgerMonth> openMonths,
  required double pending,
}) {
  var budget = roundMoney(_max0(pending));
  final newestFirst = [...openMonths]
    ..sort((a, b) => b.periodKey.compareTo(a.periodKey));

  final lines = <BreakdownLine>[];
  final normalized = <String, double>{};

  for (final month in newestFirst) {
    final owed = roundMoney(_max0(month.ownRemaining));
    if (owed <= kMoneyEpsilon) continue;

    final covered = owed < budget ? owed : budget;
    budget = roundMoney(budget - covered);

    if (covered > kMoneyEpsilon) {
      lines.add(
        BreakdownLine(
          periodKey: month.periodKey,
          amount: roundMoney(covered),
          billId: month.billId,
        ),
      );
    }

    if (owed - covered > kMoneyEpsilon) {
      normalized[month.billId] = roundMoney(covered);
    }
  }

  lines.sort((a, b) => a.periodKey.compareTo(b.periodKey));

  return PreviousOutstandingBreakdown(
    lines: lines,
    earlierBalance: budget,
    normalizedRemaining: normalized,
  );
}

// ===========================================================================
// GOAT CHARGES
// ===========================================================================

class GoatChargeInput {
  const GoatChargeInput({
    required this.goatId,
    required this.label,
    required this.monthlyRate,
    required this.billingStart,
    required this.leaveDate,
    required this.billedThrough,
  });

  final String goatId;
  final String label;
  final double monthlyRate;

  /// Farm arrival date (first billable day).
  final DateTime? billingStart;

  /// Checkout or death date (last billable day), null while on the farm.
  final DateTime? leaveDate;

  /// Last day already charged by a bill, checkout or death settlement.
  final DateTime billedThrough;
}

class GoatChargeLine {
  const GoatChargeLine({
    required this.goatId,
    required this.label,
    required this.monthlyRate,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.daysInMonth,
    required this.amount,
  });

  final String goatId;
  final String label;
  final double monthlyRate;
  final DateTime fromDate;
  final DateTime toDate;
  final int days;
  final int daysInMonth;
  final double amount;
}

/// Works out one goat's charge for the month [periodKey]:
///
///   from = latest of (month start, arrival date, day after billedThrough)
///   to   = earliest of (month end, checkout/death date)
///
/// Returns null when there is nothing to charge (not on the farm that
/// month, or those days were already charged by checkout/death/an earlier
/// bill), which is what makes double billing impossible.
GoatChargeLine? chargeGoatForPeriod(GoatChargeInput goat, String periodKey) {
  final monthStart = periodStart(periodKey);
  final monthEnd = periodEnd(periodKey);

  var from = monthStart;
  if (goat.billingStart != null) {
    final arrival = palaiDateOnly(goat.billingStart!);
    if (arrival.isAfter(from)) from = arrival;
  }
  final billed = palaiDateOnly(goat.billedThrough);
  final afterBilled = DateTime(billed.year, billed.month, billed.day + 1);
  if (afterBilled.isAfter(from)) from = afterBilled;

  var to = monthEnd;
  if (goat.leaveDate != null) {
    final left = palaiDateOnly(goat.leaveDate!);
    if (left.isBefore(to)) to = left;
  }

  if (to.isBefore(from)) return null;

  final dim = PalaiProrationCalculator.daysInMonth(
    monthStart.year,
    monthStart.month,
  );
  final days = palaiDaysInclusive(from, to);
  final rate = goat.monthlyRate < 0 ? 0.0 : goat.monthlyRate;

  return GoatChargeLine(
    goatId: goat.goatId,
    label: goat.label,
    monthlyRate: rate,
    fromDate: from,
    toDate: to,
    days: days,
    daysInMonth: dim,
    amount: roundMoney(rate / dim * days),
  );
}

/// The last day a goat counts as already charged for.
///
/// Uses the stored billedThroughDate when there is one. Older goats were
/// billed before that field existed, so for them:
/// * a goat already checked out / dead under the old code was charged up
///   to its leaving date by that checkout → [leaveDate];
/// * otherwise, up to the end of the customer's last billed month;
/// * a customer never billed at all → [fallback] (the day before the
///   first month the new system will charge).
DateTime effectiveBilledThrough({
  required DateTime? stored,
  required bool closedUnderOldCode,
  required DateTime? leaveDate,
  required String? lastBilledKey,
  required DateTime fallback,
}) {
  if (stored != null) return palaiDateOnly(stored);
  if (closedUnderOldCode && leaveDate != null) return palaiDateOnly(leaveDate);
  if (lastBilledKey != null && parsePeriodKey(lastBilledKey) != null) {
    return periodEnd(lastBilledKey);
  }
  return palaiDateOnly(fallback);
}

// ===========================================================================
// STATEMENT TOTALS
// ===========================================================================

class StatementTotals {
  const StatementTotals({
    required this.previousOutstanding,
    required this.currentCharges,
    required this.advanceApplied,
    required this.totalPayable,
    required this.advanceAfter,
  });

  final double previousOutstanding;
  final double currentCharges;
  final double advanceApplied;
  final double totalPayable;
  final double advanceAfter;
}

/// Total Payable = currentCharges + previousOutstanding − advance applied.
/// Advance is used up to what is owed; the rest stays as advance.
StatementTotals computeStatement({
  required double previousOutstanding,
  required double currentCharges,
  required double advanceAvailable,
}) {
  final prev = roundMoney(_max0(previousOutstanding));
  final current = roundMoney(_max0(currentCharges));
  final advance = roundMoney(_max0(advanceAvailable));
  final owed = roundMoney(prev + current);
  final applied = advance < owed ? advance : owed;

  return StatementTotals(
    previousOutstanding: prev,
    currentCharges: current,
    advanceApplied: roundMoney(applied),
    totalPayable: roundMoney(owed - applied),
    advanceAfter: roundMoney(advance - applied),
  );
}

/// 'paid' / 'partial' / 'unpaid' for any paid-vs-remaining pair.
String paymentStatusFor({required double paid, required double remaining}) {
  if (remaining <= kMoneyEpsilon) return 'paid';
  if (paid > kMoneyEpsilon) return 'partial';
  return 'unpaid';
}

// ===========================================================================
// CORRECTIONS (edit / void the latest statement)
// ===========================================================================

class StatementEdit {
  const StatementEdit({
    required this.newCharges,
    required this.ownRemaining,
    required this.totalPayable,
    required this.remaining,
    required this.pendingDelta,
  });

  /// The month's corrected own charge.
  final double newCharges;

  /// Corrected unpaid part of the month's own charge.
  final double ownRemaining;

  /// previousOutstanding + newCharges − advanceApplied.
  final double totalPayable;

  /// totalPayable − amount already paid against the statement.
  final double remaining;

  /// How much the customer's pendingAmount moves (only the difference
  /// between the new and old charge — nothing else is re-charged).
  final double pendingDelta;
}

/// Works out an edit of the latest statement's own charge. The advance
/// applied and the previous outstanding stay exactly as issued.
///
/// Throws [StateError] when the new charge would be less than what has
/// already been paid on this month, or the new Total Payable less than
/// what has already been paid against the statement.
StatementEdit computeStatementEdit({
  required double oldCharges,
  required double newCharges,
  required double ownPaid,
  required double previousOutstanding,
  required double advanceApplied,
  required double amountPaid,
}) {
  final charges = roundMoney(_max0(newCharges));
  if (charges + kMoneyEpsilon < ownPaid) {
    throw StateError(
      'The month\'s charges cannot be less than the ₹${ownPaid.toStringAsFixed(2)} '
          'already paid on it.',
    );
  }

  final totalPayable = roundMoney(previousOutstanding + charges - advanceApplied);
  if (totalPayable + kMoneyEpsilon < amountPaid) {
    throw StateError(
      'The total payable cannot be less than the ₹${amountPaid.toStringAsFixed(2)} '
          'already paid against this bill.',
    );
  }

  return StatementEdit(
    newCharges: charges,
    ownRemaining: roundMoney(charges - ownPaid),
    totalPayable: totalPayable,
    remaining: roundMoney(_max0(totalPayable - amountPaid)),
    pendingDelta: roundMoney(charges - oldCharges),
  );
}

/// Reverses a voided statement's effect on the customer's pending: its
/// own charge comes off and the advance it used goes back to advance.
double voidPendingDelta({
  required double ownCharges,
  required double advanceApplied,
}) =>
    roundMoney(-(ownCharges - advanceApplied));