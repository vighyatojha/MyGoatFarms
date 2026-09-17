import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_goat_health_record.dart';
import '../../../models/trading_goat_weight_entry.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../palai/fullscreen_image_viewer.dart';
import 'add_health_record_screen.dart';
import 'add_weight_entry_screen.dart';

/// Feature 6 — Own Palai Goat Profile.
///
/// The detail screen for a single Own Palai goat, built up section by
/// section across the phase 3 plan's Pairs 3–6:
///
///   - Task 3.1 (done)       — Basic Details + Purchase History
///   - Task 3.2 (done)       — Growth Tracking
///   - Task 3.3 (this pair)  — Health Tracking
///   - Task 3.4 (next pair)  — Reminder badges
///
/// Basic Details and Purchase History are both read-only — Basic
/// Details comes straight off the `goat` this screen was opened with
/// (the exact same `tradingGoats/{goatId}` doc Goat Stock shows —
/// nothing is duplicated, per Task 2.3). Purchase History is fetched
/// from the linked `tradingPurchases/{purchaseId}` doc via
/// [TradingService].
///
/// Growth Tracking streams `weightHistory` via
/// [GoatService.weightHistoryStream] and shows Current Weight vs
/// Previous Weight, a Weight Gain figure, and the full history — plus
/// a form (pushed as [AddWeightEntryScreen]) to log a new entry with
/// an optional monthly photo. Per the plan's edge-case note, Weight
/// Gain only ever shows with two or more entries; otherwise it shows
/// "—" rather than a misleading 0 or a divide-by-nothing.
///
/// Health Tracking streams the single `healthRecords` subcollection
/// via [GoatService.healthRecordsStream] and splits it client-side
/// into its four [GoatHealthRecordType] sections (Vaccination, Hoof
/// Cutting, Hair Trimming, Medicine), each showing its latest entry
/// plus history and a button that opens [AddHealthRecordScreen] with
/// that type preselected. Next-due-date badges (Task 3.4) are the
/// next pair — dates are shown plainly here for now.
class OwnPalaiGoatProfileScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const OwnPalaiGoatProfileScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<OwnPalaiGoatProfileScreen> createState() =>
      _OwnPalaiGoatProfileScreenState();
}

