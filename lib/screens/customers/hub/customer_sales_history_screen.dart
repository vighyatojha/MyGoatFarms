import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/customer_sales_history.dart';
import '../../../models/sale_model.dart';
import '../../../services/customer_account_service.dart';
import '../../../widgets/fast_route.dart';
import '../../palai/fullscreen_image_viewer.dart';
import '../../trading/sale_receipt_screen.dart';
import 'hub_widgets.dart';
import 'sale_money_widgets.dart';

/// Every DELIVERED goat sale to one customer (open bookings are on the
/// Wait on Delivery and Booking & Holding screens): which lot each goat came from, how it
/// was priced, what was paid and what is still due. Read-only.
///
/// Goat-sale money only. Palai package and monthly Palai charges are not
/// shown here, and neither is any lot's purchase cost.
class CustomerSalesHistoryScreen extends StatefulWidget {
  const CustomerSalesHistoryScreen({
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
  State<CustomerSalesHistoryScreen> createState() =>
      _CustomerSalesHistoryScreenState();
}

class _CustomerSalesHistoryScreenState
    extends State<CustomerSalesHistoryScreen> {
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final NumberFormat _kg = NumberFormat('#,##0.##', 'en_IN');
  static final NumberFormat _rupee2 =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  late final Stream<CustomerProfileData> _data = CustomerAccountService
      .instance
      .profileStream(widget.farmId, widget.personKey);

  final TextEditingController _search = TextEditingController();
  final Set<String> _expanded = <String>{};
  SalesHistoryFilter _filter = SalesHistoryFilter.all;
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _searching = value.isNotEmpty || _searching;
      if (_search.text != value) _search.text = value;
    });
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

  void _openReceipt(Sale sale) {
    Navigator.of(context).push(
      fastRoute(SaleReceiptScreen(farmId: widget.farmId, saleId: sale.id)),
    );
  }

