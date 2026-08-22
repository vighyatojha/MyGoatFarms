import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents one structured monthly report for one Palai goat.
///
/// This model is intentionally separate from the old GoatReport /
/// Progress Report system.
///
/// A report always represents ONE calendar month.
///
/// Example:
///   August 2026
///
/// Firestore:
/// palaiCustomers/{customerId}/goats/{goatId}/monthlyReports/{reportId}
class MonthlyReport {
  final String id;
  final String customerId;
  final String goatId;

  /// First day of the reported month.
  ///
  /// Example:
  /// 2026-08-01
  final DateTime month;

  final DateTime generatedAt;

  // ---------------------------------------------------------------------------
  // GOAT SNAPSHOT
  // ---------------------------------------------------------------------------

  final String goatName;
  final String goatCode;
  final String breed;
  final String gender;
  final String color;

  // ---------------------------------------------------------------------------
  // BOARDING
  // ---------------------------------------------------------------------------

  final DateTime checkInDate;
  final DateTime? checkOutDate;

  /// Number of days the goat was present during this month.
  final int boardingDays;

  // ---------------------------------------------------------------------------
  // WEIGHT
  // ---------------------------------------------------------------------------

  final double? startingWeight;
  final double? endingWeight;
  final double? weightChange;

  // ---------------------------------------------------------------------------
  // ACTIVITY COUNTS
  // ---------------------------------------------------------------------------

  final int healthRecordCount;
  final int vaccinationCount;
  final int medicineCount;
  final int hoofCuttingCount;
  final int hairTrimmingCount;
  final int monthlyPhotoCount;

  // ---------------------------------------------------------------------------
  // HEALTH SUMMARY
  // ---------------------------------------------------------------------------

  final String healthStatus;

  // ---------------------------------------------------------------------------
  // REPORT PHOTOS
  // ---------------------------------------------------------------------------

  /// URLs are preferred because MonthlyPhotoRecord already uses Firebase
  /// Storage URLs.
  final List<String> photoUrls;

  // ---------------------------------------------------------------------------
  // NOTES
  // ---------------------------------------------------------------------------

  final String notes;

  const MonthlyReport({
    required this.id,
    required this.customerId,
    required this.goatId,
    required this.month,
    required this.generatedAt,
    required this.goatName,
    required this.goatCode,
    required this.breed,
    required this.gender,
    required this.color,
    required this.checkInDate,
    this.checkOutDate,
    required this.boardingDays,
    this.startingWeight,
    this.endingWeight,
    this.weightChange,
    required this.healthRecordCount,
    required this.vaccinationCount,
    required this.medicineCount,
    required this.hoofCuttingCount,
    required this.hairTrimmingCount,
    required this.monthlyPhotoCount,
    required this.healthStatus,
    this.photoUrls = const [],
    this.notes = '',
  });

  // ---------------------------------------------------------------------------
  // MONTH KEY
  // ---------------------------------------------------------------------------

  String get monthKey {
    return '${month.year}-${month.month.toString().padLeft(2, '0')}';
  }

  String get monthLabel {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[month.month - 1]} ${month.year}';
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------------

  factory MonthlyReport.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    return MonthlyReport(
      id: doc.id,
      customerId: _string(data['customerId']),
      goatId: _string(data['goatId']),
      month: _date(
        data['month'],
        fallback: DateTime.now(),
      ),
      generatedAt: _date(
        data['generatedAt'],
        fallback: DateTime.now(),
      ),
      goatName: _string(data['goatName']),
      goatCode: _string(data['goatCode']),
      breed: _string(data['breed']),
      gender: _string(data['gender']),
      color: _string(data['color']),
      checkInDate: _date(
        data['checkInDate'],
        fallback: DateTime.now(),
      ),
      checkOutDate: _nullableDate(data['checkOutDate']),
      boardingDays: _int(data['boardingDays']),
      startingWeight: _nullableDouble(data['startingWeight']),
      endingWeight: _nullableDouble(data['endingWeight']),
      weightChange: _nullableDouble(data['weightChange']),
      healthRecordCount: _int(data['healthRecordCount']),
      vaccinationCount: _int(data['vaccinationCount']),
      medicineCount: _int(data['medicineCount']),
      hoofCuttingCount: _int(data['hoofCuttingCount']),
      hairTrimmingCount: _int(data['hairTrimmingCount']),
      monthlyPhotoCount: _int(data['monthlyPhotoCount']),
      healthStatus: _string(
        data['healthStatus'],
        fallback: 'Not Available',
      ),
      photoUrls: List<String>.from(
        (data['photoUrls'] as List<dynamic>?) ?? const [],
      ),
      notes: _string(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'goatId': goatId,

      'month': Timestamp.fromDate(month),

      'generatedAt': Timestamp.fromDate(generatedAt),

      'goatName': goatName,
      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,

      'checkInDate': Timestamp.fromDate(checkInDate),

      'checkOutDate': checkOutDate == null
          ? null
          : Timestamp.fromDate(checkOutDate!),

      'boardingDays': boardingDays,

      'startingWeight': startingWeight,
      'endingWeight': endingWeight,
      'weightChange': weightChange,

      'healthRecordCount': healthRecordCount,
      'vaccinationCount': vaccinationCount,
      'medicineCount': medicineCount,
      'hoofCuttingCount': hoofCuttingCount,
      'hairTrimmingCount': hairTrimmingCount,
      'monthlyPhotoCount': monthlyPhotoCount,

      'healthStatus': healthStatus,

      'photoUrls': photoUrls,

      'notes': notes,
    };
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  static String _string(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  static int _int(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _nullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  static DateTime _date(
      dynamic value, {
        required DateTime fallback,
      }) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  static DateTime? _nullableDate(dynamic value) {
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