import 'sale_model.dart';
import 'trading_purchase_model.dart';

/// Sales figures for ONE Purchase Lot, worked out from that lot's sales.
///
/// Pure Dart (no Firestore / Flutter) so the arithmetic can be unit tested.
///
/// What counts:
/// * A sale is **recognised** once the goats have left the lot
///   ([Sale.isDelivered]): Deliver Now, completed Booking delivery,
///   completed Wait-for-Delivery pickup, or a Transfer to Customer Palai.
/// * Booked / Wait-for-Delivery sales that are still open are **not**
///   revenue or profit yet. Their goats are counted as [openGoats].
///
/// Revenue is the goat value only ([Sale.billGoatSale]); holding and
/// transport charges are the customer's bill, not goat revenue.
///
/// Cost uses the sale's own `costPerGoatSnapshot` (falling back to the
/// lot's current cost per goat for a sale that has none), so profit already
/// recognised never moves when the lot is edited later.
///
/// Known limitation (handover §5): the snapshot spreads cost over all
/// purchased goats, so transit mortality that happens AFTER a sale is not
/// reflected in that sale's profit.
class LotSalesSummary {
  /// Recognised sales, newest first.
  final List<Sale> completedSales;

  /// Booked / Wait-for-Delivery sales not yet delivered, newest first.
  final List<Sale> openSales;

  final int goatsSold;
  final double salesWeight;
  final double revenue;
  final double cost;
  final double customerPending;

  /// Goats promised to customers but not yet delivered.
  final int openGoats;

  const LotSalesSummary({
    required this.completedSales,
    required this.openSales,
    required this.goatsSold,
    required this.salesWeight,
    required this.revenue,
    required this.cost,
    required this.customerPending,
    required this.openGoats,
  });

  double get profit => _round2(revenue - cost);

  bool get hasSales => completedSales.isNotEmpty || openSales.isNotEmpty;

  /// Average price per kg actually realised (revenue / weight).
  double get averagePricePerKg =>
      salesWeight > 0 ? _round2(revenue / salesWeight) : 0;

  factory LotSalesSummary.from(TradingPurchase lot, List<Sale> sales) {
    final completed = <Sale>[];
    final open = <Sale>[];

    for (final sale in sales) {
      if (!sale.isLotSale) continue;
      (sale.isDelivered ? completed : open).add(sale);
    }

    int goats = 0;
    double weight = 0;
    double revenue = 0;
    double cost = 0;
    double pending = 0;

    for (final sale in completed) {
      goats += sale.lotQuantity;
      weight += saleWeight(sale);
      revenue += sale.billGoatSale;
      cost += (sale.costPerGoatSnapshot ?? lot.lotCostPerGoat) *
          sale.lotQuantity;
      pending += sale.billBalanceDue;
    }

    return LotSalesSummary(
      completedSales: completed,
      openSales: open,
      goatsSold: goats,
      salesWeight: _round2(weight),
      revenue: _round2(revenue),
      cost: _round2(cost),
      customerPending: _round2(pending),
      openGoats: open.fold<int>(0, (sum, s) => sum + s.lotQuantity),
    );
  }

  /// Weight the goats were actually sold at: the pickup weight after a
  /// Wait-for-Delivery pickup, otherwise the selling weight.
  static double saleWeight(Sale sale) =>
      sale.hasPickupSettlement ? sale.pickupWeight! : sale.sellingWeight;

  /// Price per kg for one sale. A fixed-price sale has no meaningful rate,
  /// so this is the effective rate (goat value / weight).
  static double effectivePricePerKg(Sale sale) {
    final weight = saleWeight(sale);
    if (weight <= 0) return sale.sellingPricePerKg;
    return _round2(sale.billGoatSale / weight);
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}

/// Sales totals across EVERY lot — the dashboard's Sales Revenue and
/// Customer Pending. Same recognition rule as [LotSalesSummary]: only sales
/// whose goats have left ([Sale.isDelivered]) count; open Booking /
/// Wait-for-Delivery sales are reported separately as [openGoats].
class LotSalesTotals {
  final int goatsSold;
  final double revenue;
  final double customerPending;
  final int openGoats;

  const LotSalesTotals({
    this.goatsSold = 0,
    this.revenue = 0,
    this.customerPending = 0,
    this.openGoats = 0,
  });

  factory LotSalesTotals.from(List<Sale> sales) {
    int goats = 0;
    int open = 0;
    double revenue = 0;
    double pending = 0;

    for (final sale in sales) {
      if (!sale.isLotSale) continue;

      if (sale.isDelivered) {
        goats += sale.lotQuantity;
        revenue += sale.billGoatSale;
        pending += sale.billBalanceDue;
      } else {
        open += sale.lotQuantity;
      }
    }

    double r2(double v) => (v * 100).roundToDouble() / 100;

    return LotSalesTotals(
      goatsSold: goats,
      revenue: r2(revenue),
      customerPending: r2(pending),
      openGoats: open,
    );
  }
}