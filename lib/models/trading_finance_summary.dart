/// Finance figures for the Trading side of the Finance tab, for one date
/// range. Built by FinanceService.getTradingFinanceSummary().
///
/// Everything here is CASH-BASED, exactly like the Palai side: money is
/// counted when it is received / paid.
///
///   salesRevenue      Sold Goat Revenue received (one entry per receipt).
///   purchaseSpend     Goat Purchase expenses (the purchase amount paid
///                     to sellers).
///   otherPurchaseCosts Transport / loading / unloading / other costs of
///                     the purchases in the range. These live on the
///                     `tradingPurchases` docs, not in `expenses`, so they
///                     are added on top of [purchaseSpend] — never double
///                     counted.
///   receivable        Goat-sale balances customers still owe. This is a
///                     CURRENT balance, never a period total.
class TradingFinanceSummary {
  final double salesRevenue;
  final double purchaseSpend;
  final double otherPurchaseCosts;

  final double receivable;
  final int receivableCount;

  final double cashReceived;
  final double onlineReceived;
  final double cashPaid;
  final double onlinePaid;

  /// Distinct sales that received money in the range.
  final int salesCount;

  /// Purchases made in the range, and the goats in them.
  final int purchaseCount;
  final int goatsPurchased;

  final Map<String, double> revenueByCategory;
  final Map<String, double> expenseByCategory;

  const TradingFinanceSummary({
    this.salesRevenue = 0,
    this.purchaseSpend = 0,
    this.otherPurchaseCosts = 0,
    this.receivable = 0,
    this.receivableCount = 0,
    this.cashReceived = 0,
    this.onlineReceived = 0,
    this.cashPaid = 0,
    this.onlinePaid = 0,
    this.salesCount = 0,
    this.purchaseCount = 0,
    this.goatsPurchased = 0,
    this.revenueByCategory = const {},
    this.expenseByCategory = const {},
  });

  static const TradingFinanceSummary empty = TradingFinanceSummary();

  /// Everything spent on buying and bringing goats in.
  double get totalCost => purchaseSpend + otherPurchaseCosts;

  /// Cash in minus cash out for the Trading business.
  double get netCashFlow => salesRevenue - totalCost;

  bool get isEmpty =>
      salesRevenue == 0 &&
          totalCost == 0 &&
          receivable == 0 &&
          purchaseCount == 0;
}