import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer who boards goats under the Palai (boarding & care) service.
/// A customer who boards goats under the Palai (boarding & care) service.
class PalaiCustomer {
  final String id;
  final String name;
  final String mobileNumber;
  final String address;
  final String package;
  final DateTime joiningDate;

  /// Amount currently owed by the customer.
  final double pendingAmount;

  /// Amount paid in excess of the customer's outstanding balance.
  ///
  /// Example:
  /// Pending = ₹1,000
  /// Payment = ₹1,500
  /// Pending = ₹0
  /// Advance = ₹500
  final double advanceAmount;

  /// Palai price for this customer (₹).
  final double price;

  PalaiCustomer({
    required this.id,
    required this.name,
    required this.mobileNumber,
    required this.address,
    required this.package,
    required this.joiningDate,
    required this.pendingAmount,
    this.advanceAmount = 0,
    this.price = 0,
  });

  factory PalaiCustomer.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PalaiCustomer(
      id: doc.id,
      name: data['name'] ?? '',
      mobileNumber: data['mobileNumber'] ?? '',
      address: data['address'] ?? '',
      package: data['package'] ?? '',
      joiningDate:
      (data['joiningDate'] as Timestamp?)?.toDate() ??
          DateTime.now(),

      pendingAmount:
      (data['pendingAmount'] ?? 0).toDouble(),

      // Existing customers do not have this field yet.
      // They safely default to ₹0.
      advanceAmount:
      (data['advanceAmount'] ?? 0).toDouble(),

      price:
      (data['price'] ?? 0).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PalaiCustomer && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'mobileNumber': mobileNumber,
      'address': address,
      'package': package,
      'joiningDate': Timestamp.fromDate(joiningDate),

      'pendingAmount': pendingAmount,
      'advanceAmount': advanceAmount,

      'price': price,

      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'name': name,
      'mobileNumber': mobileNumber,
      'address': address,
      'package': package,

      'pendingAmount': pendingAmount,
      'advanceAmount': advanceAmount,

      'price': price,
    };
  }

  PalaiCustomer copyWith({
    String? name,
    String? mobileNumber,
    String? address,
    String? package,
    DateTime? joiningDate,
    double? pendingAmount,
    double? advanceAmount,
    double? price,
  }) {
    return PalaiCustomer(
      id: id,
      name: name ?? this.name,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      address: address ?? this.address,
      package: package ?? this.package,
      joiningDate: joiningDate ?? this.joiningDate,

      pendingAmount:
      pendingAmount ?? this.pendingAmount,

      advanceAmount:
      advanceAmount ?? this.advanceAmount,

      price:
      price ?? this.price,
    );
  }
}

