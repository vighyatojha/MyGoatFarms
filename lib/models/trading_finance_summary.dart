/// Finance figures for the Trading side of the Finance tab, for one date
/// range. Built by FinanceService.getTradingFinanceSummary().
///
/// Everything here is CASH-BASED, exactly like the Palai side: money is
/// counted when it is received / paid.
///
///   salesRevenue      Sold Goat Revenue received (one entry per receipt).
///   purchaseSpend     Cash / online actually paid to sellers: Goat
///                     Purchase expenses (older purchases, paid in full
///                     when saved) plus one Supplier Payment expense per
///                     payment made on a Purchase Lot. Credit rows (a
///                     lot's audit-only purchase entry) are not cash and
///                     are left out.
///   otherPurchaseCosts Transport / loading / unloading / other costs of
///                     the purchases in the range. These live on the
///                     `tradingPurchases` docs, not in `expenses`, so they
///                     are added on top of [purchaseSpend] — never double
///                     counted.
///   receivable        Goat-sale balances customers still owe. This is a
///                     CURRENT balance, never a period total.
///
/// LOT ACCOUNTING (accrual) — a second, separate view for Purchase Lots
/// only. It counts a purchase or a sale when it HAPPENS, not when cash
/// moves, so it can be compared with Lot Detail:
///
///   lotPurchaseValue   Purchase amount of lots bought in the range.
///   lotSupplierPending Still owed to suppliers across all lots, now
///                      (a current balance, never a period total).
///   lotSalesValue      Goat value of lot sales delivered in the range.
///   lotCostOfSales     Cost of those goats: each sale's cost-per-goat
///                      snapshot x goats sold.
///   lotProfit          lotSalesValue - lotCostOfSales.
///
/// The cash figures above are unchanged and still drive Net Cash Flow.
class TradingFinanceSummary {
  final double salesRevenue;
  final double purchaseSpend;
  final double otherPurchaseCosts;

  /// Purchase amount of the purchases made in the range (what the goats
  /// were bought for, paid or not). Only used for [avgCostPerGoat], so the
  /// goats and the money in that figure come from the same purchases.
  final double purchasedValue;

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

  // Lot accounting (accrual) — see class comment.
  final double lotPurchaseValue;
  final double lotSupplierPending;
  final double lotSalesValue;
  final double lotCostOfSales;
  final int lotGoatsSold;

  const TradingFinanceSummary({
    this.salesRevenue = 0,
    this.purchaseSpend = 0,
    this.otherPurchaseCosts = 0,
    this.purchasedValue = 0,
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
    this.lotPurchaseValue = 0,
    this.lotSupplierPending = 0,
    this.lotSalesValue = 0,
    this.lotCostOfSales = 0,
    this.lotGoatsSold = 0,
  });

  static const TradingFinanceSummary empty = TradingFinanceSummary();

  /// Everything spent on buying and bringing goats in.
  double get totalCost => purchaseSpend + otherPurchaseCosts;

  /// Average cost of one goat bought in the range: what those purchases
  /// cost (purchase amount + their transport / other costs) over the goats
  /// in them. Deliberately NOT based on cash paid in the range — a lot paid
  /// for in a later month would otherwise show cost with no goats.
  double get avgCostPerGoat => goatsPurchased > 0
      ? ((purchasedValue + otherPurchaseCosts) / goatsPurchased * 100)
      .roundToDouble() /
      100
      : 0;

  /// Cash in minus cash out for the Trading business.
  double get netCashFlow => salesRevenue - totalCost;

  /// Accrual profit on lot sales in the range.
  double get lotProfit =>
      ((lotSalesValue - lotCostOfSales) * 100).roundToDouble() / 100;

  /// True when there is anything to show in the Lot Accounting block.
  bool get hasLotAccounting =>
      lotPurchaseValue != 0 ||
          lotSupplierPending != 0 ||
          lotSalesValue != 0 ||
          lotCostOfSales != 0;

  bool get isEmpty =>
      salesRevenue == 0 &&
          totalCost == 0 &&
          receivable == 0 &&
          purchaseCount == 0;
}