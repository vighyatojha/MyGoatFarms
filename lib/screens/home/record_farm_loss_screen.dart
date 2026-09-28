import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/death_record.dart';
import '../../services/death_settlement_service.dart';
import '../../services/image_service.dart';
import '../../widgets/Loss_proof.dart';

/// Record a manual farm loss — fire, theft, disease, spoiled feed,
/// storm damage, or anything else that isn't a goat's death.
///
/// A proof photo (receipt, damage photo, report) can be attached, but
/// is entirely optional — Save is never blocked on it. See
/// DeathSettlementService.recordManualLoss.
class RecordFarmLossScreen extends StatefulWidget {
  final String farmId;

  const RecordFarmLossScreen({super.key, required this.farmId});

  @override
  State<RecordFarmLossScreen> createState() => _RecordFarmLossScreenState();
}

class _RecordFarmLossScreenState extends State<RecordFarmLossScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  String _category = DeathRecord.categoryOther;
  DateTime _lossDate = DateTime.now();
  bool _isCashLoss = false;
  PickedImage? _proofImage;
  bool _saving = false;

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
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
      initialDate: _lossDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _lossDate = picked);
  }

  Future<void> _pickProofImage() async {
    final picked = await pickLossProofImage(context);
    if (picked != null && mounted) {
      setState(() => _proofImage = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final lossId = await DeathSettlementService.instance.recordManualLoss(
        farmId: widget.farmId,
        category: _category,
        lossDate: _lossDate,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        amount: _amount,
        isCashLoss: _isCashLoss,
      );

      // Proof is optional, so this only runs if the owner actually
      // picked a photo — the record above is already saved either way.
      if (_proofImage != null) {
        try {
          await DeathSettlementService.instance.addLossProof(
            farmId: widget.farmId,
            lossId: lossId,
            image: _proofImage!,
          );
        } catch (_) {
          // The loss itself is already recorded — a failed photo
          // upload shouldn't look like the whole save failed. It can
          // always be added later from the loss card.
          if (mounted) {
            _showSnack(
              'Loss recorded, but the photo failed to upload. You can add '
                  'it again later.',
              isError: true,
            );
          }
        }
      }

      if (!mounted) return;
      _showSnack('Farm loss recorded.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not record loss: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Record Farm Loss'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Loss Type', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  items: DeathRecord.manualLossCategories
                      .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(DeathRecord.categoryLabelFor(c)),
                  ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Loss Date', style: AppTheme.heading(size: 13)),
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
                    Text(DateFormat('dd MMM yyyy').format(_lossDate)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Title', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'e.g. Store room fire',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),

            Text('Description (optional)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'What happened',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            Text('Loss Amount (₹)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g. 15000',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim());
                if (v == null || v.trim().isEmpty) return 'Amount is required';
                if (amount == null) return 'Enter a valid amount';
                if (amount < 0) return 'Amount cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Cash actually left the farm', style: AppTheme.body(size: 13)),
                subtitle: Text(
                  'Off for a pure value loss (e.g. spoiled feed thrown away). '
                      'On if you paid for repairs, replacement, etc.',
                  style: AppTheme.body(size: 11, color: AppColors.textGrey),
                ),
                value: _isCashLoss,
                onChanged: (v) => setState(() => _isCashLoss = v),
                activeColor: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 16),

            Text('Proof (optional)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 4),
            Text(
              'A photo of the receipt, damage, or report — helpful for your '
                  'records, but not required to save this loss.',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
            const SizedBox(height: 10),
            if (_proofImage != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _proofImage!.bytes,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: () => setState(() => _proofImage = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            else
              InkWell(
                onTap: _pickProofImage,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_outlined, color: AppColors.textGrey),
                      const SizedBox(height: 6),
                      Text('Add a photo', style: AppTheme.body(size: 12, color: AppColors.textGrey)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.report_gmailerrorred_outlined),
                label: Text(_saving ? 'Saving...' : 'Record Loss'),
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