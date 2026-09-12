import 'dart:typed_data';

import 'bill_settings_model.dart';
import 'goat_history_models.dart';
import 'palai_models.dart';

/// One month's activity counts for a single goat — the compressed
/// per-month row shown in a goat's "Monthly History" table on the Final
/// Checkout Report. Same shape as [MonthlyReportGoat] from the recurring
/// Monthly Report, but scoped to ONE goat across ONE month, and produced
/// by looping [MonthlyReportService] across every month of that goat's
/// Palai period rather than across every goat for one month.
class GoatMonthlyHistoryRow {
  final DateTime monthStart;
  final String monthLabel; // e.g. "Jan 2026"

  final int weightRecords;
  final int health;
  final int vaccination;
  final int medicine;
  final int hoof;
  final int hair;
  final int photos;

  const GoatMonthlyHistoryRow({
    required this.monthStart,
    required this.monthLabel,
    required this.weightRecords,
    required this.health,
    required this.vaccination,
    required this.medicine,
    required this.hoof,
    required this.hair,
    required this.photos,
  });
}

/// Everything needed to render ONE goat's page in the Final Checkout
/// Report — goat information, its full monthly history compressed into
/// one table (instead of a page per month), a representative photo per
/// month, and the lifetime summary shown at the bottom of the page.
///
/// One [GoatFinalReportEntry] = one page in the PDF (see
/// FinalCheckoutReportPdfService — "ONE GOAT = ONE PAGE").
class GoatFinalReportEntry {
  final PalaiGoat goat;

  final DateTime checkInDate;
  final DateTime checkOutDate;

  final double initialWeight;
  final double finalWeight;

  final Uint8List? beforeImage;
  final Uint8List? afterImage;

  final List<GoatMonthlyHistoryRow> monthlyHistory;

  /// Every actual weight record for this goat across its whole Palai
  /// period, oldest first — the raw data behind the weight chart AND
  /// the weight-related counts in [monthlyHistory]. Both must read
  /// from this single list, never two independently-derived datasets.
  final List<GoatWeightHistoryPoint> weightHistory;

  /// One representative photo per month, keyed by the same
  /// [GoatMonthlyHistoryRow.monthLabel] used in the history table, so
  /// the PDF can show a compact "Month → representative photo" grid
  /// instead of dumping every photo taken that month.
  final Map<String, Uint8List> representativePhotoByMonth;

  final String healthStatus;
  final String deliveryStatus;

  double get weightChange => finalWeight - initialWeight;

  int get totalMonths => monthlyHistory.length;

  int get totalHealthRecords =>
      monthlyHistory.fold(0, (sum, m) => sum + m.health);

  int get totalVaccinations =>
      monthlyHistory.fold(0, (sum, m) => sum + m.vaccination);

  int get totalMedicines =>
      monthlyHistory.fold(0, (sum, m) => sum + m.medicine);

  int get totalHoofCutting =>
      monthlyHistory.fold(0, (sum, m) => sum + m.hoof);

  int get totalHairTrimming =>
      monthlyHistory.fold(0, (sum, m) => sum + m.hair);

  int get totalPhotos =>
      monthlyHistory.fold(0, (sum, m) => sum + m.photos);

  const GoatFinalReportEntry({
    required this.goat,
    required this.checkInDate,
    required this.checkOutDate,
    required this.initialWeight,
    required this.finalWeight,
    required this.monthlyHistory,
    required this.representativePhotoByMonth,
    required this.healthStatus,
    required this.deliveryStatus,
    this.weightHistory = const [],
    this.beforeImage,
    this.afterImage,
  });
}

/// One row in the Final Settlement's Payment History table.
class FinalPaymentHistoryRow {
  final DateTime date;
  final String paymentNumber;
  final String method;
  final double amount;
  final String status; // e.g. "Paid"

