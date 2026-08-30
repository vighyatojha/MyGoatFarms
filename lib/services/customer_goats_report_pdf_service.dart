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

/// Builds ONE consolidated PDF report covering every goat (or every
/// selected goat) under a single Palai customer — as opposed to
/// [ReportPdfService], which builds a detailed report for one goat at
/// a time. Used by "Generate Goats Report" on the Customer Profile
/// screen so the owner can hand a customer a single document listing
/// all their goats at once, instead of generating one PDF per goat.
class CustomerGoatsReportPdfService {
  CustomerGoatsReportPdfService._();

  static final CustomerGoatsReportPdfService instance =
  CustomerGoatsReportPdfService._();

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  Future<Uint8List> generatePdf({
    required PalaiCustomer customer,
    required List<PalaiGoat> goats,
    required BillSettings billSettings,
    MonthlyBill? bill,
  }) async {
    // -------------------------------------------------------------------
    // Unicode font (so ₹ renders correctly instead of a broken glyph —
    // same fix applied to MonthlyBillPdfService).
    // -------------------------------------------------------------------

    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 30),

        header: (context) => _buildHeader(billSettings),
        footer: (context) => _buildPageFooter(context),

        build: (context) => [
          _buildTitle(goats.length),
          pw.SizedBox(height: 16),
          _buildCustomerInfo(customer),
          pw.SizedBox(height: 18),
          _buildGoatsTable(goats),
          pw.SizedBox(height: 18),
          _buildSummary(goats),
          if (bill != null) ...[
            pw.SizedBox(height: 18),
            _buildBillingSummary(bill, goats),
          ],
          pw.SizedBox(height: 22),
          _buildThankYou(billSettings),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> preview({
    required PalaiCustomer customer,
    required List<PalaiGoat> goats,
    required BillSettings billSettings,
    MonthlyBill? bill,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      goats: goats,
      billSettings: billSettings,
      bill: bill,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _safeFileName(customer),
    );
  }

  Future<void> share({
    required PalaiCustomer customer,
    required List<PalaiGoat> goats,
    required BillSettings billSettings,
    MonthlyBill? bill,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      goats: goats,
      billSettings: billSettings,
      bill: bill,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _safeFileName(customer),
    );
  }

  Future<String> save({
    required PalaiCustomer customer,
    required List<PalaiGoat> goats,
    required BillSettings billSettings,
    MonthlyBill? bill,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      goats: goats,
      billSettings: billSettings,
      bill: bill,
    );

    final directory = await getApplicationDocumentsDirectory();
    final fileName = _safeFileName(customer);
    final file = File('${directory.path}/$fileName');

    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  pw.Widget _buildHeader(BillSettings b) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 1, color: PdfColors.grey400),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            b.businessName,
            style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          if (b.address.trim().isNotEmpty)
            pw.Text(
              b.address,
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
            ),
          if (b.phone.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Phone: ${b.phone}',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // TITLE
  // ===========================================================================

  pw.Widget _buildTitle(int goatCount) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 11, horizontal: 14),
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(color: PdfColors.grey500),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'GOATS REPORT',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '$goatCount goat${goatCount == 1 ? '' : 's'} • Generated ${_formatDate(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CUSTOMER INFO
  // ===========================================================================

  pw.Widget _buildCustomerInfo(PalaiCustomer customer) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CUSTOMER',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  customer.name,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                if (customer.mobileNumber.trim().isNotEmpty)
                  pw.Text(
                    customer.mobileNumber,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'JOINED',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _formatDate(customer.joiningDate),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GOATS TABLE
  // ===========================================================================

  pw.Widget _buildGoatsTable(List<PalaiGoat> goats) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'GOAT DETAILS',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.6),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.6),
            4: const pw.FlexColumnWidth(1.2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _tableHeader('GOAT'),
                _tableHeader('BREED'),
                _tableHeader('WEIGHT'),
                _tableHeader('HEALTH'),
                _tableHeader('CHECK-IN', alignRight: true),
              ],
            ),
            ...goats.map(
                  (goat) => pw.TableRow(
                children: [
                  _tableCell(goat.name.trim().isNotEmpty ? goat.name : goat.tagNumber),
                  _tableCell(goat.breed.trim().isNotEmpty ? goat.breed : '-'),
                  _tableCell(_weightLabel(goat)),
                  _tableCell(goat.healthStatus.trim().isNotEmpty ? goat.healthStatus : '-'),
                  _tableCell(_formatDate(goat.checkInDate), alignRight: true),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _weightLabel(PalaiGoat goat) {
    final current = goat.currentWeight;
    if (current == null) {
      return '${goat.weightAtCheckIn.toStringAsFixed(1)} kg';
    }
    return '${goat.weightAtCheckIn.toStringAsFixed(1)} → ${current.toStringAsFixed(1)} kg';
  }

  pw.Widget _tableHeader(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _tableCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 8.5),
      ),
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  pw.Widget _buildSummary(List<PalaiGoat> goats) {
    final totalPricing = goats.fold<double>(0, (sum, g) => sum + g.pricing);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Total Goats: ${goats.length}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Total Monthly Pricing: ${_currency(totalPricing)}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BILLING SUMMARY (only rendered when a MonthlyBill is passed in)
  // ===========================================================================

  pw.Widget _buildBillingSummary(MonthlyBill bill, List<PalaiGoat> goats) {
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
                  color: bill.isPaid
                      ? PdfColors.green100
                      : (bill.isPartiallyPaid ? PdfColors.orange100 : PdfColors.red100),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  bill.statusLabel,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: bill.isPaid
                        ? PdfColors.green900
                        : (bill.isPartiallyPaid ? PdfColors.orange900 : PdfColors.red900),
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
          ] else if (goats.isNotEmpty) ...[
            pw.Text(
              'Current Month Palai (goat-wise)',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 3),
            for (final goat in goats)
              _billRow(
                goat.name.trim().isNotEmpty
                    ? goat.name
                    : (goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber),
                _currency(goat.pricing),
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
  // THANK YOU / PAGE FOOTER
  // ===========================================================================

  pw.Widget _buildThankYou(BillSettings b) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'THANK YOU',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            b.footerNote,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
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
          pw.Text(
            'Goats Report',
            style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Spacer(),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
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
    return '₹${formatter.format(value)}';
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _safeFileName(PalaiCustomer customer) {
    final raw = 'GoatsReport_${customer.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '$cleaned.pdf';
  }
}