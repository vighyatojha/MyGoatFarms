import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A single goat registered out of a Trading purchase.
///
/// Stored at:
/// farms/{farmId}/tradingGoats/{goatId}
///
/// Age is stored as:
///   ageMonths      -> age in complete months when recorded
///   ageRecordedAt  -> date when that age was recorded
///
/// The current age is calculated dynamically from those two values.
/// This means the app does not need to update Firestore every month.
class Goat {
  final String id;

  // ---------------------------------------------------------------------
  // DETAILS
  // ---------------------------------------------------------------------

  final String breed;

  /// Age in complete months when the goat's age was recorded.
  final int ageMonthsAtRecord;

  /// Date/time when [ageMonthsAtRecord] was recorded.
  final DateTime ageRecordedAt;

  final double weight;
  final String color;

  /// One of [healthStatusValues].
  final String healthStatus;

  final String notes;

  // ---------------------------------------------------------------------
  // ORIGIN
  // ---------------------------------------------------------------------

  final String purchaseId;
  final DateTime purchaseDate;

  // ---------------------------------------------------------------------
  // STATUS
  // ---------------------------------------------------------------------

  final String currentStatus;

  // ---------------------------------------------------------------------
  // PHOTO
  // ---------------------------------------------------------------------

  final Uint8List? photo;
  final String? photoContentType;

  final DateTime? createdAt;

  // ---------------------------------------------------------------------
  // OWN PALAI
  // ---------------------------------------------------------------------

  final DateTime? movedToOwnPalaiAt;

  // ---------------------------------------------------------------------
  // SALE (Phase 4)
  // ---------------------------------------------------------------------

  /// Links back to farms/{farmId}/sales/{saleId} once this goat has been
  /// included in a sale (any delivery branch, including Transfer to
  /// Palai). Null for goats that have never been sold.
  final String? saleId;

  // ---------------------------------------------------------------------
  // GENDER (Phase 4)
  // ---------------------------------------------------------------------

  /// One of [genderValues], or '' when never recorded.
  ///
  /// Trading's Goat Registration (Phase 3) never captured gender, unlike
  /// the Own Farm and Customer Palai goat models. Rather than reopening
  /// Registration, this is deliberately optional and only ever edited
  /// from the Sell Goat wizard's Step 3 (Selected Goat Details) — see
  /// SaleDraft.genderFor()/setGender(). Once set there it's written back
  /// onto this doc so it isn't asked again next time.
  final String gender;

  const Goat({
    required this.id,
    required this.breed,
    required this.ageMonthsAtRecord,
    required this.ageRecordedAt,
    required this.weight,
    required this.color,
    required this.healthStatus,
    required this.notes,
    required this.purchaseId,
    required this.purchaseDate,
    required this.currentStatus,
    this.photo,
    this.photoContentType,
    this.createdAt,
    this.movedToOwnPalaiAt,
    this.saleId,
    this.gender = '',
  });

  // ---------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------

  static const String statusAvailable = 'Available';
  static const String statusOwnPalai = 'Own Palai';
  static const String statusSold = 'Sold';
  static const String statusBooked = 'Booked';

  /// Branch C (Wait for Delivery) of the Sale flow. This was missing
  /// from the original enum even though the Trading dashboard already
  /// had a "Wait on Delivery" summary card wired up — see
  /// TradingSummary.waitOnDelivery.
  static const String statusWaitOnDelivery = 'Wait on Delivery';

  static const String statusInCustomerPalai = 'In Customer Palai';

  static const List<String> statusValues = [
    statusAvailable,
    statusOwnPalai,
    statusSold,
    statusBooked,
    statusWaitOnDelivery,
    statusInCustomerPalai,
  ];

  static const List<String> genderValues = [
    'Male',
    'Female',
  ];

  static const List<String> healthStatusValues = [
    'Healthy',
    'Under Treatment',
    'Sick',
    'Quarantined',
  ];

  // ---------------------------------------------------------------------
  // CURRENT AGE
  // ---------------------------------------------------------------------

  /// Current age in complete calendar months.
  ///
  /// Example:
  ///
  /// ageMonthsAtRecord = 8
  /// ageRecordedAt = 17 Sep 2026
  ///
  /// 17 Oct 2026 -> 9 months
  /// 17 Nov 2026 -> 10 months
  /// 17 Dec 2026 -> 11 months
  ///
  /// We intentionally calculate calendar months instead of:
  ///
  ///     elapsedDays ~/ 30
  ///
  /// because calendar months are not all 30 days long.
  int get currentAgeMonths {
    final now = DateTime.now();

    if (now.isBefore(ageRecordedAt)) {
      return ageMonthsAtRecord;
    }

    var months =
        (now.year - ageRecordedAt.year) * 12 +
            (now.month - ageRecordedAt.month);

    // The anniversary day has not happened yet this month.
    if (now.day < ageRecordedAt.day) {
      months--;
    }

    if (months < 0) {
      months = 0;
    }

    return ageMonthsAtRecord + months;
  }

  /// Human-readable current age.
  ///
  /// Existing screens can continue using:
  ///
  ///     goat.age
  ///
  /// without needing to change their UI logic.
  String get age {
    return '$currentAgeMonths months';
  }

  /// Numeric current age for calculations.
  int get ageMonths {
    return currentAgeMonths;
  }

  /// Age that was originally entered during registration.
  String get recordedAge {
    return '$ageMonthsAtRecord months';
  }

  // ---------------------------------------------------------------------
  // LEGACY AGE SUPPORT
  // ---------------------------------------------------------------------

