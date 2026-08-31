import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/bill_settings_model.dart';
import '../../../models/palai_models.dart';
import '../../../models/report_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';
import '../../../services/individual_goat_report_pdf_service.dart';
import '../../../services/monthly_billing_service.dart';

enum _RangeMode { wholePeriod, oneMonth, custom }

/// Generates an individual goat's report for a chosen date range:
///
///   - Whole Period  — from arrival at the farm through today (or
///     through checkout, if this goat has been checked out).
///   - One Month     — any single calendar month.
///   - Custom Range  — any start/end date the owner picks.
///
/// The PDF itself is built by [IndividualGoatReportPdfService], adapted
/// from the layout already used in the Customer Goat Progress Report.
class GoatReportGenerateScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;
  final PalaiGoat goat;

  const GoatReportGenerateScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
    required this.goat,
  });

  @override
  State<GoatReportGenerateScreen> createState() => _GoatReportGenerateScreenState();
}

class _GoatReportGenerateScreenState extends State<GoatReportGenerateScreen> {
  _RangeMode _mode = _RangeMode.wholePeriod;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _customStart;
  DateTime? _customEnd;

  PickedImage? _capturedEndPhoto;
  bool _generating = false;

  DateTime get _arrivalDate => widget.goat.farmArrivalDate ?? widget.goat.checkInDate;

  ({DateTime start, DateTime end, String label}) get _resolvedRange {
    final now = DateTime.now();
    final effectiveEnd = widget.goat.checkOutDate ?? now;

    switch (_mode) {
      case _RangeMode.wholePeriod:
        return (start: _arrivalDate, end: effectiveEnd, label: 'Whole Period (Arrival to ${widget.goat.checkOutDate != null ? 'Checkout' : 'Today'})');
      case _RangeMode.oneMonth:
        final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
        final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
        final end = lastDayOfMonth.isAfter(effectiveEnd) ? effectiveEnd : lastDayOfMonth;
        return (start: start, end: end, label: DateFormat('MMMM yyyy').format(_selectedMonth));
      case _RangeMode.custom:
        final start = _customStart ?? _arrivalDate;
        final end = _customEnd ?? effectiveEnd;
        return (start: start, end: end, label: '${DateFormat('d MMM yyyy').format(start)} \u2013 ${DateFormat('d MMM yyyy').format(end)}');
    }
  }

