import 'expense_categories.dart';

/// The two "sides" of the Finance tab.
///
///  * [palai]   — Palai customers (bills, monthly bills, customer
///                payments, receivables / advances) plus the farm's own
///                running costs (feed, medicine, office, ...).
///  * [trading] — the goat Trading business: goat purchases, goat sales,
///                sale credit and the transport costs of a purchase.
enum FinanceScope { palai, trading }

extension FinanceScopeX on FinanceScope {
  String get label => this == FinanceScope.palai ? 'Palai' : 'Trading';

  String get longLabel =>
      this == FinanceScope.palai ? 'Palai Customers' : 'Goat Trading';
}

/// The ONE place that decides whether a finance record is a Trading
/// record or a Palai record.
///
/// Nothing else in the app should re-implement this check. If the
/// classification ever needs to change (for example, treat "Transport
/// Income" as Trading), change it here and every screen follows.
///
/// Trading records are the ones the Trading module writes itself:
///
///   revenue  -> `transactions` docs with referenceType = tradingSale,
///               or category Sold Goat Revenue / Goat Sale
///   expenses -> `expenses` docs with referenceType = tradingPurchase,
///               or category Goat Purchase
///
/// Everything else (customer payments, monthly bills, feed, medicine,
/// office expenses, manual income, ...) belongs to the Palai side.
class FinanceScopeRules {
  FinanceScopeRules._();

  static const String tradingPurchaseRef = 'tradingPurchase';
  static const String tradingSaleRef = 'tradingSale';

  static bool isTradingRevenue({
    required String referenceType,
    required String category,
  }) {
    if (referenceType == tradingSaleRef) return true;

    return category == RevenueCategories.soldGoatRevenue ||
        category == RevenueCategories.goatSale;
  }

  static bool isTradingExpense({
    required String referenceType,
    required String category,
  }) {
    if (referenceType == tradingPurchaseRef) return true;

    return category == ExpenseCategories.goatPurchase;
  }

  /// [data] is a raw `transactions` document map.
  static bool revenueMapBelongsTo(
      FinanceScope scope,
      Map<String, dynamic> data,
      ) {
    final trading = isTradingRevenue(
      referenceType: (data['referenceType'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
    );

    return scope == FinanceScope.trading ? trading : !trading;
  }

  /// [data] is a raw `expenses` document map.
  static bool expenseMapBelongsTo(
      FinanceScope scope,
      Map<String, dynamic> data,
      ) {
    return expenseBelongsTo(
      scope,
      referenceType: (data['referenceType'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
    );
  }

  static bool expenseBelongsTo(
      FinanceScope scope, {
        required String? referenceType,
        required String category,
      }) {
    final trading = isTradingExpense(
      referenceType: (referenceType ?? '').toString(),
      category: category,
    );

    return scope == FinanceScope.trading ? trading : !trading;
  }
}