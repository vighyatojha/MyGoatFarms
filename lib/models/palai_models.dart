import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================================
// PALAI CUSTOMER
// ============================================================================

/// A customer who boards goats under the Palai boarding & care service.
class PalaiCustomer {
  final String id;
  final String name;
  final String mobileNumber;
  final String address;
  final String package;
  final DateTime joiningDate;

  /// Amount currently owed by the customer.
  final double pendingAmount;

  /// Amount paid in excess of the outstanding balance.
  final double advanceAmount;

  /// Palai price for this customer.
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
      name: data['name']?.toString() ?? '',
      mobileNumber: data['mobileNumber']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      package: data['package']?.toString() ?? '',
      joiningDate:
      (data['joiningDate'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      pendingAmount:
      (data['pendingAmount'] as num?)?.toDouble() ?? 0,
      advanceAmount:
      (data['advanceAmount'] as num?)?.toDouble() ?? 0,
      price:
      (data['price'] as num?)?.toDouble() ?? 0,
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
      pendingAmount: pendingAmount ?? this.pendingAmount,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      price: price ?? this.price,
    );
  }
}

// ============================================================================
// PALAI GOAT
// ============================================================================

/// The single source-of-truth model for a goat in the Palai system.
///
/// This model combines:
///
/// 1. Goat identity / registration information
/// 2. Palai check-in / check-out information
/// 3. Weight information
/// 4. Health information
/// 5. Before / after Palai photos
/// 6. Monthly photos
/// 7. Report information
///
/// All Palai screens should use this class from:
///
///     package:mygoatfarms/models/palai_models.dart
///
/// Do NOT create another PalaiGoat model in palai_goat.dart.
class PalaiGoat {
  // --------------------------------------------------------------------------
  // IDENTITY
  // --------------------------------------------------------------------------

  /// Firestore document ID.
  final String id;

  /// Customer who owns this goat.
  final String customerId;

  /// Goat name.
  ///
  /// This belongs to the newer goat identity structure.
  final String name;

  /// Goat tag / identification number.
  ///
  /// Example: G-1001
  final String tagNumber;

  /// Legacy/display goat code used by existing Palai screens.
  ///
  /// Kept for compatibility with existing code.
  final String goatCode;

  /// Goat breed.
  final String breed;

  /// Goat gender.
  final String gender;

  /// Goat colour.
  final String color;

  /// Optional date of birth.
  final DateTime? dateOfBirth;

  // --------------------------------------------------------------------------
  // WEIGHT
  // --------------------------------------------------------------------------

  /// Weight when the goat entered Palai.
  final double weightAtCheckIn;

  /// Current/latest weight.
  final double? currentWeight;

  // --------------------------------------------------------------------------
  // HEALTH
  // --------------------------------------------------------------------------

  /// Current health status.
  final String healthStatus;

  // --------------------------------------------------------------------------
  // CHECK-IN / CHECK-OUT
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // CHECK-IN / CHECK-OUT
  // --------------------------------------------------------------------------

  /// Date when goat entered Palai.
  final DateTime checkInDate;

  /// Date when goat actually arrived at the farm.
  ///
  /// This is intentionally separate from [checkInDate].
  /// [checkInDate] represents the Palai check-in/registration time,
  /// while this field represents the actual farm arrival date.
  final DateTime? farmArrivalDate;

  /// Date when goat left Palai.
  final DateTime? checkOutDate;



  /// Current operational status.
  ///
  /// Examples:
  /// active
  /// checkedIn
  /// checkedOut
  /// inactive
  ///
  /// Kept in addition to [isCheckedOut] so the newer structure
  /// can use an explicit status field.
  final String status;

  /// Whether this goat has already been checked out.
  final bool isCheckedOut;

  // --------------------------------------------------------------------------
  // PALAI PACKAGE / PRICING
  // --------------------------------------------------------------------------

  /// Monthly Palai package.
  final String monthlyPackage;

  /// Palai price for this goat/check-in.
  final double pricing;

  // --------------------------------------------------------------------------
  // REGISTRATION
  // --------------------------------------------------------------------------

