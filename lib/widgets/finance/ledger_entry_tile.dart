import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/customer_ledger_entry_model.dart';

class LedgerEntryTile extends StatelessWidget {
  final CustomerLedgerEntry entry;
  final bool showDivider;

  const LedgerEntryTile({
    super.key,
    required this.entry,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    // Outstanding-added entries are a debit (money now owed) but are
    // visually distinguished from a real bill, matching how
    // customer_profile_screen.dart already renders this payment type.
    final isOutstandingAdded =
        entry.kind == LedgerEntryKind.outstandingAdded;

    final isRefund = entry.kind == LedgerEntryKind.refund;
    final isAdvanceInfo = entry.kind == LedgerEntryKind.advanceAdded ||
        entry.kind == LedgerEntryKind.advanceUsed;

    // Advance rows are blue (money sitting with the farm for the customer),
    // refunds are orange (cash handed back), bills red, payments green.
    final color = isAdvanceInfo
        ? AppColors.info
        : isRefund
        ? AppColors.warning
        : entry.isDebit
        ? (isOutstandingAdded ? AppColors.warning : AppColors.error)
        : AppColors.success;

    final icon = isAdvanceInfo
        ? Icons.savings_outlined
        : isRefund
        ? Icons.undo_rounded
        : entry.isDebit
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    // For a payment: how the cash was split between the bill and advance.
    final applied = entry.appliedToBill;
    final advance = entry.advanceAddedAmount;
    final showSplit = entry.kind == LedgerEntryKind.payment &&
        advance != null &&
        advance > 0;

    final sign = isRefund ? '' : (entry.isDebit ? '+' : '-');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    if (entry.subtitle.isNotEmpty)
                      Text(
                        entry.subtitle,
                        style: AppTheme.body(size: 10, color: AppColors.textGrey),
                      ),
                    Text(
                      DateFormat('dd MMM yyyy').format(entry.date),
                      style: AppTheme.body(size: 9, color: AppColors.textGrey),
                    ),
                    if (showSplit)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Applied to bill ₹${(applied ?? (entry.amount - advance)).toStringAsFixed(0)}'
                              ' · Added to advance ₹${advance.toStringAsFixed(0)}',
                          style: AppTheme.body(size: 9, color: AppColors.info),
                        ),
                      ),
                    if (isRefund)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Cash returned · balance unchanged',
                          style: AppTheme.body(size: 9, color: AppColors.warning),
                        ),
                      ),
                    if (entry.kind == LedgerEntryKind.advanceUsed)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Taken from advance · not cash',
                          style: AppTheme.body(size: 9, color: AppColors.info),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '$sign₹${entry.amount.toStringAsFixed(0)}',
                style: AppTheme.body(
                  size: 13,
                  color: color,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (showDivider) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.divider.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );
  }
}