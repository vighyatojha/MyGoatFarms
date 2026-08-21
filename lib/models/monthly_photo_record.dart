import 'package:cloud_firestore/cloud_firestore.dart';

/// A photo record associated with a customer's goat.
///
/// Photos are grouped by the month in which they were taken.
/// Stored under:
/// palaiCustomers/{customerId}/goats/{goatId}/monthlyPhotos/{photoId}
class MonthlyPhotoRecord {
  final String id;
  final String goatId;

  /// The date on which the photo was taken.
  final DateTime photoDate;

  /// Firebase Storage URL of the photo.
  final String photoUrl;

  /// Optional description/caption.
  final String caption;

  /// Four-digit year used for monthly grouping.
  final int monthYear;

  /// Month number: 1–12.
  final int month;

  /// When the record was created.
  final DateTime recordedAt;

  const MonthlyPhotoRecord({
    required this.id,
    required this.goatId,
    required this.photoDate,
    required this.photoUrl,
    this.caption = '',
    required this.monthYear,
    required this.month,
    required this.recordedAt,
  });

  // ===========================================================================
  // COPY
  // ===========================================================================

  MonthlyPhotoRecord copyWith({
    String? id,
    String? goatId,
    DateTime? photoDate,
    String? photoUrl,
    String? caption,
    int? monthYear,
    int? month,
    DateTime? recordedAt,
  }) {
    return MonthlyPhotoRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      photoDate: photoDate ?? this.photoDate,
      photoUrl: photoUrl ?? this.photoUrl,
      caption: caption ?? this.caption,
      monthYear: monthYear ?? this.monthYear,
      month: month ?? this.month,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  // ===========================================================================
  // FIRESTORE → MODEL
  // ===========================================================================

  factory MonthlyPhotoRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final photoDate = _readDateTime(
      data['photoDate'],
      fallback: _readDateTime(
        data['date'],
      ),
    );

    return MonthlyPhotoRecord(
      id: doc.id,
      goatId: _readString(data['goatId']),
      photoDate: photoDate,
      photoUrl: _readString(
        data['photoUrl'],
        fallback: _readString(
          data['url'],
        ),
      ),
      caption: _readString(
        data['caption'],
      ),
      monthYear: _readInt(
        data['monthYear'],
      ) ??
          photoDate.year,
      month: _readInt(
        data['month'],
      ) ??
          photoDate.month,
      recordedAt: _readDateTime(
        data['recordedAt'],
        fallback: _readDateTime(
          data['createdAt'],
        ),
      ),
    );
  }

  // ===========================================================================
  // MODEL → FIRESTORE
  // ===========================================================================

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,
      'photoDate': Timestamp.fromDate(
        photoDate,
      ),
      'photoUrl': photoUrl,
      'caption': caption,
      'monthYear': monthYear,
      'month': month,
      'recordedAt': Timestamp.fromDate(
        recordedAt,
      ),
    };
  }

  // ===========================================================================
  // CREATE MAP
  // ===========================================================================

  Map<String, dynamic> toCreateMap() {
    return {
      'goatId': goatId,
      'photoDate': Timestamp.fromDate(
        photoDate,
      ),
      'photoUrl': photoUrl,
      'caption': caption,
      'monthYear': monthYear,
      'month': month,
      'recordedAt':
      FieldValue.serverTimestamp(),
    };
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  bool get hasPhoto {
    return photoUrl.trim().isNotEmpty;
  }

  bool get hasCaption {
    return caption.trim().isNotEmpty;
  }

  String get monthKey {
    return '$monthYear-${month.toString().padLeft(2, '0')}';
  }

  String get monthName {
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

    if (month < 1 || month > 12) {
      return 'Unknown';
    }

    return months[month - 1];
  }

  String get monthLabel {
    return '$monthName $monthYear';
  }

  String get formattedPhotoDate {
    final day =
    photoDate.day.toString().padLeft(
      2,
      '0',
    );

    final monthNumber =
    photoDate.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$monthNumber/${photoDate.year}';
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================

  static String _readString(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  static int? _readInt(
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

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  static DateTime _readDateTime(
      dynamic value, {
        DateTime? fallback,
      }) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      final parsed =
      DateTime.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    return fallback ?? DateTime.now();
  }

  @override
  String toString() {
    return 'MonthlyPhotoRecord('
        'id: $id, '
        'goatId: $goatId, '
        'photoDate: $photoDate, '
        'photoUrl: $photoUrl, '
        'caption: $caption, '
        'monthYear: $monthYear, '
        'month: $month, '
        'recordedAt: $recordedAt'
        ')';
  }
}