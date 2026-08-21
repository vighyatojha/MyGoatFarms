import 'package:cloud_firestore/cloud_firestore.dart';

/// ===========================================================================
/// PALAI RECORD FOUNDATION
/// ===========================================================================
///
/// This file contains the NEW historical record models for the rebuilt Palai
/// module.
///
/// IMPORTANT:
/// - Existing PalaiCustomer remains in palai_models.dart.
/// - Existing PalaiGoat remains in palai_models.dart.
/// - Existing OwnFarmGoat remains in own_farm_models.dart.
/// - We are NOT replacing those models in this step.
///
/// The purpose of this file is to separate historical records properly.
///
/// Every record belongs to a goat.
/// Customer-level settings, bills and payments belong to the customer.
///
/// This structure will later be used by:
/// - Customer Palai
/// - Own Farm Palai
/// - Reminder Engine
/// - Reports
/// - Dashboard
///
/// ===========================================================================


// ============================================================================
// CARE TYPES
// ============================================================================

enum PalaiCareType {
  vaccination,
  deworming,
  hoofCutting,
  hairTrimming,
  medicine,
  checkup,
}

extension PalaiCareTypeExtension on PalaiCareType {
  String get value {
    switch (this) {
      case PalaiCareType.vaccination:
        return 'vaccination';

      case PalaiCareType.deworming:
        return 'deworming';

      case PalaiCareType.hoofCutting:
        return 'hoofCutting';

      case PalaiCareType.hairTrimming:
        return 'hairTrimming';

      case PalaiCareType.medicine:
        return 'medicine';

      case PalaiCareType.checkup:
        return 'checkup';
    }
  }

  String get label {
    switch (this) {
      case PalaiCareType.vaccination:
        return 'Vaccination';

      case PalaiCareType.deworming:
        return 'Deworming';

      case PalaiCareType.hoofCutting:
        return 'Hoof Cutting';

      case PalaiCareType.hairTrimming:
        return 'Hair Trimming';

      case PalaiCareType.medicine:
        return 'Medicine';

      case PalaiCareType.checkup:
        return 'Checkup';
    }
  }
}


// ============================================================================
// CHECK-IN / CHECK-OUT
// ============================================================================

enum PalaiCheckInOutType {
  checkIn,
  checkOut,
}

extension PalaiCheckInOutTypeExtension on PalaiCheckInOutType {
  String get value {
    switch (this) {
      case PalaiCheckInOutType.checkIn:
        return 'checkIn';

      case PalaiCheckInOutType.checkOut:
        return 'checkOut';
    }
  }

  String get label {
    switch (this) {
      case PalaiCheckInOutType.checkIn:
        return 'Check-In';

      case PalaiCheckInOutType.checkOut:
        return 'Check-Out';
    }
  }
}


// ============================================================================
// REMINDER TYPES
// ============================================================================

enum PalaiReminderType {
  vaccination,
  deworming,
  hoofCutting,
  hairTrimming,
  monthlyWeight,
  pendingPayment,
  health,
}

extension PalaiReminderTypeExtension on PalaiReminderType {
  String get value {
    switch (this) {
      case PalaiReminderType.vaccination:
        return 'vaccination';

      case PalaiReminderType.deworming:
        return 'deworming';

      case PalaiReminderType.hoofCutting:
        return 'hoofCutting';

      case PalaiReminderType.hairTrimming:
        return 'hairTrimming';

      case PalaiReminderType.monthlyWeight:
        return 'monthlyWeight';

      case PalaiReminderType.pendingPayment:
        return 'pendingPayment';

      case PalaiReminderType.health:
        return 'health';
    }
  }

  String get label {
    switch (this) {
      case PalaiReminderType.vaccination:
        return 'Vaccination';

      case PalaiReminderType.deworming:
        return 'Deworming';

      case PalaiReminderType.hoofCutting:
        return 'Hoof Cutting';

      case PalaiReminderType.hairTrimming:
        return 'Hair Trimming';

      case PalaiReminderType.monthlyWeight:
        return 'Weight';

      case PalaiReminderType.pendingPayment:
        return 'Pending Payment';

      case PalaiReminderType.health:
        return 'Health';
    }
  }
}


// ============================================================================
// BILL STATUS
// ============================================================================

