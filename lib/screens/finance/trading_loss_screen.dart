import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/widgets/fast_route.dart';
import '../../services/trading_loss_screen.dart';
import '../../widgets/finance/finance_widgets.dart';
import '../home/record_farm_loss_screen.dart';

class TradingLossScreen extends StatefulWidget {
  final String farmId;
  final DateTime start;
  final DateTime end;

  const TradingLossScreen({
    super.key,
    required this.farmId,
    required this.start,
    required this.end,
  });

  @override
  State<TradingLossScreen> createState() =>
      _TradingLossScreenState();
}

class _TradingLossScreenState
    extends State<TradingLossScreen> {
  bool _loading = true;
  String? _error;

  List<TradingLossItem> _items = [];
  TradingLossType _filter = TradingLossType.all;

  double get _totalLoss =>
      _filteredItems.fold<double>(
        0,
            (sum, item) => sum + item.amount,
      );

  List<TradingLossItem> get _filteredItems {
    if (_filter == TradingLossType.all) {
      return _items;
    }

    return _items
        .where((item) => item.type == _filter)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // One shared loader - the Recent Trading Activity feed reads the
      // same list, so the two can never disagree.
      final items = await TradingLossService.instance.load(
        widget.farmId,
        start: widget.start,
        end: widget.end,
      );

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FirestoreService.instance.describeError(e);
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat(
      'dd MMM yyyy',
    ).format(date);
  }

  String _filterLabel(TradingLossType type) {
    switch (type) {
      case TradingLossType.all:
        return 'All';
      case TradingLossType.goatDeath:
        return 'Goat Death';
      case TradingLossType.lotDeath:
        return 'Lot Death';
      case TradingLossType.cancellation:
        return 'Cancellation';
      case TradingLossType.saleDiscount:
        return 'Discount';
      case TradingLossType.belowCost:
        return 'Below Cost';
      case TradingLossType.other:
        return 'Other';
    }
  }

  IconData _filterIcon(TradingLossType type) {
    switch (type) {
      case TradingLossType.all:
        return Icons.list_alt_rounded;
      case TradingLossType.goatDeath:
        return Icons.pets_outlined;
      case TradingLossType.lotDeath:
        return Icons.inventory_2_outlined;
      case TradingLossType.cancellation:
        return Icons.cancel_outlined;
      case TradingLossType.saleDiscount:
        return Icons.local_offer_outlined;
      case TradingLossType.belowCost:
        return Icons.trending_down_rounded;
      case TradingLossType.other:
        return Icons.report_gmailerrorred_outlined;
    }
  }

  Future<void> _recordManualLoss() async {
    final changed = await Navigator.of(context).push(
      fastRoute(
        RecordFarmLossScreen(
          farmId: widget.farmId,
        ),
      ),
    );

    if (changed == true && mounted) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Trading Losses'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
        _loading ? null : _recordManualLoss,
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        icon: const Icon(
          Icons.add_circle_outline_rounded,
        ),
        label: const Text('Record Loss'),
      ),
      body: RefreshIndicator(
        color: AppColors.error,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _summarySkeleton(),
          const SizedBox(height: 12),
          _filterSkeleton(),
          const SizedBox(height: 12),
          ...List.generate(
            4,
                (_) => Padding(
              padding:
              const EdgeInsets.only(bottom: 10),
              child: _lossSkeleton(),
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.error_outline_rounded,
            size: 44,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Could not load losses',
            textAlign: TextAlign.center,
            style: AppTheme.heading(size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    final items = _filteredItems;

    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        100,
      ),
      children: [
        _summaryCard(),
        const SizedBox(height: 12),
        _filterCard(),
        const SizedBox(height: 14),

        if (items.isEmpty)
          _emptyState()
        else
          ...items.map(
                (item) => Padding(
              padding:
              const EdgeInsets.only(bottom: 10),
              child: _lossCard(item),
            ),
          ),
      ],
    );
  }

  Widget _summaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.error
              .withValues(alpha: 0.12),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.error
                      .withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.trending_down_rounded,
                  color: AppColors.error,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Loss',
                      style:
                      AppTheme.body(
                        size: 11,
                        color:
                        AppColors.textGrey,
                        weight:
                        FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      financeRupees(_totalLoss),
                      style:
                      AppTheme.heading(
                        size: 23,
                        color:
                        AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.paleGreen,
                  borderRadius:
                  BorderRadius.circular(10),
                ),
                child: Text(
                  '${_filteredItems.length} record'
                      '${_filteredItems.length == 1 ? '' : 's'}',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${DateFormat('dd MMM yyyy').format(widget.start)}'
                ' – '
                '${DateFormat('dd MMM yyyy').format(widget.end.subtract(const Duration(days: 1)))}',
            style: AppTheme.body(
              size: 10.5,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Loss Type',
            style: AppTheme.heading(size: 12.5),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection:
              Axis.horizontal,
              children: TradingLossType.values
                  .map(
                    (type) => Padding(
                  padding:
                  const EdgeInsets.only(
                    right: 7,
                  ),
                  child:
                  _filterChip(type),
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(TradingLossType type) {
    final selected =
        _filter == type;

    return InkWell(
      borderRadius:
      BorderRadius.circular(20),
      onTap: () {
        setState(() => _filter = type);
      },
      child: AnimatedContainer(
        duration:
        const Duration(milliseconds: 160),
        padding:
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.error
              : AppColors.paleGreen,
          borderRadius:
          BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.error
                : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              _filterIcon(type),
              size: 14,
              color: selected
                  ? Colors.white
                  : AppColors.textGrey,
            ),
            const SizedBox(width: 5),
            Text(
              _filterLabel(type),
              style: AppTheme.body(
                size: 11,
                color: selected
                    ? Colors.white
                    : AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lossCard(
      TradingLossItem item,
      ) {
    final actor =
        item.actorName?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.error
                  .withValues(alpha: 0.08),
              borderRadius:
              BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style:
                        AppTheme.heading(
                          size: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      financeRupees(
                        item.amount,
                      ),
                      style:
                      AppTheme.heading(
                        size: 14,
                        color:
                        AppColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 11,
                    color:
                    AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _metaChip(
                      item.typeLabel,
                      Icons.label_outline_rounded,
                    ),
                    _metaChip(
                      _formatDate(item.date),
                      Icons.calendar_today_outlined,
                    ),
                    if (actor.isNotEmpty)
                      _metaChip(
                        actor,
                        Icons.person_outline_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(
      String text,
      IconData icon,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius:
        BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: AppColors.textGrey,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTheme.body(
              size: 9.5,
              color: AppColors.textGrey,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 42,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.paleGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.success,
              size: 29,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No losses recorded',
            style: AppTheme.heading(size: 15),
          ),
          const SizedBox(height: 6),
          Text(
            _filter == TradingLossType.all
                ? 'There are no trading-related losses '
                'in this finance period.'
                : 'There are no losses in the selected '
                'category for this period.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 11.5,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summarySkeleton() {
    return Container(
      height: 105,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.error,
        ),
      ),
    );
  }

  Widget _filterSkeleton() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
      ),
    );
  }

  Widget _lossSkeleton() {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
      ),
    );
  }
}