import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';

/// The fully-reconstructed Health section — one of the tabs inside the
/// new Goat Profile screen.
///
///   HEALTH
///   │
///   ├── Current Health   (derived from the latest record)
///   ├── Health Update     (+ button, opens a form)
///   ├── Health History    (a timeline, every record kept — never
///   │                      overwritten — with View/Edit)
///   └── Health Reminders  (next check date, surfaced at the top when
///                          due or overdue)
///
/// Widget sizes are kept deliberately compact (11–13px text, tight
/// paddings) so more of the timeline is visible per screen.
class GoatHealthTab extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const GoatHealthTab({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<GoatHealthTab> createState() => _GoatHealthTabState();
}

class _GoatHealthTabState extends State<GoatHealthTab> {
  late Stream<List<HealthRecordEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirestoreService.instance.healthRecordsStream(
      widget.farmId,
      widget.customerId,
      widget.goat.id,
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;
      case 'Under Observation':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'Sick':
        return '🔴';
      case 'Under Observation':
        return '🟡';
      default:
        return '🟢';
    }
  }

  Future<void> _openUpdateForm({HealthRecordEntry? editing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HealthUpdateFormScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goat: widget.goat,
          editing: editing,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(HealthRecordEntry record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(
          'The health update from ${DateFormat('d MMM yyyy').format(record.recordedAt)} will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirestoreService.instance.deleteHealthRecord(
        widget.farmId,
        widget.customerId,
        widget.goat.id,
        record.id,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete record: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HealthRecordEntry>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            ),
          );
        }

        final records = snapshot.data ?? [];
        final latest = records.isNotEmpty ? records.first : null;

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
          children: [
            _buildReminderBanner(latest),
            _buildCurrentHealthCard(latest),
            const SizedBox(height: 14),
            _sectionLabel('Health History', '${records.length} record${records.length == 1 ? '' : 's'}'),
            const SizedBox(height: 8),
            if (records.isEmpty)
              _emptyHistory()
            else
              for (final record in records) _historyTile(record),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String title, String trailing) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTheme.heading(size: 13))),
        Text(trailing, style: AppTheme.body(size: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _buildReminderBanner(HealthRecordEntry? latest) {
    final nextCheck = latest?.nextCheckDate;
    if (nextCheck == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final isOverdue = nextCheck.isBefore(DateTime(now.year, now.month, now.day));
    final isDueToday = !isOverdue &&
        nextCheck.year == now.year &&
        nextCheck.month == now.month &&
        nextCheck.day == now.day;

    if (!isOverdue && !isDueToday) return const SizedBox.shrink();

    final color = isOverdue ? AppColors.error : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOverdue
                  ? 'Health check overdue — was due ${DateFormat('d MMM').format(nextCheck)}'
                  : 'Health check due today',
              style: AppTheme.body(size: 11.5, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentHealthCard(HealthRecordEntry? latest) {
    final status = latest?.healthStatus ?? widget.goat.healthStatus;
    final color = _statusColor(status);

    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_statusEmoji(status), style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status.isNotEmpty ? status : 'No health data yet',
                  style: AppTheme.heading(size: 14).copyWith(color: color),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openUpdateForm(),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Update Health'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side: const BorderSide(color: AppColors.primaryGreen),
                  foregroundColor: AppColors.primaryGreen,
                  textStyle: AppTheme.body(size: 11.5),
                ),
              ),
            ],
          ),
          if (latest != null) ...[
            const Divider(height: 18),
            _kvGrid([
              ('Last Check', DateFormat('d MMM yyyy').format(latest.recordedAt)),
              ('Weight', '${latest.weight.toStringAsFixed(1)} kg'),
              if (latest.appetite.isNotEmpty) ('Appetite', latest.appetite),
              if (latest.activity.isNotEmpty) ('Activity', latest.activity),
              if (latest.temperature.isNotEmpty) ('Temperature', latest.temperature),
              (
              'Treatment',
              latest.treatment.isNotEmpty
                  ? latest.treatment
                  : (latest.medicineGiven.isNotEmpty ? latest.medicineGiven : 'None'),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'No health updates recorded yet for this goat. Tap "Update Health" to add the first one.',
              style: AppTheme.body(size: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kvGrid(List<(String, String)> pairs) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final pair in pairs)
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pair.$1, style: AppTheme.body(size: 10, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text(pair.$2, style: AppTheme.heading(size: 12.5)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _emptyHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: AppTheme.card(radius: 12),
      child: Column(
        children: [
          Icon(Icons.health_and_safety_outlined, size: 28, color: AppColors.textMuted.withOpacity(0.6)),
          const SizedBox(height: 8),
          Text('No health history yet', style: AppTheme.body(size: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _historyTile(HealthRecordEntry record) {
    final color = _statusColor(record.healthStatus);
    final summaryParts = <String>[
      if (record.symptoms.isNotEmpty) record.symptoms,
      if (record.diseaseOrProblem.isNotEmpty) record.diseaseOrProblem,
      if (record.medicineGiven.isNotEmpty) 'Medicine: ${record.medicineGiven}',
    ];
    final summary = summaryParts.isNotEmpty ? summaryParts.join(' · ') : 'No symptoms or issues noted';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.card(radius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormat('d MMM yyyy').format(record.recordedAt),
                      style: AppTheme.heading(size: 12.5),
                    ),
                    const SizedBox(width: 6),
                    Text(record.healthStatus, style: AppTheme.body(size: 11, color: color)),
                    if (record.updatedAt != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.edit, size: 11, color: AppColors.textMuted.withOpacity(0.7)),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11, color: AppColors.textMuted),
                ),
                if (record.image != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(record.image!, width: 44, height: 44, fit: BoxFit.cover),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
            onSelected: (value) {
              if (value == 'edit') _openUpdateForm(editing: record);
              if (value == 'delete') _confirmDelete(record);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HEALTH UPDATE FORM (create + edit share this screen)
// ============================================================================

class _HealthUpdateFormScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;
  final HealthRecordEntry? editing;

  const _HealthUpdateFormScreen({
    required this.farmId,
    required this.customerId,
    required this.goat,
    this.editing,
  });

  @override
  State<_HealthUpdateFormScreen> createState() => _HealthUpdateFormScreenState();
}

class _HealthUpdateFormScreenState extends State<_HealthUpdateFormScreen> {
  static const _statusOptions = ['Healthy', 'Under Observation', 'Sick'];
  static const _levelOptions = ['Good', 'Normal', 'Poor'];

  late String _status;
  late TextEditingController _weightController;
  late TextEditingController _symptomsController;
  String? _appetite;
  String? _activity;
  late TextEditingController _temperatureController;
  late TextEditingController _diseaseController;
  late TextEditingController _medicineController;
  late TextEditingController _treatmentController;
  late TextEditingController _notesController;
  DateTime? _nextCheckDate;

  PickedImage? _newPhoto;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _status = e?.healthStatus.isNotEmpty == true ? e!.healthStatus : 'Healthy';
    _weightController = TextEditingController(
      text: (e?.weight ?? widget.goat.currentWeight ?? widget.goat.weightAtCheckIn).toStringAsFixed(1),
    );
    _symptomsController = TextEditingController(text: e?.symptoms ?? '');
    _appetite = e?.appetite.isNotEmpty == true ? e!.appetite : null;
    _activity = e?.activity.isNotEmpty == true ? e!.activity : null;
    _temperatureController = TextEditingController(text: e?.temperature ?? '');
    _diseaseController = TextEditingController(text: e?.diseaseOrProblem ?? '');
    _medicineController = TextEditingController(text: e?.medicineGiven ?? '');
    _treatmentController = TextEditingController(text: e?.treatment ?? '');
    _notesController = TextEditingController(text: e?.doctorNotes ?? '');
    _nextCheckDate = e?.nextCheckDate;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _symptomsController.dispose();
    _temperatureController.dispose();
    _diseaseController.dispose();
    _medicineController.dispose();
    _treatmentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImageService.instance.pickFromCamera(
        maxStoredBytes: 200 * 1024,
        maxDimension: 480,
      );
      if (picked != null && mounted) {
        setState(() => _newPhoto = picked);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Please try again.')),
      );
    }
  }

  Future<void> _pickNextCheckDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextCheckDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _nextCheckDate = picked);
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightController.text.trim());
    if (weight == null || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final entry = HealthRecordEntry(
        id: widget.editing?.id ?? '',
        weight: weight,
        vaccination: widget.editing?.vaccination ?? '',
        deworming: widget.editing?.deworming ?? '',
        hoofCutting: widget.editing?.hoofCutting ?? '',
        medicineGiven: _medicineController.text.trim(),
        healthStatus: _status,
        doctorNotes: _notesController.text.trim(),
        symptoms: _symptomsController.text.trim(),
        appetite: _appetite ?? '',
        activity: _activity ?? '',
        temperature: _temperatureController.text.trim(),
        diseaseOrProblem: _diseaseController.text.trim(),
        treatment: _treatmentController.text.trim(),
        nextCheckDate: _nextCheckDate,
        image: _newPhoto?.bytes ?? widget.editing?.image,
        imageContentType: _newPhoto?.contentType ?? widget.editing?.imageContentType ?? 'image/jpeg',
        recordedAt: widget.editing?.recordedAt ?? DateTime.now(),
      );

      if (_isEditing) {
        await FirestoreService.instance.updateHealthRecord(
          widget.farmId,
          widget.customerId,
          widget.goat.id,
          entry,
        );
      } else {
        await FirestoreService.instance.addHealthRecord(
          widget.farmId,
          widget.customerId,
          widget.goat.id,
          entry,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save health update: $e')),
      );
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
        title: Text(_isEditing ? 'Edit Health Update' : 'Update Health', style: AppTheme.heading(size: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _label('Health Status'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final option in _statusOptions)
                ChoiceChip(
                  label: Text(option, style: const TextStyle(fontSize: 12)),
                  selected: _status == option,
                  onSelected: (_) => setState(() => _status = option),
                  selectedColor: AppColors.primaryGreen.withOpacity(0.2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _textField(_weightController, 'Weight (kg)', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _dropdown('Appetite', _appetite, (v) => setState(() => _appetite = v))),
              const SizedBox(width: 10),
              Expanded(child: _dropdown('Activity', _activity, (v) => setState(() => _activity = v))),
            ],
          ),
          const SizedBox(height: 10),
          _textField(_temperatureController, 'Temperature (optional)'),
          const SizedBox(height: 10),
          _textField(_symptomsController, 'Symptoms (optional)', maxLines: 2),
          const SizedBox(height: 10),
          _textField(_diseaseController, 'Disease / Problem (optional)'),
          const SizedBox(height: 10),
          _textField(_medicineController, 'Medicine (optional)'),
          const SizedBox(height: 10),
          _textField(_treatmentController, 'Treatment (optional)', maxLines: 2),
          const SizedBox(height: 10),
          _textField(_notesController, 'Notes (optional)', maxLines: 3),
          const SizedBox(height: 14),
          _label('Next Check Date (optional)'),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickNextCheckDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.event_outlined, size: 18),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              child: Text(
                _nextCheckDate != null ? DateFormat('d MMM yyyy').format(_nextCheckDate!) : 'Not scheduled',
                style: AppTheme.body(size: 13),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _label('Photo (optional)'),
          const SizedBox(height: 6),
          Row(
            children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryGreen.withOpacity(0.4)),
                  ),
                  child: _newPhoto != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.memory(_newPhoto!.bytes, fit: BoxFit.cover),
                  )
                      : (widget.editing?.image != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.memory(widget.editing!.image!, fit: BoxFit.cover),
                  )
                      : const Icon(Icons.camera_alt_outlined, color: AppColors.primaryGreen)),
                ),
              ),
              const SizedBox(width: 10),
              Text('Tap to capture', style: AppTheme.body(size: 11.5, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEditing ? 'Save Changes' : 'Save Health Update'),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: AppTheme.body(size: 11.5, color: AppColors.textMuted));

  Widget _textField(
      TextEditingController controller,
      String label, {
        int maxLines = 1,
        TextInputType? keyboardType,
      }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: AppTheme.body(size: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: AppTheme.body(size: 12, color: AppColors.textMuted),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _dropdown(String label, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: AppTheme.body(size: 12, color: AppColors.textMuted),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: [
        for (final option in _levelOptions)
          DropdownMenuItem(value: option, child: Text(option, style: const TextStyle(fontSize: 13))),
      ],
      onChanged: onChanged,
    );
  }
}