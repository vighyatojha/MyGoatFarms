import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer_ledger_entry_model.dart';
import '../models/farm_model.dart';
import '../models/palai_models.dart';

/// Generates and shares a single customer's Ledger statement as a PDF —
/// mirrors the structure/format of [MonthlyBillPdfService] so every PDF
/// the app produces looks and feels consistent, but is built around a
/// list of [CustomerLedgerEntry] rows (bills + payments) instead of a
/// single bill.
///
/// This is purely a read/export helper: it never recalculates or writes
/// anything back — the current Outstanding/Advance shown always comes
/// straight from the [PalaiCustomer] passed in (the live source of
/// truth per spec §16), and every row comes from the already-computed
/// [CustomerLedgerEntry] list built by FinanceService.getCustomerLedger.
class CustomerLedgerPdfService {
  CustomerLedgerPdfService._();

  static final CustomerLedgerPdfService instance = CustomerLedgerPdfService._();

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  Future<Uint8List> generatePdf({
    required PalaiCustomer customer,
    required List<CustomerLedgerEntry> entries,
    FarmModel? farm,
  }) async {
    // Same Unicode-aware font as the other PDF services — required for
    // the ₹ glyph to render instead of a broken box.
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    pw.MemoryImage? logo;
    try {
      if (farm?.profileImage != null && farm!.profileImage!.isNotEmpty) {
        logo = pw.MemoryImage(farm.profileImage!);
      } else {
        final logoBytes = await rootBundle.load('assets/images/logo.png');
        logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
      }
    } catch (_) {
      logo = null;
    }

    // Oldest-first for a statement that reads top-to-bottom like a real
    // ledger — the in-app list (and the [entries] this receives) is
    // newest-first, so it's reversed here for the PDF only.
    final chronological = entries.reversed.toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 30),
        header: (context) => _buildHeader(farm, logo),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildTitle(customer),
          pw.SizedBox(height: 14),
          _buildCustomerInfo(customer),
          pw.SizedBox(height: 16),
          _buildBalanceSummary(customer),
          pw.SizedBox(height: 18),
          pw.Text(
            'Ledger History',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _buildLedgerTable(chronological),
          pw.SizedBox(height: 20),
          _buildGeneratedNote(),
        ],
      ),
    );

    return pdf.save();
  }

  /// Opens the system share sheet with the generated PDF — the "share
  /// icon" entry point on the Customer Ledger detail screen.
  Future<void> share({
    required PalaiCustomer customer,
    required List<CustomerLedgerEntry> entries,
    FarmModel? farm,
  }) async {
    final bytes = await generatePdf(customer: customer, entries: entries, farm: farm);
    await Printing.sharePdf(bytes: bytes, filename: _safeFileName(customer));
  }

  // ===========================================================================
  // HEADER / FOOTER
  // ===========================================================================

  pw.Widget _buildHeader(FarmModel? farm, pw.MemoryImage? logo) {
    final farmName = (farm?.farmName ?? '').trim().isNotEmpty ? farm!.farmName.trim() : 'My Goat Farms';
    final address = (farm?.address ?? '').trim();
    final phone = (farm?.mobileNumber ?? '').trim();
    final email = (farm?.email ?? '').trim();

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 1, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null)
            pw.Container(
              width: 52,
              height: 52,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.ClipOval(child: pw.Image(logo, fit: pw.BoxFit.cover)),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(farmName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                if (address.isNotEmpty)
                  pw.Text(address, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                if (phone.isNotEmpty || email.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Wrap(
                    spacing: 10,
                    children: [
                      if (phone.isNotEmpty) pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 8.5)),
                      if (email.isNotEmpty) pw.Text('Email: $email', style: const pw.TextStyle(fontSize: 8.5)),
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

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        children: [
          pw.Text('Customer Ledger', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
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
  // TITLE / CUSTOMER INFO / BALANCE
  // ===========================================================================

  pw.Widget _buildTitle(PalaiCustomer customer) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('CUSTOMER LEDGER', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text(_formatDate(DateTime.now()), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  pw.Widget _buildCustomerInfo(PalaiCustomer customer) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(customer.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        if (customer.mobileNumber.trim().isNotEmpty)
          pw.Text('Phone: ${customer.mobileNumber}', style: const pw.TextStyle(fontSize: 9)),
        if (customer.address.trim().isNotEmpty)
          pw.Text(customer.address, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    );
  }

  pw.Widget _buildBalanceSummary(PalaiCustomer customer) {
    return pw.Row(
      children: [
        pw.Expanded(child: _balanceBox('Outstanding', customer.pendingAmount, PdfColors.red)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _balanceBox('Advance', customer.advanceAmount, PdfColors.blue)),
      ],
    );
  }

  pw.Widget _balanceBox(String label, double value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 3),
          pw.Text(_currency(value), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ===========================================================================
  // LEDGER TABLE
  // ===========================================================================

  pw.Widget _buildLedgerTable(List<CustomerLedgerEntry> entries) {
    if (entries.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(16),
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
        child: pw.Text('No ledger history yet.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );
    }

    final headerStyle = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final cellStyle = const pw.TextStyle(fontSize: 8.5);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6), // date
        1: pw.FlexColumnWidth(3.4), // description
        2: pw.FlexColumnWidth(1.4), // paymentMethod
        3: pw.FlexColumnWidth(1.6), // debit
        4: pw.FlexColumnWidth(1.6), // credit
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.green700),
          children: [
            _tableHeaderCell('Date', headerStyle),
            _tableHeaderCell('Description', headerStyle),
            _tableHeaderCell('Mode', headerStyle),
            _tableHeaderCell('Debit (₹)', headerStyle, align: pw.TextAlign.right),
            _tableHeaderCell('Credit (₹)', headerStyle, align: pw.TextAlign.right),
          ],
        ),
        for (final entry in entries)
          pw.TableRow(
            children: [
              _tableCell(_formatDate(entry.date), cellStyle),
              _tableCell(
                entry.subtitle.isEmpty ? entry.title : '${entry.title}\n${entry.subtitle}',
                cellStyle,
              ),
              _tableCell(entry.paymentMethod ?? '-', cellStyle),
              _tableCell(
                entry.isDebit ? _currency(entry.amount) : '-',
                cellStyle,
                align: pw.TextAlign.right,
              ),
              _tableCell(
                !entry.isDebit ? _currency(entry.amount) : '-',
                cellStyle,
                align: pw.TextAlign.right,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _tableHeaderCell(String text, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  pw.Widget _tableCell(String text, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  pw.Widget _buildGeneratedNote() {
    return pw.Text(
      'This is a system-generated statement. Please contact the farm for any discrepancies.',
      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
    );
  }

  // ===========================================================================
  // FORMATTERS
  // ===========================================================================

  String _currency(double value) {
    final formatter = NumberFormat('#,##0.00', 'en_IN');
    return formatter.format(value);
  }

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  String _safeFileName(PalaiCustomer customer) {
    final raw = 'Ledger_${customer.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_');
    return '$cleaned.pdf';
  }
}
