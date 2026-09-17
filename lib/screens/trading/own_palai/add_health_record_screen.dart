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
  State<AddHealthRecordScreen> createState() =>
      _AddHealthRecordScreenState();
}

class _AddHealthRecordScreenState extends State<AddHealthRecordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  DateTime _date = DateTime.now();

  bool _setNextDueDate = false;
  DateTime? _manualNextDueDate;

  DateTime? _farmReminderDate;
  int? _farmReminderDays;
  bool _loadingReminderSetting = true;

  bool _saving = false;

  late final AnimationController _loadingAnimation;

  bool get _usesFarmSettings =>
      widget.type != GoatHealthRecordType.medicine;

  @override
  void initState() {
    super.initState();

    _loadingAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    if (_usesFarmSettings) {
      _loadFarmReminderSetting();
    } else {
      _loadingReminderSetting = false;
    }
  }

  @override
  void dispose() {
    _loadingAnimation.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadFarmReminderSetting() async {
    try {
      final HealthReminderSettings settings =
      await FirestoreService.instance
          .getHealthReminderSettings(widget.farmId);

      if (!mounted) return;

      setState(() {
        switch (widget.type) {
          case GoatHealthRecordType.vaccination:
            _farmReminderDate =
                settings.vaccinationNextDueDate;
            break;

          case GoatHealthRecordType.hairTrimming:
            _farmReminderDate =
                settings.hairTrimmingNextDueDate;
            break;

          case GoatHealthRecordType.hoofCutting:
            _farmReminderDays =
                settings.hoofCuttingReminderDays;
            break;

          case GoatHealthRecordType.medicine:
            break;
        }

        _loadingReminderSetting = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadingReminderSetting = false;
      });
    }
  }

  DateTime? get _resolvedNextDueDate {
    switch (widget.type) {
      case GoatHealthRecordType.vaccination:
      case GoatHealthRecordType.hairTrimming:
        return _farmReminderDate;

      case GoatHealthRecordType.hoofCutting:
        return _farmReminderDays != null
            ? _date.add(
          Duration(days: _farmReminderDays!),
        )
            : null;

      case GoatHealthRecordType.medicine:
        return _setNextDueDate
            ? _manualNextDueDate
            : null;
    }
  }

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        isError ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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

    if (picked != null && mounted) {
      setState(() {
        _date = picked;
      });
    }
  }

  Future<void> _pickManualNextDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _manualNextDueDate ??
          _date.add(
            const Duration(days: 30),
          ),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      setState(() {
        _manualNextDueDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_loadingReminderSetting) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
    });

    _loadingAnimation.repeat(reverse: true);

    final nextDueDate = _resolvedNextDueDate;

    try {
      final recordId =
      await GoatService.instance.addHealthRecord(
        farmId: widget.farmId,
        goatId: widget.goatId,
        record: GoatHealthRecord(
          id: '',
          type: widget.type,
          date: _date,
          notes: _notesController.text.trim(),
          nextDueDate: nextDueDate,
        ),
      );

      unawaited(
        HealthReminderScheduler.instance
            .scheduleTradingHealthReminder(
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
          docId:
          'health_trading_${widget.goatId}_${widget.type.name}_${recordId}_logged',
          type: '${widget.type.name}_logged',
          category: 'health',
          priority: 'normal',
          title: '${widget.type.label} recorded',
          message:
          '${widget.goatId}: ${widget.type.label} logged.',
          reference: {
            'goatId': widget.goatId,
            'recordId': recordId,
          },
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    } finally {
      _loadingAnimation.stop();

      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _typeColor;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 18,
        title: Text(
          'Log ${widget.type.label}',
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                _buildTypeHeader(accent),

                const SizedBox(height: 11),

                _buildDateCard(accent),

                const SizedBox(height: 10),

                _buildNotesCard(),

                const SizedBox(height: 10),

                _buildReminderCard(),

                const SizedBox(height: 16),

                _buildSaveButton(accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeHeader(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: accent.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _typeIcon,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  widget.type.label,
                  style: AppTheme.heading(size: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add a new health record for this goat',
                  style: AppTheme.body(
                    size: 10.5,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(Color accent) {
    return _sectionCard(
      title: 'Record Date',
      icon: Icons.calendar_today_outlined,
      accent: accent,
      child: InkWell(
        onTap: _saving ? null : _pickDate,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 17,
                color: accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  DateFormat('dd MMM yyyy').format(_date),
                  style: AppTheme.body(
                    size: 12.5,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.edit_calendar_outlined,
                size: 17,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return _sectionCard(
      title: 'Notes',
      icon: Icons.notes_outlined,
      accent: AppColors.warning,
      child: TextFormField(
        controller: _notesController,
        maxLines: 3,
        enabled: !_saving,
        style: AppTheme.body(
          size: 12.5,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          hintText: 'Optional notes about this record',
          hintStyle: AppTheme.body(
            size: 11.5,
            color: AppColors.textGrey,
          ),
          filled: true,
          fillColor:
          AppColors.paleGreen.withOpacity(0.55),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(
              color: AppColors.divider.withOpacity(0.6),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(
              color: AppColors.stockTeal,
              width: 1.2,
            ),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }

  Widget _buildReminderCard() {
    return _sectionCard(
      title: 'Reminder',
      icon: Icons.notifications_none_outlined,
      accent: AppColors.info,
      child: _buildReminderContent(),
    );
  }

  Widget _buildReminderContent() {
    if (_loadingReminderSetting) {
      return Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _skeleton(width: 180, height: 12),
          const SizedBox(height: 8),
          _skeleton(
            width: double.infinity,
            height: 42,
          ),
        ],
      );
    }

    if (!_usesFarmSettings) {
      return _buildMedicineReminder();
    }

    if (widget.type ==
        GoatHealthRecordType.hoofCutting) {
      return ReminderCadenceSelector(
        value: _farmReminderDays,
        onChanged: (_) {},
        locked: true,
        lockedNote:
        'This reminder schedule is controlled from '
            'Profile → Health Reminder Settings and applies '
            'to the farm.',
      );
    }

    return ReminderDateSelector(
      value: _farmReminderDate,
      onChanged: (_) {},
      locked: true,
      lockedNote:
      'This due date is controlled from Profile → '
          'Health Reminder Settings and applies to the farm.',
    );
  }

  Widget _buildMedicineReminder() {
    return Column(
      children: [
        InkWell(
          onTap: _saving
              ? null
              : () {
            setState(() {
              _setNextDueDate =
              !_setNextDueDate;

              if (_setNextDueDate) {
                _manualNextDueDate ??=
                    _date.add(
                      const Duration(days: 30),
                    );
              }
            });
          },
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: _setNextDueDate
                  ? AppColors.info.withOpacity(0.07)
                  : AppColors.paleGreen
                  .withOpacity(0.55),
              borderRadius:
              BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.info
                        .withOpacity(0.09),
                    borderRadius:
                    BorderRadius.circular(9),
                  ),
                  child: Icon(
                    _setNextDueDate
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_outlined,
                    size: 16,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set next due date',
                        style: AppTheme.body(
                          size: 12.5,
                          color: AppColors.textDark,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Create a reminder for this medicine',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _setNextDueDate,
                  activeColor: AppColors.info,
                  onChanged: _saving
                      ? null
                      : (value) {
                    setState(() {
                      _setNextDueDate =
                          value;

                      if (value) {
                        _manualNextDueDate ??=
                            _date.add(
                              const Duration(
                                days: 30,
                              ),
                            );
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ),

        if (_setNextDueDate) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap:
            _saving ? null : _pickManualNextDueDate,
            borderRadius:
            BorderRadius.circular(11),
            child: Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.info
                    .withOpacity(0.06),
                borderRadius:
                BorderRadius.circular(11),
                border: Border.all(
                  color: AppColors.info
                      .withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_repeat_outlined,
                    size: 17,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _manualNextDueDate != null
                          ? DateFormat('dd MMM yyyy')
                          .format(
                        _manualNextDueDate!,
                      )
                          : 'Choose a due date',
                      style: AppTheme.body(
                        size: 12.5,
                        color: AppColors.textDark,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textGrey,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveButton(Color accent) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed:
        (_saving || _loadingReminderSetting)
            ? null
            : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          disabledBackgroundColor:
          accent.withOpacity(0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _saving
            ? AnimatedBuilder(
          animation: _loadingAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: 0.45 +
                  (_loadingAnimation.value *
                      0.4),
              child: Container(
                width: 120,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                  BorderRadius.circular(7),
                ),
              ),
            );
          },
        )
            : Row(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 18,
            ),
            const SizedBox(width: 7),
            Text(
              'Save ${widget.type.label} Record',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(radius: 15),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.09),
                  borderRadius:
                  BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTheme.heading(size: 13),
              ),
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }

  Widget _skeleton({
    required double width,
    required double height,
  }) {
    return AnimatedBuilder(
      animation: _loadingAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: 0.45 +
              (_loadingAnimation.value * 0.35),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius:
              BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }

  Color get _typeColor {
    switch (widget.type) {
      case GoatHealthRecordType.vaccination:
        return AppColors.success;
      case GoatHealthRecordType.hoofCutting:
        return AppColors.warning;
      case GoatHealthRecordType.hairTrimming:
        return AppColors.info;
      case GoatHealthRecordType.medicine:
        return AppColors.error;
    }
  }

  IconData get _typeIcon {
    switch (widget.type) {
      case GoatHealthRecordType.vaccination:
        return Icons.vaccines_outlined;
      case GoatHealthRecordType.hoofCutting:
        return Icons.pets_outlined;
      case GoatHealthRecordType.hairTrimming:
        return Icons.content_cut_outlined;
      case GoatHealthRecordType.medicine:
        return Icons.medication_outlined;
    }
  }
}