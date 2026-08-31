import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/palai_models.dart';

/// One month's Palai charge for a single goat, pulled from that month's
/// MonthlyBill.goatBreakdown — used to build the "Payment (this period)"
/// section without recomputing billing math, just reading what was
/// already billed.
class GoatMonthlyPalaiLine {
  final DateTime month;
  final double amount;
  const GoatMonthlyPalaiLine({required this.month, required this.amount});
}

/// Everything needed to render an individual goat's date-range report —
/// assembled by GoatReportGenerateScreen before the PDF is built, so
/// this service stays pure/synchronous (no Firestore/camera calls here),
/// the same separation used by CustomerGoatsProgressReportPdfService.
class IndividualGoatReportData {
  final PalaiGoat goat;
  final String customerName;

  /// Human label for the period covered — "Whole Period (Arrival to
  /// Today)", "August 2026", or "12 Jun 2026 – 30 Aug 2026".
  final String rangeLabel;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  final double? startWeight;
  final DateTime startDate;
  final Uint8List startPhotoBytes;
  final String startPhotoLabel;

  final double? endWeight;
  final DateTime endDate;
  final Uint8List endPhotoBytes;
  final String endPhotoLabel;

  /// Every health record recorded inside the range, most recent first —
  /// used for both the health summary counts and the "latest" status.
  final List<HealthRecordEntry> healthRecordsInRange;

  /// This goat's own Palai line from each MonthlyBill whose billing
  /// month falls inside the range.
  final List<GoatMonthlyPalaiLine> monthlyPalaiLines;

  /// Customer-level current outstanding/advance, shown separately and
  /// clearly labelled as shared across every goat this customer has —
  /// NOT specific to this one goat, since Palai billing tracks
  /// outstanding/advance per customer, not per goat.
  final double currentOutstanding;
  final double currentAdvance;

  const IndividualGoatReportData({
    required this.goat,
    required this.customerName,
    required this.rangeLabel,
    required this.rangeStart,
    required this.rangeEnd,
    required this.startWeight,
    required this.startDate,
    required this.startPhotoBytes,
    required this.startPhotoLabel,
    required this.endWeight,
    required this.endDate,
    required this.endPhotoBytes,
    required this.endPhotoLabel,
    required this.healthRecordsInRange,
    required this.monthlyPalaiLines,
    required this.currentOutstanding,
    required this.currentAdvance,
  });

  double get totalPalaiInPeriod =>
      monthlyPalaiLines.fold<double>(0, (sum, l) => sum + l.amount);

  double? get gain => (startWeight != null && endWeight != null) ? endWeight! - startWeight! : null;

  HealthRecordEntry? get latestHealthRecord =>
      healthRecordsInRange.isNotEmpty ? healthRecordsInRange.first : null;
}

/// Builds an individual goat's report PDF for a chosen date range —
/// the whole period since arrival, one calendar month, or a custom
/// range. Layout is directly adapted from
/// CustomerGoatsProgressReportPdfService's goat card (identity /
/// photos / weight & gain / health), plus a Growth Timeline (every
/// weighing inside the range) and a Payment section scoped to this
/// one goat's own Palai lines.
class IndividualGoatReportPdfService {
  IndividualGoatReportPdfService._();
  static final IndividualGoatReportPdfService instance = IndividualGoatReportPdfService._();

  Future<Uint8List> generatePdf({
    required IndividualGoatReportData data,
    required BillSettings billSettings,
  }) async {
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 30),
        header: (context) => _buildHeader(billSettings, data),
        footer: (context) => _buildPageFooter(context),
        build: (context) => [
          _buildGoatCard(data),
          pw.SizedBox(height: 14),
          _buildGrowthTimeline(data),
          pw.SizedBox(height: 14),
          _buildHealthSummary(data),
          pw.SizedBox(height: 14),
          _buildPaymentSection(data),
          pw.SizedBox(height: 20),
          _buildThankYou(billSettings),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> preview({required IndividualGoatReportData data, required BillSettings billSettings}) async {
    final bytes = await generatePdf(data: data, billSettings: billSettings);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName(data));
  }

  Future<void> share({required IndividualGoatReportData data, required BillSettings billSettings}) async {
    final bytes = await generatePdf(data: data, billSettings: billSettings);
    await Printing.sharePdf(bytes: bytes, filename: _fileName(data));
  }

