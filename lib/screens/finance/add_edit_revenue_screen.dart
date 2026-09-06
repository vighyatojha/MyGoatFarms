import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/expense_categories.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';

/// Add or edit MANUAL revenue only — e.g. a goat sale or transport
/// income. Customer payments are never entered here; they flow in
/// automatically from the existing billing/payment screens (spec §11).
///
/// Pass [existingTransactionId] + [existingData] to edit a manual
/// revenue entry (a `transactions` doc with `referenceType:
/// 'manualRevenue'`). Leave both null to create a new one.
class AddEditRevenueScreen extends StatefulWidget {
  final String? existingTransactionId;
  final Map<String, dynamic>? existingData;

  const AddEditRevenueScreen({
    super.key,
    this.existingTransactionId,
    this.existingData,
  });

  @override
  State<AddEditRevenueScreen> createState() => _AddEditRevenueScreenState();
}

class _AddEditRevenueScreenState extends State<AddEditRevenueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _category = RevenueCategories.goatSale;
  String _paymentMethod = FinancePaymentMethods.cash;
  DateTime _date = DateTime.now();
  bool _saving = false;

  bool get _isEditing => widget.existingTransactionId != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existingData;
    if (data != null) {
      _amountController.text = ((data['amount'] ?? 0) as num).toStringAsFixed(0);
      _descriptionController.text = (data['note'] ?? '').toString();
      _category = (data['category'] ?? RevenueCategories.goatSale).toString();
      _paymentMethod = (data['paymentMethod'] ?? FinancePaymentMethods.cash).toString();
      final ts = data['date'];
      if (ts != null && ts is Timestamp) _date = ts.toDate();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
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

    final amount = double.tryParse(_amountController.text.trim()) ?? -1;
    if (amount.isNaN || amount.isInfinite || amount <= 0) {
      _message('Enter a valid amount greater than 0.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final farmId = await FirestoreService.instance.currentFarmId();
      if (farmId == null) {
        _message('Could not find your farm profile. Please log in again.', error: true);
        return;
      }

      if (_isEditing) {
        await FinanceService.instance.updateManualRevenue(
          farmId,
          widget.existingTransactionId!,
          category: _category,
          amount: amount,
          paymentMethod: _paymentMethod,
          date: _date,
          description: _descriptionController.text.trim(),
        );
      } else {
        await FinanceService.instance.addManualRevenue(
          farmId,
          category: _category,
          amount: amount,
          paymentMethod: _paymentMethod,
          date: _date,
          description: _descriptionController.text.trim(),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      _message(_isEditing ? 'Revenue updated' : 'Revenue added');
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
          _isEditing ? 'Edit Revenue' : 'Add Revenue',
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
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(.08),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.info.withOpacity(.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Use this only for income outside customer billing — like a goat sale. '
                        'Customer payments already appear here automatically.',
                        style: AppTheme.body(size: 11, color: AppColors.textDark),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _categorySelector(),
                    const SizedBox(height: 14),
                    _field(
                      controller: _amountController,
                      label: 'Amount',
                      hint: '15000',
                      icon: Icons.currency_rupee_rounded,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    ),
                    const SizedBox(height: 14),
                    _dateField(),
                    const SizedBox(height: 14),
                    _paymentMethodSelector(),
                    const SizedBox(height: 14),
                    _field(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'e.g. Sale of goat GP-21',
                      icon: Icons.edit_note_rounded,
                      maxLines: 3,
                      optional: true,
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
        labelText: 'Revenue Type',
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
      items: RevenueCategories.all
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
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
          label: Text(_saving ? 'Saving...' : (_isEditing ? 'Save Changes' : 'Add Revenue')),
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
