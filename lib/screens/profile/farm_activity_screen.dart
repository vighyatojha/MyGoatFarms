import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Farm-wide activity feed for the Profile screen.
///
/// Reuses the same `activitiesStream` / `ActivityLog` used by Home and
/// Palai, so every entry shown here is a real recorded farm action.
class FarmActivityScreen extends StatelessWidget {
  final String farmId;

  const FarmActivityScreen({
    super.key,
    required this.farmId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text(
          'Farm Activity',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.darkGreen,
          ),
        ),
        backgroundColor: AppColors.paleGreen,
        foregroundColor: AppColors.darkGreen,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<List<ActivityLog>>(
        stream: FirestoreService.instance.activitiesStream(
          farmId,
          limit: 60,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryGreen,
              ),
            );
          }

          final items = snapshot.data ?? const <ActivityLog>[];

          if (items.isEmpty) {
            return _buildEmptyState();
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
            children: [
              _buildHeader(items.length),
              const SizedBox(height: 16),

              _buildSectionTitle(),

              const SizedBox(height: 10),

              ...items.asMap().entries.map(
                    (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ActivityTile(
                    activity: entry.value,
                    isFirst: entry.key == 0,
                    isLast: entry.key == items.length - 1,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int activityCount) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 20),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.timeline_outlined,
              size: 27,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Farm Activity',
                  style: AppTheme.heading(
                    size: 16,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A record of recent actions across your farm.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$activityCount',
              style: AppTheme.heading(
                size: 12,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Activity',
                style: AppTheme.heading(
                  size: 14,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Latest actions recorded on the farm',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9F8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFE9EEEB),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 6,
                color: AppColors.primaryGreen,
              ),
              SizedBox(width: 5),
              Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryGreen,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          decoration: AppTheme.card(radius: 20),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 36,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: const Icon(
                  Icons.history_outlined,
                  size: 34,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 17),
              Text(
                'No activity yet',
                style: AppTheme.heading(
                  size: 17,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Actions across Palai, Stock, Customers and other '
                    'farm sections will appear here.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityLog activity;
  final bool isFirst;
  final bool isLast;

  const _ActivityTile({
    required this.activity,
    required this.isFirst,
    required this.isLast,
  });

  static String _moduleLabel(String module) {
    switch (module) {
      case 'palai':
        return 'Palai';
      case 'stock':
        return 'Stock';
      case 'trading':
        return 'Trading';
      case 'breeding':
        return 'Breeding';
      case 'home':
      default:
        return 'Farm';
    }
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();

    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;

    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    return '${local.day}/${local.month}/${local.year} '
        '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final module = _moduleLabel(activity.module);

    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 18),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimelineIcon(),
          const SizedBox(width: 12),
          Expanded(
            child: _buildContent(module),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineIcon() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: activity.color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            activity.icon,
            size: 21,
            color: activity.color,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(String module) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                activity.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.textDark,
                  weight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 7),
            _LabelChip(
              text: module,
              color: activity.color,
            ),
          ],
        ),

        if (activity.subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            activity.subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          ),
        ],

        const SizedBox(height: 9),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFE9EEEB),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: 12,
                color: AppColors.textGrey,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _formatDate(activity.timestamp),
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 9,
                    color: AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (activity.actorName != null &&
            activity.actorName!.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.person_outline,
                size: 13,
                color: AppColors.textGrey,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  activity.actorRoleLabel != null
                      ? 'By ${activity.actorName} · '
                      '${activity.actorRoleLabel}'
                      : 'By ${activity.actorName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 9,
                    color: AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String text;
  final Color color;

  const _LabelChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 80,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: .4,
        ),
      ),
    );
  }
}