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
        _Box(
          label: 'Received',
          value: hubMoney(line.received),
          color: AppColors.success,
        ),
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
    final Color color;
    final IconData icon;
    switch (event.kind) {
      case MoneyEventKind.received:
        color = AppColors.success;
        icon = Icons.south_west_rounded;
        break;
      case MoneyEventKind.voided:
        color = AppColors.textGrey;
        icon = Icons.block_rounded;
        break;
      case MoneyEventKind.adjusted:
        color = AppColors.info;
        icon = Icons.swap_horiz_rounded;
        break;
    }
    final strike = event.kind == MoneyEventKind.voided
        ? TextDecoration.lineThrough
        : null;
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
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 13, color: color),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1.5, color: AppColors.divider),
                  ),
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
                    style: AppTheme.heading(size: 12.5, color: color)
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

/// What delivering an open booking would come to, worked out with the
/// same getters as the Wait on Delivery / Booking & Holding screens.
class OpenBookingEstimate extends StatelessWidget {
  const OpenBookingEstimate({super.key, required this.line});

  final CustomerSaleLine line;

  @override
  Widget build(BuildContext context) {
    final s = line.estimate();
    if (s == null) return const SizedBox.shrink();

    final wait = line.sale.isWaitForDelivery;
    final rows = <Widget>[
      if (line.isFixedPrice)
        _Line('Fixed price', rupee2(s.goatAmount))
      else if (wait)
        _Line(
          'Goat value at booking weight',
          rupee2(s.goatAmount),
          sub: '${_kg(line.sale.bookingWeight ?? 0)} kg × ${rupee2(line.ratePerKg)}/kg',
        )
      else
        _Line('Goat sale amount', rupee2(s.goatAmount)),
      if (s.appliedDiscount > 0)
        _Line('Discount', '− ${rupee2(s.appliedDiscount)}', color: AppColors.success),
      if (s.holdingCharges > 0)
        _Line('Holding charges to today', rupee2(s.holdingCharges)),
      _Line(line.initialPaymentLabel, '− ${rupee2(s.advancePaid)}',
          color: AppColors.success),
    ];

    final Widget result;
    if (line.estimateNeedsWeight) {
      result = _Result(
        label: 'No booking weight saved',
        value: 'Weigh at pickup',
        color: AppColors.textGrey,
      );
    } else if (s.excess > 0) {
      result = _Result(
        label: 'Advance covers it',
        value: '${rupee2(s.excess)} extra',
        color: AppColors.success,
      );
    } else {
      result = _Result(
        label: wait ? 'Due at pickup (estimate)' : 'Due if delivered today',
        value: rupee2(s.balanceDue),
        color: HubColors.estimate,
      );
    }

    return Column(
      children: [
        ...rows,
        const Divider(height: 14, color: AppColors.divider),
        result,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            wait
                ? 'Final amount uses the pickup weight. Not in Finance until pickup.'
                : 'Holding charges grow each day. Not in Finance until delivery.',
            style: AppTheme.body(size: 10),
          ),
        ),
      ],
    );
  }

  static String _kg(double v) => NumberFormat('#,##0.##', 'en_IN').format(v);
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
            child: Text(
              notes.join('\n'),
              style: AppTheme.body(size: 10.5, color: AppColors.textDark),
            ),
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
  const _Box({
    required this.label,
    required this.value,
    this.color,
    this.strong = false,
  });

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
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(size: 13.5, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.sub, this.color});

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTheme.body(size: 12, color: AppColors.textDark)),
                if (sub != null) Text(sub!, style: AppTheme.body(size: 10)),
              ],
            ),
          ),
          Text(
            value,
            style: AppTheme.body(
              size: 12,
              color: color ?? AppColors.textDark,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTheme.heading(size: 13))),
        Text(value, style: AppTheme.heading(size: 14, color: color)),
      ],
    );
  }
}