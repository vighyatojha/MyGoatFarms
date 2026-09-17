import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/trading_goat_weight_entry.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/image_service.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/photo_upload_circle.dart';

/// Task 3.2 — "log a new weight entry" form, reached from the Growth
/// Tracking section of the Own Palai Goat Profile.
///
/// Writes a single doc to `tradingGoats/{goatId}/weightHistory` via
/// [GoatService.addWeightEntry]. Nothing else on the goat doc changes
/// — Current/Previous Weight and the Weight Gain figure shown on the
/// profile are always derived from this subcollection, never stored
/// separately (per the phase 3 plan's data-model note on
/// `weightHistory`).
///
/// The photo here is the plan's "Monthly Photos" requirement (Section
/// 5): optional, no one-per-month enforcement — just a free-form
/// gallery entry attached to whichever weight check it was taken at.
class AddWeightEntryScreen extends StatefulWidget {
  final String farmId;
  final String goatId;

  const AddWeightEntryScreen({
    super.key,
    required this.farmId,
    required this.goatId,
  });

  @override
  State<AddWeightEntryScreen> createState() => _AddWeightEntryScreenState();
}

class _AddWeightEntryScreenState extends State<AddWeightEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _date = DateTime.now();
  Uint8List? _photoBytes;
  String? _photoContentType;

  bool _saving = false;

  @override
  void dispose() {
    _weightController.dispose();
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

  Future<void> _pickPhoto() async {
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return;
      setState(() {
        _photoBytes = picked.bytes;
        _photoContentType = picked.contentType;
      });
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Could not add photo. Please try again.', isError: true);
    }
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final weight = double.tryParse(_weightController.text.trim()) ?? 0;

    setState(() => _saving = true);

    try {
      await GoatService.instance.addWeightEntry(
        farmId: widget.farmId,
        goatId: widget.goatId,
        entry: GoatWeightEntry(
          id: '',
          weight: weight,
          date: _date,
          photo: _photoBytes,
          photoContentType: _photoContentType,
          notes: _notesController.text,
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
        title: Text('Log Weight Entry', style: AppTheme.heading(size: 17)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: PhotoUploadCircle(
                    imageBytes: _photoBytes,
                    label: 'Monthly Photo (Optional)',
                    onTap: _pickPhoto,
                  ),
                ),
                const SizedBox(height: 22),
                _label('Weight (kg)'),
                _textField(
                  _weightController,
                  hint: 'e.g. 24.5',
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final value = double.tryParse((v ?? '').trim());
                    if (value == null || value <= 0) {
                      return 'Enter a valid weight';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
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
                          style: AppTheme.body(
                              size: 13, color: AppColors.textDark),
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
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
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
                        : const Text(
                      'Save Weight Entry',
                      style: TextStyle(fontWeight: FontWeight.w700),
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