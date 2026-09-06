import 'package:flutter/material.dart';

import '../../app_theme.dart';

/// Horizontal, scrollable category-filter chip row. Used identically by
/// the Expense list, Revenue list, and Reports screens — pass whichever
/// category list applies (ExpenseCategories.all / RevenueCategories.all).
class CategoryChipRow extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const CategoryChipRow({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _chip(label: 'All', value: null),
          const SizedBox(width: 8),
          for (final category in categories) ...[
            _chip(label: category, value: category),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip({required String label, required String? value}) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen
                : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.body(
            size: 12,
            color: isSelected ? Colors.white : AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
