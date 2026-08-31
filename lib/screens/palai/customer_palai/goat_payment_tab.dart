import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/monthly_bill_model.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/monthly_billing_service.dart';

/// Payment tab — this goat's OWN Palai line from every monthly bill,
/// plus the customer's current outstanding/advance (clearly labelled as
/// customer-level, since Palai billing tracks those per customer, not
/// per goat — every goat under one customer shares the same
/// outstanding/advance balance).
class GoatPaymentTab extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const GoatPaymentTab({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<GoatPaymentTab> createState() => _GoatPaymentTabState();
}

class _GoatPaymentTabState extends State<GoatPaymentTab> {
  bool _loading = true;
  String? _error;
  List<MonthlyBill> _bills = [];
  PalaiCustomer? _customer;

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
      final bills = await MonthlyBillingService.instance.getMonthlyBills(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
      final customer = await FirestoreService.instance.getCustomer(widget.farmId, widget.customerId);

      bills.sort((a, b) => b.billingMonth.compareTo(a.billingMonth));

      if (!mounted) return;
      setState(() {
        _bills = bills;
        _customer = customer;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load payment info: $e';
      });
    }
  }

  double? _lineFor(MonthlyBill bill) {
    for (final line in bill.goatBreakdown) {
      if (line.goatId == widget.goat.id) return line.palaiAmount;
    }
    return null;
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

    final billsWithGoat = _bills.where((b) => _lineFor(b) != null).toList();
    final totalPalaiAllTime = billsWithGoat.fold<double>(0, (sum, b) => sum + (_lineFor(b) ?? 0));
    final customer = _customer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _customerBalanceCard(customer),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.card(radius: 14),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Palai (this goat, all-time)', style: AppTheme.body(size: 10.5, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(_currency(totalPalaiAllTime), style: AppTheme.heading(size: 16).copyWith(color: AppColors.primaryGreen)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Text('Monthly Bills (${billsWithGoat.length})', style: AppTheme.heading(size: 13))),
          ],
        ),
        const SizedBox(height: 8),
        if (billsWithGoat.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: AppTheme.card(radius: 12),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 26, color: AppColors.textMuted.withOpacity(0.6)),
                const SizedBox(height: 8),
                Text('No bills include this goat yet', style: AppTheme.body(size: 12, color: AppColors.textMuted)),
              ],
            ),
          )
        else
          for (final bill in billsWithGoat) _billTile(bill),
      ],
    );
  }

  Widget _customerBalanceCard(PalaiCustomer? customer) {
    final outstanding = customer?.pendingAmount ?? 0;
    final advance = customer?.advanceAmount ?? 0;
    final isPending = outstanding > 0;
    final color = isPending ? AppColors.error : AppColors.success;

    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isPending ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(isPending ? 'Payment Pending' : 'No Pending Payment', style: AppTheme.heading(size: 12.5).copyWith(color: color))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Outstanding & Advance are customer-level — shared across every goat this customer has, since Palai billing tracks balance per customer.',
            style: AppTheme.body(size: 10, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _balanceStat('Current Outstanding', outstanding, color: outstanding > 0 ? AppColors.error : AppColors.textDark),
              ),
              Expanded(
                child: _balanceStat('Current Advance', advance, color: advance > 0 ? AppColors.success : AppColors.textDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceStat(String label, double value, {required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(_currency(value), style: AppTheme.heading(size: 14).copyWith(color: color)),
      ],
    );
  }

  Widget _billTile(MonthlyBill bill) {
    final amount = _lineFor(bill) ?? 0;
    final isPaid = bill.isPaid;
    final color = isPaid ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.card(radius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('MMMM yyyy').format(bill.billingMonth), style: AppTheme.heading(size: 12.5)),
                Text(bill.statusLabel, style: AppTheme.body(size: 10.5, color: color)),
              ],
            ),
          ),
          Text(_currency(amount), style: AppTheme.heading(size: 13)),
        ],
      ),
    );
  }
}