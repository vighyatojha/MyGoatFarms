import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/goat_history_models.dart';
import '../models/palai_models.dart';

/// PDF generator for Palai monthly reports and the single-goat check-out
/// bill.
///
/// The supplied Monthly Report.pdf is used as the visual reference:
/// header -> customer/summary cards -> goat details -> previous/current
/// photos -> weight/gain -> health update -> billing -> payment details ->
/// thank-you -> terms -> important notes/signature.
///
/// NOTE: the combined Final Checkout Report PDF is now built by
/// [FinalCheckoutReportPdfService] (see final_checkout_report_pdf_service.dart),
/// not this service. `FinalCheckoutReportData`/`FinalGoatReportData`/
/// `MonthlyGoatReportData` used to live at the bottom of this file but
/// have moved to `lib/models/final_checkout_report_model.dart` — their
/// only remaining consumer is the on-screen review UI in
/// final_checkout_report_screen.dart, and `MonthlyGoatReportData` is
/// also produced by MonthlyReportService — they were never PDF-only
/// types, so this was never the right file for them to live in.
class PdfBillService {
  PdfBillService._();
  static final PdfBillService instance = PdfBillService._();

  // ---------------------------------------------------------------------------
  // EXISTING MONTHLY BILL API - kept compatible with the current Billing UI.
  // ---------------------------------------------------------------------------

