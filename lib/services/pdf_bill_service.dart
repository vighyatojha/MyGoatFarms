import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/palai_models.dart';

/// Central PDF service for MyGoatFarms.
///
/// Handles:
/// 1. Single-goat checkout bills
/// 2. Monthly Palai bills
/// 3. Sharing PDFs
/// 4. Saving PDFs locally
///
/// IMPORTANT:
/// This service only generates/saves/shares PDFs.
/// Firestore payment/accounting updates must be handled by
/// FirestoreService and the relevant billing/checkout screens.
class PdfBillService {
  PdfBillService._();

  static final PdfBillService instance = PdfBillService._();

  // ================================================================
  // COMMON HELPERS
  // ================================================================

  String _fmt(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _safeFileName(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return 'document';
    }

    return trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  pw.Widget _pdfRow(
      String label,
      String value, {
        bool emphasize = false,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
                fontWeight: emphasize
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: emphasize
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _businessHeader(BillSettings settings) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          settings.businessName.trim().isEmpty
              ? 'My Goat Farms'
              : settings.businessName,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
          ),
        ),

        if (settings.tagline.trim().isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            settings.tagline,
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ],

        if (settings.address.trim().isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            settings.address,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ],

        if (settings.phone.trim().isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'Phone: ${settings.phone}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _billTitle(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 12,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.8,
        ),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 15,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.green900,
        ),
      ),
    );
  }

  pw.Widget _footer(BillSettings settings) {
    if (settings.footerNote.trim().isEmpty) {
      return pw.SizedBox();
    }

    return pw.Text(
      settings.footerNote,
      style: const pw.TextStyle(
        fontSize: 9,
        color: PdfColors.grey600,
      ),
      textAlign: pw.TextAlign.center,
    );
  }

  pw.Widget _terms(BillSettings settings) {
    if (settings.terms.trim().isEmpty) {
      return pw.SizedBox();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Terms & Conditions',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          settings.terms,
          style: const pw.TextStyle(
            fontSize: 8.5,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  pw.Widget _upiSection(BillSettings settings) {
    if (settings.upiId.trim().isEmpty) {
      return pw.SizedBox();
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.8,
        ),
      ),
      child: pw.Text(
        'Pay via UPI: ${settings.upiId}',
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.green900,
        ),
      ),
    );
  }

  // ================================================================
  // SINGLE GOAT CHECKOUT BILL
  // ================================================================

  Future<Uint8List> _buildBill({
    required PalaiGoat goat,
    required double finalWeight,
    required String healthStatus,
    required String deliveryStatus,
    required double totalCharges,
    required BillSettings billSettings,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) {
          return pw.Align(
            alignment: pw.Alignment.center,
            child: _footer(billSettings),
          );
        },
        build: (context) {
          return [
            _businessHeader(billSettings),

            pw.SizedBox(height: 18),

            _billTitle('GOAT CHECK-OUT BILL'),

            pw.SizedBox(height: 14),

            // Goat information
            pw.Text(
              'Goat Information',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 7),

            _pdfRow('Goat ID', goat.goatCode),
            _pdfRow('Breed', goat.breed),
            _pdfRow('Gender', goat.gender),
            _pdfRow('Color', goat.color),
            _pdfRow('Monthly Package', goat.monthlyPackage),
            _pdfRow('Check-In Date', _fmt(goat.checkInDate)),
            _pdfRow('Check-Out Date', _fmt(now)),

            pw.SizedBox(height: 10),
            pw.Divider(),

            // Weight information
            pw.Text(
              'Weight & Health',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 7),

            _pdfRow(
              'Weight at Check-In',
              '${goat.weightAtCheckIn.toStringAsFixed(1)} kg',
            ),

            _pdfRow(
              'Final Weight',
              '${finalWeight.toStringAsFixed(1)} kg',
              emphasize: true,
            ),

            _pdfRow(
              'Health Status',
              healthStatus,
            ),

            _pdfRow(
              'Delivery Status',
              deliveryStatus,
            ),

            pw.SizedBox(height: 12),
            pw.Divider(),

            // Charges
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Charges',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Rs. ${totalCharges.toStringAsFixed(0)}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            _upiSection(billSettings),

            pw.SizedBox(height: 18),

            _terms(billSettings),

            pw.SizedBox(height: 25),

            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Thank you for choosing our Palai service.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  // ================================================================
  // SHARE SINGLE GOAT BILL
  // ================================================================

  Future<void> shareBill({
    required PalaiGoat goat,
    required double finalWeight,
    required String healthStatus,
    required String deliveryStatus,
    required double totalCharges,
    required BillSettings billSettings,
  }) async {
    final bytes = await _buildBill(
      goat: goat,
      finalWeight: finalWeight,
      healthStatus: healthStatus,
      deliveryStatus: deliveryStatus,
      totalCharges: totalCharges,
      billSettings: billSettings,
    );

    final fileName =
        '${_safeFileName(goat.goatCode)}_checkout_bill.pdf';

    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  }

  // ================================================================
  // SAVE SINGLE GOAT BILL
  // ================================================================

  Future<String> saveBillToDevice({
    required PalaiGoat goat,
    required double finalWeight,
    required String healthStatus,
    required String deliveryStatus,
    required double totalCharges,
    required BillSettings billSettings,
  }) async {
    final bytes = await _buildBill(
      goat: goat,
      finalWeight: finalWeight,
      healthStatus: healthStatus,
      deliveryStatus: deliveryStatus,
      totalCharges: totalCharges,
      billSettings: billSettings,
    );

    final directory =
    await getApplicationDocumentsDirectory();

    final fileName =
        '${_safeFileName(goat.goatCode)}_checkout_bill.pdf';

    final filePath =
        '${directory.path}/$fileName';

    final file = File(filePath);

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return file.path;
  }

  // ================================================================
  // MONTHLY PALAI BILL
  // ================================================================

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
        margin: const pw.EdgeInsets.all(28),
        footer: (context) {
          return pw.Align(
            alignment: pw.Alignment.center,
            child: _footer(billSettings),
          );
        },
        build: (context) {
          return [
            _businessHeader(billSettings),

            pw.SizedBox(height: 18),

            _billTitle('MONTHLY PALAI BILL'),

            pw.SizedBox(height: 14),

            // --------------------------------------------------------
            // BILL INFORMATION
            // --------------------------------------------------------

            pw.Text(
              'Bill Information',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 7),

            _pdfRow(
              'Bill Number',
              billNumber,
              emphasize: true,
            ),

            _pdfRow(
              'Customer',
              customerName,
              emphasize: true,
            ),

            _pdfRow(
              'Bill Date',
              _fmt(now),
            ),

            _pdfRow(
              'Payment Method',
              paymentMethod,
            ),

            pw.SizedBox(height: 10),
            pw.Divider(),

            // --------------------------------------------------------
            // CHARGES
            // --------------------------------------------------------

            pw.Text(
              'Bill Details',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 7),

            _pdfRow(
              'Previous Balance',
              'Rs. ${previousBalance.toStringAsFixed(0)}',
            ),

            _pdfRow(
              'Monthly Charges',
              'Rs. ${monthlyCharges.toStringAsFixed(0)}',
            ),

            _pdfRow(
              'Transportation',
              'Rs. ${transport.toStringAsFixed(0)}',
            ),

            _pdfRow(
              'Discount',
              '- Rs. ${discount.toStringAsFixed(0)}',
            ),

            pw.SizedBox(height: 8),
            pw.Divider(),

            // --------------------------------------------------------
            // TOTAL
            // --------------------------------------------------------

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total Bill',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Rs. ${totalBill.toStringAsFixed(0)}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 10),

            _pdfRow(
              'Paid Amount',
              'Rs. ${paid.toStringAsFixed(0)}',
              emphasize: true,
            ),

            // --------------------------------------------------------
            // ADVANCE
            // --------------------------------------------------------

            if (advanceBefore > 0 ||
                advanceApplied > 0 ||
                advanceAfter > 0) ...[
              pw.SizedBox(height: 14),

              pw.Text(
                'Advance Payment',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 7),

              _pdfRow(
                'Advance Before',
                'Rs. ${advanceBefore.toStringAsFixed(0)}',
              ),

              _pdfRow(
                'Advance Applied',
                'Rs. ${advanceApplied.toStringAsFixed(0)}',
              ),

              _pdfRow(
                'Remaining Advance',
                'Rs. ${advanceAfter.toStringAsFixed(0)}',
              ),
            ],

            pw.SizedBox(height: 12),
            pw.Divider(),

            // --------------------------------------------------------
            // PENDING
            // --------------------------------------------------------

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: pendingAmount > 0
                    ? PdfColors.red50
                    : PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    pendingAmount > 0
                        ? 'Pending Amount'
                        : 'Amount Pending',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: pendingAmount > 0
                          ? PdfColors.red800
                          : PdfColors.green800,
                    ),
                  ),
                  pw.Text(
                    'Rs. ${pendingAmount.toStringAsFixed(0)}',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: pendingAmount > 0
                          ? PdfColors.red800
                          : PdfColors.green800,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 18),

            _upiSection(billSettings),

            pw.SizedBox(height: 18),

            _terms(billSettings),

            pw.SizedBox(height: 25),

            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Thank you for choosing our Palai service.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  // ================================================================
  // SHARE MONTHLY BILL
  // ================================================================

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

    final customerFileName =
    _safeFileName(customerName);

    final billFileName =
    _safeFileName(billNumber);

    await Printing.sharePdf(
      bytes: bytes,
      filename:
      '${customerFileName}_${billFileName}_bill.pdf',
    );
  }

  // ================================================================
  // SAVE MONTHLY BILL
  // ================================================================

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

    final directory =
    await getApplicationDocumentsDirectory();

    final customerFileName =
    _safeFileName(customerName);

    final billFileName =
    _safeFileName(billNumber);

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final fileName =
        '${customerFileName}_${billFileName}_bill_$timestamp.pdf';

    final filePath =
        '${directory.path}/$fileName';

    final file = File(filePath);

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return file.path;
  }
}