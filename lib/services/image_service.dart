import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

/// Thrown when a picked photo can't be brought under Firestore's document
/// size limit even after compression.
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

/// Picks an image from the device gallery/camera and compresses it so it
/// safely fits inside a Firestore document (1 MiB hard limit per doc).
///
/// Flow: Mobile storage → image_picker → raw bytes → resize + re-encode
/// (on a background isolate via [compute], so a large phone photo never
/// freezes the UI) → bytes small enough to store directly in Firestore.
class ImageService {
  ImageService._();
  static final ImageService instance = ImageService._();

  final ImagePicker _picker = ImagePicker();

  /// Firestore caps a single document at 1 MiB total. We keep the stored
  /// image well under that so there's always room for the rest of the
  /// farm profile fields alongside it.
  static const int maxStoredBytes = 700 * 1024; // 700 KB
  static const int maxDimension = 512; // px, longest edge

  Future<PickedImage?> pickFromGallery() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return null;
    final rawBytes = await file.readAsBytes();
    return compute(_compress, rawBytes);
  }

  Future<PickedImage?> pickFromCamera() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (file == null) return null;
    final rawBytes = await file.readAsBytes();
    return compute(_compress, rawBytes);
  }
}

/// Runs on a background isolate (via [compute]) so resizing a full-resolution
/// phone photo never blocks the UI thread.
PickedImage _compress(Uint8List rawBytes) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    throw ImageTooLargeException(
      'That file could not be opened as an image. Please choose a JPG or PNG photo.',
    );
  }

  img.Image resized = decoded;
  if (decoded.width > ImageService.maxDimension || decoded.height > ImageService.maxDimension) {
    final landscape = decoded.width >= decoded.height;
    resized = img.copyResize(
      decoded,
      width: landscape ? ImageService.maxDimension : null,
      height: !landscape ? ImageService.maxDimension : null,
    );
  }

  int quality = 85;
  Uint8List out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));

  // Step the quality down until it fits, without going so low the photo
  // becomes unrecognizable.
  while (out.length > ImageService.maxStoredBytes && quality > 30) {
    quality -= 10;
    out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  if (out.length > ImageService.maxStoredBytes) {
    throw ImageTooLargeException(
      'This photo is too large to save, even after compression. '
      'Please choose a smaller or simpler photo.',
    );
  }

  return PickedImage(bytes: out, contentType: 'image/jpeg');
}
