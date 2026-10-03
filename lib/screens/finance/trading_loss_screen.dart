import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/death_record.dart';
import 'package:mygoatfarms/models/trading_lot_death_model.dart';
import 'package:mygoatfarms/models/trading_purchase_model.dart';
import 'package:mygoatfarms/services/death_settlement_service.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/trading_service.dart';
import 'package:mygoatfarms/widgets/fast_route.dart';
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

enum _LossType {
  all,
  goatDeath,
  lotDeath,
  cancellation,
  other,
}

class _TradingLossItem {
  final String title;
  final String subtitle;
  final String typeLabel;
  final double amount;
  final DateTime date;
  final String? actorName;
  final _LossType type;
  final IconData icon;

  const _TradingLossItem({
    required this.title,
    required this.subtitle,
    required this.typeLabel,
    required this.amount,
    required this.date,
    required this.actorName,
    required this.type,
    required this.icon,
  });
}

class _TradingLossScreenState
    extends State<TradingLossScreen> {
  bool _loading = true;
  String? _error;

  List<_TradingLossItem> _items = [];
  _LossType _filter = _LossType.all;

  double get _totalLoss =>
      _filteredItems.fold<double>(
        0,
            (sum, item) => sum + item.amount,
      );

  List<_TradingLossItem> get _filteredItems {
    if (_filter == _LossType.all) {
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
      final deathRecordsFuture =
          DeathSettlementService.instance
              .deathHistoryStream(widget.farmId)
              .first;

      final lotsFuture =
          TradingService.instance
              .purchasesStream(widget.farmId)
              .first;

      final results = await Future.wait([
        deathRecordsFuture,
        lotsFuture,
      ]);

      final deathRecords =
      results[0] as List<DeathRecord>;

      final lots =
      results[1] as List<TradingPurchase>;

      final items = <_TradingLossItem>[];

      // ---------------------------------------------------------------
      // FARM / GOAT / MANUAL LOSSES
      // ---------------------------------------------------------------
      //
      // These already exist in deathRecords. We only show records
      // which actually carry a monetary farm loss.
      //
      // A Customer Palai death with farmLossAmount == 0 is therefore
      // intentionally excluded.
      for (final record in deathRecords) {
        if (record.farmLossAmount <= 0) {
          continue;
        }

        if (!_inRange(record.deathDate)) {
          continue;
        }

        if (record.isManualLoss) {
          items.add(
            _TradingLossItem(
              title: record.displayTitle,
              subtitle: record.description.trim().isNotEmpty
                  ? record.description.trim()
                  : record.reason.trim().isNotEmpty
                  ? record.reason.trim()
                  : record.goatTypeLabel,
              typeLabel: record.goatTypeLabel,
              amount: record.farmLossAmount,
              date: record.deathDate,
              actorName: record.actorName,
              type: _LossType.other,
              icon: Icons.report_gmailerrorred_outlined,
            ),
          );

          continue;
        }

        final goatLabel =
        record.goatLabel.trim().isNotEmpty
            ? record.goatLabel.trim()
            : 'Goat';

        final customerSuffix =
        record.customerName?.trim().isNotEmpty == true
            ? ' • ${record.customerName!.trim()}'
            : '';

        items.add(
          _TradingLossItem(
            title: '$goatLabel$customerSuffix',
            subtitle: record.reason.trim().isNotEmpty
                ? record.reason.trim()
                : 'Goat death loss',
            typeLabel: record.goatTypeLabel,
            amount: record.farmLossAmount,
            date: record.deathDate,
            actorName: record.actorName,
            type: _LossType.goatDeath,
            icon: Icons.pets_outlined,
          ),
        );
      }

      // ---------------------------------------------------------------
      // PURCHASE LOT DEATHS + DEAL CANCELLATIONS
      // ---------------------------------------------------------------
      //
      // Lot deaths are stored below each trading purchase:
      //
      // tradingPurchases/{lotId}/deaths
      //
      // They are separate from deathRecords, so they must be loaded
      // independently.
      final lotResults = await Future.wait(
        lots
            .where((lot) => lot.isLot)
            .map(
              (lot) => TradingService.instance
              .lotDeathsStream(
            widget.farmId,
            lot.id,
          )
              .first
              .then(
                (deaths) => (
            lot: lot,
            deaths: deaths,
            ),
          ),
        ),
      );

      for (final result in lotResults) {
        final lot = result.lot;

        // Lot death losses.
        for (final death in result.deaths) {
          if (death.reversed) {
            continue;
          }

          if (death.lossAmount <= 0) {
            continue;
          }

          if (!_inRange(death.date)) {
            continue;
          }

          final lotName =
          lot.lotId.trim().isNotEmpty
              ? lot.lotId
              : 'Purchase Lot';

          final reason =
          death.reason.trim().isNotEmpty
              ? death.reason.trim()
              : 'Goat death';

          items.add(
            _TradingLossItem(
              title: '$lotName • Goat death',
              subtitle:
              '${death.qty} goat'
                  '${death.qty == 1 ? '' : 's'} • $reason',
              typeLabel: 'Lot Death',
              amount: death.lossAmount,
              date: death.date,
              actorName: death.actorName,
              type: _LossType.lotDeath,
              icon: Icons.pets_outlined,
            ),
          );
        }

        // -------------------------------------------------------------
        // CANCELLED DEAL LOSS
        // -------------------------------------------------------------
        //
        // TradingService stores:
        //
        // cancelPaidAmount
        // cancelRefundAmount
        // cancelLossAmount
        //
        // The loss is paid minus refunded.
        if (lot.dealCancelled &&
            lot.cancelLossAmount > 0 &&
            lot.cancelledAt != null &&
            _inRange(lot.cancelledAt!)) {
          final note =
          lot.cancelNote.trim();

          items.add(
            _TradingLossItem(
              title:
              '${lot.lotId} • Deal cancellation',
              subtitle: note.isNotEmpty
                  ? note
                  : 'Supplier cancellation loss',
              typeLabel: 'Cancellation',
              amount: lot.cancelLossAmount,
              date: lot.cancelledAt!,
              actorName: null,
              type: _LossType.cancellation,
              icon: Icons.cancel_outlined,
            ),
          );
        }
      }

      items.sort(
            (a, b) => b.date.compareTo(a.date),
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
        _error =
            FirestoreService.instance
                .describeError(e);
      });
    }
  }

  bool _inRange(DateTime date) {
    return !date.isBefore(widget.start) &&
        date.isBefore(widget.end);
  }

  String _formatDate(DateTime date) {
    return DateFormat(
      'dd MMM yyyy',
    ).format(date);
  }

  String _filterLabel(_LossType type) {
    switch (type) {
      case _LossType.all:
        return 'All';
      case _LossType.goatDeath:
        return 'Goat Death';
      case _LossType.lotDeath:
        return 'Lot Death';
      case _LossType.cancellation:
        return 'Cancellation';
      case _LossType.other:
        return 'Other';
    }
  }

  IconData _filterIcon(_LossType type) {
    switch (type) {
      case _LossType.all:
        return Icons.list_alt_rounded;
      case _LossType.goatDeath:
        return Icons.pets_outlined;
      case _LossType.lotDeath:
        return Icons.inventory_2_outlined;
      case _LossType.cancellation:
        return Icons.cancel_outlined;
      case _LossType.other:
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
              children: _LossType.values
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

  Widget _filterChip(_LossType type) {
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
      _TradingLossItem item,
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
            _filter == _LossType.all
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