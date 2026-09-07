import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/supplier_ledger_entry_model.dart';

/// Renders a single Supplier Ledger row. Mirrors [LedgerEntryTile], but
/// for supplier entries: a credit purchase (money now owed) is shown as
/// a debit, a payment made to the supplier is shown as a credit.
class SupplierLedgerEntryTile extends StatelessWidget {
  final SupplierLedgerEntry entry;
  final bool showDivider;

  const SupplierLedgerEntryTile({
    super.key,
    required this.entry,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = entry.isDebit ? AppColors.error : AppColors.success;

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
                  color: color.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  entry.isDebit
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
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
                  ],
                ),
              ),
              Text(
                '${entry.isDebit ? '+' : '-'}₹${entry.amount.toStringAsFixed(0)}',
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
            Divider(height: 1, color: AppColors.divider.withOpacity(0.6)),
          ],
        ],
      ),
    );
  }
}