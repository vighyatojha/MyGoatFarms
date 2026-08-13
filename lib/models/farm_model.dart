import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class FarmModel {
  final String id;
  final String farmName;
  final String ownerName;
  final String mobileNumber;
  final String email;
  final String address;
  final String logoUrl; // legacy field, kept for backward compatibility
  final String authUid;

  /// The farm's photo/logo, stored as raw bytes directly on this document
  /// (Firestore `Blob`) — no Storage bucket, no public URL required.
  final Uint8List? profileImage;
  final String? profileImageContentType;

  /// 'en' | 'hi' | 'gu'. Lets the chosen app language follow this farm
  /// profile across devices.
  final String preferredLanguage;

  FarmModel({
    required this.id,
    required this.farmName,
    required this.ownerName,
    required this.mobileNumber,
    required this.email,
    required this.address,
    required this.logoUrl,
    required this.authUid,
    this.profileImage,
    this.profileImageContentType,
    this.preferredLanguage = 'en',
  });

  factory FarmModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final imageField = data['profileImage'];
    return FarmModel(
      id: doc.id,
      farmName: data['farmName'] ?? '',
      ownerName: data['ownerName'] ?? '',
      mobileNumber: data['mobileNumber'] ?? '',
      email: data['email'] ?? '',
      address: data['address'] ?? '',
      logoUrl: data['logoUrl'] ?? '',
      authUid: data['authUid'] ?? '',
      profileImage: imageField is Blob ? imageField.bytes : null,
      profileImageContentType: data['profileImageContentType'] as String?,
      preferredLanguage: data['preferredLanguage'] as String? ?? 'en',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'farmName': farmName,
      'ownerName': ownerName,
      'mobileNumber': mobileNumber,
      'email': email,
      'address': address,
      'logoUrl': logoUrl,
      'authUid': authUid,
    };
  }

  /// How complete the profile is, 0–100.
  ///
  /// Partner count lives in its own sub-collection so it's passed in
  /// separately rather than read off this model. Used to drive both the
  /// Home-screen completion popup and the progress bar on Profile.
  int completionPercent({required int partnerCount}) {
    final checks = <bool>[
      farmName.trim().isNotEmpty,
      ownerName.trim().isNotEmpty,
      mobileNumber.trim().isNotEmpty,
      email.trim().isNotEmpty,
      address.trim().isNotEmpty,
      profileImage != null && profileImage!.isNotEmpty,
      partnerCount > 0,
    ];
    final done = checks.where((c) => c).length;
    return ((done / checks.length) * 100).round();
  }
}
