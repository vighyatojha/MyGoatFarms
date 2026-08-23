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

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration timeout = Duration(seconds: 15);

  // ===========================================================================
  // FIRESTORE REFERENCES
  // ===========================================================================

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

  CollectionReference<Map<String, dynamic>> _weightRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('weightRecords');
  }

  CollectionReference<Map<String, dynamic>> _healthRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('healthRecords');
  }

  // NOTE: Customer Palai goats do NOT use a unified "healthEvents"
  // collection. Each activity type is written by its own screen into
  // its own subcollection (see customer_goat_vaccination_screen.dart,
  // customer_goat_medicine_screen.dart, customer_goat_hoof_screen.dart,
  // customer_goat_hair_screen.dart). "healthEvents" is a different
  // collection used only by Own Farm goats.

  CollectionReference<Map<String, dynamic>> _vaccinationRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('vaccinationRecords');
  }

  CollectionReference<Map<String, dynamic>> _medicineRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('medicineRecords');
  }

  CollectionReference<Map<String, dynamic>> _hoofCuttingRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('hoofCuttingRecords');
  }

  CollectionReference<Map<String, dynamic>> _hairTrimmingRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('hairTrimmingRecords');
  }

  CollectionReference<Map<String, dynamic>> _monthlyPhotos(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId).collection('monthlyPhotos');
  }

  // ===========================================================================
  // GENERATE MONTHLY REPORT
  // ===========================================================================

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
      ).get().timeout(timeout);

      for (final goatDoc in goatsSnapshot.docs) {
        final goatData = goatDoc.data();

        if (!_goatWasPresentDuringMonth(
          goatData,
          monthStart,
          nextMonthStart,
        )) {
          continue;
        }

        final reportGoat = await _buildGoatReport(
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

  // ===========================================================================
  // BUILD ONE GOAT REPORT
  // ===========================================================================

  Future<MonthlyReportGoat> _buildGoatReport({
    required String farmId,
    required String customerId,
    required String goatId,
    required Map<String, dynamic> goatData,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    final results = await Future.wait([
      _weightRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _healthRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _vaccinationRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _medicineRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _hoofCuttingRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _hairTrimmingRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _monthlyPhotos(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),
    ]);

    final weightRecordsSnapshot =
    results[0] as QuerySnapshot<Map<String, dynamic>>;

    final healthRecordsSnapshot =
    results[1] as QuerySnapshot<Map<String, dynamic>>;

    final vaccinationRecordsSnapshot =
    results[2] as QuerySnapshot<Map<String, dynamic>>;

    final medicineRecordsSnapshot =
    results[3] as QuerySnapshot<Map<String, dynamic>>;

    final hoofCuttingRecordsSnapshot =
    results[4] as QuerySnapshot<Map<String, dynamic>>;

    final hairTrimmingRecordsSnapshot =
    results[5] as QuerySnapshot<Map<String, dynamic>>;

    final monthlyPhotosSnapshot =
    results[6] as QuerySnapshot<Map<String, dynamic>>;

    // =========================================================================
    // WEIGHT RECORDS
    // =========================================================================

    final weightRecordsCount =
        weightRecordsSnapshot.docs.where(
              (doc) {
            final data = doc.data();

            // GoatWeightRecord stores the measurement date
            // in the "date" field.
            final date = _readDate(data['date']);

            return _isInsideMonth(
              date,
              monthStart,
              nextMonthStart,
            );
          },
        ).length;

    // =========================================================================
    // HEALTH RECORDS
    // =========================================================================

    final healthRecordsCount =
        healthRecordsSnapshot.docs.where(
              (doc) {
            final data = doc.data();

            final date = _readDate(
              data['recordedAt'] ?? data['date'],
            );

            return _isInsideMonth(
              date,
              monthStart,
              nextMonthStart,
            );
          },
        ).length;

    // =========================================================================
    // VACCINATIONS / MEDICINES / HOOF CUTTING / HAIR TRIMMING
    //
    // Each of these lives in its own collection with its own date field
    // (see customer_goat_*_screen.dart), so each is counted independently.
    // =========================================================================

    final vaccinationCount =
        vaccinationRecordsSnapshot.docs.where(
              (doc) {
            final date = _readDate(
              doc.data()['vaccinationDate'],
            );

            return _isInsideMonth(
              date,
              monthStart,
              nextMonthStart,
            );
          },
        ).length;

    final medicineCount =
        medicineRecordsSnapshot.docs.where(
              (doc) {
            final data = doc.data();

            final date = _readDate(
              data['treatmentDate'] ?? data['date'],
            );

            return _isInsideMonth(
              date,
              monthStart,
              nextMonthStart,
            );
          },
        ).length;

    final hoofCuttingCount =
        hoofCuttingRecordsSnapshot.docs.where(
              (doc) {
            final data = doc.data();

            final date = _readDate(
              data['cuttingDate'] ?? data['date'],
            );

            return _isInsideMonth(
              date,
              monthStart,
              nextMonthStart,
            );
          },
        ).length;

    final hairTrimmingCount =
        hairTrimmingRecordsSnapshot.docs.where(
              (doc) {
            final data = doc.data();

            final date = _readDate(
              data['trimmingDate'] ?? data['date'],
            );

            return _isInsideMonth(
              date,
              monthStart,
              nextMonthStart,
            );
          },
        ).length;

    // =========================================================================
    // MONTHLY PHOTOS
    // =========================================================================

    final monthlyPhotoCount =
        monthlyPhotosSnapshot.docs.where(
              (doc) {
            return _photoBelongsToMonth(
              doc.data(),
              monthStart,
            );
          },
        ).length;

    // =========================================================================
    // GOAT INFORMATION
    // =========================================================================

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

    // =========================================================================
    // FINAL STRUCTURED GOAT REPORT
    // =========================================================================

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

  // ===========================================================================
  // GOAT PRESENCE
  // ===========================================================================

  bool _goatWasPresentDuringMonth(
      Map<String, dynamic> goatData,
      DateTime monthStart,
      DateTime nextMonthStart,
      ) {
    final checkInDate = _readDate(
      goatData['checkInDate'],
    );

    final checkOutDate = _readDate(
      goatData['checkOutDate'],
    );

    if (checkInDate == null) {
      return false;
    }

    // Goat checked in after this month.
    if (!checkInDate.isBefore(nextMonthStart)) {
      return false;
    }

    // Goat checked out before this month started.
    if (checkOutDate != null &&
        !checkOutDate.isAfter(monthStart)) {
      return false;
    }

    return true;
  }

  // ===========================================================================
  // MONTH FILTER
  // ===========================================================================

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

  // ===========================================================================
  // MONTHLY PHOTO FILTER
  // ===========================================================================

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

      final monthString = monthValue.toString().trim();

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

  // ===========================================================================
  // FIRESTORE HELPERS
  // ===========================================================================

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