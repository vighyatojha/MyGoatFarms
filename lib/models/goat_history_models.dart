/// One weight measurement for a goat, at a point in time — the raw
/// data point behind the Final Checkout Report's weight-progress
/// chart. Sourced from the goat's `palaiWeightRecords` subcollection
/// (see PalaiFoundationService.addWeightRecord /
/// MonthlyReportService.getGoatWeightHistory).
class GoatWeightHistoryPoint {
  final DateTime date;
  final double weight;

  const GoatWeightHistoryPoint({
    required this.date,
    required this.weight,
  });
}

/// One chronological health event for a goat — vaccination, deworming,
/// hoof cutting, hair trimming, medicine, or a general health-update
/// checkup. Sourced by aggregating the goat's existing
/// `vaccinationRecords` / `hoofCuttingRecords` / `hairTrimmingRecords` /
/// `medicineRecords` / `healthRecords` subcollections (see
/// MonthlyReportService.getGoatHealthHistory) — deliberately not a new
/// collection; every event type keeps living where it already does,
/// this is just a read-only, date-sorted view across all of them.
///
/// Vaccination entries never carry a charge/price — per the Palai
/// spec, vaccination is health information only and is never billed.
class GoatHealthHistoryEntry {
  final DateTime date;

  /// e.g. "Vaccination", "Deworming", "Hoof Cutting", "Hair Trimming",
  /// "Medicine", "Health Update".
  final String type;

  /// Short status/action, e.g. "Completed", "1st vaccination",
  /// "Medicine given: XYZ".
  final String detail;

  /// Optional free-text note attached to the underlying record.
  final String notes;

  const GoatHealthHistoryEntry({
    required this.date,
    required this.type,
    required this.detail,
    this.notes = '',
  });
}