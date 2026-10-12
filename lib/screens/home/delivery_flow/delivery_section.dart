import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/bill_settings_model.dart';
import '../../../models/booking_delivery_group.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_goat_weight_entry.dart';
import '../../../models/sale_model.dart';
import '../../../models/wait_delivery_group.dart';
import '../../../services/booking_delivery_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/goat_photo_service.dart';
import '../../../services/image_service.dart';
import '../../../services/sale_goat_details_service.dart';
import '../../../services/sale_receipt_pdf_service.dart';
import '../../../services/sales_service.dart';
import '../../../services/wait_delivery_service.dart';
import '../../../utils/pdf_download.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/lot_origin_card.dart';
import '../../trading/sale_receipt_screen.dart';

/// The two dashboard sections of the delivery flow:
///
///   WAIT ON DELIVERY / BOOKING & HOLDING
///     → customers → customer profile → section entry
///     → select goats (CompleteGoatsSelectorScreen)
///     → checkout: ONE card with every selected goat (photo + weight),
///       the bookings and one calculation → Complete Sale
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
// GOAT UPDATES — one photo per goat + the weight typed at completion
// =============================================================================

/// One goat's weight to save when the sale is completed.
///
/// [key] is `g:<goatId>` for a registered goat, or `l:<saleId>:<index>`
/// for "Goat N" of a lot booking.
class DeliveryGoatWeight {
  final String key;
  final bool isLot;
  final String goatId;
  final String saleId;
  final int index;
  final String lotDisplayId;

  /// Weight typed on the complete screen (its pickup weight).
  final double weight;

  /// Newest weight already on record. When [weight] is the same, nothing
  /// new is written.
  final double lastWeight;

  const DeliveryGoatWeight.registered({
    required this.goatId,
    required this.saleId,
    required this.weight,
    required this.lastWeight,
  })  : key = 'g:$goatId',
        isLot = false,
        index = 0,
        lotDisplayId = '';

  DeliveryGoatWeight.lot({
    required this.saleId,
    required this.index,
    required this.lotDisplayId,
    required this.weight,
    required this.lastWeight,
  })  : key = 'l:$saleId:$index',
        isLot = true,
        goatId = '';

  bool get weightChanged =>
      weight > 0 && ((weight - lastWeight) * 1000).round() != 0;
}

/// Holds the photos picked on the complete screen until Complete Sale,
/// then saves them — with each goat's new weight — onto the goats
/// ([save]). Nothing is written before that, so backing out of the
/// screen changes nothing.
///
///  * Registered goat: the weight becomes a new weight-history entry
///    (same as Weight & health on the goat profile, with the new photo
///    attached); the photo also becomes the goat's main photo.
///  * Lot goat ("Goat N"): saved on the lot goat's record (same as its
///    profile).
class DeliveryGoatUpdates extends ChangeNotifier {
  final Map<String, PickedImage> _photos = <String, PickedImage>{};

  /// New photo picked for [key] (see [DeliveryGoatWeight.key]), if any.
  PickedImage? photoFor(String key) => _photos[key];

  /// Opens the camera / gallery sheet and keeps the picked photo for
  /// [key].
  Future<void> pickPhoto(BuildContext context, String key) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return;
      _photos[key] = picked;
      notifyListeners();
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

  /// Saves every new photo and every changed weight in [goats]. Throws on
  /// the first failure (the sale is then not completed). What was saved
  /// is dropped from this holder, so a retry never saves it twice.
  Future<void> save(String farmId, List<DeliveryGoatWeight> goats) async {
    final now = DateTime.now();

    for (final g in goats) {
      final photo = _photos[g.key];

      if (g.isLot) {
        if (photo != null) {
          await SaleGoatDetailsService.instance.setPhoto(
            farmId: farmId,
            saleId: g.saleId,
            index: g.index,
            lotDisplayId: g.lotDisplayId,
            bytes: photo.bytes,
            contentType: photo.contentType,
          );
        }
        if (g.weightChanged) {
          await SaleGoatDetailsService.instance.updateWeight(
            farmId: farmId,
            saleId: g.saleId,
            index: g.index,
            lotDisplayId: g.lotDisplayId,
            weight: g.weight,
            date: now,
          );
        }
      } else {
        if (g.weightChanged) {
          await GoatService.instance.addWeightEntry(
            farmId: farmId,
            goatId: g.goatId,
            entry: GoatWeightEntry(
              id: '',
              weight: g.weight,
              date: now,
              photo: photo?.bytes,
              photoContentType: photo?.contentType,
              notes: 'Weighed at delivery (Sale ${g.saleId})',
            ),
          );
        }
        if (photo != null) {
          await GoatPhotoService.instance.setPhoto(
            farmId: farmId,
            goatId: g.goatId,
            bytes: photo.bytes,
            contentType: photo.contentType,
          );
        }
      }

      _photos.remove(g.key);
    }
    notifyListeners();
  }
}

