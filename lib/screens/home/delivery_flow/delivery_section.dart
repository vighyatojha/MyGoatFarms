import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/bill_settings_model.dart';
import '../../../models/booking_delivery_group.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../models/wait_delivery_group.dart';
import '../../../services/booking_delivery_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_photo_service.dart';
import '../../../services/image_service.dart';
import '../../../services/sale_goat_details_service.dart';
import '../../../services/sale_receipt_pdf_service.dart';
import '../../../services/sales_service.dart';
import '../../../services/wait_delivery_service.dart';
import '../../../utils/pdf_download.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../trading/sale_receipt_screen.dart';

/// The two dashboard sections of the delivery flow:
///
///   WAIT ON DELIVERY / BOOKING & HOLDING
///     → customers → customer profile → section entry
///     → select goats (CompleteGoatsSelectorScreen)
///     → checkout: photo + age per goat ([DeliveryGoatUpdatesCard]),
///       then the section's calculation cards → Complete Sale
///     → receipts: view / download / share ([showDeliveryReceiptsSheet])
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

  IconData get icon =>
      isWait ? Icons.local_shipping_outlined : Icons.event_available_outlined;

  /// Same colours the Trading dashboard uses for these two cards.
  Color get color => isWait ? AppColors.stockTeal : Colors.deepPurple;

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
// =============================================================================
// GOAT UPDATES — one photo + age per goat, on the checkout screen
// =============================================================================

/// What will be saved for one goat when the sale is completed.
class _GoatUpdate {
  _GoatUpdate.registered({
    required this.saleId,
    required this.goatId,
    required this.originalAge,
  })  : isLot = false,
        index = 0,
        lotDisplayId = '';

  _GoatUpdate.lot({
    required this.saleId,
    required this.index,
    required this.lotDisplayId,
    required this.originalAge,
  })  : isLot = true,
        goatId = '';

  final bool isLot;
  final String saleId;

  /// Registered goat ID (empty for a lot goat).
  final String goatId;

  /// "Goat N" number inside a lot booking (0 for a registered goat).
  final int index;
  final String lotDisplayId;

  /// Age in months the goat has on record (0 = not recorded). Moved to
  /// the new age once it is saved.
  int originalAge;

  late final TextEditingController age = TextEditingController(
    text: originalAge > 0 ? '$originalAge' : '',
  );

  /// New photo picked on this screen, not saved yet.
  PickedImage? photo;

  String get label => isLot ? 'Goat $index ($lotDisplayId)' : goatId;

  /// The typed age when it is a change, null when nothing to save.
  int? get changedAge {
    final n = int.tryParse(age.text.trim());
    if (n == null || n == originalAge) return null;
    return n;
  }

  bool get hasChanges => photo != null || changedAge != null;
}

/// Holds the photos and ages typed on the checkout screen until Complete
/// Sale, then saves them onto the goats ([save]). Nothing is written
/// before that, so backing out of the checkout changes nothing.
///
/// Registered goats are saved with [GoatPhotoService] (the goat's main
/// photo and age, same as the goat profile). A lot booking's goats
/// ("Goat 1..N") are saved with [SaleGoatDetailsService] (same as the lot
/// goat profile).
class DeliveryGoatUpdates extends ChangeNotifier {
  final Map<String, _GoatUpdate> _byKey = <String, _GoatUpdate>{};

  _GoatUpdate _registered(String saleId, Goat goat) {
    return _byKey.putIfAbsent(
      'g:${goat.id}',
          () => _GoatUpdate.registered(
        saleId: saleId,
        goatId: goat.id,
        originalAge: goat.currentAgeMonths,
      ),
    );
  }

  _GoatUpdate _lot(Sale sale, SaleGoatDetail goat) {
    return _byKey.putIfAbsent(
      'l:${sale.id}:${goat.index}',
          () => _GoatUpdate.lot(
        saleId: sale.id,
        index: goat.index,
        lotDisplayId: sale.lotDisplayId,
        originalAge: goat.ageMonths,
      ),
    );
  }

  void _setPhoto(_GoatUpdate update, PickedImage photo) {
    update.photo = photo;
    notifyListeners();
  }

