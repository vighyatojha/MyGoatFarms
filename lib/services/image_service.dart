import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

/// Thrown when a picked photo can't be brought under the target size even
/// after compression.
class ImageTooLargeException implements Exception {
  final String message;
  ImageTooLargeException(this.message);

  @override
  String toString() => message;
}

/// A photo that has already been resized/compressed and is ready to be
/// stored as a Firestore `Blob`.
class PickedImage {
  final Uint8List bytes;
  final String contentType;
  const PickedImage({required this.bytes, required this.contentType});
}

/// Internal message passed into the background isolate. [compute] only
/// accepts a single argument, so every tunable for a given pick is
/// bundled into this one object.
class _CompressRequest {
  final Uint8List rawBytes;
  final int maxStoredBytes;
  final int maxDimension;
  const _CompressRequest(this.rawBytes, this.maxStoredBytes, this.maxDimension);
}

/// Picks an image from the device camera/gallery and compresses it so it
/// safely fits inside a Firestore document (1 MiB hard limit per doc).
///
/// Flow: Camera or gallery (image_picker) → raw bytes → resize + re-encode
/// (on a background isolate via [compute], so a large phone photo never
/// freezes the UI) → bytes small enough to store directly in Firestore.
///
/// Used by:
///  - The Profile screen's farm-photo picker (default size budget below).
///  - The Palai "Before Palai" / "After Palai" goat photo pickers, via
///    [goatPhotoMaxStoredBytes] / [goatPhotoMaxDimension] — a smaller
///    budget, since a single goat document can carry BOTH photos at once.
class ImageService {
  ImageService._();
  static final ImageService instance = ImageService._();

  final ImagePicker _picker = ImagePicker();

  /// Firestore caps a single document at 1 MiB total. We keep the stored
  /// image well under that so there's always room for the rest of the
  /// farm profile fields alongside it.
  static const int maxStoredBytes = 700 * 1024; // 700 KB
  static const int maxDimension = 512; // px, longest edge

  /// Tighter budget for Palai goat photos: a goat document can hold a
  /// "Before Palai" AND an "After Palai" photo at the same time, so each
  /// one needs to be smaller to keep the whole document under 1 MiB.
  static const int goatPhotoMaxStoredBytes = 350 * 1024; // 350 KB
  static const int goatPhotoMaxDimension = 480; // px, longest edge

  Future<PickedImage?> pickFromGallery({
    int maxStoredBytes = ImageService.maxStoredBytes,
    int maxDimension = ImageService.maxDimension,
  }) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return null;
    final rawBytes = await file.readAsBytes();
    return compute(_compress, _CompressRequest(rawBytes, maxStoredBytes, maxDimension));
  }

  Future<PickedImage?> pickFromCamera({
    int maxStoredBytes = ImageService.maxStoredBytes,
    int maxDimension = ImageService.maxDimension,
  }) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (file == null) return null;
    final rawBytes = await file.readAsBytes();
    return compute(_compress, _CompressRequest(rawBytes, maxStoredBytes, maxDimension));
  }
}

/// Runs on a background isolate (via [compute]) so resizing a full-resolution
/// phone photo never blocks the UI thread.
PickedImage _compress(_CompressRequest req) {
  final decoded = img.decodeImage(req.rawBytes);
  if (decoded == null) {
    throw ImageTooLargeException(
      'That file could not be opened as an image. Please choose a JPG or PNG photo.',
    );
  }

  img.Image resized = decoded;
  if (decoded.width > req.maxDimension || decoded.height > req.maxDimension) {
    final landscape = decoded.width >= decoded.height;
    resized = img.copyResize(
      decoded,
      width: landscape ? req.maxDimension : null,
      height: !landscape ? req.maxDimension : null,
    );
  }

  int quality = 85;
  Uint8List out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));

  // Step the quality down until it fits, without going so low the photo
  // becomes unrecognizable.
  while (out.length > req.maxStoredBytes && quality > 30) {
    quality -= 10;
    out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  if (out.length > req.maxStoredBytes) {
    throw ImageTooLargeException(
      'This photo is too large to save, even after compression. '
      'Please choose a smaller or simpler photo.',
    );
  }

  return PickedImage(bytes: out, contentType: 'image/jpeg');
}
