import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';

class _WeighIn {
  final DateTime date;
  final double weight;
  final String source;
  const _WeighIn({required this.date, required this.weight, required this.source});
}

/// Weight & Progress tab — merges every weight ever recorded for this
/// goat (health updates + monthly photos) with the arrival weight into
/// one chronological chain, and computes Total Gain / Average Monthly
/// Gain once here so the Monthly Report and Final Report can reuse the
/// same numbers instead of recalculating them separately.
class GoatWeightProgressTab extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const GoatWeightProgressTab({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<GoatWeightProgressTab> createState() => _GoatWeightProgressTabState();
}

class _GoatWeightProgressTabState extends State<GoatWeightProgressTab> {
  List<HealthRecordEntry> _healthRecords = [];
  List<MonthlyPhoto> _monthlyPhotos = [];
  bool _loading = true;
  String? _error;

  StreamSubscription<List<HealthRecordEntry>>? _healthSub;
  StreamSubscription<List<MonthlyPhoto>>? _photoSub;

  @override
  void initState() {
    super.initState();
    _healthSub = FirestoreService.instance
        .healthRecordsStream(widget.farmId, widget.customerId, widget.goat.id)
        .listen((records) {
      if (!mounted) return;
      setState(() {
        _healthRecords = records;
        _loading = false;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load weight history: $e';
      });
    });

    _photoSub = FirestoreService.instance
        .monthlyPhotosStream(widget.farmId, widget.customerId, widget.goat.id)
        .listen((photos) {
      if (!mounted) return;
      setState(() => _monthlyPhotos = photos);
    });
  }

  @override
  void dispose() {
    _healthSub?.cancel();
    _photoSub?.cancel();
    super.dispose();
  }

  List<_WeighIn> get _chain {
    final goat = widget.goat;
    final entries = <_WeighIn>[
      _WeighIn(date: goat.farmArrivalDate ?? goat.checkInDate, weight: goat.weightAtCheckIn, source: 'Arrival'),
      for (final r in _healthRecords) _WeighIn(date: r.recordedAt, weight: r.weight, source: 'Health Update'),
      for (final p in _monthlyPhotos)
        if (p.weightKg != null) _WeighIn(date: p.capturedAt, weight: p.weightKg!, source: 'Monthly Photo'),
    ];
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: AppTheme.body(size: 12, color: AppColors.error)));
    }

    final chain = _chain;
    final first = chain.first;
    final last = chain.last;
    final totalGain = last.weight - first.weight;
    final months = last.date.difference(first.date).inDays / 30.0;
    final avgMonthlyGain = months > 0.5 ? totalGain / months : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Container(
          decoration: AppTheme.card(radius: 14),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Gain', style: AppTheme.body(size: 10.5, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      '${totalGain >= 0 ? '+' : ''}${totalGain.toStringAsFixed(1)} kg',
                      style: AppTheme.heading(size: 16).copyWith(color: totalGain >= 0 ? AppColors.success : AppColors.error),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 30, color: AppColors.divider),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Avg Monthly Gain', style: AppTheme.body(size: 10.5, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      avgMonthlyGain != null ? '${avgMonthlyGain >= 0 ? '+' : ''}${avgMonthlyGain.toStringAsFixed(2)} kg' : 'Not enough data',
                      style: AppTheme.heading(size: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('Weight Chain (${chain.length} record${chain.length == 1 ? '' : 's'})', style: AppTheme.heading(size: 13)),
        const SizedBox(height: 8),
        for (int i = 0; i < chain.length; i++) _chainTile(chain[i], i > 0 ? chain[i - 1] : null, isLast: i == chain.length - 1),
      ],
    );
  }

  Widget _chainTile(_WeighIn entry, _WeighIn? previous, {required bool isLast}) {
    final gain = previous != null ? entry.weight - previous.weight : null;
    final color = gain == null ? AppColors.textMuted : (gain >= 0 ? AppColors.success : AppColors.error);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              if (!isLast) Expanded(child: Container(width: 2, color: AppColors.divider)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.source, style: AppTheme.body(size: 11, color: AppColors.textMuted)),
                        Text(DateFormat('d MMM yyyy').format(entry.date), style: AppTheme.body(size: 10.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Text('${entry.weight.toStringAsFixed(1)} kg', style: AppTheme.heading(size: 13)),
                  if (gain != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                      style: AppTheme.body(size: 11, color: color, weight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}