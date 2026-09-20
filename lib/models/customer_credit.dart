import 'sale_model.dart';

/// A customer who still owes money on goat sales — their outstanding
/// balance from selling on credit (or from any sale that was not paid in
/// full).
///
/// This is a read-time view, never a stored document. The amount owed is
/// always worked out from the sales themselves ([Sale.billBalanceDue]), the
/// same figure the sale receipt and Finance's Receivables total use, so it
/// can never drift away from what has actually been paid. Collecting a
/// payment on a sale ([SalesService.receiveBalancePayment]) is all it takes
/// for the balance shown here to come down.
///
/// One customer can appear under more than one customer record (a person
/// who was a goat buyer first and became a Palai customer later has a
/// record in each collection). Sales are therefore grouped by mobile
/// number, falling back to the customer id, so the same person is one row.
class CustomerCredit {
  /// Grouping key — see [keyFor] / [keyFromParts].
  final String key;

  final String name;
  final String mobile;
  final String address;

  /// Every customer record id this person's sales are filed under.
  final Set<String> customerIds;

  /// The customer's unpaid sales, oldest first.
  final List<Sale> sales;

  /// Sum of [Sale.billBalanceDue] over [sales].
  final double totalDue;

  const CustomerCredit({
    required this.key,
    required this.name,
    required this.mobile,
    required this.address,
    required this.customerIds,
    required this.sales,
    required this.totalDue,
  });

  int get saleCount => sales.length;

  /// True if any of the unpaid sales was sold on credit on purpose.
  bool get hasCreditSale => sales.any((sale) => sale.onCredit);

  /// The date of the oldest unpaid sale, if it is known.
  DateTime? get oldestSaleDate {
    DateTime? oldest;

    for (final sale in sales) {
      final date = sale.createdAt;

      if (date == null) continue;

      if (oldest == null || date.isBefore(oldest)) {
        oldest = date;
      }
    }

    return oldest;
  }

  // ---------------------------------------------------------------------
  // GROUPING
  // ---------------------------------------------------------------------

  /// The grouping key for a customer described by these parts: the last
  /// 10 digits of the mobile number when there is one (so "98765 43210"
  /// and "+91 9876543210" are the same person), otherwise the customer id,
  /// otherwise the name.
  static String keyFromParts({
    String mobile = '',
    String customerId = '',
    String name = '',
  }) {
    var digits = mobile.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }

    if (digits.isNotEmpty) return 'm:$digits';

    final id = customerId.trim();

    if (id.isNotEmpty) return 'id:$id';

    return 'n:${name.trim().toLowerCase()}';
  }

  static String keyFor(Sale sale) {
    return keyFromParts(
      mobile: sale.mobile,
      customerId: sale.customerId,
      name: sale.customerName,
    );
  }

  /// Groups [sales] into one [CustomerCredit] per customer.
  ///
  /// Only sales that still have a collectable balance are counted
  /// ([Sale.canCollectBalance]): delivered, and something still owed. The
  /// result is sorted with the biggest balance first.
  static List<CustomerCredit> group(Iterable<Sale> sales) {
    final byKey = <String, List<Sale>>{};

    for (final sale in sales) {
      if (!sale.canCollectBalance) continue;

      byKey.putIfAbsent(keyFor(sale), () => []).add(sale);
    }

    final result = <CustomerCredit>[];

    for (final entry in byKey.entries) {
      final list = entry.value
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

          return aDate.compareTo(bDate);
        });

      // The most recent sale has the customer's current details.
      final latest = list.last;

      var total = 0.0;

      for (final sale in list) {
        total += sale.billBalanceDue;
      }

      result.add(
        CustomerCredit(
          key: entry.key,
          name: latest.customerName,
          mobile: latest.mobile,
          address: latest.address,
          customerIds: list
              .map((sale) => sale.customerId)
              .where((id) => id.trim().isNotEmpty)
              .toSet(),
          sales: list,
          totalDue: Sale.roundMoney(total),
        ),
      );
    }

    result.sort((a, b) => b.totalDue.compareTo(a.totalDue));

    return result;
  }

  /// The total still owed across every customer in [credits].
  static double totalOf(Iterable<CustomerCredit> credits) {
    var total = 0.0;

    for (final credit in credits) {
      total += credit.totalDue;
    }

    return Sale.roundMoney(total);
  }
}