import 'package:cloud_firestore/cloud_firestore.dart';

/// Priority levels a notification can carry — mirrors the three-tier
/// scheme from the notification design doc (Critical / Important /
/// Normal). Used to sort/highlight in the UI, not to change delivery.
enum NotificationPriority { critical, important, normal }

NotificationPriority _priorityFromString(String? value) {
  switch (value) {
    case 'critical':
      return NotificationPriority.critical;
    case 'important':
      return NotificationPriority.important;
    default:
      return NotificationPriority.normal;
  }
}

/// A single row in a farm's `notifications` collection — what
/// NotificationScreen renders.
class AppNotificationRecord {
  final String id;
  final String type; // e.g. 'vaccination_due', 'payment_received'
  final String category; // e.g. 'health', 'finance', 'palai', 'inventory'
  final String title;
  final String message;
  final NotificationPriority priority;
  final Map<String, String> reference; // e.g. {goatId, eventId}
  final bool isRead;
  final DateTime? createdAt;

  const AppNotificationRecord({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.message,
    required this.priority,
    required this.reference,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotificationRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppNotificationRecord(
      id: doc.id,
      type: (data['type'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      message: (data['message'] ?? '').toString(),
      priority: _priorityFromString(data['priority'] as String?),
      reference: Map<String, String>.from(
        (data['reference'] as Map<dynamic, dynamic>? ?? {}).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      ),
      isRead: data['isRead'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}