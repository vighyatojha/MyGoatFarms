import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/own_farm_models.dart';
import '../../../models/activity_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/photo_upload_circle.dart';

/// Registers a new goat owned by the farm itself (Own Farm Palai), as
/// opposed to a customer's boarded goat.
class AddOwnFarmGoatScreen extends StatefulWidget {
  const AddOwnFarmGoatScreen({super.key});

  @override
  State<AddOwnFarmGoatScreen> createState() => _AddOwnFarmGoatScreenState();
}

class _AddOwnFarmGoatScreenState extends State<AddOwnFarmGoatScreen> {
  final _formKey = GlobalKey<FormState>();
  final _goatCodeController = TextEditingController();
  final _breedController = TextEditingController();
  final _colorController = TextEditingController();
  final _birthWeightController = TextEditingController();
  final _motherCodeController = TextEditingController();
  final _fatherCodeController = TextEditingController();
  final _notesController = TextEditingController();

  String _gender = 'Male';
  String _healthStatus = 'Healthy';
  DateTime _dateOfBirth = DateTime.now();
  bool _saving = false;
  String? _farmId;

  Uint8List? _photoBytes;
  String? _photoContentType;

  static const List<String> _genders = ['Male', 'Female'];
  static const List<String> _healthOptions = ['Healthy', 'Under Treatment', 'Sick', 'Quarantined'];

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  void dispose() {
    _goatCodeController.dispose();
    _breedController.dispose();
    _colorController.dispose();
    _birthWeightController.dispose();
    _motherCodeController.dispose();
    _fatherCodeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
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

  Future<void> _pickDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_farmId == null) return;
    setState(() => _saving = true);

    try {
      final birthWeight = double.tryParse(_birthWeightController.text.trim()) ?? 0;
      final goat = OwnFarmGoat(
        id: '',
        goatCode: _goatCodeController.text.trim(),
        breed: _breedController.text.trim(),
        gender: _gender,
        color: _colorController.text.trim(),
        dateOfBirth: _dateOfBirth,
        birthWeight: birthWeight,
        currentWeight: birthWeight,
        healthStatus: _healthStatus,
        motherCode: _motherCodeController.text.trim(),
        fatherCode: _fatherCodeController.text.trim(),
        notes: _notesController.text.trim(),
        registeredAt: DateTime.now(),
        photo: _photoBytes,
        photoContentType: _photoContentType,
      );

      await FirestoreService.instance.addOwnFarmGoat(_farmId!, goat);
      await FirestoreService.instance.logActivity(
        _farmId!,
        ActivityLog(
          id: '',
          type: ActivityType.ownFarmGoatAdded,
          title: 'Farm Goat Registered',
          subtitle: goat.goatCode +
              (goat.notes.isEmpty ? '' : ' — ${goat.notes}'),
          module: 'ownFarm',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Goat registered');
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
        title: Text('Register Farm Goat', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: PhotoUploadCircle(
                  imageBytes: _photoBytes,
                  label: 'Goat Photo',
                  onTap: _pickPhoto,
                ),
              ),
              const SizedBox(height: 22),
              _label('Goat ID'),
              _textField(_goatCodeController, hint: 'e.g. OF-1001'),
              const SizedBox(height: 16),
              _label('Breed'),
              _textField(_breedController, hint: 'e.g. Sojat, Jamnapari'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Gender'),
                        _dropdown(_gender, _genders, (v) => setState(() => _gender = v)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Color'),
                        _textField(_colorController, hint: 'e.g. Brown & White'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _label('Date of Birth'),
              GestureDetector(
                onTap: _pickDateOfBirth,
                child: Container(
                  decoration: AppTheme.card(radius: 12),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: AppColors.textGrey),
                      const SizedBox(width: 10),
                      Text(
                        '${_dateOfBirth.day}/${_dateOfBirth.month}/${_dateOfBirth.year}',
                        style: AppTheme.body(size: 13, color: AppColors.textDark),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _label('Birth Weight (kg)'),
              _textField(_birthWeightController, hint: 'e.g. 3', keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _label('Health Status'),
              _dropdown(_healthStatus, _healthOptions, (v) => setState(() => _healthStatus = v)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Mother ID'),
                        _textField(_motherCodeController, hint: 'Optional', optional: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Father ID'),
                        _textField(_fatherCodeController, hint: 'Optional', optional: true),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _label('Notes'),
              _textField(_notesController, hint: 'Optional notes', maxLines: 3, optional: true),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Register Goat', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: AppTheme.heading(size: 13)),
  );

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: AppTheme.body(size: 13, color: AppColors.textDark)))).toList(),
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  Widget _textField(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        bool optional = false,
      }) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: (v) => (!optional && (v == null || v.trim().isEmpty)) ? 'Required' : null,
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