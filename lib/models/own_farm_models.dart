import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A goat owned by the farm itself (as opposed to a customer's goat
/// boarded under Palai). Lives at `farms/{farmId}/ownFarmGoats/{id}`.
class OwnFarmGoat {
  final String id;
  final String goatCode; // e.g. OF-1001
  final String breed;
  final String gender;
  final String color;
  final DateTime dateOfBirth;
  final double birthWeight;
  final double currentWeight;
  final String healthStatus; // Healthy, Under Treatment, Sick, Quarantined
  final String motherCode;
  final String fatherCode;
  final String notes;
  final DateTime registeredAt;
  final bool isActive; // false once sold / deceased / removed

  /// Latest photo of the goat, stored as raw bytes directly on the
  /// document (Firestore `Blob`), same pattern used for Palai goats.
  final Uint8List? photo;
  final String? photoContentType;

  OwnFarmGoat({
    required this.id,
    required this.goatCode,
    required this.breed,
    required this.gender,
    required this.color,
    required this.dateOfBirth,
    required this.birthWeight,
    required this.currentWeight,
    required this.healthStatus,
    this.motherCode = '',
    this.fatherCode = '',
    this.notes = '',
    required this.registeredAt,
    this.isActive = true,
    this.photo,
    this.photoContentType,
  });

  int get ageInMonths {
    final now = DateTime.now();
    return (now.year - dateOfBirth.year) * 12 + (now.month - dateOfBirth.month);
  }

  @override
  bool operator ==(Object other) => other is OwnFarmGoat && other.id == id;

  @override
  int get hashCode => id.hashCode;

  factory OwnFarmGoat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final photoField = data['photo'];
    return OwnFarmGoat(
      id: doc.id,
      goatCode: data['goatCode'] ?? '',
      breed: data['breed'] ?? '',
      gender: data['gender'] ?? '',
      color: data['color'] ?? '',
      dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate() ?? DateTime.now(),
      birthWeight: (data['birthWeight'] ?? 0).toDouble(),
      currentWeight: (data['currentWeight'] ?? 0).toDouble(),
      healthStatus: data['healthStatus'] ?? 'Healthy',
      motherCode: data['motherCode'] ?? '',
      fatherCode: data['fatherCode'] ?? '',
      notes: data['notes'] ?? '',
      registeredAt: (data['registeredAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] ?? true,
      photo: photoField is Blob ? photoField.bytes : null,
      photoContentType: data['photoContentType'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'birthWeight': birthWeight,
      'currentWeight': currentWeight,
      'healthStatus': healthStatus,
      'motherCode': motherCode,
      'fatherCode': fatherCode,
      'notes': notes,
      'registeredAt': Timestamp.fromDate(registeredAt),
      'isActive': isActive,
    };
    if (photo != null) {
      map['photo'] = Blob(photo!);
      map['photoContentType'] = photoContentType ?? 'image/jpeg';
    }
    return map;
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'goatCode': goatCode,
      'breed': breed,
      'gender': gender,
      'color': color,
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'birthWeight': birthWeight,
      'healthStatus': healthStatus,
      'motherCode': motherCode,
      'fatherCode': fatherCode,
      'notes': notes,
      'isActive': isActive,
    };
  }
}

/// A single growth/weight-tracking entry logged against a farm goat.
class GrowthRecord {
  final String id;
  final double weight;
  final DateTime recordedAt;
  final String notes;

  GrowthRecord({
    required this.id,
    required this.weight,
    required this.recordedAt,
    this.notes = '',
  });

  factory GrowthRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return GrowthRecord(
      id: doc.id,
      weight: (data['weight'] ?? 0).toDouble(),
      recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'weight': weight,
      'recordedAt': Timestamp.fromDate(recordedAt),
      'notes': notes,
    };
  }
}

/// A health/care event for a farm goat: vaccination, deworming, hoof
/// cutting (khud cutting), hair trimming, or general medicine/treatment.
enum HealthEventType { vaccination, deworming, hoofCutting, hairTrimming, medicine, checkup }

class HealthEvent {
  final String id;
  final HealthEventType type;
  final String description;
  final DateTime date;
  final DateTime? nextDueDate; // used to power the reminders
  final String doctorNotes;

  HealthEvent({
    required this.id,
    required this.type,
    required this.description,
    required this.date,
    this.nextDueDate,
    this.doctorNotes = '',
  });

  factory HealthEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return HealthEvent(
      id: doc.id,
      type: HealthEventType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => HealthEventType.checkup,
      ),
      description: data['description'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nextDueDate: (data['nextDueDate'] as Timestamp?)?.toDate(),
      doctorNotes: data['doctorNotes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'description': description,
      'date': Timestamp.fromDate(date),
      'nextDueDate': nextDueDate != null ? Timestamp.fromDate(nextDueDate!) : null,
      'doctorNotes': doctorNotes,
    };
  }

  String get label {
    switch (type) {
      case HealthEventType.vaccination:
        return 'Vaccination';
      case HealthEventType.deworming:
        return 'Deworming';
      case HealthEventType.hoofCutting:
        return 'Hoof Cutting';
      case HealthEventType.hairTrimming:
        return 'Hair Trimming';
      case HealthEventType.medicine:
        return 'Medicine';
      case HealthEventType.checkup:
        return 'Checkup';
    }
  }
}

/// A breeding record for a farm goat (mating, pregnancy, kidding).
class BreedingRecord {
  final String id;
  final String partnerCode; // buck/doe code used for mating
  final DateTime matingDate;
  final DateTime? expectedKiddingDate;
  final DateTime? actualKiddingDate;
  final int kidsCount;
  final String notes;

  BreedingRecord({
    required this.id,
    required this.partnerCode,
    required this.matingDate,
    this.expectedKiddingDate,
    this.actualKiddingDate,
    this.kidsCount = 0,
    this.notes = '',
  });

  factory BreedingRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return BreedingRecord(
      id: doc.id,
      partnerCode: data['partnerCode'] ?? '',
      matingDate: (data['matingDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expectedKiddingDate: (data['expectedKiddingDate'] as Timestamp?)?.toDate(),
      actualKiddingDate: (data['actualKiddingDate'] as Timestamp?)?.toDate(),
      kidsCount: data['kidsCount'] ?? 0,
      notes: data['notes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'partnerCode': partnerCode,
      'matingDate': Timestamp.fromDate(matingDate),
      'expectedKiddingDate': expectedKiddingDate != null ? Timestamp.fromDate(expectedKiddingDate!) : null,
      'actualKiddingDate': actualKiddingDate != null ? Timestamp.fromDate(actualKiddingDate!) : null,
      'kidsCount': kidsCount,
      'notes': notes,
    };
  }
}

/// A feed/health expense logged against a farm goat (or the farm's own
/// herd generally, when [goatId] is empty).
class OwnFarmExpense {
  final String id;
  final String goatId;
  final String category; // Feed, Medicine, Vet Visit, Other
  final double amount;
  final DateTime date;
  final String notes;

  OwnFarmExpense({
    required this.id,
    required this.goatId,
    required this.category,
    required this.amount,
    required this.date,
    this.notes = '',
  });

  factory OwnFarmExpense.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return OwnFarmExpense(
      id: doc.id,
      goatId: data['goatId'] ?? '',
      category: data['category'] ?? 'Other',
      amount: (data['amount'] ?? 0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,
      'category': category,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'notes': notes,
    };
  }
}
