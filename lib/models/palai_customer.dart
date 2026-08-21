import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// PALAI CUSTOMER
/// ============================================================================
///
/// Represents a customer whose goats are kept under the Customer Palai
/// boarding/care service.
///
/// IMPORTANT:
/// - This is the NEW Palai architecture model.
/// - It is independent of the old PalaiCustomer model.
/// - Do not delete the old model yet.
/// - We will remove the old model after the new Palai system is complete
///   and tested.
///
/// Customer
///    │
///    ├── Customer details
///    ├── Palai settings
///    ├── Goats
///    ├── Billing
///    ├── Payments
///    └── Reports
///
/// ============================================================================

class PalaiCustomer {
  final String id;

  // --------------------------------------------------------------------------
  // Customer Information
  // --------------------------------------------------------------------------

  final String name;
  final String mobileNumber;
  final String alternateMobileNumber;
  final String address;

  // --------------------------------------------------------------------------
  // Palai Information
  // --------------------------------------------------------------------------

  /// Example:
  /// - Basic Palai
  /// - Special Palai
  /// - Monthly Palai
  final String packageName;

  final DateTime joiningDate;

  /// Optional date when the customer's Palai service ended.
  final DateTime? leavingDate;

  /// Whether the customer is currently using the Palai service.
  final bool isActive;

  // --------------------------------------------------------------------------
  // Financial Summary
  // --------------------------------------------------------------------------

  /// Current amount that the customer still has to pay.
  ///
  /// This is a summary value.
  /// The actual payment history will live separately.
  final double pendingAmount;

  /// Amount paid in advance by the customer.
  final double advanceAmount;

  // --------------------------------------------------------------------------
  // Goat Summary
  // --------------------------------------------------------------------------

  /// Number of active goats currently registered under this customer.
  ///
  /// This is kept as a denormalized summary for fast UI display.
  final int totalGoats;

  // --------------------------------------------------------------------------
  // Additional Information
  // --------------------------------------------------------------------------

  final String notes;

  /// Optional customer profile image.
  final String? profilePhotoUrl;

  // --------------------------------------------------------------------------
  // Audit Information
  // --------------------------------------------------------------------------

