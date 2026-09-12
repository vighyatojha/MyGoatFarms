import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';

/// Picks a single farm-wide CALENDAR DATE that becomes the `nextDueDate`
/// for every new Vaccination or Hair Trimming record logged for any goat
/// in the farm, no matter which customer it belongs to.
///
/// This is the calendar-date counterpart to [ReminderCadenceSelector]
/// (used for Hoof Cutting's day-cadence). Unlike Hoof Cutting, the value
/// picked here is NOT relative to a record's own date — it is the exact
/// date saved in Health Reminder Settings, applied as-is to every new
/// record until it's changed again from Profile.
///
/// When [locked] is true (used on the Add Vaccination / Add Hair
/// Trimming screens), renders as a read-only summary with a lock icon —
/// [onChanged] is never called. This keeps farm-level Health Reminder
/// Settings the single source of truth; the Add screen only consumes it.
///
/// When [locked] is false (used on the Health Reminder Settings screen
/// itself), renders a switch to turn the reminder on/off plus a
/// tappable date field.
class ReminderDateSelector extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String label;

  /// True when the farm's Health Reminder Settings already governs this
  /// reminder. Renders a locked, read-only summary instead of a picker.
  final bool locked;

  /// Optional override for the locked-state explanatory note. Defaults
  /// to a standard "controlled from Health Reminder Settings" message.
  final String? lockedNote;

  const ReminderDateSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Next Due Date',
    this.locked = false,
    this.lockedNote,
  });

  @override
  Widget build(BuildContext context) {
    return locked ? _buildLocked(context) : _buildEditable(context);
  }

  // -----------------------------------------------------------------
  // Locked — farm's Health Reminder Settings already controls this.
  // -----------------------------------------------------------------
  Widget _buildLocked(BuildContext context) {
    final date = value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 16, color: AppColors.darkGreen),
              const SizedBox(width: 8),
              Text(
                date != null
                    ? DateFormat('d MMM yyyy').format(date)
                    : 'No reminder',
                style: AppTheme.body(
                  size: 14,
                  color: AppColors.darkGreen,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Selected in Health Reminder Settings',
            style: AppTheme.body(
              size: 12,
              color: AppColors.darkGreen,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            lockedNote ??
                'This due date was chosen in Profile → Health Reminder '
                    'Settings and applies to every active goat in the farm, '
                    'no matter which customer they belong to. It can\'t be '
                    'changed from this screen — update it from Profile → '
                    'Health Reminder Settings instead.',
            style: AppTheme.body(size: 11.5, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Editable — used only on the Health Reminder Settings screen.
  // -----------------------------------------------------------------
  Widget _buildEditable(BuildContext context) {
    final isOn = value != null;

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) onChanged(picked);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textMuted.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.body(size: 12, color: AppColors.textGrey),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No reminder',
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                  Switch(
                    value: isOn,
                    activeColor: AppColors.primaryGreen,
                    onChanged: (enabled) async {
                      if (!enabled) {
                        onChanged(null);
                        return;
                      }
                      await pickDate();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (isOn)
            InkWell(
              onTap: pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('d MMM yyyy').format(value!),
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.textDark,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Change',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.primaryGreen,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              'Off — turn on to pick a due date for every goat in the farm.',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
        ],
      ),
    );
  }
}