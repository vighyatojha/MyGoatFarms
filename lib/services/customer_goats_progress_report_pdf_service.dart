import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/monthly_bill_model.dart';
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
    MonthlyBill? monthlyBill,
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
          if (monthlyBill != null) ...[
            _buildBillingSummary(monthlyBill, entries),
            pw.SizedBox(height: 14),
          ],
          pw.NewPage(),
          _buildContactBar(billSettings),
          pw.SizedBox(height: 16),
          _buildTermsAndConditions(),
          pw.SizedBox(height: 14),
          _buildImportantNotesAndSignature(),
          pw.SizedBox(height: 16),
          _buildClosingBanner(billSettings),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> preview({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    MonthlyBill? monthlyBill,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, billSettings: billSettings, monthlyBill: monthlyBill);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _safeFileName(customer));
  }

  Future<void> share({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    MonthlyBill? monthlyBill,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, billSettings: billSettings, monthlyBill: monthlyBill);
    await Printing.sharePdf(bytes: bytes, filename: _safeFileName(customer));
  }

  Future<String> save({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    MonthlyBill? monthlyBill,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, billSettings: billSettings, monthlyBill: monthlyBill);
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
          child: _arrowIcon(),
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

  /// A small filled right-pointing arrow, drawn as a vector path instead
  /// of a unicode character (e.g. '\u2192'). Some embedded font subsets
  /// don't include arrow glyphs, which renders as a broken "tofu" box —
  /// drawing it ourselves avoids that entirely, on every device/printer.
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
  // BILLING SUMMARY  (previous outstanding + this month's Palai bill)
  // ===========================================================================

  pw.Widget _buildBillingSummary(MonthlyBill bill, List<GoatProgressEntry> entries) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'BILLING SUMMARY — ${bill.monthYear}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: bill.isPaid ? PdfColors.green100 : (bill.isPartiallyPaid ? PdfColors.orange100 : PdfColors.red100),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  bill.statusLabel,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: bill.isPaid ? PdfColors.green900 : (bill.isPartiallyPaid ? PdfColors.orange900 : PdfColors.red900),
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.grey300, height: 1),
          pw.SizedBox(height: 8),

          // Goat-wise Palai amounts — pulled from the bill's OWN saved
          // snapshot (bill.goatBreakdown), i.e. exactly what was typed
          // for each goat that month. Falls back to each goat's
          // registered price only for older bills saved before this
          // breakdown existed.
          if (bill.goatBreakdown.isNotEmpty) ...[
            pw.Text(
              'Current Month Palai (goat-wise)',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 3),
            for (final line in bill.goatBreakdown)
              _billRow(line.label, _currency(line.palaiAmount), small: true),
            pw.SizedBox(height: 3),
            pw.Divider(color: PdfColors.grey300, height: 1),
            pw.SizedBox(height: 6),
          ] else if (entries.isNotEmpty) ...[
            pw.Text(
              'Current Month Palai (goat-wise)',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 3),
            for (final entry in entries)
              _billRow(
                entry.goat.name.trim().isNotEmpty
                    ? entry.goat.name
                    : (entry.goat.goatCode.trim().isNotEmpty ? entry.goat.goatCode : entry.goat.tagNumber),
                _currency(entry.goat.pricing),
                small: true,
              ),
            pw.SizedBox(height: 3),
            pw.Divider(color: PdfColors.grey300, height: 1),
            pw.SizedBox(height: 6),
          ],

          // Three separate, current-state numbers — never reconstructed
          // from old bills or payment history:
          //   Current Month Palai + Current Outstanding − Current Advance
          //   = Current Amount Due
          _billRow('Current Month Palai', _currency(bill.palaiCharges)),
          _billRow('Current Outstanding', _currency(bill.previousOutstanding)),
          if (bill.advanceApplied > 0)
            _billRow('Current Advance', '- ${_currency(bill.advanceApplied)}'),
          pw.SizedBox(height: 3),
          pw.Divider(color: PdfColors.grey300, height: 1),
          pw.SizedBox(height: 3),
          _billRow('Current Amount Due', _currency(bill.totalDue), emphasize: true),
          pw.SizedBox(height: 3),
          pw.Text(
            'Current Month Calculation Only — previous monthly payments and historical transactions are not included above.',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Bill No: ${bill.billNumber}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _billRow(String label, String value, {bool emphasize = false, bool small = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: emphasize ? 9.5 : (small ? 8 : 8.5),
              fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: emphasize ? PdfColors.black : PdfColors.grey700,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasize ? 10.5 : (small ? 8.5 : 9),
              fontWeight: small ? pw.FontWeight.normal : pw.FontWeight.bold,
              color: emphasize ? PdfColors.green900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CONTACT BAR  (dynamic — pulled from this farm's BillSettings, not
  // hardcoded, so every farm's report shows its own details)
  // ===========================================================================

  pw.Widget _buildContactBar(BillSettings b) {
    final items = <pw.Widget>[];

    if (b.phone.trim().isNotEmpty) {
      items.add(_contactItem('For any queries, contact us anytime.'));
      items.add(_contactItem(b.phone));
    }
    if (b.address.trim().isNotEmpty) {
      items.add(_contactItem(b.address));
    }

    if (items.isEmpty) return pw.SizedBox();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Wrap(
        alignment: pw.WrapAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) pw.Text('|', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey400)),
            items[i],
          ],
        ],
      ),
    );
  }

  pw.Widget _contactItem(String text) {
    return pw.Text(text, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800));
  }

  // ===========================================================================
  // TERMS & CONDITIONS
  // ===========================================================================

  static const List<List<String>> _terms = [
    [
      'Animal Care',
      'We provide the best care, feeding and shelter for your goats. However, the owner is advised to inform any special instructions or medical conditions in advance.',
    ],
    [
      'Health & Vaccination',
      'Regular vaccination, deworming and health checkups are done as per the schedule. Any extra medicines or treatment will be charged separately.',
    ],
    [
      'Payment Terms',
      'Payment should be cleared on or before the next billing date. A late fee may be applicable on overdue amounts.',
    ],
    [
      'Liability',
      'We are not responsible for any loss or injury due to natural calamities, disease outbreaks or any unforeseen events beyond our control.',
    ],
    [
      'Ownership',
      'The goat(s) will always remain the property of the owner. We do not claim any ownership.',
    ],
    [
      'Notice',
      'Please inform us before taking your goat(s) out from the farm. A minimum notice period is required.',
    ],
  ];

  pw.Widget _buildTermsAndConditions() {
    final left = <pw.Widget>[];
    final right = <pw.Widget>[];
    for (int i = 0; i < _terms.length; i++) {
      final widget = _termItem(i + 1, _terms[i][0], _terms[i][1]);
      if (i % 2 == 0) {
        left.add(widget);
      } else {
        right.add(widget);
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('TERMS & CONDITIONS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey300, height: 1),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: left)),
            pw.SizedBox(width: 16),
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: right)),
          ],
        ),
      ],
    );
  }

  pw.Widget _termItem(int number, String title, String body) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 15,
            height: 15,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
            child: pw.Text('$number', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(body, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // IMPORTANT NOTES + SIGNATURE
  // ===========================================================================

  pw.Widget _buildImportantNotesAndSignature() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('IMPORTANT NOTES', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              pw.SizedBox(height: 6),
              _bullet('Please check all details in this report and inform us if any correction is required.'),
              _bullet('Keep this report for your records.'),
              _bullet('All goats are under our care and supervision.'),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(height: 26),
              pw.Container(width: 140, height: 1, color: PdfColors.grey500),
              pw.SizedBox(height: 4),
              pw.Text('Farm Owner Signature', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('\u2022  ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
        ],
      ),
    );
  }

  // ===========================================================================
  // CLOSING BANNER  (dynamic — uses this farm's own footer note/name)
  // ===========================================================================

  pw.Widget _buildClosingBanner(BillSettings b) {
    final message = b.footerNote.trim().isNotEmpty
        ? b.footerNote
        : 'We care for your goats as our own.';
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(color: PdfColors.green900, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Text(
        message,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        textAlign: pw.TextAlign.center,
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