  const FinalPaymentHistoryRow({
    required this.date,
    required this.paymentNumber,
    required this.method,
    required this.amount,
    required this.status,
  });
}

/// Customer-level financial settlement shown on the Final Checkout
/// Report's closing page.
///
/// IMPORTANT: this does not recompute the customer's live balance —
/// [finalOutstanding]/[finalAdvance] are read straight from the
/// [MonthlyBillResult] produced by [FirestoreService.createMonthlyBill]
/// (which is itself the atomic write against `pendingAmount`/
/// `advanceAmount`). Everything else here (totalMonthlyCharges,
/// totalTransport, totalDiscount, paymentHistory, ...) is a read-only
/// historical breakdown built from the customer's existing bills/
/// payments — never a second source of truth for the balance itself.
class FinalSettlementData {
  final String customerName;
  final int goatCount;

  final DateTime? periodStart;
  final DateTime periodEnd;

  // Historical breakdown across the WHOLE Palai period (for display).
  final double totalMonthlyCharges;
  final double totalTransport;
  final double totalOtherCharges;
  final double totalDiscount;
  final double grossCharges;

  // Snapshot from the bill that was just created for this checkout.
  final double previousOutstanding;
  final double advanceBefore;
  final double advanceApplied;
  final double finalAmountDue; // MonthlyBillResult.totalDue
  final double finalAmountPaid; // MonthlyBillResult.paid (this checkout only)
  final double finalOutstanding; // MonthlyBillResult.pendingAfter
  final double finalAdvance; // MonthlyBillResult.advanceAfter

  /// Every payment ever received from this customer (oldest first) —
  /// informational history only, never re-summed into the balance.
  final List<FinalPaymentHistoryRow> paymentHistory;

  bool get isFullySettled => finalOutstanding <= 0;

  double get totalPaidHistorical =>
      paymentHistory.fold(0.0, (sum, p) => sum + p.amount);

  const FinalSettlementData({
    required this.customerName,
    required this.goatCount,
    required this.periodEnd,
    required this.totalMonthlyCharges,
    required this.totalTransport,
    required this.totalOtherCharges,
    required this.totalDiscount,
    required this.grossCharges,
    required this.previousOutstanding,
    required this.advanceBefore,
    required this.advanceApplied,
    required this.finalAmountDue,
    required this.finalAmountPaid,
    required this.finalOutstanding,
    required this.finalAdvance,
    required this.paymentHistory,
    this.periodStart,
  });
}

// ============================================================================
// ON-SCREEN REVIEW DATA — final_checkout_report_screen.dart builds one
// of these to drive its own preview widgets before Generate PDF is
// pressed. Moved here (out of pdf_bill_service.dart, where they used
// to live) because nothing in pdf_bill_service.dart has referenced
// them since buildFinalCheckoutReport() was removed — the review
// screen is their only remaining consumer, and it already imports
// this file in full.
// ============================================================================

class FinalCheckoutReportData {
  final String reportId;
  final String customerName;
  final String customerMobile;
  final String customerAddress;
  final String packageName;

  final DateTime checkInDate;
  final DateTime checkOutDate;
  final String deliveryStatus;
  final String finalHealthStatus;

  final List<FinalGoatReportData> goats;
  final List<MonthlyGoatReportData> months;

  final double checkInTransport;
  final double checkOutTransport;
  final double previousBalance;
  final double discount;
  final double totalBill;
  final double paidAmount;
  final double pendingAmount;

  final double advanceBefore;
  final double advanceApplied;
  final double advanceAfter;
  final String paymentMethod;

  final Uint8List? beforeImage;
  final Uint8List? afterImage;
  final Uint8List? signatureBytes;

  final List<String> importantNotes;
  final BillSettings billSettings;

  /// Every payment received from this customer across the whole Palai
  /// period, oldest first — sourced from
  /// [FinanceService.getCustomerPaymentHistory]. Display-only; the
  /// balance figures above (paidAmount/pendingAmount/advanceAfter)
  /// are never recomputed from it.
  final List<FinalPaymentHistoryRow> paymentHistory;

