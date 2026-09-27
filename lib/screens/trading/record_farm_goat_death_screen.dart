import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/goat_model.dart';
import '../../services/death_settlement_service.dart';

/// Record Death for an Own Palai or Available Stock goat.
///
/// There is no customer settlement here — the goat belongs to the farm,
/// so its value is recorded as a Goat Death Loss in Finance instead. See
/// DeathSettlementService.recordFarmGoatDeath.
class RecordFarmGoatDeathScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const RecordFarmGoatDeathScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<RecordFarmGoatDeathScreen> createState() =>
      _RecordFarmGoatDeathScreenState();
}

class _RecordFarmGoatDeathScreenState
    extends State<RecordFarmGoatDeathScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _deathDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deathDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _deathDate = picked);
    }
  }

  Future<void> _confirmAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    final goatLabel = widget.goat.isOwnPalai ? 'Own Palai' : 'Available Stock';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Goat Death'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location: $goatLabel'),
            Text('Death Date: ${DateFormat('dd MMM yyyy').format(_deathDate)}'),
            Text('Reason: ${_reasonController.text.trim()}'),
            const SizedBox(height: 10),
            const Text(
              'The goat will be marked Dead, its history will remain '
                  'available, and no future charges will be generated for it. '
                  'Its value will be recorded as a Goat Death Loss in Finance.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Death'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);

    try {
      await DeathSettlementService.instance.recordFarmGoatDeath(
        farmId: widget.farmId,
        goatId: widget.goat.id,
        deathDate: _deathDate,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      _showSnack('Goat death recorded.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not record death: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Record Death'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No customer settlement applies — this goat belongs '
                          'to the farm. Its value will be recorded as a Goat '
                          'Death Loss.',
                      style: AppTheme.body(size: 11, color: AppColors.textDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Death Date', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textGrey),
                    const SizedBox(width: 10),
                    Text(DateFormat('dd MMM yyyy').format(_deathDate)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Reason', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _reasonController,
              decoration: InputDecoration(
                hintText: 'e.g. Illness, Accident',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
            ),
            const SizedBox(height: 16),

            Text('Notes (optional)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Any additional notes',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _confirmAndSave,
                icon: _saving
                    ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.pets_outlined),
                label: Text(_saving ? 'Saving...' : 'Record Death'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}