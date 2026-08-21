import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// CHECK-IN / CHECK-OUT RECORD
/// ============================================================================
///
/// Represents one complete boarding/stay period for a goat.
///
/// This is NOT a "today's check-in" model.
///
/// The record represents the actual lifecycle:
///
///     CHECKED IN
///          ↓
///     BOARDING
///          ↓
///     CHECKED OUT
///
/// A historical record is never deleted or overwritten just because another
/// stay begins later.
///
/// Example:
///
/// Goat G001
///
/// Stay #1
///   Check-in  : 01 Jan 2026
///   Check-out : 31 Jan 2026
///
/// Stay #2
///   Check-in  : 10 Mar 2026
///   Check-out : 25 Mar 2026
///
/// This allows the application to maintain a reliable boarding history.
///
/// Used by:
///
/// 1. Customer Palai
///
/// Not required for:
///
/// 2. Own Farm Palai
///
/// ============================================================================

enum CheckInOutStatus {
  active,
  completed,
  cancelled,
}

class CheckInOutRecord {
  // ==========================================================================
  // IDENTITY
  // ==========================================================================

  final String id;

  /// Goat associated with this stay.
  final String goatId;

  /// Customer associated with this stay.
  ///
  /// For Own Farm goats this can remain empty.
  final String customerId;

  // ==========================================================================
  // CHECK-IN
  // ==========================================================================

  /// Date/time when the goat entered Palai.
  final DateTime checkInDate;

  /// Person who recorded the check-in.
  final String checkedInBy;

  // ==========================================================================
  // CHECK-OUT
  // ==========================================================================

  /// Date/time when the goat left Palai.
  ///
  /// Null while the goat is still boarding.
  final DateTime? checkOutDate;

  /// Person who recorded the check-out.
  final String checkedOutBy;

  // ==========================================================================
  // STATUS
  // ==========================================================================

  final CheckInOutStatus status;

  // ==========================================================================
  // CHECK-IN INFORMATION
  // ==========================================================================

  /// Weight at the time of check-in.
  final double? checkInWeight;

  /// Optional notes about the goat when entering Palai.
  final String checkInNotes;

  /// Health condition observed at check-in.
  final String checkInHealthStatus;

  // ==========================================================================
  // CHECK-OUT INFORMATION
  // ==========================================================================

  /// Weight at the time of check-out.
  final double? checkOutWeight;

  /// Optional notes about the goat when leaving Palai.
  final String checkOutNotes;

  /// Health condition observed at check-out.
  final String checkOutHealthStatus;

  // ==========================================================================
  // BILLING / STAY INFORMATION
  // ==========================================================================

  /// Number of days the goat stayed.
  ///
  /// For an active stay this can be calculated dynamically.
  final int? stayDays;

  /// Optional package name used during this stay.
  ///
  /// Example:
  /// - Basic Palai
  /// - Special Palai
  final String packageName;

  /// Price applicable to this stay.
  final double? packagePrice;

  // ==========================================================================
  // REASON / NOTES
  // ==========================================================================

  /// Reason for checkout.
  ///
  /// Examples:
  /// - Customer collected goat
  /// - Treatment completed
  /// - Goat transferred
  /// - Other
  final String checkOutReason;

  final String notes;

  // ==========================================================================
  // AUDIT
  // ==========================================================================

