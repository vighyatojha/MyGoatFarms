import '../models/goat_model.dart';
import '../services/sales_service.dart';
import 'expense_categories.dart';
import 'sale_model.dart';

/// Shared in-memory state for the Sell Goat wizard.
///
/// One SaleDraft instance is created when the wizard opens and is passed
/// through all wizard steps. Nothing is written to Firestore until the
/// sale is saved (Step 5's branch-specific save action).
///
/// All four Section-3 branches (Deliver Now, Booking/Holding,
/// Wait for Delivery, Transfer to Palai) have their creation-time
/// fields here. Each branch's "Complete Delivery" follow-up action
/// (Pair 7 / Phase 5) is out of scope for this phase.
class SaleDraft {
  // ---------------------------------------------------------------------------
  // NUMBER HELPERS
  // ---------------------------------------------------------------------------

  /// Rounds to 2 decimals (paise / 10 g).
  ///
  /// Dart doubles cannot represent most decimals exactly, so raw sums and
  /// products drift: 34.2 + 18.6 = 52.800000000000004 and
  /// 52.8 * 520 = 27456.000000000004. Left alone, that shows up as ugly
  /// text ("52.800000000000004 KG") and — worse — makes
  /// `amountReceived >= totalSaleAmount` fail when the customer paid the
  /// exact amount, flipping "Paid" to "Partial".
  ///
  /// Every derived money/weight figure in this draft goes through here.
  static double round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;

    // The tiny epsilon nudges values such as 1.005 (stored as
    // 1.00499999999999989...) to the rounding a human expects.
    final nudge = value >= 0 ? 1e-9 : -1e-9;

    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  /// Never negative, never `-0.0` (which NumberFormat would print as
  /// "-₹0.00").
  static double _nonNegative(double value) {
    final rounded = round2(value);

    return rounded <= 0 ? 0.0 : rounded;
  }