/// A goat that is checked into Palai boarding, belonging to a customer.
///
/// Carries two optional photos:
/// - [beforeImage] — taken at check-in ("Before Palai").
/// - [afterImage] — taken at check-out ("After Palai").
///
/// Images are stored as Firestore [Blob] values directly on the
/// document, so Firebase Storage is not required.
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
  final double pricing; // Palai pricing for this check-in (₹)

  final String notes;

  final bool isCheckedOut;

  /// "Before Palai" photo, taken at check-in.
  final Uint8List? beforeImage;
  final String? beforeImageContentType;

  /// "After Palai" photo, taken at check-out.
  final Uint8List? afterImage;
  final String? afterImageContentType;

  // ------------------------------------------------------------
  // REPORT INFORMATION
  // ------------------------------------------------------------

  /// Report-generation status shown on the goat card.
  ///
  /// Possible values:
  /// - "Not Generated"
  /// - "Progress Report Generated"
  /// - "Final Report Generated"
  final String reportStatus;

  /// Storage value of the most recently generated report.
  ///
  /// Expected values:
  /// - "progress"
  /// - "final"
  final String? lastReportType;

  /// Date and time when the most recent report was generated.
  final DateTime? lastReportDate;

  /// Total number of reports generated for this goat.
  final int reportsCount;

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
    this.pricing = 0,
    required this.notes,
    this.isCheckedOut = false,

    // Images
    this.beforeImage,
    this.beforeImageContentType,
    this.afterImage,
    this.afterImageContentType,

    // Report fields
    this.reportStatus = 'Not Generated',
    this.lastReportType,
    this.lastReportDate,
    this.reportsCount = 0,
  });

  factory PalaiGoat.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
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

      weightAtCheckIn:
      (data['weightAtCheckIn'] ?? 0).toDouble(),

      currentWeight:
      (data['currentWeight'] as num?)?.toDouble(),

      healthStatus:
      data['healthStatus'] ?? 'Healthy',

      checkInDate:
      (data['checkInDate'] as Timestamp?)?.toDate() ??
          DateTime.now(),

      checkOutDate:
      (data['checkOutDate'] as Timestamp?)?.toDate(),

      monthlyPackage:
      data['monthlyPackage'] ?? '',

      pricing:
      (data['pricing'] ?? 0).toDouble(),

      notes:
      data['notes'] ?? '',

      isCheckedOut:
      data['isCheckedOut'] ?? false,

      // --------------------------------------------------------
      // BEFORE IMAGE
      // --------------------------------------------------------
      beforeImage:
      beforeField is Blob
          ? beforeField.bytes
          : null,

      beforeImageContentType:
      data['beforeImageContentType'] as String?,

      // --------------------------------------------------------
      // AFTER IMAGE
      // --------------------------------------------------------
      afterImage:
      afterField is Blob
          ? afterField.bytes
          : null,

      afterImageContentType:
      data['afterImageContentType'] as String?,

      // --------------------------------------------------------
      // REPORT INFORMATION
      // --------------------------------------------------------
      reportStatus:
      data['reportStatus'] as String? ??
          'Not Generated',

      lastReportType:
      data['lastReportType'] as String?,

      lastReportDate:
      (data['lastReportDate'] as Timestamp?)?.toDate(),

      reportsCount:
      (data['reportsCount'] as num?)?.toInt() ?? 0,
    );
  }

  // Compared by [id] so that a goat instance picked from one stream
  // snapshot (e.g. a Dropdown's selected value) still matches the same
  // goat in a *later* snapshot after a write elsewhere updates its data.
  // Without this, DropdownButton<PalaiGoat> throws an assertion error
  // the moment the underlying stream re-emits a fresh list of objects,
  // because Dart compares objects by identity by default.
  @override
  bool operator ==(Object other) => other is PalaiGoat && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Data used when creating a new goat.
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

      'checkOutDate': checkOutDate != null
          ? Timestamp.fromDate(checkOutDate!)
          : null,

      'monthlyPackage': monthlyPackage,
      'pricing': pricing,

      'notes': notes,

      'isCheckedOut': isCheckedOut,

      // --------------------------------------------------------
      // REPORT INFORMATION
      // --------------------------------------------------------
      'reportStatus': reportStatus,
      'lastReportType': lastReportType,
      'lastReportDate': lastReportDate != null
          ? Timestamp.fromDate(lastReportDate!)
          : null,
      'reportsCount': reportsCount,

      'createdAt': FieldValue.serverTimestamp(),
    };

    // ----------------------------------------------------------
    // BEFORE IMAGE
    // ----------------------------------------------------------
    if (beforeImage != null) {
      map['beforeImage'] = Blob(beforeImage!);
      map['beforeImageContentType'] =
          beforeImageContentType ?? 'image/jpeg';
    }

    // ----------------------------------------------------------
    // AFTER IMAGE
    // ----------------------------------------------------------
    if (afterImage != null) {
      map['afterImage'] = Blob(afterImage!);
      map['afterImageContentType'] =
          afterImageContentType ?? 'image/jpeg';
    }

    return map;
  }

  /// Fields that can be updated without recreating the goat.
  ///
  /// This keeps the original [checkInDate] and [createdAt] unchanged.
  Map<String, dynamic> toUpdateMap() {
    final map = <String, dynamic>{
      'customerId': customerId,

      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,

      'weightAtCheckIn': weightAtCheckIn,
      'currentWeight': currentWeight,

      'healthStatus': healthStatus,

      'checkOutDate': checkOutDate != null
          ? Timestamp.fromDate(checkOutDate!)
          : null,

      'monthlyPackage': monthlyPackage,
      'pricing': pricing,

      'notes': notes,

      'isCheckedOut': isCheckedOut,

      // Report information
      'reportStatus': reportStatus,
      'lastReportType': lastReportType,
      'lastReportDate': lastReportDate != null
          ? Timestamp.fromDate(lastReportDate!)
          : null,
      'reportsCount': reportsCount,
    };

    // Before image
    if (beforeImage != null) {
      map['beforeImage'] = Blob(beforeImage!);
      map['beforeImageContentType'] =
          beforeImageContentType ?? 'image/jpeg';
    }

    // After image
    if (afterImage != null) {
      map['afterImage'] = Blob(afterImage!);
      map['afterImageContentType'] =
          afterImageContentType ?? 'image/jpeg';
    }

    return map;
  }

  PalaiGoat copyWith({
    String? customerId,
    String? goatCode,
    String? breed,
    String? gender,
    String? color,
    double? weightAtCheckIn,
    double? currentWeight,
    String? healthStatus,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    String? monthlyPackage,
    double? pricing,
    String? notes,
    bool? isCheckedOut,

    Uint8List? beforeImage,
    String? beforeImageContentType,

    Uint8List? afterImage,
    String? afterImageContentType,

    String? reportStatus,
    String? lastReportType,
    DateTime? lastReportDate,
    int? reportsCount,
  }) {
    return PalaiGoat(
      id: id,

      customerId: customerId ?? this.customerId,

      goatCode: goatCode ?? this.goatCode,
      breed: breed ?? this.breed,
      gender: gender ?? this.gender,
      color: color ?? this.color,

      weightAtCheckIn:
      weightAtCheckIn ?? this.weightAtCheckIn,

      currentWeight:
      currentWeight ?? this.currentWeight,

      healthStatus:
      healthStatus ?? this.healthStatus,

      checkInDate:
      checkInDate ?? this.checkInDate,

      checkOutDate:
      checkOutDate ?? this.checkOutDate,

      monthlyPackage:
      monthlyPackage ?? this.monthlyPackage,

      pricing:
      pricing ?? this.pricing,

      notes:
      notes ?? this.notes,

      isCheckedOut:
      isCheckedOut ?? this.isCheckedOut,

      // Images
      beforeImage:
      beforeImage ?? this.beforeImage,

      beforeImageContentType:
      beforeImageContentType ??
          this.beforeImageContentType,

      afterImage:
      afterImage ?? this.afterImage,

      afterImageContentType:
      afterImageContentType ??
          this.afterImageContentType,

      // Report information
      reportStatus:
      reportStatus ?? this.reportStatus,

      lastReportType:
      lastReportType ?? this.lastReportType,

      lastReportDate:
      lastReportDate ?? this.lastReportDate,

      reportsCount:
      reportsCount ?? this.reportsCount,
    );
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

  factory HealthRecordEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return HealthRecordEntry(
      id: doc.id,

      weight:
      (data['weight'] ?? 0).toDouble(),

      vaccination:
      data['vaccination'] ?? '',

      deworming:
      data['deworming'] ?? '',

      hoofCutting:
      data['hoofCutting'] ?? '',

      medicineGiven:
      data['medicineGiven'] ?? '',

      healthStatus:
      data['healthStatus'] ?? '',

      doctorNotes:
      data['doctorNotes'] ?? '',

      recordedAt:
      (data['recordedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
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

/// A single month's progress photo for a boarded Palai goat, stored the
/// same way as the check-in/check-out photos (raw bytes as a Firestore
/// `Blob`, no Storage bucket required). Lets an owner flip through how a
/// goat has grown/changed month over month while it's boarded.
class MonthlyPhoto {
  final String id;

  /// The month this photo represents, normalised to the 1st of that
  /// month (e.g. 1 Aug 2026) so entries can be sorted/labelled cleanly.
  final DateTime month;

  final Uint8List image;
  final String imageContentType;
  final String notes;
  final DateTime capturedAt;

  MonthlyPhoto({
    required this.id,
    required this.month,
    required this.image,
    this.imageContentType = 'image/jpeg',
    this.notes = '',
    required this.capturedAt,
  });

  factory MonthlyPhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final imageField = data['image'];
    return MonthlyPhoto(
      id: doc.id,
      month: (data['month'] as Timestamp?)?.toDate() ?? DateTime.now(),
      image: imageField is Blob ? imageField.bytes : Uint8List(0),
      imageContentType: data['imageContentType'] ?? 'image/jpeg',
      notes: data['notes'] ?? '',
      capturedAt: (data['capturedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'month': Timestamp.fromDate(DateTime(month.year, month.month, 1)),
      'image': Blob(image),
      'imageContentType': imageContentType,
      'notes': notes,
      'capturedAt': Timestamp.fromDate(capturedAt),
    };
  }
}