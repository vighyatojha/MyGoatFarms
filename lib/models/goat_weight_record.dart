import 'package:cloud_firestore/cloud_firestore.dart';

/// A single weight measurement for a Palai goat.
///
/// Stored under:
/// palaiCustomers/{customerId}/goats/{goatId}/weightRecords/{recordId}
class GoatWeightRecord {
  final String id;
  final String goatId;

  /// Weight of the goat in kilograms.
  final double weight;

  /// Weight before this measurement, if available.
  final double? previousWeight;

  /// Difference from the previous recorded weight.
  ///
  /// Positive = weight gain
  /// Negative = weight loss
  /// Zero = no change
  final double? weightChange;

  /// Date on which the goat was weighed.
  final DateTime date;

  /// Optional note about this measurement.
  final String note;

  /// Server/local creation timestamp.
  final DateTime recordedAt;

  const GoatWeightRecord({
    required this.id,
    required this.goatId,
    required this.weight,
    this.previousWeight,
    this.weightChange,
    required this.date,
    this.note = '',
    required this.recordedAt,
  });

  // ===========================================================================
  // COPY
  // ===========================================================================

  GoatWeightRecord copyWith({
    String? id,
    String? goatId,
    double? weight,
    double? previousWeight,
    bool clearPreviousWeight = false,
    double? weightChange,
    bool clearWeightChange = false,
    DateTime? date,
    String? note,
    DateTime? recordedAt,
  }) {
    return GoatWeightRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      weight: weight ?? this.weight,
      previousWeight: clearPreviousWeight
          ? null
          : previousWeight ?? this.previousWeight,
      weightChange: clearWeightChange
          ? null
          : weightChange ?? this.weightChange,
      date: date ?? this.date,
      note: note ?? this.note,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  // ===========================================================================
  // FIRESTORE → MODEL
  // ===========================================================================

  factory GoatWeightRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return GoatWeightRecord(
      id: doc.id,
      goatId: _readString(
        data['goatId'],
      ),
      weight: _readDouble(
        data['weight'],
      ),
      previousWeight: _readNullableDouble(
        data['previousWeight'],
      ),
      weightChange: _readNullableDouble(
        data['weightChange'],
      ),
      date: _readDateTime(
        data['date'],
      ),
      note: _readString(
        data['note'],
      ),
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
      'weight': weight,
      'previousWeight': previousWeight,
      'weightChange': weightChange,
      'date': Timestamp.fromDate(date),
      'note': note,
      'recordedAt': Timestamp.fromDate(recordedAt),
    };
  }

  // ===========================================================================
  // FIRESTORE MAP FOR CREATE
  // ===========================================================================

  Map<String, dynamic> toCreateMap() {
    return {
      'goatId': goatId,
      'weight': weight,
      'previousWeight': previousWeight,
      'weightChange': weightChange,
      'date': Timestamp.fromDate(date),
      'note': note,
      'recordedAt': FieldValue.serverTimestamp(),
    };
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static String _readString(
      dynamic value,
      ) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static double _readDouble(
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
      final parsed = DateTime.tryParse(
        value,
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return fallback ?? DateTime.now();
  }

  // ===========================================================================
  // DISPLAY HELPERS
  // ===========================================================================

  bool get hasPreviousWeight =>
      previousWeight != null;

  bool get hasWeightChange =>
      weightChange != null;

  bool get gainedWeight =>
      weightChange != null &&
          weightChange! > 0;

  bool get lostWeight =>
      weightChange != null &&
          weightChange! < 0;

  bool get maintainedWeight =>
      weightChange != null &&
          weightChange == 0;

  String get formattedWeight {
    return '${_formatNumber(weight)} kg';
  }

  String get formattedWeightChange {
    if (weightChange == null) {
      return '—';
    }

    final change = weightChange!;

    if (change > 0) {
      return '+${_formatNumber(change)} kg';
    }

    if (change < 0) {
      return '${_formatNumber(change)} kg';
    }

    return '0 kg';
  }

  String get changeDescription {
    if (weightChange == null) {
      return 'No previous weight';
    }

    if (weightChange! > 0) {
      return 'Weight gained';
    }

    if (weightChange! < 0) {
      return 'Weight lost';
    }

    return 'No weight change';
  }

  static String _formatNumber(
      double value,
      ) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(1);
  }

  @override
  String toString() {
    return 'GoatWeightRecord('
        'id: $id, '
        'goatId: $goatId, '
        'weight: $weight, '
        'previousWeight: $previousWeight, '
        'weightChange: $weightChange, '
        'date: $date, '
        'note: $note, '
        'recordedAt: $recordedAt'
        ')';
  }
}