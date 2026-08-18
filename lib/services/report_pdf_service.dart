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
/// goat details, a weight trend, the latest health update, and any
/// photos captured specifically for this report — then either shares it
/// (WhatsApp / email / etc. via the OS share sheet) or saves it to the
/// device.
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
    final images = report.images.map((img) => pw.MemoryImage(img.bytes)).toList();
    final latest = historyAscending.isEmpty ? null : historyAscending.last;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _header(billSettings),
          pw.SizedBox(height: 14),
          _titleBar(report),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _customerBlock(customer)),
              pw.SizedBox(width: 18),
              pw.Expanded(child: _goatBlock(goat, report)),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Weight & Growth', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 8),
          if (historyAscending.isEmpty)
            pw.Text(
              'No weight/health records were logged during this period.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
          else ...[
            _weightChart(historyAscending),
            pw.SizedBox(height: 10),
            _weightTable(historyAscending),
          ],
          pw.SizedBox(height: 18),
          pw.Text('Health Update', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 8),
          _healthBlock(goat, latest),
          if (images.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('Report Photos', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: images
                  .map((img) => pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(img, width: 130, height: 130, fit: pw.BoxFit.cover),
              ))
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 26),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          if (billSettings.footerNote.trim().isNotEmpty)
            pw.Text(billSettings.footerNote, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ],
      ),
    );

    return doc.save();
  }

  // -----------------------------------------------------------------
  // Sections
  // -----------------------------------------------------------------

  pw.Widget _header(BillSettings b) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(b.businessName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        if (b.tagline.trim().isNotEmpty)
          pw.Text(b.tagline, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        if (b.address.trim().isNotEmpty)
          pw.Text(b.address, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        if (b.phone.trim().isNotEmpty)
          pw.Text('Phone: ${b.phone}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ],
    );
  }

  pw.Widget _titleBar(GoatReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
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
        pw.SizedBox(height: 5),
        _pdfRow('Name', c.name),
        _pdfRow('Mobile', c.mobileNumber),
        if (c.address.trim().isNotEmpty) _pdfRow('Address', c.address),
        if (c.package.trim().isNotEmpty) _pdfRow('Package', c.package),
      ],
    );
  }

  pw.Widget _goatBlock(PalaiGoat goat, GoatReport report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('GOAT DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
        pw.SizedBox(height: 5),
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
          pw.SizedBox(width: 70, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value.isEmpty ? '—' : value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        ],
      ),
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