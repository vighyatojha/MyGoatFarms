import 'package:cloud_firestore/cloud_firestore.dart';

/// Trading Dashboard summary.
///
/// Stored at:
/// farms/{farmId}/tradingSummary/dashboard
///
/// All numeric values are parsed defensively because Firestore data can
/// contain int, double, or legacy/string values depending on older records.
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

  static const TradingSummary empty = TradingSummary();

  factory TradingSummary.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();

    if (data == null || data.isEmpty) {
      return TradingSummary.empty;
    }

    int intFrom(String key) {
      final value = data[key];

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      if (value is String) {
        return int.tryParse(value.trim()) ?? 0;
      }

      return 0;
    }

    double doubleFrom(String key) {
      final value = data[key];

      if (value is double) {
        return value;
      }

      if (value is num) {
        return value.toDouble();
      }

      if (value is String) {
        return double.tryParse(value.trim()) ?? 0.0;
      }

      return 0.0;
    }

    return TradingSummary(
      totalStock: intFrom('totalStock'),
      wholesalePurchased: intFrom('wholesalePurchased'),
      totalSold: intFrom('totalSold'),
      totalProfit: doubleFrom('totalProfit'),
      pendingRegistrations: intFrom('pendingRegistrations'),
      booking: intFrom('booking'),
      waitOnDelivery: intFrom('waitOnDelivery'),
    );
  }
}