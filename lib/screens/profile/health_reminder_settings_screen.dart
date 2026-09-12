import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/health_reminder_settings_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/reminder_date_selector.dart';

/// Dedicated Health Reminder Settings editor — Hoof Cutting reminder
/// cadence (in days), plus Vaccination and Hair Trimming next-due
/// dates.
///
/// This is a FARM-LEVEL setting (Profile > Health Reminder Settings):
/// once saved here it applies to every active goat in the farm,
/// regardless of which customer that goat is boarded under. This
/// replaces the old per-customer "Health Settings" that used to live
/// on each Customer Profile.
///
/// All three record types are governed from here now:
/// - Hoof Cutting uses a day-cadence — each new record's `nextDueDate`
///   is `cuttingDate + hoofCuttingReminderDays`.
/// - Vaccination and Hair Trimming each use a single farm-wide
///   CALENDAR DATE instead of a cadence — every new record of that
///   type, for every goat, gets that exact date as its `nextDueDate`.
///
/// The Add Hoof Cutting / Add Vaccination / Add Hair Trimming screens
/// all read this value live (via
/// [FirestoreService.getHealthReminderSettings]) — there is no separate
/// per-goat or per-customer override anymore, so changing a goat's
/// customer never changes any of its reminder settings.
class HealthReminderSettingsScreen extends StatefulWidget {
  final String farmId;
  final HealthReminderSettings initialSettings;

  const HealthReminderSettingsScreen({
    super.key,
    required this.farmId,
    required this.initialSettings,
  });

  @override
  State<HealthReminderSettingsScreen> createState() =>
      _HealthReminderSettingsScreenState();
}

class _HealthReminderSettingsScreenState
    extends State<HealthReminderSettingsScreen> {
  // Hoof Cutting's cadence: 30 / 45 / 60 / 90 days. There is
  // intentionally no 15-day option, matching the slider previously
  // offered per-customer.
  static const List<int> _reminderOptions = [30, 45, 60, 90];

  late int? _hoofCuttingDays = widget.initialSettings.hoofCuttingReminderDays;

  // Vaccination and Hair Trimming now each carry a single farm-wide
  // CALENDAR DATE, edited directly on this screen via
  // [ReminderDateSelector].
  late DateTime? _vaccinationNextDueDate =
      widget.initialSettings.vaccinationNextDueDate;
  late DateTime? _hairTrimmingNextDueDate =
      widget.initialSettings.hairTrimmingNextDueDate;

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    final settings = HealthReminderSettings(
      hoofCuttingReminderDays: _hoofCuttingDays,
      vaccinationNextDueDate: _vaccinationNextDueDate,
      hairTrimmingNextDueDate: _hairTrimmingNextDueDate,
    );

    try {
      await FirestoreService.instance.updateHealthReminderSettings(
        widget.farmId,
        settings,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Health Reminder Settings updated'),
          backgroundColor: AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Deferred to next frame — same reasoning as BillSettingsScreen's
      // _save(): avoids tearing the route down mid-frame while the
      // SnackBar entrance animation / unfocus rebuild is still pending.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(settings);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not save Health Reminder Settings: ${FirestoreService.instance.describeError(e)}',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Sliding selector for the Hoof Cutting cadence: a discrete 4-stop
  // slider across 30 / 45 / 60 / 90 days, plus a switch to turn the
  // reminder off entirely ("None" — clears the setting across the
  // WHOLE farm). This is what the Add Hoof Cutting screen, for every
  // goat, reads.
  Widget _reminderPicker({
    required String title,
    required String subtitle,
    required List<int> options,
    required int? selected,
    required ValueChanged<int?> onChanged,
  }) {
    final isOn = selected != null;
    final index = isOn ? options.indexOf(selected).clamp(0, options.length - 1) : 0;
    final displayValue = options[index == -1 ? 0 : index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTheme.body(
                  size: 12,
                  color: AppColors.textDark,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            Switch(
              value: isOn,
              activeColor: AppColors.primaryGreen,
              onChanged: (enabled) => onChanged(enabled ? displayValue : null),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: AppTheme.body(size: 11, color: AppColors.textGrey),
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: isOn ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !isOn,
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primaryGreen,
                    inactiveTrackColor: AppColors.primaryGreen.withOpacity(0.15),
                    thumbColor: AppColors.primaryGreen,
                    overlayColor: AppColors.primaryGreen.withOpacity(0.15),
                    valueIndicatorColor: AppColors.primaryGreen,
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: index.toDouble(),
                    min: 0,
                    max: (options.length - 1).toDouble(),
                    divisions: options.length - 1,
                    label: '$displayValue days',
                    onChanged: (v) => onChanged(options[v.round()]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: options
                        .map(
                          (days) => Text(
                        '$days',
                        style: AppTheme.body(
                          size: 11,
                          color: displayValue == days ? AppColors.primaryGreen : AppColors.textGrey,
                          weight: displayValue == days ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isOn ? 'Every $displayValue days' : 'No reminder',
          style: AppTheme.body(
            size: 13,
            color: AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Calendar-date pickers for Vaccination / Hair Trimming: one fixed
  // date, shared by every goat in the farm, rather than a per-record
  // cadence.
  Widget _datePicker({
    required String title,
    required String subtitle,
    required DateTime? selected,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.body(
            size: 12,
            color: AppColors.textDark,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: AppTheme.body(size: 11, color: AppColors.textGrey),
        ),
        const SizedBox(height: 8),
        ReminderDateSelector(
          value: selected,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _section({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.heading(size: 15))),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withOpacity(.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.primaryGreen),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'These reminder settings apply to every active goat in this '
                  'farm, no matter which customer they belong to. Moving a '
                  'goat to a different customer never changes any of its '
                  'reminder settings. Hoof cutting repeats on a day cadence '
                  'after each record; vaccination and hair trimming instead '
                  'use one fixed due date that is applied to every new '
                  'record you log for any goat.',
              style: TextStyle(fontSize: 11, color: AppColors.darkGreen),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text('Health Reminder Settings', style: AppTheme.heading(size: 18)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text(
              'Save Health Reminder Settings',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoBanner(),
            const SizedBox(height: 16),
            _section(
              title: 'Hoof Cutting',
              icon: Icons.health_and_safety_outlined,
              child: _reminderPicker(
                title: 'Hoof Cutting Reminder',
                subtitle: 'Remind again this many days after each hoof cutting.',
                options: _reminderOptions,
                selected: _hoofCuttingDays,
                onChanged: (v) => setState(() => _hoofCuttingDays = v),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Vaccination',
              icon: Icons.vaccines_outlined,
              child: _datePicker(
                title: 'Vaccination Reminder',
                subtitle:
                'Every new vaccination record logged for any goat in the '
                    'farm will show this date as its next-due date.',
                selected: _vaccinationNextDueDate,
                onChanged: (d) => setState(() => _vaccinationNextDueDate = d),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Hair Trimming',
              icon: Icons.content_cut_outlined,
              child: _datePicker(
                title: 'Hair Trimming Reminder',
                subtitle:
                'Every new hair trimming record logged for any goat in '
                    'the farm will show this date as its next-due date.',
                selected: _hairTrimmingNextDueDate,
                onChanged: (d) => setState(() => _hairTrimmingNextDueDate = d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}