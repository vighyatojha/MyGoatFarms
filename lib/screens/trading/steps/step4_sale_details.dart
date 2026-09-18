import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app_theme.dart';
import '../../../../models/sale_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 4 — Sale Details (Task 2.4).
///
/// Selling Price/KG (editable) × Total Selling Weight (from Step 3,
/// summed across every selected goat) = Total Sale Amount. Same
/// "derived field, never manually overridden" rule as Phase 1's
/// Purchase Amount.
class Step4SaleDetails extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final SaleDraft draft;

  const Step4SaleDetails({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<Step4SaleDetails> createState() => _Step4SaleDetailsState();
}

class _Step4SaleDetailsState extends State<Step4SaleDetails> {
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _priceController = TextEditingController(
      text: draft.sellingPricePerKg == 0
          ? ''
          : _trimZero(draft.sellingPricePerKg),
    );
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _recalculate() {
    widget.draft.sellingPricePerKg =
        double.tryParse(_priceController.text.trim()) ?? 0;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardSectionCard(
            title: 'Sale Details',
            icon: Icons.sell_outlined,
            children: [
              WizardComputedRow(
                label: draft.isMultiGoat
                    ? 'Total Selling Weight (${draft.selectedGoats.length} goats)'
                    : 'Selling Weight',
                value: '${draft.totalSellingWeight.toStringAsFixed(1)} kg',
              ),

              const SizedBox(height: 8),

              _buildField(
                controller: _priceController,
                label: 'Selling Price per KG',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                prefix: '₹ ',
                suffix: '/ KG',
                onChanged: (_) => _recalculate(),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number <= 0) {
                    return 'Enter a valid price';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 14),

          _buildTotalCard(draft.totalSaleAmount),
        ],
      ),
    );
  }

  // Mirrors Step2PurchaseDetails._buildPurchaseAmountCard so the two
  // wizards read the same way.
  Widget _buildTotalCard(double amount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.calculate_outlined,
              color: AppColors.darkGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Sale Amount',
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Selling Weight × Price per KG',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _currency(amount),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(
                size: 18,
                color: AppColors.darkGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
    FormFieldValidator<String>? validator,
    String? prefix,
    String? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        prefixText: prefix,
        suffixText: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}