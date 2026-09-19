import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/sale_model.dart';

/// Standalone PDF generator for Trading > Goat Sale receipts.
///
/// This service intentionally does NOT import or depend on the customer
/// progress-report PDF service. It only reuses the same visual language:
/// farm logo, farm name, locality/contact line, green section banners and
/// compact information bars.
class SaleReceiptPdfService {
  SaleReceiptPdfService._();

  static final SaleReceiptPdfService instance = SaleReceiptPdfService._();

  Future<Uint8List> generatePdf({
    required Sale sale,
    required BillSettings billSettings,
  }) async {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    final logo = _safeMemoryImage(billSettings.billLogo);
    final farmName = _farmName(billSettings);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 18, 24, 22),
        header: (context) => _pageHeader(
          context: context,
          billSettings: billSettings,
          logo: logo,
        ),
        footer: (context) => _footer(
          billSettings: billSettings,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
        ),
        // IMPORTANT: this callback builds the BODY, and the pdf package
        // hands it a Context that has no page yet. Reading
        // `context.pageNumber` / `context.pagesCount` here throws
        // "Null check operator used on a null value". Those are only valid
        // inside `header:` and `footer:` (which is where they are used).
        //
        // The body list is built exactly once, so the title and info bar
        // below already appear only once, at the top of the first page —
        // no page-number check is needed.
        build: (_) => [
          _receiptTitle(sale),
          pw.SizedBox(height: 8),
          _infoBar(sale),
          pw.SizedBox(height: 10),
          _sectionBanner(
            number: '1',
            title: 'Customer Details',
            subtitle: 'Buyer information recorded with this sale',
          ),
          pw.SizedBox(height: 6),
          _customerCard(sale),
          pw.SizedBox(height: 10),
          _sectionBanner(
            number: '2',
            title: 'Goat Sale Details',
            subtitle: '${sale.goatIds.length} goat${sale.goatIds.length == 1 ? '' : 's'} included in this receipt',
          ),
          pw.SizedBox(height: 6),
          _goatDetails(sale),
          pw.SizedBox(height: 10),
          _sectionBanner(
            number: '3',
            title: 'Price Calculation',
            subtitle: 'Transparent calculation of the sale amount',
          ),
          pw.SizedBox(height: 6),
          _priceCalculation(sale),
          pw.SizedBox(height: 10),
          _transactionDetails(sale),
          pw.SizedBox(height: 10),
          _paymentSummary(sale),
          pw.SizedBox(height: 10),
          _closingNote(sale, farmName),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> preview({
    required Sale sale,
    required BillSettings billSettings,
  }) async {
    final bytes = await generatePdf(
      sale: sale,
      billSettings: billSettings,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _fileName(sale),
    );
  }

  Future<void> share({
    required Sale sale,
    required BillSettings billSettings,
  }) async {
    final bytes = await generatePdf(
      sale: sale,
      billSettings: billSettings,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _fileName(sale),
    );
  }

  Future<String> save({
    required Sale sale,
    required BillSettings billSettings,
  }) async {
    final bytes = await generatePdf(
      sale: sale,
      billSettings: billSettings,
    );

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_fileName(sale)}');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  pw.MemoryImage? _safeMemoryImage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  pw.Widget _pageHeader({
    required pw.Context context,
    required BillSettings billSettings,
    required pw.MemoryImage? logo,
  }) {
    if (context.pageNumber == 1) {
      return pw.Column(
        children: [
          _fullHeader(billSettings, logo),
          pw.SizedBox(height: 5),
        ],
      );
    }

    return pw.Column(
      children: [
        _minorHeader(billSettings, logo),
        pw.SizedBox(height: 5),
      ],
    );
  }

  pw.Widget _fullHeader(
      BillSettings settings,
      pw.MemoryImage? logo,
      ) {
    final darkGreen = PdfColor.fromHex('#1B5E20');
    final farmName = _farmName(settings);
    final locality = _locality(settings);
    final phone = settings.phone.trim();
    final address = settings.address.trim();
    final email = settings.email.trim();

    return pw.SizedBox(
      width: double.infinity,
      height: 96,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 2,
            top: 2,
            child: _farmLogo(logo, size: 82),
          ),
          pw.Positioned(
            left: 72,
            right: 2,
            top: 2,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  farmName.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: darkGreen,
                  ),
                ),
                if (locality.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    locality,
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 11.5,
                      fontWeight: pw.FontWeight.bold,
                      color: darkGreen,
                    ),
                  ),
                ],
                if (phone.isNotEmpty || address.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Wrap(
                    alignment: pw.WrapAlignment.center,
                    children: [
                      if (phone.isNotEmpty)
                        pw.Text(
                          phone,
                          maxLines: 1,
                          style: pw.TextStyle(fontSize: 9.5, color: darkGreen),
                        ),
                      if (phone.isNotEmpty && address.isNotEmpty)
                        pw.SizedBox(width: 10),
                      if (address.isNotEmpty)
                        pw.Text(
                          address,
                          maxLines: 2,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(fontSize: 9.5, color: darkGreen),
                        ),
                    ],
                  ),
                ],
                if (email.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    email,
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 8.5, color: darkGreen),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _minorHeader(
      BillSettings settings,
      pw.MemoryImage? logo,
      ) {
    return pw.SizedBox(
      width: double.infinity,
      height: 28,
      child: pw.Row(
        children: [
          _farmLogo(logo, size: 22),
          pw.SizedBox(width: 7),
          pw.Expanded(
            child: pw.Text(
              _farmName(settings),
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

  pw.Widget _farmLogo(
      pw.MemoryImage? image, {
        required double size,
      }) {
    final border = size >= 40 ? 2.0 : 1.0;
    final padding = size >= 40 ? 3.0 : 1.5;
    final inner = size - ((border + padding) * 2);

    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(padding),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(
          color: PdfColors.green700,
          width: border,
        ),
      ),
      child: pw.ClipOval(
        child: image != null
            ? pw.Image(
          image,
          width: inner,
          height: inner,
          fit: pw.BoxFit.cover,
        )
            : pw.Container(
          color: PdfColors.green50,
          alignment: pw.Alignment.center,
          child: pw.Text(
            'GOAT',
            style: pw.TextStyle(
              fontSize: size >= 40 ? 8 : 4,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _receiptTitle(Sale sale) {
    final statusColor = _statusColor(sale);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SALE RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  _statusLabel(sale),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(
              color: statusColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
            ),
            child: pw.Text(
              sale.id,
              style: const pw.TextStyle(
                fontSize: 7,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _infoBar(Sale sale) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: pw.Row(
        children: [
          _infoItem('Customer', sale.customerName),
          _infoItem(
            'Date of Sale',
            sale.createdAt == null
                ? '-'
                : DateFormat('dd MMM yyyy').format(sale.createdAt!),
          ),
          _infoItem('No. of Goats', '${sale.goatIds.length}'),
        ],
      ),
    );
  }

  pw.Widget _infoItem(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 6.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green800,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value.isEmpty ? '-' : value,
            maxLines: 2,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionBanner({
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
            decoration: const pw.BoxDecoration(
              color: PdfColors.green700,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              number,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    fontSize: 6.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _customerCard(Sale sale) {
    return _card(
      child: pw.Column(
        children: [
          _detailRow('Customer Name', sale.customerName),
          _detailRow('Mobile', sale.mobile),
          if (sale.address.trim().isNotEmpty)
            _detailRow('Address', sale.address),
          _detailRow('Customer ID', sale.customerId),
        ],
      ),
    );
  }

  pw.Widget _goatDetails(Sale sale) {
    return _card(
      child: pw.Column(
        children: [
          _detailRow(
            'Goat ID(s)',
            sale.goatIds.isEmpty ? '-' : sale.goatIds.join(', '),
          ),
          _detailRow(
            'Selling Weight',
            '${sale.sellingWeight.toStringAsFixed(2)} kg',
          ),
          _detailRow(
            'Selling Price / kg',
            _currency(sale.sellingPricePerKg),
          ),
          _detailRow(
            'Delivery Type',
            _deliveryTypeLabel(sale),
          ),
        ],
      ),
    );
  }

  pw.Widget _priceCalculation(Sale sale) {
    final holding = sale.totalHoldingCharges ?? 0;
    final isFinalBooking =
        sale.isBooking && sale.status == Sale.statusDeliveryCompleted;
    final isFinalPickup =
        sale.isWaitForDelivery && sale.status == Sale.statusPickupCompleted;

    final baseAmount = sale.totalSaleAmount;
    final finalTotal = _round2(
      isFinalBooking
          ? (sale.finalAmountAfterHolding ?? baseAmount + holding)
          : isFinalPickup
          ? (sale.finalPriceAfterPickup ?? baseAmount)
          : baseAmount + (sale.isBooking ? holding : 0),
    );

    return _card(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _calculationRow(
            'Selling Weight',
            '${sale.sellingWeight.toStringAsFixed(2)} kg',
          ),
          _calculationRow(
            'Selling Price / kg',
            _currency(sale.sellingPricePerKg),
          ),
          pw.SizedBox(height: 3),
          pw.Divider(color: PdfColors.green200),
          _calculationRow(
            'Goat Sale Amount',
            _currency(baseAmount),
          ),
          if (sale.isBooking && holding > 0)
            _calculationRow(
              'Holding Charges',
              _currency(holding),
              note:
              '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days × ${_currency(sale.holdingChargePerDay ?? 0)} / day',
            ),
          if (isFinalPickup)
            _calculationRow(
              'Pickup Weight',
              '${(sale.pickupWeight ?? sale.sellingWeight).toStringAsFixed(2)} kg',
              note:
              'Final price uses booking rate ${_currency(sale.bookingPricePerKg ?? sale.sellingPricePerKg)} / kg',
            ),
          pw.SizedBox(height: 3),
          pw.Divider(color: PdfColors.green300),
          _calculationRow(
            isFinalBooking ? 'Final Amount After Holding' : 'Total Sale Amount',
            _currency(finalTotal),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _transactionDetails(Sale sale) {
    final rows = <pw.Widget>[];

    if (sale.isBooking) {
      rows.add(
        _detailRow(
          'Booking Amount',
          _currency(sale.bookingAmount ?? 0),
        ),
      );
      rows.add(
        _detailRow(
          'Holding Period',
          '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days',
        ),
      );
      rows.add(
        _detailRow(
          'Holding Rate',
          '${_currency(sale.holdingChargePerDay ?? 0)} / day',
        ),
      );
      if (sale.expectedDeliveryDate != null) {
        rows.add(
          _detailRow(
            'Expected Delivery',
            DateFormat('dd MMM yyyy').format(sale.expectedDeliveryDate!),
          ),
        );
      }
      if (sale.deliveryCompletedAt != null) {
        rows.add(
          _detailRow(
            'Delivery Completed',
            DateFormat('dd MMM yyyy, hh:mm a')
                .format(sale.deliveryCompletedAt!),
          ),
        );
      }
    }

    if (sale.isWaitForDelivery) {
      rows.add(
        _detailRow(
          'Booking Weight',
          '${(sale.bookingWeight ?? 0).toStringAsFixed(2)} kg',
        ),
      );
      rows.add(
        _detailRow(
          'Booking Price / kg',
          _currency(sale.bookingPricePerKg ?? 0),
        ),
      );
      if (sale.pickupWeight != null) {
        rows.add(
          _detailRow(
            'Pickup Weight',
            '${sale.pickupWeight!.toStringAsFixed(2)} kg',
          ),
        );
      }
    }

    if (sale.transportCost != null) {
      rows.add(
        _detailRow(
          'Transport Cost',
          _currency(sale.transportCost!),
        ),
      );
    }

    if (sale.isPalaiTransfer) {
      rows.add(
        _detailRow('Transfer Date', sale.transferDate == null
            ? '-'
            : DateFormat('dd MMM yyyy').format(sale.transferDate!)),
      );
      if ((sale.palaiPackage ?? '').trim().isNotEmpty) {
        rows.add(_detailRow('Palai Package', sale.palaiPackage!));
      }
      if (sale.monthlyPalaiCharge != null) {
        rows.add(
          _detailRow(
            'Monthly Palai Charge',
            _currency(sale.monthlyPalaiCharge!),
          ),
        );
      }
    }

    if (rows.isEmpty) {
      return _card(
        child: _detailRow('Transaction Type', _deliveryTypeLabel(sale)),
      );
    }

    return _card(
      child: pw.Column(
        children: [
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              'TRANSACTION DETAILS',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green900,
              ),
            ),
          ),
          pw.SizedBox(height: 5),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _paymentSummary(Sale sale) {
    final paid = _paid(sale);
    final total = _finalPayable(sale);
    final rawRemaining = _round2(total - paid);
    final remaining = rawRemaining <= 0 ? 0.0 : rawRemaining;
    final status = remaining <= 0
        ? 'PAID'
        : paid > 0
        ? 'PARTIALLY PAID'
        : 'PENDING';

    final statusColor = status == 'PAID'
        ? PdfColors.green800
        : status == 'PARTIALLY PAID'
        ? PdfColors.orange800
        : PdfColors.red800;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.green200),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'PAYMENT SUMMARY',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: statusColor,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(12),
                  ),
                ),
                child: pw.Text(
                  status,
                  style: const pw.TextStyle(
                    fontSize: 6.5,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.green200),
          _calculationRow('Final Payable', _currency(total)),
          _calculationRow('Amount Paid', _currency(paid)),
          pw.SizedBox(height: 2),
          pw.Divider(color: PdfColors.green300),
          _calculationRow(
            'Remaining Amount',
            _currency(remaining),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _closingNote(Sale sale, String farmName) {
    final text = sale.isBooking && sale.status != Sale.statusDeliveryCompleted
        ? 'This is a booking receipt. Final holding charges are based on the recorded holding period when delivery is completed.'
        : sale.isWaitForDelivery &&
        sale.status != Sale.statusPickupCompleted
        ? 'This sale is awaiting delivery. Final settlement uses the booking-time price and the pickup weight recorded at completion.'
        : 'This receipt is generated from the sale record saved in ${farmName.trim().isEmpty ? 'the farm' : farmName}.';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(
          fontSize: 7,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _card({required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: PdfColors.green200, width: 0.7),
      ),
      child: child,
    );
  }

  pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 7.2,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              value.trim().isEmpty ? '-' : value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _calculationRow(
      String label,
      String value, {
        String? note,
        bool emphasized = false,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: emphasized ? 9.5 : 7.8,
                    fontWeight: emphasized
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: emphasized
                        ? PdfColors.grey900
                        : PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: emphasized ? 10 : 8,
                  fontWeight: pw.FontWeight.bold,
                  color: emphasized
                      ? PdfColors.green900
                      : PdfColors.grey900,
                ),
              ),
            ],
          ),
          if (note != null)
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: pw.Text(
                  note,
                  style: const pw.TextStyle(
                    fontSize: 6.2,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Rounds to 2 decimals so floating-point drift (e.g.
  /// 27456.000000000004) can never flip "PAID" to "PARTIALLY PAID".
  double _round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    final nudge = value >= 0 ? 1e-9 : -1e-9;
    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  double _paid(Sale sale) {
    if (sale.isDeliverNow) return _round2(sale.amountReceived ?? 0);
    if (sale.isBooking) return _round2(sale.bookingAmount ?? 0);
    if (sale.isWaitForDelivery) {
      return _round2(sale.bookingAdvanceAmount ?? 0);
    }
    return 0;
  }

  double _finalPayable(Sale sale) {
    if (sale.isBooking &&
        sale.status == Sale.statusDeliveryCompleted) {
      return _round2(
        sale.finalAmountAfterHolding ?? sale.totalSaleAmount,
      );
    }

    if (sale.isWaitForDelivery &&
        sale.status == Sale.statusPickupCompleted) {
      return _round2(sale.finalPriceAfterPickup ?? sale.totalSaleAmount);
    }

    return _round2(
      sale.totalSaleAmount +
          (sale.isBooking ? (sale.totalHoldingCharges ?? 0) : 0),
    );
  }

  String _statusLabel(Sale sale) {
    if (sale.isDeliverNow) return 'DELIVERED & SOLD';
    if (sale.isBooking) {
      return sale.status == Sale.statusDeliveryCompleted
          ? 'DELIVERY COMPLETED'
          : 'BOOKED / ON HOLD';
    }
    if (sale.isWaitForDelivery) {
      return sale.status == Sale.statusPickupCompleted
          ? 'PICKUP COMPLETED'
          : 'WAITING FOR DELIVERY';
    }
    if (sale.isPalaiTransfer) return 'TRANSFERRED TO PALAI';
    return sale.status.toUpperCase();
  }

  PdfColor _statusColor(Sale sale) {
    if (sale.status == Sale.statusSold ||
        sale.status == Sale.statusDeliveryCompleted ||
        sale.status == Sale.statusPickupCompleted) {
      return PdfColors.green700;
    }
    if (sale.isBooking || sale.isWaitForDelivery) {
      return PdfColors.orange700;
    }
    if (sale.isPalaiTransfer) return PdfColors.blue700;
    return PdfColors.green700;
  }

  String _deliveryTypeLabel(Sale sale) {
    if (sale.isDeliverNow) return 'Deliver Now';
    if (sale.isBooking) return 'Booking / Holding';
    if (sale.isWaitForDelivery) return 'Wait for Delivery';
    if (sale.isPalaiTransfer) return 'Transfer to Palai';
    return sale.deliveryType;
  }

  /// Same formatter as the on-screen receipt, so both show identical
  /// figures (Indian digit grouping, e.g. ₹1,00,000.00).
  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _farmName(BillSettings settings) {
    return settings.businessName.trim().isEmpty
        ? 'My Goat Farms'
        : settings.businessName.trim();
  }

  String _locality(BillSettings settings) {
    final address = settings.address.trim();
    if (address.isEmpty) return '';
    final parts = address
        .split(RegExp(r'[,|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.last;
  }

  String _fileName(Sale sale) {
    final id = sale.id.trim().isEmpty ? 'Sale' : sale.id.trim();
    final date = DateFormat('yyyyMMdd').format(
      sale.createdAt ?? DateTime.now(),
    );
    final cleaned = id.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return 'SaleReceipt_${cleaned}_$date.pdf';
  }

  pw.Widget _footer({
    required BillSettings billSettings,
    required int pageNumber,
    required int totalPages,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey300,
            width: 0.5,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            _farmName(billSettings),
            style: const pw.TextStyle(
              fontSize: 6,
              color: PdfColors.grey600,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'Page $pageNumber of $totalPages',
            style: const pw.TextStyle(
              fontSize: 6,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
}