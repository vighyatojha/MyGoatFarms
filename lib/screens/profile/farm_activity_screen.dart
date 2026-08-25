import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Farm-wide activity feed for the Profile screen.
///
/// This intentionally reuses the same `activitiesStream` / `ActivityLog`
/// that Home and Palai already log to — so every entry shown here is a
/// real, already-recorded action instead of a separate empty feed.
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
        title: const Text('Farm Activity'),
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: StreamBuilder<List<ActivityLog>>(
        stream: FirestoreService.instance.activitiesStream(
          farmId,
          limit: 60,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }

          final items = snapshot.data ?? const <ActivityLog>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  'No activity recorded yet. Actions across Palai, Stock '
                  'and Customers will show up here.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 13, color: AppColors.textGrey),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) => _ActivityTile(activity: items[index]),
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityLog activity;

  const _ActivityTile({required this.activity});

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
    return '${local.day}/${local.month}/${local.year} $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: activity.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(activity.icon, size: 20, color: activity.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          activity.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _LabelChip(text: _moduleLabel(activity.module)),
                    ],
                  ),
                  if (activity.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      activity.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 12, color: AppColors.textGrey),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(activity.timestamp),
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String text;

  const _LabelChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: AppColors.primaryGreen,
          letterSpacing: .4,
        ),
      ),
    );
  }
}
