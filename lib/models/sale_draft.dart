import '../models/goat_model.dart';
import '../services/sales_service.dart';

/// Shared in-memory state for the Sell Goat wizard.
///
/// One SaleDraft instance is created when the wizard opens and is passed
/// through all wizard steps. Nothing is written to Firestore until the
/// sale is saved (Step 5's branch-specific save action).
///
/// Fields are added to this draft task-by-task, following the Phase 4
/// build order: Steps 1-2 today, Steps 3-4 and the four delivery
/// branches (Section 3) land on top of this in later tasks.
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

  /// Selling weight per goat, keyed by goat ID. Selling weight can
  /// differ slightly from the goat's last recorded weight, so this
  /// starts out equal to `goat.weight` and becomes editable on Step 3.
  Map<String, double> sellingWeights = {};

  /// Optional gender per goat, keyed by goat ID, entered on Step 3.
  ///
  /// Trading's Goat model (lib/models/goat_model.dart) has no `gender`
  /// field — it's tracked for Own Farm and Palai goats but was never
  /// added when Trading's Goat Registration was built. Backfilling it
  /// there means touching Registration end-to-end and leaves every
  /// already-registered goat blank until re-edited, which is scope
  /// Phase 4 doesn't own. So gender here is captured just for this
  /// sale: it lives only in the draft, shown on the Step 3 goat card
  /// for the seller's own record, and is not written back to the goat
  /// doc.
  Map<String, String> genderOverrides = {};

  double sellingWeightFor(Goat goat) =>
      sellingWeights[goat.id] ?? goat.weight;

  double get totalSellingWeight => selectedGoats.fold(
    0.0,
        (sum, goat) => sum + sellingWeightFor(goat),
  );

  // ---------------------------------------------------------------------------
  // STEP 4 — SALE DETAILS  (Task 2.4)
  // ---------------------------------------------------------------------------

  /// Single price/KG applied across every selected goat — matches the
  /// plan's "Selling Price/KG × Selling Weight, summed across goats"
  /// rule rather than a per-goat price.
  double sellingPricePerKg = 0;

  /// Derived field, never manually overridden — same rule as Phase 1's
  /// Purchase Amount.
  double get totalSaleAmount => sellingPricePerKg * totalSellingWeight;
}