import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/final_checkout_report_model.dart';
import '../models/palai_models.dart';

/// Builds the combined "Final Checkout Report" PDF:
///
///   Page 1..N  -> one page per goat (goat info, arrival/current
///                 photos, a weight-progress chart built from real
///                 per-date records, full Monthly History compressed
///                 into one table, a representative photo per month,
///                 and that goat's lifetime summary).
///   Next page  -> Final Settlement: charges breakdown and final
///                 balance/status. No payment-history table — kept
///                 deliberately out of this report; charges/balance
///                 only, so the page doesn't read like a ledger.
///   Last page  -> Terms & Conditions, Important Notes, and a closing
///                 thank-you banner, all sourced from BillSettings.
///
/// The header/footer/logo/section-banner structure below is
/// deliberately the SAME structure already used by
/// [CustomerGoatsProgressReportPdfService] (full farm header + info
/// bar on page 1, a slim minor header on every page after, one
/// pw.MultiPage flow so nothing can ever overlap, and the same footer)
/// — this is the "same PDF header and last page structure" the
/// Progress Report already established, reused here rather than a new
/// PDF architecture (per the Final Checkout spec, item 3/17).
class FinalCheckoutReportPdfService {
  FinalCheckoutReportPdfService._();

  static final FinalCheckoutReportPdfService instance =
  FinalCheckoutReportPdfService._();

  // ==========================================================================
  // PUBLIC API
  // ==========================================================================