enum PalaiBillStatus {
  pending,
  partial,
  paid,
  cancelled,
}

extension PalaiBillStatusExtension on PalaiBillStatus {
  String get value {
    switch (this) {
      case PalaiBillStatus.pending:
        return 'pending';

      case PalaiBillStatus.partial:
        return 'partial';

      case PalaiBillStatus.paid:
        return 'paid';

      case PalaiBillStatus.cancelled:
        return 'cancelled';
    }
  }
}


// ============================================================================
// CUSTOMER PALAI SETTINGS
// ============================================================================
//
// These settings control reminders for a specific customer.
//
// Example:
//
// Customer A
// Vaccination = 180 days
// Hoof = 45 days
// Hair = 30 days
//
// Customer B
// Vaccination = 365 days
// Hoof = 30 days
// Hair = 60 days
//
// The reminder engine will use these settings later.
//
// ============================================================================

class PalaiCustomerSettings {
  final String customerId;

  /// 0 = disabled.
  final int vaccinationReminderDays;

  /// 0 = disabled.
  final int dewormingReminderDays;

  /// Usually 30 or 45 days.
  final int hoofCuttingReminderDays;

  /// 0 = disabled.
  final int hairTrimmingReminderDays;

  /// Usually 30 days.
  final int monthlyWeightReminderDays;

  final bool remindersEnabled;

  final DateTime updatedAt;

  const PalaiCustomerSettings({
    required this.customerId,
    this.vaccinationReminderDays = 0,
    this.dewormingReminderDays = 0,
    this.hoofCuttingReminderDays = 45,
    this.hairTrimmingReminderDays = 0,
    this.monthlyWeightReminderDays = 30,
    this.remindersEnabled = true,
    required this.updatedAt,
  });

  factory PalaiCustomerSettings.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PalaiCustomerSettings(
      customerId:
      (data['customerId'] ?? doc.id).toString(),

      vaccinationReminderDays:
      _toInt(data['vaccinationReminderDays']),

      dewormingReminderDays:
      _toInt(data['dewormingReminderDays']),

      hoofCuttingReminderDays:
      _toInt(
        data['hoofCuttingReminderDays'],
        fallback: 45,
      ),

      hairTrimmingReminderDays:
      _toInt(data['hairTrimmingReminderDays']),

      monthlyWeightReminderDays:
      _toInt(
        data['monthlyWeightReminderDays'],
        fallback: 30,
      ),

      remindersEnabled:
      data['remindersEnabled'] as bool? ?? true,

      updatedAt:
      _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,

      'vaccinationReminderDays':
      vaccinationReminderDays,

      'dewormingReminderDays':
      dewormingReminderDays,

      'hoofCuttingReminderDays':
      hoofCuttingReminderDays,

      'hairTrimmingReminderDays':
      hairTrimmingReminderDays,

      'monthlyWeightReminderDays':
      monthlyWeightReminderDays,

      'remindersEnabled':
      remindersEnabled,

      'updatedAt':
      Timestamp.fromDate(updatedAt),
    };
  }

  PalaiCustomerSettings copyWith({
    int? vaccinationReminderDays,
    int? dewormingReminderDays,
    int? hoofCuttingReminderDays,
    int? hairTrimmingReminderDays,
    int? monthlyWeightReminderDays,
    bool? remindersEnabled,
  }) {
    return PalaiCustomerSettings(
      customerId: customerId,

      vaccinationReminderDays:
      vaccinationReminderDays ??
          this.vaccinationReminderDays,

      dewormingReminderDays:
      dewormingReminderDays ??
          this.dewormingReminderDays,

      hoofCuttingReminderDays:
      hoofCuttingReminderDays ??
          this.hoofCuttingReminderDays,

      hairTrimmingReminderDays:
      hairTrimmingReminderDays ??
          this.hairTrimmingReminderDays,

      monthlyWeightReminderDays:
      monthlyWeightReminderDays ??
          this.monthlyWeightReminderDays,

      remindersEnabled:
      remindersEnabled ??
          this.remindersEnabled,

      updatedAt: DateTime.now(),
    );
  }
}


// ============================================================================
// WEIGHT RECORD
// ============================================================================

class GoatWeightRecord {
  final String id;

  final String goatId;

  final double weight;

  /// Difference from the previous weight.
  final double? weightGain;

