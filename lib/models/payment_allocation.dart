/// The ONE set of money rules for a customer's account.
///
/// Every screen and service that splits a payment (Trading sale, Palai
/// payment, Monthly Bill, Customer Ledger, Reports) should use these
/// functions instead of repeating its own clamp/subtract arithmetic, so the
/// same ₹ can never be counted twice.
///
/// Rules
/// -----
///  1. Money received is applied to what the customer owes FIRST.
///  2. Anything left over is the EXCESS.
///  3. Excess is exactly ONE of: customer advance, or a refund (cash out).
///  4. Advance and refund are NEVER revenue.
///  5. Advance can be used to pay a bill; what it pays is not new cash.
library;

/// Rounds to 2 decimals so floating point drift (27456.000000000004) never
/// flips a bill from "paid" to "partial".
double roundMoney(double value) {
  if (value.isNaN || value.isInfinite) return 0;
  return (value * 100).roundToDouble() / 100;
}

double _nonNegative(double value) => value < 0 ? 0 : roundMoney(value);

/// How one payment is split between a bill and the excess.
class PaymentAllocation {
  /// Cash the customer actually handed over.
  final double received;

  /// What was owed when the payment arrived.
  final double due;

  /// The part of [received] that pays the bill: min(received, due).
  final double appliedToBill;

  /// [received] - [appliedToBill]. Must become advance OR a refund.
  final double excess;

  /// What is still owed after the payment.
  final double remainingDue;

  const PaymentAllocation({
    required this.received,
    required this.due,
    required this.appliedToBill,
    required this.excess,
    required this.remainingDue,
  });

  bool get hasExcess => excess > 0;
  bool get isFullyPaid => remainingDue <= 0;
  bool get isUnderpaid => remainingDue > 0;

  /// Splits [received] against [due].
  ///
  ///   due 10000, received 12000 -> applied 10000, excess 2000
  ///   due 10000, received  7000 -> applied  7000, remaining 3000
  factory PaymentAllocation.split({
    required double received,
    required double due,
  }) {
    final r = _nonNegative(received);
    final d = _nonNegative(due);
    final applied = r < d ? r : d;

    return PaymentAllocation(
      received: r,
      due: d,
      appliedToBill: roundMoney(applied),
      excess: _nonNegative(r - applied),
      remainingDue: _nonNegative(d - applied),
    );
  }

  /// The part of the sale that counts as farm revenue: what was applied to
  /// the bill, capped at [revenueTotal] (transport is not revenue).
  /// Excess (advance or refund) is never included.
  double revenueFor(double revenueTotal) {
    final cap = _nonNegative(revenueTotal);
    return appliedToBill < cap ? appliedToBill : cap;
  }
}

/// How a customer's existing advance is used against a new bill.
class AdvanceUsage {
  final double advanceBefore;
  final double due;

  /// Advance consumed: min(advance, due).
  final double advanceUsed;

  /// Advance still available afterwards.
  final double advanceAfter;

  /// What the customer still has to pay after the advance is used.
  final double dueAfterAdvance;

  const AdvanceUsage({
    required this.advanceBefore,
    required this.due,
    required this.advanceUsed,
    required this.advanceAfter,
    required this.dueAfterAdvance,
  });

  /// advance 3000, due 5000 -> used 3000, due after 2000, advance after 0.
  factory AdvanceUsage.apply({
    required double advance,
    required double due,
  }) {
    final a = _nonNegative(advance);
    final d = _nonNegative(due);
    final used = a < d ? a : d;

    return AdvanceUsage(
      advanceBefore: a,
      due: d,
      advanceUsed: roundMoney(used),
      advanceAfter: _nonNegative(a - used),
      dueAfterAdvance: _nonNegative(d - used),
    );
  }
}

/// A customer's account position after a payment (Palai or monthly bill):
/// outstanding first, then advance for any excess.
class AccountPosition {
  final double pendingBefore;
  final double advanceBefore;
  final double appliedToPending;
  final double advanceAdded;
  final double pendingAfter;
  final double advanceAfter;

  const AccountPosition({
    required this.pendingBefore,
    required this.advanceBefore,
    required this.appliedToPending,
    required this.advanceAdded,
    required this.pendingAfter,
    required this.advanceAfter,
  });

  /// pending 5000, paid 7000 -> applied 5000, advance +2000.
  factory AccountPosition.afterPayment({
    required double pending,
    required double advance,
    required double paid,
    double appliedElsewhere = 0,
  }) {
    final split = PaymentAllocation.split(received: paid, due: pending);
    final spare = _nonNegative(split.excess - appliedElsewhere);

    return AccountPosition(
      pendingBefore: _nonNegative(pending),
      advanceBefore: _nonNegative(advance),
      appliedToPending: split.appliedToBill,
      advanceAdded: spare,
      pendingAfter: split.remainingDue,
      advanceAfter: _nonNegative(advance + spare),
    );
  }
}