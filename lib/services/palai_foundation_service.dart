import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/palai_record_models.dart';

/// ============================================================================
/// PALAI FOUNDATION SERVICE
/// ============================================================================
///
/// This service belongs to the NEW Palai architecture.
///
/// IMPORTANT:
/// - It does NOT replace FirestoreService yet.
/// - It does NOT delete or migrate existing data.
/// - It uses the existing farm/customer/goat hierarchy.
/// - Existing application screens can continue working normally.
///
/// Existing hierarchy:
///
/// farms/{farmId}
///   └── palaiCustomers/{customerId}
///         └── goats/{goatId}
///
/// New historical records:
///
/// goats/{goatId}
///   ├── palaiWeightRecords
///   ├── palaiHealthRecords
///   ├── vaccinations
///   ├── deworming
///   ├── hoofCutting
///   ├── hairTrimming
///   ├── medicines
///   ├── checkups
///   ├── monthlyPhotosV2
///   └── checkInOutHistory
///
/// Customer settings:
///
/// palaiCustomers/{customerId}/palaiSettings/preferences
///
/// Reminders:
///
/// farms/{farmId}/palaiReminders
///
/// ============================================================================

class PalaiFoundationService {
  PalaiFoundationService._();

  static final PalaiFoundationService instance =
  PalaiFoundationService._();

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  static const Duration timeout =
  Duration(seconds: 15);

  // ==========================================================================
  // ROOT REFERENCES
  // ==========================================================================

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  DocumentReference<Map<String, dynamic>> _farm(
      String farmId,
      ) {
    return _farms().doc(farmId);
  }

  CollectionReference<Map<String, dynamic>> _customers(
      String farmId,
      ) {
    return _farm(farmId).collection('palaiCustomers');
  }

  DocumentReference<Map<String, dynamic>> _customer(
      String farmId,
      String customerId,
      ) {
    return _customers(farmId).doc(customerId);
  }

  CollectionReference<Map<String, dynamic>> _goats(
      String farmId,
      String customerId,
      ) {
    return _customer(
      farmId,
      customerId,
    ).collection('goats');
  }

  DocumentReference<Map<String, dynamic>> _goat(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goats(
      farmId,
      customerId,
    ).doc(goatId);
  }

  // ==========================================================================
  // CUSTOMER SETTINGS
  // ==========================================================================

  DocumentReference<Map<String, dynamic>>
  _customerSettingsDocument(
      String farmId,
      String customerId,
      ) {
    return _customer(
      farmId,
      customerId,
    )
        .collection('palaiSettings')
        .doc('preferences');
  }

  /// Gets customer-specific reminder settings.
  ///
  /// If the customer has never configured settings, sensible defaults are
  /// returned without writing anything to Firestore.
  Future<PalaiCustomerSettings> getCustomerSettings({
    required String farmId,
    required String customerId,
  }) async {
    final snapshot = await _customerSettingsDocument(
      farmId,
      customerId,
    ).get().timeout(timeout);

    if (!snapshot.exists) {
      return PalaiCustomerSettings(
        customerId: customerId,
        vaccinationReminderDays: 0,
        dewormingReminderDays: 0,
        hoofCuttingReminderDays: 45,
        hairTrimmingReminderDays: 0,
        monthlyWeightReminderDays: 30,
        remindersEnabled: true,
        updatedAt: DateTime.now(),
      );
    }

    return PalaiCustomerSettings.fromDoc(
      snapshot,
    );
  }

  /// Saves customer-specific reminder settings.
  Future<void> saveCustomerSettings(
      PalaiCustomerSettings settings, {
        required String farmId,
      }) async {
    await _customerSettingsDocument(
      farmId,
      settings.customerId,
    ).set(
      settings.toMap(),
      SetOptions(merge: true),
    ).timeout(timeout);
  }

  Stream<PalaiCustomerSettings> customerSettingsStream({
    required String farmId,
    required String customerId,
  }) {
    return _customerSettingsDocument(
      farmId,
      customerId,
    ).snapshots().map(
          (snapshot) {
        if (!snapshot.exists) {
          return PalaiCustomerSettings(
            customerId: customerId,
            hoofCuttingReminderDays: 45,
            monthlyWeightReminderDays: 30,
            remindersEnabled: true,
            updatedAt: DateTime.now(),
          );
        }

        return PalaiCustomerSettings.fromDoc(
          snapshot,
        );
      },
    );
  }