  /// Percentage growth from previous record.
  final double? growthPercentage;

  final String notes;

  final DateTime recordedAt;

  const GoatWeightRecord({
    required this.id,
    required this.goatId,
    required this.weight,
    this.weightGain,
    this.growthPercentage,
    this.notes = '',
    required this.recordedAt,
  });

  factory GoatWeightRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return GoatWeightRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      weight:
      _toDouble(data['weight']),

      weightGain:
      _toNullableDouble(data['weightGain']),

      growthPercentage:
      _toNullableDouble(
        data['growthPercentage'],
      ),

      notes:
      _toStringValue(data['notes']),

      recordedAt:
      _toDate(data['recordedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,

      'weight': weight,

      'weightGain': weightGain,

      'growthPercentage':
      growthPercentage,

      'notes': notes,

      'recordedAt':
      Timestamp.fromDate(recordedAt),
    };
  }
}


// ============================================================================
// HEALTH RECORD
// ============================================================================
//
// This represents a general health observation/checkup.
//
// Vaccination, medicine, hoof, hair etc. DO NOT get stored here anymore.
// They have their own models below.
//
// ============================================================================

class GoatHealthRecord {
  final String id;

  final String goatId;

  /// Healthy
  /// Under Observation
  /// Sick
  /// Under Treatment
  /// Critical
  final String healthStatus;

  final String bodyConditionScore;

  final String symptoms;

  final String diagnosis;

  final String doctorName;

  final String doctorNotes;

  final DateTime recordedAt;

  const GoatHealthRecord({
    required this.id,
    required this.goatId,
    required this.healthStatus,
    this.bodyConditionScore = '',
    this.symptoms = '',
    this.diagnosis = '',
    this.doctorName = '',
    this.doctorNotes = '',
    required this.recordedAt,
  });

  factory GoatHealthRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return GoatHealthRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      healthStatus:
      _toStringValue(
        data['healthStatus'],
      ).isEmpty
          ? 'Healthy'
          : _toStringValue(
        data['healthStatus'],
      ),

      bodyConditionScore:
      _toStringValue(
        data['bodyConditionScore'],
      ),

      symptoms:
      _toStringValue(data['symptoms']),

      diagnosis:
      _toStringValue(data['diagnosis']),

      doctorName:
      _toStringValue(data['doctorName']),

      doctorNotes:
      _toStringValue(data['doctorNotes']),

      recordedAt:
      _toDate(data['recordedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,

      'healthStatus':
      healthStatus,

      'bodyConditionScore':
      bodyConditionScore,

      'symptoms':
      symptoms,

      'diagnosis':
      diagnosis,

      'doctorName':
      doctorName,

      'doctorNotes':
      doctorNotes,

      'recordedAt':
      Timestamp.fromDate(recordedAt),
    };
  }
}


// ============================================================================
// VACCINATION RECORD
// ============================================================================

class VaccinationRecord {
  final String id;

  final String goatId;

  final String vaccineName;

  final String batchNumber;

  final String dose;

  final DateTime administeredAt;

  /// Explicit next due date.
  ///
  /// The reminder engine will later calculate/use this together with
  /// customer settings.
  final DateTime? nextDueDate;

  final String administeredBy;

  final String notes;

  const VaccinationRecord({
    required this.id,
    required this.goatId,
    required this.vaccineName,
    this.batchNumber = '',
    this.dose = '',
    required this.administeredAt,
    this.nextDueDate,
    this.administeredBy = '',
    this.notes = '',
  });

  factory VaccinationRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return VaccinationRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      vaccineName:
      _toStringValue(data['vaccineName']),

      batchNumber:
      _toStringValue(data['batchNumber']),

      dose:
      _toStringValue(data['dose']),

      administeredAt:
      _toDate(data['administeredAt']),

      nextDueDate:
      _toNullableDate(
        data['nextDueDate'],
      ),

      administeredBy:
      _toStringValue(
        data['administeredBy'],
      ),

      notes:
      _toStringValue(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,

      'vaccineName':
      vaccineName,

      'batchNumber':
      batchNumber,

      'dose':
      dose,

      'administeredAt':
      Timestamp.fromDate(
        administeredAt,
      ),

      'nextDueDate':
      nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),

      'administeredBy':
      administeredBy,

      'notes':
      notes,
    };
  }
}


