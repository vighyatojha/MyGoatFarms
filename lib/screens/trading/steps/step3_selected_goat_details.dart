import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_theme.dart';
import '../../../../models/goat_model.dart';
import '../../../../models/sale_draft.dart';

/// Step 3 — Selected Goat Details (Task 2.3).
///
/// Shows Photo / ID / Breed / Gender / Age / Current Weight for every
/// goat picked on Step 1, with Selling Weight editable per goat — the
/// selling weight may differ slightly from the last recorded weight.
///
/// Gender note: Trading's Goat model has no `gender` field (see
/// lib/models/goat_model.dart) — it's tracked for Own Farm and Palai
/// goats but was never added when Trading's Goat Registration was
/// built. Backfilling it there means touching Registration end-to-end
/// and leaves every already-registered goat blank until re-edited —
/// real scope creep for this phase. So Gender here is a per-sale,
/// optional field: it lives only in SaleDraft.genderOverrides, shown
/// on this card for the seller's own record-keeping, and is never
/// written back to the goat doc.
class Step3SelectedGoatDetails extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final SaleDraft draft;

  const Step3SelectedGoatDetails({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<Step3SelectedGoatDetails> createState() =>
      _Step3SelectedGoatDetailsState();
}

class _Step3SelectedGoatDetailsState
    extends State<Step3SelectedGoatDetails> {
  late final Map<String, TextEditingController> _weightControllers;

  static const List<String> _genderOptions = ['Male', 'Female'];

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _weightControllers = {
      for (final goat in draft.selectedGoats)
        goat.id: TextEditingController(
          text: _trimZero(draft.sellingWeightFor(goat)),
        ),
    };

    // Seed the draft with the current weight for any goat that hasn't
    // had a selling weight set yet, so totalSellingWeight is correct
    // even before the person touches a field.
    for (final goat in draft.selectedGoats) {
      draft.sellingWeights.putIfAbsent(goat.id, () => goat.weight);
    }
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setGender(String goatId, String? gender) {
    setState(() {
      if (gender == null || gender.isEmpty) {
        widget.draft.genderOverrides.remove(goatId);
      } else {
        widget.draft.genderOverrides[goatId] = gender;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Confirm each goat\'s selling weight below — it can differ '
                'slightly from the last recorded weight.',
            style: AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
          const SizedBox(height: 14),
          for (final goat in draft.selectedGoats) ...[
            _GoatDetailCard(
              goat: goat,
              weightController: _weightControllers[goat.id]!,
              gender: draft.genderOverrides[goat.id],
              genderOptions: _genderOptions,
              onGenderChanged: (value) => _setGender(goat.id, value),
              onWeightChanged: (value) {
                final parsed = double.tryParse(value.trim());
                draft.sellingWeights[goat.id] = parsed ?? goat.weight;
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _GoatDetailCard extends StatelessWidget {
  final Goat goat;
  final TextEditingController weightController;
  final String? gender;
  final List<String> genderOptions;
  final ValueChanged<String?> onGenderChanged;
  final ValueChanged<String> onWeightChanged;

  const _GoatDetailCard({
    required this.goat,
    required this.weightController,
    required this.gender,
    required this.genderOptions,
    required this.onGenderChanged,
    required this.onWeightChanged,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedGender =
    gender != null && genderOptions.contains(gender) ? gender : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------------------------------------------------------------
          // PHOTO + ID + BREED
          // -------------------------------------------------------------
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.stockTeal.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: goat.photo != null
                    ? Image.memory(goat.photo!, fit: BoxFit.cover)
                    : const Icon(
                  Icons.pets_outlined,
                  color: AppColors.stockTeal,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goat.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goat.breed.isEmpty
                          ? 'Breed not specified'
                          : goat.breed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // -------------------------------------------------------------
          // AGE + RECORDED WEIGHT (read-only)
          // -------------------------------------------------------------
          Row(
            children: [
              Expanded(
                child: _readOnlyStat(
                  icon: Icons.calendar_month_outlined,
                  label: 'Age',
                  value: goat.age,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _readOnlyStat(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Recorded Weight',
                  value: '${goat.weight.toStringAsFixed(1)} kg',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // -------------------------------------------------------------
          // GENDER (optional, draft-only) + SELLING WEIGHT (editable)
          // -------------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: resolvedGender,
                  decoration: _fieldDecoration(
                    label: 'Gender (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Not specified'),
                    ),
                    for (final option in genderOptions)
                      DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      ),
                  ],
                  onChanged: onGenderChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  onChanged: onWeightChanged,
                  validator: (value) {
                    final number = double.tryParse(value?.trim() ?? '');

                    if (number == null || number <= 0) {
                      return 'Enter weight';
                    }

                    return null;
                  },
                  decoration: _fieldDecoration(
                    label: 'Selling Weight',
                    suffix: 'KG',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppColors.primaryGreen,
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }

  Widget _readOnlyStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textGrey),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(size: 9, color: AppColors.textGrey),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 11,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}