import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app_theme.dart';
import '../../../../models/trading_purchase_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 2 — Purchase Details.
///
/// Fields:
/// - Total Goats
/// - Total Weight at Purchase
/// - Price per KG
/// - Payment Method: Cash / Online
///
/// Breed has intentionally been removed from the Trading purchase flow.
///
/// Purchase Amount is always calculated as:
/// Total Weight × Price per KG
class Step2PurchaseDetails extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PurchaseDraft draft;

  const Step2PurchaseDetails({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<Step2PurchaseDetails> createState() =>
      _Step2PurchaseDetailsState();
}

class _Step2PurchaseDetailsState
    extends State<Step2PurchaseDetails> {
  late final TextEditingController _totalGoatsController;
  late final TextEditingController _weightController;
  late final TextEditingController _priceController;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _totalGoatsController = TextEditingController(
      text: draft.totalGoats == 0
          ? ''
          : draft.totalGoats.toString(),
    );

    _weightController = TextEditingController(
      text: draft.totalWeightAtPurchase == 0
          ? ''
          : _trimZero(draft.totalWeightAtPurchase),
    );

    _priceController = TextEditingController(
      text: draft.pricePerKg == 0
          ? ''
          : _trimZero(draft.pricePerKg),
    );
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _totalGoatsController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final draft = widget.draft;

    draft.totalGoats =
        int.tryParse(_totalGoatsController.text.trim()) ?? 0;

    draft.totalWeightAtPurchase =
        double.tryParse(_weightController.text.trim()) ?? 0;

    draft.pricePerKg =
        double.tryParse(_priceController.text.trim()) ?? 0;

    setState(() {});
  }

  void _setPaymentMethod(String method) {
    setState(() {
      widget.draft.paymentMethod = method;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24,
        ),
        children: [
          WizardSectionCard(
            title: 'Purchase Details',
            icon: Icons.shopping_cart_outlined,
            children: [
              _buildField(
                controller: _totalGoatsController,
                label: 'Total Goats',
                hint: 'Number of goats',
                icon: Icons.pets_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => _recalculate(),
                validator: (value) {
                  final number = int.tryParse(
                    value?.trim() ?? '',
                  );

                  if (number == null || number <= 0) {
                    return 'Enter a valid goat count';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _buildField(
                controller: _weightController,
                label: 'Total Weight at Purchase',
                hint: '0.00',
                icon: Icons.scale_outlined,
                suffix: 'KG',
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => _recalculate(),
                validator: (value) {
                  final number = double.tryParse(
                    value?.trim() ?? '',
                  );

                  if (number == null || number <= 0) {
                    return 'Enter a valid weight';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _buildField(
                controller: _priceController,
                label: 'Price per KG',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                prefix: '₹ ',
                suffix: '/ KG',
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => _recalculate(),
                validator: (value) {
                  final number = double.tryParse(
                    value?.trim() ?? '',
                  );

                  if (number == null || number <= 0) {
                    return 'Enter a valid price';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 14),

          _buildPurchaseAmountCard(
            draft.purchaseAmount,
          ),

          const SizedBox(height: 16),

          WizardSectionCard(
            title: 'Payment Method',
            icon: Icons.payments_outlined,
            children: [
              Text(
                'Select how the seller is being paid.',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _paymentOption(
                      title: 'Cash',
                      icon: Icons.money_rounded,
                      selected:
                      draft.paymentMethod == 'Cash',
                      onTap: () {
                        _setPaymentMethod('Cash');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _paymentOption(
                      title: 'Online',
                      icon:
                      Icons.account_balance_wallet_outlined,
                      selected:
                      draft.paymentMethod == 'Online',
                      onTap: () {
                        _setPaymentMethod('Online');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseAmountCard(double amount) {
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
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Purchase Amount',
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Weight × Price per KG',
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

  Widget _paymentOption({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 58,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.lightGreen
                : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? AppColors.primaryGreen
                  : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected
                    ? AppColors.darkGreen
                    : AppColors.textGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 12,
                    color: selected
                        ? AppColors.darkGreen
                        : AppColors.textDark,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.primaryGreen,
                ),
              ],
            ],
          ),
        ),
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
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
    String? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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
          borderSide: const BorderSide(
            color: AppColors.divider,
          ),
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
          borderSide: const BorderSide(
            color: AppColors.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}