import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer who boards goats under the Palai (boarding & care) service.
class PalaiCustomer {
  final String id;
  final String name;
  final String mobileNumber;
  final String address;
  final String package; // e.g. "Special Palai", "Basic Palai"
  final DateTime joiningDate;
  final double pendingAmount;

  PalaiCustomer({
    required this.id,
    required this.name,
    required this.mobileNumber,
    required this.address,
    required this.package,
    required this.joiningDate,
    required this.pendingAmount,
  });

  factory PalaiCustomer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return PalaiCustomer(
      id: doc.id,
      name: data['name'] ?? '',
      mobileNumber: data['mobileNumber'] ?? '',
      address: data['address'] ?? '',
      package: data['package'] ?? '',
      joiningDate: (data['joiningDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendingAmount: (data['pendingAmount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'mobileNumber': mobileNumber,
      'address': address,
      'package': package,
      'joiningDate': Timestamp.fromDate(joiningDate),
      'pendingAmount': pendingAmount,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

/// A goat that is checked into Palai boarding, belonging to a customer.
///
/// Carries two optional photos, stored as raw bytes directly on the
/// document (Firestore `Blob`s) the same way the farm profile photo is
/// stored — no Storage bucket required:
///   - [beforeImage] — taken at check-in ("Before Palai").
///   - [afterImage]  — taken at check-out ("After Palai").
/// Each is compressed to a tighter budget than the farm profile photo
/// (see `ImageService.goatPhotoMaxStoredBytes`) since both can live on
/// the same ~1 MiB document at once.
class PalaiGoat {
  final String id;
  final String customerId;
  final String goatCode; // e.g. G-1001
  final String breed;
  final String gender;
  final String color;
  final double weightAtCheckIn;
  final double? currentWeight;
  final String healthStatus;
  final DateTime checkInDate;
  final DateTime? checkOutDate;
  final String monthlyPackage;
  final String notes;
  final bool isCheckedOut;

  /// "Before Palai" photo, taken at check-in time.
  final Uint8List? beforeImage;
  final String? beforeImageContentType;

  /// "After Palai" photo, taken at check-out time.
  final Uint8List? afterImage;
  final String? afterImageContentType;

  PalaiGoat({
    required this.id,
    required this.customerId,
    required this.goatCode,
    required this.breed,
    required this.gender,
    required this.color,
    required this.weightAtCheckIn,
    this.currentWeight,
    required this.healthStatus,
    required this.checkInDate,
    this.checkOutDate,
    required this.monthlyPackage,
    required this.notes,
    this.isCheckedOut = false,
    this.beforeImage,
    this.beforeImageContentType,
    this.afterImage,
    this.afterImageContentType,
  });

  factory PalaiGoat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final beforeField = data['beforeImage'];
    final afterField = data['afterImage'];
    return PalaiGoat(
      id: doc.id,
      customerId: data['customerId'] ?? '',
      goatCode: data['goatCode'] ?? '',
      breed: data['breed'] ?? '',
      gender: data['gender'] ?? '',
      color: data['color'] ?? '',
      weightAtCheckIn: (data['weightAtCheckIn'] ?? 0).toDouble(),
      currentWeight: (data['currentWeight'] as num?)?.toDouble(),
      healthStatus: data['healthStatus'] ?? 'Healthy',
      checkInDate: (data['checkInDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      checkOutDate: (data['checkOutDate'] as Timestamp?)?.toDate(),
      monthlyPackage: data['monthlyPackage'] ?? '',
      notes: data['notes'] ?? '',
      isCheckedOut: data['isCheckedOut'] ?? false,
      beforeImage: beforeField is Blob ? beforeField.bytes : null,
      beforeImageContentType: data['beforeImageContentType'] as String?,
      afterImage: afterField is Blob ? afterField.bytes : null,
      afterImageContentType: data['afterImageContentType'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'customerId': customerId,
      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,
      'weightAtCheckIn': weightAtCheckIn,
      'currentWeight': currentWeight,
      'healthStatus': healthStatus,
      'checkInDate': Timestamp.fromDate(checkInDate),
      'checkOutDate': checkOutDate != null ? Timestamp.fromDate(checkOutDate!) : null,
      'monthlyPackage': monthlyPackage,
      'notes': notes,
      'isCheckedOut': isCheckedOut,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (beforeImage != null) {
      map['beforeImage'] = Blob(beforeImage!);
      map['beforeImageContentType'] = beforeImageContentType ?? 'image/jpeg';
    }
    if (afterImage != null) {
      map['afterImage'] = Blob(afterImage!);
      map['afterImageContentType'] = afterImageContentType ?? 'image/jpeg';
    }
    return map;
  }
}

/// A single health-record entry logged against a Palai goat over time.
class HealthRecordEntry {
  final String id;
  final double weight;
  final String vaccination;
  final String deworming;
  final String hoofCutting;
  final String medicineGiven;
  final String healthStatus;
  final String doctorNotes;
  final DateTime recordedAt;

  HealthRecordEntry({
    required this.id,
    required this.weight,
    required this.vaccination,
    required this.deworming,
    required this.hoofCutting,
    required this.medicineGiven,
    required this.healthStatus,
    required this.doctorNotes,
    required this.recordedAt,
  });

  factory HealthRecordEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return HealthRecordEntry(
      id: doc.id,
      weight: (data['weight'] ?? 0).toDouble(),
      vaccination: data['vaccination'] ?? '',
      deworming: data['deworming'] ?? '',
      hoofCutting: data['hoofCutting'] ?? '',
      medicineGiven: data['medicineGiven'] ?? '',
      healthStatus: data['healthStatus'] ?? '',
      doctorNotes: data['doctorNotes'] ?? '',
      recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'weight': weight,
      'vaccination': vaccination,
      'deworming': deworming,
      'hoofCutting': hoofCutting,
      'medicineGiven': medicineGiven,
      'healthStatus': healthStatus,
      'doctorNotes': doctorNotes,
      'recordedAt': Timestamp.fromDate(recordedAt),
    };
  }
}
