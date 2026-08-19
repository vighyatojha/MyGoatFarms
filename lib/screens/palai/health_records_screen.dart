import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';

/// Maintains health records for a Palai goat: weight, vaccination,
/// deworming, hoof cutting, medicine given, health status (with a date
/// and time) and doctor notes — per the Palai spec.
class HealthRecordsScreen extends StatefulWidget {
  const HealthRecordsScreen({super.key});

  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen> {
  String? _farmId;
  PalaiGoat? _selectedGoat;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  void _openAddEntrySheet() {
    if (_selectedGoat == null || _farmId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHealthRecordSheet(farmId: _farmId!, goat: _selectedGoat!),
    );
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Goat', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 8),
            StreamBuilder<List<PalaiGoat>>(
              stream: FirestoreService.instance.allActiveGoatsStream(_farmId!),
              builder: (context, snap) {
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
                      hint: Text('Choose a goat', style: AppTheme.body(size: 13)),
                      items: goats
                          .map((g) => DropdownMenuItem(value: g, child: Text('${g.goatCode} · ${g.breed}', style: AppTheme.body(size: 13, color: AppColors.textDark))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedGoat = v),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            if (_selectedGoat != null)
              Expanded(
                child: StreamBuilder<List<HealthRecordEntry>>(
                  stream: FirestoreService.instance.healthRecordsStream(
                    _farmId!,
                    _selectedGoat!.customerId,
                    _selectedGoat!.id,
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                    }
                    final entries = snap.data!;
                    if (entries.isEmpty) {
                      return Center(child: Text('No health records yet.', style: AppTheme.body(size: 12)));
                    }
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        final color = _healthColor(e.healthStatus);
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
              ),
          ],
        ),
      ),
      floatingActionButton: _selectedGoat == null
          ? null
          : FloatingActionButton.extended(
        onPressed: _openAddEntrySheet,
        backgroundColor: AppColors.primaryGreen,
        icon: const Icon(Icons.add),
        label: const Text('Add Record'),
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
    await FirestoreService.instance.addHealthRecord(widget.farmId, widget.goat.customerId, widget.goat.id, entry);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
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