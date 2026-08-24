import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/palai_models.dart';

/// One goat's worth of data needed to render its card in the Progress
/// Report — assembled by CustomerGoatsProgressReportScreen before the
/// PDF is built, so this service stays pure/synchronous (no Firestore
/// or camera calls in here).
class GoatProgressEntry {
  final PalaiGoat goat;

  /// The "before" photo shown on the left side of the card: either the
  /// goat's check-in photo (first-ever report) or the photo saved with
  /// the goat's previous report.
  final Uint8List previousImageBytes;
  final String previousLabel;
  final DateTime previousDate;
  final double? previousWeight;

  /// The photo captured just now, while generating this report.
  final Uint8List currentImageBytes;
  final DateTime currentDate;
  final double? currentWeight;

  final HealthRecordEntry? latestHealthRecord;

  const GoatProgressEntry({
    required this.goat,
    required this.previousImageBytes,
    required this.previousLabel,
    required this.previousDate,
    required this.previousWeight,
    required this.currentImageBytes,
    required this.currentDate,
    required this.currentWeight,
    required this.latestHealthRecord,
  });
}

/// Builds the consolidated, multi-goat Progress Report PDF — one numbered
/// card per goat, each showing the goat's identity, its previous photo
/// next to the photo captured for this report, a Weight & Gain box, and
/// a Health Update box. Modeled directly on the reference "Monthly
/// Report" layout the owner already uses outside the app.
///
/// Unlike [CustomerGoatsReportPdfService] (a flat summary table), this
/// service is meant for the richer, per-goat visual report — used by
/// CustomerGoatsProgressReportScreen.
class CustomerGoatsProgressReportPdfService {
  CustomerGoatsProgressReportPdfService._();

