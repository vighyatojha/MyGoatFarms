import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app_theme.dart';
import '../../../../models/sale_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 4 — Sale Details.
///
/// Selling Price/KG (editable) x Total Selling Weight (derived from
/// Step 3) = Total Sale Amount, auto-calculated live and summed across
/// every selected goat — Task 2.4. Same "derived field, never manually
/// overridden" rule as the Purchase wizard's Purchase Amount.
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

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void initState() {
    super.initState();

    _priceController = TextEditingController(
      text: widget.draft.sellingPricePerKg == 0
          ? ''
          : _trimZero(widget.draft.sellingPricePerKg),
    );
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
              _ReadOnlyRow(
                icon: Icons.pets_outlined,
                label: 'Goats in this Sale',
                value: '${draft.selectedGoats.length}',
              ),
              const SizedBox(height: 12),
              _ReadOnlyRow(
                icon: Icons.scale_outlined,
                label: 'Total Selling Weight',
                value: '${_trimZero(draft.totalSellingWeight)} KG',
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _priceController,
                label: 'Selling Price per KG',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                suffix: '/ KG',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
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
}

// ============================================================================
// READ-ONLY ROW
// ============================================================================

class _ReadOnlyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(size: 12, color: AppColors.textGrey),
            ),
          ),
          Text(
            value,
            style: AppTheme.heading(size: 13, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}