import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 3 — Selected Goat Details.
///
/// For each selected goat: Photo/ID/Breed/Gender/Age/Current Weight,
/// with weight editable (selling weight may differ slightly from last
/// recorded weight) — Task 2.3.
///
/// Gender is shown here read-only. It's captured once, during Trading's
/// Goat Registration (see Goat.gender's doc comment) — this screen only
/// displays whatever was recorded then; it is never asked or edited
/// again during a sale.
///
/// Weights are pushed into the [SaleDraft] on EVERY keystroke (not only
/// when Next is pressed), so:
///  - the live "Total Selling Weight" bar below is always accurate, and
///  - pressing Back and returning never loses an edited weight.
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
        text: SaleDraft.formatWeight(widget.draft.weightFor(goat)),
      );
    }
  }

  /// Live sync: called on every keystroke in a weight field.
  ///
  /// A blank / invalid field counts as 0 kg in the live total so the total
  /// always reflects exactly what is typed. [validate] still refuses to
  /// continue until every goat has a weight above zero.
  void _onWeightChanged(Goat goat, String text) {
    final parsed = double.tryParse(text.trim()) ?? 0;

    setState(() {
      widget.draft.setWeight(goat, parsed);
    });
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool validate() {
    final formValid = _formKey.currentState?.validate() ?? false;

    // The list is lazily built, so a Form only validates the goats that
    // are currently on screen. With many goats selected, one scrolled
    // out of view could slip through with a blank weight. Check every
    // controller explicitly.
    String? firstInvalidGoatId;

    for (final goat in widget.draft.selectedGoats) {
      final weight = double.tryParse(
        _weightControllers[goat.id]?.text.trim() ?? '',
      );

      if (weight == null || weight <= 0) {
        firstInvalidGoatId ??= goat.id;
        continue;
      }

      widget.draft.setWeight(goat, weight);
    }

    if (firstInvalidGoatId != null) {
      // If the visible fields were fine, the invalid one is off-screen —
      // the inline error text can't help, so say which goat it is.
      if (formValid) {
        wizardSnack(
          context,
          'Enter a valid selling weight for $firstInvalidGoatId.',
          error: true,
        );
      }

      return false;
    }

    return formValid;
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView.separated(
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: draft.selectedGoats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final goat = draft.selectedGoats[index];

                return _GoatDetailCard(
                  goat: goat,
                  weightController: _weightControllers[goat.id]!,
                  onWeightChanged: (value) =>
                      _onWeightChanged(goat, value),
                );
              },
            ),
          ),
        ),

        // -------------------------------------------------------------
        // LIVE TOTAL — pinned, so it stays visible while scrolling
        // through many goats and while the keyboard is open.
        // -------------------------------------------------------------
        _buildTotalBar(draft),
      ],
    );
  }

  Widget _buildTotalBar(SaleDraft draft) {
    final count = draft.selectedGoats.length;
    final total = draft.totalSellingWeight;
    final recorded = draft.totalRecordedWeight;
    final diff = SaleDraft.round2(total - recorded);

    final diffText = diff == 0
        ? 'Same as recorded weight'
        : '${diff > 0 ? '+' : '−'}${SaleDraft.formatWeight(diff.abs())} kg '
        'vs recorded ${SaleDraft.formatWeight(recorded)} kg';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.scale_outlined,
              color: AppColors.darkGreen,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Selling Weight · $count '
                      'goat${count == 1 ? '' : 's'}',
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  diffText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${SaleDraft.formatWeight(total)} KG',
            style: AppTheme.heading(
              size: 17,
              color: AppColors.darkGreen,
            ),
          ),
        ],
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
  final ValueChanged<String> onWeightChanged;

  const _GoatDetailCard({
    required this.goat,
    required this.weightController,
    required this.onWeightChanged,
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
                  GoatIcons.paw,
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
                        if (goat.gender.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(
                            goat.gender == 'Female'
                                ? Icons.female_rounded
                                : Icons.male_rounded,
                            size: 13,
                            color: AppColors.textGrey,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            goat.gender,
                            style: AppTheme.body(
                              size: 10,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
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
            onChanged: onWeightChanged,
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
              helperText:
              'Last recorded: ${SaleDraft.formatWeight(goat.weight)} kg',
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