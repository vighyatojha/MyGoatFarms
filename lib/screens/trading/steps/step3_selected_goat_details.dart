import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_theme.dart';
import '../../../../models/goat_model.dart';
import '../../../../models/sale_draft.dart';

/// Step 3 — Selected Goat Details.
///
/// For each selected goat: Photo/ID/Breed/Gender/Age/Current Weight,
/// with weight editable (selling weight may differ slightly from last
/// recorded weight) — Task 2.3.
///
/// Gender is also editable here even though it isn't part of the plan's
/// literal field list: Trading's Goat model never captured it (see
/// Goat.gender's doc comment), so this is the one place it can be
/// filled in, and it's written back onto the goat record on save.
///
/// Exposes [validate] via its State, same pattern as Step2, so the
/// wizard can block advancing until every goat has a valid weight.
class Step3SelectedGoatDetails extends StatefulWidget {
  final SaleDraft draft;

  const Step3SelectedGoatDetails({
    super.key,
    required this.draft,
  });

  @override
  State<Step3SelectedGoatDetails> createState() =>
      Step3SelectedGoatDetailsState();
}

class Step3SelectedGoatDetailsState
    extends State<Step3SelectedGoatDetails> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _weightControllers = {};

  @override
  void initState() {
    super.initState();

    for (final goat in widget.draft.selectedGoats) {
      _weightControllers[goat.id] = TextEditingController(
        text: _trimZero(widget.draft.weightFor(goat)),
      );
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

  bool validate() {
    final valid = _formKey.currentState?.validate() ?? false;

    if (!valid) return false;

    for (final goat in widget.draft.selectedGoats) {
      final weight = double.tryParse(
        _weightControllers[goat.id]?.text.trim() ?? '',
      );

      if (weight != null) {
        widget.draft.setWeight(goat, weight);
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: widget.draft.selectedGoats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final goat = widget.draft.selectedGoats[index];

          return _GoatDetailCard(
            goat: goat,
            weightController: _weightControllers[goat.id]!,
            gender: widget.draft.genderFor(goat),
            onGenderChanged: (value) {
              setState(() {
                widget.draft.setGender(goat, value);
              });
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// GOAT DETAIL CARD
// ============================================================================

class _GoatDetailCard extends StatelessWidget {
  final Goat goat;
  final TextEditingController weightController;
  final String gender;
  final ValueChanged<String> onGenderChanged;

  const _GoatDetailCard({
    required this.goat,
    required this.weightController,
    required this.gender,
    required this.onGenderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------------------------------------------------------------
          // HEADER — PHOTO / ID / BREED
          // ---------------------------------------------------------------

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
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 12,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          goat.age,
                          style: AppTheme.body(
                            size: 10,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 14),

          // ---------------------------------------------------------------
          // GENDER
          // ---------------------------------------------------------------

          Text(
            'Gender',
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: Goat.genderValues.map((value) {
              final selected = gender == value;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => onGenderChanged(value),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryGreen
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.primaryGreen
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      value,
                      style: AppTheme.body(
                        size: 11,
                        color: selected
                            ? Colors.white
                            : AppColors.textGrey,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // ---------------------------------------------------------------
          // SELLING WEIGHT
          // ---------------------------------------------------------------

          Text(
            'Selling Weight',
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: weightController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d*\.?\d{0,2}'),
              ),
            ],
            style: AppTheme.body(size: 13, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: '0.00',
              suffixText: 'KG',
              prefixIcon: const Icon(
                Icons.monitor_weight_outlined,
                color: AppColors.primaryGreen,
                size: 20,
              ),
              filled: true,
              fillColor: AppColors.paleGreen,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) {
              final number = double.tryParse(value?.trim() ?? '');

              if (number == null || number <= 0) {
                return 'Enter a valid weight';
              }

              return null;
            },
          ),
        ],
      ),
    );
  }
}