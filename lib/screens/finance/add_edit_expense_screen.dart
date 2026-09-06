import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/expense_categories.dart';
import '../../models/expense_model.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';

/// Add or edit a farm-wide expense. Pass [existing] to edit; leave it
/// null to create a new one.
class AddEditExpenseScreen extends StatefulWidget {
  final ExpenseModel? existing;

  const AddEditExpenseScreen({super.key, this.existing});

  @override
  State<AddEditExpenseScreen> createState() => _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends State<AddEditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _unitController = TextEditingController();
  final _supplierController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _notesController = TextEditingController();

  String _category = ExpenseCategories.other;
  String _paymentMethod = FinancePaymentMethods.cash;
  DateTime _date = DateTime.now();

  bool _saving = false;
  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _amountController.text = existing.amount.toStringAsFixed(0);
      _quantityController.text = existing.quantity?.toString() ?? '';
      _unitPriceController.text = existing.unitPrice?.toString() ?? '';
      _unitController.text = existing.unit ?? '';
      _supplierController.text = existing.supplierName ?? '';
      _invoiceController.text = existing.invoiceNumber ?? '';
      _notesController.text = existing.note;
      _category = existing.category;
      _paymentMethod = existing.paymentMethod;
      _date = existing.date;
    }

    // Auto-calculate amount from quantity x unit price, but never
    // override an amount the user typed in directly afterwards.
    _quantityController.addListener(_recalculateAmount);
    _unitPriceController.addListener(_recalculateAmount);
  }

  void _recalculateAmount() {
    final quantity = double.tryParse(_quantityController.text.trim());
    final unitPrice = double.tryParse(_unitPriceController.text.trim());
    if (quantity != null && unitPrice != null && quantity > 0 && unitPrice > 0) {
      _amountController.text = (quantity * unitPrice).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _unitController.dispose();
    _supplierController.dispose();
    _invoiceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : AppColors.primaryGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Safe numeric conversion — never allow negative/NaN/Infinity
    // amounts through (spec §9/§38).
    final amount = double.tryParse(_amountController.text.trim()) ?? -1;
    if (amount.isNaN || amount.isInfinite || amount <= 0) {
      _message('Enter a valid amount greater than 0.', error: true);
      return;
    }

    final quantity = double.tryParse(_quantityController.text.trim());
    final unitPrice = double.tryParse(_unitPriceController.text.trim());

    setState(() => _saving = true);

    try {
      final farmId = await FirestoreService.instance.currentFarmId();
      if (farmId == null) {
        _message('Could not find your farm profile. Please log in again.', error: true);
        return;
      }

      final expense = ExpenseModel(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        category: _category,
        amount: amount,
        quantity: (quantity != null && quantity > 0) ? quantity : null,
        unitPrice: (unitPrice != null && unitPrice > 0) ? unitPrice : null,
        unit: _unitController.text.trim().isEmpty ? null : _unitController.text.trim(),
        supplierName: _supplierController.text.trim().isEmpty
            ? null
            : _supplierController.text.trim(),
        paymentMethod: _paymentMethod,
        invoiceNumber: _invoiceController.text.trim().isEmpty
            ? null
            : _invoiceController.text.trim(),
        note: _notesController.text.trim(),
        date: _date,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (_isEditing) {
        await FinanceService.instance.updateExpense(farmId, widget.existing!.id, expense);
      } else {
        await FinanceService.instance.addExpense(farmId, expense);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      _message(_isEditing ? 'Expense updated' : 'Expense added');
    } on TimeoutException {
      _message('Connection is taking too long. Please try again.', error: true);
    } on ArgumentError catch (e) {
      _message(e.message.toString(), error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text(
          _isEditing ? 'Edit Expense' : 'Add Expense',
          style: AppTheme.heading(size: 18),
        ),
      ),
      bottomNavigationBar: _bottomAction(),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _section(
                title: 'Expense details',
                icon: Icons.remove_circle_outline,
                children: [
                  _field(
                    controller: _titleController,
                    label: 'Expense Title',
                    hint: 'e.g. Antibiotic Purchase',
                    icon: Icons.title_rounded,
                  ),
                  const SizedBox(height: 14),
                  _categorySelector(),
                  const SizedBox(height: 14),
                  _dateField(),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Amount',
                icon: Icons.currency_rupee_rounded,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          controller: _quantityController,
                          label: 'Quantity',
                          hint: 'Optional',
                          icon: Icons.numbers_rounded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          optional: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          controller: _unitController,
                          label: 'Unit',
                          hint: 'kg, bottle...',
                          icon: Icons.straighten_rounded,
                          optional: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field(
                    controller: _unitPriceController,
                    label: 'Unit Price',
                    hint: 'Optional — auto-fills Amount',
                    icon: Icons.sell_outlined,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    optional: true,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    controller: _amountController,
                    label: 'Total Amount',
                    hint: '2500',
                    icon: Icons.currency_rupee_rounded,
                    suffix: '₹',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Payment',
                icon: Icons.payments_outlined,
                children: [
                  _paymentMethodSelector(),
                  const SizedBox(height: 14),
                  _field(
                    controller: _supplierController,
                    label: 'Supplier / Vendor',
                    hint: 'Optional',
                    icon: Icons.storefront_outlined,
                    optional: true,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    controller: _invoiceController,
                    label: 'Reference / Invoice Number',
                    hint: 'Optional',
                    icon: Icons.receipt_long_outlined,
                    optional: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Notes',
                icon: Icons.notes_rounded,
                children: [
                  _field(
                    controller: _notesController,
                    label: 'Additional note',
                    hint: 'Optional',
                    icon: Icons.edit_note_rounded,
                    maxLines: 3,
                    optional: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(13),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date',
          prefixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.primaryGreen, size: 20),
          labelStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: AppColors.divider),
          ),
        ),
        child: Text(
          '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
          style: AppTheme.body(size: 13, color: AppColors.textDark),
        ),
      ),
    );
  }

  Widget _categorySelector() {
    return DropdownButtonFormField<String>(
      value: _category,
      decoration: InputDecoration(
        labelText: 'Category',
        prefixIcon: const Icon(Icons.category_outlined, color: AppColors.primaryGreen, size: 20),
        labelStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
      items: ExpenseCategories.all
          .map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppTheme.body(size: 13))))
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _category = value);
      },
    );
  }

  Widget _paymentMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget _section({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryGreen, size: 18),
              const SizedBox(width: 8),
              Text(title, style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    bool optional = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: (value) {
        if (!optional && (value == null || value.trim().isEmpty)) return 'Required';
        return null;
      },
      style: AppTheme.body(size: 13, color: AppColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
        suffixText: suffix,
        labelStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        hintStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
        ),
      ),
    );
  }

  Widget _bottomAction() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: SizedBox(
        height: 54,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Saving...' : (_isEditing ? 'Save Changes' : 'Add Expense')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