  /// Weight for display: at most 2 decimals, trailing zeros removed.
  ///   50.0 -> "50"   50.8 -> "50.8"   50.05 -> "50.05"
  static String formatWeight(double value) {
    final fixed = round2(value).toStringAsFixed(2);

    if (!fixed.contains('.')) return fixed;

    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  // ---------------------------------------------------------------------------
  // STEP 1 — SELECT GOAT(S)  (Task 2.1)
  // ---------------------------------------------------------------------------

  /// The full Goat objects for every goat included in this sale, not
  /// just their IDs — Step 3 (Selected Goat Details) needs
  /// Photo/ID/Breed/Gender/Age/Current Weight for each one, and building
  /// that from IDs alone would mean re-fetching every goat again.
  List<Goat> selectedGoats = [];

  List<String> get goatIds =>
      selectedGoats.map((g) => g.id).toList();

  bool get isMultiGoat => selectedGoats.length > 1;

  // ---------------------------------------------------------------------------
  // STEP 2 — CUSTOMER MOBILE LOOKUP  (Task 2.2)
  // ---------------------------------------------------------------------------

  String mobile = '';
  String customerName = '';
  String address = '';

  /// Set once a match (new or existing) has been confirmed on Step 2.
  /// Null means the person has typed a mobile number but not yet
  /// picked/confirmed who it belongs to.
  CustomerMatchSource? customerSource;

  /// Firestore doc ID of the matched/created customer:
  /// - customerSource == sale  -> farms/{farmId}/customers/{customerId}
  /// - customerSource == palai -> farms/{farmId}/palaiCustomers/{id}
  /// - null (brand-new customer, not yet saved) -> empty string; the
  ///   Sale save step creates the `customers` doc at save time.
  String customerId = '';

  bool get isExistingCustomer => customerSource != null;

  bool get isExistingPalaiCustomer =>
      customerSource == CustomerMatchSource.palai;

  void applyMatch(CustomerMatch match) {
    customerSource = match.source;
    customerId = match.id;
    customerName = match.name;
    mobile = match.mobile;
    address = match.address;
  }

  void clearCustomerMatch() {
    customerSource = null;
    customerId = '';
  }

  // ---------------------------------------------------------------------------
  // STEP 3 — SELECTED GOAT DETAILS  (Task 2.3)
  // ---------------------------------------------------------------------------

  /// Selling weight per goat, keyed by goat ID. Selling weight may
  /// differ slightly from the goat's last recorded weight, so this is
  /// edited independently rather than reusing Goat.weight directly.
  /// Falls back to the goat's recorded weight until edited.
  final Map<String, double> _sellingWeights = {};

  double weightFor(Goat goat) => _sellingWeights[goat.id] ?? goat.weight;

  void setWeight(Goat goat, double weight) {
    _sellingWeights[goat.id] = weight;
  }

  /// Gender per goat, keyed by goat ID. Trading's Goat Registration
  /// never captured gender (see Goat.gender's doc comment) — this is
  /// the one place it's ever asked, and it's written back onto the goat
  /// doc when the sale saves so it isn't asked again next time. Falls
  /// back to whatever's already on the goat record, if anything.
  final Map<String, String> _genders = {};

  String genderFor(Goat goat) => _genders[goat.id] ?? goat.gender;

  void setGender(Goat goat, String gender) {
    _genders[goat.id] = gender;
  }

  /// Sum of every selected goat's selling weight — this is what Step 4
  /// treats as the sale's total Selling Weight. It is deliberately
  /// derived from Step 3's per-goat entries rather than re-entered as
  /// an independent value in Step 4, so the two steps can never
  /// disagree about how much is being sold.
  double get totalSellingWeight => round2(
    selectedGoats.fold(
      0.0,
          (sum, g) => sum + weightFor(g),
    ),
  );

  /// Sum of every selected goat's last *recorded* weight. Only used by
  /// Step 3 to show how far the entered selling weights are from the
  /// weights already on file.
  double get totalRecordedWeight => round2(
    selectedGoats.fold(0.0, (sum, g) => sum + g.weight),
  );

  // ---------------------------------------------------------------------------
  // STEP 4 — SALE DETAILS  (Task 2.4)
  // ---------------------------------------------------------------------------

  double sellingPricePerKg = 0;

  /// Derived: never manually overridden, same rule as the Purchase
  /// wizard's Purchase Amount.
  double get totalSaleAmount =>
      round2(totalSellingWeight * sellingPricePerKg);

  // ---------------------------------------------------------------------------
  // STEP 5 — DELIVERY OPTIONS  (Section 3)
  // ---------------------------------------------------------------------------

  /// One of Sale.deliveryTypeValues, or '' until a branch is picked.
  String deliveryType = '';

  bool get isDeliverNow =>
      deliveryType == Sale.deliveryTypeDeliverNow;

  bool get isBooking =>
      deliveryType == Sale.deliveryTypeBooking;

  bool get isWaitForDelivery =>
      deliveryType == Sale.deliveryTypeWaitForDelivery;

  bool get isPalaiTransfer =>
      deliveryType == Sale.deliveryTypePalai;

  /// How the money taken now is being paid (Cash, UPI, ...). Shared by
  /// the three branches that take a payment at the sale: Deliver Now
  /// (amount received), Booking (booking amount) and Wait for Delivery
  /// (advance). Saved on the sale and used as the payment method of the
  /// Finance entry for that money.
  String paymentMethod = FinancePaymentMethods.cash;

  // --- Branch A: Deliver Now (Task 3.1) --------------------------------------

  double transportCost = 0;
  double amountReceived = 0;

  /// What the customer actually owes: sale amount + transport charge.
  /// Transportation is billed to the customer but paid on to the
  /// transport team, so it is part of this total and NOT farm revenue —
  /// SalesService's revenue write uses [totalSaleAmount] instead.
  double get customerTotalDeliverNow =>
      round2(totalSaleAmount + transportCost);

  double get remainingBalanceDeliverNow =>
      _nonNegative(customerTotalDeliverNow - amountReceived);

  /// How much MORE than the customer total was entered as received. Not
  /// blocked (the person may be rounding up, or settling something else
  /// in the same handover) but Step 5 surfaces it so a typo such as an
  /// extra digit is obvious before saving.
  double get extraReceivedDeliverNow =>
      _nonNegative(amountReceived - customerTotalDeliverNow);

  String get paymentStatusDeliverNow {
    final received = round2(amountReceived);

    if (received <= 0) return Sale.paymentStatusPending;
    if (received >= customerTotalDeliverNow) return Sale.paymentStatusPaid;
    return Sale.paymentStatusPartial;
  }

  // --- Branch B: Booking / Holding (Task 3.2) ---------------------------------

  double bookingAmount = 0;
  DateTime? expectedDeliveryDate;
  int holdingDays = 0;
  double holdingChargePerDay = 0;

  /// Transportation charge for this booking, billed to the customer —
  /// same rule as Branch A. Typically collected/confirmed when the
  /// goat is actually handed over (Complete Delivery), but can be
  /// estimated here at booking time too. Named distinctly from Branch
  /// A's [transportCost] since both live flat on the same draft.
  double bookingTransportCost = 0;

  /// Auto-calculated: Holding Days x Daily Charge — never entered
  /// directly, same "derived field" rule as totalSaleAmount.
  double get totalHoldingCharges =>
      round2(holdingDays * holdingChargePerDay);

  /// Sale amount + holding charges + transport — what the customer owes
  /// in total before the booking amount is deducted.
  double get totalPayableBooking =>
      round2(totalSaleAmount + totalHoldingCharges + bookingTransportCost);

  /// What's left to collect once holding charges and transport are added
  /// on top of the sale amount and the booking amount already paid is
  /// deducted. The actual "Complete Delivery" recompute redoes this same
  /// sum later using whatever holding days actually elapse and whatever
  /// transport is confirmed then — this is just the creation-time
  /// estimate shown on Step 5.
  double get remainingBalanceBooking =>
      _nonNegative(totalPayableBooking - bookingAmount);

  // --- Branch C: Wait for Delivery (Task 3.3) --------------------------------

  /// Price/kg is fixed at booking time, using whatever was set on
  /// Step 4 — never re-entered separately, and never re-priced at the
  /// market rate on pickup day. The eventual "Complete Delivery" action
  /// (out of scope this phase) must use this same value, not whatever
  /// the market rate is on that day.
  double get bookingPricePerKg => sellingPricePerKg;

  /// Weight at booking time, same total Step 3 already collected —
  /// re-weighing happens later, at pickup, as part of Complete Delivery.
  double get bookingWeightTotal => totalSellingWeight;

  double bookingAdvanceAmount = 0;

  /// Transportation charge for this booking, billed to the customer —
  /// same rule as Branch A. Confirmed for real at pickup (Complete
  /// Delivery), but can be estimated here at booking time too. Named
  /// distinctly from the other two branches' transport fields since
  /// all three live flat on the same draft.
  double waitForDeliveryTransportCost = 0;

  /// Customer total at today's estimate: sale amount + transport. The
  /// real payable amount is settled at pickup using pickup weight x
  /// booking rate + whatever transport is confirmed then.
  double get customerTotalWaitForDelivery =>
      round2(totalSaleAmount + waitForDeliveryTransportCost);

  /// Estimate at BOOKING weight. The real amount is settled at pickup
  /// (pickup weight x this same booking rate + transport - advance).
  double get remainingAdvanceBalanceWaitForDelivery =>
      _nonNegative(customerTotalWaitForDelivery - bookingAdvanceAmount);

  // --- Branch D: Transfer to Palai (Task 3.4) --------------------------------

  DateTime? transferDate;
  String palaiPackage = '';
  double monthlyPalaiCharge = 0;
}