  const FinalCheckoutReportData({
    required this.reportId,
    required this.customerName,
    this.customerMobile = '',
    this.customerAddress = '',
    this.packageName = '',
    required this.checkInDate,
    required this.checkOutDate,
    this.deliveryStatus = '',
    this.finalHealthStatus = '',
    this.goats = const [],
    this.months = const [],
    this.checkInTransport = 0,
    this.checkOutTransport = 0,
    this.previousBalance = 0,
    this.discount = 0,
    this.totalBill = 0,
    this.paidAmount = 0,
    this.pendingAmount = 0,
    this.advanceBefore = 0,
    this.advanceApplied = 0,
    this.advanceAfter = 0,
    this.paymentMethod = '',
    this.beforeImage,
    this.afterImage,
    this.signatureBytes,
    this.importantNotes = const [],
    required this.billSettings,
    this.paymentHistory = const [],
  });

  double get totalFinalWeight =>
      goats.fold(0, (sum, goat) => sum + goat.finalWeight);

  double get totalWeightGain =>
      goats.fold(0, (sum, goat) => sum + goat.weightGain);
}

class FinalGoatReportData {
  final String goatCode;
  final String breed;
  final String gender;
  final String color;
  final double checkInWeight;
  final double finalWeight;
  final String healthStatus;
  final String deliveryStatus;
  final double charges;

  /// Every actual weight record for this goat across its whole Palai
  /// period, oldest first — feeds the weight-progress chart, and the
  /// per-month weight counts in [GoatFinalReportEntry.monthlyHistory].
  final List<GoatWeightHistoryPoint> weightHistory;

  /// Every health event for this goat, oldest first — vaccination,
  /// deworming, hoof cutting, hair trimming, medicine, and general
  /// health-update checkups, aggregated from their existing
  /// collections (see MonthlyReportService.getGoatHealthHistory).
  /// Vaccination entries here never carry a charge.
  final List<GoatHealthHistoryEntry> healthHistory;

  const FinalGoatReportData({
    required this.goatCode,
    required this.breed,
    this.gender = '',
    this.color = '',
    required this.checkInWeight,
    required this.finalWeight,
    this.healthStatus = '',
    this.deliveryStatus = '',
    this.charges = 0,
    this.weightHistory = const [],
    this.healthHistory = const [],
  });

  double get weightGain => finalWeight - checkInWeight;
}

class MonthlyGoatReportData {
  final String monthLabel;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime reportDate;

  final String goatCode;
  final String breed;
  final String gender;
  final String color;
  final DateTime checkInDate;

  final double previousWeight;
  final double currentWeight;
  final double monthlyCharge;

  final String packageName;
  final String healthStatus;
  final String vaccination;
  final String deworming;
  final String hoofCutting;
  final String hairTrimming;
  final String medicineGiven;
  final String healthNotes;

  final Uint8List? previousImage;
  final Uint8List? currentImage;
  final List<Uint8List> additionalImages;

  final String notes;

  const MonthlyGoatReportData({
    required this.monthLabel,
    required this.periodStart,
    required this.periodEnd,
    required this.reportDate,
    required this.goatCode,
    required this.breed,
    this.gender = '',
    this.color = '',
    required this.checkInDate,
    this.previousWeight = 0,
    this.currentWeight = 0,
    this.monthlyCharge = 0,
    this.packageName = '',
    this.healthStatus = 'Not recorded',
    this.vaccination = '',
    this.deworming = '',
    this.hoofCutting = '',
    this.hairTrimming = '',
    this.medicineGiven = '',
    this.healthNotes = '',
    this.previousImage,
    this.currentImage,
    this.additionalImages = const [],
    this.notes = '',
  });

  double get weightGain => currentWeight - previousWeight;
}