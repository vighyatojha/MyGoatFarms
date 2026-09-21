import 'package:flutter/material.dart';

import '../../app_theme.dart';

/// Date-range presets shared by both sides of the Finance tab, so one
/// selector at the top drives whichever side is showing.
enum FinanceRangePreset { all, today, thisWeek, thisMonth, lastMonth, thisYear }

extension FinanceRangePresetX on FinanceRangePreset {
  String get label {
    switch (this) {
      case FinanceRangePreset.all:
        return 'All';
      case FinanceRangePreset.today:
        return 'Today';
      case FinanceRangePreset.thisWeek:
        return 'This Week';
      case FinanceRangePreset.thisMonth:
        return 'This Month';
      case FinanceRangePreset.lastMonth:
        return 'Last Month';
      case FinanceRangePreset.thisYear:
        return 'Year';
    }
  }

  /// [start, end) — always the same "date >= start && date < end" query
  /// shape, so there is no separate "unbounded" code path.
  ({DateTime start, DateTime end}) get range {
    final now = DateTime.now();

    switch (this) {
      case FinanceRangePreset.all:
      // Wide enough for every record ever entered, plus a little
      // future headroom for backdated / forward entries.
        return (start: DateTime(2000, 1, 1), end: DateTime(now.year + 1, 1, 1));
      case FinanceRangePreset.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start: start, end: start.add(const Duration(days: 1)));
      case FinanceRangePreset.thisWeek:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (start: start, end: start.add(const Duration(days: 7)));
      case FinanceRangePreset.thisMonth:
        return (
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 1),
        );
      case FinanceRangePreset.lastMonth:
        return (
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 1),
        );
      case FinanceRangePreset.thisYear:
        return (
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year + 1, 1, 1),
        );
    }
  }
}

class FinanceRangeSelector extends StatelessWidget {
  final FinanceRangePreset selected;
  final ValueChanged<FinanceRangePreset> onChanged;
  final Color accent;

  const FinanceRangeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.accent = AppColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in FinanceRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected == preset ? accent : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected == preset ? accent : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    preset.label,
                    style: AppTheme.body(
                      size: 12,
                      color: selected == preset ? Colors.white : AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}