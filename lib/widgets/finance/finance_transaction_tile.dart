import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/finance_summary_model.dart';

/// One row for a [FinanceTransactionRow] — used on the Finance Overview's
/// "Recent Transactions" list and on the Expense/Revenue list screens.
/// Mirrors the visual pattern of the existing Stock screen's
/// `_activityItem` (circular icon + title/subtitle + trailing amount).
class FinanceTransactionTile extends StatelessWidget {
  final FinanceTransactionRow row;
  final VoidCallback? onTap;
  final bool showDivider;

  const FinanceTransactionTile({
    super.key,
    required this.row,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = row.isIncome ? AppColors.success : AppColors.error;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    row.isIncome
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title.isEmpty ? row.category : row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.textDark,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${row.category} · ${DateFormat('dd MMM, hh:mm a').format(row.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 9, color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${row.isIncome ? '+' : '-'}₹${row.amount.toStringAsFixed(0)}',
                      style: AppTheme.body(
                        size: 12,
                        color: color,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.isIncome ? 'Revenue' : 'Expense',
                      style: AppTheme.body(size: 8, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ],
            ),
            if (showDivider) ...[
              const SizedBox(height: 11),
              Divider(height: 1, color: AppColors.divider.withOpacity(0.65)),
            ],
          ],
        ),
      ),
    );
  }
}
