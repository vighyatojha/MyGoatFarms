import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/customer_sales_history.dart';
import 'hub_widgets.dart';

final DateFormat _date = DateFormat('d MMM yyyy');
final NumberFormat _rupee2 =
NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String saleDay(DateTime? d) => d == null ? '—' : _date.format(d);
String rupee2(double v) => _rupee2.format(v);

String goatsText(CustomerSaleLine l) {
  final n = l.goatCount;
  final goats = '$n goat${n == 1 ? '' : 's'}';
  return l.lots.isEmpty ? goats : '$goats · ${l.lots.keys.join(', ')}';
}

/// Bill → received → due, as three boxes. Due is Finance's figure.
class SaleBillStrip extends StatelessWidget {
  const SaleBillStrip({super.key, required this.line});

  final CustomerSaleLine line;

  @override
  Widget build(BuildContext context) {
    final due = line.balance;
    return Row(
      children: [
        _Box(label: 'Bill', value: hubMoney(line.total)),
        const SizedBox(width: 8),
        _Box(label: 'Received', value: hubMoney(line.received), color: AppColors.success),
        const SizedBox(width: 8),
        _Box(
          label: due > 0 ? 'Due' : 'Status',
          value: due > 0 ? hubMoney(due) : 'Paid',
          color: due > 0 ? HubColors.owes : AppColors.success,
          strong: true,
        ),
      ],
    );
  }
}

/// Every payment on a sale as a small timeline, oldest first.
class SalePaymentTimeline extends StatelessWidget {
  const SalePaymentTimeline({super.key, required this.line});

  final CustomerSaleLine line;

  @override
  Widget build(BuildContext context) {
    final events = line.moneyEvents;
    if (events.isEmpty) {
      return Text('No payment recorded yet', style: AppTheme.body(size: 11.5));
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineRow(event: events[i], last: i == events.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.last});

  final SaleMoneyEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final style = moneyEventStyle(event.kind);
    final strike = event.kind == MoneyEventKind.voided ? TextDecoration.lineThrough : null;
    final sub = [
      saleDay(event.date),
      if (event.method.isNotEmpty) event.method,
      if (event.note.isNotEmpty) event.note,
    ].join(' · ');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, size: 13, color: style.color),
                ),
                if (!last) Expanded(child: Container(width: 1.5, color: AppColors.divider)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.label,
                          style: AppTheme.body(
                            size: 12,
                            color: AppColors.textDark,
                            weight: FontWeight.w600,
                          ).copyWith(decoration: strike),
                        ),
                        Text(sub, style: AppTheme.body(size: 10)),
                      ],
                    ),
                  ),
                  Text(
                    event.kind == MoneyEventKind.adjusted
                        ? '− ${rupee2(event.amount)}'
                        : rupee2(event.amount),
                    style: AppTheme.heading(size: 12.5, color: style.color)
                        .copyWith(decoration: strike),
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

class MoneyEventStyle {
  const MoneyEventStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

MoneyEventStyle moneyEventStyle(MoneyEventKind kind) {
  switch (kind) {
    case MoneyEventKind.received:
      return const MoneyEventStyle(AppColors.success, Icons.south_west_rounded);
    case MoneyEventKind.voided:
      return const MoneyEventStyle(AppColors.textGrey, Icons.block_rounded);
    case MoneyEventKind.adjusted:
      return const MoneyEventStyle(AppColors.info, Icons.swap_horiz_rounded);
  }
}

/// Shown on a sale whose figures need a look. Never changes any total.
class SaleCheckNote extends StatelessWidget {
  const SaleCheckNote({super.key, required this.line});

  final CustomerSaleLine line;

  @override
  Widget build(BuildContext context) {
    final notes = <String>[
      if (line.notCountedByFinance > 0)
        'Bill shows ${hubMoney(line.notCountedByFinance)} unpaid, but the sale '
            'is saved as paid, so Finance counts ₹0. Check the receipt.',
      if (line.overpaid > 0)
        'Received ${hubMoney(line.overpaid)} more than the bill, and it was '
            'not recorded as advance or refund. Check the receipt.',
    ];
    if (notes.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 15, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(notes.join('\n'),
                style: AppTheme.body(size: 10.5, color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PIECES
// =============================================================================

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.value, this.color, this.strong = false});

  final String label;
  final String value;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textDark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: strong ? c.withValues(alpha: 0.08) : AppColors.paleGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.body(size: 10)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(size: 13.5, color: c)),
          ],
        ),
      ),
    );
  }
}