import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/customer_account.dart';
import '../../../models/customer_sales_history.dart';
import '../../../models/sale_model.dart';
import '../../../services/customer_account_service.dart';
import '../../../widgets/fast_route.dart';
import '../../finance/credit_customer_detail_screen.dart';
import '../../trading/goat_stock/booking_delivery_customer_screen.dart';
import '../../trading/goat_stock/wait_delivery_customer_screen.dart';
import '../../trading/sale_receipt_screen.dart';
import 'hub_widgets.dart';
import 'sale_money_widgets.dart';

/// A customer's trading ledger, sale by sale. Read-only.
///
///  * Pending comes from Finance (the customer's Goat sale credit), and each
///    unpaid sale shows Finance's figure for it, so this screen, the
///    account screen and Finance ▸ Trading ▸ Receivable always agree.
///  * Open bookings show what delivery would come to (estimate) with a
///    button to complete it.
///  * Paid sales are listed last.
///
/// Palai bills, Palai payments and Palai advance are never shown here.
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

class _CustomerTradingLedgerScreenState
    extends State<CustomerTradingLedgerScreen> {
  late final Stream<CustomerProfileData> _data = CustomerAccountService
      .instance
      .profileStream(widget.farmId, widget.personKey);

  final Set<String> _expanded = <String>{};
  bool _showPaid = false;

  void _push(Widget screen) => Navigator.of(context).push(fastRoute(screen));

  void _openReceipt(Sale sale) =>
      _push(SaleReceiptScreen(farmId: widget.farmId, saleId: sale.id));

  /// Opens Finance's existing collect screen for the credit group this
  /// sale is filed in.
  void _collect(CustomerAccount a, CustomerSaleLine l) {
    final key = l.creditKey ?? a.credit?.key;
    if (key == null) return;
    _push(CreditCustomerDetailScreen(
      farmId: widget.farmId,
      creditKey: key,
      customerName: a.name,
    ));
  }

  void _openComplete(CustomerSaleLine l) {
    final name = l.sale.customerName.trim().isEmpty
        ? widget.customerName
        : l.sale.customerName.trim();
    _push(
      l.sale.isWaitForDelivery
          ? WaitDeliveryCustomerScreen(
        farmId: widget.farmId,
        customerKey: l.deliveryKey,
        customerName: name,
      )
          : BookingDeliveryCustomerScreen(
        farmId: widget.farmId,
        customerKey: l.deliveryKey,
        customerName: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  HubHeaderButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Trading ledger',
                            style: AppTheme.heading(size: 19)),
                        if (widget.customerName.trim().isNotEmpty)
                          Text(
                            widget.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(size: 11.5),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<CustomerProfileData>(
                stream: _data,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const HubMessage(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load the ledger",
                      subtitle:
                      'Check your connection and open this screen again.',
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryGreen),
                    );
                  }
                  final a = snap.data!.account;
                  final h = snap.data!.history;
                  if (a == null || h == null) {
                    return const HubMessage(
                      icon: Icons.person_off_outlined,
                      title: 'Customer not found',
                    );
                  }
                  return _body(a, h);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(CustomerAccount a, CustomerSalesHistory h) {
    final unpaid = h.lines.where((l) => l.hasBalance).toList();
    final open = h.lines.where((l) => l.isOpen).toList();
    final paid =
    h.lines.where((l) => l.sale.isDelivered && !l.hasBalance).toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _summary(a, h),
        _section('Unpaid sales', unpaid.length),
        if (unpaid.isEmpty)
          _emptyNote('Nothing pending on delivered sales.')
        else
          for (final l in unpaid) ...[
            _unpaidCard(a, l),
            const SizedBox(height: 10),
          ],
        if (open.isNotEmpty) ...[
          _section('Open bookings', open.length),
          for (final l in open) ...[
            _openCard(l),
            const SizedBox(height: 10),
          ],
        ],
        if (paid.isNotEmpty) ...[
          _section('Paid sales', paid.length),
          if (!_showPaid)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _showPaid = true),
                child: Text('Show ${paid.length} paid sales'),
              ),
            )
          else
            DecoratedBox(
              decoration: AppTheme.card(radius: 16),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (var i = 0; i < paid.length; i++) ...[
                      _paidRow(paid[i]),
                      if (i < paid.length - 1)
                        const Divider(
                          height: 1,
                          indent: 12,
                          endIndent: 12,
                          color: AppColors.divider,
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  Widget _summary(CustomerAccount a, CustomerSalesHistory h) {
    final pending = a.goatSaleCredit; // Finance's figure for this customer
    return HubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Pending on delivered sales',
                    style: AppTheme.body(size: 11.5)),
              ),
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
              _Fact('Unpaid sales', '${h.unpaidCount}'),
              _Fact(
                'Due at delivery',
                h.openCount == 0 ? '—' : hubMoney(h.dueAtDelivery),
                color: h.dueAtDelivery > 0 ? HubColors.estimate : null,
              ),
              _Fact(
                'Advance held',
                hubMoney(a.goatSaleAdvance),
                color: a.goatSaleAdvance > 0 ? AppColors.success : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Goat sales only. Palai bills and payments are not included. '
                'Due at delivery is an estimate and moves to pending once the '
                'goats are delivered.',
            style: AppTheme.body(size: 10),
          ),
          if (h.needsCheckCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${h.needsCheckCount} sale${h.needsCheckCount == 1 ? '' : 's'} '
                        'below ${h.needsCheckCount == 1 ? 'has' : 'have'} figures to check.',
                    style: AppTheme.body(size: 10.5, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARDS
  // ---------------------------------------------------------------------------

  Widget _saleHeader(CustomerSaleLine l, {required Color color}) {
    final what = l.lots.keys.isEmpty
        ? '${l.goatCount} goat${l.goatCount == 1 ? '' : 's'}'
        : '${l.goatCount} goat${l.goatCount == 1 ? '' : 's'} · ${l.lots.keys.join(', ')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HubIconBox(
          icon: l.sale.isLotSale ? Icons.layers_outlined : Icons.sell_outlined,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l.id} · ${saleDay(l.deliveredOn ?? l.date)}',
                  style: AppTheme.heading(size: 13.5)),
              Text(
                what,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 11),
              ),
            ],
          ),
        ),
        HubPill(l.typeLabel, color),
      ],
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
          _saleHeader(l, color: HubColors.owes),
          const SizedBox(height: 12),
          SaleBillStrip(line: l),
          SaleCheckNote(line: l),
          if (open) ...[
            const SizedBox(height: 14),
            Text('Payments', style: AppTheme.heading(size: 12.5, color: AppColors.textGrey)),
            const SizedBox(height: 8),
            SalePaymentTimeline(line: l),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openReceipt(l.sale),
                  style: _outlined,
                  child: const Text('Receipt'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _collect(a, l),
                  style: _filled,
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

  Widget _openCard(CustomerSaleLine l) {
    final wait = l.sale.isWaitForDelivery;
    final color = wait ? HubColors.wait : HubColors.holding;
    return HubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HubIconBox(
                icon: wait
                    ? Icons.local_shipping_outlined
                    : Icons.event_available_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.id} · ${saleDay(l.date)}',
                        style: AppTheme.heading(size: 13.5)),
                    Text(
                      '${l.goatCount} goat${l.goatCount == 1 ? '' : 's'}'
                          '${l.lots.isEmpty ? '' : ' · ${l.lots.keys.join(', ')}'}',
                      style: AppTheme.body(size: 11),
                    ),
                  ],
                ),
              ),
              HubPill(l.stageLabel, color),
            ],
          ),
          const SizedBox(height: 12),
          OpenBookingEstimate(line: l),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton.icon(
              onPressed: () => _openComplete(l),
              style: _filled,
              icon: Icon(
                wait ? Icons.local_shipping_outlined : Icons.event_available_outlined,
                size: 18,
              ),
              label: Text(wait ? 'Complete pickup' : 'Complete delivery'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidRow(CustomerSaleLine l) {
    return InkWell(
      onTap: () => _openReceipt(l.sale),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            HubIconBox(
              icon: Icons.check_rounded,
              color: l.needsCheck ? AppColors.warning : AppColors.success,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l.id} · ${saleDay(l.deliveredOn ?? l.date)}',
                      style: AppTheme.heading(size: 12.5)),
                  Text(
                    l.needsCheck
                        ? 'Figures to check, open receipt'
                        : '${l.goatCount} goat${l.goatCount == 1 ? '' : 's'}'
                        '${l.lots.isEmpty ? '' : ' · ${l.lots.keys.join(', ')}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 10.5,
                      color: l.needsCheck ? AppColors.warning : AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  l.priceNotTracked ? '—' : hubMoney(l.total),
                  style: AppTheme.heading(size: 12.5),
                ),
                Text(
                  l.priceNotTracked ? 'No price saved' : 'Paid',
                  style: AppTheme.body(size: 10, color: AppColors.success),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SMALL
  // ---------------------------------------------------------------------------

  Widget _section(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Text(title, style: AppTheme.heading(size: 15)),
          const SizedBox(width: 8),
          HubPill('$count', AppColors.textGrey),
        ],
      ),
    );
  }

  Widget _emptyNote(String text) {
    return HubCard(
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Text(text, style: AppTheme.body(size: 12)),
        ],
      ),
    );
  }

  static final ButtonStyle _filled = FilledButton.styleFrom(
    backgroundColor: AppColors.primaryGreen,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  static final ButtonStyle _outlined = OutlinedButton.styleFrom(
    foregroundColor: AppColors.darkGreen,
    side: const BorderSide(color: AppColors.primaryGreen),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.body(size: 10.5)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(
                size: 13.5, color: color ?? AppColors.textDark),
          ),
        ],
      ),
    );
  }
}