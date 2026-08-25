import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../widgets/image_source_sheet.dart';
import 'fullscreen_image_viewer.dart';

/// Maintains a boarded Palai goat's checkup log — weight, health status,
/// doctor notes, and an optional photo per entry.
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
    FirestoreService.instance.currentFarmId().then((id) async {
      if (!mounted || id == null) {
        if (mounted) setState(() => _farmId = id);
        return;
      }
      // Repair any goat docs missing `farmId` before this screen's
      // "Select Goat" dropdown queries them — see backfillMissingGoatFarmIds.
      try {
        debugPrint('========================================');
        debugPrint('GOAT FARM ID BACKFILL STARTED');
        debugPrint('Farm ID: $id');

        await FirestoreService.instance.backfillMissingGoatFarmIds(id);

        debugPrint('GOAT FARM ID BACKFILL COMPLETED');
        debugPrint('========================================');
      } catch (e, stack) {
        debugPrint('========================================');
        debugPrint('GOAT FARM ID BACKFILL FAILED');
        debugPrint('Farm ID: $id');
        debugPrint('Error: $e');
        debugPrintStack(stackTrace: stack);
        debugPrint('========================================');
      }
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
                  debugPrint('========================================');
                  debugPrint('HEALTH RECORDS - GOAT QUERY ERROR');
                  debugPrint('Farm ID: $_farmId');
                  debugPrint('Error: ${snap.error}');
                  debugPrint('Error type: ${snap.error.runtimeType}');
                  debugPrint('========================================');

                  return _errorBanner(
                    'Could not load goats.\n\n'
                        '${FirestoreService.instance.describeError(snap.error!)}',
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
                child: _CheckupsTab(farmId: _farmId!, goat: _selectedGoat!, healthColor: _healthColor),
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
                    if (e.image != null && e.image!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => FullscreenImageViewer(
                            imageBytes: e.image!,
                            title: DateFormat('dd MMM yyyy').format(e.recordedAt),
                          ),
                        )),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            e.image!,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
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
  PickedImage? _pickedImage;
  bool _saving = false;

  Future<void> _pickImage() async {
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null || !mounted) return; // user cancelled
      setState(() => _pickedImage = picked);
    } on ImageTooLargeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

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
      image: _pickedImage?.bytes,
      imageContentType: _pickedImage?.contentType ?? 'image/jpeg',
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
            const SizedBox(height: 10),
            Text('Photo (optional)', style: AppTheme.body(size: 12, color: AppColors.textDark)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(10),
              child: _pickedImage == null
                  ? Container(
                decoration: AppTheme.card(radius: 10),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.add_a_photo_outlined, size: 18, color: AppColors.primaryGreen),
                    const SizedBox(width: 10),
                    Text('Attach a photo', style: AppTheme.body(size: 13, color: AppColors.textDark)),
                  ],
                ),
              )
                  : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Image.memory(
                      _pickedImage!.bytes,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: InkWell(
                        onTap: () => setState(() => _pickedImage = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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