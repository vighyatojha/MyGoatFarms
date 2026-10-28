import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../goat_icons.dart';

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
  // --- Finance module ---
  expenseVoided,
  revenueAdded,
  revenueVoided,

  // --- Palai (written by older code as plain strings; listed here so
  //     they get their own icon instead of the "payment" fallback) ---
  outstandingAdded,
  checkInTransportAdded,
  monthlyBillGenerated,
  monthlyBillUpdated,
  monthlyBillDeleted,
  goatDeathRecorded,
  farmLossRecorded,
  palaiHealthRecorded,
  palaiGoatDeleted,

  // --- Trading: purchases / lots ---
  lotPurchased,
  lotEdited,
  lotCancelled,
  lotReceived,
  supplierPaymentAdded,
  supplierPaymentVoided,
  lotDeathRecorded,
  lotDeathUndone,

  // --- Trading: goats ---
  goatRegistered,
  goatMovedToOwnPalai,
  goatWeightRecorded,
  goatHealthRecorded,

  // --- Trading: sales ---
  bookingCreated,
  bookingDelivered,
  waitForDeliveryCreated,
  waitForDeliveryPickedUp,
  goatTransferredToPalai,
  balancePaymentReceived,

  // --- Stock ---
  stockItemEdited,

  /// Fallback for an activity type this app version doesn't know.
  other,
}

class ActivityLog {
  final String id;
  final ActivityType type;
  final String title;
  final String subtitle;
  final String module; // "home", "palai", "stock", "trading", "breeding", "finance"
  final DateTime timestamp;

  /// Who performed this activity — set by [FirestoreService.getCurrentActor]
  /// at write time. Nullable so older activity docs written before this
  /// field existed still parse and render fine (they just show no "By ..."
  /// line).
  final String? actorUid;
  final String? actorName;
  final String? actorRole; // 'owner' or 'partner'

  ActivityLog({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.module,
    required this.timestamp,
    this.actorUid,
    this.actorName,
    this.actorRole,
  });

