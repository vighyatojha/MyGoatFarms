import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/sale_model.dart';

class SaleReceiptPdfService {
  SaleReceiptPdfService._();

  static final SaleReceiptPdfService instance =
  SaleReceiptPdfService._();

  Future<Uint8List> generatePdf({
    required Sale sale,
    required BillSettings billSettings,
    Uint8List? farmLogo,
  }) async {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    // Profile image is the primary logo.
    // Bill Settings logo remains a fallback.
    final logo = _safeMemoryImage(
      farmLogo ?? billSettings.billLogo,
    );

    final farmName = _farmName(billSettings);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          22,
          18,
          22,
          18,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _fullHeader(
                billSettings,
                logo,
              ),

              pw.SizedBox(height: 5),

              _receiptTitle(sale),

              pw.SizedBox(height: 5),

              _infoBar(sale),

              pw.SizedBox(height: 6),

              _sectionBanner(
                number: '1',
                title: 'Customer Details',
                subtitle: 'Buyer information recorded with this sale',
              ),

              pw.SizedBox(height: 3),

              _customerCard(sale),

              pw.SizedBox(height: 5),

              _sectionBanner(
                number: '2',
                title: 'Goat Sale Details',
                subtitle:
                '${sale.goatIds.length} goat${sale.goatIds.length == 1 ? '' : 's'} included in this receipt',
              ),

              pw.SizedBox(height: 3),

              _goatDetails(sale),

              pw.SizedBox(height: 5),

              _sectionBanner(
                number: '3',
                title: 'Price Calculation',
                subtitle:
                'Goat sale, transportation and customer total',
              ),

              pw.SizedBox(height: 3),

              _priceCalculation(sale),

              pw.SizedBox(height: 5),

              _transactionDetails(sale),

              pw.SizedBox(height: 5),

              _paymentSummary(sale),

              pw.SizedBox(height: 5),

              _closingNote(
                sale,
                farmName,
              ),

              pw.Spacer(),

              _footer(
                billSettings: billSettings,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> preview({
    required Sale sale,
    required BillSettings billSettings,
    Uint8List? farmLogo,
  }) async {
    final bytes = await generatePdf(
      sale: sale,
      billSettings: billSettings,
      farmLogo: farmLogo,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _fileName(sale),
    );
  }

  Future<void> share({
    required Sale sale,
    required BillSettings billSettings,
    Uint8List? farmLogo,
  }) async {
    final bytes = await generatePdf(
      sale: sale,
      billSettings: billSettings,
      farmLogo: farmLogo,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _fileName(sale),
    );
  }

  Future<String> save({
    required Sale sale,
    required BillSettings billSettings,
    Uint8List? farmLogo,
  }) async {
    final bytes = await generatePdf(
      sale: sale,
      billSettings: billSettings,
      farmLogo: farmLogo,
    );

    final directory = await getApplicationDocumentsDirectory();

    final file = File(
      '${directory.path}/${_fileName(sale)}',
    );

    await file.writeAsBytes(bytes);

    return file.path;
  }

  pw.MemoryImage? _safeMemoryImage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

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
      height: 72,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // STRICTLY CIRCULAR LOGO
          _farmLogo(
            logo,
            size: 62,
          ),

          pw.SizedBox(width: 12),

          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  farmName.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 21,
                    fontWeight: pw.FontWeight.bold,
                    color: darkGreen,
                  ),
                ),

