import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';

/// Records a payment received from a Palai customer. Reduces that
/// customer's pending amount by the amount received, and adds the
/// amount to the farm's income (both stay in sync since they're driven
/// off the same `pendingAmount` field and `transactions` collection used
/// everywhere else — Billing, Home stat cards, Income detail).
class ReceivePaymentScreen extends StatefulWidget {
  const ReceivePaymentScreen({super.key});

  @override
  State<ReceivePaymentScreen> createState() => _ReceivePaymentScreenState();
}

class _ReceivePaymentScreenState extends State<ReceivePaymentScreen> {
  String? _farmId;
  PalaiCustomer? _selectedCustomer;
  final _amountController = TextEditingController(text: '0');
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  double get _amount => double.tryParse(_amountController.text) ?? 0;
  double get _pendingBefore => _selectedCustomer?.pendingAmount ?? 0;
  double get _pendingAfter => (_pendingBefore - _amount).clamp(0, double.infinity);
  bool get _isAdvance => _amount > _pendingBefore && _pendingBefore > 0;

  Future<void> _receivePayment() async {
    if (_selectedCustomer == null || _farmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount greater than 0'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);

    // Subtract the amount received from this customer's pending balance.
    await FirestoreService.instance.updateCustomerPendingAmount(_farmId!, _selectedCustomer!.id, _pendingAfter);

    // Add the amount received to total income — the same `transactions`
    // collection every income figure on Home / Palai / Income Detail is
    // summed from, so this shows up there immediately.
    await FirestoreService.instance.addTransaction(
      _farmId!,
      amount: _amount,
      isIncome: true,
      category: 'Payment Received',
      note: _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : 'Payment received from ${_selectedCustomer!.name}',
    );

    await FirestoreService.instance.logActivity(
      _farmId!,
      ActivityLog(
        id: '',
        type: ActivityType.paymentReceived,
        title: 'Payment Received',
        subtitle: '${_selectedCustomer!.name} · ₹${_amount.toStringAsFixed(0)}',
        module: 'palai',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment recorded'), backgroundColor: AppColors.primaryGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Receive Payment', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Select Customer'),
            StreamBuilder<List<PalaiCustomer>>(
              stream: FirestoreService.instance.customersStream(_farmId!),
              builder: (context, snap) {
                final customers = snap.data ?? [];
                return Container(
                  decoration: AppTheme.card(radius: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PalaiCustomer>(
                      value: customers.contains(_selectedCustomer) ? _selectedCustomer : null,
                      isExpanded: true,
                      hint: Text('Choose a customer', style: AppTheme.body(size: 13)),
                      items: customers
                          .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.name} · Pending ₹${c.pendingAmount.toStringAsFixed(0)}',
                              style: AppTheme.body(size: 13, color: AppColors.textDark))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCustomer = v),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _label('Amount Received (₹)'),
            _amountField(_amountController),
            const SizedBox(height: 12),
            _label('Note (optional)'),
            Container(
              decoration: AppTheme.card(radius: 12),
              child: TextField(
                controller: _noteController,
                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(14)),
                style: AppTheme.body(size: 13, color: AppColors.textDark),
              ),
            ),
            const SizedBox(height: 20),
            if (_selectedCustomer != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(radius: 14),
                child: Column(
                  children: [
                    _summaryRow('Pending Before', _pendingBefore, color: AppColors.error),
                    _summaryRow('Amount Received', _amount, color: AppColors.success),
                    const Divider(height: 20),
                    _summaryRow('Pending After', _pendingAfter, bold: true),
                    if (_isAdvance) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This clears the pending balance. The remaining ₹${(_amount - _pendingBefore).toStringAsFixed(0)} still counts as income received.',
                        style: AppTheme.body(size: 11, color: AppColors.textGrey),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _receivePayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Record Payment', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.body(size: 13)),
          Text(
            '₹${value.toStringAsFixed(0)}',
            style: bold
                ? AppTheme.heading(size: 14, color: color ?? AppColors.textDark)
                : AppTheme.body(size: 13, color: color ?? AppColors.textDark),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: AppTheme.heading(size: 13)),
  );

  Widget _amountField(TextEditingController controller) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(14)),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
    );
  }
}