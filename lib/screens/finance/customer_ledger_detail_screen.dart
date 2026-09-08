import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/customer_ledger_entry_model.dart';
import '../../models/farm_model.dart';
import '../../models/palai_models.dart';
import '../../services/customer_ledger_pdf_service.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/finance/ledger_entry_tile.dart';
import '../palai/receive_payment_screen.dart';

/// Shows a customer's full financial history.
///
/// Per spec §16, the CURRENT outstanding/advance shown at the top always
/// comes straight from the customer document (the live source of truth)
/// — it is never recomputed by summing historical bills/payments here.
/// The ledger list below is history only, rendered from each bill/
/// payment doc's own stored snapshot fields.
///
/// The sticky "Add Credit" / "Add Debit" bar lets the farm record a
/// payment or a manual outstanding charge right from this screen,
/// reusing the exact same FirestoreService calls the rest of the app
/// already uses for those actions (ReceivePaymentScreen /
/// addOutstandingAmount) so nothing about how balances are calculated
/// changes — this screen just gives it a second entry point.
class CustomerLedgerDetailScreen extends StatefulWidget {
  final PalaiCustomer customer;

  const CustomerLedgerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerLedgerDetailScreen> createState() => _CustomerLedgerDetailScreenState();
}

class _CustomerLedgerDetailScreenState extends State<CustomerLedgerDetailScreen> {
  late PalaiCustomer _customer;
  String? _farmId;
  FarmModel? _farm;
  bool _loading = true;
  bool _sharing = false;
  List<CustomerLedgerEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final farmId = await FirestoreService.instance.currentFarmId();
      if (farmId == null) return;
      _farmId = farmId;

      // Re-fetch the customer too — not just the ledger — so the balance
      // cards reflect any Add Credit / Add Debit made from this screen
      // instead of staying frozen at whatever was passed in originally.
      // The farm profile is fetched alongside it purely so the shared
      // ledger PDF can carry the farm's name/logo/contact details.
      final results = await Future.wait([
        FirestoreService.instance.getCustomer(farmId, widget.customer.id),
        FinanceService.instance.getCustomerLedger(farmId, widget.customer.id),
        FirestoreService.instance.getFarmById(farmId),
      ]);
      final refreshedCustomer = results[0] as PalaiCustomer?;
      final entries = results[1] as List<CustomerLedgerEntry>;
      final farm = results[2] as FarmModel?;

      if (!mounted) return;
      setState(() {
        if (refreshedCustomer != null) _customer = refreshedCustomer;
        _entries = entries;
        _farm = farm;
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

  Future<void> _openAddCredit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceivePaymentScreen(presetCustomer: _customer),
      ),
    );

    if (result == true) await _load();
  }

  Future<void> _openAddDebit() async {
    final farmId = _farmId;
    if (farmId == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: _AddOutstandingSheet(farmId: farmId, customer: _customer),
        );
      },
    );

    if (saved == true) await _load();
  }

  /// Generates the customer's ledger as a PDF and opens the system share
  /// sheet — the "share as PDF" entry point requested for this screen.
  /// Works even with zero history (an empty statement is still valid),
  /// and is disabled while a share is already in progress so a fast
  /// double-tap can't kick off two PDF generations at once.
  Future<void> _shareLedger() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await CustomerLedgerPdfService.instance.share(
        customer: _customer,
        entries: _entries,
        farm: _farm,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FirestoreService.instance.describeError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text(customer.name, style: AppTheme.heading(size: 18)),
        actions: [
          IconButton(
            tooltip: 'Share ledger as PDF',
            onPressed: (_loading || _sharing) ? null : _shareLedger,
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                  )
                : const Icon(Icons.share_outlined),
          ),
        ],
      ),
      bottomNavigationBar: _bottomActionBar(),
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

  Widget _bottomActionBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _openAddCredit,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Credit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _farmId == null ? null : _openAddDebit,
                icon: const Icon(Icons.remove_rounded),
                label: const Text('Add Debit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add Debit" sheet — records a manual outstanding charge against the
/// customer via [FirestoreService.addOutstandingAmount], the same call
/// already used elsewhere in the app for this exact action.
class _AddOutstandingSheet extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;

  const _AddOutstandingSheet({required this.farmId, required this.customer});

  @override
  State<_AddOutstandingSheet> createState() => _AddOutstandingSheetState();
}

class _AddOutstandingSheetState extends State<_AddOutstandingSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount greater than ₹0.'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await FirestoreService.instance.addOutstandingAmount(
        farmId: widget.farmId,
        customerId: widget.customer.id,
        amount: amount,
        note: _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Text('Add Debit', style: AppTheme.heading(size: 17)),
          const SizedBox(height: 4),
          Text(
            'Add a manual outstanding charge for ${widget.customer.name}. This increases what they owe you.',
            style: AppTheme.body(size: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.body(size: 14, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppColors.error),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 2,
            style: AppTheme.body(size: 13, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: 'Optional note',
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}