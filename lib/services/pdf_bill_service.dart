import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_settings_model.dart';
import '../models/palai_models.dart';

/// Builds the final Palai check-out bill as a PDF, and either shares it
/// (WhatsApp / email / etc. via the OS share sheet) or saves it to the
/// device so the owner can "download" it.
///
/// The business name, address, phone, UPI/payment info, thank-you note
/// and terms & conditions are all driven by [BillSettings] — editable
/// from Profile > Bill Details — instead of being hard-coded here.
class PdfBillService {
  PdfBillService._();
  static final PdfBillService instance = PdfBillService._();

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
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(billSettings.businessName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              if (billSettings.tagline.trim().isNotEmpty)
                pw.Text(billSettings.tagline, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              if (billSettings.address.trim().isNotEmpty)
                pw.Text(billSettings.address, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              if (billSettings.phone.trim().isNotEmpty)
                pw.Text('Phone: ${billSettings.phone}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text('Check-Out Bill', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              ),
              pw.SizedBox(height: 14),
              _pdfRow('Goat ID', goat.goatCode),
              _pdfRow('Breed', goat.breed),
              _pdfRow('Gender', goat.gender),
              _pdfRow('Color', goat.color),
              _pdfRow('Monthly Package', goat.monthlyPackage),
              _pdfRow('Check-In Date', _fmt(goat.checkInDate)),
              _pdfRow('Check-Out Date', _fmt(now)),
              _pdfRow('Weight at Check-In', '${goat.weightAtCheckIn.toStringAsFixed(1)} kg'),
              _pdfRow('Final Weight', '${finalWeight.toStringAsFixed(1)} kg'),
              _pdfRow('Health Status', healthStatus),
              _pdfRow('Delivery Status', deliveryStatus),
              pw.Divider(height: 22),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Bill', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rs. ${totalCharges.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              if (billSettings.upiId.trim().isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text(
                  'Pay via UPI: ${billSettings.upiId}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                ),
              ],
              if (billSettings.terms.trim().isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Terms & Conditions', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(billSettings.terms, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
              pw.SizedBox(height: 30),
              if (billSettings.footerNote.trim().isNotEmpty)
                pw.Text(billSettings.footerNote, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Opens the OS share sheet with the bill PDF (WhatsApp, email, etc.) —
  /// used by the "Share" button on the Checked-Out success screen.
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
    await Printing.sharePdf(bytes: bytes, filename: '${goat.goatCode}_bill.pdf');
  }

  /// Saves the bill PDF to the device and returns the saved file path —
  /// used by the "Download PDF" button on the Check-Out Details screen.
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
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${goat.goatCode}_bill.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // -------------------------------------------------------------------
  // Monthly Palai bill (Billing & Payments screen)
  // -------------------------------------------------------------------

  Future<Uint8List> _buildMonthlyBill({
    required String customerName,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required BillSettings billSettings,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(billSettings.businessName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              if (billSettings.tagline.trim().isNotEmpty)
                pw.Text(billSettings.tagline, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              if (billSettings.address.trim().isNotEmpty)
                pw.Text(billSettings.address, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              if (billSettings.phone.trim().isNotEmpty)
                pw.Text('Phone: ${billSettings.phone}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text('Monthly Bill', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              ),
              pw.SizedBox(height: 14),
              _pdfRow('Customer', customerName),
              _pdfRow('Bill Date', _fmt(now)),
              pw.Divider(height: 22),
              _pdfRow('Previous Balance', 'Rs. ${previousBalance.toStringAsFixed(0)}'),
              _pdfRow('Monthly Charges', 'Rs. ${monthlyCharges.toStringAsFixed(0)}'),
              _pdfRow('Transportation Charges', 'Rs. ${transport.toStringAsFixed(0)}'),
              _pdfRow('Discount', '- Rs. ${discount.toStringAsFixed(0)}'),
              pw.Divider(height: 22),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Bill', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rs. ${totalBill.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 6),
              _pdfRow('Paid Amount', 'Rs. ${paid.toStringAsFixed(0)}'),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Pending Amount', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                  pw.Text('Rs. ${pendingAmount.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                ],
              ),
              if (billSettings.upiId.trim().isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  'Pay via UPI: ${billSettings.upiId}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                ),
              ],
              if (billSettings.terms.trim().isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Terms & Conditions', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(billSettings.terms, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
              pw.SizedBox(height: 30),
              if (billSettings.footerNote.trim().isNotEmpty)
                pw.Text(billSettings.footerNote, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Opens the OS share sheet with the monthly bill PDF — used right
  /// after "Generate & Save Bill" on the Billing & Payments screen.
  Future<void> shareMonthlyBill({
    required String customerName,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required BillSettings billSettings,
  }) async {
    final bytes = await _buildMonthlyBill(
      customerName: customerName,
      monthlyCharges: monthlyCharges,
      transport: transport,
      previousBalance: previousBalance,
      discount: discount,
      paid: paid,
      totalBill: totalBill,
      pendingAmount: pendingAmount,
      billSettings: billSettings,
    );
    final safeName = customerName.trim().isEmpty ? 'customer' : customerName.trim().replaceAll(RegExp(r'\s+'), '_');
    await Printing.sharePdf(bytes: bytes, filename: '${safeName}_bill.pdf');
  }

  /// Saves the monthly bill PDF to the device and returns the saved file
  /// path — used by the "Download PDF" option after generating a bill.
  Future<String> saveMonthlyBillToDevice({
    required String customerName,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required BillSettings billSettings,
  }) async {
    final bytes = await _buildMonthlyBill(
      customerName: customerName,
      monthlyCharges: monthlyCharges,
      transport: transport,
      previousBalance: previousBalance,
      discount: discount,
      paid: paid,
      totalBill: totalBill,
      pendingAmount: pendingAmount,
      billSettings: billSettings,
    );
    final dir = await getApplicationDocumentsDirectory();
    final safeName = customerName.trim().isEmpty ? 'customer' : customerName.trim().replaceAll(RegExp(r'\s+'), '_');
    final file = File('${dir.path}/${safeName}_bill_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}