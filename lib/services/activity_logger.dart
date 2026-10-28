import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/activity_model.dart';
import 'firestore_service.dart';

/// One-line way to add an entry to the farm's activity feed — the list
/// shown in Home > Recent Activity and Profile > Farm Activity.
///
/// Used by the Trading module (purchases, lots, registrations, sales,
/// bookings, Wait on Delivery, Own Palai) and by Palai screens that did
/// not log anything before (health records, check-out, goat delete).
///
/// Always "fire and forget":
///   * it is called AFTER the real work has been saved, and
///   * it never throws — if the activity entry cannot be written, the
///     sale / purchase / record the user just saved is still saved.
///
/// It goes through [FirestoreService.logActivity], so every entry also
/// gets "By <name> · OWNER/PARTNER" and, for a partner, the usual
/// notification to the farm owner.
class ActivityLogger {
  ActivityLogger._();

  static void log({
    required String farmId,
    required ActivityType type,
    required String title,
    required String module,
    String subtitle = '',
  }) {
    if (farmId.isEmpty) return;

    unawaited(_write(
      farmId: farmId,
      type: type,
      title: title,
      module: module,
      subtitle: subtitle,
    ));
  }

  static Future<void> _write({
    required String farmId,
    required ActivityType type,
    required String title,
    required String module,
    required String subtitle,
  }) async {
    try {
      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: type,
          title: title,
          subtitle: subtitle,
          module: module,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('ActivityLogger: "$title" could not be logged: $e');
    }
  }

  // -------------------------------------------------------------------
  // Small text helpers so every subtitle reads the same way.
  // -------------------------------------------------------------------

  /// ₹1200.4 -> "₹1200"
  static String money(num value) => '₹${value.toStringAsFixed(0)}';

  /// 1 -> "1 goat", 3 -> "3 goats"
  static String goats(int count) => count == 1 ? '1 goat' : '$count goats';

  /// 24.5 -> "24.5 kg", 24.0 -> "24 kg"
  static String kg(num value) {
    final fixed = value.toStringAsFixed(2);
    final trimmed = fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
    return '$trimmed kg';
  }

  /// Lot document id -> the lot's display id: "PUR-0007" -> "LOT-0007".
  /// Same rule as TradingPurchase.lotId.
  static String lotLabel(String lotDocId) {
    final dash = lotDocId.indexOf('-');
    return dash < 0 ? lotDocId : 'LOT-${lotDocId.substring(dash + 1)}';
  }

  /// Joins non-empty parts with " · ".
  static String join(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(' · ');
}