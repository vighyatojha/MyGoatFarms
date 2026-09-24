import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';

/// Shared UI building blocks for the Trading wizards (Purchase + Sell).
///
/// Common cards, fields, date picker, popups and result cards live here so
/// every step looks and behaves the same way.
///
/// Trading uses the application's core green palette.

// ============================================================================
// FORMATTING HELPERS
// ============================================================================

final NumberFormat _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

/// ₹1,57,500.00 — Indian digit grouping, always 2 decimals.
String wizardCurrency(num value) {
  // `-0.0 == 0`, so this also stops "-₹0.00".
  return _inr.format(value == 0 ? 0 : value);
}

/// dd/MM/yyyy
String wizardDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

/// Allows digits and at most 2 decimals, e.g. "350", "350.5", "350.25".
List<TextInputFormatter> wizardDecimalFormatters() {
  return [
    FilteringTextInputFormatter.allow(
      RegExp(r'^\d*\.?\d{0,2}'),
    ),
  ];
}

const TextInputType wizardDecimalKeyboard =
TextInputType.numberWithOptions(decimal: true);

// ============================================================================
// POPUP HELPERS
// ============================================================================

/// Themed date picker used by every wizard date field.
///
/// `initialDate` is clamped into [firstDate, lastDate]; the raw
/// `showDatePicker` throws if it is outside the range (which used to
/// happen when a stored date fell before `firstDate`).
Future<DateTime?> showWizardDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  final first = day(firstDate);
  final last = day(lastDate).isBefore(first) ? first : day(lastDate);

  var initial = day(initialDate);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: helpText,
    builder: (context, child) {
      final theme = Theme.of(context);

      return Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: AppColors.primaryGreen,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.textDark,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: Colors.white,
            headerBackgroundColor: AppColors.primaryGreen,
            headerForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            // Today is often ALSO the selected day. Its number used to be
            // green on the green selection circle, so it vanished — keep it
            // white while selected, green otherwise.
            dayForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
              if (states.contains(WidgetState.disabled)) {
                return AppColors.textDark.withOpacity(0.3);
              }
              return AppColors.textDark;
            }),
            todayForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
              if (states.contains(WidgetState.disabled)) {
                return AppColors.textDark.withOpacity(0.3);
              }
              return AppColors.primaryGreen;
            }),
            todayBorder: const BorderSide(
              color: AppColors.primaryGreen,
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}

/// Floating snackbar that is dismissed before a new one shows, so messages
/// never queue up behind each other.
void wizardSnack(
    BuildContext context,
    String message, {
      bool error = false,
    }) {
  final messenger = ScaffoldMessenger.of(context);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
        error ? AppColors.error : AppColors.darkGreen,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTheme.body(
                  size: 12,
                  color: Colors.white,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

/// Confirmation dialog. Returns true only when the confirm button is tapped;
/// dismissing (tap outside / back) counts as cancel.
///
/// Use [destructive] when confirming throws something away — the confirm
/// button turns red so it is never mistaken for the safe choice.
Future<bool> showWizardConfirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final color =
  destructive ? AppColors.error : AppColors.primaryGreen;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 27),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textDark,
                      side: const BorderSide(
                        color: AppColors.divider,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      cancelLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  return result ?? false;
}

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

InputDecoration _wizardDecoration({
  required String label,
  String? hint,
  IconData? icon,
  String? prefix,
  String? suffix,
  String? helper,
  String? errorText,
  bool hideCounter = false,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperStyle: AppTheme.body(size: 10),
    errorText: errorText,
    errorStyle: AppTheme.body(
      size: 10,
      color: AppColors.error,
    ),
    errorMaxLines: 2,
    prefixIcon: icon == null
        ? null
        : Icon(icon, color: AppColors.primaryGreen, size: 20),
    prefixText: prefix,
    prefixStyle: AppTheme.body(
      size: 13,
      color: AppColors.textDark,
    ),
    suffixText: suffix,
    suffixStyle: AppTheme.body(
      size: 12,
      color: AppColors.textGrey,
      weight: FontWeight.w600,
    ),
    counterText: hideCounter ? '' : null,
    labelStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
    floatingLabelStyle: AppTheme.body(
      size: 12,
      color: AppColors.primaryGreen,
      weight: FontWeight.w600,
    ),
    hintStyle: AppTheme.body(
      size: 12,
      color: AppColors.textGrey.withOpacity(0.7),
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 14,
    ),
    border: border(AppColors.divider),
    enabledBorder: border(AppColors.divider),
    focusedBorder: border(AppColors.primaryGreen, 1.5),
    errorBorder: border(AppColors.error),
    focusedErrorBorder: border(AppColors.error, 1.5),
  );
}

/// Standard text form field used throughout the Trading wizards.
///
/// Required fields automatically get a " *" after the label (the PDF marks
/// required fields that way); pass `optional: true` to drop it.
///
/// Validation runs as the person interacts with the field, so an error
/// clears itself the moment it is fixed instead of sitting there until
/// Next is pressed again.
Widget wizardField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  String? prefix,
  String? suffix,
  String? helper,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  TextCapitalization textCapitalization = TextCapitalization.none,
  TextInputAction? textInputAction,
  int maxLines = 1,
  int? maxLength,
  bool optional = false,
  bool enabled = true,
  String? Function(String?)? validator,
  ValueChanged<String>? onChanged,
}) {
  return TextFormField(
    controller: controller,
    enabled: enabled,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    textCapitalization: textCapitalization,
    textInputAction: textInputAction ??
        (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
    maxLines: maxLines,
    maxLength: maxLength,
    onChanged: onChanged,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: validator ??
            (value) {
          if (!optional && (value == null || value.trim().isEmpty)) {
            return 'Required';
          }
          return null;
        },
    style: AppTheme.body(size: 13, color: AppColors.textDark),
    decoration: _wizardDecoration(
      label: optional ? label : '$label *',
      hint: hint,
      icon: icon,
      prefix: prefix,
      suffix: suffix,
      helper: helper,
      hideCounter: maxLength != null,
    ),
  );
}

// ============================================================================
// WIZARD DATE FIELD
// ============================================================================

/// Tappable date field used throughout the Trading wizards.
/// Dropdown styled like [wizardField] — same border, label and icon — so
/// a fixed list of choices looks like the rest of the wizard's inputs.
///
/// [value] must be one of [options].
Widget wizardDropdown({
  required String label,
  required String value,
  required List<String> options,
  required IconData icon,
  required ValueChanged<String> onChanged,
  String? helper,
}) {
  return InputDecorator(
    decoration: _wizardDecoration(
      label: label,
      icon: icon,
      helper: helper,
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: options.contains(value) ? value : null,
        isExpanded: true,
        isDense: true,
        borderRadius: BorderRadius.circular(13),
        icon: const Icon(
          Icons.expand_more_rounded,
          color: AppColors.textGrey,
        ),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
        dropdownColor: Colors.white,
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
            value: option,
            child: Text(option),
          ),
        )
            .toList(),
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      ),
    ),
  );
}

class WizardDateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  final String? helper;
  final String? errorText;

  const WizardDateField({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
    this.helper,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: InputDecorator(
        decoration: _wizardDecoration(
          label: label,
          icon: Icons.calendar_today_outlined,
          helper: helper,
          errorText: errorText,
        ).copyWith(
          suffixIcon: const Icon(
            Icons.expand_more_rounded,
            color: AppColors.textGrey,
          ),
        ),
        child: Text(
          wizardDate(date),
          style: AppTheme.body(size: 13, color: AppColors.textDark),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: AppTheme.body(
                size: emphasize ? 14 : 13,
                color: emphasize
                    ? AppColors.textDark
                    : AppColors.textGrey,
                weight:
                emphasize ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
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
// RESULT CARD (big live number)
// ============================================================================

/// Highlighted card for a live, calculated amount.
///
/// The amount shrinks to fit rather than being cut off with "…" — a money
/// figure must never be truncated.
class WizardResultCard extends StatelessWidget {
  final IconData icon;
  final String title;

  /// The working, e.g. "350 kg × ₹450 / kg".
  final String formula;
  final String value;

  const WizardResultCard({
    super.key,
    required this.icon,
    required this.title,
    required this.formula,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Icon(icon, color: AppColors.darkGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formula,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 5,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                textAlign: TextAlign.right,
                style: AppTheme.heading(
                  size: 19,
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
// STAT CHIP (small live fact)
// ============================================================================

/// Small label + value tile, used in pairs for quick live facts such as
/// "Avg weight / goat".
class WizardStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const WizardStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 10),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTheme.heading(
                      size: 13,
                      color: AppColors.textDark,
                    ),
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

// ============================================================================
// NOTE (inline info / warning)
// ============================================================================

enum WizardNoteTone { info, warning, error }

/// One-line explanatory or warning message with an icon.
class WizardNote extends StatelessWidget {
  final String text;
  final WizardNoteTone tone;

  const WizardNote(
      this.text, {
        super.key,
        this.tone = WizardNoteTone.info,
      });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;

    switch (tone) {
      case WizardNoteTone.warning:
        color = const Color(0xFFB26A00);
        icon = Icons.warning_amber_rounded;
        break;
      case WizardNoteTone.error:
        color = AppColors.error;
        icon = Icons.error_outline_rounded;
        break;
      case WizardNoteTone.info:
        color = AppColors.textGrey;
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone == WizardNoteTone.info
            ? AppColors.paleGreen
            : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(size: 11, color: color),
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
/// `currentStep` is zero-based and refers to a position in [labels], so a
/// wizard that skips a step simply passes fewer labels and the bar and the
/// "Step x of y" text both stay honest.
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
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    final safeStep = currentStep.clamp(0, labels.length - 1);

    return Column(
      children: [
        Row(
          children: List.generate(labels.length, (i) {
            final filled = i <= safeStep;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == labels.length - 1 ? 0 : 6,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
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
          }),
        ),
        const SizedBox(height: 8),
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