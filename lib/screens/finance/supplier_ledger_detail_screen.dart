import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/expense_categories.dart';
import '../../models/supplier_ledger_entry_model.dart';
import '../../models/supplier_model.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/finance/supplier_ledger_entry_tile.dart';

/// Shows a single supplier's full payment history, and lets the farm
/// record either:
///
///  - **Add Credit** (green) — a payment made TO the supplier, which
///    reduces what the farm owes them.
///  - **Add Debit** (red) — an amount now owed to the supplier (e.g. a
///    manual credit purchase not made through the Stock screens),
///    which increases what the farm owes them.
///
/// The buttons keep the same green/red "Add Credit" / "Add Debit"
/// language as the Customer Ledger design, but the meaning is mirrored:
/// on the customer side, a credit is money coming IN; here, a credit is
/// money going OUT to settle what's owed.
class SupplierLedgerDetailScreen extends StatefulWidget {
  final SupplierModel supplier;

  const SupplierLedgerDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierLedgerDetailScreen> createState() => _SupplierLedgerDetailScreenState();
}

class _SupplierLedgerDetailScreenState extends State<SupplierLedgerDetailScreen> {
  late SupplierModel _supplier;
  String? _farmId;
  bool _loading = true;
  List<SupplierLedgerEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final farmId = await FirestoreService.instance.currentFarmId();
      if (farmId == null) return;
      _farmId = farmId;

      final refreshed = await FirestoreService.instance.getSupplier(farmId, _supplier.id);
      final entries = await FinanceService.instance.getSupplierLedger(farmId, _supplier.id);

      if (!mounted) return;
      setState(() {
        if (refreshed != null) _supplier = refreshed;
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

  Future<void> _openAddCredit() async {
    final farmId = _farmId;
    if (farmId == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: _AddPaymentSheet(farmId: farmId, supplier: _supplier),
        );
      },
    );

    if (saved == true) await _load();
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
          child: _AddCreditPurchaseSheet(farmId: farmId, supplier: _supplier),
        );
      },
    );

    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final supplier = _supplier;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text(supplier.name, style: AppTheme.heading(size: 18)),
      ),
      bottomNavigationBar: _bottomActionBar(),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (supplier.mobileNumber.isNotEmpty || supplier.address.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.card(radius: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (supplier.mobileNumber.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.call_outlined, size: 15, color: AppColors.textGrey),
                            const SizedBox(width: 8),
                            Text(supplier.mobileNumber, style: AppTheme.body(size: 12)),
                          ],
                        ),
                      if (supplier.address.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textGrey),
                            const SizedBox(width: 8),
                            Expanded(child: Text(supplier.address, style: AppTheme.body(size: 12))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: _balanceCard(
                      'You Owe',
                      supplier.pendingAmount,
                      AppColors.error,
                      Icons.hourglass_empty_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _balanceCard(
                      'Advance Paid',
                      supplier.advanceAmount,
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
                      SupplierLedgerEntryTile(
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
                onPressed: _farmId == null ? null : _openAddCredit,
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

/// "Add Credit" sheet — records a payment made TO the supplier.
class _AddPaymentSheet extends StatefulWidget {
  final String farmId;
  final SupplierModel supplier;

  const _AddPaymentSheet({required this.farmId, required this.supplier});

  @override
  State<_AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends State<_AddPaymentSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _paymentMethod = FinancePaymentMethods.cash;
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
      await FirestoreService.instance.recordSupplierPayment(
        farmId: widget.farmId,
        supplierId: widget.supplier.id,
        amount: amount,
        paymentMethod: _paymentMethod,
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
          Text('Add Credit', style: AppTheme.heading(size: 17)),
          const SizedBox(height: 4),
          Text(
            'Record a payment made to ${widget.supplier.name}. This reduces what you owe them.',
            style: AppTheme.body(size: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.body(size: 14, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Amount Paid (₹)',
              prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppColors.success),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          Text('Payment Method', style: AppTheme.body(size: 11, color: AppColors.textGrey, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FinancePaymentMethods.all.map((method) {
              final selected = _paymentMethod == method;
              return GestureDetector(
                onTap: () => setState(() => _paymentMethod = method),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryGreen : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AppColors.primaryGreen : AppColors.divider),
                  ),
                  child: Text(
                    method,
                    style: AppTheme.body(
                      size: 12,
                      color: selected ? Colors.white : AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
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
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Save Payment'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add Debit" sheet — records a manual amount now owed to the supplier
/// (e.g. a credit purchase made outside the Stock screens).
class _AddCreditPurchaseSheet extends StatefulWidget {
  final String farmId;
  final SupplierModel supplier;

  const _AddCreditPurchaseSheet({required this.farmId, required this.supplier});

  @override
  State<_AddCreditPurchaseSheet> createState() => _AddCreditPurchaseSheetState();
}

class _AddCreditPurchaseSheetState extends State<_AddCreditPurchaseSheet> {
  final _amountController = TextEditingController();
  final _itemController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _itemController.dispose();
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
      await FirestoreService.instance.recordSupplierCreditPurchase(
        farmId: widget.farmId,
        supplierId: widget.supplier.id,
        amount: amount,
        itemName: _itemController.text.trim(),
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
            'Record an amount now owed to ${widget.supplier.name} — for a purchase made on '
                'credit outside the Stock screens. This increases what you owe them.',
            style: AppTheme.body(size: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.body(size: 14, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Amount Owed (₹)',
              prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppColors.error),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _itemController,
            style: AppTheme.body(size: 13, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Item / reason (optional)',
              prefixIcon: const Icon(Icons.inventory_2_outlined, color: AppColors.primaryGreen),
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