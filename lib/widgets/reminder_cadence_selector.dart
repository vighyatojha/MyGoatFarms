import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Picks the reminder cadence (in days) for a vaccination / hoof-cutting /
/// hair-trimming record: how many days after the record's date the next
/// occurrence is due.
///
/// The actual due date is computed by the caller as
/// `recordDate.add(Duration(days: value))` — this widget only picks the
/// number of days.
///
/// This is a discrete horizontal slider snapping to [options] — 30, 45,
/// 60, or 90 days. There is intentionally no 15-day option.
///
/// When [locked] is true (the customer this record belongs to already has
/// a schedule configured in their Customer Profile), the selector renders
/// as a read-only summary with a lock icon and an explanatory note
/// instead of an interactive slider, and [onChanged] is never called.
/// This keeps Customer Profile the single source of truth for that
/// customer's recurring health schedule — Add screens only consume it.
class ReminderCadenceSelector extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;

  /// True when a customer-level setting already governs this reminder.
  /// Renders a locked, read-only summary instead of a slider.
  final bool locked;

  /// Optional override for the locked-state explanatory note. Defaults to
  /// a standard "controlled from Customer Profile" message.
  final String? lockedNote;

  /// Whether "No reminder" is offered alongside the slider. Hidden while
  /// [locked] is true (a customer setting is always some number of days).
  final bool allowNoReminder;

  static const List<int> options = [30, 45, 60, 90];

  const ReminderCadenceSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Reminder Schedule',
    this.locked = false,
    this.lockedNote,
    this.allowNoReminder = true,
  });

  int get _selectedIndex {
    if (value == null) return 0;
    final idx = options.indexOf(value!);
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    return locked ? _buildLocked(context) : _buildEditable(context);
  }

  // -----------------------------------------------------------------
  // Locked — customer profile already controls this reminder.
  // -----------------------------------------------------------------
  Widget _buildLocked(BuildContext context) {
    final days = value;

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
                days != null ? 'Every $days days' : 'No reminder',
                style: AppTheme.body(size: 14, color: AppColors.darkGreen, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Selected in Customer Profile',
            style: AppTheme.body(size: 12, color: AppColors.darkGreen, weight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            lockedNote ??
                'This reminder schedule was chosen in the customer\'s profile '
                    'and applies to every one of their goats. It can\'t be '
                    'changed from this screen — update it from Customer '
                    'Profile → Health Settings instead.',
            style: AppTheme.body(size: 11.5, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Editable — no customer-level setting exists; slide between the
  // standard cadences, defaulting to 30 days.
  // -----------------------------------------------------------------
  Widget _buildEditable(BuildContext context) {
    final isOff = value == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
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
                child: Text(label, style: AppTheme.body(size: 12, color: AppColors.textGrey)),
              ),
              if (allowNoReminder)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No reminder', style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                    Switch(
                      value: !isOff,
                      activeColor: AppColors.primaryGreen,
                      onChanged: (enabled) => onChanged(enabled ? options[_selectedIndex] : null),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'No customer schedule has been selected for this record type — '
            'default reminder is ${options.first} days. You can change it below.',
            style: AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
          const SizedBox(height: 4),
          Opacity(
            opacity: isOff ? 0.4 : 1,
            child: IgnorePointer(
              ignoring: isOff,
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primaryGreen,
                      inactiveTrackColor: AppColors.primaryGreen.withOpacity(0.15),
                      thumbColor: AppColors.primaryGreen,
                      overlayColor: AppColors.primaryGreen.withOpacity(0.15),
                      valueIndicatorColor: AppColors.primaryGreen,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _selectedIndex.toDouble(),
                      min: 0,
                      max: (options.length - 1).toDouble(),
                      divisions: options.length - 1,
                      label: '${options[_selectedIndex]} days',
                      onChanged: (v) => onChanged(options[v.round()]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: options
                          .map(
                            (days) => Text(
                              '$days',
                              style: AppTheme.body(
                                size: 11,
                                color: (value ?? options.first) == days
                                    ? AppColors.primaryGreen
                                    : AppColors.textGrey,
                                weight: (value ?? options.first) == days ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        isOff ? 'No reminder' : 'Every ${options[_selectedIndex]} days',
                        style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
