/// What to do with money the customer has paid beyond what they owe.
enum ExcessAction { carryToAdvance, refundToCustomer }

extension ExcessActionStorage on ExcessAction {
  /// Value stored on the sale document.
  String get storageName =>
      this == ExcessAction.refundToCustomer ? 'refund' : 'advance';

  String get label => this == ExcessAction.refundToCustomer
      ? 'Return to customer'
      : "Add to customer's advance";
}

/// Pure settlement maths shared by every sale / delivery screen and by
/// SalesService, so the discount and the excess-advance rules live in
/// exactly one place.
///
/// Example (delivery): 85 kg x 620 = 52,700, advance 60,000
///   -> excess 7,300 -> carried to the customer's advance, or refunded.
/// Example (discount): 32,500 sale, discount 500, paid 3,200
///   -> net 32,000, balance 28,800.
///
/// Discount applies to the goat amount only. Holding charges and transport
/// are never discounted. Transport is billed to the customer but is NOT
/// farm revenue.
class SaleSettlement {
  /// Per-kg sale: pass [weightKg] and [ratePerKg].
  SaleSettlement({
    required this.weightKg,
    required this.ratePerKg,
    this.discount = 0,
    this.holdingCharges = 0,
    this.transportCharge = 0,
    this.advancePaid = 0,
    this.paidNow = 0,
    this.excessAction = ExcessAction.carryToAdvance,
  }) : goatAmountOverride = null;

  /// Fixed-price sale, lot sale or anywhere the goat value is already
  /// known: pass the [goatAmount] directly.
  SaleSettlement.fromAmount({
    required double goatAmount,
    this.discount = 0,
    this.holdingCharges = 0,
    this.transportCharge = 0,
    this.advancePaid = 0,
    this.paidNow = 0,
    this.excessAction = ExcessAction.carryToAdvance,
  })  : weightKg = 0,
        ratePerKg = 0,
        goatAmountOverride = goatAmount;

  final double weightKg;
  final double ratePerKg;
  final double? goatAmountOverride;
  final double discount;

  /// Booking / holding charges. Revenue, but never discounted.
  final double holdingCharges;
  final double transportCharge;

  /// Money already received before this step (booking amount / advance).
  final double advancePaid;

  /// Cash collected at this step (on top of any advance).
  final double paidNow;
  final ExcessAction excessAction;

  static double _round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;

    final nudge = value >= 0 ? 1e-9 : -1e-9;

    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  static double _nonNegative(double value) {
    final rounded = _round2(value);

    return rounded <= 0 ? 0.0 : rounded;
  }

  /// Goat value before discount.
  double get goatAmount =>
      _round2(goatAmountOverride ?? (weightKg * ratePerKg));

  /// Discount can never be negative or exceed the goat amount.
  double get appliedDiscount {
    final value = _round2(discount);

    if (value <= 0) return 0.0;
    if (value > goatAmount) return goatAmount;

    return value;
  }

  /// Goat value after discount.
  double get netGoatAmount => _round2(goatAmount - appliedDiscount);

  /// Farm revenue basis: discounted goat value + holding charges.
  /// Transport is NOT revenue.
  double get netRevenue => _round2(netGoatAmount + holdingCharges);

  /// What the customer must pay in total (revenue + transport).
  double get payable => _round2(netRevenue + transportCharge);

  double get totalPaid => _round2(advancePaid + paidNow);

  /// Still owed by the customer (never negative).
  double get balanceDue => _nonNegative(payable - totalPaid);

  /// Paid beyond what is owed (never negative).
  double get excess => _nonNegative(totalPaid - payable);

  bool get hasExcess => excess > 0;

  /// Added to the customer's advance balance.
  double get creditToAdvance =>
      excessAction == ExcessAction.carryToAdvance ? excess : 0.0;

  /// Money handed back to the customer (recorded as a Finance outflow).
  double get refundAmount =>
      excessAction == ExcessAction.refundToCustomer ? excess : 0.0;
}
