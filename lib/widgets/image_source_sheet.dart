import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/image_service.dart';

enum _PickerSource { camera, gallery }

/// Bottom sheet offering "Take Photo" (camera) and "Choose from Gallery"
/// (device storage) — the same choice used for photo uploads across the
/// app (e.g. the Palai "Before Palai" / "After Palai" goat photos).
///
/// Returns the already-compressed [PickedImage], or `null` if the user
/// cancelled. Can throw [ImageTooLargeException] — callers should wrap
/// the call in a try/catch the same way the Profile photo picker does.
///
/// Pass [isGoatPhoto] = true to use the smaller Palai goat-photo size
/// budget (so two photos — before & after — can both fit comfortably on
/// one Firestore goat document).
Future<PickedImage?> showImageSourceSheet(
  BuildContext context, {
  bool isGoatPhoto = false,
}) async {
  final choice = await showModalBottomSheet<_PickerSource>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primaryGreen),
              title: Text(
                'Take Photo',
                style: AppTheme.body(size: 15, color: AppColors.textDark, weight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(sheetContext, _PickerSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryGreen),
              title: Text(
                'Choose from Gallery',
                style: AppTheme.body(size: 15, color: AppColors.textDark, weight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(sheetContext, _PickerSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (choice == null) return null;

  final maxBytes = isGoatPhoto ? ImageService.goatPhotoMaxStoredBytes : ImageService.maxStoredBytes;
  final maxDim = isGoatPhoto ? ImageService.goatPhotoMaxDimension : ImageService.maxDimension;

  if (choice == _PickerSource.camera) {
    return ImageService.instance.pickFromCamera(maxStoredBytes: maxBytes, maxDimension: maxDim);
  }
  return ImageService.instance.pickFromGallery(maxStoredBytes: maxBytes, maxDimension: maxDim);
}
