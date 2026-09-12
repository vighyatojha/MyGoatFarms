import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/health_reminder_settings_model.dart';
import '../../../models/hoof_cutting_record.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/health_reminder_scheduler.dart';
import '../../../services/notification_service.dart';
import '../../../widgets/reminder_cadence_selector.dart';

class AddHoofCuttingScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const AddHoofCuttingScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<AddHoofCuttingScreen> createState() => _AddHoofCuttingScreenState();
}

class _AddHoofCuttingScreenState extends State<AddHoofCuttingScreen> {
  final _performedByController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _cuttingDate = DateTime.now();

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

  // Reads the Hoof Cutting reminder cadence from the FARM'S Health
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
      _reminderDays = settings.hoofCuttingReminderDays;
      _loadingReminderSetting = false;
    });
  }

  @override
  void dispose() {
    _performedByController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _hoofCollection {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('hoofCuttingRecords');
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
    if (_loadingReminderSetting) {
      // Farm reminder setting hasn't finished loading yet — the Save
      // button should be disabled in this state, but guard here too
      // so we never silently persist a null nextDueDate by racing the
      // fetch.
      return;
    }

    setState(() {
      _saving = true;
    });

    final nextDueDate = _reminderDays != null
        ? _cuttingDate.add(
      Duration(days: _reminderDays!),
    )
        : null;

    try {
      final reference = _hoofCollection.doc();

      final record = HoofCuttingRecord(
        id: reference.id,
        goatId: widget.goat.id,
        cuttingDate: _cuttingDate,
        nextDueDate: nextDueDate,
        performedBy: _performedByController.text.trim(),
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
          'health_${widget.goat.id}_hoofCutting_${reference.id}_logged',
          type: 'hoofCutting_logged',
          category: 'health',
          priority: 'normal',
          title: 'Hoof cutting recorded',
          message: '${widget.goat.goatCode}: hoof cutting logged.',
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
          title: 'Hoof cutting recorded',
          body: '${widget.goat.goatCode}: hoof cutting logged.',
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
          recordType: 'hoofCutting',
          recordId: reference.id,
          label: 'Hoof cutting',
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
            'Could not save hoof cutting: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Hoof Cutting'),
      ),
      body: ListView(
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
          _DateTile(
            label: 'Cutting date',
            date: _cuttingDate,
            onTap: () => _pickDate(
              initial: _cuttingDate,
              first: DateTime(2000),
              last: DateTime.now(),
              onPicked: (d) {
                setState(() {
                  _cuttingDate = d;
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
            controller: _performedByController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Performed by',
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: (_saving || _loadingReminderSetting) ? null : _save,
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
                  : const Text('Save Hoof Cutting'),
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