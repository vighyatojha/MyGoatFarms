import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/health_reminder_settings_model.dart';
import '../../../models/trading_goat_health_record.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/health_reminder_scheduler.dart';
import '../../../widgets/reminder_cadence_selector.dart';
import '../../../widgets/reminder_date_selector.dart';

/// Task 3.3 — "log a new entry per type" form, reached from the Health
/// Tracking section of the Own Palai Goat Profile.
///
/// [type] is fixed by whichever of the four buttons (Vaccination, Hoof
/// Cutting, Hair Trimming, Medicine) opened this screen — the person
/// never picks it here, matching the plan's "current status + history
/// for each of" four separate sections rather than one combined type
/// picker.
///
/// Task 1.3's reminder mechanism reuses the app's existing farm-wide
/// Health Reminder Settings (Profile > Health Reminder Settings)
/// instead of a separate Trading-only setting: Vaccination and Hair
/// Trimming use the farm's single calendar date, Hoof Cutting uses the
/// farm's day cadence — exactly the way Customer Palai's Add
/// Vaccination / Add Hoof Cutting / Add Hair Trimming screens already
/// do (see [ReminderDateSelector] / [ReminderCadenceSelector]). Only
/// Medicine keeps a manual, per-entry "Set next due date" picker, since
/// Customer Palai has no farm-wide setting for it either. Saving calls
/// [HealthReminderScheduler.scheduleTradingHealthReminder] — the same
/// on-device scheduler and farm-wide notification feed Own Farm and
/// Customer Palai already use — so nothing new had to be built to make
/// this goat's reminders actually fire.
class AddHealthRecordScreen extends StatefulWidget {
  final String farmId;
  final String goatId;
  final GoatHealthRecordType type;

  const AddHealthRecordScreen({
    super.key,
    required this.farmId,
    required this.goatId,
    required this.type,
  });

  @override
  State<AddHealthRecordScreen> createState() => _AddHealthRecordScreenState();
}