                if (locality.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    locality,
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: darkGreen,
                    ),
                  ),
                ],

                if (phone.isNotEmpty ||
                    address.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    [
                      if (phone.isNotEmpty) phone,
                      if (address.isNotEmpty) address,
                    ].join('  •  '),
                    maxLines: 1,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 7.2,
                      color: darkGreen,
                    ),
                  ),
                ],

                if (email.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    email,
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 6.8,
                      color: darkGreen,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Creates a TRUE circular image.
  ///
  /// The image itself is placed inside a square and clipped with ClipOval.
  /// BoxFit.cover ensures the image fills the circle instead of appearing
  /// rectangular or stretched.
  pw.Widget _farmLogo(
      pw.MemoryImage? image, {
        required double size,
      }) {
    return pw.Container(
      width: size,
      height: size,
      padding: const pw.EdgeInsets.all(2.5),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(
          color: PdfColors.green700,
          width: 1.8,
        ),
      ),
      child: pw.ClipOval(
        child: pw.SizedBox(
          width: size - 5,
          height: size - 5,
          child: image != null
              ? pw.Image(
            image,
            width: size - 5,
            height: size - 5,
            fit: pw.BoxFit.cover,
          )
              : pw.Container(
            color: PdfColors.green50,
            alignment: pw.Alignment.center,
            child: pw.Text(
              'GOAT',
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TITLE
  // ---------------------------------------------------------------------------

  pw.Widget _receiptTitle(Sale sale) {
    final statusColor = _statusColor(sale);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.6,
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SALE RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  _statusLabel(sale),
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: pw.BoxDecoration(
              color: statusColor,
              borderRadius: const pw.BorderRadius.all(
                pw.Radius.circular(12),
              ),
            ),
            child: pw.Text(
              sale.id,
              style: const pw.TextStyle(
                fontSize: 6,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INFO BAR
  // ---------------------------------------------------------------------------

  pw.Widget _infoBar(Sale sale) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(5),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.6,
        ),
      ),
      child: pw.Row(
        children: [
          _infoItem(
            'Customer',
            sale.customerName,
          ),
          _infoItem(
            'Date of Sale',
            sale.createdAt == null
                ? '-'
                : DateFormat(
              'dd MMM yyyy',
            ).format(sale.createdAt!),
          ),
          _infoItem(
            'No. of Goats',
            '${sale.goatIds.length}',
          ),
        ],
      ),
    );
  }

  pw.Widget _infoItem(
      String label,
      String value,
      ) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 5.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green800,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            value.isEmpty ? '-' : value,
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 6.5,
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION
  // ---------------------------------------------------------------------------

  pw.Widget _sectionBanner({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(6),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.6,
        ),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 19,
            height: 19,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              color: PdfColors.green700,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              number,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                pw.Text(
                  subtitle,
                  maxLines: 1,
                  style: const pw.TextStyle(
                    fontSize: 5.2,
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

  // ---------------------------------------------------------------------------
  // CUSTOMER
  // ---------------------------------------------------------------------------

  pw.Widget _customerCard(Sale sale) {
    return _card(
      child: pw.Column(
        children: [
          _detailRow(
            'Customer Name',
            sale.customerName,
          ),
          _detailRow(
            'Mobile',
            sale.mobile,
          ),
          if (sale.address.trim().isNotEmpty)
            _detailRow(
              'Address',
              sale.address,
            ),
          _detailRow(
            'Customer ID',
            sale.customerId,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GOAT DETAILS
  // ---------------------------------------------------------------------------

  pw.Widget _goatDetails(Sale sale) {
    return _card(
      child: pw.Column(
        children: [
          _detailRow(
            'Goat ID(s)',
            sale.goatIds.isEmpty
                ? '-'
                : sale.goatIds.join(', '),
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

  // ---------------------------------------------------------------------------
  // PRICE
  // ---------------------------------------------------------------------------

  pw.Widget _priceCalculation(Sale sale) {
    return _card(
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          if (sale.hasPickupSettlement) ...[
            _calculationRow(
              'Pickup Weight',
              '${sale.pickupWeight!.toStringAsFixed(2)} kg',
            ),
            _calculationRow(
              'Booking Rate / kg',
              _currency(
                sale.bookingPricePerKg ??
                    sale.sellingPricePerKg,
              ),
              note:
              'Fixed at booking time, not today\'s rate',
            ),
          ] else ...[
            _calculationRow(
              'Selling Weight',
              '${sale.sellingWeight.toStringAsFixed(2)} kg',
            ),
            _calculationRow(
              'Selling Price / kg',
              _currency(
                sale.sellingPricePerKg,
              ),
            ),
          ],

          pw.SizedBox(height: 1),

          pw.Divider(
            color: PdfColors.green200,
            height: 4,
          ),

          _calculationRow(
            'Goat Sale',
            _currency(sale.billGoatSale),
          ),

          if (sale.billHoldingCharges > 0)
            _calculationRow(
              'Holding Charges',
              _currency(sale.billHoldingCharges),
              note:
              '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days × '
                  '${_currency(sale.holdingChargePerDay ?? 0)} / day',
            ),

          if (sale.billTransportCharges > 0)
            _calculationRow(
              'Transportation',
              _currency(sale.billTransportCharges),
            ),

          pw.SizedBox(height: 1),

          pw.Divider(
            color: PdfColors.green300,
            height: 4,
          ),

          _calculationRow(
            'Customer Total',
            _currency(sale.billCustomerTotal),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRANSACTION
  // ---------------------------------------------------------------------------

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
            DateFormat(
              'dd MMM yyyy',
            ).format(sale.expectedDeliveryDate!),
          ),
        );
      }

      if (sale.deliveryCompletedAt != null) {
        rows.add(
          _detailRow(
            'Delivery Completed',
            DateFormat(
              'dd MMM yyyy, hh:mm a',
            ).format(sale.deliveryCompletedAt!),
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
          _currency(
            sale.bookingPricePerKg ?? 0,
          ),
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

    if (sale.isPalaiTransfer) {
      rows.add(
        _detailRow(
          'Transfer Date',
          sale.transferDate == null
              ? '-'
              : DateFormat(
            'dd MMM yyyy',
          ).format(sale.transferDate!),
        ),
      );

      if ((sale.palaiPackage ?? '').trim().isNotEmpty) {
        rows.add(
          _detailRow(
            'Palai Package',
            sale.palaiPackage!,
          ),
        );
      }

      if (sale.monthlyPalaiCharge != null) {
        rows.add(
          _detailRow(
            'Monthly Palai Charge',
            _currency(
              sale.monthlyPalaiCharge!,
            ),
          ),
        );
      }
    }

    if (rows.isEmpty) {
      return _card(
        child: _detailRow(
          'Transaction Type',
          _deliveryTypeLabel(sale),
        ),
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
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green900,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          ...rows,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PAYMENT
  // ---------------------------------------------------------------------------

  pw.Widget _paymentSummary(Sale sale) {
    final paid = sale.billAmountPaid;
    final total = sale.billCustomerTotal;
    final remaining = sale.billBalanceDue;

    // The receipt is ONE fixed A4 page (pw.Page, not MultiPage), so an
    // unbounded payment list would overflow it and fail PDF generation.
    // List only the most recent balance payments and fold anything older
    // into a single row; the totals below stay exact either way.
    const maxListedPayments = 2;

    final payments = sale.payments;
    final hiddenCount = payments.length > maxListedPayments
        ? payments.length - maxListedPayments
        : 0;
    final earlier = payments.take(hiddenCount).toList();
    final listed = payments.skip(hiddenCount).toList();
    final earlierTotal = earlier.fold<double>(
      0.0,
          (sum, payment) => sum + payment.amount,
    );

    final initialMethod = (sale.paymentMethod ?? '').trim();
    final initialLabel =
    sale.billInitialPayment > 0 && initialMethod.isNotEmpty
        ? '${sale.billInitialPaymentLabel} ($initialMethod)'
        : sale.billInitialPaymentLabel;

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
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(7),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
        ),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'PAYMENT SUMMARY',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: statusColor,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(10),
                  ),
                ),
                child: pw.Text(
                  status,
                  style: const pw.TextStyle(
                    fontSize: 5.5,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 3),

          pw.Divider(
            color: PdfColors.green200,
            height: 3,
          ),

          _calculationRow(
            'Customer Total',
            _currency(total),
          ),

          if (payments.isEmpty)
            _calculationRow(
              'Amount Paid',
              _currency(paid),
            )
          else ...[
            _calculationRow(
              initialLabel,
              _currency(sale.billInitialPayment),
            ),
            if (earlier.isNotEmpty)
              _calculationRow(
                'Earlier balance payments (${earlier.length})',
                _currency(earlierTotal),
              ),
            for (final payment in listed)
              _calculationRow(
                _balancePaymentLabel(payment),
                _currency(payment.amount),
              ),
            _calculationRow(
              'Total Paid',
              _currency(paid),
            ),
          ],

          pw.Divider(
            color: PdfColors.green300,
            height: 3,
          ),

          _calculationRow(
            'Remaining Amount',
            _currency(remaining),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  /// One compact line per balance payment: date and method are folded
  /// into the label so no extra note line is needed on the fixed page.
  String _balancePaymentLabel(SalePayment payment) {
    final method = payment.method.trim();

    return 'Balance payment · '
        '${DateFormat('dd MMM yyyy').format(payment.date)}'
        '${method.isEmpty ? '' : ' · $method'}';
  }

  // ---------------------------------------------------------------------------
  // CLOSING
  // ---------------------------------------------------------------------------

  pw.Widget _closingNote(
      Sale sale,
      String farmName,
      ) {
    final text =
    sale.isBooking &&
        sale.status != Sale.statusDeliveryCompleted
        ? 'This is a booking receipt. Final holding charges are based on the recorded holding period when delivery is completed.'
        : sale.isWaitForDelivery &&
        sale.status != Sale.statusPickupCompleted
        ? 'This sale is awaiting delivery. Final settlement uses the booking-time price and the pickup weight recorded at completion.'
        : 'This receipt is generated from the sale record saved in ${farmName.trim().isEmpty ? 'the farm' : farmName}.';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.green900,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(6),
        ),
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        maxLines: 2,
        style: const pw.TextStyle(
          fontSize: 5.8,
          color: PdfColors.white,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMMON CARD
  // ---------------------------------------------------------------------------

  pw.Widget _card({
    required pw.Widget child,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(6),
        ),
        border: pw.Border.all(
          color: PdfColors.green200,
          width: 0.6,
        ),
      ),
      child: child,
    );
  }

  pw.Widget _detailRow(
      String label,
      String value,
      ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 3,
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 6.2,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              value.trim().isEmpty ? '-' : value,
              textAlign: pw.TextAlign.right,
              maxLines: 2,
              style: pw.TextStyle(
                fontSize: 6.5,
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
      padding: const pw.EdgeInsets.only(
        bottom: 3,
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: emphasized ? 7.5 : 6.6,
                    fontWeight: emphasized
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: emphasized
                        ? PdfColors.grey900
                        : PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: emphasized ? 8 : 6.8,
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
              child: pw.Text(
                note,
                maxLines: 1,
                style: const pw.TextStyle(
                  fontSize: 5.2,
                  color: PdfColors.grey600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _statusLabel(Sale sale) {
    if (sale.isDeliverNow) {
      return 'DELIVERED & SOLD';
    }

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

    if (sale.isPalaiTransfer) {
      return 'TRANSFERRED TO PALAI';
    }

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

    if (sale.isPalaiTransfer) {
      return PdfColors.blue700;
    }

    return PdfColors.green700;
  }

  String _deliveryTypeLabel(Sale sale) {
    if (sale.isDeliverNow) return 'Deliver Now';
    if (sale.isBooking) return 'Booking / Holding';
    if (sale.isWaitForDelivery) return 'Wait for Delivery';
    if (sale.isPalaiTransfer) return 'Transfer to Palai';
    return sale.deliveryType;
  }

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

    if (address.isEmpty) {
      return '';
    }

    final parts = address
        .split(RegExp(r'[,|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return parts.isEmpty ? '' : parts.last;
  }

  String _fileName(Sale sale) {
    final id = sale.id.trim().isEmpty
        ? 'Sale'
        : sale.id.trim();

    final date = DateFormat(
      'yyyyMMdd',
    ).format(
      sale.createdAt ?? DateTime.now(),
    );

    final cleaned = id.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );

    return 'SaleReceipt_${cleaned}_$date.pdf';
  }

  pw.Widget _footer({
    required BillSettings billSettings,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(
        top: 3,
      ),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey300,
            width: 0.4,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            _farmName(billSettings),
            style: const pw.TextStyle(
              fontSize: 5,
              color: PdfColors.grey600,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'Sale Receipt',
            style: const pw.TextStyle(
              fontSize: 5,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
}