import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/monthly_bill_model.dart';

/// Generates, previews, saves and shares Monthly Bill PDFs.
///
/// This service is ONLY for Customer-level Monthly Bills.
///
/// The goat Check-Out / Final Bill PDF remains separate.
class MonthlyBillPdfService {
  MonthlyBillPdfService._();

  static final MonthlyBillPdfService instance =
  MonthlyBillPdfService._();

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Generates the monthly bill PDF and returns the raw PDF bytes.
  Future<Uint8List> generatePdf(MonthlyBill bill,) async {
    final pdf = pw.Document();

    // -------------------------------------------------------------------------
    // Load farm logo.
    // -------------------------------------------------------------------------

    pw.MemoryImage? logo;

    try {
      final logoBytes =
      await rootBundle.load('assets/images/logo.png');

      logo = pw.MemoryImage(
        logoBytes.buffer.asUint8List(),
      );
    } catch (_) {
      // Logo is optional.
      logo = null;
    }

    // -------------------------------------------------------------------------
    // Build PDF.
    // -------------------------------------------------------------------------

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          32,
          28,
          32,
          30,
        ),

        header: (context) {
          return _buildHeader(
            bill,
            logo,
          );
        },

        footer: (context) {
          return _buildPageFooter(
            context,
          );
        },

