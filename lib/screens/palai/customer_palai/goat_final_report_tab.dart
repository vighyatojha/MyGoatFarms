import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/monthly_bill_model.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/monthly_billing_service.dart';
import 'goat_report_generate_screen.dart';

/// Final Report tab — a lifecycle summary from arrival through today
/// (or checkout, if already checked out): growth, health, and financial
/// totals. "Generate Final Report PDF" reuses the same Whole Period
/// flow as the Monthly Reports tab, since the underlying report
/// generation, layout, and calculations are identical — only the
/// framing (this is the closing summary, not a progress check-in)
/// differs.
class GoatFinalReportTab extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;
  final PalaiGoat goat;

  const GoatFinalReportTab({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
    required this.goat,
  });

  @override
  State<GoatFinalReportTab> createState() => _GoatFinalReportTabState();
}

class _GoatFinalReportTabState extends State<GoatFinalReportTab> {
  bool _loading = true;
  String? _error;
  List<HealthRecordEntry> _healthRecords = [];
  double _totalPalaiAllTime = 0;
  double _totalPaidAllTime = 0;

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
      final records = await FirestoreService.instance
          .healthRecordsStream(widget.farmId, widget.customerId, widget.goat.id)
          .first;

      final bills = await MonthlyBillingService.instance.getMonthlyBills(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );

      double totalPalai = 0;
      double totalPaid = 0;
      for (final MonthlyBill bill in bills) {
        for (final line in bill.goatBreakdown) {
          if (line.goatId == widget.goat.id) {
            totalPalai += line.palaiAmount;
            // amountPaid is recorded per bill, not per goat within a
            // bill — apportion it across this bill's goats by Palai
            // share so a multi-goat bill's payment isn't double-counted
            // against every goat.
            final billTotalPalai = bill.palaiCharges;
            if (billTotalPalai > 0) {
              totalPaid += bill.amountPaid * (line.palaiAmount / billTotalPalai);
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _healthRecords = records;
        _totalPalaiAllTime = totalPalai;
        _totalPaidAllTime = totalPaid;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load final report data: $e';
      });
    }
  }

  Future<void> _generateFinalReport() async {
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

  String _currency(double value) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(value);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: AppTheme.body(size: 12, color: AppColors.error), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final goat = widget.goat;
    final arrivalDate = goat.farmArrivalDate ?? goat.checkInDate;
    final endDate = goat.checkOutDate ?? DateTime.now();
    final totalDays = endDate.difference(arrivalDate).inDays;
    final finalWeight = goat.currentWeight ?? goat.weightAtCheckIn;
    final totalGain = finalWeight - goat.weightAtCheckIn;
    final issues = _healthRecords.where((r) => r.healthStatus == 'Sick' || r.diseaseOrProblem.trim().isNotEmpty).length;
    final vaccinations = _healthRecords.where((r) => r.vaccination.trim().isNotEmpty).length;
    final pendingForGoat = (_totalPalaiAllTime - _totalPaidAllTime).clamp(0, double.infinity).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _sectionCard('Summary', [
          ('Arrival Date', DateFormat('d MMM yyyy').format(arrivalDate)),
          (goat.isCheckedOut ? 'Checkout Date' : 'As of', DateFormat('d MMM yyyy').format(endDate)),
          ('Total Days', '$totalDays days'),
        ]),
        const SizedBox(height: 12),
        _sectionCard('Growth', [
          ('Arrival Weight', '${goat.weightAtCheckIn.toStringAsFixed(1)} kg'),
          (goat.isCheckedOut ? 'Final Weight' : 'Current Weight', '${finalWeight.toStringAsFixed(1)} kg'),
          ('Total Weight Gain', '${totalGain >= 0 ? '+' : ''}${totalGain.toStringAsFixed(1)} kg'),
        ]),
        const SizedBox(height: 12),
        _sectionCard('Health', [
          ('Total Health Updates', '${_healthRecords.length}'),
          ('Health Issues', '$issues'),
          ('Vaccinations Logged', '$vaccinations'),
          ('Current Status', goat.healthStatus.isNotEmpty ? goat.healthStatus : 'Not recorded'),
        ]),
        const SizedBox(height: 12),
        _sectionCard('Financial (this goat, all-time)', [
          ('Total Palai Billed', _currency(_totalPalaiAllTime)),
          ('Total Paid (apportioned)', _currency(_totalPaidAllTime)),
          ('Pending (this goat, est.)', _currency(pendingForGoat)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Paid/Pending here are apportioned from customer-level bills by this goat\'s Palai share — Palai billing itself tracks payment per customer, not per goat.',
          style: AppTheme.body(size: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _generateFinalReport,
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('Generate Final Report PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard(String title, List<(String, String)> pairs) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.heading(size: 13)),
          const SizedBox(height: 8),
          for (final pair in pairs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(pair.$1, style: AppTheme.body(size: 11.5, color: AppColors.textMuted))),
                  Expanded(flex: 3, child: Text(pair.$2, style: AppTheme.body(size: 12, weight: FontWeight.w500))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}