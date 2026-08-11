/// A single farm's profile, as stored in the `farms` Firestore collection.
///
/// Document ID is a sequential human-readable ID (FRM1, FRM2, ...), not the
/// Firebase Auth UID — `authUid` links back to the account that owns it.
class FarmModel {
  final String farmId;
  final String authUid;
  final String farmName;
  final String ownerName;
  final String mobileNumber;
  final String email;

  const FarmModel({
    required this.farmId,
    required this.authUid,
    required this.farmName,
    required this.ownerName,
    required this.mobileNumber,
    required this.email,
  });

  factory FarmModel.fromFirestore(String documentId, Map<String, dynamic> data) {
    return FarmModel(
      farmId: data['farmId'] as String? ?? documentId,
      authUid: data['authUid'] as String? ?? '',
      farmName: data['farmName'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      mobileNumber: data['mobileNumber'] as String? ?? '',
      email: data['email'] as String? ?? '',
    );
  }

  /// Fields written to Firestore. `createdAt`/`FieldValue.serverTimestamp()`
  /// is added separately by FirestoreService since it isn't a plain value.
  Map<String, dynamic> toFirestore() {
    return {
      'farmId': farmId,
      'authUid': authUid,
      'farmName': farmName,
      'ownerName': ownerName,
      'mobileNumber': mobileNumber,
      'email': email,
    };
  }
}
