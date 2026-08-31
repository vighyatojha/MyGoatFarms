import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';

class _TimelineEntry {
  final DateTime date;
  final Uint8List bytes;
  final String label;
  final double? weight;
  final bool deletable;
  final String? photoId;

  const _TimelineEntry({
    required this.date,
    required this.bytes,
    required this.label,
    required this.weight,
    this.deletable = false,
    this.photoId,
  });
}

/// Photos & Growth tab — a real visual timeline: arrival photo, every
/// monthly photo captured since, and (if checked out) the check-out
/// photo, each paired with that entry's weight and its gain over the
/// previous entry.
class GoatPhotosGrowthTab extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const GoatPhotosGrowthTab({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<GoatPhotosGrowthTab> createState() => _GoatPhotosGrowthTabState();
}

class _GoatPhotosGrowthTabState extends State<GoatPhotosGrowthTab> {
  late Stream<List<MonthlyPhoto>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirestoreService.instance.monthlyPhotosStream(
      widget.farmId,
      widget.customerId,
      widget.goat.id,
    );
  }

  Future<void> _addPhoto() async {
    final weightController = TextEditingController(
      text: (widget.goat.currentWeight ?? widget.goat.weightAtCheckIn).toStringAsFixed(1),
    );

    try {
      final picked = await ImageService.instance.pickFromCamera(
        maxStoredBytes: 300 * 1024,
        maxDimension: 720,
      );
      if (picked == null || !mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add this photo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(picked.bytes, height: 140, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg)', isDense: true, border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      final now = DateTime.now();
      await FirestoreService.instance.addMonthlyPhoto(
        widget.farmId,
        widget.customerId,
        widget.goat.id,
        MonthlyPhoto(
          id: '',
          month: DateTime(now.year, now.month),
          image: picked.bytes,
          imageContentType: picked.contentType,
          weightKg: double.tryParse(weightController.text.trim()),
          capturedAt: now,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add photo: $e')),
      );
    }
  }

  Future<void> _deletePhoto(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this photo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirestoreService.instance.deleteMonthlyPhoto(
        widget.farmId,
        widget.customerId,
        widget.goat.id,
        photoId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete photo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MonthlyPhoto>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
        }

        final photos = (snapshot.data ?? []).toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

        final goat = widget.goat;
        final entries = <_TimelineEntry>[
          _TimelineEntry(
            date: goat.farmArrivalDate ?? goat.checkInDate,
            bytes: goat.beforeImage ?? Uint8List(0),
            label: 'Arrival',
            weight: goat.weightAtCheckIn,
          ),
          for (final photo in photos)
            _TimelineEntry(
              date: photo.capturedAt,
              bytes: photo.image,
              label: DateFormat('MMMM yyyy').format(photo.month),
              weight: photo.weightKg,
              deletable: true,
              photoId: photo.id,
            ),
          if (goat.isCheckedOut && goat.afterImage != null)
            _TimelineEntry(
              date: goat.checkOutDate ?? DateTime.now(),
              bytes: goat.afterImage!,
              label: 'Check-Out',
              weight: goat.currentWeight,
            ),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
          children: [
            Row(
              children: [
                Expanded(child: Text('Photos & Growth', style: AppTheme.heading(size: 13))),
                OutlinedButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                  label: const Text('Add Photo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    side: const BorderSide(color: AppColors.primaryGreen),
                    foregroundColor: AppColors.primaryGreen,
                    textStyle: AppTheme.body(size: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < entries.length; i++) _timelineCard(entries[i], i > 0 ? entries[i - 1] : null),
          ],
        );
      },
    );
  }

  Widget _timelineCard(_TimelineEntry entry, _TimelineEntry? previous) {
    final gain = (entry.weight != null && previous?.weight != null) ? entry.weight! - previous!.weight! : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: entry.bytes.isNotEmpty
                ? Image.memory(entry.bytes, width: 84, height: 84, fit: BoxFit.cover)
                : Container(
              width: 84,
              height: 84,
              color: AppColors.lightGreen,
              child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(entry.label, style: AppTheme.heading(size: 13))),
                    if (entry.deletable && entry.photoId != null)
                      GestureDetector(
                        onTap: () => _deletePhoto(entry.photoId!),
                        child: Icon(Icons.delete_outline, size: 17, color: AppColors.textMuted.withOpacity(0.7)),
                      ),
                  ],
                ),
                Text(DateFormat('d MMM yyyy').format(entry.date), style: AppTheme.body(size: 11, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      entry.weight != null ? '${entry.weight!.toStringAsFixed(1)} kg' : 'No weight recorded',
                      style: AppTheme.heading(size: 12.5),
                    ),
                    if (gain != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (gain >= 0 ? AppColors.success : AppColors.error).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg',
                          style: AppTheme.body(size: 10.5, color: gain >= 0 ? AppColors.success : AppColors.error, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}