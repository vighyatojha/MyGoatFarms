import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_report_model.dart';

/// Service for the structured Monthly Report.
///
/// Each goat contains ONLY:
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
///
/// This service is READ-ONLY.
class MonthlyReportService {
  MonthlyReportService._();

  static final MonthlyReportService instance =
  MonthlyReportService._();

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  static const Duration timeout =
  Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // FIRESTORE REFERENCES
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _customers(
      String farmId,
      ) {
    return _db
        .collection('farms')
        .doc(farmId)
        .collection('palaiCustomers');
  }

  CollectionReference<Map<String, dynamic>> _goats(
      String farmId,
      String customerId,
      ) {
    return _customers(farmId)
        .doc(customerId)
        .collection('goats');
  }

  CollectionReference<Map<String, dynamic>> _healthRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    )
        .doc(goatId)
        .collection('healthRecords');
  }

  CollectionReference<Map<String, dynamic>> _healthEvents(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    )
        .doc(goatId)
        .collection('healthEvents');
  }

  CollectionReference<Map<String, dynamic>> _monthlyPhotos(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    )
        .doc(goatId)
        .collection('monthlyPhotos');
  }

  // ---------------------------------------------------------------------------
  // GENERATE MONTHLY REPORT
  // ---------------------------------------------------------------------------

  Future<MonthlyReport> generateMonthlyReport({
    required String farmId,
    required DateTime month,
  }) async {
    final monthStart = DateTime(
      month.year,
      month.month,
      1,
    );

    final nextMonthStart = DateTime(
      month.year,
      month.month + 1,
      1,
    );

    final customersSnapshot = await _customers(farmId)
        .get()
        .timeout(timeout);

    final reportGoats = <MonthlyReportGoat>[];

    for (final customerDoc in customersSnapshot.docs) {
      final customerId = customerDoc.id;

      final goatsSnapshot = await _goats(
        farmId,
        customerId,
      )
          .get()
          .timeout(timeout);

      for (final goatDoc in goatsSnapshot.docs) {
        final goatData = goatDoc.data();

        final goatWasPresent =
        _goatWasPresentDuringMonth(
          goatData,
          monthStart,
          nextMonthStart,
        );

        if (!goatWasPresent) {
          continue;
        }

        final reportGoat =
        await _buildGoatReport(
          farmId: farmId,
          customerId: customerId,
          goatId: goatDoc.id,
          goatData: goatData,
          monthStart: monthStart,
          nextMonthStart: nextMonthStart,
        );

        reportGoats.add(reportGoat);
      }
    }

    reportGoats.sort(
          (a, b) {
        final nameCompare = a.goatName
            .toLowerCase()
            .compareTo(
          b.goatName.toLowerCase(),
        );

        if (nameCompare != 0) {
          return nameCompare;
        }

        return a.tagNumber
            .toLowerCase()
            .compareTo(
          b.tagNumber.toLowerCase(),
        );
      },
    );

    return MonthlyReport(
      id: '',
      farmId: farmId,
      month: monthStart,
      generatedAt: DateTime.now(),
      goats: reportGoats,
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD ONE GOAT REPORT
  // ---------------------------------------------------------------------------

  Future<MonthlyReportGoat> _buildGoatReport({
    required String farmId,
    required String customerId,
    required String goatId,
    required Map<String, dynamic> goatData,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    final results = await Future.wait([
      _healthRecords(
        farmId,
        customerId,
        goatId,
      )
          .get()
          .timeout(timeout),

      _healthEvents(
        farmId,
        customerId,
        goatId,
      )
          .get()
          .timeout(timeout),

      _monthlyPhotos(
        farmId,
        customerId,
        goatId,
      )
          .get()
          .timeout(timeout),
    ]);

    final healthRecordsSnapshot =
    results[0]
    as QuerySnapshot<Map<String, dynamic>>;

    final healthEventsSnapshot =
    results[1]
    as QuerySnapshot<Map<String, dynamic>>;

    final monthlyPhotosSnapshot =
    results[2]
    as QuerySnapshot<Map<String, dynamic>>;

    // -------------------------------------------------------------------------
    // HEALTH RECORDS
    // -------------------------------------------------------------------------

    final healthRecordsList =
    healthRecordsSnapshot.docs.where(
          (doc) {
        final date = _readDate(
          doc.data()['recordedAt'],
        );

        return _isInsideMonth(
          date,
          monthStart,
          nextMonthStart,
        );
      },
    ).toList();

    final weightRecordsCount =
        healthRecordsList.where(
              (doc) {
            return doc.data()['weight'] != null;
          },
        ).length;

    final healthRecordsCount =
        healthRecordsList.length;

    // -------------------------------------------------------------------------
    // HEALTH EVENTS
    // -------------------------------------------------------------------------

    final healthEvents =
    healthEventsSnapshot.docs.where(
          (doc) {
        final date = _readDate(
          doc.data()['date'],
        );

        return _isInsideMonth(
          date,
          monthStart,
          nextMonthStart,
        );
      },
    );

    var vaccinationCount = 0;
    var medicineCount = 0;
    var hoofCuttingCount = 0;
    var hairTrimmingCount = 0;

    for (final doc in healthEvents) {
      final type = _normaliseType(
        doc.data()['type'],
      );

      if (_isVaccination(type)) {
        vaccinationCount++;
      }

      if (_isMedicine(type)) {
        medicineCount++;
      }

      if (_isHoofCutting(type)) {
        hoofCuttingCount++;
      }

      if (_isHairTrimming(type)) {
        hairTrimmingCount++;
      }
    }

    // -------------------------------------------------------------------------
    // MONTHLY PHOTOS
    // -------------------------------------------------------------------------

    final monthlyPhotoCount =
        monthlyPhotosSnapshot.docs.where(
              (doc) {
            return _photoBelongsToMonth(
              doc.data(),
              monthStart,
            );
          },
        ).length;

    // -------------------------------------------------------------------------
    // GOAT INFORMATION
    // -------------------------------------------------------------------------

    final goatName = _readFirstString(
      goatData,
      const [
        'name',
        'goatName',
      ],
    );

    final tagNumber = _readFirstString(
      goatData,
      const [
        'tagNumber',
        'goatCode',
        'code',
        'tagId',
      ],
    );

    return MonthlyReportGoat(
      goatName: goatName,
      tagNumber: tagNumber,
      weightRecordsCount: weightRecordsCount,
      healthRecordsCount: healthRecordsCount,
      vaccinationCount: vaccinationCount,
      medicineCount: medicineCount,
      hoofCuttingCount: hoofCuttingCount,
      hairTrimmingCount: hairTrimmingCount,
      monthlyPhotoCount: monthlyPhotoCount,
    );
  }

  // ---------------------------------------------------------------------------
  // GOAT PRESENCE
  // ---------------------------------------------------------------------------

  bool _goatWasPresentDuringMonth(
      Map<String, dynamic> goatData,
      DateTime monthStart,
      DateTime nextMonthStart,
      ) {
    final checkInDate =
    _readDate(goatData['checkInDate']);

    final checkOutDate =
    _readDate(goatData['checkOutDate']);

    if (checkInDate == null) {
      return false;
    }

    if (!checkInDate.isBefore(nextMonthStart)) {
      return false;
    }

    if (checkOutDate != null &&
        !checkOutDate.isAfter(monthStart)) {
      return false;
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // MONTH FILTER
  // ---------------------------------------------------------------------------

  bool _isInsideMonth(
      DateTime? date,
      DateTime monthStart,
      DateTime nextMonthStart,
      ) {
    if (date == null) {
      return false;
    }

    return !date.isBefore(monthStart) &&
        date.isBefore(nextMonthStart);
  }

  // ---------------------------------------------------------------------------
  // PHOTO FILTER
  // ---------------------------------------------------------------------------

  bool _photoBelongsToMonth(
      Map<String, dynamic> data,
      DateTime monthStart,
      ) {
    final monthValue = data['month'];

    if (monthValue != null) {
      final monthDate = _readDate(monthValue);

      if (monthDate != null) {
        return monthDate.year == monthStart.year &&
            monthDate.month == monthStart.month;
      }

      final monthString = monthValue.toString();

      final expected =
          '${monthStart.year}-'
          '${monthStart.month.toString().padLeft(2, '0')}';

      if (monthString == expected) {
        return true;
      }
    }

    final fallbackDate = _readDate(
      data['date'] ?? data['createdAt'],
    );

    if (fallbackDate == null) {
      return false;
    }

    return fallbackDate.year == monthStart.year &&
        fallbackDate.month == monthStart.month;
  }

  // ---------------------------------------------------------------------------
  // EVENT TYPES
  // ---------------------------------------------------------------------------

  String _normaliseType(dynamic value) {
    return _readString(value)
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }

  bool _isVaccination(String type) {
    return type.contains('vaccin');
  }

  bool _isMedicine(String type) {
    return type.contains('medicine') ||
        type.contains('medication') ||
        type.contains('drug');
  }

  bool _isHoofCutting(String type) {
    return type.contains('hoof') ||
        type.contains('khud') ||
        type.contains('hoofcut');
  }

  bool _isHairTrimming(String type) {
    return type.contains('hair') ||
        type.contains('trim') ||
        type.contains('hairtrim');
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  DateTime? _readDate(dynamic value) {
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

  String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  String _readFirstString(
      Map<String, dynamic> data,
      List<String> keys,
      ) {
    for (final key in keys) {
      final value = _readString(data[key]);

      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }
}