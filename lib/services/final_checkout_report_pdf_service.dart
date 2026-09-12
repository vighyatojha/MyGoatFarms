import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/final_checkout_report_model.dart';
import '../models/goat_history_models.dart';
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
/// [CustomerGoatsProgressReportPdfService].
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
    Uint8List? farmLogoOverride,
  }) async {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    final logoImage = _safeMemoryImage(
      farmLogoOverride ?? billSettings.billLogo,
    );

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

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _safeFileName(customer),
    );
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

    await Printing.sharePdf(
      bytes: bytes,
      filename: _safeFileName(customer),
    );
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
    final file = File(
      '${directory.path}/${_safeFileName(customer)}',
    );

    await file.writeAsBytes(bytes);

    return file.path;
  }

  Future<void> shareBytes(
      Uint8List bytes,
      String filename,
      ) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: filename,
    );
  }

  Future<String> saveBytes(
      Uint8List bytes,
      String filename,
      ) async {
    final directory = await getApplicationDocumentsDirectory();

    final file = File(
      '${directory.path}/$filename',
    );

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return file.path;
  }

  // ==========================================================================
  // IMAGE LOADING
  // ==========================================================================

  pw.MemoryImage? _safeMemoryImage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

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
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
            ),
          ),
        ),
      );
    } else {
      // ONE GOAT = ONE PAGE.
      for (int i = 0; i < goatEntries.length; i++) {
        content.add(
          _buildGoatFinalReportPage(
            i + 1,
            goatEntries[i],
          ),
        );

        content.add(
          pw.NewPage(),
        );
      }
    }

    final settlementSectionNumber =
    goatEntries.isEmpty ? 1 : goatEntries.length + 1;

    final termsSectionNumber =
        settlementSectionNumber + 1;

    // FINAL SETTLEMENT
    content.add(
      _buildFinalSettlementPage(
        customer,
        settlement,
        settlementSectionNumber,
      ),
    );

    // TERMS & CONDITIONS
    content.add(
      pw.NewPage(),
    );

    content.add(
      _buildSectionBanner(
        number: '$termsSectionNumber',
        title: 'Terms & Conditions',
        subtitle:
        'Important notes • Customer acknowledgement • Farm policies',
      ),
    );

    content.add(
      pw.SizedBox(height: 10),
    );

    content.add(
      _buildTermsGrid(billSettings),
    );

    content.add(
      pw.SizedBox(height: 9),
    );

    content.add(
      _buildImportantNotes(billSettings),
    );

    content.add(
      pw.SizedBox(height: 14),
    );

    content.add(
      _buildClosingBanner(billSettings),
    );

    return content;
  }

  // ==========================================================================
  // ONE GOAT PAGE
  // ==========================================================================

  pw.Widget _buildGoatFinalReportPage(
      int number,
      GoatFinalReportEntry entry,
      ) {
    final goat = entry.goat;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionBanner(
          number: '$number',
          title: 'Goat Final Report — ${_goatLabel(goat)}',
          subtitle:
          'Check-in ${_formatDate(entry.checkInDate)}  •  Check-out ${_formatDate(entry.checkOutDate)}',
        ),

        pw.SizedBox(height: 6),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 4,
              child: _goatInfoBox(entry),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              flex: 4,
              child: _goatPhotoPair(entry),
            ),
          ],
        ),

        pw.SizedBox(height: 8),

        _sectionLabel('WEIGHT PROGRESS'),

        pw.SizedBox(height: 4),

        _buildWeightProgressChart(entry),

        pw.SizedBox(height: 6),

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
    final code = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : goat.tagNumber;

    final name = goat.name.trim();

    return name.isNotEmpty
        ? '$code ($name)'
        : code;
  }

  // ==========================================================================
  // GOAT INFORMATION
  // ==========================================================================

  pw.Widget _goatInfoBox(
      GoatFinalReportEntry entry,
      ) {
    final goat = entry.goat;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle('GOAT INFORMATION'),

          pw.SizedBox(height: 4),

          _detailRow(
            'Breed',
            goat.breed,
          ),

          _detailRow(
            'Gender',
            goat.gender,
          ),

          _detailRow(
            'Color',
            goat.color,
          ),

          _detailRow(
            'Check-in Date',
            _formatDate(entry.checkInDate),
          ),

          _detailRow(
            'Check-out Date',
            _formatDate(entry.checkOutDate),
          ),

          _detailRow(
            'Initial Weight',
            '${entry.initialWeight.toStringAsFixed(1)} kg',
          ),

          _detailRow(
            'Final Weight',
            '${entry.finalWeight.toStringAsFixed(1)} kg',
          ),

          _detailRow(
            'Weight Change',
            '${entry.weightChange >= 0 ? '+' : ''}${entry.weightChange.toStringAsFixed(1)} kg',
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ARRIVAL / CURRENT PHOTOS
  // ==========================================================================

  pw.Widget _goatPhotoPair(
      GoatFinalReportEntry entry,
      ) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          'ARRIVAL / CURRENT',
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
        ),

        pw.SizedBox(height: 4),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            _photoTile(
              label: 'Check-in',
              bytes: entry.beforeImage,
            ),

            pw.SizedBox(width: 6),

            _photoTile(
              label: 'Check-out',
              bytes: entry.afterImage,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _photoTile({
    required String label,
    required Uint8List? bytes,
  }) {
    const size = 90.0;

    final image = _safeMemoryImage(bytes);

    return pw.Column(
      children: [
        pw.Container(
          width: size,
          height: size,
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(
              pw.Radius.circular(6),
            ),
            border: pw.Border.all(
              color: PdfColors.green200,
            ),
            color: PdfColors.grey100,
          ),
          child: image != null
              ? pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Image(
              image,
              fit: pw.BoxFit.cover,
              width: size,
              height: size,
            ),
          )
              : pw.Center(
            child: pw.Text(
              'No photo',
              style: const pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey500,
              ),
            ),
          ),
        ),

        pw.SizedBox(height: 2),

        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 6.5,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // WEIGHT PROGRESS CHART
  // ==========================================================================

  pw.Widget _buildWeightProgressChart(
      GoatFinalReportEntry entry,
      ) {
    final points = _buildMonthlyWeightPoints(entry);

    return pw.SizedBox(
      width: double.infinity,
      height: 116,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ------------------------------------------------------------------
          // WEIGHT PROGRESS CARD
          // ------------------------------------------------------------------

          pw.Expanded(
            flex: 6,
            child: pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(
                8,
                7,
                8,
                5,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                border: pw.Border.all(
                  color: PdfColors.green200,
                  width: 0.7,
                ),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(7),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      // Green circle intentionally has NO Unicode icon.
                      pw.Container(
                        width: 13,
                        height: 13,
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.green700,
                          shape: pw.BoxShape.circle,
                        ),
                      ),

                      pw.SizedBox(width: 4),

                      pw.Text(
                        'WEIGHT PROGRESS',
                        style: pw.TextStyle(
                          fontSize: 6.8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green900,
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 3),

                  pw.Expanded(
                    child: _buildLinearWeightChart(points),
                  ),
                ],
              ),
            ),
          ),

          pw.SizedBox(width: 8),

          // ------------------------------------------------------------------
          // WEIGHT DETAILS CARD
          // ------------------------------------------------------------------

          pw.Expanded(
            flex: 4,
            child: pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(
                10,
                8,
                10,
                7,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                border: pw.Border.all(
                  color: PdfColors.green200,
                  width: 0.7,
                ),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(7),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      // Green circle intentionally has NO Unicode icon.
                      pw.Container(
                        width: 13,
                        height: 13,
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.green700,
                          shape: pw.BoxShape.circle,
                        ),
                      ),

                      pw.SizedBox(width: 4),

                      pw.Text(
                        'WEIGHT DETAILS',
                        style: pw.TextStyle(
                          fontSize: 6.8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green900,
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 5),

                  _compactWeightDetail(
                    'Initial Weight',
                    '${entry.initialWeight.toStringAsFixed(1)} kg',
                  ),

                  pw.SizedBox(height: 4),

                  _compactWeightDetail(
                    'Current Weight',
                    '${entry.finalWeight.toStringAsFixed(1)} kg',
                  ),

                  pw.SizedBox(height: 5),

                  pw.Container(
                    height: 0.6,
                    color: PdfColors.green200,
                  ),

                  pw.SizedBox(height: 4),

                  pw.Text(
                    'Total Gain',
                    style: const pw.TextStyle(
                      fontSize: 6.2,
                      color: PdfColors.grey600,
                    ),
                  ),

                  pw.SizedBox(height: 1),

                  // IMPORTANT:
                  // Removed the Unicode ↗ character that was rendering
                  // as the unwanted square/object.
                  pw.Text(
                    '${entry.weightChange >= 0 ? '+' : ''}${entry.weightChange.toStringAsFixed(1)} kg',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // COMPACT WEIGHT DETAIL
  // ==========================================================================

  pw.Widget _compactWeightDetail(
      String label,
      String value,
      ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 6.2,
            color: PdfColors.grey600,
          ),
        ),

        pw.SizedBox(height: 1),

        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // MONTHLY WEIGHT POINTS
  // ==========================================================================

  List<(DateTime, double)> _buildMonthlyWeightPoints(
      GoatFinalReportEntry entry,
      ) {
    final history = [...entry.weightHistory]
      ..sort(
            (a, b) => a.date.compareTo(b.date),
      );

    if (history.isEmpty) {
      return [
        (
        entry.checkInDate,
        entry.initialWeight,
        ),
        (
        entry.checkOutDate,
        entry.finalWeight,
        ),
      ];
    }

    final byMonth = <String, GoatWeightHistoryPoint>{};

    for (final point in history) {
      final key =
          '${point.date.year}-${point.date.month}';

      byMonth[key] = point;
    }

    final points = byMonth.values
        .map(
          (point) => (
      point.date,
      point.weight,
      ),
    )
        .toList()
      ..sort(
            (a, b) => a.$1.compareTo(b.$1),
      );

    // Keep arrival weight visible.
    if (points.isEmpty ||
        points.first.$1.isAfter(entry.checkInDate)) {
      points.insert(
        0,
        (
        entry.checkInDate,
        entry.initialWeight,
        ),
      );
    }

    // Keep checkout weight visible.
    if (points.isEmpty ||
        points.last.$1.isBefore(entry.checkOutDate)) {
      points.add(
        (
        entry.checkOutDate,
        entry.finalWeight,
        ),
      );
    } else {
      points[points.length - 1] = (
      points.last.$1,
      entry.finalWeight,
      );
    }

    // Avoid duplicate months.
    final compact = <(DateTime, double)>[];

    for (final point in points) {
      if (compact.isNotEmpty &&
          compact.last.$1.year == point.$1.year &&
          compact.last.$1.month == point.$1.month) {
        compact[compact.length - 1] = point;
      } else {
        compact.add(point);
      }
    }

    if (compact.length == 1) {
      compact.add(
        (
        entry.checkOutDate,
        entry.finalWeight,
        ),
      );
    }

    return compact;
  }

  // ==========================================================================
  // LINEAR WEIGHT CHART
  // ==========================================================================

  pw.Widget _buildLinearWeightChart(
      List<(DateTime, double)> points,
      ) {
    const double chartHeight = 86;
    const double chartWidth = 300;
    const double yAxisWidth = 24;
    const double rightPadding = 5;
    const double topPadding = 7;
    const double bottomPadding = 18;

    final weights = points
        .map((p) => p.$2)
        .toList();

    final rawMin = weights.reduce(
          (a, b) => a < b ? a : b,
    );

    final rawMax = weights.reduce(
          (a, b) => a > b ? a : b,
    );

    final rawRange = rawMax - rawMin;

    final padding = rawRange <= 0
        ? 2.0
        : (rawRange * 0.18).clamp(
      0.5,
      5.0,
    );

    final minWeight =
    (rawMin - padding).floorToDouble();

    final maxWeight =
    (rawMax + padding).ceilToDouble();

    final weightRange =
    (maxWeight - minWeight) <= 0
        ? 1.0
        : maxWeight - minWeight;

    const int gridLevels = 4;

    final plotHeight =
        chartHeight -
            topPadding -
            bottomPadding;

    final plotWidth =
        chartWidth -
            yAxisWidth -
            rightPadding;

    final step = points.length <= 1
        ? 0.0
        : plotWidth / (points.length - 1);

    (double, double) pointAt(int index) {
      final x =
          yAxisWidth +
              (step * index);

      final normalized =
      ((points[index].$2 - minWeight) /
          weightRange)
          .clamp(
        0.0,
        1.0,
      );

      final y =
          topPadding +
              ((1 - normalized) * plotHeight);

      return (
      x,
      y,
      );
    }

    return pw.SizedBox(
      width: chartWidth,
      height: chartHeight,
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------------------
          // Y AXIS
          // ------------------------------------------------------------------

          pw.SizedBox(
            width: yAxisWidth,
            height: chartHeight,
            child: pw.Stack(
              children: [
                for (int i = 0;
                i <= gridLevels;
                i++)
                  pw.Positioned(
                    left: 0,
                    top: topPadding -
                        3 +
                        (plotHeight *
                            i /
                            gridLevels),
                    right: yAxisWidth - 3,
                    child: pw.Text(
                      '${(maxWeight - (weightRange * i / gridLevels)).toStringAsFixed(0)}',
                      textAlign:
                      pw.TextAlign.right,
                      style:
                      const pw.TextStyle(
                        fontSize: 5.1,
                        color:
                        PdfColors.grey700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ------------------------------------------------------------------
          // PLOT AREA
          // ------------------------------------------------------------------

          pw.SizedBox(
            width: plotWidth,
            height: chartHeight,
            child: pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    size: PdfPoint(
                      plotWidth,
                      chartHeight,
                    ),
                    painter: (
                        canvas,
                        size,
                        ) {
                      final localStep =
                      points.length <= 1
                          ? 0.0
                          : size.x /
                          (points.length - 1);

                      (double, double)
                      localPointAt(
                          int index,
                          ) {
                        final normalized =
                        ((points[index].$2 -
                            minWeight) /
                            weightRange)
                            .clamp(
                          0.0,
                          1.0,
                        );

                        final y =
                            topPadding +
                                ((1 - normalized) *
                                    plotHeight);

                        return (
                        localStep * index,
                        y,
                        );
                      }

                      // Horizontal grid lines.
                      canvas
                        ..setStrokeColor(
                          PdfColors.grey300,
                        )
                        ..setLineWidth(
                          0.45,
                        );

                      for (int i = 0;
                      i <= gridLevels;
                      i++) {
                        final y =
                            topPadding +
                                (plotHeight *
                                    i /
                                    gridLevels);

                        canvas
                          ..moveTo(
                            0,
                            size.y - y,
                          )
                          ..lineTo(
                            size.x,
                            size.y - y,
                          )
                          ..strokePath();
                      }

                      // X-axis baseline.
                      final baselineY =
                          chartHeight -
                              bottomPadding;

                      canvas
                        ..setStrokeColor(
                          PdfColors.grey400,
                        )
                        ..setLineWidth(
                          0.6,
                        )
                        ..moveTo(
                          0,
                          size.y - baselineY,
                        )
                        ..lineTo(
                          size.x,
                          size.y - baselineY,
                        )
                        ..strokePath();

                      if (points.length >= 2) {
                        // ----------------------------------------------------
                        // SHADED AREA
                        // ----------------------------------------------------

                        final first =
                        localPointAt(0);

                        final last =
                        localPointAt(
                          points.length - 1,
                        );

                        canvas.moveTo(
                          first.$1,
                          size.y - first.$2,
                        );

                        for (int i = 1;
                        i < points.length;
                        i++) {
                          final p =
                          localPointAt(i);

                          canvas.lineTo(
                            p.$1,
                            size.y - p.$2,
                          );
                        }

                        canvas
                          ..lineTo(
                            last.$1,
                            size.y - baselineY,
                          )
                          ..lineTo(
                            first.$1,
                            size.y - baselineY,
                          )
                          ..setColor(
                            PdfColors.green100,
                          )
                          ..fillPath();

                        // ----------------------------------------------------
                        // TREND LINE
                        // ----------------------------------------------------

                        canvas
                          ..setStrokeColor(
                            PdfColors.green700,
                          )
                          ..setLineWidth(
                            1.35,
                          );

                        for (int i = 0;
                        i < points.length - 1;
                        i++) {
                          final a =
                          localPointAt(i);

                          final b =
                          localPointAt(i + 1);

                          canvas
                            ..moveTo(
                              a.$1,
                              size.y - a.$2,
                            )
                            ..lineTo(
                              b.$1,
                              size.y - b.$2,
                            )
                            ..strokePath();
                        }
                      }

                      // Point markers.
                      for (int i = 0;
                      i < points.length;
                      i++) {
                        final p =
                        localPointAt(i);

                        canvas
                          ..setColor(
                            PdfColors.green700,
                          )
                          ..drawEllipse(
                            p.$1,
                            size.y - p.$2,
                            2.4,
                            2.4,
                          )
                          ..fillPath();
                      }
                    },
                  ),
                ),

                // ----------------------------------------------------------------
                // WEIGHT VALUES
                // ----------------------------------------------------------------

                for (int i = 0;
                i < points.length;
                i++)
                  pw.Positioned(
                    left: (step * i) - 17,
                    top: (pointAt(i).$2 - 9)
                        .clamp(
                      0.0,
                      chartHeight - 25,
                    ),
                    right: 34,
                    child: pw.Text(
                      '${points[i].$2.toStringAsFixed(1)} kg',
                      textAlign:
                      pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 4.8,
                        fontWeight:
                        pw.FontWeight.bold,
                        color:
                        PdfColors.green900,
                      ),
                    ),
                  ),

                // ----------------------------------------------------------------
                // DATE LABELS
                // ----------------------------------------------------------------

                for (int i = 0;
                i < points.length;
                i++)
                  pw.Positioned(
                    left: (step * i) - 25,
                    top: chartHeight -
                        bottomPadding +
                        3,
                    right: 50,
                    child: pw.Text(
                      DateFormat(
                        'dd MMM yyyy',
                      ).format(
                        points[i].$1,
                      ),
                      textAlign:
                      pw.TextAlign.center,
                      style:
                      const pw.TextStyle(
                        fontSize: 4.6,
                        color:
                        PdfColors.grey700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WEIGHT STAT
  // ==========================================================================

  pw.Widget _weightStat(
      String label,
      String value, {
        bool emphasize = false,
        bool leftAligned = false,
      }) {
    return pw.Column(
      crossAxisAlignment: leftAligned
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          textAlign: leftAligned
              ? pw.TextAlign.left
              : pw.TextAlign.center,
          style: const pw.TextStyle(
            fontSize: 6.2,
            color: PdfColors.grey600,
          ),
        ),

        pw.SizedBox(height: 1),

        pw.Text(
          value,
          textAlign: leftAligned
              ? pw.TextAlign.left
              : pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize:
            emphasize ? 11 : 9.5,
            fontWeight:
            pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // MONTHLY PHOTOS
  // ==========================================================================

  pw.Widget _buildMonthlyPhotoGrid(
      GoatFinalReportEntry entry,
      ) {
    final months = entry.monthlyHistory
        .map(
          (r) => r.monthLabel,
    )
        .toList();

    const tileSize = 58.0;

    return pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final month in months)
          if (entry.representativePhotoByMonth[
          month] !=
              null)
            pw.Column(
              children: [
                pw.Container(
                  width: tileSize,
                  height: tileSize,
                  decoration: pw.BoxDecoration(
                    borderRadius:
                    const pw.BorderRadius.all(
                      pw.Radius.circular(5),
                    ),
                    border: pw.Border.all(
                      color:
                      PdfColors.green200,
                    ),
                  ),
                  child: pw.ClipRRect(
                    horizontalRadius: 5,
                    verticalRadius: 5,
                    child: pw.Image(
                      _safeMemoryImage(
                        entry.representativePhotoByMonth[
                        month],
                      )!,
                      fit: pw.BoxFit.cover,
                      width: tileSize,
                      height: tileSize,
                    ),
                  ),
                ),

                pw.SizedBox(height: 2),

                pw.Text(
                  month,
                  style:
                  const pw.TextStyle(
                    fontSize: 6,
                    color:
                    PdfColors.grey700,
                  ),
                ),
              ],
            ),
      ],
    );
  }

  // ==========================================================================
  // GOAT SUMMARY
  // ==========================================================================

  pw.Widget _buildGoatSummaryBox(
      GoatFinalReportEntry entry,
      ) {
    final rows = <(String, String)>[
      (
      'Total Months',
      '${entry.totalMonths}',
      ),
      (
      'Health Records',
      '${entry.totalHealthRecords}',
      ),
      (
      'Vaccinations',
      '${entry.totalVaccinations}',
      ),
      (
      'Medicines',
      '${entry.totalMedicines}',
      ),
      (
      'Hoof Cutting',
      '${entry.totalHoofCutting}',
      ),
      (
      'Hair Trimming',
      '${entry.totalHairTrimming}',
      ),
      (
      'Monthly Photos',
      '${entry.totalPhotos}',
      ),
      (
      'Health Status',
      entry.healthStatus.trim().isEmpty
          ? '-'
          : entry.healthStatus,
      ),
      (
      'Delivery Status',
      entry.deliveryStatus.trim().isEmpty
          ? '-'
          : entry.deliveryStatus,
      ),
    ];

    final labelStyle = pw.TextStyle(
      fontSize: 7.5,
      color: PdfColors.grey700,
    );

    final valueStyle = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.green900,
    );

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey300,
        width: 0.5,
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.6),
      },
      children: [
        for (int i = 0;
        i < rows.length;
        i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven
                  ? PdfColors.white
                  : PdfColors.green50,
            ),
            children: [
              _tableCell(
                rows[i].$1,
                labelStyle,
              ),
              _tableCell(
                rows[i].$2,
                valueStyle,
                align: pw.TextAlign.right,
              ),
            ],
          ),
      ],
    );
  }

  // ==========================================================================
  // FINAL SETTLEMENT
  // ==========================================================================

  pw.Widget _buildFinalSettlementPage(
      PalaiCustomer customer,
      FinalSettlementData s,
      int sectionNumber,
      ) {
    final periodLabel = s.periodStart != null
        ? '${_formatMonthYear(s.periodStart!)} – ${_formatMonthYear(s.periodEnd)}'
        : _formatDate(s.periodEnd);

    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: [
        _buildSectionBanner(
          number: '$sectionNumber',
          title: 'Final Settlement',
          subtitle:
          'Customer: ${s.customerName}  •  Goats: ${s.goatCount}  •  Palai Period: $periodLabel',
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

  // ==========================================================================
  // PAYMENT STAT ROW
  // ==========================================================================

  pw.Widget _buildPaymentStatRow(
      FinalSettlementData s,
      ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(
          color: PdfColors.green200,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment:
        pw.MainAxisAlignment.spaceEvenly,
        children: [
          _weightStat(
            'Total Amount Paid',
            _currency(s.finalAmountPaid),
          ),

          _weightStat(
            'Remaining',
            _currency(s.finalOutstanding),
            emphasize: true,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CHARGES BREAKDOWN
  // ==========================================================================

  pw.Widget _buildChargesBreakdown(
      FinalSettlementData s,
      ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(
          color: PdfColors.green200,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel('CHARGES'),

          pw.SizedBox(height: 6),

          _billingRow(
            'Monthly Palai Charges',
            _currency(
              s.totalMonthlyCharges,
            ),
          ),

          _billingRow(
            'Transport',
            _currency(
              s.totalTransport,
            ),
          ),

          if (s.totalOtherCharges > 0)
            _billingRow(
              'Other Charges',
              _currency(
                s.totalOtherCharges,
              ),
            ),

          if (s.totalDiscount > 0)
            _billingRow(
              'Discount',
              '- ${_currency(s.totalDiscount)}',
            ),

          pw.Divider(
            color: PdfColors.green200,
          ),

          _billingRow(
            'Gross Charges',
            _currency(s.grossCharges),
            emphasize: true,
          ),

          pw.SizedBox(height: 6),

          _billingRow(
            'Previous Outstanding',
            _currency(
              s.previousOutstanding,
            ),
          ),

          if (s.advanceApplied > 0)
            _billingRow(
              'Advance Applied',
              '- ${_currency(s.advanceApplied)}',
            ),
        ],
      ),
    );
  }

  // ==========================================================================
  // FINAL BALANCE
  // ==========================================================================

  pw.Widget _buildFinalBalanceBox(
      FinalSettlementData s,
      ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(
          color: PdfColors.green300,
          width: 1,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            'FINAL AMOUNT DUE',
          ),

          pw.SizedBox(height: 6),

          _billingRow(
            'Total Due',
            _currency(
              s.finalAmountDue,
            ),
          ),

          _billingRow(
            'Total Paid (this checkout)',
            _currency(
              s.finalAmountPaid,
            ),
          ),

          pw.Divider(
            color: PdfColors.green200,
          ),

          _billingRow(
            'Remaining',
            _currency(
              s.finalOutstanding,
            ),
            emphasize: true,
          ),

          if (s.finalAdvance > 0) ...[
            pw.SizedBox(height: 4),

            _billingRow(
              'Advance Carried Forward',
              _currency(
                s.finalAdvance,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // STATUS
  // ==========================================================================

  pw.Widget _buildStatusBanner(
      FinalSettlementData s,
      ) {
    final settled = s.isFullySettled;

    return pw.Container(
      width: double.infinity,
      padding:
      const pw.EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 12,
      ),
      decoration: pw.BoxDecoration(
        color: settled
            ? PdfColors.green700
            : PdfColors.orange700,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(8),
        ),
      ),
      child: pw.Text(
        settled
            ? 'STATUS: FULLY SETTLED'
            : 'STATUS: PAYMENT PENDING — ₹${s.finalOutstanding.toStringAsFixed(0)} REMAINING',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  // ==========================================================================
  // PAGE HEADER
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
          _buildFullHeader(
            billSettings: billSettings,
            logoImage: logoImage,
          ),

          pw.SizedBox(height: 4),

          _buildCustomerBar(
            customer: customer,
            totalGoatsInReport:
            totalGoatsInReport,
          ),

          pw.SizedBox(height: 4),
        ],
      );
    }

    return pw.Column(
      children: [
        _buildMinorHeader(
          billSettings: billSettings,
          logoImage: logoImage,
        ),

        pw.SizedBox(height: 4),
      ],
    );
  }

  // ==========================================================================
  // FULL HEADER
  // ==========================================================================

  pw.Widget _buildFullHeader({
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    final darkGreen =
    PdfColor.fromHex('#1B5E20');

    const double logoSize = 90.0;

    final String farmName =
    billSettings.businessName.trim().isNotEmpty
        ? billSettings.businessName
        .trim()
        .toUpperCase()
        : 'MY GOAT FARM';

    final String phone =
    billSettings.phone.trim();

    final String address =
    billSettings.address.trim();

    return pw.SizedBox(
      width: double.infinity,
      height: 100,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 4,
            top: 4,
            child: _buildFarmLogo(
              logoImage,
              size: logoSize,
            ),
          ),

          pw.Positioned(
            left: 72,
            right: 10,
            top: 5,
            child: pw.Column(
              mainAxisSize:
              pw.MainAxisSize.min,
              crossAxisAlignment:
              pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  farmName,
                  textAlign:
                  pw.TextAlign.center,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 25.5,
                    fontWeight:
                    pw.FontWeight.bold,
                    color: darkGreen,
                  ),
                ),

                pw.SizedBox(height: 3),

                pw.Text(
                  'FINAL CHECKOUT REPORT',
                  textAlign:
                  pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight:
                    pw.FontWeight.bold,
                    color:
                    PdfColors.green700,
                  ),
                ),

                pw.SizedBox(height: 4),

                pw.Wrap(
                  alignment:
                  pw.WrapAlignment.center,
                  crossAxisAlignment:
                  pw.WrapCrossAlignment.center,
                  children: [
                    if (phone.isNotEmpty)
                      pw.Text(
                        phone,
                        maxLines: 1,
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          color: darkGreen,
                        ),
                      ),

                    if (phone.isNotEmpty &&
                        address.isNotEmpty)
                      pw.SizedBox(width: 14),

                    if (address.isNotEmpty)
                      pw.Text(
                        address,
                        maxLines: 1,
                        textAlign:
                        pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          color: darkGreen,
                        ),
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

  // ==========================================================================
  // MINOR HEADER
  // ==========================================================================

  pw.Widget _buildMinorHeader({
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    return pw.Container(
      width: double.infinity,
      height: 34,
      padding:
      const pw.EdgeInsets.symmetric(
        horizontal: 8,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(8),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.7,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.center,
        children: [
          _buildFarmLogo(
            logoImage,
            size: 26,
          ),

          pw.SizedBox(width: 8),

          pw.Expanded(
            child: pw.Text(
              billSettings.businessName
                  .trim()
                  .isNotEmpty
                  ? billSettings.businessName
                  : 'My Goat Farm',
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight:
                pw.FontWeight.bold,
                color:
                PdfColors.green900,
              ),
            ),
          ),

          pw.Text(
            'FINAL CHECKOUT REPORT',
            style: pw.TextStyle(
              fontSize: 6.5,
              fontWeight:
              pw.FontWeight.bold,
              color:
              PdfColors.green700,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // FARM LOGO
  // ==========================================================================

  pw.Widget _buildFarmLogo(
      pw.MemoryImage? logoImage, {
        double size = 92.0,
      }) {
    final double borderWidth =
    size >= 40 ? 2 : 1;

    final double padding =
    size >= 40 ? 3 : 1.5;

    final double innerSize =
        size - (padding * 2);

    if (logoImage == null) {
      return pw.Container(
        width: size,
        height: size,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.white,
          border: pw.Border.all(
            color: PdfColors.green800,
            width: borderWidth,
          ),
        ),
        alignment: pw.Alignment.center,
        child: size >= 40
            ? pw.Text(
          'LOGO',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight:
            pw.FontWeight.bold,
            color:
            PdfColors.green800,
          ),
        )
            : null,
      );
    }

    return pw.Container(
      width: size,
      height: size,
      padding:
      pw.EdgeInsets.all(padding),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: PdfColors.white,
        border: pw.Border.all(
          color: PdfColors.green800,
          width: borderWidth,
        ),
        boxShadow: size >= 40
            ? [
          pw.BoxShadow(
            color: PdfColor(
              0,
              0,
              0,
              0.18,
            ),
            blurRadius: 3,
            offset: const PdfPoint(
              0,
              1,
            ),
          ),
        ]
            : null,
      ),
      child: pw.ClipRRect(
        horizontalRadius:
        innerSize / 2,
        verticalRadius:
        innerSize / 2,
        child: pw.Image(
          logoImage,
          fit: pw.BoxFit.cover,
          width: innerSize,
          height: innerSize,
        ),
      ),
    );
  }

  // ==========================================================================
  // CUSTOMER BAR
  // ==========================================================================

  pw.Widget _buildCustomerBar({
    required PalaiCustomer customer,
    required int totalGoatsInReport,
  }) {
    return pw.Container(
      width: double.infinity,
      padding:
      const pw.EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(6),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.7,
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _customerInfo(
              'Customer',
              customer.name,
            ),
          ),

          pw.Expanded(
            child: _customerInfo(
              'Checkout Date',
              _formatDate(DateTime.now()),
            ),
          ),

          pw.Expanded(
            child: _customerInfo(
              'No. of Goats',
              '$totalGoatsInReport',
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _customerInfo(
      String label,
      String value,
      ) {
    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 6.5,
            fontWeight:
            pw.FontWeight.bold,
            color:
            PdfColors.green800,
          ),
        ),

        pw.SizedBox(height: 1),

        pw.Text(
          value.trim().isEmpty
              ? '-'
              : value,
          maxLines: 1,
          style: const pw.TextStyle(
            fontSize: 7.5,
            color:
            PdfColors.grey800,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // SECTION BANNER
  // ==========================================================================

  pw.Widget _buildSectionBanner({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return pw.Container(
      width: double.infinity,
      padding:
      const pw.EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.7,
        ),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 25,
            height: 25,
            alignment:
            pw.Alignment.center,
            decoration:
            const pw.BoxDecoration(
              color: PdfColors.green700,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              number,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight:
                pw.FontWeight.bold,
                color:
                PdfColors.white,
              ),
            ),
          ),

          pw.SizedBox(width: 8),

          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment:
              pw.MainAxisAlignment.center,
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight:
                    pw.FontWeight.bold,
                    color:
                    PdfColors.green900,
                  ),
                ),

                if (subtitle
                    .trim()
                    .isNotEmpty)
                  pw.Text(
                    subtitle,
                    maxLines: 1,
                    style:
                    const pw.TextStyle(
                      fontSize: 6.5,
                      color:
                      PdfColors.grey700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionLabel(
      String title,
      ) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight:
        pw.FontWeight.bold,
        color:
        PdfColors.green900,
      ),
    );
  }

  pw.Widget _boxTitle(
      String title,
      ) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 6.8,
        fontWeight:
        pw.FontWeight.bold,
        color:
        PdfColors.green900,
      ),
    );
  }

  // ==========================================================================
  // DETAIL ROW
  // ==========================================================================

  pw.Widget _detailRow(
      String label,
      String value,
      ) {
    return pw.Padding(
      padding:
      const pw.EdgeInsets.only(
        bottom: 2,
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style:
              const pw.TextStyle(
                fontSize: 6.5,
                color:
                PdfColors.grey600,
              ),
            ),
          ),

          pw.SizedBox(width: 4),

          pw.Expanded(
            flex: 5,
            child: pw.Text(
              value.trim().isEmpty
                  ? '-'
                  : value,
              maxLines: 1,
              textAlign:
              pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight:
                pw.FontWeight.bold,
                color:
                PdfColors.grey900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // BILLING ROW
  // ==========================================================================

  pw.Widget _billingRow(
      String label,
      String value, {
        bool emphasize = false,
      }) {
    return pw.Padding(
      padding:
      const pw.EdgeInsets.only(
        bottom: 6,
      ),
      child: pw.Row(
        mainAxisAlignment:
        pw.MainAxisAlignment
            .spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize:
                emphasize ? 11 : 8.5,
                fontWeight: emphasize
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: emphasize
                    ? PdfColors.black
                    : PdfColors.grey700,
              ),
            ),
          ),

          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize:
              emphasize ? 11 : 9,
              fontWeight:
              pw.FontWeight.bold,
              color: emphasize
                  ? PdfColors.green900
                  : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TABLE CELL
  // ==========================================================================

  pw.Widget _tableCell(
      String text,
      pw.TextStyle style, {
        pw.TextAlign align =
            pw.TextAlign.left,
      }) {
    return pw.Padding(
      padding:
      const pw.EdgeInsets.symmetric(
        vertical: 5,
        horizontal: 5,
      ),
      child: pw.Text(
        text,
        style: style,
        textAlign: align,
      ),
    );
  }

  // ==========================================================================
  // TERMS & CONDITIONS
  // ==========================================================================

  pw.Widget _buildTermsGrid(
      BillSettings b,
      ) {
    final sections = b.termsSections
        .where(
          (s) => s.enabled,
    )
        .toList();

    final widgets = <pw.Widget>[];

    for (int i = 0;
    i < sections.length;
    i++) {
      widgets.add(
        _termCard(
          i + 1,
          sections[i].title,
          sections[i].text,
        ),
      );
    }

    if (b.otherTermsEnabled &&
        b.otherTermsText
            .trim()
            .isNotEmpty) {
      widgets.add(
        _termCard(
          sections.length + 1,
          b.otherTermsTitle
              .trim()
              .isNotEmpty
              ? b.otherTermsTitle
              : 'Other',
          b.otherTermsText,
        ),
      );
    }

    if (widgets.isEmpty) {
      return pw.Text(
        'No terms and conditions configured.',
        style:
        const pw.TextStyle(
          fontSize: 8,
          color:
          PdfColors.grey600,
        ),
      );
    }

    final rows = <pw.Widget>[];

    for (int i = 0;
    i < widgets.length;
    i += 2) {
      rows.add(
        pw.Padding(
          padding:
          const pw.EdgeInsets.only(
            bottom: 7,
          ),
          child: pw.Row(
            crossAxisAlignment:
            pw.CrossAxisAlignment
                .start,
            children: [
              pw.Expanded(
                child: widgets[i],
              ),

              pw.SizedBox(width: 8),

              pw.Expanded(
                child: i + 1 <
                    widgets.length
                    ? widgets[i + 1]
                    : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      children: rows,
    );
  }

  pw.Widget _termCard(
      int number,
      String title,
      String text,
      ) {
    return pw.Container(
      height: 82,
      padding:
      const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.7,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 19,
            height: 19,
            alignment:
            pw.Alignment.center,
            decoration:
            const pw.BoxDecoration(
              color: PdfColors.green700,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              '$number',
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight:
                pw.FontWeight.bold,
                color:
                PdfColors.white,
              ),
            ),
          ),

          pw.SizedBox(width: 6),

          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment
                  .start,
              children: [
                pw.Text(
                  title,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight:
                    pw.FontWeight.bold,
                    color:
                    PdfColors.green900,
                  ),
                ),

                pw.SizedBox(height: 4),

                pw.Text(
                  text,
                  style:
                  const pw.TextStyle(
                    fontSize: 6.8,
                    color:
                    PdfColors.grey700,
                    lineSpacing: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // IMPORTANT NOTES
  // ==========================================================================

  pw.Widget _buildImportantNotes(
      BillSettings b,
      ) {
    final notes = b.importantNotes
        .where(
          (n) => n.enabled,
    )
        .toList();

    return pw.Container(
      width: double.infinity,
      padding:
      const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'IMPORTANT NOTES',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight:
              pw.FontWeight.bold,
              color:
              PdfColors.green900,
            ),
          ),

          pw.SizedBox(height: 5),

          for (final note in notes)
            _bullet(
              '${note.title}: ${note.text}',
            ),

          if (b.otherNoteEnabled &&
              b.otherNoteText
                  .trim()
                  .isNotEmpty)
            _bullet(
              b.otherNoteText,
            ),
        ],
      ),
    );
  }

  pw.Widget _bullet(
      String text,
      ) {
    return pw.Padding(
      padding:
      const pw.EdgeInsets.only(
        bottom: 3,
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '\u2022',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight:
              pw.FontWeight.bold,
              color:
              PdfColors.green700,
            ),
          ),

          pw.SizedBox(width: 5),

          pw.Expanded(
            child: pw.Text(
              text,
              style:
              const pw.TextStyle(
                fontSize: 6.8,
                color:
                PdfColors.grey700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CLOSING BANNER
  // ==========================================================================

  pw.Widget _buildClosingBanner(
      BillSettings b,
      ) {
    final text = b.footerNote
        .trim()
        .isNotEmpty
        ? b.footerNote
        : 'We care for your goats as our own.';

    return pw.Container(
      width: double.infinity,
      padding:
      const pw.EdgeInsets.symmetric(
        vertical: 9,
        horizontal: 10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green900,
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
      ),
      child: pw.Text(
        text,
        textAlign:
        pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight:
          pw.FontWeight.bold,
          color:
          PdfColors.white,
        ),
      ),
    );
  }

  // ==========================================================================
  // FOOTER
  // ==========================================================================

  pw.Widget _buildFooter({
    required BillSettings billSettings,
    required int pageNumber,
    required int totalPages,
  }) {
    return pw.Container(
      width: double.infinity,
      padding:
      const pw.EdgeInsets.only(
        top: 5,
      ),
      decoration:
      const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey300,
            width: 0.5,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            billSettings.businessName,
            style:
            const pw.TextStyle(
              fontSize: 6,
              color:
              PdfColors.grey600,
            ),
          ),

          pw.Spacer(),

          pw.Text(
            'Page $pageNumber of $totalPages',
            style:
            const pw.TextStyle(
              fontSize: 6,
              color:
              PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // FORMAT HELPERS
  // ==========================================================================

  String _currency(
      double value,
      ) {
    final formatter = NumberFormat(
      '#,##0.00',
      'en_IN',
    );

    return '\u20b9${formatter.format(value)}';
  }

  String _formatDate(
      DateTime date,
      ) {
    return DateFormat(
      'dd MMM yyyy',
    ).format(date);
  }

  String _formatMonthYear(
      DateTime date,
      ) {
    return DateFormat(
      'MMM yyyy',
    ).format(date);
  }

  String _safeFileName(
      PalaiCustomer customer,
      ) {
    final raw =
        'FinalCheckout_${customer.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}';

    final cleaned = raw
        .replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    )
        .replaceAll(
      RegExp(r'\s+'),
      '_',
    );

    return '$cleaned.pdf';
  }
}