        build: (context) {
          return [
            _buildBillTitle(bill),

            pw.SizedBox(height: 16),

            _buildCustomerAndBillInfo(bill),

            pw.SizedBox(height: 18),

            _buildChargesTable(bill),

            pw.SizedBox(height: 18),

            _buildOutstandingSummary(bill),

            pw.SizedBox(height: 18),

            _buildPaymentStatus(bill),

            if (bill.notes
                .trim()
                .isNotEmpty) ...[
              pw.SizedBox(height: 18),
              _buildNotes(bill),
            ],

            pw.SizedBox(height: 28),

            _buildTermsAndConditions(bill),

            pw.SizedBox(height: 20),

            _buildSignatureSection(bill),

            pw.SizedBox(height: 14),

            _buildThankYouSection(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Opens the system PDF preview.
  Future<void> preview(MonthlyBill bill,) async {
    final bytes = await generatePdf(bill);

    await Printing.layoutPdf(
      onLayout: (_) async {
        return bytes;
      },
      name: _safeFileName(bill),
    );
  }

  /// Opens the system print/share sheet.
  ///
  /// On Android this can be used to share/save the generated PDF.
  Future<void> share(MonthlyBill bill,) async {
    final bytes = await generatePdf(bill);

    await Printing.sharePdf(
      bytes: bytes,
      filename: _safeFileName(bill),
    );
  }

  /// Saves the PDF to the application documents directory.
  ///
  /// Returns the full local path.
  Future<String> save(MonthlyBill bill,) async {
    final bytes = await generatePdf(bill);

    final directory =
    await getApplicationDocumentsDirectory();

    final fileName =
    _safeFileName(bill);

    final file = File(
      '${directory.path}/$fileName',
    );

    await file.writeAsBytes(bytes);

    return file.path;
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  pw.Widget _buildHeader(MonthlyBill bill,
      pw.MemoryImage? logo,) {
    final farmName =
    bill.farmName
        .trim()
        .isNotEmpty
        ? bill.farmName.trim()
        : 'My Goat Farms';

    final address =
    bill.farmAddress.trim();

    final phone =
    bill.farmPhone.trim();

    final email =
    bill.farmEmail.trim();

    return pw.Container(
      padding: const pw.EdgeInsets.only(
        bottom: 12,
      ),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            width: 1,
            color: PdfColors.grey400,
          ),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 58,
              height: 58,
              margin: const pw.EdgeInsets.only(
                right: 12,
              ),
              child: pw.Image(
                logo,
                fit: pw.BoxFit.contain,
              ),
            ),
          ],

          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  farmName,
                  style: pw.TextStyle(
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),

                pw.SizedBox(height: 3),

                if (address.isNotEmpty)
                  pw.Text(
                    address,
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey700,
                    ),
                  ),

                if (phone.isNotEmpty ||
                    email.isNotEmpty) ...[
                  pw.SizedBox(height: 3),

                  pw.Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      if (phone.isNotEmpty)
                        pw.Text(
                          'Phone: $phone',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                          ),
                        ),

                      if (email.isNotEmpty)
                        pw.Text(
                          'Email: $email',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TITLE
  // ===========================================================================

  pw.Widget _buildBillTitle(MonthlyBill bill,) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        vertical: 11,
        horizontal: 14,
      ),
      decoration: pw.BoxDecoration(
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(5),
        ),
        border: pw.Border.all(
          color: PdfColors.grey500,
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'MONTHLY BILL',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),

          pw.SizedBox(height: 5),

          pw.Text(
            bill.monthYear,
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CUSTOMER / BILL INFO
  // ===========================================================================

  pw.Widget _buildCustomerAndBillInfo(MonthlyBill bill,) {
    return pw.Row(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _infoBox(
            title: 'BILL TO',
            children: [
              _infoLine(
                'Customer',
                bill.customerName,
              ),
              _infoLine(
                'Customer ID',
                bill.customerId,
              ),
            ],
          ),
        ),

        pw.SizedBox(width: 12),

        pw.Expanded(
          child: _infoBox(
            title: 'BILL DETAILS',
            children: [
              _infoLine(
                'Bill No.',
                bill.billNumber,
              ),
              _infoLine(
                'Billing Period',
                bill.monthYear,
              ),
              _infoLine(
                'Generated',
                _formatDate(bill.generatedAt),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _infoBox({
    required String title,
    required List<pw.Widget> children,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),

          pw.SizedBox(height: 7),

          ...children,
        ],
      ),
    );
  }

  pw.Widget _infoLine(String label,
      String value,) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 4,
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 75,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
          ),

          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '-' : value,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CHARGES TABLE
  // ===========================================================================

  pw.Widget _buildChargesTable(MonthlyBill bill,) {
    final rows = <List<String>>[
      [
        'Monthly Palai Charges',
        _currency(bill.palaiCharges),
      ],
      [
        'Other Charges',
        _currency(bill.otherCharges),
      ],
      [
        'Discount',
        '- ${_currency(bill.discount)}',
      ],
    ];

    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'BILL DETAILS',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),

        pw.SizedBox(height: 8),

        pw.Table(
          border: pw.TableBorder.all(
            color: PdfColors.grey400,
            width: 0.6,
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.2),
          },
          children: [
            pw.TableRow(
              decoration:
              const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              children: [
                _tableHeader('DESCRIPTION'),
                _tableHeader(
                  'AMOUNT',
                  alignRight: true,
                ),
              ],
            ),

            ...rows.map(
                  (row) =>
                  pw.TableRow(
                    children: [
                      _tableCell(row[0]),
                      _tableCell(
                        row[1],
                        alignRight: true,
                      ),
                    ],
                  ),
            ),

            pw.TableRow(
              decoration:
              const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              children: [
                _tableCell(
                  'CURRENT MONTH BILL',
                  bold: true,
                ),
                _tableCell(
                  _currency(
                    bill.currentBillAmount,
                  ),
                  alignRight: true,
                  bold: true,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableHeader(String text, {
    bool alignRight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text,
        textAlign:
        alignRight
            ? pw.TextAlign.right
            : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _tableCell(String text, {
    bool alignRight = false,
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text,
        textAlign:
        alignRight
            ? pw.TextAlign.right
            : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight:
          bold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // ===========================================================================
  // OUTSTANDING SUMMARY
  // ===========================================================================

  pw.Widget _buildOutstandingSummary(MonthlyBill bill,) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey500,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(5),
        ),
      ),
      child: pw.Column(
        children: [
          _summaryRow(
            'Previous Outstanding',
            bill.previousOutstanding,
          ),

          pw.SizedBox(height: 6),

          _summaryRow(
            'Current Monthly Bill',
            bill.currentBillAmount,
          ),

          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
              vertical: 7,
            ),
            child: pw.Divider(
              color: PdfColors.grey400,
            ),
          ),

          _summaryRow(
            'Total Outstanding',
            bill.totalDue,
            bold: true,
            large: true,
          ),

          pw.SizedBox(height: 6),

          _summaryRow(
            'Paid Against This Bill',
            bill.amountPaid,
          ),

          pw.SizedBox(height: 6),

          _summaryRow(
            'Remaining',
            bill.remainingAmount,
            bold: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _summaryRow(String label,
      double amount, {
        bool bold = false,
        bool large = false,
      }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: large ? 11 : 9,
              fontWeight:
              bold
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
          ),
        ),

        pw.Text(
          _currency(amount),
          style: pw.TextStyle(
            fontSize: large ? 12 : 9,
            fontWeight:
            bold
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PAYMENT STATUS
  // ===========================================================================

  pw.Widget _buildPaymentStatus(MonthlyBill bill,) {
    final label = bill.statusLabel;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey500,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'PAYMENT STATUS',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.Spacer(),

          pw.Container(
            padding:
            const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 4,
            ),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: PdfColors.grey600,
              ),
              borderRadius:
              const pw.BorderRadius.all(
                pw.Radius.circular(3),
              ),
            ),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight:
                pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  pw.Widget _buildNotes(MonthlyBill bill,) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NOTES',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 5),

          pw.Text(
            bill.notes,
            style: const pw.TextStyle(
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TERMS & CONDITIONS
  // ===========================================================================

  pw.Widget _buildTermsAndConditions(MonthlyBill bill,) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TERMS & CONDITIONS',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 7),

          _term(
            'Animal Care',
            'We provide proper care, feeding and shelter '
                'for the goats under our Palai service.',
          ),

          _term(
            'Health & Vaccination',
            'Regular health care, vaccination and deworming '
                'are carried out according to the farm schedule. '
                'Additional treatment or medicine may be charged separately.',
          ),

          _term(
            'Payment Terms',
            'Monthly charges should be paid on time. '
                'Outstanding amounts remain payable until fully settled.',
          ),

          _term(
            'Additional Charges',
            'Any additional service, medicine, treatment or '
                'other agreed expense may be added separately.',
          ),

          _term(
            'Ownership',
            'The goat remains the property of the customer. '
                'The Palai service does not transfer ownership to the farm.',
          ),

          _term(
            'Notice',
            'Please inform the farm in advance before taking '
                'the goat out of the Palai service.',
          ),

          _term(
            'Records',
            'Please verify the details mentioned in this bill '
                'and contact the farm if any correction is required.',
          ),
        ],
      ),
    );
  }

  pw.Widget _term(String title,
      String description,) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 5,
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '• ',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '$title: ',
                    style: pw.TextStyle(
                      fontSize: 7.8,
                      fontWeight:
                      pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: description,
                    style: const pw.TextStyle(
                      fontSize: 7.8,
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

  // ===========================================================================
  // SIGNATURE
  // ===========================================================================

  pw.Widget _buildSignatureSection(MonthlyBill bill,) {
    final farmName =
    bill.farmName
        .trim()
        .isNotEmpty
        ? bill.farmName.trim()
        : 'Farm Owner';

    return pw.Row(
      crossAxisAlignment:
      pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment:
            pw.CrossAxisAlignment.start,
            children: [
              if (bill.farmPhone
                  .trim()
                  .isNotEmpty ||
                  bill.farmEmail
                      .trim()
                      .isNotEmpty)
                pw.Text(
                  'For any queries, please contact us anytime.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight:
                    pw.FontWeight.bold,
                  ),
                ),

              if (bill.farmPhone
                  .trim()
                  .isNotEmpty)
                pw.Padding(
                  padding:
                  const pw.EdgeInsets.only(
                    top: 3,
                  ),
                  child: pw.Text(
                    'Phone: ${bill.farmPhone}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                    ),
                  ),
                ),

              if (bill.farmEmail
                  .trim()
                  .isNotEmpty)
                pw.Padding(
                  padding:
                  const pw.EdgeInsets.only(
                    top: 2,
                  ),
                  child: pw.Text(
                    'Email: ${bill.farmEmail}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                    ),
                  ),
                ),
            ],
          ),
        ),

        pw.SizedBox(width: 20),

        pw.Column(
          crossAxisAlignment:
          pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 130,
              height: 35,
              decoration:
              const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            ),

            pw.SizedBox(height: 4),

            pw.Text(
              'Authorized Signature',
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey700,
              ),
            ),

            pw.SizedBox(height: 2),

            pw.Text(
              farmName,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight:
                pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // THANK YOU
  // ===========================================================================

  pw.Widget _buildThankYouSection() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        vertical: 9,
        horizontal: 12,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
        ),
        borderRadius:
        const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'THANK YOU',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1,
            ),
          ),

          pw.SizedBox(height: 3),

          pw.Text(
            'We care for your goats like our own.',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAGE FOOTER
  // ===========================================================================

  pw.Widget _buildPageFooter(pw.Context context,) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(
        top: 8,
      ),
      padding: const pw.EdgeInsets.only(
        top: 5,
      ),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            width: 0.5,
            color: PdfColors.grey400,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Monthly Bill',
            style: const pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),

          pw.Spacer(),

          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FORMATTERS
  // ===========================================================================

  String _currency(double value,) {
    final formatter = NumberFormat(
      '#,##0.00',
      'en_IN',
    );

    return '₹${formatter.format(value)}';
  }

  String _formatDate(DateTime date,) {
    return DateFormat(
      'dd MMM yyyy',
    ).format(date);
  }

  String _safeFileName(MonthlyBill bill,) {
    final raw =
        '${bill.billNumber}_${bill.customerName}_${bill.monthYear}';

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