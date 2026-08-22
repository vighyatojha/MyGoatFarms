import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/monthly_bill_model.dart';
import '../../services/monthly_billing_service.dart';

class MonthlyBillGenerateScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;
  final int goatCount;
  final double suggestedMonthlyAmount;

  const MonthlyBillGenerateScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
    this.goatCount = 0,
    this.suggestedMonthlyAmount = 0,
  });

  @override
  State<MonthlyBillGenerateScreen> createState() =>
      _MonthlyBillGenerateScreenState();
}

class _MonthlyBillGenerateScreenState
    extends State<MonthlyBillGenerateScreen> {
  final _formKey = GlobalKey<FormState>();

  final _palaiController =
  TextEditingController();

  final _otherController =
  TextEditingController();

  final _discountController =
  TextEditingController();

  final _notesController =
  TextEditingController();

  final MonthlyBillingService
  _billingService =
      MonthlyBillingService.instance;

  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    if (widget.suggestedMonthlyAmount > 0) {
      _palaiController.text =
          widget.suggestedMonthlyAmount
              .toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _palaiController.dispose();
    _otherController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double _number(
      String value,
      ) {
    return double.tryParse(
      value.trim(),
    ) ??
        0;
  }

  double get _palaiCharges =>
      _number(_palaiController.text);

  double get _otherCharges =>
      _number(_otherController.text);

  double get _discount =>
      _number(_discountController.text);

  double get _currentBill =>
      (_palaiCharges +
          _otherCharges -
          _discount)
          .clamp(0, double.infinity)
          .toDouble();

  String _currency(double value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Generate Monthly Bill',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildCustomerCard(),

            const SizedBox(height: 18),

            _buildMonthSelector(),

            const SizedBox(height: 18),

            _moneyField(
              controller: _palaiController,
              label: 'Monthly Palai Charges',
              icon: Icons.home_work_outlined,
            ),

            const SizedBox(height: 12),

            _moneyField(
              controller: _otherController,
              label: 'Other Charges',
              icon: Icons.add_card_outlined,
            ),

            const SizedBox(height: 12),

            _moneyField(
              controller: _discountController,
              label: 'Discount',
              icon: Icons.discount_outlined,
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              decoration:
              const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            _buildAmountPreview(),

            const SizedBox(height: 20),

            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                _saving ? null : _generateBill,
                icon: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(
                  Icons.receipt_long,
                ),
                label: Text(
                  _saving
                      ? 'Generating...'
                      : 'Generate Monthly Bill',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 25,
              child: Icon(
                Icons.person_outline,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customer',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.customerName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${widget.goatCount} goat(s)',
                    style: TextStyle(
                      color:
                      Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    final text = DateFormat(
      'MMMM yyyy',
    ).format(_selectedMonth);

    return InkWell(
      borderRadius:
      BorderRadius.circular(10),
      onTap: _selectMonth,
      child: InputDecorator(
        decoration:
        const InputDecoration(
          labelText: 'Billing Month',
          prefixIcon:
          Icon(Icons.calendar_month),
          border: OutlineInputBorder(),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _moneyField({
    required TextEditingController
    controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),
      onChanged: (_) {
        setState(() {});
      },
      validator: (value) {
        final number =
        double.tryParse(
          value?.trim() ?? '',
        );

        if (number == null) {
          return 'Enter a valid amount';
        }

        if (number < 0) {
          return 'Amount cannot be negative';
        }

        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        prefixText: '₹ ',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildAmountPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey.shade300,
        ),
        borderRadius:
        BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.calculate_outlined),
              SizedBox(width: 8),
              Text(
                'Bill Preview',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _previewRow(
            'Palai Charges',
            _currency(_palaiCharges),
          ),

          _previewRow(
            'Other Charges',
            _currency(_otherCharges),
          ),

          _previewRow(
            'Discount',
            '- ${_currency(_discount)}',
          ),

          const Divider(),

          _previewRow(
            'Current Bill',
            _currency(_currentBill),
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _previewRow(
      String label,
      String value, {
        bool bold = false,
      }) {
    return Padding(
      padding:
      const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectMonth() async {
    final now = DateTime.now();

    final selected =
    await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(
        now.year - 5,
        1,
        1,
      ),
      lastDate: DateTime(
        now.year + 1,
        12,
        31,
      ),
      helpText:
      'Select any date in the billing month',
    );

    if (selected == null) return;

    setState(() {
      _selectedMonth = DateTime(
        selected.year,
        selected.month,
      );
    });
  }

  Future<void> _generateBill() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    if (_currentBill <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Monthly bill amount must be greater than zero.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final exists =
      await _billingService.monthlyBillExists(
        farmId: widget.farmId,
        customerId: widget.customerId,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
      );

      if (exists) {
        throw StateError(
          'A monthly bill already exists for '
              '${DateFormat('MMMM yyyy').format(_selectedMonth)}.',
        );
      }

      final MonthlyBill bill =
      await _billingService.createMonthlyBill(
        farmId: widget.farmId,
        customerId: widget.customerId,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
        palaiCharges: _palaiCharges,
        otherCharges: _otherCharges,
        discount: _discount,
        goatCount: widget.goatCount,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Monthly bill ${bill.billNumber} generated.',
          ),
        ),
      );

      Navigator.of(context).pop(bill);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Unable to generate bill: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}