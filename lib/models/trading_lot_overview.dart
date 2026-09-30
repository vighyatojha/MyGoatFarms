import 'purchase_costing.dart';
import 'trading_purchase_model.dart';

/// A pure, derived snapshot of every Purchase Lot on a farm, computed
/// entirely from the purchase list — no separate Firestore reads, no
/// stored counters. [TradingService.lotOverviewStream] builds one of
/// these on every `tradingPurchases` update.
///
/// This exists because the dashboard's stored counters
/// (`tradingSummary/dashboard`) were never meant to carry lot stock —
/// they track individual goat records, and a lot has none until it is
/// transferred (see [TradingPurchase]'s doc comment). The dashboard reads
/// lot numbers from here instead; the stored counters stay in charge of
/// Booking / Wait on Delivery / Total Sold / Profit, which still apply to
/// lots too (see `TradingService.backfillDashboardSummary`).
class TradingLotOverview {
  /// Every lot (lotSchema >= 1) that still has goats anywhere
  /// (`isActive`), unsorted.
  final List<TradingPurchase> activeLots;

  /// Everything still owed to a supplier, newest first: lots with goats
  /// still at the supplier (`supplierQty > 0`, regardless of
  /// `receivingStatus` — a lot fully sold out at the supplier before
  /// anything arrived would otherwise show `receivingStatus: pending`
  /// forever) plus legacy (non-lot) purchases whose receiving is still
  /// pending.
  final List<TradingPurchase> pendingReceiving;

  /// Goats across every lot still physically at the supplier.
  final int supplierQty;

  /// Goats across every lot at the farm (registered or not, reserved or
  /// not) — the sum of each lot's `farmQty`.
  final int farmQty;

  /// Goats across every lot currently reserved by a Booking or
  /// Wait-for-Delivery sale (`reservedFarmQty`).
  final int reservedQty;

  /// Goats across every lot at the farm and not reserved — what can
  /// actually be sold, transferred, or is otherwise free right now.
  final int farmAvailableQty;

  /// Total still owed to suppliers across every lot.
  final double supplierDue;

  /// Purchases not yet converted to the lot format (`lotSchema == 0`).
  final int unconvertedPurchases;

  /// Goats from unconverted purchases still awaiting individual
  /// registration — the same count `pendingRegistrationStream` shows,
  /// kept here too so the dashboard can decide whether to show the
  /// "Older Purchases to Register" strip without a second listener.
  final int legacyPendingRegistrations;

  /// Goats sold out of lots so far (`soldFromSupplierQty +
  /// soldFromFarmQty`, completed sales only). The dashboard uses it to
  /// decide whether Total Sold should offer the Lot Sales list.
  final int lotSoldQty;

  /// Goats bought across every lot, ever (sum of each lot's `totalGoats`).
  final int totalPurchasedQty;

  /// Purchase amount across every lot (goats x weight x rate, before
  /// transport / other costs). This is what the suppliers are owed in all.
  final double totalPurchaseAmount;

  /// Paid to suppliers across every lot so far (sum of `paidAmount`).
  final double totalPaidToSuppliers;

  const TradingLotOverview({
    required this.activeLots,
    required this.pendingReceiving,
    required this.supplierQty,
    required this.farmQty,
    required this.reservedQty,
    required this.farmAvailableQty,
    required this.supplierDue,
    required this.unconvertedPurchases,
    required this.legacyPendingRegistrations,
    this.lotSoldQty = 0,
    this.totalPurchasedQty = 0,
    this.totalPurchaseAmount = 0,
    this.totalPaidToSuppliers = 0,
  });

  /// Empty overview — used before the first snapshot arrives.
  factory TradingLotOverview.empty() => const TradingLotOverview(
    activeLots: [],
    pendingReceiving: [],
    supplierQty: 0,
    farmQty: 0,
    reservedQty: 0,
    farmAvailableQty: 0,
    supplierDue: 0,
    unconvertedPurchases: 0,
    legacyPendingRegistrations: 0,
  );

  int get activeLotCount => activeLots.length;

  /// Goats still owned by lots: at the supplier plus at the farm.
  int get remainingQty => supplierQty + farmQty;

  bool get hasLegacyPurchasesToConvert => unconvertedPurchases > 0;

  factory TradingLotOverview.fromPurchases(List<TradingPurchase> purchases) {
    final lots = purchases.where((p) => p.isLot).toList();
    final legacy = purchases.where((p) => !p.isLot).toList();

    var supplierQty = 0;
    var farmQty = 0;
    var reservedQty = 0;
    var farmAvailableQty = 0;
    var supplierDue = 0.0;
    var lotSoldQty = 0;
    var totalPurchasedQty = 0;
    var totalPurchaseAmount = 0.0;
    var totalPaid = 0.0;

    for (final lot in lots) {
      totalPurchasedQty += lot.totalGoats;
      totalPurchaseAmount += lot.purchaseAmount;
      totalPaid += lot.paidAmount;
      lotSoldQty += lot.soldQty;
      supplierQty += lot.supplierQty;
      farmQty += lot.farmQty;
      reservedQty += lot.reservedFarmQty;
      farmAvailableQty += lot.farmAvailableQty;
      supplierDue += lot.dueAmount;
    }

    final activeLots = lots.where((l) => l.isActive).toList();

    final pendingReceiving = <TradingPurchase>[
      ...lots.where((l) => l.supplierQty > 0),
      ...legacy.where((p) => p.receivingStatus == 'pending'),
    ]..sort(
          (a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)),
    );

    final legacyPendingRegistrations = legacy
        .where((p) => p.isReceivingCompleted && p.pendingCount > 0)
        .fold<int>(0, (sum, p) => sum + p.pendingCount);

    return TradingLotOverview(
      activeLots: activeLots,
      pendingReceiving: pendingReceiving,
      supplierQty: supplierQty,
      farmQty: farmQty,
      reservedQty: reservedQty,
      farmAvailableQty: farmAvailableQty,
      supplierDue: PurchaseCosting.round2(supplierDue),
      unconvertedPurchases: legacy.length,
      legacyPendingRegistrations: legacyPendingRegistrations,
      lotSoldQty: lotSoldQty,
      totalPurchasedQty: totalPurchasedQty,
      totalPurchaseAmount: PurchaseCosting.round2(totalPurchaseAmount),
      totalPaidToSuppliers: PurchaseCosting.round2(totalPaid),
    );
  }
}