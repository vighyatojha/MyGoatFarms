import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/bill_settings_model.dart';
import '../../../models/palai_models.dart';
import '../../../models/report_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/individual_goat_report_pdf_service.dart';
import '../../../services/monthly_billing_service.dart';
import 'goat_report_generate_screen.dart';

/// Monthly Reports tab — every report generated for this goat so far
/// (Whole Period / One Month / Custom Range, whichever was chosen when
/// generated), newest first, plus a "+ New Report" entry point.
class GoatMonthlyReportsTab extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;
  final PalaiGoat goat;

  const GoatMonthlyReportsTab({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
    required this.goat,
  });

  @override
  State<GoatMonthlyReportsTab> createState() => _GoatMonthlyReportsTabState();
}

class _GoatMonthlyReportsTabState extends State<GoatMonthlyReportsTab> {
  late Stream<List<GoatReport>> _stream;
  bool _reopening = false;

  @override
  void initState() {
    super.initState();
    _stream = FirestoreService.instance.goatReportsStream(
      widget.farmId,
      widget.customerId,
      widget.goat.id,
    );
  }

  Future<void> _openNewReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => GoatReportGenerateScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          customerName: widget.customerName,
          goat: widget.goat,
        ),
      ),
    );
  }

  /// Re-opens a previously saved report as a PDF preview. The saved
  /// [GoatReport] already carries its own weight/photo/health snapshot;
  /// only the Payment section is recomputed live (from the bills that
  /// fall in that report's original date range) since payment lines
  /// aren't part of the saved report record.
  Future<void> _reopenReport(GoatReport report) async {
    setState(() => _reopening = true);
    try {
      final bills = await MonthlyBillingService.instance.getMonthlyBills(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );

      final monthlyPalaiLines = <GoatMonthlyPalaiLine>[];
      for (final bill in bills) {
        if (bill.billingMonth.isBefore(DateTime(report.fromDate.year, report.fromDate.month)) ||
            bill.billingMonth.isAfter(DateTime(report.toDate.year, report.toDate.month))) {
          continue;
        }
        for (final line in bill.goatBreakdown) {
          if (line.goatId == widget.goat.id) {
            monthlyPalaiLines.add(GoatMonthlyPalaiLine(month: bill.billingMonth, amount: line.palaiAmount));
          }
        }
      }
      monthlyPalaiLines.sort((a, b) => a.month.compareTo(b.month));

      final customer = await FirestoreService.instance.getCustomer(widget.farmId, widget.customerId);
      final farm = await FirestoreService.instance.getFarmById(widget.farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();

      final startImage = report.images.isNotEmpty ? report.images.first : null;
      final endImage = report.images.length > 1 ? report.images[1] : startImage;

      final data = IndividualGoatReportData(
        goat: widget.goat,
        customerName: widget.customerName,
        rangeLabel: report.notes.isNotEmpty
            ? report.notes
            : '${DateFormat('d MMM yyyy').format(report.fromDate)} \u2013 ${DateFormat('d MMM yyyy').format(report.toDate)}',
        rangeStart: report.fromDate,
        rangeEnd: report.toDate,
        startWeight: report.startWeight,
        startDate: report.fromDate,
        startPhotoBytes: startImage?.bytes ?? Uint8List(0),
        startPhotoLabel: startImage?.label ?? 'Start',
        endWeight: report.endWeight,
        endDate: report.toDate,
        endPhotoBytes: endImage?.bytes ?? Uint8List(0),
        endPhotoLabel: endImage?.label ?? 'End',
        healthRecordsInRange: const [],
        monthlyPalaiLines: monthlyPalaiLines,
        currentOutstanding: customer?.pendingAmount ?? 0,
        currentAdvance: customer?.advanceAmount ?? 0,
      );

      await IndividualGoatReportPdfService.instance.preview(data: data, billSettings: billSettings);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reopen report: $e')),
      );
    } finally {
      if (mounted) setState(() => _reopening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<GoatReport>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
            }

            final reports = snapshot.data ?? [];

            if (reports.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined, size: 30, color: AppColors.textMuted.withOpacity(0.6)),
                      const SizedBox(height: 10),
                      Text('No reports yet', style: AppTheme.heading(size: 14)),
                      const SizedBox(height: 6),
                      Text(
                        'Generate the first report for this goat — whole period, one month, or a custom range.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 11.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
              children: [
                for (final report in reports) _reportTile(report),
              ],
            );
          },
        ),
        Positioned(
          right: 14,
          bottom: 14,
          child: FloatingActionButton.extended(
            onPressed: _openNewReport,
            backgroundColor: AppColors.primaryGreen,
            icon: const Icon(Icons.add),
            label: const Text('New Report'),
          ),
        ),
        if (_reopening)
          Container(
            color: Colors.black.withOpacity(0.15),
            child: const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
          ),
      ],
    );
  }

  Widget _reportTile(GoatReport report) {
    final gain = (report.startWeight != null && report.endWeight != null) ? report.endWeight! - report.startWeight! : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.card(radius: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _reopenReport(report),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.description_outlined, size: 18, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.notes.isNotEmpty
                          ? report.notes
                          : '${DateFormat('d MMM').format(report.fromDate)} \u2013 ${DateFormat('d MMM yyyy').format(report.toDate)}',
                      style: AppTheme.heading(size: 12.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Generated ${DateFormat('d MMM yyyy').format(report.generatedAt)}'
                          '${gain != null ? ' \u2022 ${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : ''}',
                      style: AppTheme.body(size: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}