  static final CustomerGoatsProgressReportPdfService instance =
  CustomerGoatsProgressReportPdfService._();

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  Future<Uint8List> generatePdf({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
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
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 26),
        header: (context) => context.pageNumber == 1 ? _buildHeader(billSettings, customer, entries.length) : pw.SizedBox(),
        footer: (context) => _buildPageFooter(context),
        build: (context) => [
          for (int i = 0; i < entries.length; i++) ...[
            _buildGoatCard(i + 1, entries[i]),
            pw.SizedBox(height: 14),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> preview({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, billSettings: billSettings);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _safeFileName(customer));
  }

  Future<void> share({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, billSettings: billSettings);
    await Printing.sharePdf(bytes: bytes, filename: _safeFileName(customer));
  }

  Future<String> save({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, billSettings: billSettings);
    final directory = await getApplicationDocumentsDirectory();
    final fileName = _safeFileName(customer);
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ===========================================================================
  // HEADER / FOOTER
  // ===========================================================================

  pw.Widget _buildHeader(BillSettings b, PalaiCustomer customer, int goatCount) {
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
              pw.Text('PROGRESS REPORT', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
              pw.SizedBox(height: 3),
              pw.Text(customer.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                '$goatCount goat${goatCount == 1 ? '' : 's'} \u2022 ${_formatDate(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
              ),
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
          pw.Text('Progress Report', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Spacer(),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  // ===========================================================================
  // GOAT CARD  (mirrors the reference "Monthly Report" layout)
  // ===========================================================================

  pw.Widget _buildGoatCard(int number, GoatProgressEntry entry) {
    final goat = entry.goat;
    final gain = (entry.previousWeight != null && entry.currentWeight != null) ? entry.currentWeight! - entry.previousWeight! : null;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _cardTitle(number, goat),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 24, child: _identityColumn(goat)),
              pw.SizedBox(width: 8),
              pw.Expanded(flex: 34, child: _photosColumn(entry)),
              pw.SizedBox(width: 8),
              pw.Expanded(flex: 32, child: _statsColumn(entry, gain)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _cardTitle(int number, PalaiGoat goat) {
    final code = goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber;
    final extra = goat.name.trim().isNotEmpty ? goat.name : goat.breed;
    return pw.Row(
      children: [
        pw.Container(
          width: 20,
          height: 20,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
          child: pw.Text('$number', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          extra.isNotEmpty ? '$code ($extra)' : code,
          style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _identityColumn(PalaiGoat goat) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _idRow('Breed', goat.breed.trim().isNotEmpty ? goat.breed : '-'),
        _idRow('Gender', goat.gender.trim().isNotEmpty ? goat.gender : '-'),
        _idRow('Color', goat.color.trim().isNotEmpty ? goat.color : '-'),
        _idRow('Date of Join', _formatDate(goat.checkInDate)),
        _idRow('Age', _ageLabel(goat.dateOfBirth)),
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

  pw.Widget _photosColumn(GoatProgressEntry entry) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: _photoBlock(
            title: 'PREVIOUS (${_formatMonthYear(entry.previousDate)})',
            caption: entry.previousLabel,
            bytes: entry.previousImageBytes,
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Text('\u2192', style: pw.TextStyle(fontSize: 16, color: PdfColors.green700, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Expanded(
          child: _photoBlock(
            title: 'CURRENT (${_formatMonthYear(entry.currentDate)})',
            caption: 'Report Day Photo',
            bytes: entry.currentImageBytes,
          ),
        ),
      ],
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
              ? pw.Image(pw.MemoryImage(bytes), width: 78, height: 78, fit: pw.BoxFit.cover)
              : pw.Container(
            width: 78,
            height: 78,
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

  pw.Widget _statsColumn(GoatProgressEntry entry, double? gain) {
    final record = entry.latestHealthRecord;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _statBox(
          title: 'WEIGHT & GAIN',
          rows: [
            _idRowPair('Previous Weight', entry.previousWeight != null ? '${entry.previousWeight!.toStringAsFixed(1)} kg' : '-'),
            _idRowPair('Current Weight', entry.currentWeight != null ? '${entry.currentWeight!.toStringAsFixed(1)} kg' : '-'),
            _idRowPair(
              'Gain',
              gain != null ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : '-',
              valueColor: gain == null ? PdfColors.grey800 : (gain >= 0 ? PdfColors.green700 : PdfColors.red700),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        _statBox(
          title: 'HEALTH UPDATE',
          rows: [
            _idRowPair('Health Status', record?.healthStatus.trim().isNotEmpty == true ? record!.healthStatus : entry.goat.healthStatus),
            _idRowPair('Vaccination', record?.vaccination.trim().isNotEmpty == true ? record!.vaccination : '-'),
            _idRowPair('Deworming', record?.deworming.trim().isNotEmpty == true ? record!.deworming : '-'),
            _idRowPair('Hoof Cutting', record?.hoofCutting.trim().isNotEmpty == true ? record!.hoofCutting : '-'),
            _idRowPair('Medicine Given', record?.medicineGiven.trim().isNotEmpty == true ? record!.medicineGiven : 'None'),
            _idRowPair('Notes', record?.doctorNotes.trim().isNotEmpty == true ? record!.doctorNotes : '-'),
          ],
        ),
      ],
    );
  }

  pw.Widget _statBox({required String title, required List<pw.Widget> rows}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _idRowPair(String label, String value, {PdfColor valueColor = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 5, child: pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700))),
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              value.isEmpty ? '-' : value,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: valueColor),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FORMATTERS
  // ===========================================================================

  String _currency(double value) {
    final formatter = NumberFormat('#,##0.00', 'en_IN');
    return '\u20b9${formatter.format(value)}';
  }

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  String _formatMonthYear(DateTime date) => DateFormat('MMM yyyy').format(date);

  String _ageLabel(DateTime? dateOfBirth) {
    if (dateOfBirth == null) return '-';
    final now = DateTime.now();
    int months = (now.year - dateOfBirth.year) * 12 + (now.month - dateOfBirth.month);
    if (now.day < dateOfBirth.day) months -= 1;
    if (months < 0) months = 0;
    final years = months ~/ 12;
    final remMonths = months % 12;
    if (years <= 0) return '$remMonths Month${remMonths == 1 ? '' : 's'}';
    if (remMonths == 0) return '$years Year${years == 1 ? '' : 's'}';
    return '$years Year${years == 1 ? '' : 's'} $remMonths Month${remMonths == 1 ? '' : 's'}';
  }

  String _safeFileName(PalaiCustomer customer) {
    final raw = 'ProgressReport_${customer.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_');
    return '$cleaned.pdf';
  }
}