  void _ageChanged() => notifyListeners();

  Iterable<_GoatUpdate> _inSales(Set<String> saleIds) =>
      _byKey.values.where((u) => saleIds.contains(u.saleId));

  /// Null when every age typed for [saleIds] is valid; otherwise what to
  /// fix.
  String? validate(Set<String> saleIds) {
    for (final u in _inSales(saleIds)) {
      final text = u.age.text.trim();
      if (text.isEmpty) continue;
      final n = int.tryParse(text);
      if (n == null || n < 0 || n > 240) {
        return 'Enter the age of ${u.label} in whole months (0 to 240).';
      }
    }
    return null;
  }

  /// Saves every changed photo and age of the goats in [saleIds]. Throws
  /// on the first failure (the sale is then not completed).
  Future<void> save(String farmId, Set<String> saleIds) async {
    for (final u in _inSales(saleIds).toList()) {
      if (!u.hasChanges) continue;
      final photo = u.photo;
      final age = u.changedAge;

      if (u.isLot) {
        if (photo != null) {
          await SaleGoatDetailsService.instance.setPhoto(
            farmId: farmId,
            saleId: u.saleId,
            index: u.index,
            lotDisplayId: u.lotDisplayId,
            bytes: photo.bytes,
            contentType: photo.contentType,
          );
        }
        if (age != null) {
          await SaleGoatDetailsService.instance.setAgeMonths(
            farmId: farmId,
            saleId: u.saleId,
            index: u.index,
            lotDisplayId: u.lotDisplayId,
            months: age,
          );
        }
      } else {
        if (photo != null) {
          await GoatPhotoService.instance.setPhoto(
            farmId: farmId,
            goatId: u.goatId,
            bytes: photo.bytes,
            contentType: photo.contentType,
          );
        }
        if (age != null) {
          await GoatPhotoService.instance.setAgeMonths(
            farmId: farmId,
            goatId: u.goatId,
            months: age,
          );
        }
      }

      // Saved: a second Complete must not save it again.
      u.photo = null;
      if (age != null) u.originalAge = age;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final u in _byKey.values) {
      u.age.dispose();
    }
    _byKey.clear();
    super.dispose();
  }
}

/// "Update photo & age for each goat": one card per goat of [bookings],
/// with the goat's photo (Upload when there is none, Update when there
/// is) and its age in months. Changes are held in [updates] and saved
/// when the sale is completed.
class DeliveryGoatUpdatesCard extends StatefulWidget {
  final String farmId;
  final List<SectionBooking> bookings;
  final DeliveryGoatUpdates updates;
  final Color color;
  final bool enabled;

  const DeliveryGoatUpdatesCard({
    super.key,
    required this.farmId,
    required this.bookings,
    required this.updates,
    required this.color,
    this.enabled = true,
  });

  @override
  State<DeliveryGoatUpdatesCard> createState() =>
      _DeliveryGoatUpdatesCardState();
}

class _DeliveryGoatUpdatesCardState extends State<DeliveryGoatUpdatesCard> {
  /// One live stream per lot booking, kept so rebuilds do not
  /// re-subscribe.
  final Map<String, Stream<List<SaleGoatDetail>>> _lotStreams = {};

