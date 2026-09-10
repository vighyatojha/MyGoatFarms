import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/monthly_bill_model.dart';
import '../models/palai_models.dart';

class GoatProgressEntry {
  final PalaiGoat goat;

  final Uint8List previousImageBytes;
  final String previousLabel;
  final DateTime previousDate;
  final double? previousWeight;

  final Uint8List currentImageBytes;
  final DateTime currentDate;
  final double? currentWeight;

  final HealthRecordEntry? latestHealthRecord;

  // --------------------------------------------------------------------
  // Bug fix (item 7): Vaccination / Hoof Cutting / Hair Trimming used to
  // be read off `latestHealthRecord` (a single shared health-record
  // snapshot), which isn't reliable — those three have their own
  // dedicated per-goat Firestore subcollections (vaccinationRecords /
  // hoofCuttingRecords / hairTrimmingRecords), the same ones shown on
  // the goat's own Vaccination / Hoof / Hair tabs. These three fields
  // hold the date of the latest record actually found in each of those
  // subcollections (null = no record yet, i.e. "Not done yet").
  // --------------------------------------------------------------------
  final DateTime? latestVaccinationDate;
  final DateTime? latestHoofCuttingDate;
  final DateTime? latestHairTrimmingDate;

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
    this.latestVaccinationDate,
    this.latestHoofCuttingDate,
    this.latestHairTrimmingDate,
  });
}

class CustomerGoatsProgressReportPdfService {
  CustomerGoatsProgressReportPdfService._();

  static final CustomerGoatsProgressReportPdfService instance =
  CustomerGoatsProgressReportPdfService._();

  // ==========================================================================
  // PUBLIC API
  // ==========================================================================

  Future<Uint8List> generatePdf({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    MonthlyBill? monthlyBill,
  }) async {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    final logoImage = _safeMemoryImage(billSettings.billLogo);

    // ------------------------------------------------------------------
    // Bug fix (item 1) — everything below now flows through ONE
    // pw.MultiPage instead of being manually chunked into fixed-height
    // pw.Page's. The `pdf` package computes each widget's real height
    // and flows it onto as many pages as it actually needs, so a goat
    // card (or a wrapped header, long address, etc.) can never overlap
    // the next one — it simply continues on the next page instead.
    //
    // This single MultiPage also gives us, for free:
    //   - accurate "Page X of Y" numbers across the WHOLE report
    //     (via context.pageNumber / context.pagesCount in the footer),
    //   - a header that can differ by page number (full header + info
    //     bar on page 1, a slim header on every page after — item 5),
    //   - Payment Details and Terms & Conditions each still forced onto
    //     their own fresh page via the pw.NewPage() marker widget,
    //     exactly like the old separate pdf.addPage() calls did.
    // ------------------------------------------------------------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
        header: (context) => _buildPageHeader(
          context: context,
          customer: customer,
          totalGoatsInReport: entries.length,
          billSettings: billSettings,
          logoImage: logoImage,
        ),
        footer: (context) => _buildFooter(
          billSettings: billSettings,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
        ),
        build: (context) => _buildDocumentContent(
          customer: customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
        ),
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
    final bytes = await generatePdf(
      customer: customer,
      entries: entries,
      billSettings: billSettings,
      monthlyBill: monthlyBill,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _safeFileName(customer),
    );
  }

  Future<void> share({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    MonthlyBill? monthlyBill,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      entries: entries,
      billSettings: billSettings,
      monthlyBill: monthlyBill,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _safeFileName(customer),
    );
  }

  Future<String> save({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    MonthlyBill? monthlyBill,
  }) async {
    final bytes = await generatePdf(
      customer: customer,
      entries: entries,
      billSettings: billSettings,
      monthlyBill: monthlyBill,
    );

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_safeFileName(customer)}');
    await file.writeAsBytes(bytes);

