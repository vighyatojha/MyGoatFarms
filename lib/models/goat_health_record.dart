import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// GOAT HEALTH RECORD
/// ============================================================================
///
/// Stores ONE health-related event/check for a goat.
///
/// IMPORTANT ARCHITECTURE:
///
/// PalaiGoat
///    └── current health status
///
/// GoatHealthRecord
///    ├── complete health history
///    ├── symptoms
///    ├── diagnosis
///    ├── treatment
///    ├── temperature
///    ├── veterinary information
///    └── follow-up information
///
/// We keep the history separately so the goat document remains small and
/// the Health screen can show a chronological medical/health timeline.
///
/// This model is shared by:
///
/// Customer Palai
///    └── health monitoring of customer's goats
///
/// Own Farm Palai
///    └── health monitoring + complete performance history
///
/// ============================================================================

enum GoatHealthRecordType {
  routineCheck,
  illness,
  injury,
  treatment,
  followUp,
  observation,
  emergency,
  other,
}

enum GoatHealthCondition {
  healthy,
  underObservation,
  sick,
  recovering,
  injured,
  critical,
  unknown,
}

class GoatHealthRecord {
  // ==========================================================================
  // IDENTITY
  // ==========================================================================

  final String id;

  /// Goat associated with this health record.
  final String goatId;

  // ==========================================================================
  // RECORD INFORMATION
  // ==========================================================================

  /// Type of health event.
  final GoatHealthRecordType recordType;

  /// Overall condition observed during this record.
  final GoatHealthCondition condition;

  /// Date/time when the health event/check happened.
  final DateTime recordedAt;

  // ==========================================================================
  // CLINICAL INFORMATION
  // ==========================================================================

  /// Main symptoms observed.
  final String symptoms;

  /// Diagnosis, if available.
  final String diagnosis;

  /// Treatment given during this health event.
  final String treatment;

  /// General health observation.
  final String observation;

  /// Temperature in Celsius, if recorded.
  final double? temperatureCelsius;

  // ==========================================================================
  // VETERINARY INFORMATION
  // ==========================================================================

  /// Name of veterinarian, if applicable.
  final String veterinarianName;

  /// Veterinarian/contact clinic information.
  final String veterinarianContact;

  // ==========================================================================
  // FOLLOW-UP
  // ==========================================================================

  /// Whether a follow-up is required.
  final bool followUpRequired;

  /// Date on which the goat should be checked again.
  final DateTime? followUpDate;

  /// Follow-up instructions.
  final String followUpNotes;

  // ==========================================================================
  // MEDICINE LINK
  // ==========================================================================

  /// Optional reference to a medicine record.
  ///
  /// Medicine itself will have its own model/history.
  final String? medicineRecordId;

  // ==========================================================================
  // ATTACHMENTS / NOTES
  // ==========================================================================

  /// Optional health-related photo.
  final String? photoUrl;

  /// Additional notes.
  final String notes;

  // ==========================================================================
  // AUDIT
  // ==========================================================================

