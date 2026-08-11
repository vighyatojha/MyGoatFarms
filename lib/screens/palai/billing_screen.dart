import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Generates a monthly bill for a Palai customer: monthly charges,
/// transport charges, previous balance, discount, paid amount — computes
/// the total and pending amount, then records it to Firestore.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  String? _farmId;
  PalaiCustomer? _selectedCustomer;
  final _monthlyChargesController = TextEditingController(text: '0');
  final _transportController = TextEditingController(text: '0');
  final _discountController = TextEditingController(text: '0');
  final _paidController = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  double get _monthlyCharges => double.tryParse(_monthlyChargesController.text) ?? 0;
  double get _transport => double.tryParse(_transportController.text) ?? 0;
  double get _discount => double.tryParse(_discountController.text) ?? 0;
  double get _paid => double.tryParse(_paidController.text) ?? 0;
  double get _previousBalance => _selectedCustomer?.pendingAmount ?? 0;

  double get _totalBill => (_monthlyCharges + _transport + _previousBalance - _discount).clamp(0, double.infinity);
  double get _pendingAmount => (_totalBill - _paid).clamp(0, double.infinity);

  Future<void> _generateBill() async {
    if (_selectedCustomer == null || _farmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _saving = true);

    await FirestoreService.instance.updateCustomerPendingAmount(_farmId!, _selectedCustomer!.id, _pendingAmount);

    if (_paid > 0) {
      await FirestoreService.instance.addTransaction(
        _farmId!,
        amount: _paid,
        isIncome: true,
        category: 'Palai Payment',
        note: 'Bill payment from ${_selectedCustomer!.name}',
      );
    }

    await FirestoreService.instance.logActivity(
      _farmId!,
      ActivityLog(
        id: '',
        type: ActivityType.paymentReceived,
        title: 'Monthly Bill Generated',
        subtitle: '${_selectedCustomer!.name} · Total ₹${_totalBill.toStringAsFixed(0)}',
        module: 'palai',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill generated and saved'), backgroundColor: AppColors.primaryGreen),
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
        title: Text('Billing & Payments', style: AppTheme.heading(size: 17)),
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
                            value: _selectedCustomer,
                            isExpanded: true,
                            hint: Text('Choose a customer', style: AppTheme.body(size: 13)),
                            items: customers
                                .map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: AppTheme.body(size: 13, color: AppColors.textDark))))
                                .toList(),
                            onChanged: (v) => setState(() => _selectedCustomer = v),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _label('Monthly Charges (₹)'),
                  _amountField(_monthlyChargesController),
                  const SizedBox(height: 12),
                  _label('Transportation Charges (₹)'),
                  _amountField(_transportController),
                  const SizedBox(height: 12),
                  _label('Discount (₹)'),
                  _amountField(_discountController),
                  const SizedBox(height: 12),
                  _label('Paid Amount (₹)'),
                  _amountField(_paidController),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.card(radius: 14),
                    child: Column(
                      children: [
                        _summaryRow('Previous Balance', _previousBalance),
                        _summaryRow('Total Bill', _totalBill, bold: true),
                        const Divider(height: 20),
                        _summaryRow('Pending Amount', _pendingAmount, color: AppColors.error, bold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _generateBill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Generate & Save Bill', style: TextStyle(fontWeight: FontWeight.w600)),
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
