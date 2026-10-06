import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_theme.dart';
import '../../../models/goat_supplier_account.dart';
import '../../../models/trading_lot_payment_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../customers/hub/hub_widgets.dart';
import '../lots/add_lot_payment_sheet.dart';
import '../lots/lot_detail_screen.dart';

final DateFormat _date = DateFormat('d MMM yyyy');
final NumberFormat _rupee2 =
NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final NumberFormat _kg = NumberFormat('#,##0.##', 'en_IN');

/// One goat supplier's ledger:
///
///  1. Balance: due (big), bought and paid.
///  2. Lots bought from them, each with its own bill and a Pay button
///     (the existing lot payment sheet, which saves the payment and its
///     Finance expense).
///  3. Payment history across all their lots.
///
/// Every figure is the lot's own, so it matches Lot Management and the
/// dashboard. This screen never writes money itself.
class GoatSupplierDetailScreen extends StatefulWidget {
  const GoatSupplierDetailScreen({
    super.key,
    required this.farmId,
    required this.supplierKey,
    this.initialName = '',
  });

  final String farmId;

  /// [GoatSupplierAccount.key].
  final String supplierKey;
  final String initialName;

  @override
  State<GoatSupplierDetailScreen> createState() => _GoatSupplierDetailScreenState();
}

class _GoatSupplierDetailScreenState extends State<GoatSupplierDetailScreen> {
  late final Stream<List<TradingPurchase>> _stream =
  TradingService.instance.purchasesStream(widget.farmId);

  bool _showCancelled = false;

  void _openLot(TradingPurchase lot) {
    Navigator.of(context).push(
      fastRoute(LotDetailScreen(
        farmId: widget.farmId,
        lotDocId: lot.id,
        initialLot: lot,
      )),
    );
  }

