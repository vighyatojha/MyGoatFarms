import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_model.dart';

/// Small coloured pill used by Lot Management and Lot Detail.
class LotBadge extends StatelessWidget {
  final String label;
  final Color color;

  const LotBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

Color lotLocationColor(LotLocation location) {
  switch (location) {
    case LotLocation.atSupplier:
      return AppColors.info;
    case LotLocation.partiallyAtFarm:
      return const Color(0xFFB26A00);
    case LotLocation.atFarm:
      return AppColors.success;
  }
}

Color lotPaymentColor(String status) {
  switch (status) {
    case 'Paid':
      return AppColors.success;
    case 'Partial':
      return const Color(0xFFB26A00);
    case 'Cancelled':
      return AppColors.textGrey;
    default:
      return AppColors.error;
  }
}

/// Location label with the wording Lot Management uses on its tabs.
String lotLocationLabel(LotLocation location) {
  switch (location) {
    case LotLocation.atSupplier:
      return 'At Supplier';
    case LotLocation.partiallyAtFarm:
      return 'Partially Received';
    case LotLocation.atFarm:
      return 'At Farm';
  }
}
IconData lotLocationIcon(LotLocation location) {
  switch (location) {
    case LotLocation.atSupplier:
      return Icons.local_shipping_outlined;
    case LotLocation.partiallyAtFarm:
      return Icons.timelapse_rounded;
    case LotLocation.atFarm:
      return Icons.check_circle_outline_rounded;
  }
}

/// Outlined pill with a small leading icon (location / payment status).
class LotIconBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const LotIconBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}