  factory ActivityLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ActivityLog(
      id: doc.id,
      type: ActivityType.values.firstWhere(
            (e) => e.name == data['type'],
        // Unknown types used to fall back to paymentReceived, so they
        // showed a payment icon. A neutral icon is less misleading.
        orElse: () => ActivityType.other,
      ),
      title: data['title'] ?? '',
      subtitle: data['subtitle'] ?? '',
      module: data['module'] ?? 'home',
      // Activities are queried `orderBy('timestamp', descending: true)`,
      // so falling back to DateTime.now() for a record with no/corrupt
      // timestamp made it jump to the TOP of Recent Activity and read as
      // happening right now. Fall back to epoch instead, so a record
      // missing this field sinks to the bottom rather than lying about
      // when it happened.
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'title': title,
      'subtitle': subtitle,
      'module': module,
      'timestamp': Timestamp.fromDate(timestamp),
      if (actorUid != null) 'actorUid': actorUid,
      if (actorName != null) 'actorName': actorName,
      if (actorRole != null) 'actorRole': actorRole,
    };
  }

  /// "OWNER" / "PARTNER" badge text for the activity feed, or null when
  /// there's no actor on this doc (older activities, or the write
  /// happened outside a signed-in session).
  String? get actorRoleLabel {
    final role = actorRole;
    if (role == null || role.isEmpty) return null;
    return role.toUpperCase();
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
        return GoatIcons.paw;
      case ActivityType.ownFarmExpenseAdded:
        return Icons.remove_circle_outline;
      case ActivityType.expenseVoided:
        return Icons.undo_rounded;
      case ActivityType.revenueAdded:
        return Icons.add_circle_outline;
      case ActivityType.revenueVoided:
        return Icons.undo_rounded;
      case ActivityType.outstandingAdded:
        return Icons.request_quote_outlined;
      case ActivityType.checkInTransportAdded:
        return Icons.local_shipping_outlined;
      case ActivityType.monthlyBillGenerated:
        return Icons.receipt_long_outlined;
      case ActivityType.monthlyBillUpdated:
        return Icons.edit_note_outlined;
      case ActivityType.monthlyBillDeleted:
        return Icons.delete_outline;
      case ActivityType.goatDeathRecorded:
        return Icons.report_outlined;
      case ActivityType.farmLossRecorded:
        return Icons.trending_down;
      case ActivityType.palaiHealthRecorded:
        return Icons.vaccines_outlined;
      case ActivityType.palaiGoatDeleted:
        return Icons.delete_outline;
      case ActivityType.lotPurchased:
        return Icons.shopping_cart_outlined;
      case ActivityType.lotEdited:
        return Icons.edit_outlined;
      case ActivityType.lotCancelled:
        return Icons.cancel_outlined;
      case ActivityType.lotReceived:
        return Icons.inventory_2_outlined;
      case ActivityType.supplierPaymentAdded:
        return Icons.payments_outlined;
      case ActivityType.supplierPaymentVoided:
        return Icons.undo_rounded;
      case ActivityType.lotDeathRecorded:
        return Icons.report_outlined;
      case ActivityType.lotDeathUndone:
        return Icons.undo_rounded;
      case ActivityType.goatRegistered:
        return GoatIcons.paw;
      case ActivityType.goatMovedToOwnPalai:
        return Icons.home_work_outlined;
      case ActivityType.goatWeightRecorded:
        return Icons.monitor_weight_outlined;
      case ActivityType.goatHealthRecorded:
        return Icons.vaccines_outlined;
      case ActivityType.bookingCreated:
        return Icons.event_available_outlined;
      case ActivityType.bookingDelivered:
        return Icons.local_shipping_outlined;
      case ActivityType.waitForDeliveryCreated:
        return Icons.hourglass_top;
      case ActivityType.waitForDeliveryPickedUp:
        return Icons.local_shipping_outlined;
      case ActivityType.goatTransferredToPalai:
        return Icons.swap_horiz;
      case ActivityType.balancePaymentReceived:
        return Icons.account_balance_wallet_outlined;
      case ActivityType.stockItemEdited:
        return Icons.edit_outlined;
      case ActivityType.other:
        return Icons.history;
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
      case ActivityType.expenseVoided:
        return AppColors.textGrey;
      case ActivityType.revenueAdded:
        return AppColors.success;
      case ActivityType.revenueVoided:
        return AppColors.textGrey;
      case ActivityType.outstandingAdded:
        return AppColors.warning;
      case ActivityType.checkInTransportAdded:
        return AppColors.info;
      case ActivityType.monthlyBillGenerated:
        return AppColors.primaryGreen;
      case ActivityType.monthlyBillUpdated:
        return AppColors.info;
      case ActivityType.monthlyBillDeleted:
        return AppColors.error;
      case ActivityType.goatDeathRecorded:
        return AppColors.error;
      case ActivityType.farmLossRecorded:
        return AppColors.error;
      case ActivityType.palaiHealthRecorded:
        return AppColors.breedingPurple;
      case ActivityType.palaiGoatDeleted:
        return AppColors.error;
      case ActivityType.lotPurchased:
        return AppColors.tradingBlue;
      case ActivityType.lotEdited:
        return AppColors.info;
      case ActivityType.lotCancelled:
        return AppColors.error;
      case ActivityType.lotReceived:
        return AppColors.primaryGreen;
      case ActivityType.supplierPaymentAdded:
        return AppColors.warning;
      case ActivityType.supplierPaymentVoided:
        return AppColors.textGrey;
      case ActivityType.lotDeathRecorded:
        return AppColors.error;
      case ActivityType.lotDeathUndone:
        return AppColors.textGrey;
      case ActivityType.goatRegistered:
        return AppColors.primaryGreen;
      case ActivityType.goatMovedToOwnPalai:
        return AppColors.darkGreen;
      case ActivityType.goatWeightRecorded:
        return AppColors.stockTeal;
      case ActivityType.goatHealthRecorded:
        return AppColors.breedingPurple;
      case ActivityType.bookingCreated:
        return AppColors.tradingBlue;
      case ActivityType.bookingDelivered:
        return AppColors.success;
      case ActivityType.waitForDeliveryCreated:
        return AppColors.warning;
      case ActivityType.waitForDeliveryPickedUp:
        return AppColors.success;
      case ActivityType.goatTransferredToPalai:
        return AppColors.info;
      case ActivityType.balancePaymentReceived:
        return AppColors.success;
      case ActivityType.stockItemEdited:
        return AppColors.stockTeal;
      case ActivityType.other:
        return AppColors.textGrey;
    }
  }

  /// Short section name shown on the activity chip ("TRADING", "PALAI"...).
  String get moduleLabel => ActivityLog.labelForModule(module);

  static String labelForModule(String module) {
    switch (module) {
      case 'palai':
        return 'Palai';
      case 'stock':
        return 'Stock';
      case 'trading':
        return 'Trading';
      case 'finance':
        return 'Finance';
      case 'customers':
        return 'Customers';
      case 'breeding':
        return 'Breeding';
      case 'ownFarm':
        return 'Own Farm';
      case 'home':
      default:
        return 'Farm';
    }
  }
}