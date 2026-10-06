import 'purchase_costing.dart';
import 'trading_lot_payment_model.dart';
import 'trading_purchase_model.dart';

/// One goat supplier, worked out live from the purchase lots. Nothing is
/// stored for it. Every figure is the lot's own figure, so this ledger,
/// Lot Management, the lot screens and the Trading dashboard's "Supplier
/// Payments Due" always show the same numbers:
///
///   Bought  = sum of purchaseAmount   (cancelled deals not counted)
///   Paid    = sum of paidAmount       (cancelled deals not counted)
///   Due     = sum of dueAmount        (= dashboard Supplier Payments Due)
///
/// Only purchase lots are included, the same as the dashboard and the
/// Supplier Pending Payments screen.
class GoatSupplierAccount {
  /// "m:<last 10 digits>" when there is a mobile number, else "n:<name>".
  final String key;
  final String name;
  final String mobile;
  final String market;

  /// Every lot from this supplier, newest first (cancelled ones included).
  final List<TradingPurchase> lots;

  const GoatSupplierAccount({
    required this.key,
    required this.name,
    required this.mobile,
    required this.market,
    required this.lots,
  });

  List<TradingPurchase> get activeLots =>
      lots.where((l) => !l.dealCancelled).toList();
  List<TradingPurchase> get cancelledLots =>
      lots.where((l) => l.dealCancelled).toList();

  /// Lots with money still owed, oldest first (pay these first).
  List<TradingPurchase> get unpaidLots {
    final list = lots.where((l) => l.dueAmount >= 0.01).toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    return list;
  }

  double get totalBought => PurchaseCosting.round2(
      activeLots.fold(0.0, (s, l) => s + l.purchaseAmount));
  double get totalPaid =>
      PurchaseCosting.round2(activeLots.fold(0.0, (s, l) => s + l.paidAmount));
  double get totalDue =>
      PurchaseCosting.round2(lots.fold(0.0, (s, l) => s + l.dueAmount));

  int get goatsBought => activeLots.fold(0, (s, l) => s + l.totalGoats);
  int get lotCount => activeLots.length;

  DateTime? get lastPurchase => lots.isEmpty ? null : lots.first.purchaseDate;
  DateTime? get firstPurchase => lots.isEmpty ? null : lots.last.purchaseDate;

  bool get owes => totalDue >= 0.01;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (market.toLowerCase().contains(q)) return true;
    if (lots.any((l) => l.lotId.toLowerCase().contains(q))) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty &&
        mobile.replaceAll(RegExp(r'\D'), '').contains(digits);
  }

  // -------------------------------------------------------------------------

  static String digitsOf(String mobile) {
    var digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    return digits;
  }

  static String keyOf(TradingPurchase lot) {
    final d = digitsOf(lot.mobile);
    if (d.isNotEmpty) return 'm:$d';
    final name = lot.sellerName.trim().toLowerCase();
    return name.isEmpty ? 'n:unnamed' : 'n:$name';
  }

  /// Every supplier from [purchases]: those still owed first (biggest
  /// due first), then the rest by latest purchase.
  static List<GoatSupplierAccount> group(List<TradingPurchase> purchases) {
    final byKey = <String, List<TradingPurchase>>{};
    for (final p in purchases) {
      if (!p.isLot) continue;
      byKey.putIfAbsent(keyOf(p), () => []).add(p);
    }

    String pick(Iterable<String> values) => values
        .map((v) => v.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    final result = byKey.entries.map((e) {
      final lots = [...e.value]
        ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      final name = pick(lots.map((l) => l.sellerName));
      return GoatSupplierAccount(
        key: e.key,
        name: name.isEmpty ? 'Unnamed supplier' : name,
        mobile: pick(lots.map((l) => l.mobile)),
        market: pick(lots.map((l) => l.market)),
        lots: lots,
      );
    }).toList();

    result.sort((a, b) {
      final byDue = b.totalDue.compareTo(a.totalDue);
      if (byDue != 0) return byDue;
      final ad = a.lastPurchase ?? DateTime(1970);
      final bd = b.lastPurchase ?? DateTime(1970);
      return bd.compareTo(ad);
    });
    return result;
  }

  /// Sum of every supplier's due: equals the dashboard's figure.
  static double totalDueOf(List<GoatSupplierAccount> suppliers) =>
      PurchaseCosting.round2(suppliers.fold(0.0, (s, a) => s + a.totalDue));
}

/// One payment to a supplier, with the lot it was paid against.
class SupplierPaymentLine {
  final TradingPurchase lot;
  final LotPayment payment;

  const SupplierPaymentLine({required this.lot, required this.payment});

  String get label {
    if (payment.voided) return 'Payment voided';
    if (payment.isLegacy) return 'Paid at purchase';
    return 'Payment to supplier';
  }
}