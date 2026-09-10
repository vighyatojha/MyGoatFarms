import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/health_reminder_settings_model.dart';
import '../../../models/palai_models.dart';
import '../../../models/vaccination_record.dart';
import '../../../services/firestore_service.dart';
import '../../../services/health_reminder_scheduler.dart';
import '../../../services/notification_service.dart';
import '../../../widgets/reminder_cadence_selector.dart';

class AddVaccinationScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const AddVaccinationScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<AddVaccinationScreen> createState() => _AddVaccinationScreenState();
}

class _AddVaccinationScreenState extends State<AddVaccinationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _vaccineController = TextEditingController();
  final _diseaseController = TextEditingController();
  final _batchController = TextEditingController();
  final _dosageController = TextEditingController();
  final _veterinarianController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _vaccinationDate = DateTime.now();

  // Sourced from the FARM'S Health Reminder Settings (Profile > Health
  // Reminder Settings) — single source of truth for every active goat
  // in the farm, regardless of customer. Null means the farm has
  // switched this reminder off entirely. 30 is only ever shown while
  // [_loadingReminderSetting] is true, as a placeholder before the real
  // farm value arrives.
  int? _reminderDays = 30;
  bool _saving = false;
  bool _loadingReminderSetting = true;

  @override
  void initState() {
    super.initState();
    _loadFarmReminderSetting();
  }

  // Reads the Vaccination reminder cadence from the FARM'S Health
  // Reminder Settings — farms/{farmId}.healthReminderSettings — see
  // FirestoreService.getHealthReminderSettings and
  // HealthReminderSettingsScreen (Profile > Health Reminder Settings).
  // This value always governs the reminder: it's shown locked/read-only
  // here, since Farm Profile is now the single place to change it.
  Future<void> _loadFarmReminderSetting() async {
    final HealthReminderSettings settings =
    await FirestoreService.instance.getHealthReminderSettings(widget.farmId);

    if (!mounted) return;

    setState(() {
      _reminderDays = settings.vaccinationReminderDays;
      _loadingReminderSetting = false;
    });
  }

  @override
  void dispose() {
    _vaccineController.dispose();
    _diseaseController.dispose();
    _batchController.dispose();
    _dosageController.dispose();
    _veterinarianController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _vaccinationCollection {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('vaccinationRecords');
  }

  Future<void> _pickDate({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );

    if (picked != null) {
      onPicked(picked);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final nextDueDate = _reminderDays != null
        ? _vaccinationDate.add(
      Duration(days: _reminderDays!),
    )
        : null;

    try {
      final reference = _vaccinationCollection.doc();

      final record = VaccinationRecord(
        id: reference.id,
        goatId: widget.goat.id,
        vaccineName: _vaccineController.text.trim(),
        disease: _diseaseController.text.trim(),
        vaccinationDate: _vaccinationDate,
        nextDueDate: nextDueDate,
        batchNumber: _batchController.text.trim(),
        dosage: _dosageController.text.trim(),
        veterinarian: _veterinarianController.text.trim(),
        note: _noteController.text.trim(),
        recordedAt: DateTime.now(),
      );

      await reference.set({
        ...record.toCreateMap(),
        'farmId': widget.farmId,
      });

      unawaited(
        FirestoreService.instance.addNotification(
          farmId: widget.farmId,
          docId:
          'health_${widget.goat.id}_vaccination_${reference.id}_logged',
          type: 'vaccination_logged',
          category: 'health',
          priority: 'normal',
          title: 'Vaccination recorded',
          message:
          '${widget.goat.goatCode}: ${record.vaccineName} vaccination logged.',
          reference: {
            'customerId': widget.customerId,
            'goatId': widget.goat.id,
            'recordId': reference.id,
          },
        ),
      );

      unawaited(
        NotificationService.instance.showNow(
          id: reference.id.hashCode & 0x0FFFFFFF,
          title: 'Vaccination recorded',
          body:
          '${widget.goat.goatCode}: ${record.vaccineName} vaccination logged.',
          data: {
            'customerId': widget.customerId,
            'goatId': widget.goat.id,
            'recordId': reference.id,
          },
        ),
      );

      unawaited(
        HealthReminderScheduler.instance.scheduleCustomerHealthReminder(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goatId: widget.goat.id,
          goatCode: widget.goat.goatCode,
          recordType: 'vaccination',
          recordId: reference.id,
          label: 'Vaccination',
          dueDate: nextDueDate,
        ),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save vaccination: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Vaccination'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            100,
          ),
          children: [
            if (_loadingReminderSetting)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            TextFormField(
              controller: _vaccineController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Vaccine name *',
                hintText: 'Example: PPR Vaccine',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter the vaccine name';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _diseaseController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Disease / protection',
                hintText: 'Example: PPR',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            _DateTile(
              label: 'Vaccination date',
              date: _vaccinationDate,
              onTap: () => _pickDate(
                initial: _vaccinationDate,
                first: DateTime(2000),
                last: DateTime.now(),
                onPicked: (d) {
                  setState(() {
                    _vaccinationDate = d;
                  });
                },
              ),
            ),
            const SizedBox(height: 14),
            // While the farm's setting is still loading, the
            // LinearProgressIndicator above already signals that — the
            // selector itself is withheld rather than briefly flashing a
            // placeholder value.
            if (!_loadingReminderSetting)
              ReminderCadenceSelector(
                value: _reminderDays,
                locked: true,
                lockedNote:
                'This reminder schedule is set for the whole farm in '
                    'Profile → Health Reminder Settings and applies to '
                    'every goat, no matter which customer they belong to.',
                onChanged: (days) {
                  setState(() {
                    _reminderDays = days;
                  });
                },
              ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _batchController,
              decoration: const InputDecoration(
                labelText: 'Batch number',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dosageController,
              decoration: const InputDecoration(
                labelText: 'Dosage',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _veterinarianController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Veterinarian',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('Save Vaccination'),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool optional;
  final bool showTime;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateTile({
    required this.label,
    required this.date,
    this.optional = false,
    this.showTime = false,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: optional ? '$label (optional)' : label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear != null
              ? IconButton(
            icon: const Icon(
              Icons.clear,
              size: 18,
            ),
            onPressed: onClear,
          )
              : const Icon(
            Icons.calendar_today_outlined,
            size: 18,
          ),
        ),
        child: Text(
          date != null
              ? DateFormat(
            showTime
                ? 'd MMM yyyy, h:mm a'
                : 'd MMM yyyy',
          ).format(date!)
              : 'Not set',
          style: TextStyle(
            color: date != null
                ? null
                : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}