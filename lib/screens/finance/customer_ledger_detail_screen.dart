import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/customer_ledger_entry_model.dart';
import '../../models/palai_models.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/finance/ledger_entry_tile.dart';

/// Shows a customer's full financial history.
///
/// Per spec §16, the CURRENT outstanding/advance shown at the top always
/// comes straight from the customer document (the live source of truth)
/// — it is never recomputed by summing historical bills/payments here.
/// The ledger list below is history only, rendered from each bill/
/// payment doc's own stored snapshot fields.
class CustomerLedgerDetailScreen extends StatefulWidget {
  final PalaiCustomer customer;

  const CustomerLedgerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerLedgerDetailScreen> createState() => _CustomerLedgerDetailScreenState();
}

class _CustomerLedgerDetailScreenState extends State<CustomerLedgerDetailScreen> {
  bool _loading = true;
  List<CustomerLedgerEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final farmId = await FirestoreService.instance.currentFarmId();
      if (farmId == null) return;
      final entries = await FinanceService.instance.getCustomerLedger(farmId, widget.customer.id);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FirestoreService.instance.describeError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text(customer.name, style: AppTheme.heading(size: 18)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _balanceCard(
                      'Outstanding',
                      customer.pendingAmount,
                      AppColors.error,
                      Icons.hourglass_empty_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _balanceCard(
                      'Advance',
                      customer.advanceAmount,
                      AppColors.info,
                      Icons.savings_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Ledger History', style: AppTheme.heading(size: 15)),
              const SizedBox(height: 10),
              _loading
                  ? Container(
                      height: 150,
                      alignment: Alignment.center,
                      decoration: AppTheme.card(radius: 17),
                      child: const CircularProgressIndicator(color: AppColors.primaryGreen, strokeWidth: 2),
                    )
                  : _entries.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: AppTheme.card(radius: 17),
                          child: Column(
                            children: [
                              const Icon(Icons.receipt_long_outlined, color: AppColors.textGrey, size: 30),
                              const SizedBox(height: 9),
                              Text(
                                'No ledger history yet',
                                style: AppTheme.body(size: 12, color: AppColors.textGrey, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.divider.withOpacity(0.7)),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < _entries.length; i++)
                                LedgerEntryTile(
                                  entry: _entries[i],
                                  showDivider: i != _entries.length - 1,
                                ),
                            ],
                          ),
                        ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceCard(String label, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text('₹${value.toStringAsFixed(0)}', style: AppTheme.heading(size: 17)),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.body(size: 11)),
        ],
      ),
    );
  }
}