  bool get _rangeEndIsToday {
    final end = _resolvedRange.end;
    final now = DateTime.now();
    return widget.goat.checkOutDate == null &&
        end.year == now.year && end.month == now.month && end.day == now.day;
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(_arrivalDate.year, _arrivalDate.month),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select any date within the month',
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _arrivalDate,
      lastDate: DateTime.now(),
      initialDateRange: (_customStart != null && _customEnd != null)
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : DateTimeRange(start: _arrivalDate, end: DateTime.now()),
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
      });
    }
  }

  Future<void> _captureEndPhoto() async {
    try {
      final picked = await ImageService.instance.pickFromCamera(
        maxStoredBytes: 200 * 1024,
        maxDimension: 480,
      );
      if (picked != null && mounted) {
        setState(() => _capturedEndPhoto = picked);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Please try again.')),
      );
    }
  }

  Future<void> _generate({required bool share}) async {
    if (_mode == _RangeMode.custom && (_customStart == null || _customEnd == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a start and end date first.')),
      );
      return;
    }

    setState(() => _generating = true);

    try {
      final range = _resolvedRange;
      final farmId = widget.farmId;
      final customerId = widget.customerId;
      final goatId = widget.goat.id;

      // ------------------------------------------------------------
      // GATHER: health records + monthly photos (one-time reads),
      // filtered to the chosen range.
      // ------------------------------------------------------------
      final allHealthRecords = await FirestoreService.instance
          .healthRecordsStream(farmId, customerId, goatId)
          .first;
      final recordsInRange = allHealthRecords
          .where((r) => !r.recordedAt.isBefore(range.start) && !r.recordedAt.isAfter(range.end))
          .toList();

      final allMonthlyPhotos = await FirestoreService.instance
          .monthlyPhotosStream(farmId, customerId, goatId)
          .first;

      // ------------------------------------------------------------
      // START WEIGHT / PHOTO — the latest thing AT OR BEFORE the
      // range start, falling back to the goat's arrival snapshot.
      // ------------------------------------------------------------
      final recordsAtOrBeforeStart = allHealthRecords
          .where((r) => !r.recordedAt.isAfter(range.start))
          .toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      final startWeight = recordsAtOrBeforeStart.isNotEmpty
          ? recordsAtOrBeforeStart.first.weight
          : widget.goat.weightAtCheckIn;

      final photosAtOrBeforeStart = allMonthlyPhotos
          .where((p) => !p.capturedAt.isAfter(range.start))
          .toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      final Uint8List startPhotoBytes = photosAtOrBeforeStart.isNotEmpty
          ? photosAtOrBeforeStart.first.image
          : (widget.goat.beforeImage ?? Uint8List(0));
      final String startPhotoLabel = photosAtOrBeforeStart.isNotEmpty ? 'Monthly Photo' : 'Check-In Photo';

      // ------------------------------------------------------------
      // END WEIGHT / PHOTO — latest AT OR BEFORE the range end,
      // falling back to the goat's live current values. If the range
      // ends today and a fresh photo was captured, that wins.
      // ------------------------------------------------------------
      final recordsAtOrBeforeEnd = allHealthRecords
          .where((r) => !r.recordedAt.isAfter(range.end))
          .toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      final endWeight = recordsAtOrBeforeEnd.isNotEmpty
          ? recordsAtOrBeforeEnd.first.weight
          : (widget.goat.currentWeight ?? widget.goat.weightAtCheckIn);

      final photosAtOrBeforeEnd = allMonthlyPhotos
          .where((p) => !p.capturedAt.isAfter(range.end))
          .toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      Uint8List endPhotoBytes;
      String endPhotoLabel;
      if (_capturedEndPhoto != null) {
        endPhotoBytes = _capturedEndPhoto!.bytes;
        endPhotoLabel = 'Report Day Photo';
      } else if (photosAtOrBeforeEnd.isNotEmpty) {
        endPhotoBytes = photosAtOrBeforeEnd.first.image;
        endPhotoLabel = 'Monthly Photo';
      } else if (widget.goat.afterImage != null && widget.goat.checkOutDate != null) {
        endPhotoBytes = widget.goat.afterImage!;
        endPhotoLabel = 'Check-Out Photo';
      } else {
        endPhotoBytes = widget.goat.beforeImage ?? Uint8List(0);
        endPhotoLabel = 'Check-In Photo';
      }

      // ------------------------------------------------------------
      // PAYMENT — this goat's own Palai line from every bill whose
      // billing month falls inside the range, plus the customer's
      // CURRENT (live) outstanding/advance, clearly labelled as
      // customer-level, not per-goat.
      // ------------------------------------------------------------
      final bills = await MonthlyBillingService.instance.getMonthlyBills(
        farmId: farmId,
        customerId: customerId,
      );

      final monthlyPalaiLines = <GoatMonthlyPalaiLine>[];
      for (final bill in bills) {
        if (bill.billingMonth.isBefore(DateTime(range.start.year, range.start.month)) ||
            bill.billingMonth.isAfter(DateTime(range.end.year, range.end.month))) {
          continue;
        }
        for (final line in bill.goatBreakdown) {
          if (line.goatId == goatId) {
            monthlyPalaiLines.add(GoatMonthlyPalaiLine(month: bill.billingMonth, amount: line.palaiAmount));
          }
        }
      }
      monthlyPalaiLines.sort((a, b) => a.month.compareTo(b.month));

      final customer = await FirestoreService.instance.getCustomer(farmId, customerId);
      final currentOutstanding = customer?.pendingAmount ?? 0;
      final currentAdvance = customer?.advanceAmount ?? 0;

      final farm = await FirestoreService.instance.getFarmById(farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();

      final data = IndividualGoatReportData(
        goat: widget.goat,
        customerName: widget.customerName,
        rangeLabel: range.label,
        rangeStart: range.start,
        rangeEnd: range.end,
        startWeight: startWeight,
        startDate: range.start,
        startPhotoBytes: startPhotoBytes,
        startPhotoLabel: startPhotoLabel,
        endWeight: endWeight,
        endDate: range.end,
        endPhotoBytes: endPhotoBytes,
        endPhotoLabel: endPhotoLabel,
        healthRecordsInRange: recordsInRange,
        monthlyPalaiLines: monthlyPalaiLines,
        currentOutstanding: currentOutstanding,
        currentAdvance: currentAdvance,
      );

      if (share) {
        await IndividualGoatReportPdfService.instance.share(data: data, billSettings: billSettings);
      } else {
        await IndividualGoatReportPdfService.instance.preview(data: data, billSettings: billSettings);
      }

      // Save a permanent record of this report under the goat, same
      // path GenerateReportScreen/Progress Report use, so it shows up
      // in the Monthly Reports tab's history and updates the goat's
      // "Report" badge.
      await FirestoreService.instance.saveGoatReport(
        farmId,
        customerId,
        goatId,
        GoatReport(
          id: '',
          type: GoatReportType.progress,
          fromDate: range.start,
          toDate: range.end,
          generatedAt: DateTime.now(),
          startWeight: startWeight,
          endWeight: endWeight,
          healthStatus: recordsInRange.isNotEmpty ? recordsInRange.first.healthStatus : widget.goat.healthStatus,
          notes: range.label,
          images: [
            ReportImage(bytes: startPhotoBytes, contentType: 'image/jpeg', label: 'Start ($startPhotoLabel)'),
            ReportImage(bytes: endPhotoBytes, contentType: 'image/jpeg', label: 'End ($endPhotoLabel)'),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate report: $e')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _resolvedRange;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('New Goat Report', style: AppTheme.heading(size: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text('Report Period', style: AppTheme.body(size: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Whole Period', style: TextStyle(fontSize: 12)),
                selected: _mode == _RangeMode.wholePeriod,
                onSelected: (_) => setState(() => _mode = _RangeMode.wholePeriod),
                selectedColor: AppColors.primaryGreen.withOpacity(0.2),
              ),
              ChoiceChip(
                label: const Text('One Month', style: TextStyle(fontSize: 12)),
                selected: _mode == _RangeMode.oneMonth,
                onSelected: (_) => setState(() => _mode = _RangeMode.oneMonth),
                selectedColor: AppColors.primaryGreen.withOpacity(0.2),
              ),
              ChoiceChip(
                label: const Text('Custom Range', style: TextStyle(fontSize: 12)),
                selected: _mode == _RangeMode.custom,
                onSelected: (_) => setState(() => _mode = _RangeMode.custom),
                selectedColor: AppColors.primaryGreen.withOpacity(0.2),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_mode == _RangeMode.oneMonth) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickMonth,
              child: InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Month',
                  prefixIcon: Icon(Icons.calendar_month, size: 18),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: Text(DateFormat('MMMM yyyy').format(_selectedMonth), style: AppTheme.body(size: 13)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_mode == _RangeMode.custom) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickCustomRange,
              child: InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Date Range',
                  prefixIcon: Icon(Icons.date_range, size: 18),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: Text(
                  (_customStart != null && _customEnd != null)
                      ? '${DateFormat('d MMM yyyy').format(_customStart!)} \u2013 ${DateFormat('d MMM yyyy').format(_customEnd!)}'
                      : 'Tap to choose dates',
                  style: AppTheme.body(size: 13),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(radius: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This report will cover:', style: AppTheme.body(size: 11, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Text(range.label, style: AppTheme.heading(size: 13.5)),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('d MMM yyyy').format(range.start)} \u2013 ${DateFormat('d MMM yyyy').format(range.end)}',
                  style: AppTheme.body(size: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_rangeEndIsToday) ...[
            Text('Report Day Photo (optional)', style: AppTheme.body(size: 11.5, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                GestureDetector(
                  onTap: _captureEndPhoto,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryGreen.withOpacity(0.4)),
                    ),
                    child: _capturedEndPhoto != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(_capturedEndPhoto!.bytes, fit: BoxFit.cover),
                    )
                        : const Icon(Icons.camera_alt_outlined, color: AppColors.primaryGreen),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'If skipped, the most recent monthly photo (or the check-in photo) is used instead.',
                    style: AppTheme.body(size: 11, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generating ? null : () => _generate(share: false),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primaryGreen),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generating ? null : () => _generate(share: true),
                  icon: _generating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.share_outlined),
                  label: Text(_generating ? 'Generating...' : 'Share Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}