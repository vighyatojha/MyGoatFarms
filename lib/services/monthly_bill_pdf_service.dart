import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/bill_settings_model.dart';
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
  // BRAND COLOR
  // ===========================================================================
  //
  // PDFs use PdfColor (from `package:pdf`), a completely separate type
  // from Flutter's Color used by AppColors.primaryGreen in app_theme.dart
  // — the two can't be shared directly. I don't have app_theme.dart's
  // actual hex value in this conversation, so this is my best-guess
  // match for a "goat farm app" primary green. If it doesn't look right
  // next to the rest of the app, tell me the exact hex from
  // AppColors.primaryGreen (e.g. `Color(0xFF2E7D32)`) and I'll swap this
  // constant for the real value — every green in this file reads from
  // here, so it's a one-line fix.
  static const PdfColor _brandGreen =
  PdfColor.fromInt(0xFF2E7D32);

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Generates the monthly bill PDF and returns the raw PDF bytes.
  ///
  /// [settings] supplies everything about the FARM/BUSINESS side of the
  /// bill — business name, address, phone, email, logo, footer note,
  /// Terms & Conditions, and Important Notes. This replaces the old
  /// behaviour of reading `bill.farmName` / `bill.farmAddress` / etc.
  /// (a snapshot frozen on the bill at generation time) — the PDF now
  /// always reflects whatever is currently saved in Bill Details /
  /// Settings, the same source the Customer Goat Progress Report reads
  /// from.
  Future<Uint8List> generatePdf(
      MonthlyBill bill,
      BillSettings settings,
      ) async {
    // -------------------------------------------------------------------------
    // Load a Unicode-aware font that supports the ₹ (Rupee) glyph.
    //
    // PdfGoogleFonts downloads Noto Sans from Google's font CDN the first
    // time it's needed on a device, then caches it locally. That network
    // call has NO built-in timeout — on a device with no internet
    // connection, or a slow/blocked one, `await`ing it can hang
    // indefinitely. That is exactly why View/Share/Download all looked
    // like they did nothing: generatePdf() never finished, so it never
    // reached success OR the calling screen's catch block/error snackbar.
    //
    // _loadFonts() below now bounds that call with a timeout and falls
    // back to the PDF package's built-in default font if it fails or
    // times out, so the bill always finishes generating. Offline, it
    // just won't render the ₹ glyph (falls back to a box) until the
    // fonts have been cached once while online — everything else about
    // the PDF still works.
    // -------------------------------------------------------------------------

    final fonts = await _loadFonts();

    final pdf = pw.Document(
      theme: fonts != null
          ? pw.ThemeData.withFont(
        base: fonts.base,
        bold: fonts.bold,
      )
          : null,
    );

    // -------------------------------------------------------------------------
    // Load the logo. Prefer the farm's own uploaded Bill Details logo
    // (settings.billLogo); fall back to the bundled placeholder asset
    // only when the farm hasn't set one, so a bill still looks branded
    // out of the box.
    // -------------------------------------------------------------------------

    pw.MemoryImage? logo;

    if (settings.billLogo != null && settings.billLogo!.isNotEmpty) {
      logo = pw.MemoryImage(settings.billLogo!);
    } else {
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
    }

    // -------------------------------------------------------------------------
    // Terms & Conditions / Important Notes are only shown when there's
    // actually something enabled to show — otherwise the section (and
    // its spacing) is skipped entirely rather than rendering an empty box.
    // -------------------------------------------------------------------------

    final hasTerms = settings.termsSections.any((s) => s.enabled) ||
        (settings.otherTermsEnabled &&
            settings.otherTermsTitle.trim().isNotEmpty &&
            settings.otherTermsText.trim().isNotEmpty);

    final hasImportantNotes = settings.importantNotes.any((n) => n.enabled) ||
        (settings.otherNoteEnabled &&
            settings.otherNoteTitle.trim().isNotEmpty &&
            settings.otherNoteText.trim().isNotEmpty);

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
            settings,
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

            if (hasTerms) ...[
              pw.SizedBox(height: 28),
              _buildTermsAndConditions(settings),
            ],

            if (hasImportantNotes) ...[
              pw.SizedBox(height: 18),
              _buildImportantNotes(settings),
            ],

            pw.SizedBox(height: 20),

            _buildSignatureSection(settings),

            pw.SizedBox(height: 14),

            _buildThankYouSection(settings),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Loads the Unicode-aware Noto Sans fonts, bounded by a timeout, and
  /// falls back to `null` (the PDF package's default font) if the
  /// network fetch fails or takes too long — so a slow/offline device
  /// never blocks bill generation forever.
  Future<_PdfFonts?> _loadFonts() async {
    try {
      final base = await PdfGoogleFonts.notoSansRegular()
          .timeout(const Duration(seconds: 8));

      final bold = await PdfGoogleFonts.notoSansBold()
          .timeout(const Duration(seconds: 8));

      return _PdfFonts(base, bold);
    } catch (e) {
      debugPrint(
        'Monthly bill PDF: could not load Noto Sans (offline or slow '
            'network?). Falling back to the default font. $e',
      );
      return null;
    }
  }

  /// Opens the system PDF preview.
  Future<void> preview(
      MonthlyBill bill,
      BillSettings settings,
      ) async {
    final bytes = await generatePdf(bill, settings);

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
  Future<void> share(
      MonthlyBill bill,
      BillSettings settings,
      ) async {
    final bytes = await generatePdf(bill, settings);

    await Printing.sharePdf(
      bytes: bytes,
      filename: _safeFileName(bill),
    );
  }

  /// Saves the PDF to the application documents directory.
  ///
  /// Returns the full local path.
  Future<String> save(
      MonthlyBill bill,
      BillSettings settings,
      ) async {
    final bytes = await generatePdf(bill, settings);

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

  pw.Widget _buildHeader(BillSettings settings,
      pw.MemoryImage? logo,) {
    final farmName =
    settings.businessName
        .trim()
        .isNotEmpty
        ? settings.businessName.trim()
        : 'My Goat Farms';

    final address =
    settings.address.trim();

    final phone =
    settings.phone.trim();

    final email =
    settings.email.trim();

    final initial =
    farmName.isNotEmpty
        ? farmName[0].toUpperCase()
        : '?';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(
        bottom: 14,
      ),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            width: 1,
            color: PdfColors.grey400,
          ),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.center,
        children: [
          // ---------------------------------------------------------------
          // CIRCULAR LOGO
          //
          // Falls back to a green initial avatar (matching the app's own
          // customer-avatar look) when the farm has neither a Bill Logo
          // nor a Profile photo set.
          // ---------------------------------------------------------------

          pw.Container(
            width: 78,
            height: 78,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: PdfColors.grey100,
              border: pw.Border.all(
                color: _brandGreen,
                width: 1.6,
              ),
              image: logo != null
                  ? pw.DecorationImage(
                image: logo,
                fit: pw.BoxFit.cover,
              )
                  : null,
            ),
            child: logo == null
                ? pw.Text(
              initial,
              style: pw.TextStyle(
                fontSize: 30,
                fontWeight: pw.FontWeight.bold,
                color: _brandGreen,
              ),
            )
                : null,
          ),

          pw.SizedBox(height: 8),

          // ---------------------------------------------------------------
          // FARM NAME
          // ---------------------------------------------------------------

          pw.Text(
            farmName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: _brandGreen,
            ),
          ),

          if (address.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              address,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
          ],

          if (phone.isNotEmpty ||
              email.isNotEmpty) ...[
            pw.SizedBox(height: 3),

            pw.Wrap(
              alignment: pw.WrapAlignment.center,
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

  pw.Widget _buildTermsAndConditions(BillSettings settings,) {
    final sections = settings.termsSections
        .where((s) => s.enabled)
        .toList();

    final hasOtherTerms = settings.otherTermsEnabled &&
        settings.otherTermsTitle.trim().isNotEmpty &&
        settings.otherTermsText.trim().isNotEmpty;

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

          ...sections.map(
                (section) => _bulletItem(
              section.title,
              section.text,
            ),
          ),

          if (hasOtherTerms)
            _bulletItem(
              settings.otherTermsTitle.trim(),
              settings.otherTermsText.trim(),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // IMPORTANT NOTES
  // ===========================================================================

  pw.Widget _buildImportantNotes(BillSettings settings,) {
    final notes = settings.importantNotes
        .where((n) => n.enabled)
        .toList();

    final hasOtherNote = settings.otherNoteEnabled &&
        settings.otherNoteTitle.trim().isNotEmpty &&
        settings.otherNoteText.trim().isNotEmpty;

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
            'IMPORTANT NOTES',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 7),

          ...notes.map(
                (note) => _bulletItem(
              note.title,
              note.text,
            ),
          ),

          if (hasOtherNote)
            _bulletItem(
              settings.otherNoteTitle.trim(),
              settings.otherNoteText.trim(),
            ),
        ],
      ),
    );
  }

  pw.Widget _bulletItem(String title,
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

  pw.Widget _buildSignatureSection(BillSettings settings,) {
    final farmName =
    settings.businessName
        .trim()
        .isNotEmpty
        ? settings.businessName.trim()
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
              if (settings.phone
                  .trim()
                  .isNotEmpty ||
                  settings.email
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

              if (settings.phone
                  .trim()
                  .isNotEmpty)
                pw.Padding(
                  padding:
                  const pw.EdgeInsets.only(
                    top: 3,
                  ),
                  child: pw.Text(
                    'Phone: ${settings.phone.trim()}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                    ),
                  ),
                ),

              if (settings.email
                  .trim()
                  .isNotEmpty)
                pw.Padding(
                  padding:
                  const pw.EdgeInsets.only(
                    top: 2,
                  ),
                  child: pw.Text(
                    'Email: ${settings.email.trim()}',
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

  pw.Widget _buildThankYouSection(BillSettings settings,) {
    final footerNote =
    settings.footerNote
        .trim()
        .isNotEmpty
        ? settings.footerNote.trim()
        : 'Thank you for trusting us with your goat.';

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
            footerNote,
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

/// Simple holder for the two Noto Sans weights used to theme the PDF.
class _PdfFonts {
  final pw.Font base;
  final pw.Font bold;

  const _PdfFonts(this.base, this.bold);
}