  Future<String> save({required IndividualGoatReportData data, required BillSettings billSettings}) async {
    final bytes = await generatePdf(data: data, billSettings: billSettings);
    final directory = await getApplicationDocumentsDirectory();
    final fileName = _fileName(data);
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  String _fileName(IndividualGoatReportData data) {
    final code = data.goat.goatCode.trim().isNotEmpty ? data.goat.goatCode : data.goat.tagNumber;
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'Report_${code}_$stamp.pdf'.replaceAll(' ', '_');
  }

  // ===========================================================================
  // HEADER / FOOTER
  // ===========================================================================

  pw.Widget _buildHeader(BillSettings b, IndividualGoatReportData data) {
    final code = data.goat.goatCode.trim().isNotEmpty ? data.goat.goatCode : data.goat.tagNumber;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 1, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(b.businessName, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
              if (b.address.trim().isNotEmpty)
                pw.Text(b.address, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              if (b.phone.trim().isNotEmpty)
                pw.Text('Phone: ${b.phone}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('GOAT REPORT', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
              pw.SizedBox(height: 3),
              pw.Text('$code \u2022 ${data.customerName}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(data.rangeLabel, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        children: [
          pw.Text('Goat Report', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Spacer(),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  pw.Widget _buildThankYou(BillSettings b) {
    if (b.footerNote.trim().isEmpty) return pw.SizedBox.shrink();
    return pw.Center(
      child: pw.Text(b.footerNote, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
    );
  }

  // ===========================================================================
  // GOAT CARD — identity / photos / weight & gain / health snapshot
  // ===========================================================================

  pw.Widget _buildGoatCard(IndividualGoatReportData data) {
    final goat = data.goat;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            goat.name.trim().isNotEmpty
                ? '${goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber} (${goat.name})'
                : (goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber),
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 24, child: _identityColumn(goat)),
              pw.SizedBox(width: 8),
              pw.Expanded(flex: 34, child: _photosRow(data)),
              pw.SizedBox(width: 8),
              pw.Expanded(flex: 32, child: _weightBox(data)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _identityColumn(PalaiGoat goat) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _idRow('Breed', goat.breed.trim().isNotEmpty ? goat.breed : '-'),
        _idRow('Gender', goat.gender.trim().isNotEmpty ? goat.gender : '-'),
        _idRow('Color', goat.color.trim().isNotEmpty ? goat.color : '-'),
        _idRow('Arrival', _formatDate(goat.farmArrivalDate ?? goat.checkInDate)),
        _idRow('Monthly Rate', _currency(goat.pricing)),
      ],
    );
  }

  pw.Widget _idRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label : ', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.TextSpan(text: value, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  pw.Widget _photosRow(IndividualGoatReportData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: _photoBlock(
            title: _formatDate(data.startDate).toUpperCase(),
            caption: data.startPhotoLabel,
            bytes: data.startPhotoBytes,
          ),
        ),
        pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4), child: _arrowIcon()),
        pw.Expanded(
          child: _photoBlock(
            title: _formatDate(data.endDate).toUpperCase(),
            caption: data.endPhotoLabel,
            bytes: data.endPhotoBytes,
          ),
        ),
      ],
    );
  }

  pw.Widget _arrowIcon() {
    return pw.SizedBox(
      width: 16,
      height: 16,
      child: pw.CustomPaint(
        size: const PdfPoint(16, 16),
        painter: (PdfGraphics canvas, PdfPoint size) {
          final midY = size.y / 2;
          canvas
            ..setColor(PdfColors.green700)
            ..moveTo(1, midY - 3)
            ..lineTo(size.x - 7, midY - 3)
            ..lineTo(size.x - 7, midY - 6)
            ..lineTo(size.x - 1, midY)
            ..lineTo(size.x - 7, midY + 6)
            ..lineTo(size.x - 7, midY + 3)
            ..lineTo(1, midY + 3)
            ..lineTo(1, midY - 3)
            ..fillPath();
        },
      ),
    );
  }

  pw.Widget _photoBlock({required String title, required String caption, required Uint8List bytes}) {
    return pw.Column(
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 3),
        pw.ClipRRect(
          horizontalRadius: 5,
          verticalRadius: 5,
          child: bytes.isNotEmpty
              ? pw.Image(pw.MemoryImage(bytes), width: 92, height: 92, fit: pw.BoxFit.cover)
              : pw.Container(
            width: 92,
            height: 92,
            color: PdfColors.grey200,
            alignment: pw.Alignment.center,
            child: pw.Text('No Photo', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(caption, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
      ],
    );
  }

  pw.Widget _weightBox(IndividualGoatReportData data) {
    final gain = data.gain;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('WEIGHT & GAIN', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.SizedBox(height: 4),
          _statRow('Start Weight', data.startWeight != null ? '${data.startWeight!.toStringAsFixed(1)} kg' : '-'),
          _statRow('End Weight', data.endWeight != null ? '${data.endWeight!.toStringAsFixed(1)} kg' : '-'),
          _statRow(
            'Gain',
            gain != null ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : '-',
            valueColor: gain == null ? PdfColors.grey800 : (gain >= 0 ? PdfColors.green700 : PdfColors.red700),
          ),
        ],
      ),
    );
  }

  pw.Widget _statRow(String label, String value, {PdfColor valueColor = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 5, child: pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700))),
          pw.Expanded(
            flex: 4,
            child: pw.Text(value.isEmpty ? '-' : value, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: valueColor), textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GROWTH TIMELINE — every weighing inside the range
  // ===========================================================================

  pw.Widget _buildGrowthTimeline(IndividualGoatReportData data) {
    // Oldest first for a left-to-right reading timeline.
    final records = data.healthRecordsInRange.reversed.toList();
    if (records.isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('GROWTH TIMELINE', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (int i = 0; i < records.length; i++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                  child: pw.Column(
                    children: [
                      pw.Text(_formatDate(records[i].recordedAt), style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                      pw.Text('${records[i].weight.toStringAsFixed(1)} kg', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      if (i > 0)
                        pw.Text(
                          '${(records[i].weight - records[i - 1].weight) >= 0 ? '+' : ''}${(records[i].weight - records[i - 1].weight).toStringAsFixed(1)} kg',
                          style: pw.TextStyle(
                            fontSize: 6.5,
                            color: (records[i].weight - records[i - 1].weight) >= 0 ? PdfColors.green700 : PdfColors.red700,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEALTH SUMMARY
  // ===========================================================================

  pw.Widget _buildHealthSummary(IndividualGoatReportData data) {
    final records = data.healthRecordsInRange;
    final issues = records.where((r) => r.healthStatus == 'Sick' || r.diseaseOrProblem.trim().isNotEmpty).length;
    final latest = data.latestHealthRecord;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('HEALTH SUMMARY (THIS PERIOD)', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(child: _statRow('Health Checks', '${records.length}')),
              pw.Expanded(child: _statRow('Issues Reported', '$issues')),
            ],
          ),
          _statRow('Latest Status', latest?.healthStatus.isNotEmpty == true ? latest!.healthStatus : data.goat.healthStatus),
          if (latest != null && latest.medicineGiven.trim().isNotEmpty) _statRow('Latest Medicine', latest.medicineGiven),
          if (latest != null && latest.treatment.trim().isNotEmpty) _statRow('Latest Treatment', latest.treatment),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYMENT (this goat's Palai lines for the period + customer-level balance)
  // ===========================================================================

  pw.Widget _buildPaymentSection(IndividualGoatReportData data) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PAYMENT (THIS GOAT, THIS PERIOD)', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 6),
          if (data.monthlyPalaiLines.isEmpty)
            pw.Text('No monthly bills fall inside this period.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))
          else ...[
            for (final line in data.monthlyPalaiLines)
              _statRow(DateFormat('MMMM yyyy').format(line.month), _currency(line.amount)),
            pw.Divider(color: PdfColors.grey300, height: 10),
            _statRow('Total Palai (this goat, period)', _currency(data.totalPalaiInPeriod), valueColor: PdfColors.green900),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            'Outstanding & Advance below are CUSTOMER-LEVEL balances (shared across every goat this customer has), not specific to this one goat.',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 4),
          _statRow('Current Outstanding (customer)', _currency(data.currentOutstanding)),
          _statRow('Current Advance (customer)', _currency(data.currentAdvance)),
        ],
      ),
    );
  }

  // ===========================================================================
  // FORMATTING HELPERS
  // ===========================================================================

  String _formatDate(DateTime date) => DateFormat('d MMM yyyy').format(date);

  String _currency(double value) => NumberFormat.currency(locale: 'en_IN', symbol: '\u20b9', decimalDigits: 2).format(value);
}