  String _day(DateTime? d) => d == null ? '—' : _date.format(d);

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _header(),
            ),
            Expanded(
              child: StreamBuilder<CustomerProfileData>(
                stream: _data,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const HubMessage(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load purchases",
                      subtitle:
                      'Check your connection and open this screen again.',
                    );
                  }
                  if (!snap.hasData) return const _HistorySkeleton();
                  final history = snap.data!.history;
                  if (history == null) {
                    return const HubMessage(
                      icon: Icons.person_off_outlined,
                      title: 'Customer not found',
                      subtitle: 'This customer may have been deleted.',
                    );
                  }
                  if (history.delivered.isEmpty) {
                    return const HubMessage(
                      icon: Icons.sell_outlined,
                      title: 'No delivered purchases yet',
                      subtitle:
                      'Goats appear here once they are delivered. Open bookings are on '
                          'the Wait on Delivery and Booking & Holding screens.',
                    );
                  }
                  return _body(history);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
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
            autofocus: _query.isEmpty,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Sale ID, lot or goat tag',
              isDense: true,
              contentPadding:
              EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Purchase history', style: AppTheme.heading(size: 19)),
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
        const SizedBox(width: 10),
        HubHeaderButton(
          icon: _searching ? Icons.close_rounded : Icons.search_rounded,
          tooltip: _searching ? 'Close search' : 'Search',
          onTap: _toggleSearch,
        ),
      ],
    );
  }

  Widget _body(CustomerSalesHistory h) {
    final visible =
    h.lines.where(_filter.test).where((l) => l.matches(_query)).toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _summary(h),
        const SizedBox(height: 12),
        _lotsCard(h),
        const SizedBox(height: 14),
        _chips(h),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          HubMessage(
            icon: Icons.search_off_outlined,
            title: 'No sales match',
            action: TextButton(
              onPressed: () => setState(() {
                _filter = SalesHistoryFilter.all;
                _search.clear();
                _query = '';
              }),
              child: const Text('Show all'),
            ),
          )
        else
          for (final line in visible) ...[
            _saleCard(line),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  Widget _summary(CustomerSalesHistory h) {
    final avg = h.averageRatePerKg;

    return HubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Fact('Goats bought', '${h.goatsBought}'),
              _Fact('Sales', '${h.deliveredCount}'),
              _Fact('Avg rate', avg == null ? '—' : '${_rupee2.format(avg)}/kg'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Fact('Total bought', hubMoney(h.totalBought)),
              _Fact(
                'Pending',
                hubMoney(h.pending),
                color: h.pending > 0 ? HubColors.owes : AppColors.success,
              ),
              _Fact('Received', hubMoney(h.totalReceived), color: AppColors.success),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Fact('Discount given', hubMoney(h.totalDiscount)),
              _Fact('Total weight', '${_kg.format(h.totalWeight)} kg'),
              _Fact('Customer since', _day(h.firstPurchase)),
            ],
          ),
          if (h.needsCheckCount > 0) ...[
            const SizedBox(height: 10),
            _Note(
              '${h.needsCheckCount} sale${h.needsCheckCount == 1 ? '' : 's'} '
                  '${h.needsCheckCount == 1 ? 'has' : 'have'} figures to check. '
                  'Open ${h.needsCheckCount == 1 ? 'it' : 'them'} to see why.',
              color: AppColors.warning,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOTS
  // ---------------------------------------------------------------------------

  Widget _lotsCard(CustomerSalesHistory h) {
    final lots = h.lots;
    if (lots.isEmpty) return const SizedBox.shrink();

    return HubCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bought from lots', style: AppTheme.heading(size: 14)),
          const SizedBox(height: 4),
          for (final lot in lots)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: lot.lotId == CustomerSalesHistory.unknownLot
                  ? null
                  : () => _setQuery(lot.lotId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const HubIconBox(
                      icon: Icons.layers_outlined,
                      color: AppColors.tradingBlue,
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(lot.lotId, style: AppTheme.heading(size: 13)),
                    ),
                    Text(
                      '${lot.goats} goat${lot.goats == 1 ? '' : 's'} · '
                          '${lot.sales} sale${lot.sales == 1 ? '' : 's'}',
                      style: AppTheme.body(size: 11.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTERS
  // ---------------------------------------------------------------------------

  Widget _chips(CustomerSalesHistory h) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: SalesHistoryFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = SalesHistoryFilter.values[i];
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
                    '${f.label}  ${h.countFor(f)}',
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
    );
  }

  // ---------------------------------------------------------------------------
  // SALE CARD
  // ---------------------------------------------------------------------------

  Color _stageColor(SaleStage stage) {
    switch (stage) {
      case SaleStage.delivered:
        return AppColors.success;
      case SaleStage.waiting:
        return HubColors.wait;
      case SaleStage.onHold:
        return HubColors.holding;
      case SaleStage.transferredToPalai:
        return HubColors.palai;
    }
  }

  String _goatsSummary(CustomerSaleLine l) {
    final n = l.goatCount;
    final goats = '$n goat${n == 1 ? '' : 's'}';
    final lots = l.lots.keys.join(', ');
    return lots.isEmpty ? goats : '$goats · $lots';
  }

  Widget _saleCard(CustomerSaleLine l) {
    final open = _expanded.contains(l.id);
    final color = _stageColor(l.stage);

    return HubCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                color: color,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_day(l.date), style: AppTheme.heading(size: 13.5)),
                    Text(
                      '${l.id} · ${l.typeLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10.5),
                    ),
                  ],
                ),
              ),
              HubPill(l.stageLabel, color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _goatsSummary(l),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 12, color: AppColors.textDark, weight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (l.priceNotTracked)
            Text(
              'Price not recorded for this transfer',
              style: AppTheme.body(size: 11.5),
            )
          else ...[
            SaleBillStrip(line: l),
            SaleCheckNote(line: l),
          ],
          if (open) ...[
            const Divider(height: 22, color: AppColors.divider),
            ..._details(l),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
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

  List<Widget> _details(CustomerSaleLine l) {
    final rows = <Widget>[];

    // Pricing
    rows.add(_Heading('Pricing'));
    if (l.isFixedPrice) {
      rows.add(_Row('Fixed price', _rupee2.format(l.goatValue)));
      if (l.weight > 0) rows.add(_Row('Weight recorded', '${_kg.format(l.weight)} kg'));
    } else {
      rows.add(_Row('Rate', '${_rupee2.format(l.ratePerKg)} / kg'));
      if (l.weight > 0) {
        rows.add(_Row(
          l.sale.pickupWeight != null ? 'Pickup weight' : 'Weight',
          '${_kg.format(l.weight)} kg',
        ));
      }
      if (!l.isOpen) rows.add(_Row('Goat value', _rupee2.format(l.goatValue)));
    }
    if (l.discount > 0) {
      rows.add(_Row('Discount', '− ${_rupee2.format(l.discount)}', color: AppColors.success));
    }
    if (l.holdingCharges > 0) {
      rows.add(_Row('Holding charges', _rupee2.format(l.holdingCharges)));
    }
    if (l.transport > 0) {
      rows.add(_Row('Transportation', _rupee2.format(l.transport)));
    }
    if (!l.isOpen && !l.priceNotTracked) {
      rows.add(_Row('Total bill', _rupee2.format(l.total), bold: true));
    }

    // Payments
    rows.add(const SizedBox(height: 8));
    rows.add(_Heading('Payments'));
    rows.add(SalePaymentTimeline(line: l));

    // Goats
    rows.add(const SizedBox(height: 8));
    rows.add(_Heading(l.sale.isLotSale ? 'Lot' : 'Goats'));
    if (l.sale.isLotSale) {
      rows.add(_Row(
        l.sale.lotDisplayId,
        '${l.goatCount} goat${l.goatCount == 1 ? '' : 's'}',
        sub: l.sourceLabel.isEmpty ? null : l.sourceLabel,
      ));
    } else {
      for (final g in l.goats) {
        rows.add(_GoatTile(goat: g));
      }
    }

    // Dates
    rows.add(const SizedBox(height: 8));
    rows.add(_Heading('Dates'));
    rows.add(_Row('Sale date', _day(l.date)));
    if (l.deliveredOn != null) {
      rows.add(_Row(
        l.stage == SaleStage.transferredToPalai ? 'Moved to Palai' : 'Delivered',
        _day(l.deliveredOn),
      ));
    }

    rows.add(const SizedBox(height: 10));
    rows.add(
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _openReceipt(l.sale),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Open receipt'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkGreen,
            side: const BorderSide(color: AppColors.primaryGreen),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
    return rows;
  }
}

// =============================================================================
// SMALL PIECES
// =============================================================================

/// One goat the customer bought: photo (tap to enlarge), tag, lot, and
/// breed · gender · age · weight.
class _GoatTile extends StatelessWidget {
  const _GoatTile({required this.goat});

  final SoldGoatLine goat;

  @override
  Widget build(BuildContext context) {
    final photo = goat.photo;
    final details = [
      goat.breed,
      goat.gender,
      goat.age,
      if (goat.weight > 0) '${goat.weight.toStringAsFixed(1)} kg',
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          GestureDetector(
            onTap: photo == null
                ? null
                : () => Navigator.of(context).push(
              fastRoute(
                FullscreenImageViewer(
                  imageBytes: photo,
                  title: goat.tag,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photo != null
                  ? Image.memory(photo, width: 52, height: 52, fit: BoxFit.cover)
                  : Container(
                width: 52,
                height: 52,
                color: AppColors.lightGreen,
                child: const Icon(Icons.image_not_supported_outlined,
                    size: 20, color: AppColors.textGrey),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(goat.tag, style: AppTheme.heading(size: 13)),
                    ),
                    if (goat.lotId.isNotEmpty)
                      Text(goat.lotId, style: AppTheme.body(size: 10.5)),
                  ],
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: AppTheme.body(size: 11, color: AppColors.textDark),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
            style: AppTheme.heading(size: 13.5, color: color ?? AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: AppTheme.heading(size: 12.5, color: AppColors.textGrey)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
      this.label,
      this.value, {
        this.sub,
        this.color,
        this.bold = false,
        this.strike = false,
      });

  final String label;
  final String value;
  final String? sub;
  final Color? color;
  final bool bold;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    final decoration = strike ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(size: 12, color: AppColors.textDark)
                      .copyWith(decoration: decoration),
                ),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!, style: AppTheme.body(size: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: (bold
                ? AppTheme.heading(size: 13, color: color ?? AppColors.textDark)
                : AppTheme.body(
              size: 12,
              color: color ?? AppColors.textDark,
              weight: FontWeight.w600,
            ))
                .copyWith(decoration: decoration),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(size: 10.5, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        HubBone(height: 170),
        SizedBox(height: 12),
        HubBone(height: 110),
        SizedBox(height: 14),
        HubBone(height: 34, radius: 20),
        SizedBox(height: 12),
        HubBone(height: 120),
        SizedBox(height: 10),
        HubBone(height: 120),
      ],
    );
  }
}