  // ==========================================================================
  // WEIGHT
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _weightRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('palaiWeightRecords');
  }

  Future<String> addWeightRecord(
      GoatWeightRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final collection = _weightRecords(
      farmId,
      customerId,
      record.goatId,
    );

    final ref = await collection.add(
      record.toMap(),
    ).timeout(timeout);

    // Update the goat's current weight too.
    await _goat(
      farmId,
      customerId,
      record.goatId,
    ).update({
      'currentWeight': record.weight,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);

    return ref.id;
  }

  Stream<List<GoatWeightRecord>> weightRecordsStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _weightRecords(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'recordedAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        GoatWeightRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // GENERAL HEALTH
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _healthRecords(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('palaiHealthRecords');
  }

  Future<String> addHealthRecord(
      GoatHealthRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _healthRecords(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    await _goat(
      farmId,
      customerId,
      record.goatId,
    ).update({
      'healthStatus': record.healthStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);

    return ref.id;
  }

  Stream<List<GoatHealthRecord>> healthRecordsStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _healthRecords(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'recordedAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        GoatHealthRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // VACCINATION
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _vaccinations(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('vaccinations');
  }

  Future<String> addVaccination(
      VaccinationRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _vaccinations(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<VaccinationRecord>> vaccinationsStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _vaccinations(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'administeredAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        VaccinationRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // DEWORMING
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _deworming(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('deworming');
  }

  Future<String> addDeworming(
      DewormingRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _deworming(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<DewormingRecord>> dewormingStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _deworming(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'administeredAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        DewormingRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // HOOF CUTTING
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _hoofCutting(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('hoofCutting');
  }

  Future<String> addHoofCutting(
      HoofCuttingRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _hoofCutting(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<HoofCuttingRecord>> hoofCuttingStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _hoofCutting(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'cutAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        HoofCuttingRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // HAIR TRIMMING
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _hairTrimming(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('hairTrimming');
  }

  Future<String> addHairTrimming(
      HairTrimmingRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _hairTrimming(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<HairTrimmingRecord>> hairTrimmingStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _hairTrimming(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'trimmedAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        HairTrimmingRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // MEDICINE
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _medicines(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('medicines');
  }

  Future<String> addMedicine(
      MedicineRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _medicines(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<MedicineRecord>> medicinesStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _medicines(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'startDate',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        MedicineRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // CHECKUP
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _checkups(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('checkups');
  }

  Future<String> addCheckup(
      GoatCheckupRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _checkups(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    // A checkup is also the latest health observation.
    await _goat(
      farmId,
      customerId,
      record.goatId,
    ).update({
      'healthStatus': record.healthStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);

    if (record.weight != null) {
      await _goat(
        farmId,
        customerId,
        record.goatId,
      ).update({
        'currentWeight': record.weight,
      }).timeout(timeout);
    }

    return ref.id;
  }

  Stream<List<GoatCheckupRecord>> checkupsStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _checkups(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'checkupDate',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        GoatCheckupRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // MONTHLY PHOTOS
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _monthlyPhotos(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('monthlyPhotosV2');
  }

  Future<String> addMonthlyPhoto(
      MonthlyPhotoRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _monthlyPhotos(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<MonthlyPhotoRecord>> monthlyPhotosStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _monthlyPhotos(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'month',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        MonthlyPhotoRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // CHECK-IN / CHECK-OUT HISTORY
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _checkInOutHistory(
      String farmId,
      String customerId,
      String goatId,
      ) {
    return _goat(
      farmId,
      customerId,
      goatId,
    ).collection('checkInOutHistory');
  }

  Future<String> addCheckInOutRecord(
      CheckInOutRecord record, {
        required String farmId,
        required String customerId,
      }) async {
    final ref = await _checkInOutHistory(
      farmId,
      customerId,
      record.goatId,
    )
        .add(record.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Stream<List<CheckInOutRecord>> checkInOutHistoryStream({
    required String farmId,
    required String customerId,
    required String goatId,
  }) {
    return _checkInOutHistory(
      farmId,
      customerId,
      goatId,
    )
        .orderBy(
      'occurredAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        CheckInOutRecord.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // REMINDERS
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
  _reminders(
      String farmId,
      ) {
    return _farm(farmId)
        .collection('palaiReminders');
  }

  Future<String> addReminder(
      PalaiReminder reminder, {
        required String farmId,
      }) async {
    final ref = await _reminders(
      farmId,
    )
        .add(reminder.toMap())
        .timeout(timeout);

    return ref.id;
  }

  Future<void> completeReminder({
    required String farmId,
    required String reminderId,
  }) async {
    await _reminders(
      farmId,
    )
        .doc(reminderId)
        .update({
      'isCompleted': true,
      'completedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  Future<void> dismissReminder({
    required String farmId,
    required String reminderId,
  }) async {
    await _reminders(
      farmId,
    )
        .doc(reminderId)
        .update({
      'isDismissed': true,
      'dismissedAt': FieldValue.serverTimestamp(),
    }).timeout(timeout);
  }

  Stream<List<PalaiReminder>> remindersStream({
    required String farmId,
  }) {
    return _reminders(
      farmId,
    )
        .where(
      'isCompleted',
      isEqualTo: false,
    )
        .where(
      'isDismissed',
      isEqualTo: false,
    )
        .orderBy(
      'dueDate',
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        PalaiReminder.fromDoc,
      )
          .toList(),
    );
  }

  // ==========================================================================
  // DELETE HELPERS
  // ==========================================================================

  Future<void> deleteWeightRecord({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _weightRecords(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteHealthRecord({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _healthRecords(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteVaccination({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _vaccinations(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteDeworming({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _deworming(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteHoofCutting({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _hoofCutting(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteHairTrimming({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _hairTrimming(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteMedicine({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _medicines(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteCheckup({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _checkups(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }

  Future<void> deleteMonthlyPhoto({
    required String farmId,
    required String customerId,
    required String goatId,
    required String recordId,
  }) async {
    await _monthlyPhotos(
      farmId,
      customerId,
      goatId,
    )
        .doc(recordId)
        .delete()
        .timeout(timeout);
  }
}