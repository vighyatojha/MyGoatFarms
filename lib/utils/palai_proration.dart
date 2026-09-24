/// Pro-rating of the monthly Palai charge for goats that join mid-month.
///
/// Rule:
///   dailyRate      = monthlyCharge ÷ number of days in that calendar month
///   billableDays   = days from the joining date (inclusive) to month end
///   proratedCharge = dailyRate × billableDays
///
/// Example (30-day month, ₹3,000/month, goat joins on day 11):
///   ₹3,000 ÷ 30 × 20 = ₹2,000
library;

/// The result of pro-rating one goat's Palai charge for one month.
class PalaiProration {
  const PalaiProration({
    required this.monthlyCharge,
    required this.daysInMonth,
    required this.billableDays,
    required this.amount,
  });

  /// Full monthly Palai charge for the goat.
  final double monthlyCharge;

  /// Number of days in the billing month (28–31).
  final int daysInMonth;

  /// Days the goat is actually charged for in that month.
  final int billableDays;

  /// Final charge, rounded to 2 decimals.
  final double amount;

  /// True when the goat is charged for fewer days than the whole month.
  bool get isPartialMonth => billableDays < daysInMonth;

  /// e.g. "20 of 30 days"
  String get label => '$billableDays of $daysInMonth days';
}

class PalaiProrationCalculator {
  const PalaiProrationCalculator._();

  /// Number of days in the given [month] (1–12) of [year].
  /// Day 0 of the next month is the last day of this month, so this
  /// handles 28/29/30/31-day months and leap years automatically.
  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Pro-rates [monthlyCharge] for the billing month [year]/[month].
  ///
  /// * [joiningDate] on or before the 1st of the month → full month.
  /// * [joiningDate] inside the month → charged from that day to the end
  ///   of the month, the joining day counted as a charged day.
  /// * [joiningDate] after the month → 0 days, ₹0 (goat not yet there).
  /// * [joiningDate] null → full month (nothing to prorate against).
  static PalaiProration calculate({
    required double monthlyCharge,
    required DateTime? joiningDate,
    required int year,
    required int month,
  }) {
    final total = daysInMonth(year, month);

    int billable;
    if (joiningDate == null) {
      billable = total;
    } else {
      final monthStart = DateTime(year, month, 1);
      final monthEnd = DateTime(year, month, total);
      // Compare on date only, ignoring time of day.
      final joined =
      DateTime(joiningDate.year, joiningDate.month, joiningDate.day);

      if (!joined.isAfter(monthStart)) {
        billable = total;
      } else if (joined.isAfter(monthEnd)) {
        billable = 0;
      } else {
        billable = total - joined.day + 1;
      }
    }

    final raw = monthlyCharge / total * billable;
    return PalaiProration(
      monthlyCharge: monthlyCharge,
      daysInMonth: total,
      billableDays: billable,
      amount: _round2(raw),
    );
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}