  final DateTime createdAt;
  final DateTime updatedAt;

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const PalaiCustomer({
    required this.id,
    required this.name,
    required this.mobileNumber,
    this.alternateMobileNumber = '',
    this.address = '',
    required this.packageName,
    required this.joiningDate,
    this.leavingDate,
    this.isActive = true,
    this.pendingAmount = 0,
    this.advanceAmount = 0,
    this.totalGoats = 0,
    this.notes = '',
    this.profilePhotoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  PalaiCustomer copyWith({
    String? id,
    String? name,
    String? mobileNumber,
    String? alternateMobileNumber,
    String? address,
    String? packageName,
    DateTime? joiningDate,
    DateTime? leavingDate,
    bool clearLeavingDate = false,
    bool? isActive,
    double? pendingAmount,
    double? advanceAmount,
    int? totalGoats,
    String? notes,
    String? profilePhotoUrl,
    bool clearProfilePhoto = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PalaiCustomer(
      id: id ?? this.id,
      name: name ?? this.name,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      alternateMobileNumber:
      alternateMobileNumber ?? this.alternateMobileNumber,
      address: address ?? this.address,
      packageName: packageName ?? this.packageName,
      joiningDate: joiningDate ?? this.joiningDate,
      leavingDate:
      clearLeavingDate ? null : (leavingDate ?? this.leavingDate),
      isActive: isActive ?? this.isActive,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      totalGoats: totalGoats ?? this.totalGoats,
      notes: notes ?? this.notes,
      profilePhotoUrl:
      clearProfilePhoto
          ? null
          : (profilePhotoUrl ?? this.profilePhotoUrl),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory PalaiCustomer.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    return PalaiCustomer(
      id: doc.id,

      name: _stringValue(
        data['name'],
      ),

      mobileNumber: _stringValue(
        data['mobileNumber'] ?? data['phone'],
      ),

      alternateMobileNumber: _stringValue(
        data['alternateMobileNumber'],
      ),

      address: _stringValue(
        data['address'],
      ),

      packageName: _stringValue(
        data['packageName'] ?? data['package'],
      ),

      joiningDate: _dateValue(
        data['joiningDate'],
      ),

      leavingDate: _nullableDateValue(
        data['leavingDate'],
      ),

      isActive: _boolValue(
        data['isActive'],
        defaultValue: true,
      ),

      pendingAmount: _doubleValue(
        data['pendingAmount'],
      ),

      advanceAmount: _doubleValue(
        data['advanceAmount'],
      ),

      totalGoats: _intValue(
        data['totalGoats'],
      ),

      notes: _stringValue(
        data['notes'],
      ),

      profilePhotoUrl: _nullableStringValue(
        data['profilePhotoUrl'],
      ),

      createdAt: _dateValue(
        data['createdAt'],
      ),

      updatedAt: _dateValue(
        data['updatedAt'],
      ),
    );
  }

  // ==========================================================================
  // MODEL -> FIRESTORE
  // ==========================================================================

  Map<String, dynamic> toMap({
    bool useServerTimestamps = false,
  }) {
    return {
      'name': name,
      'mobileNumber': mobileNumber,
      'alternateMobileNumber': alternateMobileNumber,
      'address': address,
      'packageName': packageName,

      'joiningDate': Timestamp.fromDate(
        joiningDate,
      ),

      'leavingDate': leavingDate == null
          ? null
          : Timestamp.fromDate(
        leavingDate!,
      ),

      'isActive': isActive,

      'pendingAmount': pendingAmount,
      'advanceAmount': advanceAmount,
      'totalGoats': totalGoats,

      'notes': notes,
      'profilePhotoUrl': profilePhotoUrl,

      if (useServerTimestamps)
        'createdAt': FieldValue.serverTimestamp()
      else
        'createdAt': Timestamp.fromDate(
          createdAt,
        ),

      if (useServerTimestamps)
        'updatedAt': FieldValue.serverTimestamp()
      else
        'updatedAt': Timestamp.fromDate(
          updatedAt,
        ),
    };
  }

  // ==========================================================================
  // EMPTY / NEW CUSTOMER
  // ==========================================================================

  factory PalaiCustomer.empty({
    required String id,
  }) {
    final now = DateTime.now();

    return PalaiCustomer(
      id: id,
      name: '',
      mobileNumber: '',
      alternateMobileNumber: '',
      address: '',
      packageName: '',
      joiningDate: now,
      leavingDate: null,
      isActive: true,
      pendingAmount: 0,
      advanceAmount: 0,
      totalGoats: 0,
      notes: '',
      profilePhotoUrl: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

  String get displayName {
    if (name.trim().isEmpty) {
      return 'Unnamed Customer';
    }

    return name.trim();
  }

  String get displayPackage {
    if (packageName.trim().isEmpty) {
      return 'No package';
    }

    return packageName.trim();
  }

  String get paymentStatus {
    if (pendingAmount > 0) {
      return 'Pending';
    }

    if (advanceAmount > 0) {
      return 'Advance';
    }

    return 'Paid';
  }

  bool get hasPendingPayment {
    return pendingAmount > 0;
  }

  bool get hasAdvance {
    return advanceAmount > 0;
  }

  bool get hasGoats {
    return totalGoats > 0;
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (name.trim().isEmpty) {
      return 'Customer name is required.';
    }

    if (mobileNumber.trim().isEmpty) {
      return 'Mobile number is required.';
    }

    if (packageName.trim().isEmpty) {
      return 'Palai package is required.';
    }

    if (pendingAmount < 0) {
      return 'Pending amount cannot be negative.';
    }

    if (advanceAmount < 0) {
      return 'Advance amount cannot be negative.';
    }

    if (totalGoats < 0) {
      return 'Total goats cannot be negative.';
    }

    return null;
  }

  // ==========================================================================
  // PRIVATE PARSING HELPERS
  // ==========================================================================

  static String _stringValue(
      dynamic value,
      ) {
    if (value == null) {
      return '';
    }

    return value.toString();
  }

  static String? _nullableStringValue(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  static double _doubleValue(
      dynamic value,
      ) {
    if (value == null) {
      return 0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        0;
  }

  static int _intValue(
      dynamic value,
      ) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    ) ??
        0;
  }

  static bool _boolValue(
      dynamic value, {
        required bool defaultValue,
      }) {
    if (value == null) {
      return defaultValue;
    }

    if (value is bool) {
      return value;
    }

    if (value is String) {
      return value.toLowerCase() == 'true';
    }

    return defaultValue;
  }

  static DateTime _dateValue(
      dynamic value,
      ) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value) ??
          DateTime.now();
    }

    return DateTime.now();
  }

  static DateTime? _nullableDateValue(
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

  // ==========================================================================
  // DEBUG / LOGGING
  // ==========================================================================

  @override
  String toString() {
    return 'PalaiCustomer('
        'id: $id, '
        'name: $name, '
        'mobileNumber: $mobileNumber, '
        'packageName: $packageName, '
        'totalGoats: $totalGoats, '
        'pendingAmount: $pendingAmount, '
        'advanceAmount: $advanceAmount, '
        'isActive: $isActive'
        ')';
  }
}