class _OwnPalaiGoatProfileScreenState
    extends State<OwnPalaiGoatProfileScreen> {
  Future<TradingPurchase?>? _purchaseFuture;

  @override
  void initState() {
    super.initState();
    _loadPurchase();
  }

  void _loadPurchase() {
    final purchaseId = widget.goat.purchaseId.trim();

    if (purchaseId.isEmpty) {
      _purchaseFuture = Future.value(null);
      return;
    }

    _purchaseFuture = TradingService.instance.getPurchase(
      widget.farmId,
      purchaseId,
    );
  }

  Color _healthColor(String healthStatus) {
    switch (healthStatus) {
      case 'Healthy':
        return AppColors.success;
      case 'Under Treatment':
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;
    final healthColor = _healthColor(goat.healthStatus);

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(goat.id, style: AppTheme.heading(size: 17)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _photo(goat)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.darkGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    goat.movedToOwnPalaiAt == null
                        ? 'Own Palai'
                        : 'Own Palai · since '
                        '${DateFormat('d MMM yyyy').format(goat.movedToOwnPalaiAt!)}',
                    style: const TextStyle(
                      color: AppColors.darkGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _sectionCard(
                title: 'Basic Details',
                icon: Icons.pets_outlined,
                children: [
                  _detailRow('Goat ID', goat.id),
                  _detailRow('Breed', goat.breed),
                  _detailRow('Age', goat.age),
                  _detailRow('Weight', '${goat.weight.toStringAsFixed(1)} kg'),
                  _detailRow('Color', goat.color),
                  _statusRow('Health Status', goat.healthStatus, healthColor),
                  if (goat.notes.trim().isNotEmpty)
                    _detailRow('Notes', goat.notes, isLast: true),
                ],
              ),

              const SizedBox(height: 16),

              _purchaseHistorySection(goat),

              const SizedBox(height: 16),

              _growthTrackingSection(goat),

              const SizedBox(height: 16),

              _healthTrackingSection(goat),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PURCHASE HISTORY (Task 3.1)
  // ---------------------------------------------------------------------

  Widget _purchaseHistorySection(Goat goat) {
    return FutureBuilder<TradingPurchase?>(
      future: _purchaseFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.tradingBlue,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (snap.hasError) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Could not load purchase details: '
                      '${FirestoreService.instance.describeError(snap.error!)}',
                  style: AppTheme.body(size: 12, color: AppColors.error),
                ),
              ),
            ],
          );
        }

        final purchase = snap.data;

        if (purchase == null) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            children: [
              _detailRow('Purchase ID',
                  goat.purchaseId.isEmpty ? '—' : goat.purchaseId),
              _detailRow(
                'Purchase Date',
                DateFormat('dd MMM yyyy').format(goat.purchaseDate),
                isLast: true,
              ),
            ],
          );
        }

        return _sectionCard(
          title: 'Purchase History',
          icon: Icons.receipt_long_outlined,
          children: [
            _detailRow('Purchase ID', purchase.id),
            _detailRow('Seller', purchase.sellerName),
            _detailRow(
              'Purchase Date',
              DateFormat('dd MMM yyyy').format(purchase.purchaseDate),
            ),
            _detailRow(
              'Purchase Weight',
              '${purchase.totalWeightAtPurchase.toStringAsFixed(1)} kg total',
            ),
            _detailRow(
              'Price',
              '₹${purchase.pricePerKg.toStringAsFixed(2)}/kg',
            ),
            _detailRow(
              'Amount',
              '₹${purchase.purchaseAmount.toStringAsFixed(0)}',
            ),
            _detailRow(
              'Expenses',
              '₹${purchase.totalTransportExpenses.toStringAsFixed(0)}',
              isLast: true,
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // GROWTH TRACKING (Task 3.2)
  // ---------------------------------------------------------------------

  Future<void> _openAddWeightEntry(Goat goat) async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(
        AddWeightEntryScreen(farmId: widget.farmId, goatId: goat.id),
      ),
    );
    if (saved == true && mounted) {
      // The weightHistoryStream below picks the new entry up on its
      // own — this snack is just confirmation.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weight entry logged.'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    }
  }

  Widget _growthTrackingSection(Goat goat) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up,
                  color: AppColors.stockTeal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Growth Tracking',
                    style: AppTheme.heading(size: 14)),
              ),
              TextButton.icon(
                onPressed: () => _openAddWeightEntry(goat),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Log Weight'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.stockTeal,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 12),
          StreamBuilder<List<GoatWeightEntry>>(
            stream: GoatService.instance.weightHistoryStream(
              farmId: widget.farmId,
              goatId: goat.id,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.stockTeal,
                      ),
                    ),
                  ),
                );
              }

              if (snap.hasError) {
                return Text(
                  'Could not load weight history: '
                      '${FirestoreService.instance.describeError(snap.error!)}',
                  style: AppTheme.body(size: 12, color: AppColors.error),
                );
              }

              // Oldest-first, per weightHistoryStream's doc comment —
              // kept that way for the gain math, reversed only for
              // display so the newest entry appears at the top.
              final entries = snap.data ?? const <GoatWeightEntry>[];

              if (entries.isEmpty) {
                return Text(
                  'No weight entries yet. Log the first weight check '
                      'using the button above.',
                  style: AppTheme.body(size: 12, color: AppColors.textGrey),
                );
              }

              final current = entries.last;
              final previous =
              entries.length >= 2 ? entries[entries.length - 2] : null;
              final gain =
              previous != null ? current.weight - previous.weight : null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _growthStat(
                          'Current',
                          '${current.weight.toStringAsFixed(1)} kg',
                        ),
                      ),
                      Container(
                          width: 1, height: 30, color: AppColors.divider),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _growthStat(
                          'Previous',
                          previous != null
                              ? '${previous.weight.toStringAsFixed(1)} kg'
                              : '—',
                        ),
                      ),
                      Container(
                          width: 1, height: 30, color: AppColors.divider),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _growthStat(
                          'Gain',
                          gain != null
                              ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg'
                              : '—',
                          valueColor: gain == null
                              ? null
                              : (gain >= 0
                              ? AppColors.success
                              : AppColors.error),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'History (${entries.length} '
                        'record${entries.length == 1 ? '' : 's'})',
                    style: AppTheme.body(
                        size: 11.5,
                        color: AppColors.textMuted,
                        weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  for (int i = entries.length - 1; i >= 0; i--)
                    _weightTile(
                      entries[i],
                      i > 0 ? entries[i - 1] : null,
                      isLast: i == 0,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _growthStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.heading(size: 14).copyWith(
            color: valueColor ?? AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _weightTile(
      GoatWeightEntry entry,
      GoatWeightEntry? previous, {
        required bool isLast,
      }) {
    final gain = previous != null ? entry.weight - previous.weight : null;
    final dotColor = gain == null
        ? AppColors.textMuted
        : (gain >= 0 ? AppColors.success : AppColors.error);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColors.divider),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.hasPhoto) ...[
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        fastRoute(
                          FullscreenImageViewer(
                            imageBytes: entry.photo!,
                            title: DateFormat('d MMM yyyy').format(entry.date),
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          entry.photo!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('d MMM yyyy').format(entry.date),
                          style: AppTheme.body(
                              size: 10.5, color: AppColors.textMuted),
                        ),
                        if (entry.notes.trim().isNotEmpty)
                          Text(
                            entry.notes,
                            style: AppTheme.body(
                                size: 10.5, color: AppColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${entry.weight.toStringAsFixed(1)} kg',
                    style: AppTheme.heading(size: 13),
                  ),
                  if (gain != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                      style: AppTheme.body(
                        size: 11,
                        color: dotColor,
                        weight: FontWeight.w600,
                      ),
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

  // ---------------------------------------------------------------------
  // HEALTH TRACKING (Task 3.3)
  // ---------------------------------------------------------------------

  static const List<GoatHealthRecordType> _healthTypes = [
    GoatHealthRecordType.vaccination,
    GoatHealthRecordType.hoofCutting,
    GoatHealthRecordType.hairTrimming,
    GoatHealthRecordType.medicine,
  ];

  IconData _healthTypeIcon(GoatHealthRecordType type) {
    switch (type) {
      case GoatHealthRecordType.vaccination:
        return Icons.vaccines_outlined;
      case GoatHealthRecordType.hoofCutting:
        return Icons.content_cut_outlined;
      case GoatHealthRecordType.hairTrimming:
        return Icons.brush_outlined;
      case GoatHealthRecordType.medicine:
        return Icons.medication_outlined;
    }
  }

  Future<void> _openAddHealthRecord(Goat goat, GoatHealthRecordType type) async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(
        AddHealthRecordScreen(
          farmId: widget.farmId,
          goatId: goat.id,
          type: type,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${type.label} record logged.'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    }
  }

  Widget _healthTrackingSection(Goat goat) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety_outlined,
                  color: AppColors.stockTeal, size: 18),
              const SizedBox(width: 8),
              Text('Health Tracking', style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          StreamBuilder<List<GoatHealthRecord>>(
            stream: GoatService.instance.healthRecordsStream(
              farmId: widget.farmId,
              goatId: goat.id,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.stockTeal,
                      ),
                    ),
                  ),
                );
              }

              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Could not load health records: '
                        '${FirestoreService.instance.describeError(snap.error!)}',
                    style: AppTheme.body(size: 12, color: AppColors.error),
                  ),
                );
              }

              // Newest-first (matches healthRecordsStream) — split
              // client-side by type, per that stream's doc comment,
              // rather than four separate composite-indexed queries.
              final all = snap.data ?? const <GoatHealthRecord>[];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < _healthTypes.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                    ],
                    _healthTypeSection(
                      goat,
                      _healthTypes[i],
                      all.where((r) => r.type == _healthTypes[i]).toList(),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _healthTypeSection(
      Goat goat,
      GoatHealthRecordType type,
      List<GoatHealthRecord> records,
      ) {
    final latest = records.isNotEmpty ? records.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_healthTypeIcon(type), size: 16, color: AppColors.textDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(type.label, style: AppTheme.heading(size: 13)),
            ),
            TextButton.icon(
              onPressed: () => _openAddHealthRecord(goat, type),
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Log'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.stockTeal,
                padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (latest == null)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              'No ${type.label.toLowerCase()} records yet.',
              style: AppTheme.body(size: 11.5, color: AppColors.textGrey),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Last: ${DateFormat('d MMM yyyy').format(latest.date)}'
                        '${latest.nextDueDate != null ? ' · Next due: ${DateFormat('d MMM yyyy').format(latest.nextDueDate!)}' : ''}',
                    style: AppTheme.body(size: 11.5, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
          ),
          if (records.length > 1) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _HealthHistoryExpander(
                type: type,
                records: records,
              ),
            ),
          ],
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // WIDGETS
  // ---------------------------------------------------------------------

  Widget _photo(Goat goat) {
    final hasPhoto = goat.photo != null;

    return GestureDetector(
      onTap: hasPhoto
          ? () => Navigator.of(context).push(
        fastRoute(
          FullscreenImageViewer(
            imageBytes: goat.photo!,
            title: goat.id,
          ),
        ),
      )
          : null,
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.stockTeal.withOpacity(0.14),
          image: hasPhoto
              ? DecorationImage(
              image: MemoryImage(goat.photo!), fit: BoxFit.cover)
              : null,
          border:
          Border.all(color: AppColors.stockTeal.withOpacity(0.3), width: 2),
        ),
        child: !hasPhoto
            ? const Icon(Icons.pets, color: AppColors.stockTeal, size: 48)
            : null,
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.stockTeal, size: 18),
              const SizedBox(width: 8),
              Text(title, style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: isLast ? 0 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTheme.body(size: 12)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTheme.body(
                size: 13,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTheme.body(size: 12)),
          ),
          Expanded(
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                value.isEmpty ? '—' : value,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HEALTH HISTORY EXPANDER
// ============================================================================

/// Collapsible "N more records" list for one health-tracking type —
/// the latest entry is always shown inline by [_healthTypeSection];
/// this covers everything older than that, collapsed by default so
/// four types' worth of history doesn't overwhelm the profile screen.
class _HealthHistoryExpander extends StatefulWidget {
  final GoatHealthRecordType type;
  final List<GoatHealthRecord> records;

  const _HealthHistoryExpander({
    required this.type,
    required this.records,
  });

  @override
  State<_HealthHistoryExpander> createState() =>
      _HealthHistoryExpanderState();
}

class _HealthHistoryExpanderState extends State<_HealthHistoryExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final older = widget.records.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded
                ? 'Hide history'
                : '${older.length} earlier record${older.length == 1 ? '' : 's'}',
            style: AppTheme.body(
              size: 11,
              color: AppColors.tradingBlue,
              weight: FontWeight.w600,
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          for (final record in older)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${DateFormat('d MMM yyyy').format(record.date)}'
                    '${record.nextDueDate != null ? ' · Next due: ${DateFormat('d MMM yyyy').format(record.nextDueDate!)}' : ''}'
                    '${record.notes.trim().isNotEmpty ? ' — ${record.notes.trim()}' : ''}',
                style: AppTheme.body(size: 11, color: AppColors.textGrey),
              ),
            ),
        ],
      ],
    );
  }
}