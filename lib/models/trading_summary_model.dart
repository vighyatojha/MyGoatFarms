import 'package:cloud_firestore/cloud_firestore.dart';

/// The Trading Dashboard's 7 summary numbers, persisted at
/// `farms/{farmId}/tradingSummary/dashboard` and kept up to date by a
/// Cloud Function trigger on `tradingPurchases` writes (see Task 1.3 —
/// functions/index.js) rather than recomputed client-side on every
/// dashboard load.
///
/// Phase 1 only ever writes [wholesalePurchased] and
/// [pendingRegistrations] — the rest stay at 0 (never faked) until
/// later phases (Registration, Stock, Own Palai, Sale) populate them.
class TradingSummary {
  final int totalStock;
  final int wholesalePurchased;
  final int totalSold;
  final double totalProfit;
  final int pendingRegistrations;
  final int booking;
  final int waitOnDelivery;

  const TradingSummary({
    this.totalStock = 0,
    this.wholesalePurchased = 0,
    this.totalSold = 0,
    this.totalProfit = 0,
    this.pendingRegistrations = 0,
    this.booking = 0,
    this.waitOnDelivery = 0,
  });

  static const empty = TradingSummary();

  factory TradingSummary.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    if (data == null) return TradingSummary.empty;

    int intFrom(String key) => (data[key] as num?)?.toInt() ?? 0;
    double numFrom(String key) => (data[key] as num?)?.toDouble() ?? 0;

    return TradingSummary(
      totalStock: intFrom('totalStock'),
      wholesalePurchased: intFrom('wholesalePurchased'),
      totalSold: intFrom('totalSold'),
      totalProfit: numFrom('totalProfit'),
      pendingRegistrations: intFrom('pendingRegistrations'),
      booking: intFrom('booking'),
      waitOnDelivery: intFrom('waitOnDelivery'),
    );
  }
}