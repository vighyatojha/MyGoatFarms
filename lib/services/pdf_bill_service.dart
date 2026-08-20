import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/palai_models.dart';

/// PDF generator for Palai monthly reports and final check-out reports.
///
/// The supplied Monthly Report.pdf is used as the visual reference:
/// header -> customer/summary cards -> goat details -> previous/current
/// photos -> weight/gain -> health update -> billing -> payment details ->
/// thank-you -> terms -> important notes/signature.
///
/// Historical health/monthly data is passed through the report data classes
/// below. This service deliberately does not invent Firestore history.
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
  // NEW: FINAL REPORT WITH ALL MONTHS.
  // ---------------------------------------------------------------------------

  Future<Uint8List> buildFinalCheckoutReport({
    required FinalCheckoutReportData report,
  }) async {
    final doc = pw.Document();

    // Overview page.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        header: (_) => _header(
          report.billSettings,
          'FINAL CHECK-OUT REPORT',
          right: 'Report ID: ${report.reportId}',
          period: _range(report.checkInDate, report.checkOutDate),
        ),
        footer: (c) => _footer(report.billSettings, c.pageNumber, c.pagesCount),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _card('CUSTOMER DETAILS', [
                  ['Customer Name', report.customerName],
                  ['Mobile Number', _dash(report.customerMobile)],
                  ['Address', _dash(report.customerAddress)],
                  ['Package', _dash(report.packageName)],
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _card('SUMMARY', [
                  ['Total Goats', '${report.goats.length}'],
                  ['Total Final Weight', '${report.totalFinalWeight.toStringAsFixed(1)} kg'],
                  ['Total Weight Gain', '${report.totalWeightGain.toStringAsFixed(1)} kg'],
                  ['Boarding Period', _range(report.checkInDate, report.checkOutDate)],
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _card('CHECK-OUT OVERVIEW', [
                  ['Check-In', _fmt(report.checkInDate)],
                  ['Check-Out', _fmt(report.checkOutDate)],
                  ['Delivery', _dash(report.deliveryStatus)],
                  ['Health', _dash(report.finalHealthStatus)],
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          _card(
            'GOAT FINAL DETAILS',
            report.goats
                .map(
                  (g) => [
                '${g.goatCode} (${g.breed})',
                '${g.finalWeight.toStringAsFixed(1)} kg · Gain ${g.weightGain.toStringAsFixed(1)} kg · ${_rs(g.charges)}',
              ],
            )
                .toList(),
          ),
          pw.SizedBox(height: 10),
          _photoPair(
            'CHECK-IN / BEFORE PALAI',
            _image(report.beforeImage),
            'FINAL / AFTER PALAI',
            _image(report.afterImage),
          ),
        ],
      ),
    );

    // One or more pages per month, matching the supplied report structure.
    for (final month in report.months) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          header: (_) => _header(
            report.billSettings,
            'MONTHLY REPORT',
            right: 'Report ID: ${report.reportId}',
            period: month.monthLabel,
          ),
          footer: (c) => _footer(report.billSettings, c.pageNumber, c.pagesCount),
          build: (_) => [
            _card('MONTHLY UPDATE OVERVIEW', [
              ['Report Period', _range(month.periodStart, month.periodEnd)],
              ['Package', _dash(month.packageName)],
              ['Report Date', _fmt(month.reportDate)],
              ['Monthly Rate', _rs(month.monthlyCharge)],
            ]),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _card('GOAT DETAILS', [
                    ['Goat ID', month.goatCode],
                    ['Breed', month.breed],
                    ['Gender', _dash(month.gender)],
                    ['Color', _dash(month.color)],
                    ['Date of Join', _fmt(month.checkInDate)],
                    ['Monthly Rate', _rs(month.monthlyCharge)],
                  ]),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 4,
                  child: _photoPair(
                    'PREVIOUS MONTH',
                    _image(month.previousImage),
                    'CURRENT MONTH',
                    _image(month.currentImage),
                    compact: true,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 3,
                  child: _card('WEIGHT & GAIN', [
                    ['Previous Weight', '${month.previousWeight.toStringAsFixed(1)} kg'],
                    ['Current Weight', '${month.currentWeight.toStringAsFixed(1)} kg'],
                    ['Weight Gain', '${month.weightGain.toStringAsFixed(1)} kg'],
                  ]),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            _card('HEALTH UPDATE', [
              ['Health Status', _dash(month.healthStatus)],
              ['Vaccination', _dash(month.vaccination)],
              ['Deworming', _dash(month.deworming)],
              ['Hoof Cutting', _dash(month.hoofCutting)],
              ['Medicine Given', _dash(month.medicineGiven)],
              ['Doctor / Notes', _dash(month.healthNotes)],
            ]),
            if (month.additionalImages.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _gallery('ADDITIONAL MONTHLY PHOTOS', month.additionalImages),
            ],
            if (month.notes.trim().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _card('NOTES', [['Notes', month.notes]]),
            ],
          ],
        ),
      );
    }

    // Final billing page.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        header: (_) => _header(
          report.billSettings,
          'FINAL BILL SUMMARY',
          right: 'Report ID: ${report.reportId}',
          period: _range(report.checkInDate, report.checkOutDate),
        ),
        footer: (c) => _footer(report.billSettings, c.pageNumber, c.pagesCount),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: _card('BILL SUMMARY', [
                  ...report.goats.map(
                        (g) => ['${g.goatCode} - Palai Charges', _rs(g.charges)],
                  ),
                  ['Transportation', _rs(report.transport)],
                  ['Previous Balance', _rs(report.previousBalance)],
                  ['Discount', '- ${_rs(report.discount)}'],
                  ['TOTAL BILL', _rs(report.totalBill)],
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                flex: 3,
                child: _card('PAYMENT DETAILS', [
                  ['Total Bill', _rs(report.totalBill)],
                  ['Paid Amount', _rs(report.paidAmount)],
                  ['Pending Amount', _rs(report.pendingAmount)],
                  ['Advance Before', _rs(report.advanceBefore)],
                  ['Advance Applied', _rs(report.advanceApplied)],
                  ['Advance After', _rs(report.advanceAfter)],
                  ['Payment Method', _dash(report.paymentMethod)],
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _thankYou(report.billSettings)),
            ],
          ),
          if (report.billSettings.upiId.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _upi(report.billSettings.upiId),
          ],
          if (report.billSettings.terms.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _terms(report.billSettings.terms),
          ],
          pw.SizedBox(height: 10),
          _importantNotes(
            report.importantNotes.isEmpty
                ? const [
              'Please check all details in the report.',
              'Keep this report for your records.',
              'All goats are under our care and supervision during the Palai period.',
            ]
                : report.importantNotes,
          ),
          if (report.signatureBytes != null) ...[
            pw.SizedBox(height: 8),
            _signature(report.signatureBytes!),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> shareFinalCheckoutReport({
    required FinalCheckoutReportData report,
  }) async {
    final bytes = await buildFinalCheckoutReport(report: report);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_safe(report.customerName)}_${_safe(report.reportId)}_final_report.pdf',
    );
  }

  Future<String> saveFinalCheckoutReportToDevice({
    required FinalCheckoutReportData report,
  }) async {
    final bytes = await buildFinalCheckoutReport(report: report);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/${_safe(report.customerName)}_${_safe(report.reportId)}_final_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
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

  pw.Widget _gallery(String title, List<Uint8List> bytes) {
    final images = bytes.map(_image).whereType<pw.MemoryImage>().toList();
    if (images.isEmpty) return pw.SizedBox();

    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
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
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Wrap(
            spacing: 6,
            runSpacing: 6,
            children: images
                .map(
                  (i) => pw.Container(
                width: 150,
                height: 100,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Image(i, fit: pw.BoxFit.contain),
              ),
            )
                .toList(),
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

  pw.Widget _importantNotes(List<String> notes) {
    return _card(
      'IMPORTANT NOTES',
      notes.asMap().entries.map((e) => ['${e.key + 1}', e.value]).toList(),
    );
  }

  pw.Widget _signature(Uint8List bytes) {
    final image = _image(bytes);
    if (image == null) return pw.SizedBox();
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 130,
        height: 65,
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Image(image, fit: pw.BoxFit.contain),
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

// ============================================================================
// DATA PASSED TO THE FINAL REPORT.
// ============================================================================

class FinalCheckoutReportData {
  final String reportId;
  final String customerName;
  final String customerMobile;
  final String customerAddress;
  final String packageName;

  final DateTime checkInDate;
  final DateTime checkOutDate;
  final String deliveryStatus;
  final String finalHealthStatus;

  final List<FinalGoatReportData> goats;
  final List<MonthlyGoatReportData> months;

  final double transport;
  final double previousBalance;
  final double discount;
  final double totalBill;
  final double paidAmount;
  final double pendingAmount;

  final double advanceBefore;
  final double advanceApplied;
  final double advanceAfter;
  final String paymentMethod;

  final Uint8List? beforeImage;
  final Uint8List? afterImage;
  final Uint8List? signatureBytes;

  final List<String> importantNotes;
  final BillSettings billSettings;

  const FinalCheckoutReportData({
    required this.reportId,
    required this.customerName,
    this.customerMobile = '',
    this.customerAddress = '',
    this.packageName = '',
    required this.checkInDate,
    required this.checkOutDate,
    this.deliveryStatus = '',
    this.finalHealthStatus = '',
    this.goats = const [],
    this.months = const [],
    this.transport = 0,
    this.previousBalance = 0,
    this.discount = 0,
    this.totalBill = 0,
    this.paidAmount = 0,
    this.pendingAmount = 0,
    this.advanceBefore = 0,
    this.advanceApplied = 0,
    this.advanceAfter = 0,
    this.paymentMethod = '',
    this.beforeImage,
    this.afterImage,
    this.signatureBytes,
    this.importantNotes = const [],
    required this.billSettings,
  });

  double get totalFinalWeight =>
      goats.fold(0, (sum, goat) => sum + goat.finalWeight);

  double get totalWeightGain =>
      goats.fold(0, (sum, goat) => sum + goat.weightGain);
}

class FinalGoatReportData {
  final String goatCode;
  final String breed;
  final String gender;
  final String color;
  final double checkInWeight;
  final double finalWeight;
  final String healthStatus;
  final String deliveryStatus;
  final double charges;

  const FinalGoatReportData({
    required this.goatCode,
    required this.breed,
    this.gender = '',
    this.color = '',
    required this.checkInWeight,
    required this.finalWeight,
    this.healthStatus = '',
    this.deliveryStatus = '',
    this.charges = 0,
  });

  double get weightGain => finalWeight - checkInWeight;
}

class MonthlyGoatReportData {
  final String monthLabel;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime reportDate;

  final String goatCode;
  final String breed;
  final String gender;
  final String color;
  final DateTime checkInDate;

  final double previousWeight;
  final double currentWeight;
  final double monthlyCharge;

  final String packageName;
  final String healthStatus;
  final String vaccination;
  final String deworming;
  final String hoofCutting;
  final String medicineGiven;
  final String healthNotes;

  final Uint8List? previousImage;
  final Uint8List? currentImage;
  final List<Uint8List> additionalImages;

  final String notes;

  const MonthlyGoatReportData({
    required this.monthLabel,
    required this.periodStart,
    required this.periodEnd,
    required this.reportDate,
    required this.goatCode,
    required this.breed,
    this.gender = '',
    this.color = '',
    required this.checkInDate,
    this.previousWeight = 0,
    this.currentWeight = 0,
    this.monthlyCharge = 0,
    this.packageName = '',
    this.healthStatus = 'Not recorded',
    this.vaccination = '',
    this.deworming = '',
    this.hoofCutting = '',
    this.medicineGiven = '',
    this.healthNotes = '',
    this.previousImage,
    this.currentImage,
    this.additionalImages = const [],
    this.notes = '',
  });

  double get weightGain => currentWeight - previousWeight;
}
