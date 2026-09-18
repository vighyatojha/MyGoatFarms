import '../models/goat_model.dart';
import '../services/sales_service.dart';
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
  double get totalSellingWeight => selectedGoats.fold(
    0.0,
        (sum, g) => sum + weightFor(g),
  );

  // ---------------------------------------------------------------------------
  // STEP 4 — SALE DETAILS  (Task 2.4)
  // ---------------------------------------------------------------------------

  double sellingPricePerKg = 0;

  /// Derived: never manually overridden, same rule as the Purchase
  /// wizard's Purchase Amount.
  double get totalSaleAmount => totalSellingWeight * sellingPricePerKg;

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

  // --- Branch A: Deliver Now (Task 3.1) --------------------------------------

  double transportCost = 0;
  double amountReceived = 0;

  double get remainingBalanceDeliverNow {
    final remaining = totalSaleAmount - amountReceived;
    return remaining < 0 ? 0 : remaining;
  }

  String get paymentStatusDeliverNow {
    if (amountReceived <= 0) return Sale.paymentStatusPending;
    if (amountReceived >= totalSaleAmount) return Sale.paymentStatusPaid;
    return Sale.paymentStatusPartial;
  }

  // --- Branch B: Booking / Holding (Task 3.2) ---------------------------------

  double bookingAmount = 0;
  DateTime? expectedDeliveryDate;
  int holdingDays = 0;
  double holdingChargePerDay = 0;

  /// Auto-calculated: Holding Days x Daily Charge — never entered
  /// directly, same "derived field" rule as totalSaleAmount.
  double get totalHoldingCharges => holdingDays * holdingChargePerDay;

  /// What's left to collect once holding charges are added on top of
  /// the sale amount and the booking amount already paid is deducted.
  /// The actual "Complete Delivery" recompute (Task 3.2's follow-up,
  /// out of scope this phase) does this same sum again later using
  /// whatever holding days actually elapse — this is just the
  /// creation-time estimate shown on Step 5.
  double get remainingBalanceBooking {
    final remaining =
        totalSaleAmount + totalHoldingCharges - bookingAmount;
    return remaining < 0 ? 0 : remaining;
  }

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

  double get remainingAdvanceBalanceWaitForDelivery {
    final remaining = totalSaleAmount - bookingAdvanceAmount;
    return remaining < 0 ? 0 : remaining;
  }

  // --- Branch D: Transfer to Palai (Task 3.4) --------------------------------

  DateTime? transferDate;
  String palaiPackage = '';
  double monthlyPalaiCharge = 0;
}