import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/image_source_sheet.dart';
import '../../widgets/photo_upload_circle.dart';
import 'add_customer_screen.dart';

/// Records a new goat check-in for Palai boarding: a "Before Palai" photo
/// (camera or device storage — same picker as the Profile photo), Goat
/// ID, breed, gender, age/weight, color, health status, owner (customer),
/// check-in date, monthly package and notes — per the Palai spec.
class CheckInGoatScreen extends StatefulWidget {
  /// When opened from a customer's profile, pre-fills the owner field so
  /// the person doesn't have to pick the same customer again.
  final PalaiCustomer? presetCustomer;
  const CheckInGoatScreen({super.key, this.presetCustomer});

  @override
  State<CheckInGoatScreen> createState() => _CheckInGoatScreenState();
}

class _CheckInGoatScreenState extends State<CheckInGoatScreen> {
  final _formKey = GlobalKey<FormState>();
  final _goatCodeController = TextEditingController();
  final _breedController = TextEditingController();
  final _colorController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();
  String _gender = 'Male';
  String _healthStatus = 'Healthy';
  String _monthlyPackage = 'Basic Palai';
  PalaiCustomer? _selectedCustomer;
  bool _saving = false;
  String? _farmId;

  // "Before Palai" photo, taken/picked at check-in time.
  Uint8List? _beforeImageBytes;
  String? _beforeImageContentType;

  static const List<String> _genders = ['Male', 'Female'];
  static const List<String> _healthOptions = ['Healthy', 'Under Observation', 'Sick'];
  static const List<String> _packages = ['Basic Palai', 'Standard Palai', 'Special Palai'];

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.presetCustomer;
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  void dispose() {
    _goatCodeController.dispose();
    _breedController.dispose();
    _colorController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickBeforePhoto() async {
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return; // user cancelled
      setState(() {
        _beforeImageBytes = picked.bytes;
        _beforeImageContentType = picked.contentType;
      });
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Could not add photo. Please try again.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer / owner'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_farmId == null) return;
    setState(() => _saving = true);

    final goat = PalaiGoat(
      id: '',
      customerId: _selectedCustomer!.id,
      goatCode: _goatCodeController.text.trim(),
      breed: _breedController.text.trim(),
      gender: _gender,
      color: _colorController.text.trim(),
      weightAtCheckIn: double.tryParse(_weightController.text.trim()) ?? 0,
      healthStatus: _healthStatus,
      checkInDate: DateTime.now(),
      monthlyPackage: _monthlyPackage,
      notes: _notesController.text.trim(),
      beforeImage: _beforeImageBytes,
      beforeImageContentType: _beforeImageContentType,
    );

    await FirestoreService.instance.checkInGoat(_farmId!, _selectedCustomer!.id, goat);
    await FirestoreService.instance.logActivity(
      _farmId!,
      ActivityLog(
        id: '',
        type: ActivityType.goatCheckIn,
        title: 'Goat Check-In',
        subtitle: '${goat.goatCode} · ${_selectedCustomer!.name}',
        module: 'palai',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Goat checked in successfully'), backgroundColor: AppColors.primaryGreen),
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
        title: Text('Goat Check-In', style: AppTheme.heading(size: 17)),
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
                  imageBytes: _beforeImageBytes,
                  label: 'Before Palai Photo',
                  onTap: _pickBeforePhoto,
                ),
              ),
              const SizedBox(height: 22),
              _label('Owner (Customer)'),
              _customerPicker(_farmId!),
              const SizedBox(height: 16),
              _label('Goat ID'),
              _textField(_goatCodeController, hint: 'e.g. G-1001'),
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
              _label('Weight (kg)'),
              _textField(_weightController, hint: 'e.g. 35', keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _label('Health Status'),
              _dropdown(_healthStatus, _healthOptions, (v) => setState(() => _healthStatus = v)),
              const SizedBox(height: 16),
              _label('Monthly Package'),
              _dropdown(_monthlyPackage, _packages, (v) => setState(() => _monthlyPackage = v)),
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
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save & Check-In Goat', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customerPicker(String farmId) {
    return StreamBuilder<List<PalaiCustomer>>(
      stream: FirestoreService.instance.customersStream(farmId),
      builder: (context, snap) {
        final customers = snap.data ?? [];
        return Container(
          decoration: AppTheme.card(radius: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PalaiCustomer>(
                    value: _selectedCustomer,
                    isExpanded: true,
                    hint: Text('Select customer', style: AppTheme.body(size: 13)),
                    items: customers
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: AppTheme.body(size: 13, color: AppColors.textDark))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCustomer = v),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(fastRoute(const AddCustomerScreen())),
                child: Text('+ New', style: AppTheme.body(size: 12, color: AppColors.primaryGreen, weight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
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