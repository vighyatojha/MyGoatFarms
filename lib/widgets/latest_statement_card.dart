import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/customer_credit.dart';
import '../models/monthly_bill_model.dart';
import '../utils/billing_ledger.dart';

/// Read-only billing card for the report screens.
///
/// Reports never create or change bills any more. Bills are statements
/// for the previous month, made by the statement engine (Generate Bills
/// on the Customers screen, or Generate bill in Monthly Bills). This card
/// shows the customer's latest bill as it was issued, plus what they owe
/// today, so the report and the bill can never disagree.
class LatestStatementCard extends StatelessWidget {
  const LatestStatementCard({
    super.key,
    required this.bill,
    required this.livePending,
    required this.liveAdvance,
    required this.loading,
    required this.onRetry,
    this.error,
    this.goatSaleCredit,
    this.onOpenBills,
  });

  /// The customer's newest bill, or null when they have none yet.
  final MonthlyBill? bill;

  /// customer.pendingAmount right now.
  final double livePending;

  /// customer.advanceAmount right now.
  final double liveAdvance;

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  /// Unpaid Trading goat sales (kept on the sales, not in pendingAmount).
  final CustomerCredit? goatSaleCredit;

  /// Opens Monthly Bills for this customer. Hidden when null.
  final VoidCallback? onOpenBills;

  double get _goatSale => goatSaleCredit?.totalDue ?? 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primaryGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Billing', style: AppTheme.heading(size: 14)),
              ),
              IconButton(
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                icon: loading
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(
                  Icons.refresh,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onPressed: loading ? null : onRetry,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryGreen,
                ),
              ),
            )
          else if (error != null)
            Text(
              error!,
              style: AppTheme.body(size: 11.5, color: AppColors.error),
            )
          else ...[
              if (bill == null)
                Text(
                  'No monthly bill yet. Bills cover the previous month and are '
                      'made with Generate Bills on the Customers screen, or '
                      'Generate bill in Monthly Bills.',
                  style: AppTheme.body(size: 11.5),
                )
              else
                _buildBill(bill!),
              const Divider(height: 22),
              _row('Outstanding today', _currency(livePending), bold: true),
              if (bill != null &&
                  !bill!.locked &&
                  (livePending - bill!.remainingAmount).abs() > 0.5)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Differs from the bill because of payments or charges '
                        '(such as checkout) recorded after it was issued.',
                    style: AppTheme.body(size: 10.5),
                  ),
                ),
              if (liveAdvance > kMoneyEpsilon) ...[
                const SizedBox(height: 4),
                _row('Advance held', _currency(liveAdvance)),
              ],
              if (_goatSale > kMoneyEpsilon) ...[
                const SizedBox(height: 4),
                _row('Goat sale credit (Trading)', _currency(_goatSale)),
                const SizedBox(height: 4),
                _row(
                  'Total owed to the farm',
                  _currency(livePending + _goatSale),
                  bold: true,
                ),
              ],
              if (onOpenBills != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: onOpenBills,
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Open Monthly Bills'),
                  ),
                ),
              ],
            ],
        ],
      ),
    );
  }

  Widget _buildBill(MonthlyBill bill) {
    final month = bill.isStatement
        ? periodLabel(bill.billingPeriodKey)
        : bill.monthYear;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Latest bill: $month',
          style: AppTheme.heading(size: 13),
        ),
        Text(
          '${bill.billNumber} · issued '
              '${DateFormat('d MMM yyyy').format(bill.generatedAt)}',
          style: AppTheme.body(size: 10.5),
        ),
        const SizedBox(height: 10),
        if (bill.isStatement) ...[
          _row('$month charges', _currency(bill.currentBillAmount)),
          _row('Previous outstanding', _currency(bill.previousOutstanding)),
          if (bill.advanceApplied > kMoneyEpsilon)
            _row('Less: advance applied', '− ${_currency(bill.advanceApplied)}'),
          const SizedBox(height: 4),
          _row('Total payable', _currency(bill.totalPayable), bold: true),
          if (bill.amountPaid > kMoneyEpsilon)
            _row('Paid on this bill', _currency(bill.amountPaid)),
          if (!bill.locked)
            _row('Remaining on this bill', _currency(bill.remainingAmount)),
        ] else ...[
          _row('Monthly bill', _currency(bill.currentBillAmount)),
          _row('Remaining on this month', _currency(bill.effectiveOwnRemaining)),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: bold
                  ? AppTheme.heading(size: 13)
                  : AppTheme.body(size: 12, color: AppColors.textMuted),
            ),
          ),
          Text(
            value,
            style: bold
                ? AppTheme.heading(size: 14, color: AppColors.primaryGreen)
                : AppTheme.body(size: 12, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  String _currency(double value) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  ).format(value);
}