/// The goat's photo with one button: Upload when it has none, Update when
/// it has one. A new photo is kept in [updates] until Complete Sale.
class DeliveryGoatPhoto extends StatelessWidget {
  final DeliveryGoatUpdates updates;
  final String photoKey;
  final Uint8List? currentPhoto;
  final Color color;
  final bool enabled;

  const DeliveryGoatPhoto({
    super.key,
    required this.updates,
    required this.photoKey,
    required this.currentPhoto,
    required this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final newPhoto = updates.photoFor(photoKey)?.bytes;
        final shown = newPhoto ?? currentPhoto;
        final hasPhoto = shown != null;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: shown != null
                  ? Image.memory(shown, width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                width: 48,
                height: 48,
                color: color.withValues(alpha: 0.10),
                child: Icon(GoatIcons.paw, size: 18, color: color),
              ),
            ),
            const SizedBox(height: 3),
            InkWell(
              onTap: enabled
                  ? () => updates.pickPhoto(context, photoKey)
                  : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasPhoto
                          ? Icons.photo_camera_outlined
                          : Icons.add_a_photo_outlined,
                      size: 12,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      newPhoto != null
                          ? 'New'
                          : hasPhoto
                          ? 'Update'
                          : 'Upload',
                      style: AppTheme.body(
                        size: 10,
                        color: newPhoto != null
                            ? AppColors.success
                            : AppColors.primaryGreen,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
    final lotLabels = <String, String>{};
    for (final id in widget.saleIds) {
      final sale = await SalesService.instance.getSale(widget.farmId, id);
      if (sale == null) continue;
      sales.add(sale);
      if (sale.isLotSale) {
        final lot = await LotOriginCard.lotFor(widget.farmId, sale.lotDocId);
        lotLabels[sale.id] = LotIdText.label(lot, sale.lotDocId);
      }
    }
    return _ReceiptData(
      sales: sales,
      billSettings: farm?.billSettings ?? const BillSettings(),
      logo: farm?.profileImage,
      lotLabels: lotLabels,
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
      lotLabel: d.lotLabels[sale.id],
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
      lotLabel: d.lotLabels[sale.id],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt · Booking ${sale.id}',
                      style: AppTheme.heading(size: 13),
                    ),
                    if (d.lotLabels[sale.id] != null)
                      Text(
                        d.lotLabels[sale.id]!,
                        style: AppTheme.body(size: 10.5),
                      ),
                  ],
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

  /// "LOT-0008 (Raju)" per lot sale, by sale ID.
  final Map<String, String> lotLabels;

  const _ReceiptData({
    required this.sales,
    required this.billSettings,
    required this.logo,
    this.lotLabels = const {},
  });
}

// =============================================================================
// LATEST RECORDED WEIGHTS — what the pickup-weight fields start from
// =============================================================================

/// The newest weight on record for the goats of [booking], so a weight
/// updated on a goat's profile (Weight & health) is what the complete
/// screen starts from:
///
///  * a registered goat → its latest weight-history entry, or the weight
///    recorded on the goat when it has none (key: the goat ID);
///  * a lot booking → each of Goat 1..N's saved weights
///    (key: `lot:<saleId>:<index>`).
Future<Map<String, double>> latestRecordedWeights(
    String farmId,
    SectionBooking booking,
    ) async {
  final out = <String, double>{};

  if (booking.isLot) {
    // Read fresh (not the session cache), so a weight just updated on the
    // lot goat's profile is included.
    final saved = await SaleGoatDetailsService.instance
        .streamForSale(farmId, booking.id)
        .first;

    for (final g in saved) {
      if (g.index <= booking.goatCount && g.weight > 0) {
        out['lot:${booking.id}:${g.index}'] = g.weight;
      }
    }
    return out;
  }

  for (final goat in booking.goats) {
    out[goat.id] = await latestGoatWeight(farmId, goat);
  }
  return out;
}

/// A registered goat's newest weight: its latest weight-history entry,
/// or the weight recorded on the goat when it has none.
Future<double> latestGoatWeight(String farmId, Goat goat) async {
  final history = await GoatService.instance
      .weightHistoryStream(farmId: farmId, goatId: goat.id)
      .first;
  return history.isEmpty ? goat.weight : history.last.weight;
}