/// Shared in-memory state for the Purchase Goats wizard.
///
/// One PurchaseDraft instance is created when the wizard opens and is
/// passed through all wizard steps.
///
/// Nothing is written to Firestore until the purchase is saved.
class PurchaseDraft {
  // ---------------------------------------------------------------------------
  // STEP 1 — SELLER DETAILS
  // ---------------------------------------------------------------------------

  String sellerName = '';
  String mobile = '';
  String market = '';
  String vehicleNumber = '';
  DateTime purchaseDate = DateTime.now();

  // ---------------------------------------------------------------------------
  // STEP 2 — PURCHASE DETAILS
  // ---------------------------------------------------------------------------

  /// Breed has intentionally been removed from the Trading purchase flow.
  int totalGoats = 0;
  double totalWeightAtPurchase = 0;
  double pricePerKg = 0;

  /// Trading purchase payment methods are intentionally limited to:
  /// Cash / Online.
  String paymentMethod = 'Cash';

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
  // STEP 3 — RECEIVING & TRANSPORT
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
  // DERIVED VALUES
  // ---------------------------------------------------------------------------

  /// Purchase Amount = Total Weight × Price per KG.
  ///
  /// This is always calculated live and is never manually entered.
  double get purchaseAmount =>
      totalWeightAtPurchase * pricePerKg;

  /// Weight Loss = Weight at Purchase − Weight After Arrival.
  double get weightLoss {
    final loss =
        totalWeightAtPurchase - totalWeightAfterArrival;

    return loss < 0 ? 0 : loss;
  }

  /// Total transportation/additional expenses.
  double get totalTransportExpenses =>
      transportCost +
          loadingCharges +
          unloadingCharges +
          otherExpenses;

  /// Total expenses currently attached to the purchase.
  double get totalExpenses =>
      totalTransportExpenses;

  /// Grand Total = Purchase Amount + Additional Expenses.
  double get grandTotal =>
      purchaseAmount + totalExpenses;

  /// Effective Cost per KG after arrival.
  ///
  /// Guarded against division by zero.
  double get effectiveCostPerKg =>
      totalWeightAfterArrival > 0
          ? grandTotal / totalWeightAfterArrival
          : 0;

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  /// Whether receiving information has been completed.
  bool get isReceivingCompleted =>
      receivingStatus == 'completed';

  /// Whether the purchase is waiting for receiving information.
  bool get isReceivingPending =>
      receivingStatus == 'pending';

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