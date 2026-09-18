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
}