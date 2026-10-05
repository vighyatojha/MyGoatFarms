import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../goat_icons.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_draft.dart';
import '../../../models/trading_purchase_model.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 2 — Lot Details.
///
/// Fields:
/// - Total Goats
/// - Male Goats / Female Goats (optional; if entered they must add up to
///   Total Goats)
/// - Total Weight at Purchase
/// - Pricing: By KG (Price per KG) or Fixed Price (one agreed amount for
///   the whole lot) — the same slider the Sell wizard uses
/// (Payment moved to its own step — see step_lot_payment.dart.)
///
/// Breed has intentionally been removed from the Trading purchase flow.
///
/// The Male/Female gender split lives here — a batch count taken at
/// purchase time — rather than on the Register Goat screen, since goats
/// are bought and counted as a lot, not registered one at a time with a
/// gender choice each.
///
/// Purchase Amount is calculated live: Total Weight × Price per KG (By KG),
/// or the agreed amount itself (Fixed Price).
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
  late final TextEditingController _fixedPriceController;
  late final TextEditingController _maleGoatsController;
  late final TextEditingController _femaleGoatsController;

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

    _fixedPriceController = TextEditingController(
      text: draft.fixedPurchaseAmount == 0
          ? ''
          : PurchaseCosting.formatNumber(draft.fixedPurchaseAmount),
    );

    _maleGoatsController = TextEditingController(
      text: draft.maleGoats == 0 ? '' : draft.maleGoats.toString(),
    );

    _femaleGoatsController = TextEditingController(
      text: draft.femaleGoats == 0 ? '' : draft.femaleGoats.toString(),
    );
  }

  @override
  void dispose() {
    _totalGoatsController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    _fixedPriceController.dispose();
    _maleGoatsController.dispose();
    _femaleGoatsController.dispose();
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

    draft.fixedPurchaseAmount =
        double.tryParse(_fixedPriceController.text.trim()) ?? 0;

    draft.maleGoats =
        int.tryParse(_maleGoatsController.text.trim()) ?? 0;

    draft.femaleGoats =
        int.tryParse(_femaleGoatsController.text.trim()) ?? 0;

    setState(() {});
  }

  void _setFixedPrice(bool fixed) {
    final mode = fixed
        ? TradingPurchase.pricingModeFixed
        : TradingPurchase.pricingModePerKg;

    if (widget.draft.pricingMode == mode) return;

    // The field that is about to disappear may hold the keyboard.
    FocusScope.of(context).unfocus();

    setState(() => widget.draft.pricingMode = mode);
  }

  String? _validatePrice(String? value) {
    final number = double.tryParse(value?.trim() ?? '');

    if (number == null || number <= 0) {
      return 'Enter a valid price';
    }

    return null;
  }

  /// Shared validator for both the Male and Female fields: reads straight
  /// from the controllers (rather than the draft) so it's correct even
  /// mid-keystroke, before [_recalculate] has run for this field.
  String? _validateGenderSplit(PurchaseDraft draft) {
    final total = int.tryParse(_totalGoatsController.text.trim()) ?? 0;
    final male = int.tryParse(_maleGoatsController.text.trim()) ?? 0;
    final female = int.tryParse(_femaleGoatsController.text.trim()) ?? 0;

    if (male < 0 || female < 0) {
      return 'Enter a valid count';
    }

    // Optional (PDF §4): both blank / zero means no split is recorded.
    if (male == 0 && female == 0) return null;

    if (total > 0 && (male + female) != total) {
      return 'Must add up to $total';
    }

    return null;
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
            title: 'Lot Details',
            icon: Icons.shopping_cart_outlined,
            children: [
              wizardField(
                controller: _totalGoatsController,
                label: 'Total Number of Goats',
                hint: 'e.g. 20',
                icon: GoatIcons.paw,
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

              // ---------------------------------------------------------
              // GENDER SPLIT — Male / Female goats, captured here as a
              // batch count rather than per-goat during Registration.
              // ---------------------------------------------------------

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: wizardField(
                      controller: _maleGoatsController,
                      label: 'Male Goats (optional)',
                      hint: 'e.g. 12',
                      icon: Icons.male_rounded,
                      suffix: 'male',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      onChanged: (_) => _recalculate(),
                      validator: (_) => _validateGenderSplit(draft),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: wizardField(
                      controller: _femaleGoatsController,
                      label: 'Female Goats (optional)',
                      hint: 'e.g. 8',
                      icon: Icons.female_rounded,
                      suffix: 'female',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      onChanged: (_) => _recalculate(),
                      validator: (_) => _validateGenderSplit(draft),
                    ),
                  ),
                ],
              ),

              if (draft.totalGoats > 0 &&
                  draft.hasGenderSplit &&
                  !draft.genderCountIsValid) ...[
                const SizedBox(height: 10),
                WizardNote(
                  (draft.maleGoats + draft.femaleGoats) < draft.totalGoats
                      ? 'Male + Female should add up to the '
                      '${draft.totalGoats} goats purchased — '
                      '${draft.totalGoats - (draft.maleGoats + draft.femaleGoats)} '
                      'more to account for.'
                      : 'Male + Female comes to '
                      '${draft.maleGoats + draft.femaleGoats}, which is '
                      'more than the ${draft.totalGoats} goats purchased.',
                  tone: WizardNoteTone.warning,
                ),
              ],

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

              // How is this lot priced? Only the field for the active
              // mode is in the tree, so Next only validates the price in
              // use.
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
                    ? KeyedSubtree(
                  key: const ValueKey('purchase-fixed-price'),
                  child: wizardField(
                    controller: _fixedPriceController,
                    label: 'Fixed Purchase Price',
                    hint: '0.00',
                    icon: Icons.currency_rupee_rounded,
                    suffix: 'total',
                    helper: 'One agreed price for the whole lot',
                    keyboardType: wizardDecimalKeyboard,
                    inputFormatters: wizardDecimalFormatters(),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _recalculate(),
                    validator: _validatePrice,
                  ),
                )
                    : KeyedSubtree(
                  key: const ValueKey('purchase-price-per-kg'),
                  child: wizardField(
                    controller: _priceController,
                    label: 'Price per KG',
                    hint: '0.00',
                    icon: Icons.currency_rupee_rounded,
                    suffix: '/ KG',
                    keyboardType: wizardDecimalKeyboard,
                    inputFormatters: wizardDecimalFormatters(),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _recalculate(),
                    validator: _validatePrice,
                  ),
                ),
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
            formula: draft.isFixedPrice
                ? (costing.weightAtPurchase > 0 && costing.purchaseAmount > 0
                ? 'Fixed price · '
                '${PurchaseCosting.formatNumber(costing.weightAtPurchase)} kg '
                '≈ ${wizardCurrency(costing.effectivePricePerKg)} / kg'
                : 'Fixed price for the whole lot')
                : costing.weightAtPurchase > 0 && costing.pricePerKg > 0
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