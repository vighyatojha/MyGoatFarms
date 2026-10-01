/// What to do with money the customer has paid beyond what they owe.
enum ExcessAction { carryToAdvance, refundToCustomer }

/// Pure settlement maths shared by every sale / delivery screen, so the
/// discount and the excess-advance rules live in exactly one place.
///
/// Example (delivery): 85 kg x 620 = 52,700, advance 60,000
///   -> excess 7,300 -> carried to the customer's advance, or refunded.
/// Example (discount): 32,500 sale, discount 500, paid 3,200
///   -> net 32,000, balance 28,800.
class SaleSettlement {
  SaleSettlement({
    required this.weightKg,
    required this.ratePerKg,
    this.discount = 0,
    this.transportCharge = 0,
    this.advancePaid = 0,
    this.paidNow = 0,
    this.excessAction = ExcessAction.carryToAdvance,
  });

  final double weightKg;
  final double ratePerKg;
  final double discount;
  final double transportCharge;
  final double advancePaid;

  /// Cash collected at this step (on top of any advance).
  final double paidNow;
  final ExcessAction excessAction;

  /// Goat value before discount. This is the farm's revenue basis.
  double get goatAmount => weightKg * ratePerKg;

  /// Discount can never exceed the goat amount.
  double get appliedDiscount =>
      discount.clamp(0, goatAmount).toDouble();

  /// Revenue after discount (transport is NOT farm revenue).
  double get netRevenue => goatAmount - appliedDiscount;

  /// What the customer must pay in total (revenue + transport).
  double get payable => netRevenue + transportCharge;

  double get totalPaid => advancePaid + paidNow;

  /// Still owed by the customer (never negative).
  double get balanceDue => (payable - totalPaid).clamp(0, double.infinity);

  /// Paid beyond what is owed (never negative).
  double get excess => (totalPaid - payable).clamp(0, double.infinity);

  /// Added to the customer's advance balance.
  double get creditToAdvance =>
      excessAction == ExcessAction.carryToAdvance ? excess : 0;

  /// Money handed back to the customer (record as a Finance outflow).
  double get refundAmount =>
      excessAction == ExcessAction.refundToCustomer ? excess : 0;
}