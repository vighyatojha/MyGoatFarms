import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Replaces the old manual "next due date" date/time picker on the
/// vaccination / hoof-cutting / hair-trimming forms with a fixed choice
/// of reminder cadence: 30, 45, or 90 days from the record's date, or no
/// reminder at all.
///
/// The actual due date is computed by the caller as
/// `recordDate.add(Duration(days: value))` — this widget only picks the
/// number of days.
class ReminderCadenceSelector extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;

  static const List<int> options = [30, 45, 90];

  const ReminderCadenceSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Remind me again in',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textMuted.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.body(size: 12, color: AppColors.textGrey)),
          const SizedBox(height: 6),
          ...options.map(
                (days) => RadioListTile<int?>(
              value: days,
              groupValue: value,
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: const VisualDensity(vertical: -4),
              activeColor: AppColors.primaryGreen,
              title: Text('$days days', style: AppTheme.body(size: 13)),
              onChanged: onChanged,
            ),
          ),
          RadioListTile<int?>(
            value: null,
            groupValue: value,
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(vertical: -4),
            activeColor: AppColors.primaryGreen,
            title: Text('No reminder', style: AppTheme.body(size: 13, color: AppColors.textGrey)),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