  /// Person who recorded this health event.
  final String recordedBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const GoatHealthRecord({
    required this.id,
    required this.goatId,
    required this.recordType,
    required this.condition,
    required this.recordedAt,
    this.symptoms = '',
    this.diagnosis = '',
    this.treatment = '',
    this.observation = '',
    this.temperatureCelsius,
    this.veterinarianName = '',
    this.veterinarianContact = '',
    this.followUpRequired = false,
    this.followUpDate,
    this.followUpNotes = '',
    this.medicineRecordId,
    this.photoUrl,
    this.notes = '',
    this.recordedBy = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  GoatHealthRecord copyWith({
    String? id,
    String? goatId,
    GoatHealthRecordType? recordType,
    GoatHealthCondition? condition,
    DateTime? recordedAt,
    String? symptoms,
    String? diagnosis,
    String? treatment,
    String? observation,
    double? temperatureCelsius,
    bool clearTemperature = false,
    String? veterinarianName,
    String? veterinarianContact,
    bool? followUpRequired,
    DateTime? followUpDate,
    bool clearFollowUpDate = false,
    String? followUpNotes,
    String? medicineRecordId,
    bool clearMedicineRecordId = false,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? notes,
    String? recordedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GoatHealthRecord(
      id: id ?? this.id,
      goatId: goatId ?? this.goatId,
      recordType: recordType ?? this.recordType,
      condition: condition ?? this.condition,
      recordedAt: recordedAt ?? this.recordedAt,
      symptoms: symptoms ?? this.symptoms,
      diagnosis: diagnosis ?? this.diagnosis,
      treatment: treatment ?? this.treatment,
      observation: observation ?? this.observation,

      temperatureCelsius:
      clearTemperature
          ? null
          : (temperatureCelsius ?? this.temperatureCelsius),

      veterinarianName:
      veterinarianName ?? this.veterinarianName,

      veterinarianContact:
      veterinarianContact ?? this.veterinarianContact,

      followUpRequired:
      followUpRequired ?? this.followUpRequired,

      followUpDate:
      clearFollowUpDate
          ? null
          : (followUpDate ?? this.followUpDate),

      followUpNotes:
      followUpNotes ?? this.followUpNotes,

      medicineRecordId:
      clearMedicineRecordId
          ? null
          : (medicineRecordId ?? this.medicineRecordId),

      photoUrl:
      clearPhotoUrl
          ? null
          : (photoUrl ?? this.photoUrl),

      notes: notes ?? this.notes,

      recordedBy: recordedBy ?? this.recordedBy,

      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory GoatHealthRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    return GoatHealthRecord(
      id: doc.id,

      goatId: _stringValue(
        data['goatId'],
      ),

      recordType: _recordTypeValue(
        data['recordType'],
      ),

      condition: _conditionValue(
        data['condition'],
      ),

      recordedAt: _dateValue(
        data['recordedAt'] ?? data['date'],
      ),

      symptoms: _stringValue(
        data['symptoms'],
      ),

      diagnosis: _stringValue(
        data['diagnosis'],
      ),

      treatment: _stringValue(
        data['treatment'],
      ),

      observation: _stringValue(
        data['observation'],
      ),

      temperatureCelsius: _nullableDoubleValue(
        data['temperatureCelsius'] ??
            data['temperature'],
      ),

      veterinarianName: _stringValue(
        data['veterinarianName'] ??
            data['vetName'],
      ),

      veterinarianContact: _stringValue(
        data['veterinarianContact'] ??
            data['vetContact'],
      ),

      followUpRequired: _boolValue(
        data['followUpRequired'],
        defaultValue: false,
      ),

      followUpDate: _nullableDateValue(
        data['followUpDate'],
      ),

      followUpNotes: _stringValue(
        data['followUpNotes'],
      ),

      medicineRecordId: _nullableStringValue(
        data['medicineRecordId'],
      ),

      photoUrl: _nullableStringValue(
        data['photoUrl'],
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

      'recordType': recordType.name,

      'condition': condition.name,

      'recordedAt': Timestamp.fromDate(
        recordedAt,
      ),

      'symptoms': symptoms,

      'diagnosis': diagnosis,

      'treatment': treatment,

      'observation': observation,

      'temperatureCelsius': temperatureCelsius,

      'veterinarianName': veterinarianName,

      'veterinarianContact': veterinarianContact,

      'followUpRequired': followUpRequired,

      'followUpDate':
      followUpDate == null
          ? null
          : Timestamp.fromDate(
        followUpDate!,
      ),

      'followUpNotes': followUpNotes,

      'medicineRecordId': medicineRecordId,

      'photoUrl': photoUrl,

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
  // FACTORY FOR NEW HEALTH RECORD
  // ==========================================================================

  factory GoatHealthRecord.create({
    required String id,
    required String goatId,
    GoatHealthRecordType recordType =
        GoatHealthRecordType.routineCheck,
    GoatHealthCondition condition =
        GoatHealthCondition.unknown,
    DateTime? recordedAt,
    String symptoms = '',
    String diagnosis = '',
    String treatment = '',
    String observation = '',
    double? temperatureCelsius,
    String veterinarianName = '',
    String veterinarianContact = '',
    bool followUpRequired = false,
    DateTime? followUpDate,
    String followUpNotes = '',
    String? medicineRecordId,
    String? photoUrl,
    String notes = '',
    String recordedBy = '',
  }) {
    final now = DateTime.now();

    return GoatHealthRecord(
      id: id,
      goatId: goatId,
      recordType: recordType,
      condition: condition,
      recordedAt: recordedAt ?? now,
      symptoms: symptoms,
      diagnosis: diagnosis,
      treatment: treatment,
      observation: observation,
      temperatureCelsius: temperatureCelsius,
      veterinarianName: veterinarianName,
      veterinarianContact: veterinarianContact,
      followUpRequired: followUpRequired,
      followUpDate: followUpDate,
      followUpNotes: followUpNotes,
      medicineRecordId: medicineRecordId,
      photoUrl: photoUrl,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (goatId.trim().isEmpty) {
      return 'Goat ID is required.';
    }

    if (temperatureCelsius != null &&
        temperatureCelsius! < 0) {
      return 'Temperature cannot be negative.';
    }

    if (followUpRequired && followUpDate == null) {
      return 'Follow-up date is required.';
    }

    return null;
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

  String get recordTypeLabel {
    switch (recordType) {
      case GoatHealthRecordType.routineCheck:
        return 'Routine Check';

      case GoatHealthRecordType.illness:
        return 'Illness';

      case GoatHealthRecordType.injury:
        return 'Injury';

      case GoatHealthRecordType.treatment:
        return 'Treatment';

      case GoatHealthRecordType.followUp:
        return 'Follow-up';

      case GoatHealthRecordType.observation:
        return 'Observation';

      case GoatHealthRecordType.emergency:
        return 'Emergency';

      case GoatHealthRecordType.other:
        return 'Other';
    }
  }

  String get conditionLabel {
    switch (condition) {
      case GoatHealthCondition.healthy:
        return 'Healthy';

      case GoatHealthCondition.underObservation:
        return 'Under Observation';

      case GoatHealthCondition.sick:
        return 'Sick';

      case GoatHealthCondition.recovering:
        return 'Recovering';

      case GoatHealthCondition.injured:
        return 'Injured';

      case GoatHealthCondition.critical:
        return 'Critical';

      case GoatHealthCondition.unknown:
        return 'Not Available';
    }
  }

  bool get hasSymptoms {
    return symptoms.trim().isNotEmpty;
  }

  bool get hasDiagnosis {
    return diagnosis.trim().isNotEmpty;
  }

  bool get hasTreatment {
    return treatment.trim().isNotEmpty;
  }

  bool get hasObservation {
    return observation.trim().isNotEmpty;
  }

  bool get hasVeterinarian {
    return veterinarianName.trim().isNotEmpty;
  }

  bool get hasTemperature {
    return temperatureCelsius != null;
  }

  bool get hasFollowUp {
    return followUpRequired;
  }

  bool get hasMedicine {
    return medicineRecordId != null &&
        medicineRecordId!.trim().isNotEmpty;
  }

  bool get hasPhoto {
    return photoUrl != null &&
        photoUrl!.trim().isNotEmpty;
  }

  // ==========================================================================
  // FIRESTORE ENUM HELPERS
  // ==========================================================================

  static GoatHealthRecordType _recordTypeValue(
      dynamic value,
      ) {
    if (value == null) {
      return GoatHealthRecordType.routineCheck;
    }

    switch (value.toString()) {
      case 'routineCheck':
      case 'routine_check':
        return GoatHealthRecordType.routineCheck;

      case 'illness':
        return GoatHealthRecordType.illness;

      case 'injury':
        return GoatHealthRecordType.injury;

      case 'treatment':
        return GoatHealthRecordType.treatment;

      case 'followUp':
      case 'follow_up':
        return GoatHealthRecordType.followUp;

      case 'observation':
        return GoatHealthRecordType.observation;

      case 'emergency':
        return GoatHealthRecordType.emergency;

      case 'other':
        return GoatHealthRecordType.other;

      default:
        return GoatHealthRecordType.routineCheck;
    }
  }

  static GoatHealthCondition _conditionValue(
      dynamic value,
      ) {
    if (value == null) {
      return GoatHealthCondition.unknown;
    }

    switch (value.toString()) {
      case 'healthy':
        return GoatHealthCondition.healthy;

      case 'underObservation':
      case 'under_observation':
        return GoatHealthCondition.underObservation;

      case 'sick':
        return GoatHealthCondition.sick;

      case 'recovering':
        return GoatHealthCondition.recovering;

      case 'injured':
        return GoatHealthCondition.injured;

      case 'critical':
        return GoatHealthCondition.critical;

      default:
        return GoatHealthCondition.unknown;
    }
  }

  // ==========================================================================
  // FIRESTORE VALUE HELPERS
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

  // ==========================================================================
  // DEBUG
  // ==========================================================================

  @override
  String toString() {
    return 'GoatHealthRecord('
        'id: $id, '
        'goatId: $goatId, '
        'recordType: ${recordType.name}, '
        'condition: ${condition.name}, '
        'recordedAt: $recordedAt'
        ')';
  }
}