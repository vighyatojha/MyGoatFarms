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

  static const List<GoatHealthRecordType> _healthTypes = [
    GoatHealthRecordType.vaccination,
    GoatHealthRecordType.hoofCutting,
    GoatHealthRecordType.hairTrimming,
    GoatHealthRecordType.medicine,
  ];

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

  Color _healthColor(String status) {
    switch (status) {
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

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 20,
        title: Text(
          goat.id,
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGoatHeader(goat),
              const SizedBox(height: 14),

              _basicDetails(goat),
              const SizedBox(height: 12),

              _purchaseHistory(goat),
              const SizedBox(height: 12),

              _growthTracking(goat),
              const SizedBox(height: 12),

              _healthTracking(goat),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildGoatHeader(Goat goat) {
    final healthColor = _healthColor(goat.healthStatus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardWhite,
            AppColors.stockTeal.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: AppColors.stockTeal.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          _profilePhoto(goat),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goat.id,
                  style: AppTheme.heading(size: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  goat.breed.isEmpty ? 'Breed not specified' : goat.breed,
                  style: AppTheme.body(
                    size: 11.5,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _smallBadge(
                      Icons.pets_outlined,
                      'Own Palai',
                      AppColors.stockTeal,
                    ),
                    const SizedBox(width: 6),
                    _smallBadge(
                      Icons.favorite_outline,
                      goat.healthStatus.isEmpty
                          ? 'Unknown'
                          : goat.healthStatus,
                      healthColor,
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

  Widget _profilePhoto(Goat goat) {
    final hasPhoto = goat.photo != null;

    return GestureDetector(
      onTap: hasPhoto
          ? () {
        Navigator.of(context).push(
          fastRoute(
            FullscreenImageViewer(
              imageBytes: goat.photo!,
              title: goat.id,
            ),
          ),
        );
      }
          : null,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: AppColors.stockTeal.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.stockTeal.withOpacity(0.20),
          ),
          image: hasPhoto
              ? DecorationImage(
            image: MemoryImage(goat.photo!),
            fit: BoxFit.cover,
          )
              : null,
        ),
        child: hasPhoto
            ? null
            : const Icon(
          Icons.pets,
          size: 32,
          color: AppColors.stockTeal,
        ),
      ),
    );
  }

  Widget _smallBadge(
      IconData icon,
      String text,
      Color color,
      ) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BASIC DETAILS
  // ---------------------------------------------------------------------------

  Widget _basicDetails(Goat goat) {
    return _sectionCard(
      title: 'Basic Details',
      icon: Icons.pets_outlined,
      iconColor: AppColors.stockTeal,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statBox(
                  'Age',
                  goat.age,
                  Icons.cake_outlined,
                  AppColors.tradingBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statBox(
                  'Weight',
                  '${goat.weight.toStringAsFixed(1)} kg',
                  Icons.monitor_weight_outlined,
                  AppColors.stockTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _detailRow('Goat ID', goat.id),
          _detailRow('Breed', goat.breed),
          _detailRow('Color', goat.color),
          _statusDetailRow(
            'Health Status',
            goat.healthStatus,
            _healthColor(goat.healthStatus),
          ),
          if (goat.notes.trim().isNotEmpty)
            _detailRow(
              'Notes',
              goat.notes,
              isLast: true,
            ),
        ],
      ),
    );
  }

  Widget _statBox(
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(
                    size: 9.5,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '—' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 12.5).copyWith(
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PURCHASE HISTORY
  // ---------------------------------------------------------------------------

  Widget _purchaseHistory(Goat goat) {
    return FutureBuilder<TradingPurchase?>(
      future: _purchaseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            iconColor: AppColors.tradingBlue,
            child: const _SectionSkeleton(),
          );
        }

        if (snapshot.hasError) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            iconColor: AppColors.tradingBlue,
            child: Text(
              'Could not load purchase details: '
                  '${FirestoreService.instance.describeError(snapshot.error!)}',
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.error,
              ),
            ),
          );
        }

        final purchase = snapshot.data;

        if (purchase == null) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            iconColor: AppColors.tradingBlue,
            child: Column(
              children: [
                _detailRow(
                  'Purchase ID',
                  goat.purchaseId.isEmpty ? '—' : goat.purchaseId,
                ),
                _detailRow(
                  'Purchase Date',
                  DateFormat('dd MMM yyyy').format(goat.purchaseDate),
                  isLast: true,
                ),
              ],
            ),
          );
        }

        return _sectionCard(
          title: 'Purchase History',
          icon: Icons.receipt_long_outlined,
          iconColor: AppColors.tradingBlue,
          child: Column(
            children: [
              _detailRow('Purchase ID', purchase.id),
              _detailRow('Seller', purchase.sellerName),
              _detailRow(
                'Purchase Date',
                DateFormat('dd MMM yyyy').format(
                  purchase.purchaseDate,
                ),
              ),
              _detailRow(
                'Purchase Weight',
                '${purchase.totalWeightAtPurchase.toStringAsFixed(1)} kg',
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
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // GROWTH TRACKING
  // ---------------------------------------------------------------------------

  Future<void> _openAddWeightEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(
        AddWeightEntryScreen(
          farmId: widget.farmId,
          goatId: widget.goat.id,
        ),
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weight entry logged.'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    }
  }

  Widget _growthTracking(Goat goat) {
    return _sectionCard(
      title: 'Growth Tracking',
      icon: Icons.trending_up,
      iconColor: AppColors.stockTeal,
      trailing: TextButton.icon(
        onPressed: _openAddWeightEntry,
        icon: const Icon(Icons.add, size: 15),
        label: const Text('Log'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.stockTeal,
          padding: const EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 3,
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      child: StreamBuilder<List<GoatWeightEntry>>(
        stream: GoatService.instance.weightHistoryStream(
          farmId: widget.farmId,
          goatId: goat.id,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SectionSkeleton();
          }

          if (snapshot.hasError) {
            return Text(
              'Could not load weight history: '
                  '${FirestoreService.instance.describeError(snapshot.error!)}',
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.error,
              ),
            );
          }

          final entries =
              snapshot.data ?? const <GoatWeightEntry>[];

          if (entries.isEmpty) {
            return Text(
              'No weight entries yet. Log the first weight check.',
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.textGrey,
              ),
            );
          }

          final current = entries.last;
          final previous =
          entries.length > 1 ? entries[entries.length - 2] : null;

          final gain = previous != null
              ? current.weight - previous.weight
              : null;

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
                  const SizedBox(width: 7),
                  Expanded(
                    child: _growthStat(
                      'Previous',
                      previous == null
                          ? '—'
                          : '${previous.weight.toStringAsFixed(1)} kg',
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _growthStat(
                      'Gain',
                      gain == null
                          ? '—'
                          : '${gain >= 0 ? '+' : ''}'
                          '${gain.toStringAsFixed(1)} kg',
                      valueColor: gain == null
                          ? AppColors.textDark
                          : gain >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Weight History',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = entries.length - 1; i >= 0; i--)
                _weightEntryTile(
                  entries[i],
                  i > 0 ? entries[i - 1] : null,
                  isLast: i == 0,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _growthStat(
      String label,
      String value, {
        Color? valueColor,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.body(
              size: 9,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(size: 12).copyWith(
              color: valueColor ?? AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightEntryTile(
      GoatWeightEntry entry,
      GoatWeightEntry? previous, {
        required bool isLast,
      }) {
    final gain =
    previous != null ? entry.weight - previous.weight : null;

    final dotColor = gain == null
        ? AppColors.textGrey
        : gain >= 0
        ? AppColors.success
        : AppColors.error;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                children: [
                  if (entry.hasPhoto) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(
                            FullscreenImageViewer(
                              imageBytes: entry.photo!,
                              title: DateFormat(
                                'd MMM yyyy',
                              ).format(entry.date),
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.memory(
                          entry.photo!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('d MMM yyyy').format(entry.date),
                          style: AppTheme.body(
                            size: 10.5,
                            color: AppColors.textGrey,
                          ),
                        ),
                        if (entry.notes.trim().isNotEmpty)
                          Text(
                            entry.notes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              size: 10,
                              color: AppColors.textGrey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${entry.weight.toStringAsFixed(1)} kg',
                    style: AppTheme.heading(size: 12.5),
                  ),
                  if (gain != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      '${gain >= 0 ? '+' : ''}'
                          '${gain.toStringAsFixed(1)}',
                      style: AppTheme.body(
                        size: 10,
                        color: dotColor,
                        weight: FontWeight.w700,
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

  // ---------------------------------------------------------------------------
  // HEALTH TRACKING
  // ---------------------------------------------------------------------------

  IconData _healthIcon(GoatHealthRecordType type) {
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

  Future<void> _openAddHealthRecord(
      GoatHealthRecordType type,
      ) async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(
        AddHealthRecordScreen(
          farmId: widget.farmId,
          goatId: widget.goat.id,
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

  Widget _healthTracking(Goat goat) {
    return _sectionCard(
      title: 'Health Tracking',
      icon: Icons.health_and_safety_outlined,
      iconColor: AppColors.stockTeal,
      child: StreamBuilder<List<GoatHealthRecord>>(
        stream: GoatService.instance.healthRecordsStream(
          farmId: widget.farmId,
          goatId: goat.id,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SectionSkeleton();
          }

          if (snapshot.hasError) {
            return Text(
              'Could not load health records: '
                  '${FirestoreService.instance.describeError(snapshot.error!)}',
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.error,
              ),
            );
          }

          final all =
              snapshot.data ?? const <GoatHealthRecord>[];

          return Column(
            children: [
              for (int i = 0; i < _healthTypes.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                _healthType(
                  goat,
                  _healthTypes[i],
                  all
                      .where((record) =>
                  record.type == _healthTypes[i])
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _healthType(
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
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: AppColors.stockTeal.withOpacity(0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                _healthIcon(type),
                size: 15,
                color: AppColors.stockTeal,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                type.label,
                style: AppTheme.heading(size: 12.5),
              ),
            ),
            _dueBadge(latest),
            TextButton.icon(
              onPressed: () => _openAddHealthRecord(type),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Log'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.stockTeal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(left: 37),
          child: latest == null
              ? Text(
            'No records yet.',
            style: AppTheme.body(
              size: 10.5,
              color: AppColors.textGrey,
            ),
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last: ${DateFormat('d MMM yyyy').format(latest.date)}',
                style: AppTheme.body(
                  size: 10.5,
                  color: AppColors.textDark,
                ),
              ),
              if (latest.nextDueDate != null)
                Text(
                  'Next due: ${DateFormat('d MMM yyyy').format(latest.nextDueDate!)}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              if (records.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _HealthHistoryExpander(
                    records: records,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dueBadge(GoatHealthRecord? latest) {
    if (latest == null || latest.nextDueDate == null) {
      return const SizedBox.shrink();
    }

    final overdue = latest.isOverdue;
    final dueSoon = !overdue &&
        latest.isDueWithin(
          const Duration(
            days: kHealthRecordPendingWindowDays,
          ),
        );

    if (!overdue && !dueSoon) {
      return const SizedBox.shrink();
    }

    final color =
    overdue ? AppColors.error : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(right: 3),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        overdue ? 'Overdue' : 'Due soon',
        style: AppTheme.body(
          size: 8.5,
          color: color,
          weight: FontWeight.w700,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED UI
  // ---------------------------------------------------------------------------

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(radius: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(size: 13.5),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 9),
          const Divider(height: 1),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(
      String label,
      String value, {
        bool isLast = false,
      }) {
    return Padding(
      padding: EdgeInsets.only(
        top: 9,
        bottom: isLast ? 0 : 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTheme.body(
                size: 10.5,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDetailRow(
      String label,
      String value,
      Color color,
      ) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTheme.body(
                size: 10.5,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
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
// SKELETON
// ============================================================================

class _SectionSkeleton extends StatefulWidget {
  const _SectionSkeleton();

  @override
  State<_SectionSkeleton> createState() => _SectionSkeletonState();
}

class _SectionSkeletonState extends State<_SectionSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _box(
      double width,
      double height, {
        double radius = 6,
      }) {
    return Opacity(
      opacity: 0.4 + (_controller.value * 0.35),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _box(90, 11),
                  const Spacer(),
                  _box(50, 18, radius: 10),
                ],
              ),
              const SizedBox(height: 10),
              _box(double.infinity, 11),
              const SizedBox(height: 8),
              _box(180, 11),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// HEALTH HISTORY
// ============================================================================

class _HealthHistoryExpander extends StatefulWidget {
  final List<GoatHealthRecord> records;

  const _HealthHistoryExpander({
    required this.records,
  });

  @override
  State<_HealthHistoryExpander> createState() =>
      _HealthHistoryExpanderState();
}

class _HealthHistoryExpanderState
    extends State<_HealthHistoryExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final older = widget.records.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _expanded
                    ? 'Hide history'
                    : '${older.length} earlier '
                    'record${older.length == 1 ? '' : 's'}',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.tradingBlue,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 14,
                color: AppColors.tradingBlue,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          for (final record in older)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${DateFormat('d MMM yyyy').format(record.date)}'
                    '${record.nextDueDate != null ? ' · Due: ${DateFormat('d MMM yyyy').format(record.nextDueDate!)}' : ''}'
                    '${record.notes.trim().isNotEmpty ? ' · ${record.notes.trim()}' : ''}',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ),
        ],
      ],
    );
  }
}