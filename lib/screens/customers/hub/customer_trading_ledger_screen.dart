import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/customer_account.dart';
import '../../../models/customer_sales_history.dart';
import '../../../services/customer_account_service.dart';
import '../../../widgets/fast_route.dart';
import '../../finance/credit_customer_detail_screen.dart';
import '../../trading/sale_receipt_screen.dart';
import 'hub_widgets.dart';
import 'sale_money_widgets.dart';

/// A customer's trading ledger: money on DELIVERED goat sales only.
///
///  1. Pending: Finance's Goat sale credit for this customer.
///  2. Unpaid sales, each with Finance's due and a Collect button.
///  3. Account history: every bill and payment, newest first.
///
/// Open bookings are not here (they have their own screens), and neither
/// are Palai bills, Palai payments or Palai advance. Read-only.
class CustomerTradingLedgerScreen extends StatefulWidget {
  const CustomerTradingLedgerScreen({
    super.key,
    required this.farmId,
    required this.personKey,
    this.customerName = '',
  });

  final String farmId;

  /// [CustomerAccount.key] of the person to show.
  final String personKey;
  final String customerName;

  @override
  State<CustomerTradingLedgerScreen> createState() =>
      _CustomerTradingLedgerScreenState();
}

class _CustomerTradingLedgerScreenState extends State<CustomerTradingLedgerScreen> {
  late final Stream<CustomerProfileData> _data = CustomerAccountService.instance
      .profileStream(widget.farmId, widget.personKey);

  final Set<String> _expanded = <String>{};
  int _historyShown = 20;

  void _push(Widget screen) => Navigator.of(context).push(fastRoute(screen));

  void _openReceipt(String saleId) =>
      _push(SaleReceiptScreen(farmId: widget.farmId, saleId: saleId));

  /// Finance's existing collect screen for the credit group this sale is in.
  void _collect(CustomerAccount a, CustomerSaleLine l) {
    final key = l.creditKey ?? a.credit?.key;
    if (key == null) return;
    _push(CreditCustomerDetailScreen(
      farmId: widget.farmId,
      creditKey: key,
      customerName: a.name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            HubTopBar(title: 'Trading ledger', subtitle: widget.customerName),
            Expanded(
              child: HubProfileLoader<CustomerProfileData>(
                stream: _data,
                isMissing: (d) => d.account == null || d.history == null,
                builder: (d) => _body(d.account!, d.history!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(CustomerAccount a, CustomerSalesHistory h) {
    final unpaid = h.delivered.where((l) => l.hasBalance).toList();
    final history = h.accountHistory;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _summary(a, h),
        HubSection('Unpaid sales', count: unpaid.length),
        if (unpaid.isEmpty)
          HubCard(
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Text('All delivered sales are paid', style: AppTheme.body(size: 12)),
              ],
            ),
          )
        else
          for (final l in unpaid) ...[
            _unpaidCard(a, l),
            const SizedBox(height: 10),
          ],
        HubSection('Account history', count: history.length),
        if (history.isEmpty)
          const HubMessage(
            icon: Icons.receipt_long_outlined,
            title: 'No bills or payments yet',
            subtitle: 'They appear here once goats are delivered.',
          )
        else ...[
          DecoratedBox(
            decoration: AppTheme.card(radius: 16),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < history.length && i < _historyShown; i++) ...[
                    if (i > 0)
                      const Divider(
                          height: 1, indent: 12, endIndent: 12, color: AppColors.divider),
                    _historyRow(history[i]),
                  ],
                ],
              ),
            ),
          ),
          if (history.length > _historyShown)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _historyShown += 20),
                child: Text('Show more (${history.length - _historyShown} left)'),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------

  Widget _summary(CustomerAccount a, CustomerSalesHistory h) {
    final pending = a.goatSaleCredit; // Finance's figure
    return HubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Pending', style: AppTheme.body(size: 11.5))),
              HubPill(
                h.matchesFinance ? 'Same as Finance' : 'Check Finance',
                h.matchesFinance ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            pending > 0 ? hubMoney(pending) : 'Nothing pending',
            style: AppTheme.heading(
              size: 28,
              color: pending > 0 ? HubColors.owes : AppColors.success,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              HubFact('Total billed', hubMoney(h.totalBought)),
              HubFact('Total received', hubMoney(h.totalReceived),
                  color: AppColors.success),
              HubFact('Advance held', hubMoney(a.goatSaleAdvance),
                  color: a.goatSaleAdvance > 0 ? AppColors.success : null),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Delivered goat sales only. Open bookings and Palai bills are not part of this ledger.',
            style: AppTheme.body(size: 10),
          ),
          if (h.needsCheckCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${h.needsCheckCount} sale${h.needsCheckCount == 1 ? '' : 's'} '
                  '${h.needsCheckCount == 1 ? 'has' : 'have'} figures to check. '
                  'See Purchase history.',
              style: AppTheme.body(size: 10.5, color: AppColors.warning),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unpaidCard(CustomerAccount a, CustomerSaleLine l) {
    final open = _expanded.contains(l.id);
    return HubCard(
      onTap: () => setState(() {
        if (!_expanded.remove(l.id)) _expanded.add(l.id);
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HubIconBox(
                icon: l.sale.isLotSale ? Icons.layers_outlined : Icons.sell_outlined,
                color: HubColors.owes,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.id} · ${saleDay(l.deliveredOn ?? l.date)}',
                        style: AppTheme.heading(size: 13.5)),
                    Text(goatsText(l),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SaleBillStrip(line: l),
          if (open) ...[
            const SizedBox(height: 14),
            Text('Payments',
                style: AppTheme.heading(size: 12.5, color: AppColors.textGrey)),
            const SizedBox(height: 8),
            SalePaymentTimeline(line: l),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openReceipt(l.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.darkGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Receipt'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _collect(a, l),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text('Collect ${hubMoney(l.balance)}'),
                ),
              ),
            ],
          ),
          Center(
            child: Icon(
              open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(AccountHistoryEntry e) {
    final Color color;
    final IconData icon;
    final String amount;
    if (e.isBill) {
      color = HubColors.owes;
      icon = Icons.receipt_outlined;
      amount = rupee2(e.amount);
    } else {
      final style = moneyEventStyle(e.kind!);
      color = style.color;
      icon = style.icon;
      amount = e.kind == MoneyEventKind.adjusted ? '− ${rupee2(e.amount)}' : rupee2(e.amount);
    }
    final strike = e.kind == MoneyEventKind.voided ? TextDecoration.lineThrough : null;

    return InkWell(
      onTap: () => _openReceipt(e.saleId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: AppTheme.heading(size: 12.5).copyWith(decoration: strike)),
                  Text(
                    '${saleDay(e.date)} · ${e.detail}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(amount,
                style: AppTheme.heading(size: 12.5, color: color).copyWith(decoration: strike)),
          ],
        ),
      ),
    );
  }
}