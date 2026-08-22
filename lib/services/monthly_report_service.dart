import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_report_model.dart';

/// Builds the new structured monthly Palai reports.
///
/// IMPORTANT:
/// - This service is READ-ONLY.
/// - It does not create/update/delete Firestore records.
/// - It does NOT use the old GoatReport / reports collection.
/// - It reads the actual historical collections used by Palai.
///
/// Firestore structure:
///
/// farms/{farmId}
///   └── palaiCustomers/{customerId}
///       └── goats/{goatId}
///           ├── healthRecords
///           ├── healthEvents
///           └── monthlyPhotos
class MonthlyReportService {
  MonthlyReportService._();

  static final MonthlyReportService instance =
  MonthlyReportService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration timeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // ROOT REFERENCES
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
    return _goats(farmId, customerId)
        .doc(goatId)
        .collection('healthRecords');
  }

  CollectionReference<Map<String, dynamic>> _healthEvents(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(farmId, customerId)
        .doc(goatId)
        .collection('healthEvents');
  }

  CollectionReference<Map<String, dynamic>> _monthlyPhotos(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(farmId, customerId)
        .doc(goatId)
        .collection('monthlyPhotos');
  }

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Builds reports for every goat that was present during [month].
  ///
  /// [month] can be any date inside the desired month.
  ///
  /// Example:
  ///
  ///     DateTime(2026, 8, 15)
  ///
  /// produces the August 2026 report.
  Future<List<MonthlyReport>> buildMonthlyReports({
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

    final reports = <MonthlyReport>[];

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

        final report = await _buildReportForGoat(
          farmId: farmId,
          customerId: customerId,
          goatId: goatDoc.id,
          goatData: goatData,
          monthStart: monthStart,
          nextMonthStart: nextMonthStart,
        );

        reports.add(report);
      }
    }

    // Stable ordering for the UI/PDF.
    reports.sort((a, b) {
      final nameCompare = a.goatName
          .toLowerCase()
          .compareTo(b.goatName.toLowerCase());

      if (nameCompare != 0) {
        return nameCompare;
      }

      return a.goatCode
          .toLowerCase()
          .compareTo(b.goatCode.toLowerCase());
    });

    return reports;
  }

  /// Builds the monthly report for one specific goat.
  Future<MonthlyReport?> buildMonthlyReport({
    required String farmId,
    required String customerId,
    required String goatId,
    required DateTime month,
  }) async {
    final goatDoc = await _goats(
      farmId,
      customerId,
    ).doc(goatId).get().timeout(timeout);

    if (!goatDoc.exists) {
      return null;
    }

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

    final goatData = goatDoc.data() ?? <String, dynamic>{};

    if (!_goatWasPresentDuringMonth(
      goatData,
      monthStart,
      nextMonthStart,
    )) {
      return null;
    }

    return _buildReportForGoat(
      farmId: farmId,
      customerId: customerId,
      goatId: goatId,
      goatData: goatData,
      monthStart: monthStart,
      nextMonthStart: nextMonthStart,
    );
  }

  // ---------------------------------------------------------------------------
  // REPORT BUILDER
  // ---------------------------------------------------------------------------

  Future<MonthlyReport> _buildReportForGoat({
    required String farmId,
    required String customerId,
    required String goatId,
    required Map<String, dynamic> goatData,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    // -------------------------------------------------------------------------
    // Load all historical sources.
    //
    // These are independent reads, so they can run in parallel.
    // -------------------------------------------------------------------------

    final results = await Future.wait([
      _healthRecords(
        farmId,
        customerId,
        goatId,
      ).get().timeout(timeout),

      _healthEvents(
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

    final healthRecordsSnapshot =
    results[0] as QuerySnapshot<Map<String, dynamic>>;

    final healthEventsSnapshot =
    results[1] as QuerySnapshot<Map<String, dynamic>>;

    final photosSnapshot =
    results[2] as QuerySnapshot<Map<String, dynamic>>;

    // -------------------------------------------------------------------------
    // Filter records to the selected month.
    // -------------------------------------------------------------------------

    final healthRecords = healthRecordsSnapshot.docs
        .map((doc) => doc.data())
        .where(
          (data) => _isInsideMonth(
        _readDate(
          data['recordedAt'],
        ),
        monthStart,
        nextMonthStart,
      ),
    )
        .toList();

    final healthEvents = healthEventsSnapshot.docs
        .map((doc) => doc.data())
        .where(
          (data) => _isInsideMonth(
        _readDate(
          data['date'],
        ),
        monthStart,
        nextMonthStart,
      ),
    )
        .toList();

    final monthlyPhotos = photosSnapshot.docs
        .map((doc) => doc.data())
        .where(
          (data) => _photoBelongsToMonth(
        data,
        monthStart,
      ),
    )
        .toList();

    // -------------------------------------------------------------------------
    // WEIGHT
    // -------------------------------------------------------------------------

    final weights = <_DatedWeight>[];

    for (final record in healthRecords) {
      final date = _readDate(record['recordedAt']);
      final weight = _readDouble(record['weight']);

      if (date != null && weight != null) {
        weights.add(
          _DatedWeight(
            date: date,
            weight: weight,
          ),
        );
      }
    }

    weights.sort(
          (a, b) => a.date.compareTo(b.date),
    );

    final double? startingWeight =
    weights.isNotEmpty ? weights.first.weight : null;

    final double? endingWeight =
    weights.isNotEmpty ? weights.last.weight : null;

    final double? weightChange =
    startingWeight != null && endingWeight != null
        ? endingWeight - startingWeight
        : null;

    // -------------------------------------------------------------------------
    // HEALTH EVENT COUNTS
    // -------------------------------------------------------------------------

    var vaccinationCount = 0;
    var medicineCount = 0;
    var hoofCuttingCount = 0;
    var hairTrimmingCount = 0;

    for (final event in healthEvents) {
      final type = _normaliseType(
        event['type'],
      );

      if (_isVaccination(type)) {
        vaccinationCount++;
      } else if (_isMedicine(type)) {
        medicineCount++;
      } else if (_isHoofCutting(type)) {
        hoofCuttingCount++;
      } else if (_isHairTrimming(type)) {
        hairTrimmingCount++;
      }
    }

    // -------------------------------------------------------------------------
    // PHOTOS
    // -------------------------------------------------------------------------

    final photoUrls = <String>[];

    for (final photo in monthlyPhotos) {
      final url = _readPhotoUrl(photo);

      if (url != null && url.isNotEmpty) {
        photoUrls.add(url);
      }
    }

    // Prevent duplicate URLs from appearing twice in the report.
    final uniquePhotoUrls = photoUrls.toSet().toList();

    // -------------------------------------------------------------------------
    // BOARDING
    // -------------------------------------------------------------------------

    final checkInDate =
        _readDate(goatData['checkInDate']) ??
            monthStart;

    final checkOutDate =
    _readDate(goatData['checkOutDate']);

    final boardingDays = _calculateBoardingDays(
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      monthStart: monthStart,
      nextMonthStart: nextMonthStart,
    );

    // -------------------------------------------------------------------------
    // HEALTH STATUS
    // -------------------------------------------------------------------------

    String healthStatus =
    _readString(
      goatData['healthStatus'],
    );

    // If the goat document does not have a usable health status,
    // fall back to the latest health record from the selected month.
    if (healthStatus.isEmpty && healthRecords.isNotEmpty) {
      final latestRecord = [...healthRecords]
        ..sort(
              (a, b) {
            final aDate =
                _readDate(a['recordedAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);

            final bDate =
                _readDate(b['recordedAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);

            return bDate.compareTo(aDate);
          },
        );

      healthStatus = _readString(
        latestRecord.first['healthStatus'],
      );
    }

    if (healthStatus.isEmpty) {
      healthStatus = 'Not Available';
    }

    // -------------------------------------------------------------------------
    // NOTES
    // -------------------------------------------------------------------------

    final notes = _buildNotes(
      healthRecords: healthRecords,
      healthEvents: healthEvents,
    );

    // -------------------------------------------------------------------------
    // REPORT
    // -------------------------------------------------------------------------

    return MonthlyReport(
      // Not persisted yet.
      // The save layer will provide the Firestore document ID later.
      id: '',

      customerId: customerId,
      goatId: goatId,

      month: monthStart,
      generatedAt: DateTime.now(),

      goatName: _readFirstString(
        goatData,
        const [
          'name',
          'goatName',
        ],
      ),

      goatCode: _readFirstString(
        goatData,
        const [
          'goatCode',
          'code',
          'tagNumber',
          'tagId',
        ],
      ),

      breed: _readString(
        goatData['breed'],
      ),

      gender: _readString(
        goatData['gender'],
      ),

      color: _readString(
        goatData['color'],
      ),

      checkInDate: checkInDate,
      checkOutDate: checkOutDate,

      boardingDays: boardingDays,

      startingWeight: startingWeight,
      endingWeight: endingWeight,
      weightChange: weightChange,

      healthRecordCount: healthRecords.length,

      vaccinationCount: vaccinationCount,
      medicineCount: medicineCount,
      hoofCuttingCount: hoofCuttingCount,
      hairTrimmingCount: hairTrimmingCount,

      monthlyPhotoCount: uniquePhotoUrls.length,

      healthStatus: healthStatus,

      photoUrls: uniquePhotoUrls,

      notes: notes,
    );
  }

  // ---------------------------------------------------------------------------
  // MONTH / BOARDING
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

    // Without a check-in date we cannot reliably establish
    // whether the goat belonged to this monthly report.
    if (checkInDate == null) {
      return false;
    }

    // Goat entered after the month ended.
    if (!checkInDate.isBefore(nextMonthStart)) {
      return false;
    }

    // Goat checked out before the month started.
    if (checkOutDate != null &&
        !checkOutDate.isAfter(monthStart)) {
      return false;
    }

    return true;
  }

  int _calculateBoardingDays({
    required DateTime checkInDate,
    required DateTime? checkOutDate,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) {
    final effectiveStart = checkInDate.isAfter(monthStart)
        ? _dateOnly(checkInDate)
        : _dateOnly(monthStart);

    final rawEnd = checkOutDate ?? nextMonthStart;

    final effectiveEnd = rawEnd.isBefore(nextMonthStart)
        ? _dateOnly(rawEnd)
        : _dateOnly(nextMonthStart);

    if (!effectiveStart.isBefore(effectiveEnd)) {
      return 0;
    }

    return effectiveEnd
        .difference(effectiveStart)
        .inDays;
  }

  // ---------------------------------------------------------------------------
  // PHOTO MONTH MATCHING
  // ---------------------------------------------------------------------------

  bool _photoBelongsToMonth(
      Map<String, dynamic> data,
      DateTime monthStart,
      ) {
    // MonthlyPhoto is normally keyed by a "month" field.
    final monthValue = data['month'];

    if (monthValue != null) {
      final date = _readDate(monthValue);

      if (date != null) {
        return date.year == monthStart.year &&
            date.month == monthStart.month;
      }

      // Some older records may store month as:
      // "2026-08"
      final monthString = monthValue.toString();

      if (monthString == _monthKey(monthStart)) {
        return true;
      }
    }

    // Fallback for records which may have been saved with a date field.
    final date = _readDate(
      data['date'] ?? data['createdAt'],
    );

    if (date == null) {
      return false;
    }

    return date.year == monthStart.year &&
        date.month == monthStart.month;
  }

  String? _readPhotoUrl(
      Map<String, dynamic> data,
      ) {
    final candidates = [
      data['photoUrl'],
      data['imageUrl'],
      data['url'],
      data['downloadUrl'],
    ];

    for (final candidate in candidates) {
      final value = _readString(candidate);

      if (value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // EVENT TYPE HELPERS
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
  // NOTES
  // ---------------------------------------------------------------------------

  String _buildNotes({
    required List<Map<String, dynamic>> healthRecords,
    required List<Map<String, dynamic>> healthEvents,
  }) {
    final notes = <String>[];

    for (final record in healthRecords) {
      final note = _readFirstString(
        record,
        const [
          'notes',
          'note',
          'remarks',
        ],
      );

      if (note.isNotEmpty) {
        notes.add(note);
      }
    }

    for (final event in healthEvents) {
      final note = _readFirstString(
        event,
        const [
          'notes',
          'note',
          'remarks',
        ],
      );

      if (note.isNotEmpty) {
        notes.add(note);
      }
    }

    // Keep the generated report compact and avoid repeating identical notes.
    return notes.toSet().join('\n');
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE VALUE HELPERS
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

  double? _readDouble(dynamic value) {
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

  String _readString(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  String _readFirstString(
      Map<String, dynamic> data,
      List<String> keys,
      ) {
    for (final key in keys) {
      final value = _readString(
        data[key],
      );

      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

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

  String _monthKey(DateTime month) {
    return '${month.year}-${month.month.toString().padLeft(2, '0')}';
  }
}

// -----------------------------------------------------------------------------
// INTERNAL WEIGHT VALUE
// -----------------------------------------------------------------------------

class _DatedWeight {
  final DateTime date;
  final double weight;

  const _DatedWeight({
    required this.date,
    required this.weight,
  });
}