import '../models/goat_model.dart';
import '../models/sale_model.dart';

/// One customer's open Booking / Holding sales, grouped for the
/// customer-wise Booking / Holding list — the Branch B (Booking) analog
/// of whatever groups Wait for Delivery's open sales by customer for
/// WaitDeliveryCustomerListScreen.
///
/// Sale.goatIds is a list (one Sale can cover more than one goat), so
/// every goat count here is summed from goatIds.length rather than
/// assumed to be one-per-sale.
class BookingCustomer {
  final String key;
  final String customerName;
  final String customerMobile;
  final List<Sale> sales;

  /// Earliest holdingStart among this customer's open bookings — how
  /// long they've been waiting. Shown as "Since <date>".
  final DateTime since;

  final double totalAdvance;

  /// Sale.goatIds -> Goat, resolved once here (from the same goatsStream
  /// the Goat Stock list already subscribes to) so a booking card can
  /// show the tag/breed/age line (Image 1) without every card doing its
  /// own lookup. A goat missing from this map — already sold or deleted
  /// elsewhere — just means that card falls back to showing the raw ID.
  final Map<String, Goat> goatsById;

  const BookingCustomer({
    required this.key,
    required this.customerName,
    required this.customerMobile,
    required this.sales,
    required this.since,
    required this.totalAdvance,
    required this.goatsById,
  });

  int get bookingCount => sales.length;

  int get goatCount =>
      sales.fold<int>(0, (sum, s) => sum + s.goatIds.length);

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    if (customerName.toLowerCase().contains(q)) return true;
    if (customerMobile.contains(q)) return true;

    for (final sale in sales) {
      if (sale.id.toLowerCase().contains(q)) return true;

      for (final goatId in sale.goatIds) {
        if (goatId.toLowerCase().contains(q)) return true;

        final goat = goatsById[goatId];
        if (goat != null && goat.breed.toLowerCase().contains(q)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Groups [sales] by customer mobile (falling back to name when mobile
  /// is blank — two customers can share a name), resolving goat details
  /// from [goats] along the way.
  static List<BookingCustomer> group({
    required List<Sale> sales,
    required List<Goat> goats,
  }) {
    final goatsById = {for (final g in goats) g.id: g};

    final Map<String, List<Sale>> byKey = {};

    for (final sale in sales) {
      final mobile = sale.mobile.trim();
      final name = sale.customerName.trim();
      final key = mobile.isNotEmpty ? mobile : name;

      byKey.putIfAbsent(key, () => []).add(sale);
    }

    final groups = byKey.entries.map((entry) {
      final customerSales = entry.value;
      final first = customerSales.first;

      final since = customerSales
          .map((s) => s.holdingStart)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      final totalAdvance = Sale.roundMoney(
        customerSales.fold<double>(
          0,
              (sum, s) => sum + (s.bookingAmount ?? 0),
        ),
      );

      return BookingCustomer(
        key: entry.key,
        customerName: first.customerName.trim().isEmpty
            ? 'Unknown Customer'
            : first.customerName.trim(),
        customerMobile: first.mobile.trim(),
        sales: customerSales,
        since: since,
        totalAdvance: totalAdvance,
        goatsById: goatsById,
      );
    }).toList()
      ..sort((a, b) => a.since.compareTo(b.since));

    return groups;
  }
}