// ============================================================================
// DEWORMING RECORD
// ============================================================================

class DewormingRecord {
  final String id;

  final String goatId;

  final String medicineName;

  final String dose;

  final DateTime administeredAt;

  final DateTime? nextDueDate;

  final String administeredBy;

  final String notes;

  const DewormingRecord({
    required this.id,
    required this.goatId,
    required this.medicineName,
    this.dose = '',
    required this.administeredAt,
    this.nextDueDate,
    this.administeredBy = '',
    this.notes = '',
  });

  factory DewormingRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return DewormingRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      medicineName:
      _toStringValue(
        data['medicineName'],
      ),

      dose:
      _toStringValue(data['dose']),

      administeredAt:
      _toDate(data['administeredAt']),

      nextDueDate:
      _toNullableDate(
        data['nextDueDate'],
      ),

      administeredBy:
      _toStringValue(
        data['administeredBy'],
      ),

      notes:
      _toStringValue(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,

      'medicineName':
      medicineName,

      'dose':
      dose,

      'administeredAt':
      Timestamp.fromDate(
        administeredAt,
      ),

      'nextDueDate':
      nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),

      'administeredBy':
      administeredBy,

      'notes':
      notes,
    };
  }
}


// ============================================================================
// HOOF CUTTING RECORD
// ============================================================================
//
// Khud cutting.
//
// Default reminder can be 30 or 45 days depending on customer setting.
//
// ============================================================================

class HoofCuttingRecord {
  final String id;

  final String goatId;

  final DateTime cutAt;

  final DateTime? nextDueDate;

  /// 30 or 45 days normally.
  final int? reminderIntervalDays;

  final String performedBy;

  final String notes;

  const HoofCuttingRecord({
    required this.id,
    required this.goatId,
    required this.cutAt,
    this.nextDueDate,
    this.reminderIntervalDays,
    this.performedBy = '',
    this.notes = '',
  });

  factory HoofCuttingRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return HoofCuttingRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      cutAt:
      _toDate(data['cutAt']),

      nextDueDate:
      _toNullableDate(
        data['nextDueDate'],
      ),

      reminderIntervalDays:
      _toNullableInt(
        data['reminderIntervalDays'],
      ),

      performedBy:
      _toStringValue(
        data['performedBy'],
      ),

      notes:
      _toStringValue(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId':
      goatId,

      'cutAt':
      Timestamp.fromDate(cutAt),

      'nextDueDate':
      nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),

      'reminderIntervalDays':
      reminderIntervalDays,

      'performedBy':
      performedBy,

      'notes':
      notes,
    };
  }
}


// ============================================================================
// HAIR TRIMMING RECORD
// ============================================================================

class HairTrimmingRecord {
  final String id;

  final String goatId;

  final DateTime trimmedAt;

  final DateTime? nextDueDate;

  /// Customer-specific reminder interval.
  final int? reminderIntervalDays;

  final String performedBy;

  final String notes;

  const HairTrimmingRecord({
    required this.id,
    required this.goatId,
    required this.trimmedAt,
    this.nextDueDate,
    this.reminderIntervalDays,
    this.performedBy = '',
    this.notes = '',
  });

  factory HairTrimmingRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return HairTrimmingRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      trimmedAt:
      _toDate(data['trimmedAt']),

      nextDueDate:
      _toNullableDate(
        data['nextDueDate'],
      ),

      reminderIntervalDays:
      _toNullableInt(
        data['reminderIntervalDays'],
      ),

      performedBy:
      _toStringValue(
        data['performedBy'],
      ),

      notes:
      _toStringValue(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId':
      goatId,

      'trimmedAt':
      Timestamp.fromDate(trimmedAt),

      'nextDueDate':
      nextDueDate == null
          ? null
          : Timestamp.fromDate(
        nextDueDate!,
      ),

      'reminderIntervalDays':
      reminderIntervalDays,

      'performedBy':
      performedBy,

      'notes':
      notes,
    };
  }
}


// ============================================================================
// MEDICINE RECORD
// ============================================================================

class MedicineRecord {
  final String id;

  final String goatId;

  final String medicineName;

  final String reason;

  final String dosage;

  final String frequency;

  final DateTime startDate;

  final DateTime? endDate;

  final String prescribedBy;

  final String notes;

