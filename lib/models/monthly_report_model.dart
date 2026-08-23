import 'package:cloud_firestore/cloud_firestore.dart';

/// One goat inside a structured Monthly Report.
///
/// ONLY these fields belong to the goat-wise monthly report:
///
/// goatName
/// tagNumber
/// weightRecordsCount
/// healthRecordsCount
/// vaccinationCount
/// medicineCount
/// hoofCuttingCount
/// hairTrimmingCount
/// monthlyPhotoCount
class MonthlyReportGoat {
  final String goatName;
  final String tagNumber;

  final int weightRecordsCount;
  final int healthRecordsCount;
  final int vaccinationCount;
  final int medicineCount;
  final int hoofCuttingCount;
  final int hairTrimmingCount;
  final int monthlyPhotoCount;

  const MonthlyReportGoat({
    required this.goatName,
    required this.tagNumber,
    required this.weightRecordsCount,
    required this.healthRecordsCount,
    required this.vaccinationCount,
    required this.medicineCount,
    required this.hoofCuttingCount,
    required this.hairTrimmingCount,
    required this.monthlyPhotoCount,
  });

  factory MonthlyReportGoat.fromMap(
      Map<String, dynamic> data,
      ) {
    return MonthlyReportGoat(
      goatName: _string(data['goatName']),
      tagNumber: _string(data['tagNumber']),
      weightRecordsCount: _int(data['weightRecordsCount']),
      healthRecordsCount: _int(data['healthRecordsCount']),
      vaccinationCount: _int(data['vaccinationCount']),
      medicineCount: _int(data['medicineCount']),
      hoofCuttingCount: _int(data['hoofCuttingCount']),
      hairTrimmingCount: _int(data['hairTrimmingCount']),
      monthlyPhotoCount: _int(data['monthlyPhotoCount']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatName': goatName,
      'tagNumber': tagNumber,
      'weightRecordsCount': weightRecordsCount,
      'healthRecordsCount': healthRecordsCount,
      'vaccinationCount': vaccinationCount,
      'medicineCount': medicineCount,
      'hoofCuttingCount': hoofCuttingCount,
      'hairTrimmingCount': hairTrimmingCount,
      'monthlyPhotoCount': monthlyPhotoCount,
    };
  }

  static String _string(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static int _int(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }
}

/// Complete structured Monthly Report.
///
/// One report represents one calendar month.
class MonthlyReport {
  final String id;
  final String farmId;
  final DateTime month;
  final DateTime generatedAt;

  final List<MonthlyReportGoat> goats;

  const MonthlyReport({
    required this.id,
    required this.farmId,
    required this.month,
    required this.generatedAt,
    required this.goats,
  });

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

  factory MonthlyReport.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    final goatsData =
        (data['goats'] as List<dynamic>?) ?? const [];

    return MonthlyReport(
      id: doc.id,
      farmId: _string(data['farmId']),
      month: _date(
        data['month'],
        fallback: DateTime.now(),
      ),
      generatedAt: _date(
        data['generatedAt'],
        fallback: DateTime.now(),
      ),
      goats: goatsData
          .whereType<Map>()
          .map(
            (goat) => MonthlyReportGoat.fromMap(
          Map<String, dynamic>.from(goat),
        ),
      )
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'farmId': farmId,
      'month': Timestamp.fromDate(month),
      'generatedAt': Timestamp.fromDate(generatedAt),
      'goats': goats.map(
            (goat) => goat.toMap(),
      ).toList(),
    };
  }

  static String _string(dynamic value) {
    return value?.toString().trim() ?? '';
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
}