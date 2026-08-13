import 'package:cloud_firestore/cloud_firestore.dart';

/// A farm partner, added from the Profile screen's "Add Partner" section.
///
/// The document id under `farms/{farmId}/partners/{partnerId}` is always
/// the partner's own Firebase Auth `uid` (see [FirestoreService.addPartner]
/// and [PartnerAuthService]) — this keeps the model simple and lets
/// Firestore security rules check partner access with a plain `exists()`
/// lookup, no extra query needed.
///
/// Note: the partner's password is only ever used once, to create their
/// Firebase Auth account. It is never written to Firestore.
class PartnerModel {
  final String id;
  final String name;
  final String mobileNumber;
  final String email;
  final String authUid;
  final DateTime? createdAt;

  PartnerModel({
    required this.id,
    required this.name,
    required this.mobileNumber,
    required this.email,
    required this.authUid,
    this.createdAt,
  });

  factory PartnerModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return PartnerModel(
      id: doc.id,
      name: data['name'] ?? '',
      mobileNumber: data['mobileNumber'] ?? '',
      email: data['email'] ?? '',
      authUid: data['authUid'] ?? doc.id,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
