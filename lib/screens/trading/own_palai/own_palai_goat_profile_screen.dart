import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
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
        titleSpacing: 18,
        title: Text(
          goat.id,
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(goat),
              const SizedBox(height: 10),

              _buildBasicDetails(goat),
              const SizedBox(height: 10),

              _buildPurchaseHistory(goat),
              const SizedBox(height: 10),

              _buildGrowthTracking(goat),
              const SizedBox(height: 10),

              _buildHealthTracking(goat),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader(Goat goat) {
    final healthColor = _healthColor(goat.healthStatus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardWhite,
            AppColors.stockTeal.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.stockTeal.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          _buildProfilePhoto(goat),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goat.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  goat.breed.isEmpty
                      ? 'Breed not specified'
                      : goat.breed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _badge(
                      GoatIcons.paw,
                      'Own Palai',
                      AppColors.stockTeal,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: _badge(
                        Icons.favorite_outline,
                        goat.healthStatus.isEmpty
                            ? 'Unknown'
                            : goat.healthStatus,
                        healthColor,
                      ),
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

  Widget _buildProfilePhoto(Goat goat) {
    final hasPhoto = goat.photo != null;

    return GestureDetector(
      onTap: !hasPhoto
          ? null
          : () {
        Navigator.of(context).push(
          fastRoute(
            FullscreenImageViewer(
              imageBytes: goat.photo!,
              title: goat.id,
            ),
          ),
        );
      },
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: AppColors.stockTeal.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.stockTeal.withOpacity(0.18),
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
          GoatIcons.paw,
          size: 29,
          color: AppColors.stockTeal,
        ),
      ),
    );
  }

  Widget _badge(
      IconData icon,
      String text,
      Color color,
      ) {
    return Container(
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
            size: 11,
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
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BASIC DETAILS
  // ===========================================================================

  Widget _buildBasicDetails(Goat goat) {
    return _sectionCard(
      title: 'Basic Details',
      icon: GoatIcons.paw,
      color: AppColors.stockTeal,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statCard(
                  label: 'Age',
                  value: goat.age,
                  icon: Icons.cake_outlined,
                  color: AppColors.tradingBlue,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _statCard(
                  label: 'Weight',
                  value:
                  '${goat.weight.toStringAsFixed(1)} kg',
                  icon: Icons.monitor_weight_outlined,
                  color: AppColors.stockTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _detailRow('Goat ID', goat.id),
          _detailRow('Breed', goat.breed),
          _detailRow('Color', goat.color),
          _statusRow(
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

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(11),
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
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(
                    size: 9,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '—' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 12,
                  ).copyWith(
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

  // ===========================================================================
  // PURCHASE HISTORY
  // ===========================================================================

  Widget _buildPurchaseHistory(Goat goat) {
    return FutureBuilder<TradingPurchase?>(
      future: _purchaseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            color: AppColors.tradingBlue,
            child: const _SectionSkeleton(
              rows: 5,
            ),
          );
        }

        if (snapshot.hasError) {
          return _sectionCard(
            title: 'Purchase History',
            icon: Icons.receipt_long_outlined,
            color: AppColors.tradingBlue,
            child: Text(
              'Could not load purchase details: '
                  '${FirestoreService.instance.describeError(snapshot.error!)}',
              style: AppTheme.body(
                size: 11,
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
            color: AppColors.tradingBlue,
            child: Column(
              children: [
                _detailRow(
                  'Purchase ID',
                  goat.purchaseId.isEmpty
                      ? '—'
                      : goat.purchaseId,
                ),
                _detailRow(
                  'Purchase Date',
                  DateFormat('dd MMM yyyy')
                      .format(goat.purchaseDate),
                  isLast: true,
                ),
              ],
            ),
          );
        }

        return _sectionCard(
          title: 'Purchase History',
          icon: Icons.receipt_long_outlined,
          color: AppColors.tradingBlue,
          child: Column(
            children: [
              _detailRow('Purchase ID', purchase.id),
              _detailRow(
                'Seller',
                purchase.sellerName,
              ),
              _detailRow(
                'Purchase Date',
                DateFormat('dd MMM yyyy')
                    .format(purchase.purchaseDate),
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

  // ===========================================================================
  // GROWTH TRACKING
  // ===========================================================================

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
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildGrowthTracking(Goat goat) {
    return _sectionCard(
      title: 'Growth Tracking',
      icon: Icons.trending_up,
      color: AppColors.stockTeal,
      trailing: _compactAction(
        label: 'Log',
        icon: Icons.add,
        color: AppColors.stockTeal,
        onTap: _openAddWeightEntry,
      ),
      child: StreamBuilder<List<GoatWeightEntry>>(
        stream: GoatService.instance.weightHistoryStream(
          farmId: widget.farmId,
          goatId: goat.id,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const _SectionSkeleton(rows: 4);
          }

          if (snapshot.hasError) {
            return Text(
              'Could not load weight history: '
                  '${FirestoreService.instance.describeError(snapshot.error!)}',
              style: AppTheme.body(
                size: 11,
                color: AppColors.error,
              ),
            );
          }

          final entries =
              snapshot.data ?? const <GoatWeightEntry>[];

          if (entries.isEmpty) {
            return _emptyMessage(
              icon: Icons.monitor_weight_outlined,
              text:
              'No weight entries yet. Log the first weight check.',
            );
          }

          final current = entries.last;
          final previous = entries.length > 1
              ? entries[entries.length - 2]
              : null;

          final gain = previous == null
              ? null
              : current.weight - previous.weight;

          return Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _growthStat(
                      'Current',
                      '${current.weight.toStringAsFixed(1)} kg',
                      AppColors.stockTeal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _growthStat(
                      'Previous',
                      previous == null
                          ? '—'
                          : '${previous.weight.toStringAsFixed(1)} kg',
                      AppColors.tradingBlue,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _growthStat(
                      'Gain',
                      gain == null
                          ? '—'
                          : '${gain >= 0 ? '+' : ''}'
                          '${gain.toStringAsFixed(1)} kg',
                      gain == null
                          ? AppColors.textGrey
                          : gain >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Weight History',
                style: AppTheme.body(
                  size: 10.5,
                  color: AppColors.textGrey,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              for (int i = entries.length - 1;
              i >= 0;
              i--)
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
      String value,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.body(
              size: 8.5,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(
              size: 11.5,
            ).copyWith(
              color: AppColors.textDark,
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
    final gain = previous == null
        ? null
        : entry.weight - previous.weight;

    final dotColor = gain == null
        ? AppColors.textGrey
        : gain >= 0
        ? AppColors.success
        : AppColors.error;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
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
                    width: 1.2,
                    color: AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding:
              const EdgeInsets.only(bottom: 9),
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
                        borderRadius:
                        BorderRadius.circular(7),
                        child: Image.memory(
                          entry.photo!,
                          width: 34,
                          height: 34,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat(
                            'd MMM yyyy',
                          ).format(entry.date),
                          style: AppTheme.body(
                            size: 10,
                            color: AppColors.textGrey,
                          ),
                        ),
                        if (entry.notes
                            .trim()
                            .isNotEmpty)
                          Text(
                            entry.notes,
                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,
                            style: AppTheme.body(
                              size: 9.5,
                              color:
                              AppColors.textGrey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${entry.weight.toStringAsFixed(1)} kg',
                    style: AppTheme.heading(
                      size: 11.5,
                    ),
                  ),
                  if (gain != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${gain >= 0 ? '+' : ''}'
                          '${gain.toStringAsFixed(1)}',
                      style: AppTheme.body(
                        size: 9.5,
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

  // ===========================================================================
  // HEALTH TRACKING
  // ===========================================================================

  IconData _healthIcon(
      GoatHealthRecordType type,
      ) {
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

  Color _healthTypeColor(
      GoatHealthRecordType type,
      ) {
    switch (type) {
      case GoatHealthRecordType.vaccination:
        return AppColors.success;
      case GoatHealthRecordType.hoofCutting:
        return AppColors.warning;
      case GoatHealthRecordType.hairTrimming:
        return AppColors.info;
      case GoatHealthRecordType.medicine:
        return AppColors.error;
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
          content: Text(
            '${type.label} record logged.',
          ),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildHealthTracking(Goat goat) {
    return _sectionCard(
      title: 'Health Tracking',
      icon: Icons.health_and_safety_outlined,
      color: AppColors.stockTeal,
      child: StreamBuilder<List<GoatHealthRecord>>(
        stream: GoatService.instance.healthRecordsStream(
          farmId: widget.farmId,
          goatId: goat.id,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const _SectionSkeleton(
              rows: 7,
            );
          }

          if (snapshot.hasError) {
            return Text(
              'Could not load health records: '
                  '${FirestoreService.instance.describeError(snapshot.error!)}',
              style: AppTheme.body(
                size: 11,
                color: AppColors.error,
              ),
            );
          }

          final records =
              snapshot.data ?? const <GoatHealthRecord>[];

          return Column(
            children: [
              for (int i = 0;
              i < _healthTypes.length;
              i++) ...[
                if (i > 0)
                  const Padding(
                    padding:
                    EdgeInsets.symmetric(
                      vertical: 8,
                    ),
                    child: Divider(height: 1),
                  ),
                _healthType(
                  _healthTypes[i],
                  records
                      .where(
                        (record) =>
                    record.type ==
                        _healthTypes[i],
                  )
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
      GoatHealthRecordType type,
      List<GoatHealthRecord> records,
      ) {
    final latest =
    records.isNotEmpty ? records.first : null;

    final color = _healthTypeColor(type);

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: color.withOpacity(0.09),
                borderRadius:
                BorderRadius.circular(9),
              ),
              child: Icon(
                _healthIcon(type),
                size: 15,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                type.label,
                style: AppTheme.heading(
                  size: 12,
                ),
              ),
            ),
            _dueBadge(latest),
            _compactAction(
              label: 'Log',
              icon: Icons.add,
              color: color,
              onTap: () =>
                  _openAddHealthRecord(type),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          padding:
          const EdgeInsets.only(left: 37),
          child: latest == null
              ? Text(
            'No records yet.',
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          )
              : Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Last: ${DateFormat('d MMM yyyy').format(latest.date)}',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textDark,
                ),
              ),
              if (latest.nextDueDate != null)
                Text(
                  'Next due: '
                      '${DateFormat('d MMM yyyy').format(latest.nextDueDate!)}',
                  style: AppTheme.body(
                    size: 9.5,
                    color: AppColors.textGrey,
                  ),
                ),
              if (records.length > 1)
                Padding(
                  padding:
                  const EdgeInsets.only(
                    top: 4,
                  ),
                  child:
                  _HealthHistoryExpander(
                    records: records,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dueBadge(
      GoatHealthRecord? latest,
      ) {
    if (latest == null ||
        latest.nextDueDate == null) {
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
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        overdue ? 'Overdue' : 'Due soon',
        style: AppTheme.body(
          size: 8,
          color: color,
          weight: FontWeight.w700,
        ),
      ),
    );
  }

  // ===========================================================================
  // SHARED UI
  // ===========================================================================

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 15),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.09),
                  borderRadius:
                  BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 15,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 13,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: AppColors.divider.withOpacity(0.7),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }

  Widget _compactAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 14,
      ),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 2,
        ),
        visualDensity: VisualDensity.compact,
        tapTargetSize:
        MaterialTapTargetSize.shrinkWrap,
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
        top: 8,
        bottom: isLast ? 0 : 1,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(
      String label,
      String value,
      Color color,
      ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
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

  Widget _emptyMessage({
    required IconData icon,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: AppColors.textGrey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                size: 10.5,
                color: AppColors.textGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SECTION SKELETON
// ============================================================================

class _SectionSkeleton extends StatefulWidget {
  final int rows;

  const _SectionSkeleton({
    this.rows = 4,
  });

  @override
  State<_SectionSkeleton> createState() =>
      _SectionSkeletonState();
}

class _SectionSkeletonState
    extends State<_SectionSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 850,
      ),
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
      opacity:
      0.35 + (_controller.value * 0.35),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius:
          BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            for (int i = 0;
            i < widget.rows;
            i++)
              Padding(
                padding:
                const EdgeInsets.symmetric(
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    _box(85, 10),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _box(
                        double.infinity,
                        10,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// HEALTH HISTORY
// ============================================================================

class _HealthHistoryExpander
    extends StatefulWidget {
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
    final older =
    widget.records.skip(1).toList();

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
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
                  size: 9.5,
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
          const SizedBox(height: 5),
          for (final record in older)
            Padding(
              padding:
              const EdgeInsets.only(
                bottom: 5,
              ),
              child: Text(
                '${DateFormat('d MMM yyyy').format(record.date)}'
                    '${record.nextDueDate != null ? ' · Due: ${DateFormat('d MMM yyyy').format(record.nextDueDate!)}' : ''}'
                    '${record.notes.trim().isNotEmpty ? ' · ${record.notes.trim()}' : ''}',
                style: AppTheme.body(
                  size: 9.5,
                  color: AppColors.textGrey,
                ),
              ),
            ),
        ],
      ],
    );
  }
}