import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'bill_settings_model.dart';
import 'health_reminder_settings_model.dart';

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

  /// What gets printed on the Palai check-out bill — see Profile > Bill
  /// Details. Falls back to this farm's own name/address/mobile number
  /// until the owner customizes it.
  final BillSettings billSettings;

  /// Vaccination / Hoof Cutting / Hair Trimming reminder-day cadences —
  /// see Profile > Health Reminder Settings. Single source of truth for
  /// every active goat in this farm, regardless of which customer they
  /// belong to. Replaces the old per-customer "Health Settings" that
  /// used to live on [PalaiCustomer].
  final HealthReminderSettings healthReminderSettings;

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
    BillSettings? billSettings,
    HealthReminderSettings? healthReminderSettings,
  })  : billSettings = billSettings ?? const BillSettings(),
        healthReminderSettings =
            healthReminderSettings ?? HealthReminderSettings.defaults;

  factory FarmModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final imageField = data['profileImage'];
    final farmName = data['farmName'] ?? '';
    final address = data['address'] ?? '';
    final mobileNumber = data['mobileNumber'] ?? '';
    return FarmModel(
      id: doc.id,
      farmName: farmName,
      ownerName: data['ownerName'] ?? '',
      mobileNumber: mobileNumber,
      email: data['email'] ?? '',
      address: address,
      logoUrl: data['logoUrl'] ?? '',
      authUid: data['authUid'] ?? '',
      profileImage: imageField is Blob ? imageField.bytes : null,
      profileImageContentType: data['profileImageContentType'] as String?,
      preferredLanguage: data['preferredLanguage'] as String? ?? 'en',
      billSettings: BillSettings.fromMap(
        data['billSettings'] as Map<String, dynamic>?,
        fallbackName: farmName.toString().trim().isNotEmpty ? farmName : 'My Goat Farms',
        fallbackAddress: address,
        fallbackPhone: mobileNumber,
      ),
      healthReminderSettings: HealthReminderSettings.fromMap(
        data['healthReminderSettings'] as Map<String, dynamic>?,
      ),
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
    // Adding a farm partner is an optional feature (see "Add Farm
    // Partner" on the profile screen) and is intentionally NOT part of
    // the required checklist below. Including it here used to leave the
    // profile permanently stuck at 86% (6/7) for farms that had every
    // required field filled in but no partner added.
    final checks = <bool>[
      farmName.trim().isNotEmpty,
      ownerName.trim().isNotEmpty,
      mobileNumber.trim().isNotEmpty,
      email.trim().isNotEmpty,
      address.trim().isNotEmpty,
      profileImage != null && profileImage!.isNotEmpty,
    ];
    final done = checks.where((c) => c).length;
    return ((done / checks.length) * 100).round();
  }
}