  final String recordedBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const CheckInOutRecord({
    required this.id,
    required this.goatId,
    this.customerId = '',
    required this.checkInDate,
    this.checkedInBy = '',
    this.checkOutDate,
    this.checkedOutBy = '',
    this.status = CheckInOutStatus.active,
    this.checkInWeight,
    this.checkInNotes = '',
    this.checkInHealthStatus = '',
    this.checkOutWeight,
    this.checkOutNotes = '',
    this.checkOutHealthStatus = '',
    this.stayDays,
    this.packageName = '',
    this.packagePrice,
    this.checkOutReason = '',
    this.notes = '',
    this.recordedBy = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  CheckInOutRecord copyWith({
    String? id,
    String? goatId,
    String? customerId,
    DateTime? checkInDate,
    String? checkedInBy,
    DateTime? checkOutDate,
    bool clearCheckOutDate = false,
    String? checkedOutBy,
    CheckInOutStatus? status,
    double? checkInWeight,
    bool clearCheckInWeight = false,
    String? checkInNotes,
    String? checkInHealthStatus,
    double? checkOutWeight,
    bool clearCheckOutWeight = false,
    String? checkOutNotes,
    String? checkOutHealthStatus,
    int? stayDays,
    bool clearStayDays = false,
    String? packageName,
    double? packagePrice,
    bool clearPackagePrice = false,
    String? checkOutReason,
    String? notes,
    String? recordedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CheckInOutRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      customerId: customerId ?? this.customerId,
      checkInDate: checkInDate ?? this.checkInDate,
      checkedInBy: checkedInBy ?? this.checkedInBy,

      checkOutDate:
      clearCheckOutDate
          ? null
          : (checkOutDate ?? this.checkOutDate),

      checkedOutBy:
      checkedOutBy ?? this.checkedOutBy,

      status:
      status ?? this.status,

      checkInWeight:
      clearCheckInWeight
          ? null
          : (checkInWeight ?? this.checkInWeight),

      checkInNotes:
      checkInNotes ?? this.checkInNotes,

      checkInHealthStatus:
      checkInHealthStatus ??
          this.checkInHealthStatus,

      checkOutWeight:
      clearCheckOutWeight
          ? null
          : (checkOutWeight ?? this.checkOutWeight),

      checkOutNotes:
      checkOutNotes ?? this.checkOutNotes,

      checkOutHealthStatus:
      checkOutHealthStatus ??
          this.checkOutHealthStatus,

      stayDays:
      clearStayDays
          ? null
          : (stayDays ?? this.stayDays),

      packageName:
      packageName ?? this.packageName,

      packagePrice:
      clearPackagePrice
          ? null
          : (packagePrice ?? this.packagePrice),

      checkOutReason:
      checkOutReason ?? this.checkOutReason,

      notes:
      notes ?? this.notes,

      recordedBy:
      recordedBy ?? this.recordedBy,

      createdAt:
      createdAt ?? this.createdAt,

      updatedAt:
      updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // CREATE NEW CHECK-IN
  // ==========================================================================

  factory CheckInOutRecord.createCheckIn({
    required String id,
    required String goatId,
    String customerId = '',
    required DateTime checkInDate,
    String checkedInBy = '',
    double? checkInWeight,
    String checkInNotes = '',
    String checkInHealthStatus = '',
    String packageName = '',
    double? packagePrice,
    String notes = '',
    String recordedBy = '',
  }) {
    final now = DateTime.now();

    return CheckInOutRecord(
      id: id,
      goatId: goatId,
      customerId: customerId,
      checkInDate: checkInDate,
      checkedInBy: checkedInBy,
      status: CheckInOutStatus.active,
      checkInWeight: checkInWeight,
      checkInNotes: checkInNotes,
      checkInHealthStatus: checkInHealthStatus,
      packageName: packageName,
      packagePrice: packagePrice,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // CREATE COMPLETED STAY
  // ==========================================================================

  factory CheckInOutRecord.createCompleted({
    required String id,
    required String goatId,
    String customerId = '',
    required DateTime checkInDate,
    required DateTime checkOutDate,
    String checkedInBy = '',
    String checkedOutBy = '',
    double? checkInWeight,
    String checkInNotes = '',
    String checkInHealthStatus = '',
    double? checkOutWeight,
    String checkOutNotes = '',
    String checkOutHealthStatus = '',
    String packageName = '',
    double? packagePrice,
    String checkOutReason = '',
    String notes = '',
    String recordedBy = '',
  }) {
    final now = DateTime.now();

    final stayDays = _calculateStayDays(
      checkInDate,
      checkOutDate,
    );

    return CheckInOutRecord(
      id: id,
      goatId: goatId,
      customerId: customerId,
      checkInDate: checkInDate,
      checkedInBy: checkedInBy,
      checkOutDate: checkOutDate,
      checkedOutBy: checkedOutBy,
      status: CheckInOutStatus.completed,
      checkInWeight: checkInWeight,
      checkInNotes: checkInNotes,
      checkInHealthStatus: checkInHealthStatus,
      checkOutWeight: checkOutWeight,
      checkOutNotes: checkOutNotes,
      checkOutHealthStatus: checkOutHealthStatus,
      stayDays: stayDays,
      packageName: packageName,
      packagePrice: packagePrice,
      checkOutReason: checkOutReason,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory CheckInOutRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    return CheckInOutRecord(
      id: doc.id,

      goatId: _stringValue(
        data['goatId'],
      ),

      customerId: _stringValue(
        data['customerId'],
      ),

      checkInDate: _dateValue(
        data['checkInDate'] ??
            data['checkIn'],
      ),

      checkedInBy: _stringValue(
        data['checkedInBy'],
      ),

      checkOutDate: _nullableDateValue(
        data['checkOutDate'] ??
            data['checkOut'],
      ),

      checkedOutBy: _stringValue(
        data['checkedOutBy'],
      ),

      status: _statusValue(
        data['status'],
      ),

      checkInWeight: _nullableDoubleValue(
        data['checkInWeight'],
      ),

      checkInNotes: _stringValue(
        data['checkInNotes'],
      ),

      checkInHealthStatus: _stringValue(
        data['checkInHealthStatus'],
      ),

      checkOutWeight: _nullableDoubleValue(
        data['checkOutWeight'],
      ),

      checkOutNotes: _stringValue(
        data['checkOutNotes'],
      ),

      checkOutHealthStatus: _stringValue(
        data['checkOutHealthStatus'],
      ),

      stayDays: _nullableIntValue(
        data['stayDays'],
      ),

      packageName: _stringValue(
        data['packageName'] ??
            data['package'],
      ),

      packagePrice: _nullableDoubleValue(
        data['packagePrice'] ??
            data['price'],
      ),

      checkOutReason: _stringValue(
        data['checkOutReason'],
      ),

      notes: _stringValue(
        data['notes'],
      ),

      recordedBy: _stringValue(
        data['recordedBy'],
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
      'goatId': goatId,

      'customerId': customerId,

      'checkInDate': Timestamp.fromDate(
        checkInDate,
      ),

      'checkedInBy': checkedInBy,

      'checkOutDate':
      checkOutDate == null
          ? null
          : Timestamp.fromDate(
        checkOutDate!,
      ),

      'checkedOutBy': checkedOutBy,

      'status': status.name,

      'checkInWeight': checkInWeight,

      'checkInNotes': checkInNotes,

      'checkInHealthStatus':
      checkInHealthStatus,

      'checkOutWeight': checkOutWeight,

      'checkOutNotes': checkOutNotes,

      'checkOutHealthStatus':
      checkOutHealthStatus,

      'stayDays': stayDays,

      'packageName': packageName,

      'packagePrice': packagePrice,

      'checkOutReason': checkOutReason,

      'notes': notes,

      'recordedBy': recordedBy,

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
  // CHECK-OUT OPERATION
  // ==========================================================================

  /// Returns a new record representing the completed stay.
  ///
  /// We do not mutate the existing object.
  ///
  /// This is important because the model remains immutable.
  CheckInOutRecord checkout({
    required DateTime date,
    String checkedOutBy = '',
    double? weight,
    String checkOutNotes = '',
    String checkOutHealthStatus = '',
    String reason = '',
  }) {
    final calculatedStayDays = _calculateStayDays(
      checkInDate,
      date,
    );

    return copyWith(
      checkOutDate: date,
      checkedOutBy: checkedOutBy,
      status: CheckInOutStatus.completed,
      checkOutWeight: weight,
      checkOutNotes: checkOutNotes,
      checkOutHealthStatus: checkOutHealthStatus,
      stayDays: calculatedStayDays,
      checkOutReason: reason,
      updatedAt: DateTime.now(),
    );
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (goatId.trim().isEmpty) {
      return 'Goat ID is required.';
    }

    if (checkInDate.isAfter(
      checkOutDate ?? DateTime.now(),
    )) {
      return 'Check-in date cannot be after check-out date.';
    }

    if (checkOutDate != null &&
        checkOutDate!.isBefore(checkInDate)) {
      return 'Check-out date cannot be before check-in date.';
    }

    if (checkInWeight != null &&
        checkInWeight! <= 0) {
      return 'Check-in weight must be greater than zero.';
    }

    if (checkOutWeight != null &&
        checkOutWeight! <= 0) {
      return 'Check-out weight must be greater than zero.';
    }

    if (status == CheckInOutStatus.completed &&
        checkOutDate == null) {
      return 'Completed stay must have a check-out date.';
    }

    return null;
  }

  // ==========================================================================
  // STATUS HELPERS
  // ==========================================================================

  bool get isActive {
    return status == CheckInOutStatus.active;
  }

  bool get isCompleted {
    return status == CheckInOutStatus.completed;
  }

  bool get isCancelled {
    return status == CheckInOutStatus.cancelled;
  }

  String get statusLabel {
    switch (status) {
      case CheckInOutStatus.active:
        return 'Currently Boarding';

      case CheckInOutStatus.completed:
        return 'Completed';

      case CheckInOutStatus.cancelled:
        return 'Cancelled';
    }
  }

  // ==========================================================================
  // STAY DURATION
  // ==========================================================================

  /// Calculates the current stay duration.
  ///
  /// For an active stay:
  ///
  ///     check-in → today
  ///
  /// For completed stay:
  ///
  ///     check-in → check-out
  int get calculatedStayDays {
    final endDate =
        checkOutDate ?? DateTime.now();

    return _calculateStayDays(
      checkInDate,
      endDate,
    );
  }

  // ==========================================================================
  // WEIGHT CHANGE
  // ==========================================================================

  double? get weightChange {
    if (checkInWeight == null ||
        checkOutWeight == null) {
      return null;
    }

    return checkOutWeight! -
        checkInWeight!;
  }

  bool get gainedWeight {
    final change = weightChange;

    return change != null &&
        change > 0;
  }

  bool get lostWeight {
    final change = weightChange;

    return change != null &&
        change < 0;
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

  bool get hasCustomer {
    return customerId.trim().isNotEmpty;
  }

  bool get hasCheckOut {
    return checkOutDate != null;
  }

  bool get hasCheckInWeight {
    return checkInWeight != null;
  }

  bool get hasCheckOutWeight {
    return checkOutWeight != null;
  }

  bool get hasPackage {
    return packageName.trim().isNotEmpty;
  }

  bool get hasCheckInNotes {
    return checkInNotes.trim().isNotEmpty;
  }

  bool get hasCheckOutNotes {
    return checkOutNotes.trim().isNotEmpty;
  }

  // ==========================================================================
  // FIRESTORE HELPERS
  // ==========================================================================

  static String _stringValue(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString();

    if (result.trim().isEmpty) {
      return fallback;
    }

    return result;
  }

  static int? _nullableIntValue(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    );
  }

  static double? _nullableDoubleValue(
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

  static CheckInOutStatus _statusValue(
      dynamic value,
      ) {
    if (value == null) {
      return CheckInOutStatus.active;
    }

    switch (value.toString()) {
      case 'active':
        return CheckInOutStatus.active;

      case 'completed':
        return CheckInOutStatus.completed;

      case 'cancelled':
        return CheckInOutStatus.cancelled;

      default:
        return CheckInOutStatus.active;
    }
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
      return DateTime.tryParse(
        value,
      ) ??
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

  static int _calculateStayDays(
      DateTime start,
      DateTime end,
      ) {
    final startDay = DateTime(
      start.year,
      start.month,
      start.day,
    );

    final endDay = DateTime(
      end.year,
      end.month,
      end.day,
    );

    final difference =
        endDay.difference(startDay).inDays;

    // A goat checked in and checked out on the same date
    // still represents one boarding day.
    return difference < 1
        ? 1
        : difference + 1;
  }

  // ==========================================================================
  // DEBUG
  // ==========================================================================

  @override
  String toString() {
    return 'CheckInOutRecord('
        'id: $id, '
        'goatId: $goatId, '
        'customerId: $customerId, '
        'status: ${status.name}, '
        'checkInDate: $checkInDate, '
        'checkOutDate: $checkOutDate'
        ')';
  }
}