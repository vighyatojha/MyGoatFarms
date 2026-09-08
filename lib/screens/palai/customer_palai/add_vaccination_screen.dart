import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../models/vaccination_record.dart';
import '../../../services/firestore_service.dart';
import '../../../services/health_reminder_scheduler.dart';

/// Full-page "Add Vaccination" screen, pushed from the Vaccination tab
/// on GoatProfileScreen. Deliberately a pushed screen rather than a
/// dialog/popup — a popup form nested inside a TabBarView page is what
/// was causing the '_dependents.isEmpty' crash when saving, and a real
/// screen is a much better mobile UX for a form this long anyway.
class AddVaccinationScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  /// Default number of days to suggest for "Next due date", pulled
  /// from this customer's settings by the parent tab.
  final int reminderDays;

  const AddVaccinationScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
    this.reminderDays = 30,
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
  DateTime? _nextDueDate;
  bool _saving = false;

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
    if (picked != null) onPicked(picked);
  }

  /// Date + time picker — used for "Next due date" so the due moment can
  /// be set to a few minutes from now, which is the only practical way
  /// to manually test the "due today" notification without waiting
  /// until midnight.
  Future<void> _pickDateTime({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    onPicked(DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    ));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final reference = _vaccinationCollection.doc();
      final record = VaccinationRecord(
        id: reference.id,
        goatId: widget.goat.id,
        vaccineName: _vaccineController.text.trim(),
        disease: _diseaseController.text.trim(),
        vaccinationDate: _vaccinationDate,
        nextDueDate: _nextDueDate,
        batchNumber: _batchController.text.trim(),
        dosage: _dosageController.text.trim(),
        veterinarian: _veterinarianController.text.trim(),
        note: _noteController.text.trim(),
        recordedAt: DateTime.now(),
      );
      await reference.set(record.toCreateMap());

      // Instant "it happened" notification — fires regardless of
      // whether a next-due date was set, so every vaccination logged
      // shows up in the notification feed right away.
      unawaited(FirestoreService.instance.addNotification(
        farmId: widget.farmId,
        docId: 'health_${widget.goat.id}_vaccination_${reference.id}_logged',
        type: 'vaccination_logged',
        category: 'health',
        priority: 'normal',
        title: 'Vaccination recorded',
        message: '${widget.goat.goatCode}: ${record.vaccineName} vaccination logged.',
        reference: {'customerId': widget.customerId, 'goatId': widget.goat.id, 'recordId': reference.id},
      ));

      // Due-date reminder engine (7 days before / 1 day before / due
      // today) for the next-due date, if one was set.
      unawaited(HealthReminderScheduler.instance.scheduleCustomerHealthReminder(
        farmId: widget.farmId,
        customerId: widget.customerId,
        goatId: widget.goat.id,
        goatCode: widget.goat.goatCode,
        recordType: 'vaccination',
        recordId: reference.id,
        label: 'Vaccination',
        dueDate: record.nextDueDate,
      ));

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save vaccination: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Vaccination')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            TextFormField(
              controller: _vaccineController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Vaccine name *',
                hintText: 'Example: PPR Vaccine',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the vaccine name' : null,
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
                onPicked: (d) => setState(() => _vaccinationDate = d),
              ),
            ),
            const SizedBox(height: 14),
            _DateTile(
              label: 'Next due date',
              date: _nextDueDate,
              optional: true,
              showTime: true,
              onTap: () => _pickDateTime(
                initial: _nextDueDate ?? _vaccinationDate.add(Duration(days: widget.reminderDays)),
                first: _vaccinationDate,
                last: DateTime(2100),
                onPicked: (d) => setState(() => _nextDueDate = d),
              ),
              onClear: _nextDueDate == null ? null : () => setState(() => _nextDueDate = null),
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryGreen),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClear)
              : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          date != null
              ? DateFormat(showTime ? 'd MMM yyyy, h:mm a' : 'd MMM yyyy').format(date!)
              : 'Not set',
          style: TextStyle(color: date != null ? null : AppColors.textMuted),
        ),
      ),
    );
  }
}