  const MedicineRecord({
    required this.id,
    required this.goatId,
    required this.medicineName,
    this.reason = '',
    this.dosage = '',
    this.frequency = '',
    required this.startDate,
    this.endDate,
    this.prescribedBy = '',
    this.notes = '',
  });

  factory MedicineRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return MedicineRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      medicineName:
      _toStringValue(
        data['medicineName'],
      ),

      reason:
      _toStringValue(data['reason']),

      dosage:
      _toStringValue(data['dosage']),

      frequency:
      _toStringValue(data['frequency']),

      startDate:
      _toDate(data['startDate']),

      endDate:
      _toNullableDate(
        data['endDate'],
      ),

      prescribedBy:
      _toStringValue(
        data['prescribedBy'],
      ),

      notes:
      _toStringValue(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId':
      goatId,

      'medicineName':
      medicineName,

      'reason':
      reason,

      'dosage':
      dosage,

      'frequency':
      frequency,

      'startDate':
      Timestamp.fromDate(
        startDate,
      ),

      'endDate':
      endDate == null
          ? null
          : Timestamp.fromDate(
        endDate!,
      ),

      'prescribedBy':
      prescribedBy,

      'notes':
      notes,
    };
  }
}


// ============================================================================
// CHECKUP RECORD
// ============================================================================
//
// A dedicated checkup record.
//
// This replaces the old approach where checkup + vaccination + medicine
// information were all placed into HealthRecordEntry.
//
// ============================================================================

class GoatCheckupRecord {
  final String id;

  final String goatId;

  final double? weight;

  final String healthStatus;

  final String symptoms;

  final String diagnosis;

  final String bodyConditionScore;

  final String doctorName;

  final String doctorNotes;

  final DateTime checkupDate;

  const GoatCheckupRecord({
    required this.id,
    required this.goatId,
    this.weight,
    required this.healthStatus,
    this.symptoms = '',
    this.diagnosis = '',
    this.bodyConditionScore = '',
    this.doctorName = '',
    this.doctorNotes = '',
    required this.checkupDate,
  });

  factory GoatCheckupRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return GoatCheckupRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      weight:
      _toNullableDouble(
        data['weight'],
      ),

      healthStatus:
      _toStringValue(
        data['healthStatus'],
      ).isEmpty
          ? 'Healthy'
          : _toStringValue(
        data['healthStatus'],
      ),

      symptoms:
      _toStringValue(
        data['symptoms'],
      ),

      diagnosis:
      _toStringValue(
        data['diagnosis'],
      ),

      bodyConditionScore:
      _toStringValue(
        data['bodyConditionScore'],
      ),

      doctorName:
      _toStringValue(
        data['doctorName'],
      ),

      doctorNotes:
      _toStringValue(
        data['doctorNotes'],
      ),

      checkupDate:
      _toDate(data['checkupDate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId':
      goatId,

      'weight':
      weight,

      'healthStatus':
      healthStatus,

      'symptoms':
      symptoms,

      'diagnosis':
      diagnosis,

      'bodyConditionScore':
      bodyConditionScore,

      'doctorName':
      doctorName,

      'doctorNotes':
      doctorNotes,

      'checkupDate':
      Timestamp.fromDate(
        checkupDate,
      ),
    };
  }
}


// ============================================================================
// MONTHLY PHOTO RECORD
// ============================================================================
//
// Monthly progress photos are separate from check-in/check-out photos.
//
// Existing PalaiGoat has before/after images. We will keep those for the
// boarding lifecycle and use this model for monthly progress history.
//
// ============================================================================

class MonthlyPhotoRecord {
  final String id;

  final String goatId;

  /// First day of the month represented by this record.
  final DateTime month;

  final String frontImageUrl;

  final String sideImageUrl;

  final String backImageUrl;

  final String? imageUrl;

  final String notes;

  final DateTime capturedAt;

  const MonthlyPhotoRecord({
    required this.id,
    required this.goatId,
    required this.month,
    this.frontImageUrl = '',
    this.sideImageUrl = '',
    this.backImageUrl = '',
    this.imageUrl,
    this.notes = '',
    required this.capturedAt,
  });

  factory MonthlyPhotoRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return MonthlyPhotoRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      month:
      _toMonth(data['month']),

