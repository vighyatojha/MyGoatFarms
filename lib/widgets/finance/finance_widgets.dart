import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/finance_summary_model.dart';
import 'finance_transaction_tile.dart';

/// Small building blocks shared by BOTH sides of the Finance tab (Palai
/// and Trading), so the two sides look and behave the same.

String financeRupees(double value) => '₹${value.toStringAsFixed(0)}';

/// Big number tile: icon, amount, label.
class FinanceStatTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final String? caption;
  final VoidCallback? onTap;

  /// Shown instead of the rupee amount when the figure is not money
  /// (for example a goat count).
  final String? valueText;

  const FinanceStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.caption,
    this.onTap,
    this.valueText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.card(radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text(valueText ?? financeRupees(value), style: AppTheme.heading(size: 16)),
            const SizedBox(height: 2),
            Text(label, style: AppTheme.body(size: 11), overflow: TextOverflow.ellipsis),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                style: AppTheme.body(size: 9.5, color: AppColors.textGrey),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wide "Net Cash Flow" style card.
class FinanceNetCard extends StatelessWidget {
  final String label;
  final double value;
  final String? caption;

  const FinanceNetCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final color = value >= 0 ? AppColors.success : AppColors.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                Text(
                  financeRupees(value),
                  style: AppTheme.heading(size: 18, color: color),
                ),
                if (caption != null)
                  Text(caption!, style: AppTheme.body(size: 10, color: AppColors.textGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cash vs Online split card with a proportion bar. Used for "Payments
/// Received" (Palai + Trading) and "Paid to Sellers" (Trading).
class FinanceModeCard extends StatelessWidget {
  final String title;
  final IconData titleIcon;
  final double cash;
  final double online;

  const FinanceModeCard({
    super.key,
    required this.title,
    this.titleIcon = Icons.payments_outlined,
    required this.cash,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final total = cash + online;
    final cashShare = total > 0 ? cash / total : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, color: AppColors.darkGreen, size: 18),
              const SizedBox(width: 8),
              Text(title, style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat('Cash', cash, AppColors.warning,
                    Icons.account_balance_wallet_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat('Online', online, AppColors.info,
                    Icons.qr_code_scanner_rounded),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: cashShare,
                minHeight: 8,
                backgroundColor: AppColors.info.withOpacity(0.25),
                valueColor: const AlwaysStoppedAnimation(AppColors.warning),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, double value, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(financeRupees(value), style: AppTheme.heading(size: 14)),
              Text(label, style: AppTheme.body(size: 10)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tinted action button (Add Expense / Add Revenue style).
class FinanceActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const FinanceActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTheme.body(size: 11, color: color, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// White chip that opens a list screen.
class FinanceNavChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const FinanceNavChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.darkGreen, size: 18),
            const SizedBox(height: 5),
            Text(
              label,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Recent Transactions" list with loading and empty states.
class FinanceRecentList extends StatelessWidget {
  final bool loading;
  final List<FinanceTransactionRow> rows;
  final String emptyHint;
  final void Function(FinanceTransactionRow row) onTapRow;

  const FinanceRecentList({
    super.key,
    required this.loading,
    required this.rows,
    required this.emptyHint,
    required this.onTapRow,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        height: 130,
        alignment: Alignment.center,
        decoration: AppTheme.card(radius: 17),
        child: const CircularProgressIndicator(
          color: AppColors.primaryGreen,
          strokeWidth: 2,
        ),
      );
    }

    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: AppTheme.card(radius: 17),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, color: AppColors.textGrey, size: 30),
            const SizedBox(height: 9),
            Text(
              'No transactions yet',
              style: AppTheme.body(
                size: 12,
                color: AppColors.textGrey,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(emptyHint, style: AppTheme.body(size: 10)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider.withOpacity(0.7)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++)
            FinanceTransactionTile(
              row: rows[i],
              showDivider: i != rows.length - 1,
              onTap: () => onTapRow(rows[i]),
            ),
        ],
      ),
    );
  }
}