  Future<void> _pickPhoto(_GoatUpdate update) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null || !mounted) return;
      widget.updates._setPhoto(update, picked);
    } on ImageTooLargeException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not get the photo. Please try again.'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final goatCount =
    widget.bookings.fold<int>(0, (sum, b) => sum + b.goatCount);

    return ListenableBuilder(
      listenable: widget.updates,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(goatCount),
          for (final b in widget.bookings)
            if (b.isLot)
              _lotGoats(b)
            else
              for (final g in b.goats)
                _goatCard(
                  update: widget.updates._registered(b.id, g),
                  title: g.id,
                  subtitle: [
                    if (g.breed.trim().isNotEmpty) g.breed.trim(),
                    'Booking ${b.id}',
                  ].join(' · '),
                  currentPhoto: g.photo,
                ),
        ],
      ),
    );
  }

  Widget _header(int goatCount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: AppTheme.card(radius: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update photo & age for each goat',
                    style: AppTheme.heading(size: 13.5)),
                const SizedBox(height: 2),
                Text(
                  '$goatCount goat${goatCount == 1 ? '' : 's'} · '
                      'saved when you complete the sale',
                  style: AppTheme.body(size: 10.5),
                ),
              ],
            ),
          ),
          Icon(Icons.photo_camera_outlined, color: widget.color, size: 22),
        ],
      ),
    );
  }

  Widget _lotGoats(SectionBooking booking) {
    return StreamBuilder<List<SaleGoatDetail>>(
      stream: _lotStreams.putIfAbsent(
        booking.id,
            () => SaleGoatDetailsService.instance
            .streamForSale(widget.farmId, booking.id),
      ),
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
          return const Padding(
            padding: EdgeInsets.all(12),
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
        ).where((g) => g.index <= booking.goatCount);

        return Column(
          children: [
            for (final g in goats)
              _goatCard(
                update: widget.updates._lot(booking.sale, g),
                title: g.label,
                subtitle:
                '${booking.sale.lotDisplayId} · Booking ${booking.id}',
                currentPhoto: g.hasPhoto ? g.photo : null,
              ),
          ],
        );
      },
    );
  }

  Widget _goatCard({
    required _GoatUpdate update,
    required String title,
    required String subtitle,
    required Uint8List? currentPhoto,
  }) {
    final newPhoto = update.photo?.bytes;
    final shown = newPhoto ?? currentPhoto;
    final hasPhoto = currentPhoto != null || newPhoto != null;

    final photoNote = newPhoto != null
        ? 'New photo · saved on Complete Sale'
        : currentPhoto != null
        ? 'Current photo'
        : 'No photo yet';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: shown != null
                    ? Image.memory(shown,
                    width: 54, height: 54, fit: BoxFit.cover)
                    : Container(
                  width: 54,
                  height: 54,
                  color: widget.color.withValues(alpha: 0.10),
                  child: Icon(GoatIcons.paw,
                      size: 20, color: widget.color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heading(size: 13.5)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 10.5)),
                    const SizedBox(height: 2),
                    Text(
                      photoNote,
                      style: AppTheme.body(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: newPhoto != null
                            ? AppColors.success
                            : currentPhoto != null
                            ? AppColors.textGrey
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.enabled ? () => _pickPhoto(update) : null,
                icon: Icon(
                  hasPhoto
                      ? Icons.photo_camera_outlined
                      : Icons.add_a_photo_outlined,
                  size: 17,
                ),
                label: Text(hasPhoto ? 'Update' : 'Upload'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.divider),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current age', style: AppTheme.body(size: 10.5)),
                    Text(
                      update.originalAge > 0
                          ? '${update.originalAge} months'
                          : 'Not recorded',
                      style: AppTheme.heading(size: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: AppColors.textGrey),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: update.age,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: (_) => widget.updates._ageChanged(),
                  style: AppTheme.heading(size: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Age (months)',
                    labelStyle:
                    AppTheme.body(size: 11, color: AppColors.textGrey),
                    prefixIcon: const Icon(Icons.cake_outlined, size: 18),
                    prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// RECEIPTS — after Complete Sale
// =============================================================================

/// Shown after a sale is completed: one row per delivered booking with
/// View (the receipt screen), Download (the phone's "Save as" screen) and
/// Share.
Future<void> showDeliveryReceiptsSheet(
    BuildContext context, {
      required String farmId,
      required List<String> saleIds,
    }) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _DeliveryReceiptsSheet(farmId: farmId, saleIds: saleIds),
  );
}

class _DeliveryReceiptsSheet extends StatefulWidget {
  final String farmId;
  final List<String> saleIds;

  const _DeliveryReceiptsSheet({required this.farmId, required this.saleIds});

  @override
  State<_DeliveryReceiptsSheet> createState() => _DeliveryReceiptsSheetState();
}

class _DeliveryReceiptsSheetState extends State<_DeliveryReceiptsSheet> {
  late final Future<_ReceiptData> _data = _load();

  /// Sale ID of the receipt being generated (buttons locked meanwhile).
  String? _busyId;

  /// Last result line per sale ("Saved: …", or an error).
  final Map<String, String> _notes = {};
  final Set<String> _errors = {};

  Future<_ReceiptData> _load() async {
    final farm = await FirestoreService.instance.getFarmById(widget.farmId);
    final sales = <Sale>[];
    for (final id in widget.saleIds) {
      final sale = await SalesService.instance.getSale(widget.farmId, id);
      if (sale != null) sales.add(sale);
    }
    return _ReceiptData(
      sales: sales,
      billSettings: farm?.billSettings ?? const BillSettings(),
      logo: farm?.profileImage,
    );
  }

  Future<void> _run(String saleId, Future<String?> Function() action) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = saleId;
      _notes.remove(saleId);
      _errors.remove(saleId);
    });
    try {
      final note = await action();
      if (!mounted) return;
      setState(() {
        if (note != null) _notes[saleId] = note;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notes[saleId] = e is PlatformException
            ? (e.message ?? 'Unable to create the receipt.')
            : 'Unable to create the receipt. '
            '${FirestoreService.instance.describeError(e)}';
        _errors.add(saleId);
      });
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _view(Sale sale) {
    Navigator.of(context).push(
      fastRoute(SaleReceiptScreen(farmId: widget.farmId, saleId: sale.id)),
    );
  }

  Future<void> _download(Sale sale, _ReceiptData d) => _run(sale.id, () async {
    final result = await SaleReceiptPdfService.instance.saveAs(
      sale: sale,
      billSettings: d.billSettings,
      farmLogo: d.logo,
    );
    switch (result.status) {
      case PdfSaveStatus.saved:
        return 'Saved: ${result.fileName}';
      case PdfSaveStatus.cancelled:
      case PdfSaveStatus.shared:
        return null;
    }
  });

  Future<void> _share(Sale sale, _ReceiptData d) => _run(sale.id, () async {
    await SaleReceiptPdfService.instance.share(
      sale: sale,
      billSettings: d.billSettings,
      farmLogo: d.logo,
    );
    return null;
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sale completed', style: AppTheme.heading(size: 17)),
                    Text(
                      widget.saleIds.length == 1
                          ? 'Your receipt is ready.'
                          : '${widget.saleIds.length} receipts are ready.',
                      style: AppTheme.body(size: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: FutureBuilder<_ReceiptData>(
              future: _data,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Could not load the receipts. Open them later from '
                          'the customer\'s Purchase history.',
                      style: AppTheme.body(size: 12, color: AppColors.error),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  );
                }
                final d = snap.data!;
                return ListView(
                  shrinkWrap: true,
                  children: [for (final sale in d.sales) _receiptRow(sale, d)],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _busyId != null
                  ? null
                  : () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(Sale sale, _ReceiptData d) {
    final busy = _busyId == sale.id;
    final locked = _busyId != null;
    final note = _notes[sale.id];
    final goats = sale.goatCount;

    Widget action(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: OutlinedButton(
          onPressed: locked ? null : onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 9),
            side: const BorderSide(color: AppColors.primaryGreen),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.primaryGreen),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textDark,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Receipt · Booking ${sale.id}',
                  style: AppTheme.heading(size: 13),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text('$goats goat${goats == 1 ? '' : 's'}',
                    style: AppTheme.body(size: 10.5)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              action(Icons.visibility_outlined, 'View', () => _view(sale)),
              const SizedBox(width: 8),
              action(Icons.download_outlined, 'Download',
                      () => _download(sale, d)),
              const SizedBox(width: 8),
              action(Icons.share_outlined, 'Share', () => _share(sale, d)),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: AppTheme.body(
                  size: 10.5,
                  color: _errors.contains(sale.id)
                      ? AppColors.error
                      : AppColors.success,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReceiptData {
  final List<Sale> sales;
  final BillSettings billSettings;
  final Uint8List? logo;

  const _ReceiptData({
    required this.sales,
    required this.billSettings,
    required this.logo,
  });
}