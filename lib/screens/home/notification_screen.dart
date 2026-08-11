import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../../app_theme.dart';

/// Notification center.
///
/// Intentionally NOT wired to Firestore — every other screen in this app
/// persists to Firestore, but notifications are transient/local (or would
/// come from a push-notification payload / FCM in a later step), so this
/// screen works off an in-memory list for now.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

enum NotificationKind { payment, checkIn, checkOut, lowStock, reminder }

class _AppNotification {
  final NotificationKind kind;
  final String title;
  final String message;
  final String time;
  bool isRead;

  _AppNotification({
    required this.kind,
    required this.title,
    required this.message,
    required this.time,
    this.isRead = false,
  });
}

class _NotificationScreenState extends State<NotificationScreen> {
  // Local, in-memory sample data. Replace with FCM / local-notification
  // history when push notifications are wired up.
  final List<_AppNotification> _notifications = [
    _AppNotification(
      kind: NotificationKind.payment,
      title: 'Payment Received',
      message: 'Rameshbhai paid ₹5,000 for Palai charges.',
      time: '10:30 AM',
    ),
    _AppNotification(
      kind: NotificationKind.lowStock,
      title: 'Low Stock Alert',
      message: 'Mix Feed stock is running low (12 kg left).',
      time: '9:05 AM',
      isRead: true,
    ),
    _AppNotification(
      kind: NotificationKind.checkOut,
      title: 'Goat Check-Out Due',
      message: '2 goats are due for check-out today.',
      time: 'Yesterday',
    ),
    _AppNotification(
      kind: NotificationKind.reminder,
      title: 'Billing Reminder',
      message: 'Monthly bill pending for 8 customers this week.',
      time: '2 Days Ago',
      isRead: true,
    ),
  ];

  IconData _iconFor(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.payment:
        return Icons.payments_outlined;
      case NotificationKind.checkIn:
        return Icons.login;
      case NotificationKind.checkOut:
        return Icons.logout;
      case NotificationKind.lowStock:
        return Icons.warning_amber_outlined;
      case NotificationKind.reminder:
        return Icons.notifications_active_outlined;
    }
  }

  Color _colorFor(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.payment:
        return AppColors.success;
      case NotificationKind.checkIn:
        return AppColors.info;
      case NotificationKind.checkOut:
        return AppColors.error;
      case NotificationKind.lowStock:
        return AppColors.warning;
      case NotificationKind.reminder:
        return AppColors.primaryGreen;
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
          TextButton(
            onPressed: () => setState(() {
              for (final n in _notifications) {
                n.isRead = true;
              }
            }),
            child: Text('Mark all read', style: AppTheme.body(size: 12, color: AppColors.primaryGreen, weight: FontWeight.w600)),
          ),
        ],
      ),
      body: _notifications.isEmpty
          ? Center(child: Text('No notifications yet.', style: AppTheme.body(size: 13)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final n = _notifications[index];
                return FadeInUp(
                  delay: Duration(milliseconds: 80 * index),
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
                          decoration: BoxDecoration(color: _colorFor(n.kind).withOpacity(0.12), shape: BoxShape.circle),
                          child: Icon(_iconFor(n.kind), color: _colorFor(n.kind), size: 18),
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
                              Text(n.time, style: AppTheme.body(size: 10)),
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
                );
              },
            ),
    );
  }
}