      frontImageUrl:
      _toStringValue(
        data['frontImageUrl'],
      ),

      sideImageUrl:
      _toStringValue(
        data['sideImageUrl'],
      ),

      backImageUrl:
      _toStringValue(
        data['backImageUrl'],
      ),

      imageUrl:
      data['imageUrl']?.toString(),

      notes:
      _toStringValue(data['notes']),

      capturedAt:
      _toDate(data['capturedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId':
      goatId,

      'month':
      Timestamp.fromDate(
        DateTime(
          month.year,
          month.month,
          1,
        ),
      ),

      'frontImageUrl':
      frontImageUrl,

      'sideImageUrl':
      sideImageUrl,

      'backImageUrl':
      backImageUrl,

      'imageUrl':
      imageUrl,

      'notes':
      notes,

      'capturedAt':
      Timestamp.fromDate(
        capturedAt,
      ),
    };
  }
}


// ============================================================================
// CHECK-IN / CHECK-OUT HISTORY
// ============================================================================
//
// IMPORTANT:
//
// There will NOT be a "Today's Check-In / Check-Out" feature in the new
// Palai flow.
//
// This model only records the actual boarding lifecycle events.
//
// Example:
//
// 10 Jan 2026 -> Check-In
// 05 Apr 2026 -> Check-Out
//
// The customer profile can show the history.
//
// ============================================================================

class CheckInOutRecord {
  final String id;

  final String goatId;

  final String customerId;

  final PalaiCheckInOutType type;

  final DateTime occurredAt;

  final double? weight;

  final String healthStatus;

  final String deliveryStatus;

  final String notes;

  const CheckInOutRecord({
    required this.id,
    required this.goatId,
    required this.customerId,
    required this.type,
    required this.occurredAt,
    this.weight,
    this.healthStatus = '',
    this.deliveryStatus = '',
    this.notes = '',
  });

  factory CheckInOutRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final rawType =
    _toStringValue(data['type']);

    return CheckInOutRecord(
      id: doc.id,

      goatId:
      _toStringValue(data['goatId']),

      customerId:
      _toStringValue(
        data['customerId'],
      ),

      type:
      rawType == 'checkOut'
          ? PalaiCheckInOutType.checkOut
          : PalaiCheckInOutType.checkIn,

      occurredAt:
      _toDate(data['occurredAt']),

      weight:
      _toNullableDouble(
        data['weight'],
      ),

      healthStatus:
      _toStringValue(
        data['healthStatus'],
      ),

      deliveryStatus:
      _toStringValue(
        data['deliveryStatus'],
      ),

      notes:
      _toStringValue(data['notes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId':
      goatId,

      'customerId':
      customerId,

      'type':
      type.value,

      'occurredAt':
      Timestamp.fromDate(
        occurredAt,
      ),

      'weight':
      weight,

      'healthStatus':
      healthStatus,

      'deliveryStatus':
      deliveryStatus,

      'notes':
      notes,
    };
  }
}


// ============================================================================
// MONTHLY BILL
// ============================================================================

class PalaiBill {
  final String id;

  final String customerId;

  final String billNumber;

  /// Example: 2026-08
  final String periodMonth;

  final double monthlyCharges;

  final double transportCharges;

  final double discount;

  final double previousPending;

  final double advanceApplied;

  final double totalDue;

  final double amountPaid;

  final double pendingAfter;

  final double advanceAfter;

  final PalaiBillStatus status;

  final String note;

  final DateTime createdAt;

  const PalaiBill({
    required this.id,
    required this.customerId,
    required this.billNumber,
    required this.periodMonth,
    required this.monthlyCharges,
    this.transportCharges = 0,
    this.discount = 0,
    this.previousPending = 0,
    this.advanceApplied = 0,
    required this.totalDue,
    this.amountPaid = 0,
    required this.pendingAfter,
    this.advanceAfter = 0,
    required this.status,
    this.note = '',
    required this.createdAt,
  });

