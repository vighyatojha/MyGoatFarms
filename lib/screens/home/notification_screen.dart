import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/notification_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../palai/customer_palai/goat_profile_screen.dart';
import '../palai/own_farm/own_farm_goat_detail_screen.dart';

/// Notification center — reads from `farms/{farmId}/notifications`.
///
/// This collection is populated two ways (see NotificationService /
/// HealthReminderScheduler docs):
///   * HealthReminderScheduler's due-check, for vaccination / hoof
///     cutting / hair trimming reminders that are due today or overdue.
///   * Any future event-based write (payment received, check-in/out,
///     low stock) — not wired up everywhere yet, so those categories
///     may be sparse until the corresponding screens call
///     FirestoreService.addNotification themselves.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  bool _isOwner = false;
  final _timeFmt = DateFormat('d MMM, h:mm a');

  @override
  void initState() {
    super.initState();
    _loadFarmId();
  }

  Future<void> _loadFarmId() async {
    final id = await FirestoreService.instance.currentFarmId();
    final actor = await FirestoreService.instance.getCurrentActor();
    if (!mounted) return;
    setState(() {
      _farmId = id;
      _isOwner = actor?.role == 'owner';
      _loadingFarm = false;
    });
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'health':
        return Icons.health_and_safety_outlined;
      case 'finance':
        return Icons.payments_outlined;
      case 'palai':
        return Icons.pets_outlined;
      case 'inventory':
        return Icons.warning_amber_outlined;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  Color _colorFor(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.critical:
        return AppColors.error;
      case NotificationPriority.important:
        return AppColors.warning;
      case NotificationPriority.normal:
        return AppColors.primaryGreen;
    }
  }

  Future<void> _onTap(AppNotificationRecord n) async {
    final farmId = _farmId;
    if (farmId == null) return;

    if (!n.isRead) {
      // Fire-and-forget — don't block navigation on this write.
      FirestoreService.instance.markNotificationRead(farmId, n.id);
    }

    // Health notifications carry a goatId — deep-link to that goat.
    // Customer-Palai health records (vaccination/hoof-cutting/hair-
    // trimming/medicine) additionally carry a customerId, and land on
    // GoatProfileScreen at the tab matching what the notification was
    // about; Own-Farm health events go to OwnFarmGoatDetailScreen as
    // before.
    final goatId = n.reference['goatId'];
    final customerId = n.reference['customerId'];
    if (n.category == 'health' && goatId != null && mounted) {
      if (customerId != null) {
        final goat = await FirestoreService.instance.getPalaiGoat(farmId, customerId, goatId);
        if (goat != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GoatProfileScreen(
                farmId: farmId,
                goat: goat,
                initialTabIndex: _customerPalaiTabIndexFor(n.type),
              ),
            ),
          );
        }
      } else {
        final goat = await FirestoreService.instance.getOwnFarmGoat(farmId, goatId);
        if (goat != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OwnFarmGoatDetailScreen(goat: goat)),
          );
        }
      }
    }
  }

  /// GoatProfileScreen's tab order is: 0 Overview, 1 Photos & Growth,
  /// 2 Health, 3 Vaccination, 4 Hoof Cutting, 5 Hair Trimming,
  /// 6 Medicine, ... — map a notification `type` (e.g.
  /// 'vaccination_due', 'hoofCutting_logged') to the matching tab.
  int _customerPalaiTabIndexFor(String type) {
    if (type.startsWith('vaccination')) return 3;
    if (type.startsWith('hoofCutting')) return 4;
    if (type.startsWith('hairTrimming')) return 5;
    if (type.startsWith('medicine')) return 6;
    return 2; // General health record — Health tab.
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete notification?', style: AppTheme.heading(size: 15)),
        content: Text('This can\'t be undone.', style: AppTheme.body(size: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteNotification(AppNotificationRecord n) async {
    final farmId = _farmId;
    if (farmId == null) return;
    try {
      await FirestoreService.instance.deleteNotification(farmId, n.id);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final message = e.code == 'permission-denied'
          ? 'Only the farm owner can delete notifications.'
          : 'Could not delete notification.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete notification.')),
      );
    }
  }

  Future<void> _showActionsSheet(AppNotificationRecord n) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textGrey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                n.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                color: AppColors.textDark,
              ),
              title: Text(
                n.isRead ? 'Mark as unread' : 'Mark as read',
                style: AppTheme.body(size: 14),
              ),
              onTap: () => Navigator.of(sheetContext).pop('toggleRead'),
            ),
            // Delete is server-enforced to owners only (see
            // FirestoreService.deleteNotification) — only offering it
            // to owners here is just the matching UX, not the actual
            // security boundary.
            if (_isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: Text('Delete', style: AppTheme.body(size: 14, color: AppColors.error)),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'toggleRead') {
      final farmId = _farmId;
      if (farmId == null) return;
      if (n.isRead) {
        await FirestoreService.instance.markNotificationUnread(farmId, n.id);
      } else {
        await FirestoreService.instance.markNotificationRead(farmId, n.id);
      }
    } else if (action == 'delete') {
      final confirmed = await _confirmDelete();
      if (confirmed) {
        await _deleteNotification(n);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Notifications', style: AppTheme.heading(size: 17)),
        actions: [
          if (_farmId != null)
            TextButton(
              onPressed: () => FirestoreService.instance.markAllNotificationsRead(_farmId!),
              child: Text('Mark all read', style: AppTheme.body(size: 12, color: AppColors.primaryGreen, weight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loadingFarm
          ? const Center(child: CircularProgressIndicator())
          : _farmId == null
          ? FarmNotLinkedState(onRetry: _loadFarmId)
          : StreamBuilder<List<AppNotificationRecord>>(
        stream: FirestoreService.instance.notificationsStream(_farmId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load notifications.', style: AppTheme.body(size: 13)),
            );
          }

          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
            return Center(child: Text('No notifications yet.', style: AppTheme.body(size: 13)));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final n = notifications[index];
              final tile = FadeInUp(
                delay: Duration(milliseconds: 25 * index),
                duration: const Duration(milliseconds: 180),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _onTap(n),
                  onLongPress: () => _showActionsSheet(n),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: n.isRead ? Colors.white : AppColors.lightGreen.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _colorFor(n.priority).withOpacity(0.12), shape: BoxShape.circle),
                          child: Icon(_iconFor(n.category), color: _colorFor(n.priority), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.title, style: AppTheme.heading(size: 13)),
                              const SizedBox(height: 2),
                              Text(n.message, style: AppTheme.body(size: 12)),
                              const SizedBox(height: 4),
                              Text(
                                n.createdAt != null ? _timeFmt.format(n.createdAt!) : '',
                                style: AppTheme.body(size: 10),
                              ),
                            ],
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                ),
              );

              // Delete is server-enforced to owners only (see
              // FirestoreService.deleteNotification) — only offering the
              // swipe gesture to owners here is just the matching UX,
              // not the actual security boundary.
              if (!_isOwner) return tile;

              return Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(),
                onDismissed: (_) => _deleteNotification(n),
                background: Container(
                  alignment: Alignment.centerRight,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }
}