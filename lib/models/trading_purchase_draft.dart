import 'purchase_costing.dart';

/// Shared in-memory state for the Purchase Lot wizard.
///
/// One PurchaseDraft instance is created when the wizard opens and is
/// passed through all wizard steps.
///
/// Nothing is written to Firestore until the purchase is saved.
///
/// All money / weight figures are derived through [PurchaseCosting], so the
/// live numbers on screen, the summary and the saved record always agree.
class PurchaseDraft {
  // ---------------------------------------------------------------------------
  // STEP 1 — SELLER DETAILS
  // ---------------------------------------------------------------------------

  String sellerName = '';
  String mobile = '';

  /// Remarks about the purchase itself (PDF §3). Kept apart from
  /// [remarks], which is the note about the goats' ARRIVAL, so a lot saved
  /// as "receive later" does not lose what was typed here.
  String supplierRemarks = '';
  String market = '';
  String vehicleNumber = '';
  DateTime purchaseDate = DateTime.now();

  /// When the supplier is expected to deliver the lot. Optional.
  DateTime? expectedDeliveryDate;

  // ---------------------------------------------------------------------------
  // STEP 2 — LOT DETAILS
  // ---------------------------------------------------------------------------

  /// Breed has intentionally been removed from the Trading purchase flow.
  int totalGoats = 0;
  double totalWeightAtPurchase = 0;
  double pricePerKg = 0;

  /// Gender split of [totalGoats], captured here — at Purchase Details —
  /// rather than per-goat on the Register Goat screen, since a wholesale
  /// lot is bought and counted as a batch, not goat by goat.
  ///
  /// Both start at 0 and are expected to add up to [totalGoats] once the
  /// user has filled them in; see [genderCountIsValid].
  int maleGoats = 0;
  int femaleGoats = 0;

  // ---------------------------------------------------------------------------
  // STEP 3 — PAYMENT (supplier)
  // ---------------------------------------------------------------------------

  /// Trading purchase payment methods are intentionally limited to:
  /// Cash / Online. This is the method of the payment made NOW; later
  /// payments choose their own method from Lot Detail.
  String paymentMethod = 'Cash';

  /// Paid to the supplier right now. 0 is allowed (nothing paid yet).
  double paidNow = 0;

  /// False until the person has actually typed an amount on the Payment
  /// step, so "0" is always a deliberate choice and never a forgotten
  /// field. The wizard will not move on until this is true.
  bool paidNowEntered = false;

  String paymentNote = '';

  /// Amount still owed to the supplier after [paidNow].
  double get dueAfterPayment {
    final due = PurchaseCosting.round2(purchaseAmount - paidNow);
    return due < 0 ? 0 : due;
  }

  /// Unpaid / Partial / Paid — derived from [paidNow], never typed in.
  /// Same rule as TradingPurchase.paymentStatus.
  String get paymentStatus {
    if (paidNow <= 0) return 'Unpaid';
    if (dueAfterPayment < 0.01) return 'Paid';
    return 'Partial';
  }

  /// True when the amount typed can legally be saved.
  bool get paymentIsValid =>
      paidNowEntered &&
          paidNow >= 0 &&
          paidNow <= purchaseAmount + 0.005;

  // ---------------------------------------------------------------------------
  // RECEIVING FLOW
  // ---------------------------------------------------------------------------

  /// True when the user chooses "Fill Receiving Details Now".
  ///
  /// False means the purchase can be saved with receiving pending.
  bool receivingNow = false;

  /// Current receiving status.
  ///
  /// Values used by the Trading module:
  /// - pending
  /// - completed
  String receivingStatus = 'pending';

  // ---------------------------------------------------------------------------
  // STEP 4 — RECEIVING & TRANSPORT (optional)
  // ---------------------------------------------------------------------------

  DateTime dateReceivedAtFarm = DateTime.now();

  double totalWeightAfterArrival = 0;

  int mortality = 0;

  String remarks = '';

  double transportCost = 0;

  double loadingCharges = 0;

  double unloadingCharges = 0;

  double otherExpenses = 0;

  // ---------------------------------------------------------------------------
  // COSTING
  // ---------------------------------------------------------------------------

