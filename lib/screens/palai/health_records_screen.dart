import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/own_farm_models.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../widgets/image_source_sheet.dart';
import 'fullscreen_image_viewer.dart';

/// Maintains everything about a boarded Palai goat's wellbeing:
///   • Checkups — weight, health status, doctor notes (the original log)
///   • Vaccination & Care — vaccination schedule & history, deworming,
///     hoof cutting (khud cutting, 30/45-day reminder), hair trimming
///     (reminder as set for the record) and medicine records, each with
///     an optional reminder due-date
///   • Monthly Photos — one progress photo per month while boarded
///
/// Pass [initialGoat] to land on this screen with a goat already picked
/// (used when opening this from the goat list's "Update Health" option).
class HealthRecordsScreen extends StatefulWidget {
  final PalaiGoat? initialGoat;
  const HealthRecordsScreen({super.key, this.initialGoat});

  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen> {
  String? _farmId;
  PalaiGoat? _selectedGoat;

  @override
  void initState() {
    super.initState();
    _selectedGoat = widget.initialGoat;
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  Color _healthColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;
      case 'Under Observation':
        return AppColors.warning;
      default:
        return AppColors.success;
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
        title: Text('Health Records', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Goat', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 8),
            StreamBuilder<List<PalaiGoat>>(
              stream: FirestoreService.instance.allActiveGoatsStream(_farmId!),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _errorBanner(
                    'Could not load goats.\n${FirestoreService.instance.describeError(snap.error!)}',
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                  );
                }
                final goats = snap.data ?? [];
                // Keep _selectedGoat pointed at the freshest instance
                // for this goat id (the stream re-emits a brand new
                // list of PalaiGoat objects on every write, so the
                // dropdown always needs to hold one of *this*
                // snapshot's instances, not a stale one).
                if (_selectedGoat != null && goats.isNotEmpty) {
                  final match = goats.where((g) => g.id == _selectedGoat!.id);
                  if (match.isNotEmpty) {
                    _selectedGoat = match.first;
                  }
                }
                final dropdownValue = goats.contains(_selectedGoat) ? _selectedGoat : null;
                return Container(
                  decoration: AppTheme.card(radius: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PalaiGoat>(
                      value: dropdownValue,
                      isExpanded: true,
                      hint: Text(
                        goats.isEmpty ? 'No boarded goats found' : 'Choose a goat',
                        style: AppTheme.body(size: 13),
                      ),
                      items: goats
                          .map((g) => DropdownMenuItem(value: g, child: Text('${g.goatCode} · ${g.breed}', style: AppTheme.body(size: 13, color: AppColors.textDark))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedGoat = v),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            if (_selectedGoat != null)
              Expanded(
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      Container(
                        decoration: AppTheme.card(radius: 12),
                        child: TabBar(
                          labelColor: AppColors.primaryGreen,
                          unselectedLabelColor: AppColors.textGrey,
                          indicatorColor: AppColors.primaryGreen,
                          labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          tabs: const [
                            Tab(text: 'Checkups'),
                            Tab(text: 'Vaccination & Care'),
                            Tab(text: 'Photos'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _CheckupsTab(farmId: _farmId!, goat: _selectedGoat!, healthColor: _healthColor),
                            _VaccinationCareTab(farmId: _farmId!, goat: _selectedGoat!),
                            _MonthlyPhotosTab(farmId: _farmId!, goat: _selectedGoat!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Center(child: Text('Choose a goat above to view its health records.', style: AppTheme.body(size: 12))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: AppTheme.body(size: 12, color: AppColors.error))),
        ],
      ),
    );
  }
}

// ===========================================================================
// Checkups — weight, health status, doctor notes (original combined log)
// ===========================================================================

class _CheckupsTab extends StatelessWidget {
  final String farmId;
  final PalaiGoat goat;
  final Color Function(String) healthColor;

  const _CheckupsTab({required this.farmId, required this.goat, required this.healthColor});

  void _openAddEntrySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHealthRecordSheet(farmId: farmId, goat: goat),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEntrySheet(context),
        backgroundColor: AppColors.primaryGreen,
        icon: const Icon(Icons.add),
        label: const Text('Add Record'),
      ),
      body: StreamBuilder<List<HealthRecordEntry>>(
        stream: FirestoreService.instance.healthRecordsStream(farmId, goat.customerId, goat.id),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(FirestoreService.instance.describeError(snap.error!), style: AppTheme.body(size: 12, color: AppColors.error)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return Center(child: Text('No health records yet.', style: AppTheme.body(size: 12)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 90),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final e = entries[index];
              final color = healthColor(e.healthStatus);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(radius: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            Text(
                              e.healthStatus.isEmpty ? 'Healthy' : e.healthStatus,
                              style: AppTheme.heading(size: 13, color: color),
                            ),
                          ],
                        ),
                        Text(DateFormat('dd MMM yyyy · hh:mm a').format(e.recordedAt), style: AppTheme.body(size: 11)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${e.weight} kg', style: AppTheme.body(size: 12, color: AppColors.textDark)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (e.vaccination.isNotEmpty) _tag('Vaccination: ${e.vaccination}'),
                        if (e.deworming.isNotEmpty) _tag('Deworming: ${e.deworming}'),
                        if (e.hoofCutting.isNotEmpty) _tag('Hoof Cutting: ${e.hoofCutting}'),
                        if (e.medicineGiven.isNotEmpty) _tag('Medicine: ${e.medicineGiven}'),
                      ],
                    ),
                    if (e.doctorNotes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(e.doctorNotes, style: AppTheme.body(size: 11)),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: AppTheme.body(size: 10, color: AppColors.darkGreen)),
    );
  }
}

class _AddHealthRecordSheet extends StatefulWidget {
  final String farmId;
  final PalaiGoat goat;
  const _AddHealthRecordSheet({required this.farmId, required this.goat});

  @override
  State<_AddHealthRecordSheet> createState() => _AddHealthRecordSheetState();
}

class _AddHealthRecordSheetState extends State<_AddHealthRecordSheet> {
  static const List<String> _healthOptions = ['Healthy', 'Under Observation', 'Sick'];

  final _weightController = TextEditingController();
  final _vaccinationController = TextEditingController();
  final _dewormingController = TextEditingController();
  final _hoofController = TextEditingController();
  final _medicineController = TextEditingController();
  final _notesController = TextEditingController();
  String _healthStatus = 'Healthy';
  DateTime _recordedAt = DateTime.now();
  bool _saving = false;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _recordedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_recordedAt),
    );
    if (time == null) return;
    setState(() {
      _recordedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final entry = HealthRecordEntry(
      id: '',
      weight: double.tryParse(_weightController.text.trim()) ?? 0,
      vaccination: _vaccinationController.text.trim(),
      deworming: _dewormingController.text.trim(),
      hoofCutting: _hoofController.text.trim(),
      medicineGiven: _medicineController.text.trim(),
      healthStatus: _healthStatus,
      doctorNotes: _notesController.text.trim(),
      recordedAt: _recordedAt,
    );
    try {
      await FirestoreService.instance.addHealthRecord(widget.farmId, widget.goat.customerId, widget.goat.id, entry);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add Health Record · ${widget.goat.goatCode}', style: AppTheme.heading(size: 15)),
            const SizedBox(height: 14),
            Text('Health Status', style: AppTheme.body(size: 12, color: AppColors.textDark)),
            const SizedBox(height: 6),
            _dropdown(_healthStatus, _healthOptions, (v) => setState(() => _healthStatus = v)),
            const SizedBox(height: 10),
            Text('Date & Time', style: AppTheme.body(size: 12, color: AppColors.textDark)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: AppTheme.card(radius: 10),
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy · hh:mm a').format(_recordedAt),
                      style: AppTheme.body(size: 13, color: AppColors.textDark),
                    ),
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primaryGreen),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _field(_weightController, 'Current Weight (kg)', keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            _field(_vaccinationController, 'Vaccination'),
            const SizedBox(height: 10),
            _field(_dewormingController, 'Deworming'),
            const SizedBox(height: 10),
            _field(_hoofController, 'Hoof Cutting'),
            const SizedBox(height: 10),
            _field(_medicineController, 'Medicine Given'),
            const SizedBox(height: 10),
            _field(_notesController, 'Doctor Notes', maxLines: 3),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Record', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      decoration: AppTheme.card(radius: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o, style: AppTheme.body(size: 13, color: AppColors.textDark))))
              .toList(),
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint, {TextInputType? keyboardType, int maxLines = 1}) {
    return Container(
      decoration: AppTheme.card(radius: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.body(size: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
        ),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
    );
  }
}

// ===========================================================================
// Vaccination & Care — vaccination schedule & history, hoof cutting (khud
// cutting, 30/45-day reminder), hair trimming and medicine records, each
// with its own reminder due-date.
// ===========================================================================

class _VaccinationCareTab extends StatelessWidget {
  final String farmId;
  final PalaiGoat goat;
  const _VaccinationCareTab({required this.farmId, required this.goat});

  static final _dateFmt = DateFormat('d MMM yyyy');

  IconData _iconFor(HealthEventType type) {
    switch (type) {
      case HealthEventType.vaccination:
        return Icons.vaccines_outlined;
      case HealthEventType.deworming:
        return Icons.medication_liquid_outlined;
      case HealthEventType.hoofCutting:
        return Icons.content_cut;
      case HealthEventType.hairTrimming:
        return Icons.cut;
      case HealthEventType.medicine:
        return Icons.medical_services_outlined;
      case HealthEventType.checkup:
        return Icons.fact_check_outlined;
    }
  }

  Future<void> _addEvent(BuildContext context) async {
    HealthEventType type = HealthEventType.vaccination;
    final descController = TextEditingController();
    DateTime date = DateTime.now();
    // Vaccination & hair trimming reminders follow whatever cadence the
    // farm/customer has set for that goat; hoof cutting (khud cutting)
    // defaults to the standard 30/45-day cadence.
    int? reminderDays = 30;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add Vaccination / Care Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<HealthEventType>(
                  value: type,
                  isExpanded: true,
                  items: HealthEventType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(HealthEvent(id: '', type: t, description: '', date: date).label)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    type = v ?? type;
                    reminderDays = (type == HealthEventType.hoofCutting ||
                        type == HealthEventType.vaccination ||
                        type == HealthEventType.hairTrimming)
                        ? 30
                        : null;
                  }),
                ),
                TextField(controller: descController, decoration: const InputDecoration(hintText: 'Description / medicine used')),
                const SizedBox(height: 8),
                if (type == HealthEventType.hoofCutting)
                  Row(
                    children: [
                      Text('Remind after: ', style: AppTheme.body(size: 12)),
                      DropdownButton<int>(
                        value: reminderDays,
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 days')),
                          DropdownMenuItem(value: 45, child: Text('45 days')),
                        ],
                        onChanged: (v) => setState(() => reminderDays = v),
                      ),
                    ],
                  )
                else if (type == HealthEventType.vaccination || type == HealthEventType.hairTrimming)
                  Row(
                    children: [
                      Text('Remind after (days): ', style: AppTheme.body(size: 12)),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(text: reminderDays?.toString() ?? ''),
                          decoration: const InputDecoration(hintText: 'e.g. 30'),
                          onChanged: (v) => reminderDays = int.tryParse(v.trim()),
                        ),
                      ),
                      Text(' or none', style: AppTheme.body(size: 11)),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await FirestoreService.instance.addPalaiHealthEvent(
        farmId,
        goat.customerId,
        goat.id,
        HealthEvent(
          id: '',
          type: type,
          description: descController.text.trim(),
          date: date,
          nextDueDate: reminderDays != null ? date.add(Duration(days: reminderDays!)) : null,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Record added'), backgroundColor: AppColors.primaryGreen),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _remindersBanner(List<HealthEvent> events) {
    // Latest event (by date, already sorted desc) per reminder-bearing
    // type, kept only if it's overdue or due within the next 7 days.
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 7));
    final latestByType = <HealthEventType, HealthEvent>{};
    for (final e in events) {
      if (e.nextDueDate == null) continue;
      latestByType.putIfAbsent(e.type, () => e);
    }
    final due = latestByType.values.where((e) => e.nextDueDate!.isBefore(soon)).toList()
      ..sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));
    if (due.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Text('Reminders', style: AppTheme.heading(size: 12, color: AppColors.warning)),
            ],
          ),
          const SizedBox(height: 6),
          ...due.map((e) {
            final overdue = e.nextDueDate!.isBefore(now);
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${e.label}: ${overdue ? 'overdue since' : 'due'} ${_dateFmt.format(e.nextDueDate!)}',
                style: AppTheme.body(size: 11.5, color: overdue ? AppColors.error : AppColors.warning, weight: FontWeight.w600),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEvent(context),
        backgroundColor: AppColors.primaryGreen,
        icon: const Icon(Icons.favorite_border),
        label: const Text('Add Record'),
      ),
      body: StreamBuilder<List<HealthEvent>>(
        stream: FirestoreService.instance.palaiHealthEventsStream(farmId, goat.customerId, goat.id),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(FirestoreService.instance.describeError(snap.error!), style: AppTheme.body(size: 12, color: AppColors.error)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }
          final events = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 90),
            children: [
              _remindersBanner(events),
              if (events.isEmpty)
                Text('No vaccination, hoof cutting, hair trimming or medicine records yet.', style: AppTheme.body(size: 12)),
              ...events.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: AppTheme.card(radius: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconFor(e.type), size: 18, color: AppColors.primaryGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.label, style: AppTheme.heading(size: 13)),
                          if (e.description.isNotEmpty) Text(e.description, style: AppTheme.body(size: 11)),
                          Text('On ${_dateFmt.format(e.date)}', style: AppTheme.body(size: 11)),
                          if (e.nextDueDate != null)
                            Text('Next due: ${_dateFmt.format(e.nextDueDate!)}',
                                style: AppTheme.body(size: 11, color: AppColors.warning, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Monthly Photos — one progress photo per month while the goat is boarded.
// ===========================================================================

class _MonthlyPhotosTab extends StatefulWidget {
  final String farmId;
  final PalaiGoat goat;
  const _MonthlyPhotosTab({required this.farmId, required this.goat});

  @override
  State<_MonthlyPhotosTab> createState() => _MonthlyPhotosTabState();
}

class _MonthlyPhotosTabState extends State<_MonthlyPhotosTab> {
  bool _saving = false;

  Future<void> _addPhoto() async {
    DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return; // user cancelled
      if (!mounted) return;

      final confirmedMonth = await showDialog<DateTime>(
        context: context,
        builder: (ctx) {
          DateTime selected = month;
          return StatefulBuilder(
            builder: (ctx, setState) => AlertDialog(
              title: const Text('Which month is this photo for?'),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<int>(
                    value: selected.month,
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(value: m, child: Text(DateFormat('MMMM').format(DateTime(0, m)))))
                        .toList(),
                    onChanged: (v) => setState(() => selected = DateTime(selected.year, v ?? selected.month, 1)),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: selected.year,
                    items: List.generate(6, (i) => DateTime.now().year - 4 + i)
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (v) => setState(() => selected = DateTime(v ?? selected.year, selected.month, 1)),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Save')),
              ],
            ),
          );
        },
      );
      if (confirmedMonth == null || !mounted) return;

      setState(() => _saving = true);
      await FirestoreService.instance.addMonthlyPhoto(
        widget.farmId,
        widget.goat.customerId,
        widget.goat.id,
        MonthlyPhoto(
          id: '',
          month: confirmedMonth,
          image: picked.bytes,
          imageContentType: picked.contentType,
          capturedAt: DateTime.now(),
        ),
      );
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (e) {
      _showSnack(FirestoreService.instance.describeError(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addPhoto,
        backgroundColor: AppColors.primaryGreen,
        icon: _saving
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add Photo'),
      ),
      body: StreamBuilder<List<MonthlyPhoto>>(
        stream: FirestoreService.instance.monthlyPhotosStream(widget.farmId, widget.goat.customerId, widget.goat.id),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(FirestoreService.instance.describeError(snap.error!), style: AppTheme.body(size: 12, color: AppColors.error)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }
          final photos = snap.data!;
          if (photos.isEmpty) {
            return Center(child: Text('No monthly photos yet.', style: AppTheme.body(size: 12)));
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 90),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final p = photos[index];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FullscreenImageViewer(imageBytes: p.image, title: DateFormat('MMMM yyyy').format(p.month)),
                )),
                child: Container(
                  decoration: AppTheme.card(radius: 14),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    children: [
                      Expanded(
                        child: p.image.isNotEmpty
                            ? Image.memory(p.image, fit: BoxFit.cover, width: double.infinity)
                            : Container(color: AppColors.lightGreen, child: const Icon(Icons.pets, color: AppColors.primaryGreen)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(DateFormat('MMMM yyyy').format(p.month), style: AppTheme.body(size: 11, color: AppColors.textDark, weight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}