import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/hoof_cutting_record.dart';
import '../../../models/palai_models.dart';

/// Full-page "Add Hoof Cutting" screen, pushed from the Hoof Cutting
/// tab on GoatProfileScreen (see AddVaccinationScreen for why this is
/// a pushed screen and not a dialog).
class AddHoofCuttingScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;
  final int reminderDays;

  const AddHoofCuttingScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
    this.reminderDays = 30,
  });

  @override
  State<AddHoofCuttingScreen> createState() => _AddHoofCuttingScreenState();
}

class _AddHoofCuttingScreenState extends State<AddHoofCuttingScreen> {
  final _performedByController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _cuttingDate = DateTime.now();
  DateTime? _nextDueDate;
  bool _saving = false;

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
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final reference = _hoofCollection.doc();
      final record = HoofCuttingRecord(
        id: reference.id,
        goatId: widget.goat.id,
        cuttingDate: _cuttingDate,
        nextDueDate: _nextDueDate,
        performedBy: _performedByController.text.trim(),
        note: _noteController.text.trim(),
        recordedAt: DateTime.now(),
      );
      await reference.set(record.toCreateMap());

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save hoof cutting: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Hoof Cutting')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _DateTile(
            label: 'Cutting date',
            date: _cuttingDate,
            onTap: () => _pickDate(
              initial: _cuttingDate,
              first: DateTime(2000),
              last: DateTime.now(),
              onPicked: (d) => setState(() => _cuttingDate = d),
            ),
          ),
          const SizedBox(height: 14),
          _DateTile(
            label: 'Next due date',
            date: _nextDueDate,
            optional: true,
            onTap: () => _pickDate(
              initial: _nextDueDate ?? _cuttingDate.add(Duration(days: widget.reminderDays)),
              first: _cuttingDate,
              last: DateTime(2100),
              onPicked: (d) => setState(() => _nextDueDate = d),
            ),
            onClear: _nextDueDate == null ? null : () => setState(() => _nextDueDate = null),
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
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryGreen),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateTile({
    required this.label,
    required this.date,
    this.optional = false,
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
          date != null ? DateFormat('d MMM yyyy').format(date!) : 'Not set',
          style: TextStyle(color: date != null ? null : AppColors.textMuted),
        ),
      ),
    );
  }
}