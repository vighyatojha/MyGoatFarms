import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/goat_service.dart';
import '../../../services/sale_goat_details_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/lot_origin_card.dart';
import '../../palai/fullscreen_image_viewer.dart';
import '../../trading/own_palai/own_palai_goat_profile_screen.dart';
import 'complete_goats_selector_screen.dart';
import 'delivery_section.dart';
import 'lot_goat_profile_screen.dart';

/// Dashboard → section → customer → THIS CUSTOMER'S GOATS.
///
///  * Wait on Delivery: the customer's Wait-on-Delivery goats, grouped by
///    booking.
///  * Booking & Holding: the customer's booked / held goats, grouped by
///    booking.
///
/// Both have a COMPLETE button at the bottom that opens
/// [CompleteGoatsSelectorScreen] → that section's existing checkout.
///
/// Every goat is shown with the photo, approximate age and weight taken on
/// the sale's Goat Photos step. Tapping a goat opens its profile:
///  * registered goats → [OwnPalaiGoatProfileScreen];
///  * a lot booking's goats ("Goat 1..N", at the farm or still at the
///    supplier) → [LotGoatProfileScreen] (lot details, photos, weight,
///    health). Goats with nothing saved yet are listed too, so their
///    photo, age and weight can be added there.
class DeliveryCustomerGoatsScreen extends StatefulWidget {
  final String farmId;
  final DeliverySection section;
  final String customerKey;

  /// Used for the header while loading, or once nothing is left.
  final String customerName;

  const DeliveryCustomerGoatsScreen({
    super.key,
    required this.farmId,
    required this.section,
    required this.customerKey,
    required this.customerName,
  });

  @override
  State<DeliveryCustomerGoatsScreen> createState() =>
      _DeliveryCustomerGoatsScreenState();
}