  factory PalaiBill.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PalaiBill(
      id: doc.id,

      customerId:
      _toStringValue(
        data['customerId'],
      ),

      billNumber:
      _toStringValue(
        data['billNumber'],
      ).isEmpty
          ? doc.id
          : _toStringValue(
        data['billNumber'],
      ),

      periodMonth:
      _toStringValue(
        data['periodMonth'],
      ),

      monthlyCharges:
      _toDouble(
        data['monthlyCharges'],
      ),

      transportCharges:
      _toDouble(
        data['transportCharges'],
      ),

      discount:
      _toDouble(
        data['discount'],
      ),

      previousPending:
      _toDouble(
        data['previousPending'],
      ),

      advanceApplied:
      _toDouble(
        data['advanceApplied'],
      ),

      totalDue:
      _toDouble(
        data['totalDue'],
      ),

      amountPaid:
      _toDouble(
        data['amountPaid'],
      ),

      pendingAfter:
      _toDouble(
        data['pendingAfter'],
      ),

      advanceAfter:
      _toDouble(
        data['advanceAfter'],
      ),

      status:
      _toBillStatus(
        data['status'],
      ),

      note:
      _toStringValue(
        data['note'],
      ),

      createdAt:
      _toDate(
        data['createdAt'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId':
      customerId,

      'billNumber':
      billNumber,

      'periodMonth':
      periodMonth,

      'monthlyCharges':
      monthlyCharges,

      'transportCharges':
      transportCharges,

      'discount':
      discount,

      'previousPending':
      previousPending,

      'advanceApplied':
      advanceApplied,

      'totalDue':
      totalDue,

      'amountPaid':
      amountPaid,

      'pendingAfter':
      pendingAfter,

      'advanceAfter':
      advanceAfter,

      'status':
      status.value,

      'note':
      note,

      'createdAt':
      Timestamp.fromDate(
        createdAt,
      ),
    };
  }
}


// ============================================================================
// PAYMENT
// ============================================================================
//
// Payments are immutable financial history.
//
// We do NOT simply read the customer's current pendingAmount to display
// historical payment information.
//
// Each payment stores its own before/after snapshot.
//
// ============================================================================

class PalaiPayment {
  final String id;

  final String customerId;

  final String billId;

  final String paymentNumber;

  final double amount;

  final double amountAppliedToBill;

  final double pendingBefore;

  final double pendingAfter;

  final double advanceBefore;

  final double advanceAdded;

  final double advanceAfter;

  final String paymentMethod;

  final String note;

  final DateTime paidAt;

  const PalaiPayment({
    required this.id,
    required this.customerId,
    this.billId = '',
    required this.paymentNumber,
    required this.amount,
    this.amountAppliedToBill = 0,
    this.pendingBefore = 0,
    this.pendingAfter = 0,
    this.advanceBefore = 0,
    this.advanceAdded = 0,
    this.advanceAfter = 0,
    required this.paymentMethod,
    this.note = '',
    required this.paidAt,
  });

  factory PalaiPayment.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PalaiPayment(
      id: doc.id,

      customerId:
      _toStringValue(
        data['customerId'],
      ),

      billId:
      _toStringValue(
        data['billId'],
      ),

      paymentNumber:
      _toStringValue(
        data['paymentNumber'],
      ).isEmpty
          ? doc.id
          : _toStringValue(
        data['paymentNumber'],
      ),

      amount:
      _toDouble(
        data['amount'] ??
            data['amountReceived'],
      ),

      amountAppliedToBill:
      _toDouble(
        data['amountAppliedToBill'] ??
            data['amountAppliedToPending'],
      ),

      pendingBefore:
      _toDouble(
        data['pendingBefore'],
      ),

      pendingAfter:
      _toDouble(
        data['pendingAfter'],
      ),

      advanceBefore:
      _toDouble(
        data['advanceBefore'],
      ),

      advanceAdded:
      _toDouble(
        data['advanceAdded'] ??
            data['advanceAmount'],
      ),

      advanceAfter:
      _toDouble(
        data['advanceAfter'],
      ),

      paymentMethod:
      _toStringValue(
        data['paymentMethod'],
      ),

      note:
      _toStringValue(
        data['note'],
      ),

      paidAt:
      _toDate(
        data['date'] ??
            data['createdAt'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId':
      customerId,

      'billId':
      billId,

      'paymentNumber':
      paymentNumber,

      'amount':
      amount,

      'amountAppliedToBill':
      amountAppliedToBill,

      'pendingBefore':
      pendingBefore,

      'pendingAfter':
      pendingAfter,

      'advanceBefore':
      advanceBefore,

      'advanceAdded':
      advanceAdded,

      'advanceAfter':
      advanceAfter,

      'paymentMethod':
      paymentMethod,

      'note':
      note,

      'date':
      Timestamp.fromDate(
        paidAt,
      ),
    };
  }
}


// ============================================================================
// REMINDER
// ============================================================================
//
// Reminders are derived from actual records/settings.
//
// They are NOT the source of truth.
//
// Example:
//
// VaccinationRecord
//       ↓
// Customer Settings
//       ↓
// Reminder Engine
//       ↓
// PalaiReminder
//
// ============================================================================

class PalaiReminder {
  final String id;

