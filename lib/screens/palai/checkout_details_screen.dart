import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../services/pdf_bill_service.dart';

/// Full check-out / bill detail view, reached from the "View Details"
/// button on the Checked-Out success screen. Lets the owner download the
/// same bill as a PDF.
class CheckoutDetailsScreen extends StatefulWidget {
  final PalaiGoat goat;
  final double finalWeight;
  final String healthStatus;
  final String deliveryStatus;
  final double totalCharges;
  final Uint8List? beforeImage;
  final Uint8List? afterImage;
  final BillSettings billSettings;

  const CheckoutDetailsScreen({
    super.key,
    required this.goat,
    required this.finalWeight,
    required this.healthStatus,
    required this.deliveryStatus,
    required this.totalCharges,
    this.beforeImage,
    this.afterImage,
    this.billSettings = const BillSettings(),
  });

  @override
  State<CheckoutDetailsScreen> createState() => _CheckoutDetailsScreenState();
}

class _CheckoutDetailsScreenState extends State<CheckoutDetailsScreen> {
  bool _downloading = false;

  Future<void> _downloadPdf() async {
    setState(() => _downloading = true);
    try {
      final path = await PdfBillService.instance.saveBillToDevice(
        goat: widget.goat,
        finalWeight: widget.finalWeight,
        healthStatus: widget.healthStatus,
        deliveryStatus: widget.deliveryStatus,
        totalCharges: widget.totalCharges,
        billSettings: widget.billSettings,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bill saved: $path'), backgroundColor: AppColors.darkGreen),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the PDF. Please try again.'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Check-Out Details', style: AppTheme.heading(size: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: AppTheme.card(radius: 16),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goat.goatCode, style: AppTheme.heading(size: 18)),
                  const SizedBox(height: 4),
                  Text('${goat.breed} · ${goat.gender} · ${goat.color}', style: AppTheme.body(size: 12)),
                  const Divider(height: 24),
                  _row('Check-In Date', _fmt(goat.checkInDate)),
                  _row('Check-Out Date', _fmt(DateTime.now())),
                  _row('Weight at Check-In', '${goat.weightAtCheckIn.toStringAsFixed(1)} kg'),
                  _row('Final Weight', '${widget.finalWeight.toStringAsFixed(1)} kg'),
                  _row('Health Status', widget.healthStatus),
                  _row('Delivery Status', widget.deliveryStatus),
                  _row('Monthly Package', goat.monthlyPackage),
                  if (goat.pricing > 0) _row('Palai Pricing', '₹${goat.pricing.toStringAsFixed(0)}'),
                  const Divider(height: 24),
                  _row('Total Charges', '₹${widget.totalCharges.toStringAsFixed(0)}', bold: true),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (widget.beforeImage != null || widget.afterImage != null)
              Row(
                children: [
                  if (widget.beforeImage != null) Expanded(child: _photo('Before Palai', widget.beforeImage!)),
                  if (widget.beforeImage != null && widget.afterImage != null) const SizedBox(width: 12),
                  if (widget.afterImage != null) Expanded(child: _photo('After Palai', widget.afterImage!)),
                ],
              ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _downloading ? null : _downloadPdf,
                icon: _downloading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(_downloading ? 'Saving…' : 'Download PDF', style: const TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.body(size: 13)),
          Text(
            value,
            style: AppTheme.body(size: 13, color: AppColors.textDark, weight: bold ? FontWeight.w700 : FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _photo(String label, Uint8List bytes) {
    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Text(label, style: AppTheme.body(size: 11, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(bytes, height: 110, width: double.infinity, fit: BoxFit.cover),
          ),
        ],
      ),
    );
  }
}
