import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/lot_transfer_models.dart';
import '../../../models/trading_purchase_model.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// The "who are these goats" form shared by both lot transfers (Own Palai
/// and Customer Palai).
///
/// Goats in a lot are anonymous. The moment they are transferred each one
/// becomes an individual record, so this collects what Goat Registration
/// would: breed, age, color and health are entered once and applied to
/// every goat; weight and (optionally) gender are per goat.
///
/// Gender defaults to "Auto", which lets the transfer draw from what is
/// left of the lot's Male / Female split — the same rule Goat
/// Registration uses. Photos, height and length are not asked here; they
/// can be added from the goat's own profile afterwards.
///
/// The parent reads the result through the State (same pattern as the
/// wizard steps): [LotTransferGoatsFormState.validate] and
/// [LotTransferGoatsFormState.buildGoats].
class LotTransferGoatsForm extends StatefulWidget {
  final TradingPurchase lot;

  /// Most goats that can be transferred right now
  /// (lot.farmAvailableQty, capped by the per-transfer limit).
  final int maxQuantity;

  /// Called whenever the quantity changes, so the parent can refresh
  /// anything that shows it (button label, totals).
  final ValueChanged<int>? onQuantityChanged;

  /// Restores an earlier entry when the person navigates back to this
  /// step in a wizard. Null starts empty.
  final List<LotTransferGoat>? initialGoats;

  const LotTransferGoatsForm({
    super.key,
    required this.lot,
    required this.maxQuantity,
    this.onQuantityChanged,
    this.initialGoats,
  });

  @override
  State<LotTransferGoatsForm> createState() => LotTransferGoatsFormState();
}

