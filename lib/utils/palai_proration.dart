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
    return calculateForStay(
      monthlyCharge: monthlyCharge,
      joiningDate: joiningDate,
      leavingDate: null,
      year: year,
      month: month,
    );
  }

  /// Pro-rates [monthlyCharge] for the billing month [year]/[month],
  /// accounting for BOTH ends of the goat's stay:
  ///
  /// * [joiningDate] — same rule as [calculate]: null or on/before the
  ///   1st of the month means the goat was already there at month start.
  /// * [leavingDate] — the date the goat checked out (or `null` if the
  ///   goat is still checked in, in which case billing runs to month
  ///   end exactly like [calculate]). The leaving day itself IS billed
  ///   (the goat was still on the farm that day), mirroring how the
  ///   joining day is billed.
  ///
  /// This is what [calculate] was missing: without a [leavingDate], a
  /// goat checked out mid-month was always charged for the WHOLE
  /// remainder of the month it never actually stayed for, which is what
  /// let Final Checkout's default Palai charge silently double the
  /// amount already sitting in that month's Monthly Bill.
  static PalaiProration calculateForStay({
    required double monthlyCharge,
    required DateTime? joiningDate,
    required DateTime? leavingDate,
    required int year,
    required int month,
  }) {
    final total = daysInMonth(year, month);
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month, total);

    // Compare on date only, ignoring time of day.
    var effectiveStart = monthStart;
    if (joiningDate != null) {
      final joined =
      DateTime(joiningDate.year, joiningDate.month, joiningDate.day);
      if (joined.isAfter(monthStart)) {
        effectiveStart = joined;
      }
    }

    var effectiveEnd = monthEnd;
    if (leavingDate != null) {
      final left =
      DateTime(leavingDate.year, leavingDate.month, leavingDate.day);
      if (left.isBefore(monthEnd)) {
        effectiveEnd = left;
      }
    }

    int billable;
    if (effectiveStart.isAfter(monthEnd) ||
        effectiveEnd.isBefore(monthStart) ||
        effectiveEnd.isBefore(effectiveStart)) {
      // Joined after the month ended, or left before the month began —
      // the goat wasn't here at all during this billing month.
      billable = 0;
    } else {
      billable = effectiveEnd.difference(effectiveStart).inDays + 1;
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
// ===========================================================================
// DATE-RANGE CHARGES (statement billing)
// ===========================================================================

/// Strips the time of day so billing always works on whole calendar days.
DateTime palaiDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Whole days from [from] to [to], both inclusive. Counted on UTC dates so
/// a daylight-saving change can never turn a 24-hour day into 23 hours and
/// drop a day from the count.
int palaiDaysInclusive(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays + 1;
}

/// One calendar month's slice of a [PalaiRangeCharge].
class PalaiRangeSegment {
  const PalaiRangeSegment({
    required this.year,
    required this.month,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.daysInMonth,
    required this.amount,
  });

  final int year;
  final int month;
  final DateTime fromDate;
  final DateTime toDate;
  final int days;
  final int daysInMonth;
  final double amount;
}

/// Palai charge for a stay that can cross month boundaries, e.g. the
/// unbilled days charged at checkout or at a goat's death.
///
/// Each month is pro-rated on its own day count (₹3,000 in a 30-day month
/// is ₹100/day, in a 31-day month ₹96.77/day), so a range charge always
/// equals the sum of what the monthly bills would have charged.
class PalaiRangeCharge {
  const PalaiRangeCharge({
    required this.monthlyCharge,
    required this.segments,
  });

  const PalaiRangeCharge.none(this.monthlyCharge) : segments = const [];

  final double monthlyCharge;
  final List<PalaiRangeSegment> segments;

  int get totalDays => segments.fold(0, (sum, s) => sum + s.days);

  double get amount => PalaiProrationCalculator._round2(
    segments.fold<double>(0, (sum, s) => sum + s.amount),
  );

  bool get isEmpty => segments.isEmpty;

  DateTime? get fromDate => segments.isEmpty ? null : segments.first.fromDate;

  DateTime? get toDate => segments.isEmpty ? null : segments.last.toDate;
}

class PalaiRangeCalculator {
  const PalaiRangeCalculator._();

  /// Charges [monthlyCharge] for every day from [from] to [to], both
  /// inclusive. Returns an empty charge when [to] is before [from].
  static PalaiRangeCharge chargeForRange({
    required double monthlyCharge,
    required DateTime from,
    required DateTime to,
  }) {
    final start = palaiDateOnly(from);
    final end = palaiDateOnly(to);

    if (end.isBefore(start) || monthlyCharge <= 0) {
      return PalaiRangeCharge.none(monthlyCharge < 0 ? 0.0 : monthlyCharge);
    }

    final segments = <PalaiRangeSegment>[];
    var cursor = start;

    while (!cursor.isAfter(end)) {
      final dim = PalaiProrationCalculator.daysInMonth(
        cursor.year,
        cursor.month,
      );
      final monthEnd = DateTime(cursor.year, cursor.month, dim);
      final segmentEnd = monthEnd.isBefore(end) ? monthEnd : end;
      final days = palaiDaysInclusive(cursor, segmentEnd);

      segments.add(
        PalaiRangeSegment(
          year: cursor.year,
          month: cursor.month,
          fromDate: cursor,
          toDate: segmentEnd,
          days: days,
          daysInMonth: dim,
          amount: PalaiProrationCalculator._round2(
            monthlyCharge / dim * days,
          ),
        ),
      );

      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return PalaiRangeCharge(
      monthlyCharge: monthlyCharge,
      segments: segments,
    );
  }
}