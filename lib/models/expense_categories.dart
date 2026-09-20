/// Single reusable source of expense categories.
///
/// Do not hard-code this list anywhere else — every expense screen
/// (add/edit form, filters, category chips) reads from here so adding a
/// category later means changing exactly one file.
class ExpenseCategories {
  ExpenseCategories._();

  // -----------------------------------------------------------------------
  // EXPENSE CATEGORIES
  // -----------------------------------------------------------------------

  static const String feed = 'Feed';
  static const String medicine = 'Medicine';
  static const String healthcare = 'Healthcare';

  /// Expenses created automatically when goats are purchased through
  /// the Trading module.
  static const String goatPurchase = 'Goat Purchase';

  static const String farmExpenses = 'Farm Expenses';
  static const String officeExpenses = 'Office Expenses';
  static const String hoofCuttingSelf = 'Hoof Cutting (Self)';
  static const String other = 'Other';

  static const List<String> all = [
    feed,
    medicine,
    healthcare,
    goatPurchase,
    farmExpenses,
    officeExpenses,
    hoofCuttingSelf,
    other,
  ];
}


/// Revenue categories for manual (non-billing) income.
///
/// Customer-payment revenue is never entered through these categories —
/// it comes automatically from the existing billing/payment flow. These
/// are only for money the farm receives outside that flow.
class RevenueCategories {
  RevenueCategories._();

  static const String goatSale = 'Goat Sale';
  static const String transportIncome = 'Transport Income';
  static const String otherFarmIncome = 'Other Farm Income';
  static const String miscellaneous = 'Miscellaneous Income';

  /// Revenue created automatically from Trading sales, recorded as the
  /// customer's money is received (one entry per receipt, each with its
  /// own payment method) and linked to the sale by saleId. Covers the
  /// goat sale amount (plus holding charges on Booking sales). Any
  /// transportation charge billed to the customer is paid on to the
  /// transport team and is NOT included — see
  /// SalesService._recordSaleReceiptRevenue.
  ///
  /// Kept separate from [goatSale] (which is for manually-entered
  /// revenue outside the Trading flow) so Finance can tell "the app
  /// created this automatically from a sale" apart from "someone typed
  /// this in by hand."
  static const String soldGoatRevenue = 'Sold Goat Revenue';

  static const List<String> all = [
    goatSale,
    soldGoatRevenue,
    transportIncome,
    otherFarmIncome,
    miscellaneous,
  ];
}


/// Payment methods used by the existing Finance module.
///
/// NOTE:
/// The Trading Purchase flow does NOT use this complete list.
///
/// Trading Purchase intentionally has its own restricted selection:
///
///     Cash
///     Online
///
/// The existing Finance module is left unchanged so existing expenses,
/// stock purchases, billing and other finance functionality continue to
/// work as before.
class FinancePaymentMethods {
  FinancePaymentMethods._();

  static const String cash = 'Cash';
  static const String upi = 'UPI';
  static const String bankTransfer = 'Bank Transfer';
  static const String cheque = 'Cheque';
  static const String other = 'Other';

  /// Not a real cash payment — used only when stock is purchased on
  /// credit from a supplier.
  ///
  /// Deliberately excluded from [all].
  static const String credit = 'Credit';

  static const List<String> all = [
    cash,
    upi,
    bankTransfer,
    cheque,
    other,
  ];

  /// Returns true when the payment was made using cash.
  static bool isCash(String method) {
    return method.trim().toLowerCase() == 'cash';
  }

  /// Existing Finance helper.
  ///
  /// This remains compatible with the current Finance screens:
  /// every non-empty method other than Cash is treated as online.
  static bool isOnline(String method) {
    return method.trim().isNotEmpty && !isCash(method);
  }
}