  Future<void> _pay(TradingPurchase lot) async {
    final saved = await showAddLotPaymentSheet(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier payment recorded.')),
      );
    }
  }

  /// One unpaid lot: pay it. More than one: choose which lot, oldest first.
  void _paySupplier(GoatSupplierAccount s) {
    final unpaid = s.unpaidLots;
    if (unpaid.isEmpty) return;
    if (unpaid.length == 1) {
      unawaited(_pay(unpaid.single));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pay against which lot?', style: AppTheme.heading(size: 16)),
              const SizedBox(height: 4),
              Text('Oldest first. Each payment is saved on its lot.',
                  style: AppTheme.body(size: 11)),
              const SizedBox(height: 8),
              for (final lot in unpaid)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const HubIconBox(
                      icon: Icons.layers_outlined, color: AppColors.tradingBlue),
                  title: Text(lot.lotId, style: AppTheme.heading(size: 13.5)),
                  subtitle: Text(
                    '${_date.format(lot.purchaseDate)} · ${lot.totalGoats} goats',
                    style: AppTheme.body(size: 11),
                  ),
                  trailing: Text(hubMoney(lot.dueAmount),
                      style: AppTheme.heading(size: 14, color: AppColors.error)),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    unawaited(_pay(lot));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _call(String mobile) async {
    final digits = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TradingPurchase>>(
      stream: _stream,
      builder: (context, snap) {
        GoatSupplierAccount? s;
        if (snap.hasData) {
          for (final a in GoatSupplierAccount.group(snap.data!)) {
            if (a.key == widget.supplierKey) s = a;
          }
        }

        Widget body;
        if (snap.hasError) {
          body = const HubMessage(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't load this supplier",
            subtitle: 'Check your connection and open this screen again.',
          );
        } else if (!snap.hasData) {
          body = const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        } else if (s == null) {
          body = const HubMessage(
            icon: Icons.person_off_outlined,
            title: 'Supplier not found',
            subtitle: 'Their lots may have been deleted or the mobile number changed.',
          );
        } else {
          body = _content(s);
        }

        return Scaffold(
          backgroundColor: AppColors.paleGreen,
          body: SafeArea(
            child: Column(
              children: [
                HubTopBar(title: s?.name ?? widget.initialName),
                Expanded(child: body),
              ],
            ),
          ),
          bottomNavigationBar: s != null && s.owes ? _bottomBar(s) : null,
        );
      },
    );
  }

  Widget _content(GoatSupplierAccount s) {
    final active = s.activeLots;
    final cancelled = s.cancelledLots;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _identity(s),
        const SizedBox(height: 12),
        _balance(s),
        HubSection('Lots bought', count: active.length),
        for (final lot in active) ...[
          _lotCard(lot),
          const SizedBox(height: 10),
        ],
        if (cancelled.isNotEmpty) ...[
          HubSection('Cancelled deals', count: cancelled.length),
          if (!_showCancelled)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _showCancelled = true),
                child: Text('Show ${cancelled.length} cancelled'),
              ),
            )
          else
            for (final lot in cancelled) ...[
              _cancelledCard(lot),
              const SizedBox(height: 10),
            ],
        ],
        HubSection('Payment history'),
        _PaymentHistory(
          farmId: widget.farmId,
          lots: s.lots,
          onOpenLot: _openLot,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------

  Widget _identity(GoatSupplierAccount s) {
    return HubCard(
      child: Row(
        children: [
          HubAvatar(name: s.name, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: AppTheme.heading(size: 17)),
                if (s.mobile.isNotEmpty)
                  InkWell(
                    onTap: () => unawaited(_call(s.mobile)),
                    child: Text(
                      s.mobile,
                      style: AppTheme.body(
                          size: 12.5, color: AppColors.info, weight: FontWeight.w500),
                    ),
                  )
                else
                  Text('No mobile saved', style: AppTheme.body(size: 12)),
                if (s.market.isNotEmpty)
                  Text('Market: ${s.market}', style: AppTheme.body(size: 11.5)),
                const SizedBox(height: 6),
                const HubPill('Goat supplier', AppColors.tradingBlue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _balance(GoatSupplierAccount s) {
    return HubCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Due to supplier', style: AppTheme.body(size: 11.5)),
          const SizedBox(height: 4),
          Text(
            s.owes ? hubMoney(s.totalDue) : 'Fully paid',
            style: AppTheme.heading(
              size: 30,
              color: s.owes ? AppColors.error : AppColors.success,
            ),
          ),
          const Divider(height: 22, color: AppColors.divider),
          Row(
            children: [
              HubFact('Total bought', hubMoney(s.totalBought)),
              HubFact('Total paid', hubMoney(s.totalPaid), color: AppColors.success),
              HubFact('Goats', '${s.goatsBought}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              HubFact('First purchase',
                  s.firstPurchase == null ? '—' : _date.format(s.firstPurchase!)),
              HubFact('Last purchase',
                  s.lastPurchase == null ? '—' : _date.format(s.lastPurchase!)),
              HubFact('Lots', '${s.lotCount}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Goat price only, same as Lot Management. Transport and other lot '
                'expenses are not owed to the supplier.',
            style: AppTheme.body(size: 10),
          ),
        ],
      ),
    );
  }

  Widget _lotCard(TradingPurchase lot) {
    final due = lot.dueAmount;
    final statusColor = lot.paymentStatus == 'Paid'
        ? AppColors.success
        : lot.paymentStatus == 'Partial'
        ? AppColors.warning
        : AppColors.error;
    final pricing = lot.isFixedPrice
        ? 'Fixed price'
        : '${_kg.format(lot.totalWeightAtPurchase)} kg × ${_rupee2.format(lot.pricePerKg)}/kg';

    return HubCard(
      onTap: () => _openLot(lot),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HubIconBox(icon: Icons.layers_outlined, color: AppColors.tradingBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${lot.lotId} · ${_date.format(lot.purchaseDate)}',
                        style: AppTheme.heading(size: 13.5)),
                    Text(
                      '${lot.totalGoats} goats · $pricing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 11),
                    ),
                  ],
                ),
              ),
              HubPill(lot.paymentStatus, statusColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Box('Bill', hubMoney(lot.purchaseAmount)),
              const SizedBox(width: 8),
              _Box('Paid', hubMoney(lot.paidAmount), color: AppColors.success),
              const SizedBox(width: 8),
              _Box(
                due >= 0.01 ? 'Due' : 'Status',
                due >= 0.01 ? hubMoney(due) : 'Paid',
                color: due >= 0.01 ? AppColors.error : AppColors.success,
                strong: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openLot(lot),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.darkGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Open lot'),
                ),
              ),
              if (due >= 0.01) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => unawaited(_pay(lot)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text('Pay ${hubMoney(due)}'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cancelledCard(TradingPurchase lot) {
    return HubCard(
      onTap: () => _openLot(lot),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HubIconBox(icon: Icons.block_rounded, color: AppColors.textGrey),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${lot.lotId} · ${_date.format(lot.purchaseDate)}',
                    style: AppTheme.heading(size: 13.5)),
              ),
              const HubPill('Cancelled', AppColors.textGrey),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              HubFact('Paid', hubMoney(lot.cancelPaidAmount)),
              HubFact('Refunded', hubMoney(lot.cancelRefundAmount),
                  color: AppColors.success),
              HubFact('Loss', hubMoney(lot.cancelLossAmount),
                  color: lot.cancelLossAmount > 0 ? AppColors.error : null),
            ],
          ),
          if (lot.cancelNote.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(lot.cancelNote, style: AppTheme.body(size: 11)),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(GoatSupplierAccount s) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _paySupplier(s),
            icon: const Icon(Icons.payments_outlined, size: 20),
            label: Text('Pay supplier · ${hubMoney(s.totalDue)} due',
                style: AppTheme.heading(size: 15, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PAYMENT HISTORY (every payment on every lot of this supplier)
// =============================================================================

class _PaymentHistory extends StatefulWidget {
  const _PaymentHistory({
    required this.farmId,
    required this.lots,
    required this.onOpenLot,
  });

  final String farmId;
  final List<TradingPurchase> lots;
  final void Function(TradingPurchase lot) onOpenLot;

  @override
  State<_PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<_PaymentHistory> {
  final Map<String, StreamSubscription<List<LotPayment>>> _subs = {};
  final Map<String, List<LotPayment>> _payments = {};
  int _shown = 20;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PaymentHistory old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Listens to the payments of every lot, adding / dropping listeners
  /// when the supplier's lots change.
  void _sync() {
    final ids = widget.lots.map((l) => l.id).toSet();
    for (final id in _subs.keys.toList()) {
      if (!ids.contains(id)) {
        _subs.remove(id)?.cancel();
        _payments.remove(id);
      }
    }
    for (final id in ids) {
      if (_subs.containsKey(id)) continue;
      _subs[id] = TradingService.instance
          .lotPaymentsStream(widget.farmId, id)
          .listen((list) {
        if (mounted) setState(() => _payments[id] = list);
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lotById = {for (final l in widget.lots) l.id: l};
    final lines = <SupplierPaymentLine>[
      for (final e in _payments.entries)
        if (lotById[e.key] != null)
          for (final p in e.value) SupplierPaymentLine(lot: lotById[e.key]!, payment: p),
    ]..sort((a, b) => b.payment.date.compareTo(a.payment.date));

    if (_payments.length < widget.lots.length && lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }
    if (lines.isEmpty) {
      return HubCard(
        child: Text('No payments made to this supplier yet',
            style: AppTheme.body(size: 12)),
      );
    }

    return Column(
      children: [
        DecoratedBox(
          decoration: AppTheme.card(radius: 16),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < lines.length && i < _shown; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, indent: 12, endIndent: 12, color: AppColors.divider),
                  _row(lines[i]),
                ],
              ],
            ),
          ),
        ),
        if (lines.length > _shown)
          TextButton(
            onPressed: () => setState(() => _shown += 20),
            child: Text('Show more (${lines.length - _shown} left)'),
          ),
      ],
    );
  }

  Widget _row(SupplierPaymentLine line) {
    final p = line.payment;
    final color = p.voided ? AppColors.textGrey : AppColors.success;
    final strike = p.voided ? TextDecoration.lineThrough : null;
    final detail = [
      _date.format(p.date),
      line.lot.lotId,
      if (p.method.trim().isNotEmpty) p.method.trim(),
      if (p.note.trim().isNotEmpty) p.note.trim(),
      if (p.voided && p.voidReason.trim().isNotEmpty) 'Reason: ${p.voidReason.trim()}',
    ].join(' · ');

    return InkWell(
      onTap: () => widget.onOpenLot(line.lot),
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
              child: Icon(
                p.voided ? Icons.block_rounded : Icons.north_east_rounded,
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.label,
                      style: AppTheme.heading(size: 12.5).copyWith(decoration: strike)),
                  Text(detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_rupee2.format(p.amount),
                style: AppTheme.heading(size: 12.5, color: color).copyWith(decoration: strike)),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box(this.label, this.value, {this.color, this.strong = false});

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