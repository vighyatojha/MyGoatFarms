import 'dart:math' as math;

/// Single source of truth for every Trading purchase cost figure.
///
/// The Purchase wizard (live, while typing), the save service and the
/// "Complete Receiving" screen all build one of these and read the same
/// getters, so what the person sees on screen is exactly what gets saved.
/// There is deliberately no second copy of this maths anywhere else.
///
/// Formulas (from the Trading flow PDF):
///
///   Purchase Amount       = Weight at Purchase x Price per KG
///   Total Expenses        = Transport + Loading + Unloading + Other
///   Grand Total           = Purchase Amount + Total Expenses
///   Weight Loss           = Weight at Purchase - Weight After Arrival
///   Surviving Goats       = Total Goats - Mortality
///   Effective Cost / KG   = Grand Total / Weight After Arrival
///   Cost / Surviving Goat = Grand Total / Surviving Goats
///
/// Example: 350 kg x Rs 450 = Rs 1,57,500. Add Rs 6,000 of expenses ->
/// Grand Total Rs 1,63,500. 335 kg arrive and 1 of 20 goats is lost ->
/// Rs 488.06 per kg after arrival, Rs 8,605.26 per surviving goat.
///
/// Mortality does not change the Grand Total (the money was already
/// spent). It shows up where it really hurts: fewer goats and less weight
/// to spread the same cost over, so cost per KG and per goat go up.
class PurchaseCosting {
  final int totalGoats;
  final double weightAtPurchase;
  final double pricePerKg;

  /// 0 means "not received yet".
  final double weightAfterArrival;
  final int mortality;

  final double transportCost;
  final double loadingCharges;
  final double unloadingCharges;
  final double otherExpenses;

  const PurchaseCosting({
    this.totalGoats = 0,
    this.weightAtPurchase = 0,
    this.pricePerKg = 0,
    this.weightAfterArrival = 0,
    this.mortality = 0,
    this.transportCost = 0,
    this.loadingCharges = 0,
    this.unloadingCharges = 0,
    this.otherExpenses = 0,
  });

  // ---------------------------------------------------------------------------
  // NUMBER HELPERS
  // ---------------------------------------------------------------------------

  /// Rounds to 2 decimals.
  ///
  /// Dart doubles drift: 350.1 * 450 = 157545.00000000003. Every derived
  /// figure goes through here so nothing ugly is ever shown or saved, and
  /// comparisons such as "paid in full" never fail by a hair.
  static double round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;

    // Nudges values such as 1.005 (stored as 1.00499999...) to the rounding
    // a person expects.
    final nudge = value >= 0 ? 1e-9 : -1e-9;

    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  /// Never negative, never -0.0 (which would print as "-Rs 0.00").
  static double _nonNegative(double value) {
    final rounded = round2(value);

    return rounded <= 0 ? 0.0 : rounded;
  }

  /// For text fields and labels: at most 2 decimals, no trailing zeros.
  ///   350.0 -> "350"   350.5 -> "350.5"   350.25 -> "350.25"
  static String formatNumber(double value) {
    final fixed = round2(value).toStringAsFixed(2);

    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  // ---------------------------------------------------------------------------
  // PURCHASE
  // ---------------------------------------------------------------------------

  /// Weight at Purchase x Price per KG. Never entered by hand.
  double get purchaseAmount => round2(weightAtPurchase * pricePerKg);

  /// Purchase price of one goat on average, before any expenses.
  double get purchaseAmountPerGoat =>
      totalGoats > 0 ? round2(purchaseAmount / totalGoats) : 0;

  /// Average live weight per goat at purchase.
  double get avgWeightPerGoatAtPurchase =>
      totalGoats > 0 ? round2(weightAtPurchase / totalGoats) : 0;

  // ---------------------------------------------------------------------------
  // EXPENSES
  // ---------------------------------------------------------------------------

  /// Transport + Loading + Unloading + Other.
  double get totalExpenses => round2(
    transportCost + loadingCharges + unloadingCharges + otherExpenses,
  );

  /// Purchase Amount + Total Expenses.
  double get grandTotal => round2(purchaseAmount + totalExpenses);

  // ---------------------------------------------------------------------------
  // RECEIVING (arrival weight + mortality)
  // ---------------------------------------------------------------------------

  /// True once an arrival weight has been entered. Every "after arrival"
  /// figure below is 0 until then, instead of showing something misleading
  /// such as a weight loss equal to the whole purchase weight.
  bool get hasArrival => weightAfterArrival > 0;

  /// Mortality can never exceed the number of goats bought.
  int get safeMortality => math.max(0, math.min(mortality, totalGoats));

  int get survivingGoats => math.max(0, totalGoats - safeMortality);

  double get weightLoss => hasArrival
      ? _nonNegative(weightAtPurchase - weightAfterArrival)
      : 0;

  /// Weight loss as a share of purchase weight, e.g. 4.29 (%).
  double get weightLossPercent =>
      hasArrival && weightAtPurchase > 0
          ? round2(weightLoss / weightAtPurchase * 100)
          : 0;

  /// Average live weight per surviving goat on arrival.
  double get avgWeightPerSurvivorAfterArrival =>
      hasArrival && survivingGoats > 0
          ? round2(weightAfterArrival / survivingGoats)
          : 0;

  // ---------------------------------------------------------------------------
  // TRUE COST AFTER TRANSPORT, MORTALITY AND ARRIVAL WEIGHT
  // ---------------------------------------------------------------------------

  /// Grand Total / Weight After Arrival.
  double get effectiveCostPerKg =>
      hasArrival ? round2(grandTotal / weightAfterArrival) : 0;

  /// How much dearer each kg is than the rate paid to the seller.
  double get costIncreasePerKg => hasArrival
      ? round2(effectiveCostPerKg - pricePerKg)
      : 0;

  /// Grand Total / goats that actually arrived alive.
  double get costPerSurvivingGoat =>
      hasArrival && survivingGoats > 0
          ? round2(grandTotal / survivingGoats)
          : 0;

  /// Purchase value of the goats lost in transit. Informational only: it is
  /// already inside [grandTotal], and is the reason cost per goat rises.
  double get mortalityLoss => totalGoats > 0
      ? round2(purchaseAmount * safeMortality / totalGoats)
      : 0;

  // ---------------------------------------------------------------------------
  // VARIANTS
  // ---------------------------------------------------------------------------

  /// The same purchase with every receiving/transport figure removed.
  /// Used for the "receive later" path, where nothing after purchase is known
  /// yet and stale values typed earlier must not leak into the summary.
  PurchaseCosting withoutReceiving() {
    return PurchaseCosting(
      totalGoats: totalGoats,
      weightAtPurchase: weightAtPurchase,
      pricePerKg: pricePerKg,
    );
  }
}