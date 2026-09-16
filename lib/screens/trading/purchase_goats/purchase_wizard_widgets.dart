import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';

/// Shared UI building blocks for the Purchase Goats wizard.
///
/// This file contains the common cards, fields, date picker field,
/// computed rows, and step indicator used by Steps 1-4.
///
/// Trading uses the application's core green palette.
/// No Trading-specific blue color is used here.

// ============================================================================
// WIZARD SECTION CARD
// ============================================================================

/// A titled white card used to group related fields in the wizard.
class WizardSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const WizardSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ============================================================================
// WIZARD FIELD
// ============================================================================

/// Standard text form field used throughout the Purchase Goats wizard.
///
/// Intentionally does not expose `textCapitalization` because the current
/// wizard steps do not require it and the previous helper API did not define
/// that parameter.
Widget wizardField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  String? suffix,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int maxLines = 1,
  int? maxLength,
  bool optional = false,
  String? Function(String?)? validator,
  ValueChanged<String>? onChanged,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    maxLines: maxLines,
    maxLength: maxLength,
    onChanged: onChanged,
    validator: validator ??
            (value) {
          if (!optional && (value == null || value.trim().isEmpty)) {
            return 'Required';
          }
          return null;
        },
    style: AppTheme.body(
      size: 13,
      color: AppColors.textDark,
    ),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: AppColors.primaryGreen,
        size: 20,
      ),
      suffixText: suffix,
      counterText: maxLength != null ? '' : null,
      labelStyle: AppTheme.body(
        size: 12,
        color: AppColors.textGrey,
      ),
      hintStyle: AppTheme.body(
        size: 12,
        color: AppColors.textGrey,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AppColors.divider,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AppColors.divider,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AppColors.primaryGreen,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AppColors.error,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AppColors.error,
          width: 1.5,
        ),
      ),
    ),
  );
}

// ============================================================================
// WIZARD DATE FIELD
// ============================================================================

/// Tappable date field used throughout the Purchase Goats wizard.
class WizardDateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const WizardDateField({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(
            Icons.calendar_today_outlined,
            color: AppColors.primaryGreen,
            size: 20,
          ),
          labelStyle: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: AppColors.divider,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: AppColors.divider,
            ),
          ),
        ),
        child: Text(
          '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}/'
              '${date.year}',
          style: AppTheme.body(
            size: 13,
            color: AppColors.textDark,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// COMPUTED ROW
// ============================================================================

/// Read-only computed value row.
///
/// Used for values such as:
/// - Purchase Amount
/// - Weight Loss
/// - Transport Total
/// - Grand Total
/// - Effective Cost/Kg
///
/// These values are calculated automatically and are not manually editable.
class WizardComputedRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const WizardComputedRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: emphasize ? 14 : 13,
                color: emphasize
                    ? AppColors.textDark
                    : AppColors.textGrey,
                weight: emphasize
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(
                size: emphasize ? 16 : 14,
                color: emphasize
                    ? AppColors.primaryGreen
                    : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STEP INDICATOR
// ============================================================================

/// Step progress indicator shown at the top of the wizard.
///
/// `currentStep` is zero-based:
/// 0 = Step 1
/// 1 = Step 2
/// 2 = Step 3
/// 3 = Step 4
class WizardStepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> labels;

  const WizardStepIndicator({
    super.key,
    required this.currentStep,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final safeStep = currentStep.clamp(
      0,
      labels.isEmpty ? 0 : labels.length - 1,
    );

    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Progress bars.
        Row(
          children: List.generate(
            labels.length,
                (i) {
              final filled = i <= safeStep;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == labels.length - 1 ? 0 : 6,
                  ),
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: filled
                          ? AppColors.primaryGreen
                          : AppColors.divider,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Step number + current label.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step ${safeStep + 1} of ${labels.length}',
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
                weight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                labels[safeStep],
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.primaryGreen,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}