class _DeliveryCustomerGoatsScreenState
    extends State<DeliveryCustomerGoatsScreen> {
  static final DateFormat _date = DateFormat('d MMM yyyy');

  late final Stream<List<Goat>> _goats =
  GoatService.instance.goatsStream(widget.farmId);
  late final Stream<List<Sale>> _sales =
  widget.section.openSalesStream(widget.farmId);

  /// One live stream per lot booking (kept, so rebuilds do not
  /// re-subscribe).
  final Map<String, Stream<List<SaleGoatDetail>>> _lotGoatStreams = {};

  /// Blocks a second tap on Complete while the selector is opening.
  bool _opening = false;

  DeliverySection get _section => widget.section;

  void _openGoat(Goat goat) {
    Navigator.of(context).push(
      fastRoute(
        OwnPalaiGoatProfileScreen(farmId: widget.farmId, goat: goat),
      ),
    );
  }

  Future<void> _openComplete(SectionCustomer customer) async {
    if (_opening) return;
    _opening = true;

    await Navigator.of(context).push<bool>(
      fastRoute(
        CompleteGoatsSelectorScreen(
          farmId: widget.farmId,
          section: _section,
          customerKey: customer.key,
          customerName: customer.name,
        ),
      ),
    );

    _opening = false;
    // Nothing else to do: the list below is live, so completed goats have
    // already dropped out of it and unselected goats are still here.
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Goat>>(
      stream: _goats,
      builder: (context, goatSnap) {
        return StreamBuilder<List<Sale>>(
          stream: _sales,
          builder: (context, saleSnap) {
            if (goatSnap.hasError || saleSnap.hasError) {
              return _shell(
                title: widget.customerName,
                body: const DeliveryMessage(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  title: 'Unable to load goats',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }
            if (!goatSnap.hasData || !saleSnap.hasData) {
              return _shell(
                title: widget.customerName,
                body: const Center(
                  child:
                  CircularProgressIndicator(color: AppColors.primaryGreen),
                ),
              );
            }

            SectionCustomer? customer;
            for (final c in _section.group(
              sales: saleSnap.data!,
              goats: goatSnap.data!,
            )) {
              if (c.key == widget.customerKey) {
                customer = c;
                break;
              }
            }

            if (customer == null) {
              return _shell(
                title: widget.customerName,
                body: DeliveryMessage(
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.success,
                  title: _section.isWait
                      ? 'No goats waiting'
                      : 'No booked goats',
                  subtitle: _section.isWait
                      ? 'Every goat for this customer has been delivered.'
                      : 'This customer has no booked or held goats now.',
                ),
              );
            }

            return _shell(
              title: customer.name,
              subtitle: customer.mobile.isEmpty ? null : customer.mobile,
              body: _body(customer),
              bottom: _completeBar(customer),
            );
          },
        );
      },
    );
  }

  Widget _shell({
    required String title,
    String? subtitle,
    required Widget body,
    Widget? bottom,
  }) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      bottomNavigationBar: bottom,
      body: SafeArea(
        child: Column(
          children: [
            DeliveryHeader(
              title: title,
              subtitle: subtitle == null
                  ? _section.title
                  : '${_section.title} · $subtitle',
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _body(SectionCustomer customer) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
      children: [
        _summary(customer),
        const SizedBox(height: 12),
        for (var i = 0; i < customer.bookings.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _bookingCard(customer.bookings[i]),
        ],
        const SizedBox(height: 10),
        Text(
          'Tap a goat to see its profile, add photos, or update its '
              'weight and health.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 10.5),
        ),
      ],
    );
  }

  Widget _summary(SectionCustomer customer) {
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: AppTheme.heading(size: 17)),
          Text(label, style: AppTheme.body(size: 9.5)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          stat('${customer.goatCount}',
              _section.isWait ? 'Goats waiting' : 'Goats booked'),
          Container(width: 1, height: 30, color: AppColors.divider),
          stat('${customer.bookings.length}',
              customer.bookings.length == 1 ? 'Booking' : 'Bookings'),
        ],
      ),
    );
  }

  Widget _bookingCard(SectionBooking booking) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LotOriginCard(
            farmId: widget.farmId,
            bookingId: booking.id,
            lotDocIds: LotOriginCard.lotsOf(booking.sale, booking.goats),
            note: booking.isLot &&
                booking.sale.sourceLocation == Sale.sourceSupplier
                ? 'At supplier'
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              'Booked ${_date.format(booking.bookedAt)}',
              style: AppTheme.body(size: 10),
            ),
          ),
          if (booking.isLot)
            _lotRow(booking)
          else
            for (final goat in booking.goats) _goatRow(goat),
        ],
      ),
    );
  }

  /// A lot booking: its goats are not registered, so they are shown as
  /// "Goat 1..N" with the photo, age and weight taken at the sale.
  Widget _lotRow(SectionBooking booking) {
    final atSupplier = booking.sale.sourceLocation == Sale.sourceSupplier;
    final n = booking.goatCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            '$n goat${n == 1 ? '' : 's'} from ${booking.sale.lotDisplayId} · '
                '${atSupplier ? 'still at the supplier' : 'at the farm'}',
            style: AppTheme.heading(size: 12.5),
          ),
        ),
        StreamBuilder<List<SaleGoatDetail>>(
          stream: _lotGoatStreams.putIfAbsent(
            booking.id,
                () => SaleGoatDetailsService.instance
                .streamForSale(widget.farmId, booking.id),
          ),
          builder: (context, snap) {
            if (!snap.hasData && !snap.hasError) {
              return const Padding(
                padding: EdgeInsets.all(10),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final goats = SaleGoatDetailsService.withPlaceholders(
              snap.data ?? const <SaleGoatDetail>[],
              booking.goatCount,
            );
            return Column(
              children: [for (final g in goats) _lotGoatRow(booking, g)],
            );
          },
        ),
      ],
    );
  }

  void _openLotGoat(SectionBooking booking, SaleGoatDetail g) {
    Navigator.of(context).push(
      fastRoute(
        LotGoatProfileScreen(
          farmId: widget.farmId,
          sale: booking.sale,
          index: g.index,
        ),
      ),
    );
  }

  Widget _lotGoatRow(SectionBooking booking, SaleGoatDetail g) {
    final photo = g.photo;
    final details = [
      if (g.weight > 0) '${g.weight.toStringAsFixed(1)} kg',
      if (g.ageMonths > 0) '${g.ageMonths} months',
      if (g.healthStatus.isNotEmpty) g.healthStatus,
    ];
    final missing = [
      if (!g.hasPhoto) 'photo',
      if (g.ageMonths <= 0) 'age',
      if (g.weight <= 0) 'weight',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openLotGoat(booking, g),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: photo != null
                    ? Image.memory(photo, width: 42, height: 42, fit: BoxFit.cover)
                    : Container(
                  width: 42,
                  height: 42,
                  color: _section.color.withValues(alpha: 0.12),
                  child: Icon(Icons.add_a_photo_outlined,
                      size: 18, color: _section.color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.label, style: AppTheme.heading(size: 13.5)),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 10.5),
                      ),
                    if (missing.isNotEmpty)
                      Text(
                        'Tap to add ${missing.join(', ')}',
                        style: AppTheme.body(
                          size: 10.5,
                          color: AppColors.warning,
                          weight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textGrey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goatRow(Goat goat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openGoat(goat),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: goat.photo == null
                    ? null
                    : () => Navigator.of(context).push(
                  fastRoute(FullscreenImageViewer(
                    imageBytes: goat.photo!,
                    title: goat.id,
                  )),
                ),
                child: _avatarBox(goat),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goat.id, style: AppTheme.heading(size: 13.5)),
                    Text(
                      [
                        if (goat.weight > 0)
                          '${goat.weight.toStringAsFixed(1)} kg',
                        if (goat.currentAgeMonths > 0) goat.age,
                        if (goat.breed.trim().isNotEmpty) goat.breed.trim(),
                        goat.healthStatus.trim().isEmpty
                            ? 'Health not recorded'
                            : goat.healthStatus.trim(),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textGrey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarBox(Goat? goat) {
    final photo = goat?.photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: photo != null
          ? Image.memory(photo, width: 42, height: 42, fit: BoxFit.cover)
          : Container(
        width: 42,
        height: 42,
        color: _section.color.withValues(alpha: 0.12),
        child: Icon(GoatIcons.paw, size: 18, color: _section.color),
      ),
    );
  }

  Widget _completeBar(SectionCustomer customer) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: const BoxDecoration(
          color: AppColors.paleGreen,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => _openComplete(customer),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text(
              'Complete',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}