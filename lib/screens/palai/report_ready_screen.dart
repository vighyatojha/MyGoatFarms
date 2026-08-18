import 'dart:typed_data';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/report_pdf_service.dart';

/// Shown right after a report PDF has been generated for a goat: lets
/// the owner Share it (WhatsApp / email / etc. via the OS share sheet)
/// or Save it to the device — operating on the already-built PDF bytes,
/// so nothing is regenerated.
class ReportReadyScreen extends StatefulWidget {
  final PalaiGoat goat;
  final Uint8List pdfBytes;
  const ReportReadyScreen({super.key, required this.goat, required this.pdfBytes});

  @override
  State<ReportReadyScreen> createState() => _ReportReadyScreenState();
}

class _ReportReadyScreenState extends State<ReportReadyScreen> {
  bool _saving = false;

  String get _filename {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${widget.goat.goatCode}_progress_report_$stamp.pdf';
  }

  Future<void> _share() async {
    try {
      await ReportPdfService.instance.shareBytes(widget.pdfBytes, _filename);
    } catch (_) {
      _showSnack('Could not share the report. Please try again.', isError: true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final path = await ReportPdfService.instance.saveBytes(widget.pdfBytes, _filename);
      if (!mounted) return;
      _showSnack('Report saved to $path');
    } catch (_) {
      _showSnack('Could not save the report. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElasticIn(
                  duration: const Duration(milliseconds: 700),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryGreen),
                    child: const Icon(Icons.description_outlined, color: Colors.white, size: 52),
                  ),
                ),
                const SizedBox(height: 26),
                FadeInUp(
                  delay: const Duration(milliseconds: 250),
                  duration: const Duration(milliseconds: 300),
                  child: Text('Report Ready!', style: AppTheme.heading(size: 22)),
                ),
                const SizedBox(height: 8),
                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    'The progress report for ${widget.goat.goatCode} has been generated.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(size: 13),
                  ),
                ),
                const SizedBox(height: 36),
                FadeInUp(
                  delay: const Duration(milliseconds: 350),
                  duration: const Duration(milliseconds: 300),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                          )
                              : const Icon(Icons.download, size: 16),
                          label: Text('Save', style: AppTheme.heading(size: 13, color: AppColors.primaryGreen)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            side: const BorderSide(color: AppColors.primaryGreen),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: Text('Share', style: AppTheme.heading(size: 13, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  duration: const Duration(milliseconds: 300),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    child: Text('Done', style: AppTheme.body(size: 13, color: AppColors.textGrey)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}