class LotTransferGoatsFormState extends State<LotTransferGoatsForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _fillWeightController = TextEditingController();

  String _healthStatus = Goat.healthStatusValues.first;

  final List<TextEditingController> _weightControllers = [];

  /// '' = Auto, otherwise one of [Goat.genderValues].
  final List<String> _genders = [];

  int get quantity => _weightControllers.length;

  int get _cap {
    final c = widget.maxQuantity;
    if (c < 0) return 0;
    return c > LotTransferPlanner.maxGoatsPerTransfer
        ? LotTransferPlanner.maxGoatsPerTransfer
        : c;
  }

  bool get _hasSplit =>
      widget.lot.maleGoats > 0 || widget.lot.femaleGoats > 0;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialGoats;

    if (initial != null && initial.isNotEmpty) {
      final first = initial.first;

      _breedController.text = first.breed;
      _ageController.text = first.ageMonths.toString();
      _colorController.text = first.color;

      if (Goat.healthStatusValues.contains(first.healthStatus)) {
        _healthStatus = first.healthStatus;
      }

      _quantityController.text = initial.length.toString();

      for (final g in initial) {
        _weightControllers.add(
          TextEditingController(text: _plain(g.weight)),
        );
        _genders.add(g.gender);
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _colorController.dispose();
    _fillWeightController.dispose();

    for (final c in _weightControllers) {
      c.dispose();
    }

    super.dispose();
  }

  String _plain(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  // ---------------------------------------------------------------------
  // QUANTITY
  // ---------------------------------------------------------------------

  void _setQuantity(int wanted) {
    final n = wanted < 0 ? 0 : (wanted > _cap ? _cap : wanted);

    setState(() {
      while (_weightControllers.length < n) {
        _weightControllers.add(TextEditingController());
        _genders.add('');
      }

      while (_weightControllers.length > n) {
        _weightControllers.removeLast().dispose();
        _genders.removeLast();
      }
    });

    widget.onQuantityChanged?.call(n);
  }

  void _applyFillWeight() {
    final w = double.tryParse(_fillWeightController.text.trim());

    if (w == null || w <= 0) {
      wizardSnack(context, 'Enter a valid weight to fill in.', error: true);
      return;
    }

    if (_weightControllers.isEmpty) {
      wizardSnack(context, 'Enter the number of goats first.', error: true);
      return;
    }

    setState(() {
      for (final c in _weightControllers) {
        c.text = _plain(w);
      }
    });
  }

  // ---------------------------------------------------------------------
  // RESULT (read by the parent)
  // ---------------------------------------------------------------------

  /// Runs every field's validator. Returns false (and shows the errors)
  /// when anything is missing or invalid.
  bool validate() => _formKey.currentState?.validate() ?? false;

  /// The goats entered, in row order. Call [validate] first.
  List<LotTransferGoat> buildGoats() {
    final age = int.tryParse(_ageController.text.trim()) ?? 0;

    return [
      for (var i = 0; i < _weightControllers.length; i++)
        LotTransferGoat(
          breed: _breedController.text.trim(),
          ageMonths: age,
          weight: double.tryParse(_weightControllers[i].text.trim()) ?? 0,
          color: _colorController.text.trim(),
          healthStatus: _healthStatus,
          gender: _genders[i],
        ),
    ];
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;

    final maleLeft = lot.maleGoats - lot.maleRegistered;
    final femaleLeft = lot.femaleGoats - lot.femaleRegistered;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardSectionCard(
            title: 'Goats to transfer',
            icon: Icons.inventory_2_outlined,
            children: [
              WizardComputedRow(
                label: 'Free at the farm',
                value: '${lot.farmAvailableQty} goats',
              ),
              if (lot.reservedFarmQty > 0)
                WizardComputedRow(
                  label: 'Reserved for customers',
                  value: '${lot.reservedFarmQty} goats',
                ),
              const SizedBox(height: 8),
              wizardField(
                controller: _quantityController,
                label: 'Number of Goats',
                hint: 'Up to $_cap',
                icon: GoatIcons.paw,
                suffix: 'goats',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (v) => _setQuantity(int.tryParse(v.trim()) ?? 0),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');

                  if (n == null || n <= 0) return 'Enter a valid count';
                  if (n > _cap) return 'Only $_cap can be transferred';

                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          WizardSectionCard(
            title: 'Goat details (same for every goat)',
            icon: Icons.pets_outlined,
            children: [
              wizardField(
                controller: _breedController,
                label: 'Breed',
                hint: 'e.g. Sirohi',
                icon: GoatIcons.paw,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: wizardField(
                      controller: _ageController,
                      label: 'Age',
                      hint: 'Months',
                      icon: Icons.cake_outlined,
                      suffix: 'months',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      validator: (value) {
                        final n = int.tryParse(value?.trim() ?? '');

                        if (n == null || n <= 0) return 'Enter whole months';

                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: wizardField(
                      controller: _colorController,
                      label: 'Color',
                      hint: 'e.g. White',
                      icon: Icons.palette_outlined,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              wizardDropdown(
                label: 'Health Status',
                value: _healthStatus,
                options: Goat.healthStatusValues,
                icon: Icons.favorite_border_rounded,
                onChanged: (v) => setState(() => _healthStatus = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          WizardSectionCard(
            title: 'Weight & gender per goat',
            icon: Icons.scale_outlined,
            children: [
              if (_hasSplit)
                WizardNote(
                  'Left in this lot\'s split: '
                      '${maleLeft < 0 ? 0 : maleLeft} male, '
                      '${femaleLeft < 0 ? 0 : femaleLeft} female. '
                      'Leave a goat on Auto to draw from it.',
                )
              else
                const WizardNote(
                  'This lot has no Male / Female split recorded, so '
                      'gender stays empty unless you pick one.',
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: wizardField(
                      controller: _fillWeightController,
                      label: 'Same weight for all',
                      hint: '0.0',
                      icon: Icons.scale_outlined,
                      suffix: 'KG',
                      optional: true,
                      keyboardType: wizardDecimalKeyboard,
                      inputFormatters: wizardDecimalFormatters(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _applyFillWeight,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          side: BorderSide(
                            color: AppColors.primaryGreen.withOpacity(0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_weightControllers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Enter the number of goats above to list them here.',
                    style: AppTheme.body(size: 12),
                  ),
                )
              else
                for (var i = 0; i < _weightControllers.length; i++)
                  _goatRow(i),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goatRow(int index) {
    final autoLabel = _hasSplit ? 'Auto' : 'Not set';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          wizardField(
            controller: _weightControllers[index],
            label: 'Goat ${index + 1} weight',
            hint: '0.0',
            icon: Icons.scale_outlined,
            suffix: 'KG',
            keyboardType: wizardDecimalKeyboard,
            inputFormatters: wizardDecimalFormatters(),
            validator: (value) {
              final n = double.tryParse(value?.trim() ?? '');

              if (n == null || n <= 0) return 'Enter a valid weight';

              return null;
            },
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _genderChip(index, '', autoLabel),
              _genderChip(index, Goat.genderValues[0], 'Male'),
              _genderChip(index, Goat.genderValues[1], 'Female'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _genderChip(int index, String value, String label) {
    final selected = _genders[index] == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _genders[index] = value),
      selectedColor: AppColors.lightGreen,
      backgroundColor: Colors.white,
      labelStyle: AppTheme.body(
        size: 12,
        color: selected ? AppColors.darkGreen : AppColors.textGrey,
        weight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected ? AppColors.primaryGreen : AppColors.divider,
      ),
    );
  }
}