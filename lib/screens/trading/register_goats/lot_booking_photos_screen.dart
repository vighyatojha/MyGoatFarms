import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';
import '../../../services/lot_goat_registration_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../palai/fullscreen_image_viewer.dart';
import 'register_lot_goats_screen.dart';

/// Photos of the goats of a lot booking while they are still at the
/// supplier — they cannot be weighed or registered there, but the customer
/// can already be shown which goats are theirs (e.g. photos the supplier
/// sends).
///
/// When the goats arrive, "Register goats" turns the booking into
/// registered goats; these photos start the goat cards there.
class LotBookingPhotosScreen extends StatefulWidget {
  final String farmId;
  final Sale sale;

  const LotBookingPhotosScreen({
    super.key,
    required this.farmId,
    required this.sale,
  });

  @override
  State<LotBookingPhotosScreen> createState() => _LotBookingPhotosScreenState();
}

class _LotBookingPhotosScreenState extends State<LotBookingPhotosScreen> {
  late final Stream<List<SaleGoatPhoto>> _photos = LotGoatRegistrationService
      .instance
      .photosStream(widget.farmId, widget.sale.id);

  bool _busy = false;

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
      ),
    );
  }

  Future<void> _add() async {
    if (_busy) return;
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null || !mounted) return;
      setState(() => _busy = true);
      await LotGoatRegistrationService.instance.addPhoto(
        farmId: widget.farmId,
        saleId: widget.sale.id,
        bytes: picked.bytes,
        contentType: picked.contentType,
      );
      if (mounted) _snack('Photo uploaded.');
    } on ImageTooLargeException {
      if (mounted) {
        _snack('That photo is too large. Please choose another.', error: true);
      }
    } catch (e) {
      if (mounted) {
        _snack(FirestoreService.instance.describeError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SaleGoatPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await LotGoatRegistrationService.instance.deletePhoto(
        farmId: widget.farmId,
        saleId: widget.sale.id,
        photoId: photo.id,
      );
    } catch (e) {
      if (mounted) {
        _snack(FirestoreService.instance.describeError(e), error: true);
      }
    }
  }

  Future<void> _register() async {
    final done = await Navigator.of(context).push<bool>(
      fastRoute(
        RegisterLotGoatsScreen.forBooking(
          farmId: widget.farmId,
          sale: widget.sale,
        ),
      ),
    );
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final count = sale.lotQuantity;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Goat photos · ${sale.id}',
            style: AppTheme.heading(size: 16)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        icon: _busy
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.add_a_photo_outlined),
        label: const Text('Upload photo'),
      ),
      body: StreamBuilder<List<SaleGoatPhoto>>(
        stream: _photos,
        builder: (context, snap) {
          final photos = snap.data ?? const <SaleGoatPhoto>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${sale.customerName} booked $count goat'
                      '${count == 1 ? '' : 's'} from ${sale.lotDisplayId} while '
                      'they are at the supplier. Upload a photo of each goat now; '
                      'when the goats arrive, tap "Register goats" to add their '
                      'weight and details.',
                  style: AppTheme.body(size: 11.5, color: AppColors.textDark),
                ),
              ),
              const SizedBox(height: 12),
              Text('${photos.length} of $count uploaded',
                  style: AppTheme.heading(size: 13)),
              const SizedBox(height: 8),
              if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Could not load the photos. '
                        '${FirestoreService.instance.describeError(snap.error!)}',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(size: 12, color: AppColors.error),
                  ),
                )
              else if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (photos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No photos yet.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 12)),
                  )
                else
                  GridView.count(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < photos.length; i++)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            fastRoute(FullscreenImageViewer(
                              imageBytes: photos[i].bytes,
                              title: 'Goat ${i + 1}',
                            )),
                          ),
                          onLongPress: () => _delete(photos[i]),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(photos[i].bytes,
                                    fit: BoxFit.cover),
                              ),
                              Positioned(
                                left: 4,
                                top: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Goat ${i + 1}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 9.5)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              if (photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Long-press a photo to remove it.',
                      style: AppTheme.body(size: 10.5)),
                ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _register,
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: const Text('Goats arrived — Register goats'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.darkGreen,
                  side: const BorderSide(color: AppColors.primaryGreen),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}