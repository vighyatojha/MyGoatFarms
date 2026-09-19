import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_draft.dart';
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
/// Purchase Amount is always calculated, live, as:
/// Total Weight × Price per KG
///
/// Every figure on this screen comes from [PurchaseCosting] (via the draft),
/// so it is the same number that is later shown in the summary and saved.
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

class _Step2PurchaseDetailsState extends State<Step2PurchaseDetails> {
  late final TextEditingController _totalGoatsController;
  late final TextEditingController _weightController;
  late final TextEditingController _priceController;

  /// Goats outside this average live weight are almost certainly a typo
  /// (an extra digit, or weight typed in grams). Only a warning — never
  /// blocks, because unusual lots do exist.
  static const double _minPlausibleKgPerGoat = 3;
  static const double _maxPlausibleKgPerGoat = 120;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _totalGoatsController = TextEditingController(
      text: draft.totalGoats == 0 ? '' : draft.totalGoats.toString(),
    );

    _weightController = TextEditingController(
      text: draft.totalWeightAtPurchase == 0
          ? ''
          : PurchaseCosting.formatNumber(draft.totalWeightAtPurchase),
    );

    _priceController = TextEditingController(
      text: draft.pricePerKg == 0
          ? ''
          : PurchaseCosting.formatNumber(draft.pricePerKg),
    );
  }

  @override
  void dispose() {
    _totalGoatsController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// Pushes what is typed into the draft on EVERY keystroke and rebuilds,
  /// so the Purchase Amount card is always live.
  void _recalculate() {
    final draft = widget.draft;

    draft.totalGoats = int.tryParse(_totalGoatsController.text.trim()) ?? 0;

    draft.totalWeightAtPurchase =
        double.tryParse(_weightController.text.trim()) ?? 0;

    draft.pricePerKg = double.tryParse(_priceController.text.trim()) ?? 0;

    setState(() {});
  }

  void _setPaymentMethod(String method) {
    setState(() {
      widget.draft.setPaymentMethod(method);
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final costing = draft.costing;

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardSectionCard(
            title: 'Purchase Details',
            icon: Icons.shopping_cart_outlined,
            children: [
              wizardField(
                controller: _totalGoatsController,
                label: 'Total Number of Goats',
                hint: 'e.g. 20',
                icon: Icons.pets_outlined,
                suffix: 'goats',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (_) => _recalculate(),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');

                  if (number == null || number <= 0) {
                    return 'Enter a valid goat count';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _weightController,
                label: 'Total Weight at Purchase',
                hint: '0.00',
                icon: Icons.scale_outlined,
                suffix: 'KG',
                keyboardType: wizardDecimalKeyboard,
                inputFormatters: wizardDecimalFormatters(),
                onChanged: (_) => _recalculate(),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number <= 0) {
                    return 'Enter a valid weight';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _priceController,
                label: 'Price per KG',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                suffix: '/ KG',
                keyboardType: wizardDecimalKeyboard,
                inputFormatters: wizardDecimalFormatters(),
                textInputAction: TextInputAction.done,
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

          // -------------------------------------------------------------
          // LIVE PURCHASE AMOUNT
          // -------------------------------------------------------------

          WizardResultCard(
            icon: Icons.calculate_outlined,
            title: 'Purchase Amount',
            formula: costing.weightAtPurchase > 0 && costing.pricePerKg > 0
                ? '${PurchaseCosting.formatNumber(costing.weightAtPurchase)} kg × '
                '${wizardCurrency(costing.pricePerKg)} / kg'
                : 'Total Weight × Price per KG',
            value: wizardCurrency(costing.purchaseAmount),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: WizardStatTile(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Avg weight / goat',
                  value: costing.totalGoats > 0 &&
                      costing.weightAtPurchase > 0
                      ? '${PurchaseCosting.formatNumber(costing.avgWeightPerGoatAtPurchase)} kg'
                      : '—',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WizardStatTile(
                  icon: Icons.sell_outlined,
                  label: 'Avg price / goat',
                  value: costing.totalGoats > 0 &&
                      costing.purchaseAmount > 0
                      ? wizardCurrency(costing.purchaseAmountPerGoat)
                      : '—',
                ),
              ),
            ],
          ),

          if (_looksImplausible(costing)) ...[
            const SizedBox(height: 10),
            WizardNote(
              'That works out to '
                  '${PurchaseCosting.formatNumber(costing.avgWeightPerGoatAtPurchase)} kg '
                  'per goat. Please double-check the goat count and '
                  'total weight.',
              tone: WizardNoteTone.warning,
            ),
          ],

          const SizedBox(height: 14),

          // -------------------------------------------------------------
          // PAYMENT METHOD
          // -------------------------------------------------------------

          WizardSectionCard(
            title: 'Payment Method',
            icon: Icons.payments_outlined,
            children: [
              Text(
                'How is the seller being paid?',
                style: AppTheme.body(size: 11),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PaymentOption(
                      title: 'Cash',
                      icon: Icons.money_rounded,
                      selected: draft.paymentMethod == 'Cash',
                      onTap: () => _setPaymentMethod('Cash'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PaymentOption(
                      title: 'Online',
                      icon: Icons.account_balance_wallet_outlined,
                      selected: draft.paymentMethod == 'Online',
                      onTap: () => _setPaymentMethod('Online'),
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

  bool _looksImplausible(PurchaseCosting costing) {
    if (costing.totalGoats <= 0 || costing.weightAtPurchase <= 0) {
      return false;
    }

    final avg = costing.avgWeightPerGoatAtPurchase;

    return avg < _minPlausibleKgPerGoat || avg > _maxPlausibleKgPerGoat;
  }
}

// ============================================================================
// PAYMENT OPTION
// ============================================================================

class _PaymentOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color:
                selected ? AppColors.darkGreen : AppColors.textGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 13,
                    color: selected
                        ? AppColors.darkGreen
                        : AppColors.textDark,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.primaryGreen,
                ),
            ],
          ),
        ),
      ),
    );
  }
}