    return file.path;
  }

  // ==========================================================================
  // IMAGE LOADING — every image on the report goes through this helper so a
  // single corrupt/undecodable photo can never blank out or crash the whole
  // PDF; it just falls back to a placeholder instead.
  // ==========================================================================

  /// Decodes [bytes] into a `pw.MemoryImage`, or returns null if the bytes
  /// are empty or fail to decode (instead of letting `pdf` throw and take
  /// the whole report down with it).
  pw.MemoryImage? _safeMemoryImage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // DOCUMENT CONTENT — the full flowing widget list handed to pw.MultiPage.
  // Section 1 (Progress of Goats) is deliberately paginated 2 goat cards
  // per page — a forced pw.NewPage() after every 2nd card, rather than
  // letting the cards flow naturally — so every "Progress of Goats" page
  // always shows exactly 2 goats (the last page only has 1 if the goat
  // count is odd). Section 2 (Payment Details) and Section 3 (Terms &
  // Conditions) are each still forced onto their own fresh page.
  // ==========================================================================

  List<pw.Widget> _buildDocumentContent({
    required PalaiCustomer customer,
    required List<GoatProgressEntry> entries,
    required BillSettings billSettings,
    required MonthlyBill? monthlyBill,
  }) {
    final content = <pw.Widget>[];

    // ---- SECTION 1: Progress of Goats -----------------------------------
    content.add(
      _buildSectionBanner(
        number: '1',
        title: 'Progress of Goats',
        subtitle: 'Customer: ${customer.name}'
            '${entries.isNotEmpty ? ' • ${entries.length} goat${entries.length == 1 ? '' : 's'} in this report' : ''}',
      ),
    );
    content.add(pw.SizedBox(height: 5));

    if (entries.isEmpty) {
      content.add(
        pw.Container(
          width: double.infinity,
          height: 120,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'No goat progress data available.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      );
    } else {
      // Fixed 2-goats-per-page pagination: every pair of cards gets a
      // small gap between them, and a hard page break after the 2nd
      // card of each pair (unless it's also the very last card overall,
      // in which case no trailing blank page is needed).
      const goatsPerPage = 2;
      for (int i = 0; i < entries.length; i++) {
        content.add(_buildGoatCard(i + 1, entries[i]));

        final isLastEntry = i == entries.length - 1;
        if (isLastEntry) break;

        final isEndOfPageGroup = (i + 1) % goatsPerPage == 0;
        content.add(isEndOfPageGroup ? pw.NewPage() : pw.SizedBox(height: 5));
      }
    }

    // ---- SECTION 2: Payment Details (always its own page) ---------------
    content.add(pw.NewPage());
    content.add(
      _buildSectionBanner(
        number: '2',
        title: 'Payment Details',
        subtitle: 'Billing summary for ${customer.name}',
      ),
    );
    content.add(pw.SizedBox(height: 14));

    if (monthlyBill != null) {
      content.add(_buildBillingSummary(monthlyBill, entries));
    } else {
      content.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
            color: PdfColors.green50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Text(
            'No billing information available for this report.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
      );
    }

    // ---- SECTION 3: Terms & Conditions (always its own page) -------------
    content.add(pw.NewPage());
    content.add(
      _buildSectionBanner(
        number: '3',
        title: 'Terms & Conditions',
        subtitle: 'Important notes • Customer acknowledgement • Farm policies',
      ),
    );
    content.add(pw.SizedBox(height: 10));
    content.add(_buildTermsGrid(billSettings));
    content.add(pw.SizedBox(height: 9));
    content.add(_buildImportantNotes(billSettings));
    content.add(pw.SizedBox(height: 14));
    content.add(_buildClosingBanner(billSettings));

    return content;
  }

  // ==========================================================================
  // PAGE HEADER — full header (+ customer/info bar) on page 1 only; a slim
  // minor header on every page after that (bug fix items 5 & 6).
  // ==========================================================================

  pw.Widget _buildPageHeader({
    required pw.Context context,
    required PalaiCustomer customer,
    required int totalGoatsInReport,
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    if (context.pageNumber == 1) {
      return pw.Column(
        children: [
          _buildFullHeader(
            billSettings: billSettings,
            logoImage: logoImage,
          ),
          pw.SizedBox(height: 4),
          _buildCustomerBar(
            customer: customer,
            totalGoatsInReport: totalGoatsInReport,
          ),
          pw.SizedBox(height: 4),
        ],
      );
    }

    return pw.Column(
      children: [
        _buildMinorHeader(
          billSettings: billSettings,
          logoImage: logoImage,
        ),
        pw.SizedBox(height: 4),
      ],
    );
  }

  // ==========================================================================
  // FULL FARM HEADER (page 1 only) — circular logo pinned top-left, farm
  // name + locality + contact block centered across the FULL header width.
  //
  // FIX: the header no longer paints ANY background — no image, no wash,
  // no fill color, no border. It's a fully transparent block that simply
  // sits on the page's own (white) background, so it can never hide or
  // compete with the farm logo or anything else again. Only the text and
  // the circular logo badge itself carry color; the header container is
  // just an invisible layout box.
  // ==========================================================================

  pw.Widget _buildFullHeader({
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    final darkGreen = PdfColor.fromHex('#1B5E20');

    const double logoSize = 90.0;

    final String farmName =
    billSettings.businessName.trim().isNotEmpty
        ? billSettings.businessName.trim().toUpperCase()
        : 'MY GOAT FARM';

    final String locality = _localitySubtitle(billSettings);
    final String phone = billSettings.phone.trim();
    final String address = billSettings.address.trim();

    return pw.SizedBox(
      width: double.infinity,
      height: 100,
      child: pw.Stack(
        children: [
          // ---------------------------------------------------------------
          // LOGO — LEFT SIDE
          // ---------------------------------------------------------------
          pw.Positioned(
            left: 4,
            top: 4,
            child: _buildFarmLogo(
              logoImage,
              size: logoSize,
            ),
          ),

          // ---------------------------------------------------------------
          // FARM INFORMATION — CENTER
          // ---------------------------------------------------------------
          pw.Positioned(
            left: 72,
            right: 10,
            top: 5,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // FARM NAME
                pw.Text(
                  farmName,
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 25.5,
                    fontWeight: pw.FontWeight.bold,
                    color: darkGreen,
                  ),
                ),

                // LOCALITY
                if (locality.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    locality,
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 12.75,
                      fontWeight: pw.FontWeight.bold,
                      color: darkGreen,
                    ),
                  ),
                ],

                // CONTACT + ADDRESS
                // FIX: previously this was a Row where the address sat in
                // an Expanded, so its own text was centered *inside its
                // own slice* of the row rather than the phone+address
                // block being centered as a whole — whenever a phone
                // number was present it visibly dragged the address off
                // the true horizontal center under the farm name. Using
                // pw.Wrap with WrapAlignment.center sizes each piece to
                // its own content and centers the whole phone+address
                // group as a single unit, matching the reference banner.
                if (phone.isNotEmpty || address.isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  pw.Wrap(
                    alignment: pw.WrapAlignment.center,
                    crossAxisAlignment: pw.WrapCrossAlignment.center,
                    children: [
                      if (phone.isNotEmpty)
                        pw.Text(
                          phone,
                          maxLines: 1,
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            color: darkGreen,
                          ),
                        ),
                      if (phone.isNotEmpty && address.isNotEmpty)
                        pw.SizedBox(width: 14),
                      if (address.isNotEmpty)
                        pw.Text(
                          address,
                          maxLines: 1,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            color: darkGreen,
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

  // ==========================================================================
  // MINOR HEADER (every page after page 1) — a slim single row: small logo
  // + business name only. No background photo, no address/phone/email.
  // ==========================================================================

  pw.Widget _buildMinorHeader({
    required BillSettings billSettings,
    required pw.MemoryImage? logoImage,
  }) {
    return pw.SizedBox(
      width: double.infinity,
      height: 30,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _buildFarmLogo(
            logoImage,
            size: 22,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              billSettings.businessName.trim().isNotEmpty
                  ? billSettings.businessName
                  : 'My Goat Farm',
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // FIX: the image used to be drawn at the FULL badge size (`size`) even
  // though it sits inside a container that already has its own padding
  // and a border — so the image content was bleeding past the padding
  // and visibly poking outside the green circular border. The image (and
  // the ClipRRect clipping it) now use the true INNER size — badge size
  // minus padding on both sides — so the photo is always contained
  // cleanly inside the ring, whatever the badge size is.
  pw.Widget _buildFarmLogo(pw.MemoryImage? logoImage, {double size = 92.0}) {
    final double borderWidth = size >= 40 ? 2 : 1;
    final double padding = size >= 40 ? 3 : 1.5;
    final double innerSize = size - (padding * 2);

    if (logoImage == null) {
      return pw.Container(
        width: size,
        height: size,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.white,
          border: pw.Border.all(color: PdfColors.green800, width: borderWidth),
        ),
        alignment: pw.Alignment.center,
        child: size >= 40
            ? pw.Text(
          'LOGO',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
        )
            : null,
      );
    }

    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(padding),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.green800, width: borderWidth),
        boxShadow: size >= 40
            ? [pw.BoxShadow(color: PdfColor(0, 0, 0, 0.18), blurRadius: 3, offset: const PdfPoint(0, 1))]
            : null,
      ),
      child: pw.ClipRRect(
        horizontalRadius: innerSize / 2,
        verticalRadius: innerSize / 2,
        child: pw.Image(logoImage, fit: pw.BoxFit.cover, width: innerSize, height: innerSize),
      ),
    );
  }

  pw.Widget _contactChip({required String symbol, required String text, int maxLines = 1}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 14,
          height: 14,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
          child: pw.Text(symbol, style: const pw.TextStyle(fontSize: 7, color: PdfColors.white)),
        ),
        pw.SizedBox(width: 5),
        pw.ConstrainedBox(
          constraints: const pw.BoxConstraints(maxWidth: 260),
          child: pw.Text(
            text,
            maxLines: maxLines,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
          ),
        ),
      ],
    );
  }

  /// Builds a short "locality" line from the free-text address (e.g. turns
  /// "Kamal's Farm, kholvad, Surat - 395001" into "KHOLVAD, SURAT") so the
  /// header can show a short place name under the farm name, the way the
  /// reference banner does, without needing a separate city field.
  String _localitySubtitle(BillSettings billSettings) {
    final address = billSettings.address.trim();
    if (address.isEmpty) return '';

    final parts = address.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length <= 1) return address.toUpperCase();

    final trimmed = List<String>.from(parts);
    if (trimmed.isNotEmpty && RegExp(r'^[\d\s-]+$').hasMatch(trimmed.last)) {
      trimmed.removeLast();
    }
    if (trimmed.isEmpty) return address.toUpperCase();

    final tail = trimmed.length > 2 ? trimmed.sublist(trimmed.length - 2) : trimmed;
    return tail.join(', ').toUpperCase();
  }

  // ==========================================================================
  // CUSTOMER / INFO BAR — page 1 only. "No. of Goats" now reflects the true
  // total across the whole report (bug fix item 6), not a per-page subset,
  // since it's only ever shown once.
  // ==========================================================================

  pw.Widget _buildCustomerBar({
    required PalaiCustomer customer,
    required int totalGoatsInReport,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: _customerInfo('Customer', customer.name)),
          pw.Expanded(child: _customerInfo('Date of Report', _formatDate(DateTime.now()))),
          pw.Expanded(child: _customerInfo('No. of Goats', '$totalGoatsInReport')),
        ],
      ),
    );
  }

  pw.Widget _customerInfo(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
        pw.SizedBox(height: 1),
        pw.Text(
          value.trim().isEmpty ? '-' : value,
          maxLines: 1,
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
        ),
      ],
    );
  }

  // ==========================================================================
  // SECTION BANNER — used for all three sections (Progress / Payment / Terms)
  // ==========================================================================

  pw.Widget _buildSectionBanner({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 25,
            height: 25,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
            child: pw.Text(number, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                if (subtitle.trim().isNotEmpty)
                  pw.Text(subtitle, maxLines: 1, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // GOAT CARD — one per goat.
  //
  // Layout (per the reference mock-up):
  //   Row 1: Goat Details card on the LEFT, Previous/Current photos on the
  //          RIGHT.
  //   Row 2: Weight & Gain card + Health Status card, side by side, full
  //          width, BELOW row 1.
  //
  // Sizes are kept deliberately compact (smaller photos, tighter padding)
  // so two goat cards comfortably fit on one A4 page. Nothing has a fixed
  // height, so pw.MultiPage still flows a card onto the next page instead
  // of ever overlapping the one before/after it if content runs long.
  // ==========================================================================

  pw.Widget _buildGoatCard(int number, GoatProgressEntry entry) {
    final goat = entry.goat;

    final gain = entry.previousWeight != null && entry.currentWeight != null
        ? entry.currentWeight! - entry.previousWeight!
        : null;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.8),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _goatTitle(number, goat),
          pw.SizedBox(height: 4),
          // Row 1: details (left) + photos (right)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 4, child: _goatDetails(goat)),
              pw.SizedBox(width: 6),
              pw.Expanded(flex: 6, child: _goatPhotos(entry)),
            ],
          ),
          pw.SizedBox(height: 5),
          // Row 2: weight & gain + health status, both below row 1
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _weightGainBox(entry, gain)),
              pw.SizedBox(width: 6),
              pw.Expanded(flex: 2, child: _healthStatusBox(entry)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _goatTitle(int number, PalaiGoat goat) {
    final code = goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber;
    final name = goat.name.trim();

    return pw.Row(
      children: [
        pw.Container(
          width: 20,
          height: 20,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
          child: pw.Text('$number', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
        pw.SizedBox(width: 6),
        pw.Text(
          name.isNotEmpty ? '$code ($name)' : code,
          maxLines: 1,
          style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
        ),
      ],
    );
  }

  // ==========================================================================
  // GOAT DETAILS — left column of row 1. Full height of whatever the photo
  // column next to it ends up being (Row uses CrossAxisAlignment.start, so
  // this card just sizes to its own content).
  // ==========================================================================

  pw.Widget _goatDetails(PalaiGoat goat) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle('GOAT DETAILS'),
          pw.SizedBox(height: 3),
          _detailRow('Breed', goat.breed.trim().isNotEmpty ? goat.breed : '-'),
          _detailRow('Gender', goat.gender.trim().isNotEmpty ? goat.gender : '-'),
          _detailRow('Color', goat.color.trim().isNotEmpty ? goat.color : '-'),
          _detailRow('Date of Join', _formatDate(goat.checkInDate)),
          _detailRow('Age', _ageLabel(goat.dateOfBirth)),
          _detailRow('Monthly Rate', _currency(goat.pricing)),
        ],
      ),
    );
  }

  // ==========================================================================
  // MONTHLY PROGRESS PHOTOS — right column of row 1, sitting beside Goat
  // Details instead of spanning the full card width. Photo tiles were
  // enlarged 25% (see _photoTile) to use the extra room in this column
  // more fully, with the gaps between the two tiles and the arrow left
  // untouched.
  // ==========================================================================

  pw.Widget _goatPhotos(GoatProgressEntry entry) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'MONTHLY PROGRESS',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _photoTile(
              title: 'Previous Month',
              subCaption: '${_formatMonthYear(entry.previousDate)} • ${entry.previousLabel}',
              bytes: entry.previousImageBytes,
            ),
            pw.SizedBox(width: 6),
            _arrow(),
            pw.SizedBox(width: 6),
            _photoTile(
              title: 'Current Month',
              subCaption: '${_formatMonthYear(entry.currentDate)} • Report Day Photo',
              bytes: entry.currentImageBytes,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _photoTile({
    required String title,
    required String subCaption,
    required Uint8List bytes,
  }) {
    // FIX: photo tile size increased 25% (92 -> 115) to fill the spare
    // room in the photos column. The gaps around each tile (the
    // SizedBox(width: 6) either side of the arrow in _goatPhotos, and
    // the internal spacing below) are unchanged — only the tile itself
    // grew.
    const size = 115.0;
    final image = _safeMemoryImage(bytes);

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 2),
        pw.Container(
          width: size,
          height: size,
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.green300, width: 1),
            color: PdfColors.grey100,
          ),
          child: pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: image != null
                ? pw.Image(image, width: size, height: size, fit: pw.BoxFit.cover)
                : pw.Center(
              child: pw.Text(
                'No Photo',
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500),
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.SizedBox(
          width: size,
          child: pw.Text(
            subCaption,
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 5.3, color: PdfColors.grey600),
          ),
        ),
      ],
    );
  }

  pw.Widget _arrow() {
    return pw.SizedBox(
      width: 14,
      height: 14,
      child: pw.CustomPaint(
        size: const PdfPoint(14, 14),
        painter: (PdfGraphics canvas, PdfPoint size) {
          final y = size.y / 2;
          canvas
            ..setColor(PdfColors.green700)
            ..moveTo(1, y - 2)
            ..lineTo(size.x - 5, y - 2)
            ..lineTo(size.x - 5, y - 4)
            ..lineTo(size.x - 1, y)
            ..lineTo(size.x - 5, y + 4)
            ..lineTo(size.x - 5, y + 2)
            ..lineTo(1, y + 2)
            ..lineTo(1, y - 2)
            ..fillPath();
        },
      ),
    );
  }

  // ==========================================================================
  // ROW 2 — Weight & Gain (left) and Health Status (right), both sitting
  // BELOW the details/photos row, full card width.
  // ==========================================================================

  pw.Widget _weightGainBox(GoatProgressEntry entry, double? gain) {
    return _statBox(
      title: 'WEIGHT & GAIN',
      rows: [
        _statRow('Previous', entry.previousWeight != null ? '${entry.previousWeight!.toStringAsFixed(1)} kg' : '-'),
        _statRow('Current', entry.currentWeight != null ? '${entry.currentWeight!.toStringAsFixed(1)} kg' : '-'),
        _statRow(
          'Gain',
          gain != null ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : '-',
          valueColor: gain == null ? PdfColors.grey800 : (gain >= 0 ? PdfColors.green700 : PdfColors.red700),
        ),
      ],
    );
  }

  pw.Widget _healthStatusBox(GoatProgressEntry entry) {
    final record = entry.latestHealthRecord;

    return _statBox(
      title: 'HEALTH STATUS',
      rows: [
        _statRow('Health', record?.healthStatus.trim().isNotEmpty == true ? record!.healthStatus : entry.goat.healthStatus),
        // Bug fix (item 7): Vaccination / Hoof Cutting / Hair Trimming
        // now come from each goat's own dedicated record subcollection
        // (fetched alongside the health-record snapshot in the capture
        // screen), not from the shared HealthRecordEntry snapshot.
        _statRow('Vaccination', _doneLabel(entry.latestVaccinationDate)),
        _statRow('Hoof Cutting', _doneLabel(entry.latestHoofCuttingDate)),
        _statRow('Hair Trimming', _doneLabel(entry.latestHairTrimmingDate)),
        _statRow('Deworming', record?.deworming.trim().isNotEmpty == true ? record!.deworming : '-'),
        _statRow('Medicine', record?.medicineGiven.trim().isNotEmpty == true ? record!.medicineGiven : 'None'),
        _statRow('Notes', record?.doctorNotes.trim().isNotEmpty == true ? record!.doctorNotes : '-'),
      ],
    );
  }

  /// "Yes — 12 Jan 2026" when a record date is present, "Not done yet"
  /// otherwise. Shared by Vaccination / Hoof Cutting / Hair Trimming so
  /// all three read the exact same way on the card.
  String _doneLabel(DateTime? date) {
    if (date == null) return 'Not done yet';
    return 'Yes \u2014 ${_formatDate(date)}';
  }

  pw.Widget _boxTitle(String title) {
    return pw.Text(title, style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900));
  }

  pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 4, child: pw.Text(label, style: const pw.TextStyle(fontSize: 6.2, color: PdfColors.grey600))),
          pw.SizedBox(width: 4),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              value.isEmpty ? '-' : value,
              maxLines: 1,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 6.6, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _statBox({required String title, required List<pw.Widget> rows}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle(title),
          pw.SizedBox(height: 3),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _statRow(String label, String value, {PdfColor valueColor = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 5, child: pw.Text(label, maxLines: 2, style: const pw.TextStyle(fontSize: 5.6, color: PdfColors.grey700))),
          pw.SizedBox(width: 2),
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              value.isEmpty ? '-' : value,
              maxLines: 2,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 5.6, fontWeight: pw.FontWeight.bold, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PAYMENT DETAILS — billing summary
  // ==========================================================================

  pw.Widget _buildBillingSummary(MonthlyBill bill, List<GoatProgressEntry> entries) {
    final statusBackground = bill.isPaid
        ? PdfColors.green100
        : bill.isPartiallyPaid
        ? PdfColors.orange100
        : PdfColors.red100;

    final statusColor = bill.isPaid
        ? PdfColors.green900
        : bill.isPartiallyPaid
        ? PdfColors.orange900
        : PdfColors.red900;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
        border: pw.Border.all(color: PdfColors.green200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'BILLING SUMMARY \u2014 ${bill.monthYear}',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: pw.BoxDecoration(color: statusBackground, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12))),
                child: pw.Text(bill.statusLabel, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: statusColor)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: PdfColors.green200),
          pw.SizedBox(height: 8),
          if (bill.goatBreakdown.isNotEmpty) ...[
            _billingHeading('CURRENT MONTH PALAI'),
            pw.SizedBox(height: 5),
            for (final line in bill.goatBreakdown) _billingRow(line.label, _currency(line.palaiAmount)),
            pw.SizedBox(height: 4),
            pw.Divider(color: PdfColors.green200),
            pw.SizedBox(height: 7),
          ] else if (entries.isNotEmpty) ...[
            _billingHeading('CURRENT MONTH PALAI'),
            pw.SizedBox(height: 5),
            for (final entry in entries)
              _billingRow(
                entry.goat.name.trim().isNotEmpty
                    ? entry.goat.name
                    : (entry.goat.goatCode.trim().isNotEmpty ? entry.goat.goatCode : entry.goat.tagNumber),
                _currency(entry.goat.pricing),
              ),
            pw.SizedBox(height: 4),
            pw.Divider(color: PdfColors.green200),
            pw.SizedBox(height: 7),
          ],
          _billingRow('Current Month Palai', _currency(bill.palaiCharges)),
          _billingRow('Old Pending Payment', _currency(bill.previousOutstanding)),
          if (bill.advanceApplied > 0) _billingRow('Current Advance', '- ${_currency(bill.advanceApplied)}'),
          pw.SizedBox(height: 5),
          pw.Divider(color: PdfColors.green300),
          pw.SizedBox(height: 5),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7))),
            child: _billingRow('TOTAL PENDING PAYMENT', _currency(bill.totalDue), emphasize: true),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Current Month Calculation Only \u2014 previous monthly payments and historical transactions are not included above.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Bill No: ${bill.billNumber}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  pw.Widget _billingHeading(String title) {
    return pw.Text(title, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900));
  }

  pw.Widget _billingRow(String label, String value, {bool emphasize = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: emphasize ? 11 : 8.5,
                fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: emphasize ? PdfColors.black : PdfColors.grey700,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasize ? 11 : 9,
              fontWeight: pw.FontWeight.bold,
              color: emphasize ? PdfColors.green900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TERMS & CONDITIONS
  // ==========================================================================

  pw.Widget _buildTermsGrid(BillSettings b) {
    final sections = b.termsSections.where((s) => s.enabled).toList();
    final widgets = <pw.Widget>[];

    for (int i = 0; i < sections.length; i++) {
      widgets.add(_termCard(i + 1, sections[i].title, sections[i].text));
    }

    if (b.otherTermsEnabled && b.otherTermsText.trim().isNotEmpty) {
      widgets.add(_termCard(sections.length + 1, b.otherTermsTitle.trim().isNotEmpty ? b.otherTermsTitle : 'Other', b.otherTermsText));
    }

    if (widgets.isEmpty) {
      return pw.Text(
        'No terms and conditions configured.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      );
    }

    final rows = <pw.Widget>[];
    for (int i = 0; i < widgets.length; i += 2) {
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: widgets[i]),
              pw.SizedBox(width: 8),
              pw.Expanded(child: i + 1 < widgets.length ? widgets[i + 1] : pw.SizedBox()),
            ],
          ),
        ),
      );
    }

    return pw.Column(children: rows);
  }

  pw.Widget _termCard(int number, String title, String text) {
    return pw.Container(
      height: 82,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 19,
            height: 19,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: PdfColors.green700, shape: pw.BoxShape.circle),
            child: pw.Text('$number', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, maxLines: 2, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                pw.SizedBox(height: 4),
                pw.Text(text, style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700, lineSpacing: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildImportantNotes(BillSettings b) {
    final notes = b.importantNotes.where((n) => n.enabled).toList();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('IMPORTANT NOTES', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 5),
          for (final note in notes) _bullet('${note.title}: ${note.text}'),
          if (b.otherNoteEnabled && b.otherNoteText.trim().isNotEmpty) _bullet(b.otherNoteText),
        ],
      ),
    );
  }

  pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('\u2022', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
          pw.SizedBox(width: 5),
          pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700))),
        ],
      ),
    );
  }

  pw.Widget _buildClosingBanner(BillSettings b) {
    final text = b.footerNote.trim().isNotEmpty ? b.footerNote : 'We care for your goats as our own.';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: pw.BoxDecoration(color: PdfColors.green900, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7))),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  // ==========================================================================
  // FOOTER — every page. Page numbers now come from pw.MultiPage's own
  // context (context.pageNumber / context.pagesCount), so they're always
  // accurate across the whole report instead of being precomputed by hand.
  // ==========================================================================

  pw.Widget _buildFooter({
    required BillSettings billSettings,
    required int pageNumber,
    required int totalPages,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      child: pw.Row(
        children: [
          pw.Text(billSettings.businessName, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
          pw.Spacer(),
          pw.Text('Page $pageNumber of $totalPages', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  // ==========================================================================
  // FORMAT HELPERS
  // ==========================================================================

  String _currency(double value) {
    final formatter = NumberFormat('#,##0.00', 'en_IN');
    return '\u20b9${formatter.format(value)}';
  }

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  String _formatMonthYear(DateTime date) => DateFormat('MMM yyyy').format(date);

  String _ageLabel(DateTime? dateOfBirth) {
    if (dateOfBirth == null) return '-';

    final now = DateTime.now();
    int months = (now.year - dateOfBirth.year) * 12 + now.month - dateOfBirth.month;
    if (now.day < dateOfBirth.day) months--;
    if (months < 0) months = 0;

    final years = months ~/ 12;
    final remainingMonths = months % 12;

    if (years == 0) return '$remainingMonths Month${remainingMonths == 1 ? '' : 's'}';
    if (remainingMonths == 0) return '$years Year${years == 1 ? '' : 's'}';
    return '$years Year${years == 1 ? '' : 's'} $remainingMonths Month${remainingMonths == 1 ? '' : 's'}';
  }

  String _safeFileName(PalaiCustomer customer) {
    final raw = 'ProgressReport_${customer.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_');
    return '$cleaned.pdf';
  }
}