class _AddHealthRecordScreenState extends State<AddHealthRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  DateTime _date = DateTime.now();

  // Medicine only — the other three types are governed by the farm's
  // Health Reminder Settings instead (see _loadFarmReminderSetting).
  bool _setNextDueDate = false;
  DateTime? _manualNextDueDate;

  // Vaccination / Hair Trimming: farm-wide calendar date.
  // Hoof Cutting: farm-wide cadence in days (applied to _date below).
  // Sourced from Profile > Health Reminder Settings — see
  // FirestoreService.getHealthReminderSettings.
  DateTime? _farmReminderDate;
  int? _farmReminderDays;
  bool _loadingReminderSetting = true;

  bool get _usesFarmSettings => widget.type != GoatHealthRecordType.medicine;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_usesFarmSettings) {
      _loadFarmReminderSetting();
    } else {
      _loadingReminderSetting = false;
    }
  }

  Future<void> _loadFarmReminderSetting() async {
    final HealthReminderSettings settings =
    await FirestoreService.instance.getHealthReminderSettings(widget.farmId);

    if (!mounted) return;

    setState(() {
      switch (widget.type) {
        case GoatHealthRecordType.vaccination:
          _farmReminderDate = settings.vaccinationNextDueDate;
          break;
        case GoatHealthRecordType.hairTrimming:
          _farmReminderDate = settings.hairTrimmingNextDueDate;
          break;
        case GoatHealthRecordType.hoofCutting:
          _farmReminderDays = settings.hoofCuttingReminderDays;
          break;
        case GoatHealthRecordType.medicine:
          break;
      }
      _loadingReminderSetting = false;
    });
  }

  /// The `nextDueDate` that will actually be saved on this record,
  /// resolved per [widget.type] from whichever source governs it.
  DateTime? get _resolvedNextDueDate {
    switch (widget.type) {
      case GoatHealthRecordType.vaccination:
      case GoatHealthRecordType.hairTrimming:
        return _farmReminderDate;
      case GoatHealthRecordType.hoofCutting:
        return _farmReminderDays != null
            ? _date.add(Duration(days: _farmReminderDays!))
            : null;
      case GoatHealthRecordType.medicine:
        return _setNextDueDate ? _manualNextDueDate : null;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.darkGreen,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickManualNextDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _manualNextDueDate ?? _date.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _manualNextDueDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_loadingReminderSetting) {
      // Farm reminder setting hasn't finished loading yet — the Save
      // button is disabled in this state, but guard here too so we
      // never race the fetch and silently persist a null nextDueDate.
      return;
    }

    setState(() => _saving = true);

    final nextDueDate = _resolvedNextDueDate;

    try {
      final recordId = await GoatService.instance.addHealthRecord(
        farmId: widget.farmId,
        goatId: widget.goatId,
        record: GoatHealthRecord(
          id: '',
          type: widget.type,
          date: _date,
          notes: _notesController.text,
          nextDueDate: nextDueDate,
        ),
      );

      // Reuses the same on-device scheduler (and the same farm-wide
      // notification feed) that Own Farm and Customer Palai already
      // use — see Task 1.3 in the phase 3 plan.
      unawaited(
        HealthReminderScheduler.instance.scheduleTradingHealthReminder(
          farmId: widget.farmId,
          goatId: widget.goatId,
          goatCode: widget.goatId,
          recordType: widget.type.name,
          recordId: recordId,
          label: widget.type.label,
          dueDate: nextDueDate,
        ),
      );

      unawaited(
        FirestoreService.instance.addNotification(
          farmId: widget.farmId,
          docId: 'health_trading_${widget.goatId}_${widget.type.name}_${recordId}_logged',
          type: '${widget.type.name}_logged',
          category: 'health',
          priority: 'normal',
          title: '${widget.type.label} recorded',
          message: '${widget.goatId}: ${widget.type.label} logged.',
          reference: {'goatId': widget.goatId, 'recordId': recordId},
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack(FirestoreService.instance.describeError(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Log ${widget.type.label}', style: AppTheme.heading(size: 17)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Date'),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: AppTheme.card(radius: 12),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: AppColors.stockTeal,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('dd MMM yyyy').format(_date),
                          style:
                          AppTheme.body(size: 13, color: AppColors.textDark),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _label('Notes'),
                _textField(
                  _notesController,
                  hint: 'Optional notes',
                  maxLines: 3,
                  optional: true,
                ),
                const SizedBox(height: 20),
                _reminderSection(),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_saving || _loadingReminderSetting) ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.stockTeal,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                        : Text(
                      'Save ${widget.type.label} Record',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reminderSection() {
    if (!_usesFarmSettings) {
      // Medicine — manual, per-entry due date (matches Customer
      // Palai's Add Medicine screen, which also has no farm setting).
      return Container(
        decoration: AppTheme.card(radius: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.stockTeal,
              title: Text(
                'Set next due date',
                style: AppTheme.body(
                    size: 13,
                    color: AppColors.textDark,
                    weight: FontWeight.w600),
              ),
              subtitle: Text(
                'Feeds the reminder for this goat\'s next '
                    '${widget.type.label.toLowerCase()}.',
                style: AppTheme.body(size: 11, color: AppColors.textGrey),
              ),
              value: _setNextDueDate,
              onChanged: (v) => setState(() {
                _setNextDueDate = v;
                if (v) {
                  _manualNextDueDate ??= _date.add(const Duration(days: 30));
                }
              }),
            ),
            if (_setNextDueDate) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: _pickManualNextDueDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.textMuted.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_repeat_outlined,
                        size: 16,
                        color: AppColors.stockTeal,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _manualNextDueDate != null
                            ? DateFormat('dd MMM yyyy').format(_manualNextDueDate!)
                            : 'Choose a date',
                        style: AppTheme.body(size: 13, color: AppColors.textDark),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_loadingReminderSetting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    // Vaccination / Hair Trimming / Hoof Cutting — locked, sourced from
    // Profile > Health Reminder Settings, same as Customer Palai.
    if (widget.type == GoatHealthRecordType.hoofCutting) {
      return ReminderCadenceSelector(
        value: _farmReminderDays,
        onChanged: (_) {},
        locked: true,
        lockedNote:
        'This reminder schedule was chosen in Profile → Health '
            'Reminder Settings and applies to every active goat in '
            'the farm — Own Palai included. Update it from Profile '
            '→ Health Reminder Settings instead.',
      );
    }

    return ReminderDateSelector(
      value: _farmReminderDate,
      onChanged: (_) {},
      locked: true,
      lockedNote:
      'This due date was chosen in Profile → Health Reminder '
          'Settings and applies to every active goat in the farm — '
          'Own Palai included. Update it from Profile → Health '
          'Reminder Settings instead.',
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: AppTheme.heading(size: 13)),
  );

  Widget _textField(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        bool optional = false,
        String? Function(String?)? validator,
      }) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator ??
                (v) => (!optional && (v == null || v.trim().isEmpty))
                ? 'Required'
                : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.body(size: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
    );
  }
}