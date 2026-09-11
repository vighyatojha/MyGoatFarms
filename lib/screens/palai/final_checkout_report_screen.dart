import 'dart:typed_data';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/final_checkout_report_model.dart';
import '../../models/palai_models.dart';
import '../../services/finance_service.dart';
import '../../services/final_checkout_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_report_service.dart';
import 'checkout_charges_payment_screen.dart' show GoatCheckoutDraft;

/// Shown once, right after a customer-level checkout completes — the
/// merged replacement for the old per-goat CheckoutSuccessScreen +
/// CheckoutDetailsScreen pair.
///
/// Instead of a separate "Checked Out!" celebration screen per goat
/// (each opening its own single-goat bill PDF), this ONE screen covers
/// every goat checked out together: it builds the Final Checkout
/// Report (one goat = one page, compressed monthly history, then a
/// customer-level Final Settlement page) and lets the owner
/// Preview/Share/Save it.
///
/// Pops with `true` when dismissed via "Done", same as the screen it
/// replaces, so callers that chain several pops together (multi-goat
/// checkout -> goat list refresh) keep working unchanged.
class FinalCheckoutReportScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final List<GoatCheckoutDraft> goats;
  final MonthlyBillResult billResult;
  final BillSettings billSettings;

  const FinalCheckoutReportScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goats,
    required this.billResult,
    this.billSettings = const BillSettings(),
  });

  @override
  State<FinalCheckoutReportScreen> createState() => _FinalCheckoutReportScreenState();
}

class _FinalCheckoutReportScreenState extends State<FinalCheckoutReportScreen> {
  bool _loading = true;
  String? _error;
  bool _busy = false;

  PalaiCustomer? _customer;
  List<GoatFinalReportEntry> _entries = [];
  FinalSettlementData? _settlement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final customer = await FirestoreService.instance.getCustomer(widget.farmId, widget.customerId);
      if (customer == null) {
        throw StateError('Customer could not be found.');
      }

      DateTime? earliestCheckIn;
      final entries = <GoatFinalReportEntry>[];

      for (final draft in widget.goats) {
        final goat = draft.goat;
        final periodStart = goat.farmArrivalDate ?? goat.checkInDate;
        final periodEnd = DateTime.now();

        if (earliestCheckIn == null || periodStart.isBefore(earliestCheckIn)) {
          earliestCheckIn = periodStart;
        }

        final monthlyHistory = await MonthlyReportService.instance.getGoatMonthlyHistory(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goatId: goat.id,
          periodStart: periodStart,
          periodEnd: periodEnd,
        );

        final photos = await FirestoreService.instance
            .monthlyPhotosStream(widget.farmId, widget.customerId, goat.id)
            .first;

        final photoByMonth = <String, Uint8List>{};
        for (final row in monthlyHistory) {
          final match = photos.where(
                (p) => p.month.year == row.monthStart.year && p.month.month == row.monthStart.month,
          );
          if (match.isNotEmpty) {
            photoByMonth[row.monthLabel] = match.first.image;
          }
        }

        entries.add(
          GoatFinalReportEntry(
            goat: goat,
            checkInDate: periodStart,
            checkOutDate: periodEnd,
            initialWeight: goat.weightAtCheckIn,
            finalWeight: draft.finalWeight,
            beforeImage: goat.beforeImage,
            afterImage: draft.afterImage,
            monthlyHistory: monthlyHistory,
            representativePhotoByMonth: photoByMonth,
            healthStatus: draft.healthStatus,
            deliveryStatus: draft.deliveryStatus,
          ),
        );
      }

      final settlement = await FinanceService.instance.buildFinalSettlement(
        farmId: widget.farmId,
        customerId: widget.customerId,
        customerName: customer.name,
        goatCount: widget.goats.length,
        billResult: widget.billResult,
        periodStart: earliestCheckIn,
        periodEnd: DateTime.now(),
      );

      if (!mounted) return;
      setState(() {
        _customer = customer;
        _entries = entries;
        _settlement = settlement;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not build the final checkout report: $e';
      });
    }
  }

  Future<void> _preview() => _run(() => FinalCheckoutReportPdfService.instance.preview(
    customer: _customer!,
    goatEntries: _entries,
    settlement: _settlement!,
    billSettings: widget.billSettings,
  ));

  Future<void> _share() => _run(() => FinalCheckoutReportPdfService.instance.share(
    customer: _customer!,
    goatEntries: _entries,
    settlement: _settlement!,
    billSettings: widget.billSettings,
  ));

  Future<void> _save() => _run(() async {
    final path = await FinalCheckoutReportPdfService.instance.save(
      customer: _customer!,
      goatEntries: _entries,
      settlement: _settlement!,
      billSettings: widget.billSettings,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Report saved: $path'), backgroundColor: AppColors.darkGreen),
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _customer == null || _settlement == null) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not build the report. Please try again.'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _currency(double value) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Final Checkout Report', style: AppTheme.heading(size: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: AppTheme.body(size: 12, color: AppColors.error)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final settlement = _settlement!;
    final settled = settlement.isFullySettled;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            children: [
              ElasticIn(
                duration: const Duration(milliseconds: 600),
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: settled ? AppColors.primaryGreen : Colors.orange,
                  ),
                  child: Icon(settled ? Icons.check : Icons.hourglass_bottom, color: Colors.white, size: 46),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  settled ? 'Checkout Complete — Fully Settled' : 'Checkout Complete — Payment Pending',
                  textAlign: TextAlign.center,
                  style: AppTheme.heading(size: 16),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '${settlement.goatCount} goat${settlement.goatCount == 1 ? '' : 's'} checked out for ${settlement.customerName}',
                  style: AppTheme.body(size: 12, color: AppColors.textGrey),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                decoration: AppTheme.card(radius: 14),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Total Due', _currency(settlement.finalAmountDue)),
                    _row('Total Paid', _currency(settlement.finalAmountPaid)),
                    const Divider(height: 20),
                    _row('Remaining', _currency(settlement.finalOutstanding), bold: true),
                    if (settlement.finalAdvance > 0) ...[
                      const SizedBox(height: 6),
                      _row('Advance Carried Forward', _currency(settlement.finalAdvance)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Goats in this report', style: AppTheme.heading(size: 13)),
              const SizedBox(height: 8),
              for (final entry in _entries) _goatTile(entry),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.body(size: 13)),
          Text(
            value,
            style: AppTheme.body(size: bold ? 15 : 13, color: AppColors.textDark, weight: bold ? FontWeight.w700 : FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _goatTile(GoatFinalReportEntry entry) {
    final goat = entry.goat;
    final label = goat.name.trim().isNotEmpty ? goat.name : goat.goatCode;
    final change = entry.weightChange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.card(radius: 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.body(size: 13, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${entry.totalMonths} month${entry.totalMonths == 1 ? '' : 's'} • '
                      '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
                  style: AppTheme.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(entry.healthStatus.isEmpty ? '-' : entry.healthStatus, style: AppTheme.body(size: 11, color: AppColors.textGrey)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _preview,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primaryGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Save'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primaryGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Done', style: AppTheme.body(size: 13, color: AppColors.textGrey)),
            ),
          ],
        ),
      ),
    );
  }
}