  Future<Uint8List> generatePdf({
    required PalaiCustomer customer,
    required List<GoatFinalReportEntry> goatEntries,
    required FinalSettlementData settlement,
    required BillSettings billSettings,
    /// Optional override for the farm logo image bytes.
    ///
    /// When the caller has the farm's actual "profile photo" bytes
    /// (wherever that lives in the database — e.g. a farm profile
    /// document, distinct from [BillSettings.billLogo]), pass them
    /// here and they take priority. Falls back to
    /// [BillSettings.billLogo] when not supplied, so nothing changes
    /// for callers that don't pass it.
    Uint8List? farmLogoOverride,
  }) async {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    final logoImage = _safeMemoryImage(farmLogoOverride ?? billSettings.billLogo);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
        header: (context) => _buildPageHeader(
          context: context,
          customer: customer,
          totalGoatsInReport: goatEntries.length,
          billSettings: billSettings,
          logoImage: logoImage,
        ),
        footer: (context) => _buildFooter(
          billSettings: billSettings,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
        ),
        build: (context) => _buildDocumentContent(
          customer: customer,
          goatEntries: goatEntries,
          settlement: settlement,
          billSettings: billSettings,
        ),
      ),
    );

    return pdf.save();
  }

  Future<void> preview({
    required PalaiCustomer customer,
    required List<GoatFinalReportEntry> goatEntries,
    required FinalSettlementData settlement,
    required BillSettings billSettings,
    Uint8List? farmLogoOverride,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      goatEntries: goatEntries,
      settlement: settlement,
      billSettings: billSettings,
      farmLogoOverride: farmLogoOverride,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _safeFileName(customer));
  }

  Future<void> share({
    required PalaiCustomer customer,
    required List<GoatFinalReportEntry> goatEntries,
    required FinalSettlementData settlement,
    required BillSettings billSettings,
    Uint8List? farmLogoOverride,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      goatEntries: goatEntries,
      settlement: settlement,
      billSettings: billSettings,
      farmLogoOverride: farmLogoOverride,
    );
    await Printing.sharePdf(bytes: bytes, filename: _safeFileName(customer));
  }

  Future<String> save({
    required PalaiCustomer customer,
    required List<GoatFinalReportEntry> goatEntries,
    required FinalSettlementData settlement,
    required BillSettings billSettings,
    Uint8List? farmLogoOverride,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      goatEntries: goatEntries,
      settlement: settlement,
      billSettings: billSettings,
      farmLogoOverride: farmLogoOverride,
    );
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_safeFileName(customer)}');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Shares PDF bytes that were already generated — use this instead of
  /// [share] whenever the caller has already built the report once
  /// (e.g. right after Generate PDF) so the same, potentially
  /// photo-heavy report is never rebuilt from scratch a second time
  /// just to share it. Mirrors PdfBillService.shareReportBytes, which
  /// this replaces for the Final Checkout Report.
  Future<void> shareBytes(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Saves already-generated PDF bytes to device — the save-side
  /// counterpart of [shareBytes], for the same reason: avoid
  /// rebuilding a report that's already sitting in memory. Mirrors
  /// PdfBillService.saveReportBytesToDevice, which this replaces for
  /// the Final Checkout Report.
  Future<String> saveBytes(Uint8List bytes, String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ==========================================================================
  // IMAGE LOADING — same "never crash the whole PDF over one bad photo"
  // rule as the Progress Report service.
  // ==========================================================================

  pw.MemoryImage? _safeMemoryImage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // DOCUMENT CONTENT
  // ==========================================================================

  List<pw.Widget> _buildDocumentContent({
    required PalaiCustomer customer,
    required List<GoatFinalReportEntry> goatEntries,
    required FinalSettlementData settlement,
    required BillSettings billSettings,
  }) {
    final content = <pw.Widget>[];

    if (goatEntries.isEmpty) {
      content.add(
        pw.Container(
          width: double.infinity,
          height: 120,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'No goats in this final checkout.',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      );
    } else {
      // ONE GOAT = ONE PAGE.
      for (int i = 0; i < goatEntries.length; i++) {
        content.add(_buildGoatFinalReportPage(i + 1, goatEntries[i]));
        content.add(pw.NewPage());
      }
    }

    // FINAL SETTLEMENT — always its own page, after every goat page.
    content.add(_buildFinalSettlementPage(customer, settlement));

    // TERMS & CONDITIONS / IMPORTANT NOTES / CLOSING — always its own
    // page, last. Sourced entirely from BillSettings, same as the
    // Progress Report — never hard-coded terms text in this file.
    content.add(pw.NewPage());
    content.add(
      _buildSectionBanner(
        number: '\u00a7',
        title: 'Terms & Conditions',
        subtitle: 'Important notes • Customer acknowledgement • Farm policies',
      ),
    );
    content.add(pw.SizedBox(height: 10));
    content.add(_buildTermsGrid(billSettings));
    content.add(pw.SizedBox(height: 9));
    content.add(_buildImportantNotes(billSettings));
    content.add(pw.SizedBox(height: 14));
    content.add(_buildClosingBanner(billSettings));

    return content;
  }

  // ==========================================================================
  // ONE GOAT PAGE
  // ==========================================================================

  pw.Widget _buildGoatFinalReportPage(int number, GoatFinalReportEntry entry) {
    final goat = entry.goat;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionBanner(
          number: '$number',
          title: 'Goat Final Report — ${_goatLabel(goat)}',
          subtitle: 'Check-in ${_formatDate(entry.checkInDate)}  •  Check-out ${_formatDate(entry.checkOutDate)}',
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 4, child: _goatInfoBox(entry)),
            pw.SizedBox(width: 6),
            pw.Expanded(flex: 4, child: _goatPhotoPair(entry)),
          ],
        ),
        pw.SizedBox(height: 8),
        _sectionLabel('WEIGHT PROGRESS'),
        pw.SizedBox(height: 4),
        _buildWeightProgressChart(entry),
        pw.SizedBox(height: 8),
        if (entry.representativePhotoByMonth.isNotEmpty) ...[
          _sectionLabel('MONTHLY PHOTOS'),
          pw.SizedBox(height: 4),
          _buildMonthlyPhotoGrid(entry),
          pw.SizedBox(height: 8),
        ],
        _sectionLabel('GOAT SUMMARY'),
        pw.SizedBox(height: 4),
        _buildGoatSummaryBox(entry),
      ],
    );
  }

  String _goatLabel(PalaiGoat goat) {
    final code = goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber;
    final name = goat.name.trim();
    return name.isNotEmpty ? '$code ($name)' : code;
  }

  pw.Widget _goatInfoBox(GoatFinalReportEntry entry) {
    final goat = entry.goat;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle('GOAT INFORMATION'),
          pw.SizedBox(height: 4),
          _detailRow('Breed', goat.breed),
          _detailRow('Gender', goat.gender),
          _detailRow('Color', goat.color),
          _detailRow('Check-in Date', _formatDate(entry.checkInDate)),
          _detailRow('Check-out Date', _formatDate(entry.checkOutDate)),
          _detailRow('Initial Weight', '${entry.initialWeight.toStringAsFixed(1)} kg'),
          _detailRow('Final Weight', '${entry.finalWeight.toStringAsFixed(1)} kg'),
          _detailRow(
            'Weight Change',
            '${entry.weightChange >= 0 ? '+' : ''}${entry.weightChange.toStringAsFixed(1)} kg',
          ),
        ],
      ),
    );
  }

  pw.Widget _goatPhotoPair(GoatFinalReportEntry entry) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          'ARRIVAL / CURRENT',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            _photoTile(label: 'Check-in', bytes: entry.beforeImage),
            pw.SizedBox(width: 6),
            _photoTile(label: 'Check-out', bytes: entry.afterImage),
          ],
        ),
      ],
    );
  }

  pw.Widget _photoTile({required String label, required Uint8List? bytes}) {
    const size = 90.0;
    final image = _safeMemoryImage(bytes);
    return pw.Column(
      children: [
        pw.Container(
          width: size,
          height: size,
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.green200),
            color: PdfColors.grey100,
          ),
          child: image != null
              ? pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Image(image, fit: pw.BoxFit.cover, width: size, height: size),
          )
              : pw.Center(
            child: pw.Text('No photo', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500)),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(label, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
      ],
    );
  }

  // ==========================================================================
  // WEIGHT PROGRESS CHART — connected line + dot markers, built strictly
  // from entry.weightHistory (real per-date records, never just
  // initialWeight/finalWeight). Given deliberate visual priority: this
  // is the tallest single element on the goat page, taller than the
  // info box, the photo pair, or any row in the monthly table.
  // ==========================================================================

  pw.Widget _buildWeightProgressChart(GoatFinalReportEntry entry) {
    final points = entry.weightHistory;
    final summary = pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
      children: [
        _weightStat('Arrival Weight', '${entry.initialWeight.toStringAsFixed(1)} kg'),
        _weightStat('Current Weight', '${entry.finalWeight.toStringAsFixed(1)} kg'),
        _weightStat(
          'Total Gain',
          '${entry.weightChange >= 0 ? '+' : ''}${entry.weightChange.toStringAsFixed(1)} kg',
          emphasize: true,
        ),
      ],
    );

    // Fewer than 2 real records: nothing meaningful to plot a line
    // through — show only the Arrival/Current/Gain summary rather
    // than fabricating a chart from two invented endpoints.
    if (points.length < 2) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.green50,
          border: pw.Border.all(color: PdfColors.green200),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: summary,
      );
    }

    // Extra headroom above/below the plotted line itself, so the
    // per-point weight labels (above each dot) and date labels
    // (below each dot) never collide with the line — mirrors the
    // "value above dot / month below dot" trend-chart reference.
    const chartHeight = 130.0;
    const chartWidth = 460.0;
    const topPadding = 24.0;
    const bottomPadding = 16.0;
    const plotHeight = chartHeight - topPadding - bottomPadding;

    final weights = points.map((p) => p.weight).toList();
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final range = (maxWeight - minWeight) <= 0 ? 1.0 : (maxWeight - minWeight);
    final step = points.length > 1 ? chartWidth / (points.length - 1) : 0.0;

    // (x, yFromTop) — yFromTop measured from the top of the chart box,
    // so it can be used directly as a pw.Positioned "top" value for
    // the label widgets. Higher weight -> smaller yFromTop (closer to
    // the top), same as the reference trend chart.
    (double, double) plot(int i) {
      final x = step * i;
      final yFromTop = topPadding +
          (1 - ((points[i].weight - minWeight) / range)) * plotHeight;
      return (x, yFromTop);
    }

    const dotRadius = 2.8;
    const labelWidth = 34.0;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.SizedBox(
            width: chartWidth,
            height: chartHeight,
            child: pw.Stack(
              children: [
                // Connecting line + dot markers.
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    size: const PdfPoint(chartWidth, chartHeight),
                    painter: (canvas, size) {
                      canvas
                        ..setStrokeColor(PdfColors.green700)
                        ..setLineWidth(1.6);
                      for (int i = 0; i < points.length - 1; i++) {
                        final (ax, ay) = plot(i);
                        final (bx, by) = plot(i + 1);
                        canvas
                          ..moveTo(ax, size.y - ay)
                          ..lineTo(bx, size.y - by)
                          ..strokePath();
                      }
                      for (int i = 0; i < points.length; i++) {
                        final (px, py) = plot(i);
                        canvas
                          ..setColor(PdfColors.green700)
                          ..drawEllipse(px, size.y - py, dotRadius, dotRadius)
                          ..fillPath();
                      }
                    },
                  ),
                ),
                // Weight value label directly above each dot.
                for (int i = 0; i < points.length; i++)
                  pw.Positioned(
                    left: plot(i).$1 - (labelWidth / 2),
                    top: plot(i).$2 - 15,
                    right: labelWidth,
                    child: pw.Text(
                      '${points[i].weight.toStringAsFixed(0)} kg',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green900,
                      ),
                    ),
                  ),
                // Date label directly below each dot.
                for (int i = 0; i < points.length; i++)
                  pw.Positioned(
                    left: plot(i).$1 - (labelWidth / 2),
                    top: chartHeight - bottomPadding + 3,
                    right: labelWidth,
                    child: pw.Text(
                      DateFormat('d MMM').format(points[i].date),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey600),
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.green200),
          pw.SizedBox(height: 4),
          summary,
        ],
      ),
    );
  }

  pw.Widget _weightStat(String label, String value, {bool emphasize = false}) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: emphasize ? 12 : 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // MONTHLY PHOTOS — compact "Month -> representative photo" grid.
  // ==========================================================================

  pw.Widget _buildMonthlyPhotoGrid(GoatFinalReportEntry entry) {
    final months = entry.monthlyHistory.map((r) => r.monthLabel).toList();
    const tileSize = 58.0;

    return pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final month in months)
          if (entry.representativePhotoByMonth[month] != null)
            pw.Column(
              children: [
                pw.Container(
                  width: tileSize,
                  height: tileSize,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                    border: pw.Border.all(color: PdfColors.green200),
                  ),
                  child: pw.ClipRRect(
                    horizontalRadius: 5,
                    verticalRadius: 5,
                    child: pw.Image(
                      _safeMemoryImage(entry.representativePhotoByMonth[month])!,
                      fit: pw.BoxFit.cover,
                      width: tileSize,
                      height: tileSize,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(month, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
              ],
            ),
      ],
    );
  }

  // ==========================================================================
  // GOAT SUMMARY — TABLE FORMAT
  // ==========================================================================

  pw.Widget _buildGoatSummaryBox(GoatFinalReportEntry entry) {
    final rows = <(String, String)>[
      ('Total Months', '${entry.totalMonths}'),
      ('Health Records', '${entry.totalHealthRecords}'),
      ('Vaccinations', '${entry.totalVaccinations}'),
      ('Medicines', '${entry.totalMedicines}'),
      ('Hoof Cutting', '${entry.totalHoofCutting}'),
      ('Hair Trimming', '${entry.totalHairTrimming}'),
      ('Monthly Photos', '${entry.totalPhotos}'),
      ('Health Status', entry.healthStatus.trim().isEmpty ? '-' : entry.healthStatus),
      ('Delivery Status', entry.deliveryStatus.trim().isEmpty ? '-' : entry.deliveryStatus),
    ];

    final labelStyle = pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700);
    final valueStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.6),
      },
      children: [
        for (int i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : PdfColors.green50,
            ),
            children: [
              _tableCell(rows[i].$1, labelStyle),
              _tableCell(rows[i].$2, valueStyle, align: pw.TextAlign.right),
            ],
          ),
      ],
    );
  }

  // ==========================================================================
  // FINAL SETTLEMENT PAGE (always the last page)
  // ==========================================================================

  pw.Widget _buildFinalSettlementPage(PalaiCustomer customer, FinalSettlementData s) {
    final periodLabel = s.periodStart != null
        ? '${_formatMonthYear(s.periodStart!)} \u2013 ${_formatMonthYear(s.periodEnd)}'
        : _formatDate(s.periodEnd);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionBanner(
          number: '\u2713',
          title: 'Final Settlement',
          subtitle: 'Customer: ${s.customerName}  •  Goats: ${s.goatCount}  •  Palai Period: $periodLabel',
        ),
        pw.SizedBox(height: 10),
        _buildPaymentStatRow(s),
        pw.SizedBox(height: 10),
        _buildChargesBreakdown(s),
        pw.SizedBox(height: 10),
        _buildFinalBalanceBox(s),
        pw.SizedBox(height: 10),
        _buildStatusBanner(s),
      ],
    );
  }

  /// Prominent "Total Amount Paid / Remaining" stat row — same visual
  /// language as the goat page's weight-stat row, so the settlement
  /// page opens with the two numbers a customer actually looks for
  /// before they read the full charges breakdown below.
  pw.Widget _buildPaymentStatRow(FinalSettlementData s) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          _weightStat('Total Amount Paid', _currency(s.finalAmountPaid)),
          _weightStat(
            'Remaining',
            _currency(s.finalOutstanding),
            emphasize: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildChargesBreakdown(FinalSettlementData s) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel('CHARGES'),
          pw.SizedBox(height: 6),
          _billingRow('Monthly Palai Charges', _currency(s.totalMonthlyCharges)),
          _billingRow('Transport', _currency(s.totalTransport)),
          if (s.totalOtherCharges > 0) _billingRow('Other Charges', _currency(s.totalOtherCharges)),
          if (s.totalDiscount > 0) _billingRow('Discount', '- ${_currency(s.totalDiscount)}'),
          pw.Divider(color: PdfColors.green200),
          _billingRow('Gross Charges', _currency(s.grossCharges), emphasize: true),
          pw.SizedBox(height: 6),
          _billingRow('Previous Outstanding', _currency(s.previousOutstanding)),
          if (s.advanceApplied > 0) _billingRow('Advance Applied', '- ${_currency(s.advanceApplied)}'),
        ],
      ),
    );
  }

  pw.Widget _buildFinalBalanceBox(FinalSettlementData s) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.green300, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel('FINAL AMOUNT DUE'),
          pw.SizedBox(height: 6),
          _billingRow('Total Due', _currency(s.finalAmountDue)),
          _billingRow('Total Paid (this checkout)', _currency(s.finalAmountPaid)),
          pw.Divider(color: PdfColors.green200),
          _billingRow('Remaining', _currency(s.finalOutstanding), emphasize: true),
          if (s.finalAdvance > 0) ...[
            pw.SizedBox(height: 4),
            _billingRow('Advance Carried Forward', _currency(s.finalAdvance)),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildStatusBanner(FinalSettlementData s) {
    final settled = s.isFullySettled;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: settled ? PdfColors.green700 : PdfColors.orange700,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Text(
        settled ? 'STATUS: FULLY SETTLED' : 'STATUS: PAYMENT PENDING — \u20b9${s.finalOutstanding.toStringAsFixed(0)} REMAINING',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  // ==========================================================================
  // PAGE HEADER — SAME STRUCTURE as CustomerGoatsProgressReportPdfService:
  // full header + customer/info bar on page 1, slim minor header after.
  // ==========================================================================

  pw.Widget _buildPageHeader({
    required pw.Context context,
    required PalaiCustomer customer,
    required int totalGoatsInReport,
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    if (context.pageNumber == 1) {
      return pw.Column(
        children: [
          _buildFullHeader(billSettings: billSettings, logoImage: logoImage),
          pw.SizedBox(height: 4),
          _buildCustomerBar(customer: customer, totalGoatsInReport: totalGoatsInReport),
          pw.SizedBox(height: 4),
        ],
      );
    }

    return pw.Column(
      children: [
        _buildMinorHeader(billSettings: billSettings, logoImage: logoImage),
        pw.SizedBox(height: 4),
      ],
    );
  }

  pw.Widget _buildFullHeader({
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    final darkGreen = PdfColor.fromHex('#1B5E20');
    const double logoSize = 90.0;

    final String farmName = billSettings.businessName.trim().isNotEmpty
        ? billSettings.businessName.trim().toUpperCase()
        : 'MY GOAT FARM';
    final String phone = billSettings.phone.trim();
    final String address = billSettings.address.trim();

    return pw.SizedBox(
      width: double.infinity,
      height: 100,
      child: pw.Stack(
        children: [
          pw.Positioned(left: 4, top: 4, child: _buildFarmLogo(logoImage, size: logoSize)),
          pw.Positioned(
            left: 72,
            right: 10,
            top: 5,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  farmName,
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  style: pw.TextStyle(fontSize: 25.5, fontWeight: pw.FontWeight.bold, color: darkGreen),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'FINAL CHECKOUT REPORT',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700),
                ),
                pw.SizedBox(height: 4),
                pw.Wrap(
                  alignment: pw.WrapAlignment.center,
                  crossAxisAlignment: pw.WrapCrossAlignment.center,
                  children: [
                    if (phone.isNotEmpty)
                      pw.Text(phone, maxLines: 1, style: pw.TextStyle(fontSize: 10.5, color: darkGreen)),
                    if (phone.isNotEmpty && address.isNotEmpty) pw.SizedBox(width: 14),
                    if (address.isNotEmpty)
                      pw.Text(
                        address,
                        maxLines: 1,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 10.5, color: darkGreen),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Clean "logo + farm name" bar used on every page after page 1 —
  /// styled to match the reference sub-header screenshot: a white
  /// pill-shaped bar, circular logo on the left, bold green farm name
  /// next to it, with the report label kept small on the right so the
  /// logo/name pairing reads first.
  pw.Widget _buildMinorHeader({
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    return pw.Container(
      width: double.infinity,
      height: 34,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _buildFarmLogo(logoImage, size: 26),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              billSettings.businessName.trim().isNotEmpty ? billSettings.businessName : 'My Goat Farm',
              maxLines: 1,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
            ),
          ),
          pw.Text(
            'FINAL CHECKOUT REPORT',
            style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green700),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFarmLogo(pw.MemoryImage? logoImage, {double size = 92.0}) {
    final double borderWidth = size >= 40 ? 2 : 1;
    final double padding = size >= 40 ? 3 : 1.5;
    final double innerSize = size - (padding * 2);

    if (logoImage == null) {
      return pw.Container(
        width: size,
        height: size,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.white,
          border: pw.Border.all(color: PdfColors.green800, width: borderWidth),
        ),
        alignment: pw.Alignment.center,
        child: size >= 40
            ? pw.Text('LOGO', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green800))
            : null,
      );
    }

    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(padding),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.green800, width: borderWidth),
        boxShadow: size >= 40
            ? [pw.BoxShadow(color: PdfColor(0, 0, 0, 0.18), blurRadius: 3, offset: const PdfPoint(0, 1))]
            : null,
      ),
      child: pw.ClipRRect(
        horizontalRadius: innerSize / 2,
        verticalRadius: innerSize / 2,
        child: pw.Image(logoImage, fit: pw.BoxFit.cover, width: innerSize, height: innerSize),
      ),
    );
  }

  pw.Widget _buildCustomerBar({
    required PalaiCustomer customer,
    required int totalGoatsInReport,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: _customerInfo('Customer', customer.name)),
          pw.Expanded(child: _customerInfo('Checkout Date', _formatDate(DateTime.now()))),
          pw.Expanded(child: _customerInfo('No. of Goats', '$totalGoatsInReport')),
        ],
      ),
    );
  }

  pw.Widget _customerInfo(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
        pw.SizedBox(height: 1),
        pw.Text(value.trim().isEmpty ? '-' : value, maxLines: 1, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
      ],
    );
  }

  // ==========================================================================
  // SECTION BANNER (same visual language as the Progress Report)
  // ==========================================================================

  pw.Widget _buildSectionBanner({required String number, required String title, required String subtitle}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 25,
            height: 25,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
            child: pw.Text(number, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                if (subtitle.trim().isNotEmpty)
                  pw.Text(subtitle, maxLines: 1, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionLabel(String title) {
    return pw.Text(title, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900));
  }

  pw.Widget _boxTitle(String title) {
    return pw.Text(title, style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900));
  }

  pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 4, child: pw.Text(label, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600))),
          pw.SizedBox(width: 4),
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              value.trim().isEmpty ? '-' : value,
              maxLines: 1,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _billingRow(String label, String value, {bool emphasize = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: emphasize ? 11 : 8.5,
                fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: emphasize ? PdfColors.black : PdfColors.grey700,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasize ? 11 : 9,
              fontWeight: pw.FontWeight.bold,
              color: emphasize ? PdfColors.green900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableCell(String text, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  // ==========================================================================
  // TERMS & CONDITIONS / IMPORTANT NOTES / CLOSING — same visual
  // language as CustomerGoatsProgressReportPdfService's equivalents.
  // This is currently a second, duplicated copy of that widget code
  // rather than a shared import — the same trade-off already made for
  // the header/footer/logo in this file (see the class-level doc
  // comment). Extracting a shared pdf_report_chrome.dart for all of
  // these is real cleanup debt, not done here.
  // ==========================================================================

  pw.Widget _buildTermsGrid(BillSettings b) {
    final sections = b.termsSections.where((s) => s.enabled).toList();
    final widgets = <pw.Widget>[];

    for (int i = 0; i < sections.length; i++) {
      widgets.add(_termCard(i + 1, sections[i].title, sections[i].text));
    }

    if (b.otherTermsEnabled && b.otherTermsText.trim().isNotEmpty) {
      widgets.add(_termCard(
        sections.length + 1,
        b.otherTermsTitle.trim().isNotEmpty ? b.otherTermsTitle : 'Other',
        b.otherTermsText,
      ));
    }

    if (widgets.isEmpty) {
      return pw.Text(
        'No terms and conditions configured.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      );
    }

    final rows = <pw.Widget>[];
    for (int i = 0; i < widgets.length; i += 2) {
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: widgets[i]),
              pw.SizedBox(width: 8),
              pw.Expanded(child: i + 1 < widgets.length ? widgets[i + 1] : pw.SizedBox()),
            ],
          ),
        ),
      );
    }

    return pw.Column(children: rows);
  }

  pw.Widget _termCard(int number, String title, String text) {
    return pw.Container(
      height: 82,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 19,
            height: 19,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
            child: pw.Text('$number', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, maxLines: 2, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                pw.SizedBox(height: 4),
                pw.Text(text, style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700, lineSpacing: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildImportantNotes(BillSettings b) {
    final notes = b.importantNotes.where((n) => n.enabled).toList();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('IMPORTANT NOTES', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 5),
          for (final note in notes) _bullet('${note.title}: ${note.text}'),
          if (b.otherNoteEnabled && b.otherNoteText.trim().isNotEmpty) _bullet(b.otherNoteText),
        ],
      ),
    );
  }

  pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('\u2022', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
          pw.SizedBox(width: 5),
          pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700))),
        ],
      ),
    );
  }

  pw.Widget _buildClosingBanner(BillSettings b) {
    final text = b.footerNote.trim().isNotEmpty ? b.footerNote : 'We care for your goats as our own.';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: pw.BoxDecoration(color: PdfColors.green900, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7))),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  // ==========================================================================
  // FOOTER — same as the Progress Report (accurate Page X of Y via
  // pw.MultiPage's own context).
  // ==========================================================================

  pw.Widget _buildFooter({
    required BillSettings billSettings,
    required int pageNumber,
    required int totalPages,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      child: pw.Row(
        children: [
          pw.Text(billSettings.businessName, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
          pw.Spacer(),
          pw.Text('Page $pageNumber of $totalPages', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  // ==========================================================================
  // FORMAT HELPERS
  // ==========================================================================

  String _currency(double value) {
    final formatter = NumberFormat('#,##0.00', 'en_IN');
    return '\u20b9${formatter.format(value)}';
  }

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  String _formatMonthYear(DateTime date) => DateFormat('MMM yyyy').format(date);

  String _safeFileName(PalaiCustomer customer) {
    final raw = 'FinalCheckout_${customer.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_');
    return '$cleaned.pdf';
  }
}