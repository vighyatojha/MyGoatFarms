import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_supplier_account.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../customers/hub/hub_widgets.dart';
import 'goat_supplier_detail_screen.dart';

enum _SupplierFilter { all, due, paid }

extension on _SupplierFilter {
  String get label {
    switch (this) {
      case _SupplierFilter.all:
        return 'All';
      case _SupplierFilter.due:
        return 'Payment due';
      case _SupplierFilter.paid:
        return 'Fully paid';
    }
  }

  bool test(GoatSupplierAccount s) {
    switch (this) {
      case _SupplierFilter.all:
        return true;
      case _SupplierFilter.due:
        return s.owes;
      case _SupplierFilter.paid:
        return !s.owes;
    }
  }
}

/// Supplier ledger: every goat supplier the farm has bought lots from,
/// with what was bought, paid and is still due. Worked out live from the
/// purchase lots, so the total due is the dashboard's "Supplier Payments
/// Due". Read-only; payments are made from the supplier's page.
class GoatSupplierListScreen extends StatefulWidget {
  const GoatSupplierListScreen({super.key, required this.farmId});

  final String farmId;

  @override
  State<GoatSupplierListScreen> createState() => _GoatSupplierListScreenState();
}

class _GoatSupplierListScreenState extends State<GoatSupplierListScreen> {
  late final Stream<List<TradingPurchase>> _stream =
  TradingService.instance.purchasesStream(widget.farmId);

  final TextEditingController _search = TextEditingController();
  _SupplierFilter _filter = _SupplierFilter.all;
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  void _open(GoatSupplierAccount s) {
    Navigator.of(context).push(fastRoute(GoatSupplierDetailScreen(
      farmId: widget.farmId,
      supplierKey: s.key,
      initialName: s.name,
    )));
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
                    child: _searching
                        ? TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Name, mobile, market or lot',
                        isDense: true,
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    )
                        : Text('Supplier ledger', style: AppTheme.heading(size: 20)),
                  ),
                  const SizedBox(width: 10),
                  HubHeaderButton(
                    icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                    tooltip: _searching ? 'Close search' : 'Search',
                    onTap: _toggleSearch,
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<TradingPurchase>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const HubMessage(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load suppliers",
                      subtitle: 'Check your connection and open this screen again.',
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryGreen),
                    );
                  }
                  return _body(GoatSupplierAccount.group(snap.data!));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<GoatSupplierAccount> all) {
    if (all.isEmpty) {
      return const HubMessage(
        icon: Icons.storefront_outlined,
        title: 'No goat suppliers yet',
        subtitle: 'Suppliers appear here when you buy a lot of goats.',
      );
    }

    final visible =
    all.where(_filter.test).where((s) => s.matches(_query)).toList();
    final due = GoatSupplierAccount.totalDueOf(all);
    final bought = all.fold<double>(0, (s, a) => s + a.totalBought);
    final paid = all.fold<double>(0, (s, a) => s + a.totalPaid);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        HubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total due to suppliers', style: AppTheme.body(size: 11.5)),
              const SizedBox(height: 2),
              Text(
                due >= 0.01 ? hubMoney(due) : 'All paid',
                style: AppTheme.heading(
                  size: 28,
                  color: due >= 0.01 ? AppColors.error : AppColors.success,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  HubFact('Suppliers', '${all.length}'),
                  HubFact('Total bought', hubMoney(bought)),
                  HubFact('Total paid', hubMoney(paid), color: AppColors.success),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _SupplierFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = _SupplierFilter.values[i];
              final selected = f == _filter;
              return Material(
                color: selected ? AppColors.primaryGreen : Colors.white,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? AppColors.primaryGreen : AppColors.divider,
                  ),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() => _filter = f),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        '${f.label}  ${all.where(f.test).length}',
                        style: AppTheme.body(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: selected ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const HubMessage(icon: Icons.search_off_outlined, title: 'No suppliers match')
        else
          for (final s in visible) ...[
            _row(s),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _row(GoatSupplierAccount s) {
    return HubCard(
      onTap: () => _open(s),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          HubAvatar(name: s.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(size: 14)),
                Text(
                  [
                    if (s.mobile.isNotEmpty) s.mobile,
                    if (s.market.isNotEmpty) s.market,
                  ].join(' · ').ifEmpty('No mobile'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11),
                ),
                const SizedBox(height: 6),
                HubPill(
                  '${s.lotCount} lot${s.lotCount == 1 ? '' : 's'} · ${s.goatsBought} goats',
                  AppColors.tradingBlue,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                s.owes ? hubMoney(s.totalDue) : 'Paid',
                style: AppTheme.heading(
                  size: 15,
                  color: s.owes ? AppColors.error : AppColors.success,
                ),
              ),
              Text(
                s.owes ? 'due' : 'all settled',
                style: AppTheme.body(
                  size: 9.5,
                  color: s.owes ? AppColors.error : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}