import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Uploads or changes a trading goat's main photo.
///
/// The photo is stored on the goat document itself
/// (farms/{farmId}/tradingGoats/{goatId} → `photo` / `photoContentType`),
/// the same fields goat registration writes and [Goat.fromDoc] reads, so
/// every list and profile that already shows the goat's photo shows the
/// new one too. Pick the image with `showImageSourceSheet(context,
/// isGoatPhoto: true)` so it is compressed to the goat-photo size budget
/// and the document stays well under Firestore's 1 MB limit.
///
/// Photos taken with a weight entry are kept separately in the goat's
/// weight history, so changing the main photo never removes them.
class GoatPhotoService {
  GoatPhotoService._();

  static final GoatPhotoService instance = GoatPhotoService._();

  static const Duration _timeout = Duration(seconds: 15);

  DocumentReference<Map<String, dynamic>> _goatRef(
      String farmId,
      String goatId,
      ) =>
      FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId)
          .collection('tradingGoats')
          .doc(goatId);

  /// Sets [bytes] as the goat's main photo, replacing any earlier one.
  Future<void> setPhoto({
    required String farmId,
    required String goatId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) {
    return _goatRef(farmId, goatId).update({
      'photo': Blob(bytes),
      'photoContentType': contentType,
      'photoUpdatedAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }
}