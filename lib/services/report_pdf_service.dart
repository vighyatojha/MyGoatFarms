import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/palai_models.dart';
import '../models/report_models.dart';

/// Builds a goat's Generate Report PDF — covering everything recorded
/// from its check-in (registration) date through today: customer &
/// goat details, a weight trend, the latest health update, and photos
/// from three moments in the goat's stay (check-in, most recent health
/// update, and report day) — then either shares it (WhatsApp / email /
/// etc. via the OS share sheet) or saves it to the device.
///
/// Mirrors the structure of [PdfBillService] but for the "Generate
/// Report" flow (Goats in Palai > goat > Generate Report) rather than
/// the Check-Out bill. Only [GoatReportType.progress] is built today —
/// see GenerateReportScreen for why.
class ReportPdfService {
  ReportPdfService._();
  static final ReportPdfService instance = ReportPdfService._();

  Future<Uint8List> buildBytes({
    required PalaiGoat goat,
    required PalaiCustomer customer,
    required GoatReport report,
    required List<HealthRecordEntry> historyAscending,
    required BillSettings billSettings,
  }) async {
    final doc = pw.Document();
    final latest = historyAscending.isEmpty ? null : historyAscending.last;
    final gain = (report.startWeight != null && report.endWeight != null) ? report.endWeight! - report.startWeight! : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            textAlign: pw.TextAlign.right,
          ),
        ),
        build: (context) => [
          _header(billSettings, goat, report),
          pw.SizedBox(height: 16),
          _titleBar(report),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _statCard('Boarded For', _boardedFor(goat.checkInDate)),
              _statCard(
                'Weight Gain',
                gain != null ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : '—',
                valueColor: gain == null ? PdfColors.green900 : (gain >= 0 ? PdfColors.green700 : PdfColors.red700),
              ),
              _statCard('Health Status', latest?.healthStatus.isNotEmpty == true ? latest!.healthStatus : goat.healthStatus),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _card(child: _customerBlock(customer))),
              pw.SizedBox(width: 12),
              pw.Expanded(child: _card(child: _goatBlock(goat))),
            ],
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('Weight & Growth'),
          pw.SizedBox(height: 8),
          _card(
            child: historyAscending.isEmpty
                ? pw.Text(
              'No weight/health records were logged during this period.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
                : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _weightChart(historyAscending),
                pw.SizedBox(height: 10),
                _weightTable(historyAscending),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('Health Update'),
          pw.SizedBox(height: 8),
          _card(child: _healthBlock(goat, latest)),
          if (report.images.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Report Photos'),
            pw.SizedBox(height: 4),
            pw.Text(
              'From check-in, the latest health update, and today\'s report.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: report.images.map(_photoCard).toList(),
            ),
          ],
          pw.SizedBox(height: 22),
          _footer(billSettings),
        ],
      ),
    );

    return doc.save();
  }

  // -----------------------------------------------------------------
  // Sections
  // -----------------------------------------------------------------

  pw.Widget _header(BillSettings b, PalaiGoat goat, GoatReport report) {
    final initial = b.businessName.trim().isNotEmpty ? b.businessName.trim()[0].toUpperCase() : 'F';
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 42,
              height: 42,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(color: PdfColors.green700, borderRadius: pw.BorderRadius.circular(21)),
              child: pw.Text(initial, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
            pw.SizedBox(width: 10),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(b.businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                if (b.tagline.trim().isNotEmpty)
                  pw.Text(b.tagline, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                if (b.address.trim().isNotEmpty)
                  pw.Text(b.address, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                if (b.phone.trim().isNotEmpty)
                  pw.Text('Phone: ${b.phone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(color: PdfColors.green900, borderRadius: pw.BorderRadius.circular(20)),
              child: pw.Text(
                report.type.label.toUpperCase(),
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Report ID: ${_reportId(goat, report)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Generated: ${_fmt(report.generatedAt)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ],
    );
  }

  pw.Widget _titleBar(GoatReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(report.type.label, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.Text(
            '${_fmt(report.fromDate)}  to  ${_fmt(report.toDate)}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
          ),
        ],
      ),
    );
  }

  pw.Widget _customerBlock(PalaiCustomer c) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('CUSTOMER DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
        pw.SizedBox(height: 6),
        _pdfRow('Name', c.name),
        _pdfRow('Mobile', c.mobileNumber),
        if (c.address.trim().isNotEmpty) _pdfRow('Address', c.address),
      ],
    );
  }

  pw.Widget _goatBlock(PalaiGoat goat) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('GOAT DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
        pw.SizedBox(height: 6),
        _pdfRow('Goat ID', goat.goatCode),
        _pdfRow('Breed', goat.breed),
        _pdfRow('Gender', goat.gender),
        _pdfRow('Color', goat.color),
        _pdfRow('Date of Join', _fmt(goat.checkInDate)),
        _pdfRow('Boarded For', _boardedFor(goat.checkInDate)),
        if (goat.monthlyPackage.trim().isNotEmpty) _pdfRow('Monthly Package', goat.monthlyPackage),
      ],
    );
  }

  pw.Widget _healthBlock(PalaiGoat goat, HealthRecordEntry? latest) {
    if (latest == null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfRow('Health Status', goat.healthStatus),
          pw.SizedBox(height: 4),
          pw.Text('No detailed health records logged yet.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfRow('Health Status', latest.healthStatus.isNotEmpty ? latest.healthStatus : goat.healthStatus),
        if (latest.vaccination.trim().isNotEmpty) _pdfRow('Vaccination', latest.vaccination),
        if (latest.deworming.trim().isNotEmpty) _pdfRow('Deworming', latest.deworming),
        if (latest.hoofCutting.trim().isNotEmpty) _pdfRow('Hoof Cutting', latest.hoofCutting),
        if (latest.medicineGiven.trim().isNotEmpty) _pdfRow('Medicine Given', latest.medicineGiven),
        _pdfRow('Last Recorded', _fmt(latest.recordedAt)),
        if (latest.doctorNotes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text('Notes', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
          pw.SizedBox(height: 2),
          pw.Text(latest.doctorNotes, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ],
    );
  }

  /// A simple bar-style weight trend — deliberately built out of plain
  /// Containers rather than a canvas/chart widget so it renders exactly
  /// the same everywhere `pdf` runs.
  pw.Widget _weightChart(List<HealthRecordEntry> historyAscending) {
    final weights = historyAscending.map((e) => e.weight).toList();
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final range = (maxW - minW) <= 0 ? 1.0 : (maxW - minW);
    const chartHeight = 64.0;

    return pw.Container(
      height: chartHeight + 34,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < historyAscending.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('${historyAscending[i].weight.toStringAsFixed(1)}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    height: 10 + ((historyAscending[i].weight - minW) / range) * chartHeight,
                    decoration: pw.BoxDecoration(color: PdfColors.green300, borderRadius: pw.BorderRadius.circular(3)),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(_fmtShort(historyAscending[i].recordedAt), style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _weightTable(List<HealthRecordEntry> historyAscending) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Expanded(flex: 2, child: pw.Text('Date', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700))),
            pw.Expanded(flex: 2, child: pw.Text('Weight', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700))),
            pw.Expanded(flex: 2, child: pw.Text('Change', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700))),
          ],
        ),
        pw.Divider(height: 8, color: PdfColors.grey300),
        for (int i = 0; i < historyAscending.length; i++) _weightRow(historyAscending, i),
      ],
    );
  }

  pw.Widget _weightRow(List<HealthRecordEntry> list, int i) {
    final entry = list[i];
    final change = i == 0 ? null : entry.weight - list[i - 1].weight;
    final changeText = change == null ? '—' : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg';
    final changeColor = change == null ? PdfColors.grey600 : (change >= 0 ? PdfColors.green700 : PdfColors.red700);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 2, child: pw.Text(_fmt(entry.recordedAt), style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(flex: 2, child: pw.Text('${entry.weight.toStringAsFixed(1)} kg', style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(flex: 2, child: pw.Text(changeText, style: pw.TextStyle(fontSize: 9, color: changeColor))),
        ],
      ),
    );
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 78, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value.isEmpty ? '—' : value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        ],
      ),
    );
  }

  /// One photo, boxed, with its label captioned underneath — the same
  /// "what is this photo of" clarity as the Front View / Side View
  /// captions in the Monthly Report style.
  pw.Widget _photoCard(ReportImage img) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
      ),
      child: pw.Column(
        children: [
          pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Image(pw.MemoryImage(img.bytes), width: 138, height: 138, fit: pw.BoxFit.cover),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            img.label.isNotEmpty ? img.label : 'Photo',
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// A white, bordered, rounded box used to group every section — gives
  /// the report a "form" feel instead of loose text floating on the
  /// page, matching the boxed-card look of the Monthly Report reference.
  pw.Widget _card({required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
      ),
      child: child,
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Text(text, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900));
  }

  pw.Widget _statCard(String label, String value, {PdfColor valueColor = PdfColors.green900}) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3),
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Column(
          children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: valueColor), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 3),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
          ],
        ),
      ),
    );
  }

  pw.Widget _footer(BillSettings b) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: pw.BoxDecoration(color: PdfColors.green900, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Column(
            children: [
              pw.Text(
                'Thank you for trusting ${b.businessName.trim().isEmpty ? 'us' : b.businessName}.',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'We care for your goats as our own.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.green100),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
        if (b.footerNote.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(b.footerNote, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
        ],
      ],
    );
  }

  // -----------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _fmtShort(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]}';

  String _boardedFor(DateTime checkInDate) {
    final now = DateTime.now();
    int months = (now.year - checkInDate.year) * 12 + (now.month - checkInDate.month);
    DateTime monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    if (monthsAgo.isAfter(now)) {
      months -= 1;
      monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    }
    final days = now.difference(monthsAgo).inDays;
    if (months <= 0) return '$days day${days == 1 ? '' : 's'}';
    if (days <= 0) return '$months month${months == 1 ? '' : 's'}';
    return '$months mo $days d';
  }

  String _reportId(PalaiGoat goat, GoatReport report) {
    final d = report.generatedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'RPT-${goat.goatCode}-${d.year}${two(d.month)}${two(d.day)}${two(d.hour)}${two(d.minute)}';
  }

  // -----------------------------------------------------------------
  // Share / save the already-built bytes — kept generic so the caller
  // only ever builds the PDF once (see GenerateReportScreen).
  // -----------------------------------------------------------------

  Future<void> shareBytes(Uint8List bytes, String filename) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }

  Future<String> saveBytes(Uint8List bytes, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}