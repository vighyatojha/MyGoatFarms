import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';

enum ActivityType {
  paymentReceived,
  goatSold,
  feedStockAdded,
  feedUsed,
  goatCheckIn,
  goatCheckOut,
  expenseAdded,
  medicineAdded,
  medicineUsed,
  goatDelivered,
  reportGenerated,
  customerAdded,
  customerUpdated,
  customerDeleted,
  ownFarmGoatAdded,
  ownFarmExpenseAdded,
}

class ActivityLog {
  final String id;
  final ActivityType type;
  final String title;
  final String subtitle;
  final String module; // "home", "palai", "stock", "trading", "breeding"
  final DateTime timestamp;

  ActivityLog({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.module,
    required this.timestamp,
  });

  factory ActivityLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ActivityLog(
      id: doc.id,
      type: ActivityType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => ActivityType.paymentReceived,
      ),
      title: data['title'] ?? '',
      subtitle: data['subtitle'] ?? '',
      module: data['module'] ?? 'home',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'title': title,
      'subtitle': subtitle,
      'module': module,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  IconData get icon {
    switch (type) {
      case ActivityType.paymentReceived:
        return Icons.payments_outlined;
      case ActivityType.goatSold:
        return Icons.sell_outlined;
      case ActivityType.feedStockAdded:
        return Icons.grass_outlined;
      case ActivityType.feedUsed:
        return Icons.outbox_outlined;
      case ActivityType.goatCheckIn:
        return Icons.login;
      case ActivityType.goatCheckOut:
        return Icons.logout;
      case ActivityType.expenseAdded:
        return Icons.remove_circle_outline;
      case ActivityType.medicineAdded:
        return Icons.medication_outlined;
      case ActivityType.medicineUsed:
        return Icons.medical_information_outlined;
      case ActivityType.goatDelivered:
        return Icons.local_shipping_outlined;
      case ActivityType.reportGenerated:
        return Icons.description_outlined;
      case ActivityType.customerAdded:
        return Icons.person_add_alt;
      case ActivityType.customerUpdated:
        return Icons.edit_outlined;
      case ActivityType.customerDeleted:
        return Icons.person_remove_alt_1_outlined;
      case ActivityType.ownFarmGoatAdded:
        return Icons.pets;
      case ActivityType.ownFarmExpenseAdded:
        return Icons.remove_circle_outline;
    }
  }

  Color get color {
    switch (type) {
      case ActivityType.paymentReceived:
        return AppColors.success;
      case ActivityType.goatSold:
        return AppColors.warning;
      case ActivityType.feedStockAdded:
        return AppColors.stockTeal;
      case ActivityType.feedUsed:
        return AppColors.warning;
      case ActivityType.goatCheckIn:
        return AppColors.info;
      case ActivityType.goatCheckOut:
        return AppColors.error;
      case ActivityType.expenseAdded:
        return AppColors.error;
      case ActivityType.medicineAdded:
        return AppColors.breedingPurple;
      case ActivityType.medicineUsed:
        return AppColors.warning;
      case ActivityType.goatDelivered:
        return AppColors.info;
      case ActivityType.reportGenerated:
        return AppColors.primaryGreen;
      case ActivityType.customerAdded:
        return AppColors.primaryGreen;
      case ActivityType.customerUpdated:
        return AppColors.info;
      case ActivityType.customerDeleted:
        return AppColors.error;
      case ActivityType.ownFarmGoatAdded:
        return AppColors.primaryGreen;
      case ActivityType.ownFarmExpenseAdded:
        return AppColors.error;
    }
  }
}
