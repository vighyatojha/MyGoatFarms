/// Single reusable source of expense categories.
///
/// Do not hard-code this list anywhere else — every expense screen
/// (add/edit form, filters, category chips) reads from here so adding a
/// category later means changing exactly one file.
class ExpenseCategories {
  ExpenseCategories._();

  static const String feed = 'Feed';
  static const String medicine = 'Medicine';
  static const String healthcare = 'Healthcare';
  static const String farmExpenses = 'Farm Expenses';
  static const String officeExpenses = 'Office Expenses';
  static const String hoofCuttingSelf = 'Hoof Cutting (Self)';
  static const String other = 'Other';

  static const List<String> all = [
    feed,
    medicine,
    healthcare,
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

  static const List<String> all = [
    goatSale,
    transportIncome,
    otherFarmIncome,
    miscellaneous,
  ];
}

/// Payment methods — mirrors the exact set already used throughout the
/// billing/payment screens. Do not introduce a second payment-method list.
class FinancePaymentMethods {
  FinancePaymentMethods._();

  static const String cash = 'Cash';
  static const String upi = 'UPI';
  static const String bankTransfer = 'Bank Transfer';
  static const String cheque = 'Cheque';
  static const String other = 'Other';

  /// Not a real cash payment — used only when stock is purchased on
  /// credit from a supplier (see AddFeedStockScreen / AddMedicineScreen's
  /// "Buy on Credit" toggle). Deliberately excluded from [all] so it
  /// never appears in payment pickers for money actually received/paid
  /// in cash (Receive Payment, manual expenses, etc.).
  static const String credit = 'Credit';

  static const List<String> all = [cash, upi, bankTransfer, cheque, other];

  /// Buckets any payment method into the simple Cash / Online split used
  /// by the Finance Overview's payment-mode tracker. Every method other
  /// than exact "Cash" (UPI, Bank Transfer, Cheque, Other, ...) is
  /// treated as an online payment.
  static bool isCash(String method) => method.trim().toLowerCase() == 'cash';

  static bool isOnline(String method) =>
      method.trim().isNotEmpty && !isCash(method);
}