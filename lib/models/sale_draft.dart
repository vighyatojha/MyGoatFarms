import '../models/goat_model.dart';
import '../services/sales_service.dart';
import 'sale_model.dart';

/// Shared in-memory state for the Sell Goat wizard.
///
/// One SaleDraft instance is created when the wizard opens and is passed
/// through all wizard steps. Nothing is written to Firestore until the
/// sale is saved (Step 5's branch-specific save action).
///
/// Branch B (Booking) and Branch C (Wait for Delivery) fields are not
/// included yet — per the plan's build order, Branch A (Deliver Now)
/// and Branch D (Transfer to Palai) are built first.
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

  // --- Branch D: Transfer to Palai (Task 3.4) --------------------------------

  DateTime? transferDate;
  String palaiPackage = '';
  double monthlyPalaiCharge = 0;
}