  /// Live costing from whatever is currently typed — used while the user is
  /// still on Step 3, before receiving has been marked completed.
  PurchaseCosting get costing => PurchaseCosting(
    totalGoats: totalGoats,
    weightAtPurchase: totalWeightAtPurchase,
    pricePerKg: pricePerKg,
    weightAfterArrival: totalWeightAfterArrival,
    mortality: mortality,
    transportCost: transportCost,
    loadingCharges: loadingCharges,
    unloadingCharges: unloadingCharges,
    otherExpenses: otherExpenses,
  );

  /// Costing exactly as it will be SAVED.
  ///
  /// When receiving is being done later, anything typed on Step 3 earlier
  /// (then abandoned by going Back) is ignored, so the summary can never show
  /// expenses that will not actually be stored.
  PurchaseCosting get finalCosting =>
      isReceivingCompleted ? costing : costing.withoutReceiving();

  // ---------------------------------------------------------------------------
  // DERIVED VALUES (kept for existing callers)
  // ---------------------------------------------------------------------------

  /// Purchase Amount = Total Weight x Price per KG. Never entered by hand.
  double get purchaseAmount => costing.purchaseAmount;

  /// Weight Loss = Weight at Purchase - Weight After Arrival.
  ///
  /// 0 until an arrival weight has been entered (it used to show the whole
  /// purchase weight as "lost" before anything was typed).
  double get weightLoss => costing.weightLoss;

  /// Total transportation / additional expenses.
  double get totalTransportExpenses => costing.totalExpenses;

  /// Total expenses currently attached to the purchase.
  double get totalExpenses => costing.totalExpenses;

  /// Grand Total = Purchase Amount + Additional Expenses.
  double get grandTotal => costing.grandTotal;

  /// Grand Total / Weight After Arrival. 0 until arrival weight is entered.
  double get effectiveCostPerKg => costing.effectiveCostPerKg;

  /// Goats that actually arrived alive.
  int get survivingGoats => costing.survivingGoats;

  /// Grand Total / surviving goats.
  double get costPerSurvivingGoat => costing.costPerSurvivingGoat;

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  /// Whether receiving information has been completed.
  bool get isReceivingCompleted => receivingStatus == 'completed';

  /// Whether the purchase is waiting for receiving information.
  bool get isReceivingPending => receivingStatus == 'pending';

  /// True once the person has typed anything. Lets the wizard skip the
  /// "Leave purchase?" warning when there is nothing to lose.
  bool get hasAnyData =>
      sellerName.trim().isNotEmpty ||
          mobile.trim().isNotEmpty ||
          market.trim().isNotEmpty ||
          vehicleNumber.trim().isNotEmpty ||
          supplierRemarks.trim().isNotEmpty ||
          totalGoats > 0 ||
          totalWeightAtPurchase > 0 ||
          pricePerKg > 0 ||
          maleGoats > 0 ||
          femaleGoats > 0 ||
          paidNow > 0 ||
          expectedDeliveryDate != null ||
          totalWeightAfterArrival > 0 ||
          mortality > 0 ||
          transportCost > 0 ||
          loadingCharges > 0 ||
          unloadingCharges > 0 ||
          otherExpenses > 0 ||
          remarks.trim().isNotEmpty;

  /// True when a Male / Female split has been entered at all. The split is
  /// optional (PDF §4): leaving both blank is fine and the lot is saved
  /// without one.
  bool get hasGenderSplit => maleGoats > 0 || femaleGoats > 0;

  /// True when the split is acceptable: either none was entered (optional),
  /// or Male + Female add up to the Total Goats entered.
  ///
  /// True (not an error) while totalGoats is still 0, so the check only
  /// starts to matter once there is something to check it against.
  bool get genderCountIsValid =>
      !hasGenderSplit ||
          totalGoats <= 0 ||
          (maleGoats + femaleGoats) == totalGoats;

  /// Normalizes the payment method so only Cash or Online can be stored.
  void setPaymentMethod(String value) {
    final normalized = value.trim().toLowerCase();

    if (normalized == 'online') {
      paymentMethod = 'Online';
    } else {
      paymentMethod = 'Cash';
    }
  }

  /// Marks the receiving portion of the purchase as completed.
  void markReceivingCompleted() {
    receivingNow = true;
    receivingStatus = 'completed';
  }

  /// Marks the purchase as waiting for receiving details.
  void markReceivingPending() {
    receivingNow = false;
    receivingStatus = 'pending';
  }
}