  /// Converts the old free-text age format into months.
  ///
  /// Existing records may contain:
  ///
  ///   "8 months"
  ///   "8-10 months"
  ///   "1 year"
  ///   "1 year 2 months"
  ///   "2 years"
  ///
  /// Those records are still supported.
  static int _parseLegacyAge(String value) {
    final text = value.trim().toLowerCase();

    if (text.isEmpty) {
      return 0;
    }

    // Example: "8-10 months"
    final rangeMatch = RegExp(
      r'(\d+)\s*[-–]\s*(\d+)\s*months?',
    ).firstMatch(text);

    if (rangeMatch != null) {
      final first =
          int.tryParse(rangeMatch.group(1) ?? '') ?? 0;

      final second =
          int.tryParse(rangeMatch.group(2) ?? '') ?? first;

      return ((first + second) / 2).round();
    }

    var totalMonths = 0;

    // Example: "2 years"
    final yearsMatch = RegExp(
      r'(\d+)\s*years?',
    ).firstMatch(text);

    if (yearsMatch != null) {
      totalMonths +=
          (int.tryParse(yearsMatch.group(1) ?? '') ?? 0) * 12;
    }

    // Example: "8 months"
    final monthsMatch = RegExp(
      r'(\d+)\s*months?',
    ).firstMatch(text);

    if (monthsMatch != null) {
      totalMonths +=
          int.tryParse(monthsMatch.group(1) ?? '') ?? 0;
    }

    if (totalMonths > 0) {
      return totalMonths;
    }

    // Last fallback for values such as "8".
    final numberMatch = RegExp(
      r'\d+',
    ).firstMatch(text);

    return int.tryParse(
      numberMatch?.group(0) ?? '',
    ) ??
        0;
  }

  // ---------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------

  bool get isAvailable =>
      currentStatus.trim().toLowerCase() ==
          statusAvailable.toLowerCase();

  bool get isOwnPalai =>
      currentStatus.trim().toLowerCase() ==
          statusOwnPalai.toLowerCase();

  bool get isSold =>
      currentStatus.trim().toLowerCase() ==
          statusSold.toLowerCase();

  bool get isBooked =>
      currentStatus.trim().toLowerCase() ==
          statusBooked.toLowerCase();

  bool get isWaitOnDelivery =>
      currentStatus.trim().toLowerCase() ==
          statusWaitOnDelivery.toLowerCase();

  bool get isInCustomerPalai =>
      currentStatus.trim().toLowerCase() ==
          statusInCustomerPalai.toLowerCase();

  /// True for goats Step 1 of the Sale wizard (Task 2.1) should list:
  /// plain farm stock, or a goat already living in Own Palai. This is
  /// the "Own Palai -> Sell" tie-in from PDF section 13 — one query,
  /// two source statuses.
  bool get isSellable => isAvailable || isOwnPalai;

  @override
  bool operator ==(Object other) =>
      other is Goat && other.id == id;

  @override
  int get hashCode => id.hashCode;

  // ---------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------

  factory Goat.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    DateTime? dateFrom(String key) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return null;
    }

    DateTime dateOrNow(String key) {
      return dateFrom(key) ?? DateTime.now();
    }

    double numFrom(String key) {
      final value = data[key];

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(
        value?.toString() ?? '',
      ) ??
          0.0;
    }

    final photoField = data['photo'];

    // -------------------------------------------------------------------
    // AGE
    // -------------------------------------------------------------------
    //
    // New records:
    //
    //   ageMonths
    //   ageRecordedAt
    //
    // Old records:
    //
    //   age: "8 months"
    //
    // For old records, purchaseDate is used as the baseline because the
    // previous model did not save the age-recorded date.

    final rawAgeMonths = data['ageMonths'];

    final parsedAgeMonths = rawAgeMonths is num
        ? rawAgeMonths.toInt()
        : _parseLegacyAge(
      (data['age'] ?? '').toString(),
    );

    final purchaseDate =
    dateOrNow('purchaseDate');

    final ageRecordedAt =
        dateFrom('ageRecordedAt') ??
            purchaseDate;

    return Goat(
      id: doc.id,

      breed:
      (data['breed'] ?? '').toString(),

      ageMonthsAtRecord:
      parsedAgeMonths < 0
          ? 0
          : parsedAgeMonths,

      ageRecordedAt:
      ageRecordedAt,

      weight:
      numFrom('weight'),

      color:
      (data['color'] ?? '').toString(),

      healthStatus:
      (data['healthStatus'] ?? 'Healthy')
          .toString(),

      notes:
      (data['notes'] ?? '').toString(),

      purchaseId:
      (data['purchaseId'] ?? '').toString(),

      purchaseDate:
      purchaseDate,

      currentStatus:
      (data['currentStatus'] ??
          statusAvailable)
          .toString(),

      photo:
      photoField is Blob
          ? photoField.bytes
          : null,

      photoContentType:
      data['photoContentType'] as String?,

      createdAt:
      dateFrom('createdAt'),

      movedToOwnPalaiAt:
      dateFrom('movedToOwnPalaiAt'),

      saleId:
      data['saleId'] as String?,

      gender:
      (data['gender'] ?? '').toString(),
    );
  }

  /// Writes the original recorded age, not the calculated current age.
  ///
  /// We intentionally DO NOT write currentAgeMonths here because it would
  /// become stale again.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'breed': breed.trim(),

      'ageMonths': ageMonthsAtRecord,

      'ageRecordedAt':
      Timestamp.fromDate(ageRecordedAt),

      'weight': weight,

      'color': color.trim(),

      'healthStatus':
      healthStatus,

      'notes':
      notes.trim(),

      'purchaseId':
      purchaseId,

      'purchaseDate':
      Timestamp.fromDate(purchaseDate),

      'currentStatus':
      currentStatus,
    };

    if (photo != null) {
      map['photo'] = Blob(photo!);

      map['photoContentType'] =
          photoContentType ?? 'image/jpeg';
    }

    return map;
  }
}