  /// When the goat was registered in the Palai system.
  final DateTime registrationDate;

  /// Last time the goat record was updated.
  final DateTime? updatedAt;

  // --------------------------------------------------------------------------
  // NOTES
  // --------------------------------------------------------------------------

  final String notes;

  // --------------------------------------------------------------------------
  // OPTIONAL IMAGE URL
  // --------------------------------------------------------------------------

  /// Optional URL for a goat image.
  ///
  /// Existing Palai before/after photos remain stored as Firestore Blobs.
  final String? imageUrl;

  // --------------------------------------------------------------------------
  // CHECK-IN / CHECK-OUT IMAGES
  // --------------------------------------------------------------------------

  /// "Before Palai" photo taken during check-in.
  final Uint8List? beforeImage;

  final String? beforeImageContentType;

  /// "After Palai" photo taken during check-out.
  final Uint8List? afterImage;

  final String? afterImageContentType;

  // --------------------------------------------------------------------------
  // REPORT INFORMATION
  // --------------------------------------------------------------------------

  /// Possible values:
  ///
  /// Not Generated
  /// Progress Report Generated
  /// Final Report Generated
  final String reportStatus;

  /// Possible values:
  ///
  /// progress
  /// final
  final String? lastReportType;

  /// Date/time of the latest report.
  final DateTime? lastReportDate;

  /// Total number of generated reports.
  final int reportsCount;



  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  PalaiGoat({
    required this.id,
    required this.customerId,

    // New identity fields
    this.name = '',
    this.tagNumber = '',

    // Existing Palai field
    this.goatCode = '',

    required this.breed,
    required this.gender,

    this.color = '',
    this.dateOfBirth,

    // Weight
    this.weightAtCheckIn = 0,
    this.currentWeight,

    // Health
    this.healthStatus = 'Healthy',

    // Check-in/out
    // Check-in/out
    required this.checkInDate,
    this.farmArrivalDate,
    this.checkOutDate,
    this.status = 'active',
    this.isCheckedOut = false,

    // Package / pricing
    this.monthlyPackage = '',
    this.pricing = 0,

    // Registration
    DateTime? registrationDate,
    this.updatedAt,

    // Other
    this.notes = '',
    this.imageUrl,

    // Images
    this.beforeImage,
    this.beforeImageContentType,
    this.afterImage,
    this.afterImageContentType,

    // Reports
    this.reportStatus = 'Not Generated',
    this.lastReportType,
    this.lastReportDate,
    this.reportsCount = 0,
  }) : registrationDate =
      registrationDate ?? checkInDate;

  // ==========================================================================
  // FIRESTORE
  // ==========================================================================

  factory PalaiGoat.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final beforeField = data['beforeImage'];
    final afterField = data['afterImage'];

    final checkInDate =
        _readDate(data['checkInDate']) ??
            _readDate(data['registrationDate']) ??
            DateTime.now();

    final checkedOut =
    _readBool(data['isCheckedOut']);

    final statusValue =
    _readString(
      data['status'],
      fallback: checkedOut
          ? 'checkedOut'
          : 'checkedIn',
    );