  Future<Uint8List> _buildMonthlyBill({
    required String customerName,
    required String billNumber,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required double advanceBefore,
    required double advanceApplied,
    required double advanceAfter,
    required String paymentMethod,
    required BillSettings billSettings,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => _header(
          billSettings,
          'MONTHLY REPORT',
          right: 'Bill: $billNumber',
          period: _monthYear(now),
        ),
        footer: (c) => _footer(billSettings, c.pageNumber, c.pagesCount),
        build: (_) => [
          _customerCard(customerName, billNumber, now, paymentMethod),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _card('BILL SUMMARY', [
                  ['Previous Balance', _rs(previousBalance)],
                  ['Monthly Charges', _rs(monthlyCharges)],
                  ['Transportation', _rs(transport)],
                  ['Discount', '- ${_rs(discount)}'],
                  ['TOTAL BILL', _rs(totalBill)],
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _card('PAYMENT DETAILS', [
                  ['Total Bill', _rs(totalBill)],
                  ['Paid Amount', _rs(paid)],
                  ['Pending Amount', _rs(pendingAmount)],
                  ['Advance Before', _rs(advanceBefore)],
                  ['Advance Applied', _rs(advanceApplied)],
                  ['Advance After', _rs(advanceAfter)],
                  ['Payment Method', paymentMethod],
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _thankYou(billSettings)),
            ],
          ),
          if (billSettings.upiId.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _upi(billSettings.upiId),
          ],
          if (billSettings.terms.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _terms(billSettings.terms),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> shareMonthlyBill({
    required String customerName,
    required String billNumber,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required double advanceBefore,
    required double advanceApplied,
    required double advanceAfter,
    required String paymentMethod,
    required BillSettings billSettings,
  }) async {
    final bytes = await _buildMonthlyBill(
      customerName: customerName,
      billNumber: billNumber,
      monthlyCharges: monthlyCharges,
      transport: transport,
      previousBalance: previousBalance,
      discount: discount,
      paid: paid,
      totalBill: totalBill,
      pendingAmount: pendingAmount,
      advanceBefore: advanceBefore,
      advanceApplied: advanceApplied,
      advanceAfter: advanceAfter,
      paymentMethod: paymentMethod,
      billSettings: billSettings,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_safe(customerName)}_${_safe(billNumber)}_monthly_report.pdf',
    );
  }

  Future<String> saveMonthlyBillToDevice({
    required String customerName,
    required String billNumber,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required double advanceBefore,
    required double advanceApplied,
    required double advanceAfter,
    required String paymentMethod,
    required BillSettings billSettings,
  }) async {
    final bytes = await _buildMonthlyBill(
      customerName: customerName,
      billNumber: billNumber,
      monthlyCharges: monthlyCharges,
      transport: transport,
      previousBalance: previousBalance,
      discount: discount,
      paid: paid,
      totalBill: totalBill,
      pendingAmount: pendingAmount,
      advanceBefore: advanceBefore,
      advanceApplied: advanceApplied,
      advanceAfter: advanceAfter,
      paymentMethod: paymentMethod,
      billSettings: billSettings,
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/${_safe(customerName)}_${_safe(billNumber)}_monthly_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // EXISTING SINGLE GOAT CHECK-OUT API - kept compatible.
  // ---------------------------------------------------------------------------

  Future<Uint8List> _buildBill({
    required PalaiGoat goat,
    required double finalWeight,
    required String healthStatus,
    required String deliveryStatus,
    required double totalCharges,
    required BillSettings billSettings,
    Uint8List? beforeImage,
    Uint8List? afterImage,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => _header(
          billSettings,
          'FINAL CHECK-OUT REPORT',
          right: 'Goat: ${goat.goatCode}',
          period: _fmt(DateTime.now()),
        ),
        footer: (c) => _footer(billSettings, c.pageNumber, c.pagesCount),
        build: (_) => [
          _card('GOAT DETAILS', [
            ['Goat ID', goat.goatCode],
            ['Breed', goat.breed],
            ['Gender', goat.gender],
            ['Color', goat.color],
            ['Monthly Package', goat.monthlyPackage],
            ['Check-In Date', _fmt(goat.checkInDate)],
            ['Check-Out Date', _fmt(DateTime.now())],
            ['Weight at Check-In', '${goat.weightAtCheckIn.toStringAsFixed(1)} kg'],
            ['Final Weight', '${finalWeight.toStringAsFixed(1)} kg'],
            ['Weight Gain', '${(finalWeight - goat.weightAtCheckIn).toStringAsFixed(1)} kg'],
            ['Health Status', healthStatus],
            ['Delivery Status', deliveryStatus],
          ]),
          pw.SizedBox(height: 10),
          _photoPair(
            'BEFORE PALAI',
            _image(beforeImage ?? goat.beforeImage),
            'AFTER PALAI',
            _image(afterImage),
          ),
          pw.SizedBox(height: 10),
          _amount('TOTAL BILL', totalCharges),
          if (billSettings.upiId.trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _upi(billSettings.upiId),
          ],
          if (billSettings.terms.trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _terms(billSettings.terms),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> shareBill({
    required PalaiGoat goat,
    required double finalWeight,
    required String healthStatus,
    required String deliveryStatus,
    required double totalCharges,
    required BillSettings billSettings,
    Uint8List? beforeImage,
    Uint8List? afterImage,
  }) async {
    final bytes = await _buildBill(
      goat: goat,
      finalWeight: finalWeight,
      healthStatus: healthStatus,
      deliveryStatus: deliveryStatus,
      totalCharges: totalCharges,
      billSettings: billSettings,
      beforeImage: beforeImage,
      afterImage: afterImage,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_safe(goat.goatCode)}_final_checkout.pdf',
    );
  }

  Future<String> saveBillToDevice({
    required PalaiGoat goat,
    required double finalWeight,
    required String healthStatus,
    required String deliveryStatus,
    required double totalCharges,
    required BillSettings billSettings,
    Uint8List? beforeImage,
    Uint8List? afterImage,
  }) async {
    final bytes = await _buildBill(
      goat: goat,
      finalWeight: finalWeight,
      healthStatus: healthStatus,
      deliveryStatus: deliveryStatus,
      totalCharges: totalCharges,
      billSettings: billSettings,
      beforeImage: beforeImage,
      afterImage: afterImage,
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/${_safe(goat.goatCode)}_final_checkout_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // WIDGET HELPERS
  // ---------------------------------------------------------------------------

  pw.Widget _header(
      BillSettings settings,
      String title, {
        String? right,
        String? period,
      }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: .7),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  settings.businessName.trim().isEmpty
                      ? 'My Goat Farms'
                      : settings.businessName,
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                if (settings.tagline.trim().isNotEmpty)
                  pw.Text(settings.tagline, style: const pw.TextStyle(fontSize: 8)),
                if (settings.address.trim().isNotEmpty)
                  pw.Text(settings.address, style: const pw.TextStyle(fontSize: 7.5)),
                if (settings.phone.trim().isNotEmpty)
                  pw.Text(settings.phone, style: const pw.TextStyle(fontSize: 7.5)),
              ],
            ),
          ),
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                if (period != null) ...[
                  pw.SizedBox(height: 3),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      period,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.topRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  right ?? 'Report Date: ${_fmt(DateTime.now())}',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(BillSettings settings, int page, int pages) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 7),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: .6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            settings.phone.trim().isEmpty ? 'Thank you for trusting us.' : settings.phone,
            style: const pw.TextStyle(fontSize: 6.8),
          ),
          pw.Text('Page $page of $pages', style: const pw.TextStyle(fontSize: 6.8)),
        ],
      ),
    );
  }

  pw.Widget _customerCard(
      String customer,
      String bill,
      DateTime date,
      String method,
      ) {
    return _card('CUSTOMER DETAILS', [
      ['Customer Name', customer],
      ['Bill Number', bill],
      ['Bill Date', _fmt(date)],
      ['Payment Method', method],
    ]);
  }

  pw.Widget _card(String title, List<List<String>> rows) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.SizedBox(height: 4),
          ...rows.map(
                (r) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      r[0],
                      style: const pw.TextStyle(
                        fontSize: 7.2,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(
                    child: pw.Text(
                      r.length > 1 ? r[1] : '—',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 7.2,
                        fontWeight: pw.FontWeight.bold,
                      ),
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

  pw.Widget _amount(String title, double value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.Text(
            _rs(value),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _photoPair(
      String leftTitle,
      pw.MemoryImage? left,
      String rightTitle,
      pw.MemoryImage? right, {
        bool compact = false,
      }) {
    final h = compact ? 105.0 : 145.0;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _photo(leftTitle, left, h)),
        pw.SizedBox(width: 7),
        pw.Expanded(child: _photo(rightTitle, right, h)),
      ],
    );
  }

  pw.Widget _photo(String title, pw.MemoryImage? image, double height) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: height,
            width: double.infinity,
            color: PdfColors.grey100,
            alignment: pw.Alignment.center,
            child: image == null
                ? pw.Text(
              'Photo not available',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            )
                : pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ],
      ),
    );
  }

  pw.Widget _upi(String upi) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Text(
        'PAY VIA UPI: $upi',
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.green900,
        ),
      ),
    );
  }

  pw.Widget _terms(String terms) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TERMS & CONDITIONS',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(terms, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      ),
    );
  }

  pw.Widget _thankYou(BillSettings settings) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'THANK YOU!',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            settings.footerNote.trim().isEmpty
                ? 'Thank you for trusting us.\nWe care for your goats as our own.'
                : settings.footerNote,
            style: const pw.TextStyle(fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  pw.MemoryImage? _image(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  String _rs(double value) => '₹${value.toStringAsFixed(0)}';

  String _dash(String value) => value.trim().isEmpty ? '—' : value;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';

  String _range(DateTime a, DateTime b) => '${_fmt(a)} - ${_fmt(b)}';

  String _monthYear(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _safe(String value) {
    final result = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return result.isEmpty ? 'report' : result;
  }
}