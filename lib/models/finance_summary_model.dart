/// Result of aggregating `transactions` + `expenses` for a date range,
/// plus the two *current-balance* figures (outstanding / advance) which
/// are never period totals — see spec §22.
class FinanceSummary {
  final double revenue;
  final double expenses;
  final double totalOutstanding;
  final double totalAdvance;

  /// category -> total, for the breakdown chart on Overview/Reports.
  final Map<String, double> revenueByCategory;
  final Map<String, double> expenseByCategory;

  const FinanceSummary({
    required this.revenue,
    required this.expenses,
    required this.totalOutstanding,
    required this.totalAdvance,
    this.revenueByCategory = const {},
    this.expenseByCategory = const {},
  });

  double get netCashFlow => revenue - expenses;

  static const empty = FinanceSummary(
    revenue: 0,
    expenses: 0,
    totalOutstanding: 0,
    totalAdvance: 0,
  );
}

/// One row in the Finance Overview / Reports "Recent Transactions" list —
/// a normalized view over a `transactions` doc (income) or an `expenses`
/// doc (expense). Not a separate Firestore collection.
class FinanceTransactionRow {
  final String id;
  final bool isIncome;
  final String category;
  final String title;
  final double amount;
  final DateTime date;
  final String? customerName;
  final String paymentMethod;
  final String? note;

  /// 'transactions' or 'expenses' — which collection [id] belongs to,
  /// so the detail screen knows where to look it up / void it.
  final String sourceCollection;

  const FinanceTransactionRow({
    required this.id,
    required this.isIncome,
    required this.category,
    required this.title,
    required this.amount,
    required this.date,
    required this.sourceCollection,
    this.customerName,
    this.paymentMethod = '',
    this.note,
  });
}
