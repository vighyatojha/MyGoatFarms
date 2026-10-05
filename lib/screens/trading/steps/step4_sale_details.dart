import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 4 — Sale Details.
///
/// The goats can be priced two ways, chosen with the slider at the top of
/// the card:
///
///  * **By KG** — Selling Price/KG (editable) x Total Selling Weight
///    (derived from Step 3) = Total Sale Amount.
///  * **Fixed Price** — one agreed price for the whole lot. It does not
///    change with the weight.
///
/// An optional **Discount** (in rupees) comes off the goat amount. It can
/// never be more than the goat amount.
///
/// Either way the Total Sale Amount is auto-calculated live and never
/// manually overridden — Task 2.4. Same "derived field" rule as the
/// Purchase wizard's Purchase Amount. It is the amount AFTER the discount
/// (see [SaleDraft.totalSaleAmount]).
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
  late final TextEditingController _fixedPriceController;
  late final TextEditingController _discountController;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  /// Price shown in the text field: "520", "520.5", "520.55".
  String _priceText(double value) => SaleDraft.formatWeight(value);

  @override
  void initState() {
    super.initState();

    // Both fields are pre-filled from the draft, so going Back from
    // Step 5 and returning here shows exactly what was typed — in the
    // mode that was chosen.
    _priceController = TextEditingController(
      text: widget.draft.sellingPricePerKg == 0
          ? ''
          : _priceText(widget.draft.sellingPricePerKg),
    );

    _fixedPriceController = TextEditingController(
      text: widget.draft.fixedSalePrice == 0
          ? ''
          : _priceText(widget.draft.fixedSalePrice),
    );

    _discountController = TextEditingController(
      text: widget.draft.discount == 0
          ? ''
          : _priceText(widget.draft.discount),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _fixedPriceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _recalculate() {
    widget.draft.sellingPricePerKg =
        double.tryParse(_priceController.text.trim()) ?? 0;

    widget.draft.fixedSalePrice =
        double.tryParse(_fixedPriceController.text.trim()) ?? 0;

    widget.draft.discount =
        double.tryParse(_discountController.text.trim()) ?? 0;

    setState(() {});
  }

  void _setFixedPrice(bool fixed) {
    final mode = fixed ? Sale.pricingModeFixed : Sale.pricingModePerKg;

    if (widget.draft.pricingMode == mode) return;

    // The field that is about to disappear may hold the keyboard.
    FocusScope.of(context).unfocus();

    setState(() {
      widget.draft.pricingMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior:
        ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardSectionCard(
            title: 'Sale Details',
            icon: Icons.sell_outlined,
            children: [
              _ReadOnlyRow(
                icon: GoatIcons.paw,
                label: 'Goats in this Sale',
                value: '${draft.saleGoatCount}',
              ),
              const SizedBox(height: 12),
              _ReadOnlyRow(
                icon: Icons.scale_outlined,
                label: 'Total Selling Weight',
                value: '${SaleDraft.formatWeight(draft.totalSellingWeight)} KG',
              ),
              const SizedBox(height: 16),

              // How is this sale priced?
              PricingModeSlider(
                isFixed: draft.isFixedPrice,
                onChanged: _setFixedPrice,
              ),

              const SizedBox(height: 14),

              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: draft.isFixedPrice
                    ? _buildFixedPriceField(draft)
                    : _buildPerKgField(),
              ),

              const SizedBox(height: 14),

              _buildDiscountField(draft),
            ],
          ),

          const SizedBox(height: 14),

          _buildTotalCard(draft),
        ],
      ),
    );
  }

  // Only the field for the active mode is in the tree, so the wizard's
  // Next-button validation only ever checks the price that is in use.

  Widget _buildPerKgField() {
    // The key gives each mode its own field state, so an error shown on
    // one price never carries over to the other.
    return KeyedSubtree(
      key: const ValueKey('price-per-kg'),
      child: wizardField(
        controller: _priceController,
        label: 'Selling Price per KG',
        hint: '0.00',
        icon: Icons.currency_rupee_rounded,
        suffix: '/ KG',
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
        ),
        inputFormatters: _priceFormatters,
        onChanged: (_) => _recalculate(),
        validator: _validatePrice,
      ),
    );
  }

  Widget _buildFixedPriceField(SaleDraft draft) {
    return KeyedSubtree(
      key: const ValueKey('fixed-price'),
      child: wizardField(
        controller: _fixedPriceController,
        label: 'Fixed Selling Price',
        hint: '0.00',
        icon: Icons.currency_rupee_rounded,
        suffix: 'total',
        helper: draft.isMultiGoat
            ? 'One agreed price for all ${draft.saleGoatCount} goats'
            : 'One agreed price for this goat',
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
        ),
        inputFormatters: _priceFormatters,
        onChanged: (_) => _recalculate(),
        validator: _validatePrice,
      ),
    );
  }

  Widget _buildDiscountField(SaleDraft draft) {
    return wizardField(
      controller: _discountController,
      label: 'Discount',
      hint: '0.00',
      icon: Icons.local_offer_outlined,
      suffix: '₹ off',
      helper: 'Optional. Comes off the goat amount, not transport.',
      optional: true,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      inputFormatters: _priceFormatters,
      onChanged: (_) => _recalculate(),
      validator: _validateDiscount,
    );
  }

  /// Blank is fine (no discount). Otherwise it cannot be more than the goat
  /// amount.
  String? _validateDiscount(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) return null;

    final number = double.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid discount';
    }

    if (number > widget.draft.grossSaleAmount) {
      return 'Discount cannot be more than the goat amount';
    }

    return null;
  }

  /// Up to 2 decimals, digits only — same rule for both price fields.
  static final List<TextInputFormatter> _priceFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
  ];

  static String? _validatePrice(String? value) {
    final number = double.tryParse(value?.trim() ?? '');

    if (number == null || number <= 0) {
      return 'Enter a valid price';
    }

    return null;
  }

  Widget _buildTotalCard(SaleDraft draft) {
    final amount = draft.saleAmountAfterSaleDiscount;

    // Live, human-checkable working.
    //   By KG:       "52.8 kg × ₹520.00 / kg"
    //   Fixed price: "Fixed price · 52.8 kg ≈ ₹519.55 / kg"
    // Falls back to a generic hint until a price has been typed.
    final String formula;

    if (draft.isFixedPrice) {
      formula = draft.fixedSalePrice > 0
          ? 'Fixed price · '
          '${SaleDraft.formatWeight(draft.totalSellingWeight)} kg ≈ '
          '${_currency(draft.effectivePricePerKg)} / kg'
          : 'Agreed fixed price for the sale';
    } else {
      formula = draft.sellingPricePerKg > 0
          ? '${SaleDraft.formatWeight(draft.totalSellingWeight)} kg × '
          '${_currency(draft.sellingPricePerKg)} / kg'
          : 'Selling Weight × Price per KG';
    }

    // With a discount, show the working: goat amount - discount.
    final discounted = draft.saleDiscountApplied > 0
        ? '${_currency(draft.grossSaleAmount)} − '
        '${_currency(draft.saleDiscountApplied)} discount\n$formula'
        : formula;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              draft.isFixedPrice
                  ? Icons.sell_outlined
                  : Icons.calculate_outlined,
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
                  discounted,
                  maxLines: 3,
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
            // A money figure must never be cut off with "…" — shrink it
            // to fit instead.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _currency(amount),
                textAlign: TextAlign.right,
                maxLines: 1,
                style: AppTheme.heading(
                  size: 18,
                  color: AppColors.darkGreen,
                ),
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