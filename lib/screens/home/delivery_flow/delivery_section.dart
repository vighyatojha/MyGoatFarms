import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/booking_delivery_group.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../models/wait_delivery_group.dart';
import '../../../services/booking_delivery_service.dart';
import '../../../services/wait_delivery_service.dart';

/// The two dashboard sections of the delivery flow:
///
///   HOME / DASHBOARD
///     ├── WAIT ON DELIVERY   → customers → goats → details / Complete
///     └── BOOKING & HOLDING  → customers → goats → details
///
/// Nothing here creates or changes data. The customers and goats are
/// grouped by the SAME code the existing Trading screens use
/// ([WaitDeliveryCustomer.group] / [BookingDeliveryCustomer.group]), so a
/// customer shows in a section only while they have goats in that state,
/// and each section shows only its own goats.
enum DeliverySection { waitOnDelivery, bookingHolding }

extension DeliverySectionInfo on DeliverySection {
  bool get isWait => this == DeliverySection.waitOnDelivery;

  String get title => isWait ? 'Wait on Delivery' : 'Booking & Holding';

  /// Shown under a goat in this section.
  String get goatStatusLabel => isWait ? 'Wait on Delivery' : 'Booked';

  IconData get icon =>
      isWait ? Icons.local_shipping_outlined : Icons.event_available_outlined;

  /// Same colours the Trading dashboard uses for these two cards.
  Color get color => isWait ? AppColors.stockTeal : Colors.deepPurple;

  String get emptyTitle =>
      isWait ? 'No goats waiting for delivery' : 'No booked or held goats';

  String get emptySubtitle => isWait
      ? 'Customers whose goats are waiting for delivery will show up here.'
      : 'Customers with booked or held goats will show up here.';

  /// Open sales of this section (one Firestore listener).
  Stream<List<Sale>> openSalesStream(String farmId) => isWait
      ? WaitDeliveryService.instance.openSalesStream(farmId)
      : BookingDeliveryService.instance.openSalesStream(farmId);

  /// Groups [sales] and [goats] into this section's customers, using the
  /// existing grouping code, newest booking first.
  List<SectionCustomer> group({
    required List<Sale> sales,
    required List<Goat> goats,
  }) {
    if (isWait) {
      return [
        for (final c in WaitDeliveryCustomer.group(sales: sales, goats: goats))
          SectionCustomer(
            key: c.key,
            name: c.name,
            mobile: c.mobile,
            bookings: [
              for (final e in c.sales)
                SectionBooking(sale: e.sale, goats: e.goats),
            ],
          ),
      ];
    }

    return [
      for (final c in BookingDeliveryCustomer.group(sales: sales, goats: goats))
        SectionCustomer(
          key: c.key,
          name: c.name,
          mobile: c.mobile,
          bookings: [
            for (final e in c.sales)
              SectionBooking(sale: e.sale, goats: e.goats),
          ],
        ),
    ];
  }
}

/// One open booking (sale) of a customer, with the goats it holds that
/// are still in this section.
class SectionBooking {
  final Sale sale;

  /// Registered goats still in this section. Empty for a lot booking,
  /// whose goats are counted inside the lot instead.
  final List<Goat> goats;

  const SectionBooking({required this.sale, required this.goats});

  String get id => sale.id;

  bool get isLot => sale.isLotSale;

  int get goatCount => isLot ? sale.lotQuantity : goats.length;

  DateTime get bookedAt => sale.saleDate ?? sale.holdingStart;
}

/// One customer of a section.
class SectionCustomer {
  final String key;
  final String name;
  final String mobile;

  /// Newest booking first.
  final List<SectionBooking> bookings;

  const SectionCustomer({
    required this.key,
    required this.name,
    required this.mobile,
    required this.bookings,
  });

  int get goatCount => bookings.fold<int>(0, (sum, b) => sum + b.goatCount);

  DateTime get latestBookedAt {
    var latest = bookings.first.bookedAt;
    for (final b in bookings) {
      if (b.bookedAt.isAfter(latest)) latest = b.bookedAt;
    }
    return latest;
  }

  /// Search by name, mobile, goat ID, booking ID or lot ID.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (mobile.toLowerCase().contains(q)) return true;

    for (final b in bookings) {
      if (b.id.toLowerCase().contains(q)) return true;
      if (b.isLot && b.sale.lotDisplayId.toLowerCase().contains(q)) {
        return true;
      }
      for (final g in b.goats) {
        if (g.id.toLowerCase().contains(q)) return true;
      }
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets for the delivery flow screens
// ---------------------------------------------------------------------------

/// Back button + title + subtitle, same look as the existing Wait on
/// Delivery screens.
class DeliveryHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool enabled;

  const DeliveryHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: enabled ? () => Navigator.of(context).maybePop() : null,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 19),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered icon + title + subtitle, for empty / error states.
class DeliveryMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const DeliveryMessage({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(height: 11),
            Text(title,
                textAlign: TextAlign.center, style: AppTheme.heading(size: 15)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center, style: AppTheme.body(size: 11)),
          ],
        ),
      ),
    );
  }
}

/// Small rounded pill with an icon and a number / label.
class DeliveryPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const DeliveryPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}