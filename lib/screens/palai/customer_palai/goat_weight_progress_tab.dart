import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../models/report_models.dart';
import '../../../services/firestore_service.dart';

class _WeighIn {
  final DateTime date;
  final double weight;
  final String source;
  const _WeighIn({required this.date, required this.weight, required this.source});
}

/// Weight & Progress tab — chains the goat's arrival weight together with
/// every weight that was actually captured on a GENERATED REPORT for this
/// goat (GoatReport.endWeight, dated by GoatReport.generatedAt), and
/// computes Total Gain / Average Monthly Gain once here so the Monthly
/// Report and Final Report can reuse the same numbers instead of
/// recalculating them separately.
///
/// FIX: this used to also pull in every raw HealthRecordEntry weigh-in
/// and every MonthlyPhoto weigh-in, so the chain (and the gain figures
/// derived from it) mixed in ad-hoc weight entries that were never part
/// of an actual report. It now only looks at weights that are on a
/// report — every entry here besides "Arrival" is a weight that a real,
/// saved GoatReport recorded, on the date that report carries.
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
  List<GoatReport> _reports = [];
  bool _loading = true;
  String? _error;

  StreamSubscription<List<GoatReport>>? _reportsSub;

  @override
  void initState() {
    super.initState();
    _reportsSub = FirestoreService.instance
        .goatReportsStream(widget.farmId, widget.customerId, widget.goat.id)
        .listen((reports) {
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load weight history: $e';
      });
    });
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    super.dispose();
  }

  /// Report-generated label for a weigh-in tile: the report's own notes
  /// (its range/date label) when present, otherwise a generic fallback.
  String _reportSourceLabel(GoatReport report) {
    return report.notes.isNotEmpty ? report.notes : 'Report';
  }

  List<_WeighIn> get _chain {
    final goat = widget.goat;
    final entries = <_WeighIn>[
      _WeighIn(date: goat.farmArrivalDate ?? goat.checkInDate, weight: goat.weightAtCheckIn, source: 'Arrival'),
      for (final r in _reports)
        if (r.endWeight != null) _WeighIn(date: r.generatedAt, weight: r.endWeight!, source: _reportSourceLabel(r)),
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

    // ------------------------------------------------------------
    // GAIN IN LAST 3 MONTHS — compares the current (last-on-chain)
    // weight against whichever report weigh-in is closest to (but
    // not after) 90 days ago. If every report is younger than 90
    // days, falls back to the earliest record so this still shows a
    // real gain rather than going blank for a goat with less than 3
    // months of report history.
    // ------------------------------------------------------------
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final atOrBeforeCutoff = chain.where((e) => !e.date.isAfter(cutoff)).toList();
    final threeMonthBaseline = atOrBeforeCutoff.isNotEmpty ? atOrBeforeCutoff.last : first;
    final gainLast3Months = chain.length > 1 ? last.weight - threeMonthBaseline.weight : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Container(
          decoration: AppTheme.card(radius: 14),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: _summaryStat('Total Gain', totalGain, isKg: true)),
              Container(width: 1, height: 30, color: AppColors.divider),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryStat(
                  'Gain (3 mo)',
                  gainLast3Months,
                  isKg: true,
                  fallback: 'Not enough data',
                ),
              ),
              Container(width: 1, height: 30, color: AppColors.divider),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryStat(
                  'Avg Monthly',
                  avgMonthlyGain,
                  isKg: true,
                  decimals: 2,
                  fallback: 'Not enough data',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('Weight Chain (${chain.length} record${chain.length == 1 ? '' : 's'})', style: AppTheme.heading(size: 13)),
        const SizedBox(height: 8),
        if (chain.length == 1)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'No reports generated yet — only the arrival weight is on record.',
              style: AppTheme.body(size: 11.5, color: AppColors.textMuted),
            ),
          ),
        for (int i = 0; i < chain.length; i++) _chainTile(chain[i], i > 0 ? chain[i - 1] : null, isLast: i == chain.length - 1),
      ],
    );
  }

  Widget _summaryStat(String label, double? value, {bool isKg = false, int decimals = 1, String fallback = '-'}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value != null
              ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(decimals)}${isKg ? ' kg' : ''}'
              : fallback,
          style: AppTheme.heading(size: 14).copyWith(
            color: value == null
                ? AppColors.textDark
                : (value >= 0 ? AppColors.success : AppColors.error),
          ),
        ),
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