  final String? customerId;

  final String? goatId;

  final PalaiReminderType type;

  final String title;

  final String message;

  final DateTime dueDate;

  final bool isCompleted;

  final bool isDismissed;

  /// ID of the record that caused this reminder.
  final String sourceRecordId;

  final DateTime createdAt;

  const PalaiReminder({
    required this.id,
    this.customerId,
    this.goatId,
    required this.type,
    required this.title,
    required this.message,
    required this.dueDate,
    this.isCompleted = false,
    this.isDismissed = false,
    this.sourceRecordId = '',
    required this.createdAt,
  });

  factory PalaiReminder.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PalaiReminder(
      id: doc.id,

      customerId:
      data['customerId']?.toString(),

      goatId:
      data['goatId']?.toString(),

      type:
      _toReminderType(
        data['type'],
      ),

      title:
      _toStringValue(
        data['title'],
      ),

      message:
      _toStringValue(
        data['message'],
      ),

      dueDate:
      _toDate(
        data['dueDate'],
      ),

      isCompleted:
      data['isCompleted'] as bool? ??
          false,

      isDismissed:
      data['isDismissed'] as bool? ??
          false,

      sourceRecordId:
      _toStringValue(
        data['sourceRecordId'],
      ),

      createdAt:
      _toDate(
        data['createdAt'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId':
      customerId,

      'goatId':
      goatId,

      'type':
      type.value,

      'title':
      title,

      'message':
      message,

      'dueDate':
      Timestamp.fromDate(
        dueDate,
      ),

      'isCompleted':
      isCompleted,

      'isDismissed':
      isDismissed,

      'sourceRecordId':
      sourceRecordId,

      'createdAt':
      Timestamp.fromDate(
        createdAt,
      ),
    };
  }
}


// ============================================================================
// FIRESTORE CONVERSION HELPERS
// ============================================================================

String _toStringValue(Object? value) {
  return value?.toString() ?? '';
}


double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(
    value?.toString() ?? '',
  ) ??
      0;
}


double? _toNullableDouble(Object? value) {
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


int _toInt(
    Object? value, {
      int fallback = 0,
    }) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value?.toString() ?? '',
  ) ??
      fallback;
}


int? _toNullableInt(Object? value) {
  if (value == null) {
    return null;
  }

  return _toInt(value);
}


DateTime _toDate(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  return DateTime.now();
}


DateTime? _toNullableDate(Object? value) {
  if (value == null) {
    return null;
  }

  return _toDate(value);
}


DateTime _toMonth(Object? value) {
  final date = _toDate(value);

  return DateTime(
    date.year,
    date.month,
    1,
  );
}


PalaiBillStatus _toBillStatus(
    Object? value,
    ) {
  final raw =
      value?.toString() ?? '';

  switch (raw) {
    case 'partial':
      return PalaiBillStatus.partial;

    case 'paid':
      return PalaiBillStatus.paid;

    case 'cancelled':
      return PalaiBillStatus.cancelled;

    case 'pending':
    default:
      return PalaiBillStatus.pending;
  }
}


PalaiReminderType _toReminderType(
    Object? value,
    ) {
  final raw =
      value?.toString() ?? '';

  switch (raw) {
    case 'vaccination':
      return PalaiReminderType.vaccination;

    case 'deworming':
      return PalaiReminderType.deworming;

    case 'hoofCutting':
      return PalaiReminderType.hoofCutting;

    case 'hairTrimming':
      return PalaiReminderType.hairTrimming;

    case 'monthlyWeight':
      return PalaiReminderType.monthlyWeight;

    case 'pendingPayment':
      return PalaiReminderType.pendingPayment;

    case 'health':
    default:
      return PalaiReminderType.health;
  }
}