    return PalaiGoat(
      id: doc.id,

      // ----------------------------------------------------------------------
      // IDENTITY
      // ----------------------------------------------------------------------

      customerId:
      _readString(data['customerId']),

      name:
      _readString(data['name']),

      tagNumber:
      _readString(data['tagNumber']),

      goatCode:
      _readString(
        data['goatCode'],
        fallback: _readString(data['tagNumber']),
      ),

      breed:
      _readString(data['breed']),

      gender:
      _readString(data['gender']),

      color:
      _readString(data['color']),

      dateOfBirth:
      _readDate(data['dateOfBirth']),

      // ----------------------------------------------------------------------
      // WEIGHT
      // ----------------------------------------------------------------------

      weightAtCheckIn:
      _readDouble(
        data['weightAtCheckIn'],
      ),

      currentWeight:
      _readNullableDouble(
        data['currentWeight'],
      ),

      // ----------------------------------------------------------------------
      // HEALTH
      // ----------------------------------------------------------------------

      healthStatus:
      _readString(
        data['healthStatus'],
        fallback: 'Healthy',
      ),

      // ----------------------------------------------------------------------
      // CHECK-IN / CHECK-OUT
      // ----------------------------------------------------------------------

      // ----------------------------------------------------------------------
      // CHECK-IN / CHECK-OUT
      // ----------------------------------------------------------------------

      checkInDate:
      checkInDate,

      farmArrivalDate:
      _readDate(data['farmArrivalDate']) ??
          checkInDate,

      checkOutDate:
      _readDate(data['checkOutDate']),

      status:
      statusValue,

      isCheckedOut:
      checkedOut,

      // ----------------------------------------------------------------------
      // PACKAGE / PRICING
      // ----------------------------------------------------------------------

      monthlyPackage:
      _readString(data['monthlyPackage']),

      pricing:
      _readDouble(data['pricing']),

      // ----------------------------------------------------------------------
      // REGISTRATION
      // ----------------------------------------------------------------------

      registrationDate:
      _readDate(
        data['registrationDate'],
      ) ??
          checkInDate,

      updatedAt:
      _readDate(data['updatedAt']),

      // ----------------------------------------------------------------------
      // NOTES
      // ----------------------------------------------------------------------

      notes:
      _readString(data['notes']),

      // ----------------------------------------------------------------------
      // IMAGE URL
      // ----------------------------------------------------------------------

      imageUrl:
      _readNullableString(
        data['imageUrl'],
      ),

      // ----------------------------------------------------------------------
      // BEFORE IMAGE
      // ----------------------------------------------------------------------

      beforeImage:
      beforeField is Blob
          ? beforeField.bytes
          : null,

      beforeImageContentType:
      _readNullableString(
        data['beforeImageContentType'],
      ),

      // ----------------------------------------------------------------------
      // AFTER IMAGE
      // ----------------------------------------------------------------------

      afterImage:
      afterField is Blob
          ? afterField.bytes
          : null,

      afterImageContentType:
      _readNullableString(
        data['afterImageContentType'],
      ),

      // ----------------------------------------------------------------------
      // REPORTS
      // ----------------------------------------------------------------------

      reportStatus:
      _readString(
        data['reportStatus'],
        fallback: 'Not Generated',
      ),

      lastReportType:
      _readNullableString(
        data['lastReportType'],
      ),

      lastReportDate:
      _readDate(data['lastReportDate']),

      reportsCount:
      _readInt(data['reportsCount']),
    );
  }

  /// Creates a goat from a normal map.
  ///
  /// Useful for data that is already loaded from Firestore or
  /// passed between services.
  factory PalaiGoat.fromMap(
      Map<String, dynamic> data, {
        required String id,
      }) {
    final checkInDate =
        _readDate(data['checkInDate']) ??
            _readDate(data['registrationDate']) ??
            DateTime.now();

    final checkedOut =
    _readBool(data['isCheckedOut']);

    return PalaiGoat(
      id: id,

      customerId:
      _readString(data['customerId']),

      name:
      _readString(data['name']),

      tagNumber:
      _readString(data['tagNumber']),

      goatCode:
      _readString(
        data['goatCode'],
        fallback: _readString(data['tagNumber']),
      ),

      breed:
      _readString(data['breed']),

      gender:
      _readString(data['gender']),

      color:
      _readString(data['color']),

      dateOfBirth:
      _readDate(data['dateOfBirth']),

      weightAtCheckIn:
      _readDouble(
        data['weightAtCheckIn'],
      ),

      currentWeight:
      _readNullableDouble(
        data['currentWeight'],
      ),

      healthStatus:
      _readString(
        data['healthStatus'],
        fallback: 'Healthy',
      ),

      checkInDate:
      checkInDate,

      farmArrivalDate:
      _readDate(data['farmArrivalDate']) ??
          checkInDate,

      checkOutDate:
      _readDate(data['checkOutDate']),

      status:
      _readString(
        data['status'],
        fallback: checkedOut
            ? 'checkedOut'
            : 'checkedIn',
      ),

      isCheckedOut:
      checkedOut,

      monthlyPackage:
      _readString(data['monthlyPackage']),

      pricing:
      _readDouble(data['pricing']),

      registrationDate:
      _readDate(
        data['registrationDate'],
      ) ??
          checkInDate,

      updatedAt:
      _readDate(data['updatedAt']),

      notes:
      _readString(data['notes']),

      imageUrl:
      _readNullableString(
        data['imageUrl'],
      ),

      beforeImage:
      data['beforeImage'] is Blob
          ? (data['beforeImage'] as Blob).bytes
          : null,

      beforeImageContentType:
      _readNullableString(
        data['beforeImageContentType'],
      ),

      afterImage:
      data['afterImage'] is Blob
          ? (data['afterImage'] as Blob).bytes
          : null,

      afterImageContentType:
      _readNullableString(
        data['afterImageContentType'],
      ),

      reportStatus:
      _readString(
        data['reportStatus'],
        fallback: 'Not Generated',
      ),

      lastReportType:
      _readNullableString(
        data['lastReportType'],
      ),

      lastReportDate:
      _readDate(data['lastReportDate']),

      reportsCount:
      _readInt(data['reportsCount']),
    );
  }

  // ==========================================================================
  // FIRESTORE MAP
  // ==========================================================================

  /// Complete data map for creating a goat.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'customerId': customerId,

      // Identity
      'name': name,
      'tagNumber': tagNumber,
      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,

      'dateOfBirth':
      dateOfBirth != null
          ? Timestamp.fromDate(dateOfBirth!)
          : null,

      // Weight
      'weightAtCheckIn': weightAtCheckIn,
      'currentWeight': currentWeight,

      // Health
      'healthStatus': healthStatus,

      // Check-in / checkout
      'checkInDate':
      Timestamp.fromDate(checkInDate),

      'farmArrivalDate':
      farmArrivalDate != null
          ? Timestamp.fromDate(farmArrivalDate!)
          : null,

      'checkOutDate':
      checkOutDate != null
          ? Timestamp.fromDate(checkOutDate!)
          : null,

      'status': status,
      'isCheckedOut': isCheckedOut,

      // Package / price
      'monthlyPackage': monthlyPackage,
      'pricing': pricing,

      // Registration
      'registrationDate':
      Timestamp.fromDate(registrationDate),

      'updatedAt':
      updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : null,

      // Other
      'imageUrl': imageUrl,
      'notes': notes,

      // Reports
      'reportStatus': reportStatus,
      'lastReportType': lastReportType,
      'lastReportDate':
      lastReportDate != null
          ? Timestamp.fromDate(lastReportDate!)
          : null,
      'reportsCount': reportsCount,

      'createdAt':
      FieldValue.serverTimestamp(),
    };

    // ------------------------------------------------------------------------
    // BEFORE IMAGE
    // ------------------------------------------------------------------------

    if (beforeImage != null) {
      map['beforeImage'] =
          Blob(beforeImage!);

      map['beforeImageContentType'] =
          beforeImageContentType ??
              'image/jpeg';
    }

    // ------------------------------------------------------------------------
    // AFTER IMAGE
    // ------------------------------------------------------------------------

    if (afterImage != null) {
      map['afterImage'] =
          Blob(afterImage!);

      map['afterImageContentType'] =
          afterImageContentType ??
              'image/jpeg';
    }

    return map;
  }

  /// Data used when updating an existing goat.
  ///
  /// The original check-in and createdAt values are not overwritten.
  Map<String, dynamic> toUpdateMap() {
    final map = <String, dynamic>{
      'customerId': customerId,

      // Identity
      'name': name,
      'tagNumber': tagNumber,
      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,

      'dateOfBirth':
      dateOfBirth != null
          ? Timestamp.fromDate(dateOfBirth!)
          : null,

      // Weight
      'weightAtCheckIn': weightAtCheckIn,
      'currentWeight': currentWeight,

      // Health
      'healthStatus': healthStatus,

      // Checkout
      'checkOutDate':
      checkOutDate != null
          ? Timestamp.fromDate(checkOutDate!)
          : null,

      // Farm arrival
      'farmArrivalDate':
      farmArrivalDate != null
          ? Timestamp.fromDate(farmArrivalDate!)
          : null,

      'status': status,
      'isCheckedOut': isCheckedOut,

      // Package / price
      'monthlyPackage': monthlyPackage,
      'pricing': pricing,

      // Registration / update
      'registrationDate':
      Timestamp.fromDate(registrationDate),

      'updatedAt':
      updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : null,

      // Other
      'imageUrl': imageUrl,
      'notes': notes,

      // Reports
      'reportStatus': reportStatus,
      'lastReportType': lastReportType,
      'lastReportDate':
      lastReportDate != null
          ? Timestamp.fromDate(lastReportDate!)
          : null,
      'reportsCount': reportsCount,
    };

    // Before image
    if (beforeImage != null) {
      map['beforeImage'] =
          Blob(beforeImage!);

      map['beforeImageContentType'] =
          beforeImageContentType ??
              'image/jpeg';
    }

    // After image
    if (afterImage != null) {
      map['afterImage'] =
          Blob(afterImage!);

      map['afterImageContentType'] =
          afterImageContentType ??
              'image/jpeg';
    }

    return map;
  }

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  PalaiGoat copyWith({
    String? customerId,

    String? name,
    String? tagNumber,
    String? goatCode,
    String? breed,
    String? gender,
    String? color,

    DateTime? dateOfBirth,

    double? weightAtCheckIn,
    double? currentWeight,

    String? healthStatus,

    DateTime? checkInDate,
    DateTime? farmArrivalDate,
    DateTime? checkOutDate,

    String? status,
    bool? isCheckedOut,

    String? monthlyPackage,
    double? pricing,

    DateTime? registrationDate,
    DateTime? updatedAt,

    String? notes,
    String? imageUrl,

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

      customerId:
      customerId ?? this.customerId,

      name:
      name ?? this.name,

      tagNumber:
      tagNumber ?? this.tagNumber,

      goatCode:
      goatCode ?? this.goatCode,

      breed:
      breed ?? this.breed,

      gender:
      gender ?? this.gender,

      color:
      color ?? this.color,

      dateOfBirth:
      dateOfBirth ?? this.dateOfBirth,

      weightAtCheckIn:
      weightAtCheckIn ??
          this.weightAtCheckIn,

      currentWeight:
      currentWeight ??
          this.currentWeight,

      healthStatus:
      healthStatus ??
          this.healthStatus,

      checkInDate:
      checkInDate ??
          this.checkInDate,

      checkOutDate:
      checkOutDate ??
          this.checkOutDate,

      status:
      status ?? this.status,

      isCheckedOut:
      isCheckedOut ??
          this.isCheckedOut,

      monthlyPackage:
      monthlyPackage ??
          this.monthlyPackage,

      pricing:
      pricing ?? this.pricing,

      registrationDate:
      registrationDate ??
          this.registrationDate,

      updatedAt:
      updatedAt ??
          this.updatedAt,

      notes:
      notes ?? this.notes,

      imageUrl:
      imageUrl ??
          this.imageUrl,

      beforeImage:
      beforeImage ??
          this.beforeImage,

      beforeImageContentType:
      beforeImageContentType ??
          this.beforeImageContentType,

      afterImage:
      afterImage ??
          this.afterImage,

      afterImageContentType:
      afterImageContentType ??
          this.afterImageContentType,

      reportStatus:
      reportStatus ??
          this.reportStatus,

      lastReportType:
      lastReportType ??
          this.lastReportType,

      lastReportDate:
      lastReportDate ??
          this.lastReportDate,

      reportsCount:
      reportsCount ??
          this.reportsCount,
    );
  }

  // ==========================================================================
  // EQUALITY
  // ==========================================================================

  /// Goats are identified by their Firestore document ID.
  ///
  /// This is important for DropdownButton, selection screens and streams,
  /// because a new Firestore snapshot creates new PalaiGoat instances.
  @override
  bool operator ==(Object other) =>
      other is PalaiGoat &&
          other.id == id;

  @override
  int get hashCode => id.hashCode;

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static String _readString(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    return value.toString();
  }

  static String? _readNullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final result =
    value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  static double _readDouble(
      dynamic value, {
        double fallback = 0,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  static double? _readNullableDouble(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }

  static int _readInt(
      dynamic value, {
        int fallback = 0,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  static bool _readBool(
      dynamic value, {
        bool fallback = false,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is String) {
      return value.toLowerCase() == 'true';
    }

    return fallback;
  }

  static DateTime? _readDate(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}

// ============================================================================
// HEALTH RECORD
// ============================================================================

/// A single health-record entry logged against a Palai goat.
class HealthRecordEntry {
  final String id;

  final double weight;

  final String vaccination;
  final String deworming;
  final String hoofCutting;
  final String medicineGiven;

  final String healthStatus;
  final String doctorNotes;

  // --------------------------------------------------------------------
  // RICHER HEALTH-UPDATE FIELDS (new Health section)
  //
  // These are additive — every record written before this change simply
  // reads back with empty/null values for these fields, so nothing
  // existing breaks. [medicineGiven] and [doctorNotes] above are reused
  // as the "Medicine" and "Notes" fields in the new form rather than
  // duplicated.
  // --------------------------------------------------------------------

  /// Free-text symptoms observed at the time of this update (e.g.
  /// "Slight limp, reduced appetite"). Empty when nothing was noted.
  final String symptoms;

  /// e.g. "Good", "Normal", "Poor" — a quick one-word read on how much
  /// the goat has been eating.
  final String appetite;

  /// e.g. "Normal", "Lethargic", "Active" — a quick one-word read on
  /// the goat's activity level.
  final String activity;

  /// Body temperature in °F, as a free-text field (e.g. "101.5") since
  /// it's often recorded as "Normal" rather than a precise number.
  final String temperature;

  /// The disease or problem identified, if any (e.g. "Foot rot").
  /// Empty when the goat is healthy / nothing was found.
  final String diseaseOrProblem;

  /// Treatment given or planned, separate from [medicineGiven] so a
  /// record can note "Isolated and kept warm" even when no medicine
  /// was administered.
  final String treatment;

  /// When this goat should next be checked, so the Health tab can
  /// surface a reminder. Null when no follow-up was scheduled.
  final DateTime? nextCheckDate;

  /// Optional photo taken at the time of this checkup (e.g. a visible
  /// wound, condition, or general appearance). Stored as a Firestore
  /// Blob, same approach as [MonthlyPhoto] — no Firebase Storage needed.
  final Uint8List? image;
  final String imageContentType;

  final DateTime recordedAt;

  /// Set only once this record has been edited after creation — lets
  /// the Health History timeline show an "edited" indicator instead of
  /// silently rewriting history.
  final DateTime? updatedAt;

  HealthRecordEntry({
    required this.id,
    required this.weight,
    required this.vaccination,
    required this.deworming,
    required this.hoofCutting,
    required this.medicineGiven,
    required this.healthStatus,
    required this.doctorNotes,
    this.symptoms = '',
    this.appetite = '',
    this.activity = '',
    this.temperature = '',
    this.diseaseOrProblem = '',
    this.treatment = '',
    this.nextCheckDate,
    this.image,
    this.imageContentType = 'image/jpeg',
    required this.recordedAt,
    this.updatedAt,
  });

  factory HealthRecordEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final imageField = data['image'];

    return HealthRecordEntry(
      id: doc.id,

      weight:
      (data['weight'] as num?)?.toDouble() ??
          0,

      vaccination:
      data['vaccination']?.toString() ?? '',

      deworming:
      data['deworming']?.toString() ?? '',

      hoofCutting:
      data['hoofCutting']?.toString() ?? '',

      medicineGiven:
      data['medicineGiven']?.toString() ?? '',

      healthStatus:
      data['healthStatus']?.toString() ?? '',

      doctorNotes:
      data['doctorNotes']?.toString() ?? '',

      symptoms:
      data['symptoms']?.toString() ?? '',

      appetite:
      data['appetite']?.toString() ?? '',

      activity:
      data['activity']?.toString() ?? '',

      temperature:
      data['temperature']?.toString() ?? '',

      diseaseOrProblem:
      data['diseaseOrProblem']?.toString() ?? '',

      treatment:
      data['treatment']?.toString() ?? '',

      nextCheckDate:
      (data['nextCheckDate'] as Timestamp?)?.toDate(),

      image:
      imageField is Blob ? imageField.bytes : null,

      imageContentType:
      data['imageContentType']?.toString() ?? 'image/jpeg',

      recordedAt:
      (data['recordedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),

      updatedAt:
      (data['updatedAt'] as Timestamp?)?.toDate(),
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
      'symptoms': symptoms,
      'appetite': appetite,
      'activity': activity,
      'temperature': temperature,
      'diseaseOrProblem': diseaseOrProblem,
      'treatment': treatment,
      if (nextCheckDate != null) 'nextCheckDate': Timestamp.fromDate(nextCheckDate!),
      if (image != null) 'image': Blob(image!),
      'imageContentType': imageContentType,
      'recordedAt':
      Timestamp.fromDate(recordedAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  HealthRecordEntry copyWith({
    double? weight,
    String? vaccination,
    String? deworming,
    String? hoofCutting,
    String? medicineGiven,
    String? healthStatus,
    String? doctorNotes,
    String? symptoms,
    String? appetite,
    String? activity,
    String? temperature,
    String? diseaseOrProblem,
    String? treatment,
    DateTime? nextCheckDate,
    Uint8List? image,
    String? imageContentType,
    DateTime? updatedAt,
  }) {
    return HealthRecordEntry(
      id: id,
      weight: weight ?? this.weight,
      vaccination: vaccination ?? this.vaccination,
      deworming: deworming ?? this.deworming,
      hoofCutting: hoofCutting ?? this.hoofCutting,
      medicineGiven: medicineGiven ?? this.medicineGiven,
      healthStatus: healthStatus ?? this.healthStatus,
      doctorNotes: doctorNotes ?? this.doctorNotes,
      symptoms: symptoms ?? this.symptoms,
      appetite: appetite ?? this.appetite,
      activity: activity ?? this.activity,
      temperature: temperature ?? this.temperature,
      diseaseOrProblem: diseaseOrProblem ?? this.diseaseOrProblem,
      treatment: treatment ?? this.treatment,
      nextCheckDate: nextCheckDate ?? this.nextCheckDate,
      image: image ?? this.image,
      imageContentType: imageContentType ?? this.imageContentType,
      recordedAt: recordedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// MONTHLY PHOTO
// ============================================================================

/// A monthly progress photo for a boarded Palai goat.
///
/// Stored as a Firestore Blob. Firebase Storage is not required.
class MonthlyPhoto {
  final String id;

  /// Month represented by this photo.
  ///
  /// Normalised to the first day of the month.
  final DateTime month;

  final Uint8List image;

  final String imageContentType;

  final String notes;

  /// Goat's weight (in kg) recorded at the time this photo was taken.
  ///
  /// Nullable/optional since older records won't have this value.
  final double? weightKg;

  final DateTime capturedAt;

  MonthlyPhoto({
    required this.id,
    required this.month,
    required this.image,
    this.imageContentType = 'image/jpeg',
    this.notes = '',
    this.weightKg,
    required this.capturedAt,
  });

  factory MonthlyPhoto.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final imageField =
    data['image'];

    final weightField = data['weightKg'];

    return MonthlyPhoto(
      id: doc.id,

      month:
      (data['month'] as Timestamp?)?.toDate() ??
          DateTime.now(),

      image:
      imageField is Blob
          ? imageField.bytes
          : Uint8List(0),

      imageContentType:
      data['imageContentType']?.toString() ??
          'image/jpeg',

      notes:
      data['notes']?.toString() ?? '',

      weightKg:
      weightField is num ? weightField.toDouble() : null,

      capturedAt:
      (data['capturedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'month': Timestamp.fromDate(
        DateTime(
          month.year,
          month.month,
          1,
        ),
      ),
      'image': Blob(image),
      'imageContentType': imageContentType,
      'notes': notes,
      'weightKg': weightKg,
      'capturedAt':
      Timestamp.fromDate(capturedAt),
    };
  }
}