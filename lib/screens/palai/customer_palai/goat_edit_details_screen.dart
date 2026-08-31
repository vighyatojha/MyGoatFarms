import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';
import '../../../widgets/image_source_sheet.dart';

/// Edits a goat's basic registration details — deliberately the SAME
/// field set as CustomerGoatRegistrationScreen, nothing more:
///
///   Before Palai Photo, Goat Code, Breed, Gender, Color,
///   Date Goat Came Into Farm, Weight, Health Status,
///   Monthly Package, Pricing, Notes
///
/// This does NOT touch check-in/checkout state, current weight
/// (that's driven by Health Updates now), or report history — those
/// belong to their own flows. It's purely for correcting a mistake
/// made at registration, or updating package/pricing going forward.
class GoatEditDetailsScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const GoatEditDetailsScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<GoatEditDetailsScreen> createState() => _GoatEditDetailsScreenState();
}

class _GoatEditDetailsScreenState extends State<GoatEditDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _goatCodeController;
  late final TextEditingController _breedController;
  late final TextEditingController _colorController;
  late final TextEditingController _weightController;
  late final TextEditingController _pricingController;
  late final TextEditingController _notesController;

  late String _gender;
  late String _healthStatus;
  late String _monthlyPackage;
  DateTime? _farmArrivalDate;

  Uint8List? _beforeImageBytes;
  String? _beforeImageContentType;

  bool _saving = false;

  static const List<String> _genders = ['Male', 'Female'];
  static const List<String> _healthOptions = ['Healthy', 'Under Observation', 'Sick'];
  static const List<String> _packages = ['Basic Palai', 'Standard Palai', 'Special Palai'];

  @override
  void initState() {
    super.initState();
    final goat = widget.goat;
    _goatCodeController = TextEditingController(text: goat.goatCode);
    _breedController = TextEditingController(text: goat.breed);
    _colorController = TextEditingController(text: goat.color);
    _weightController = TextEditingController(text: goat.weightAtCheckIn.toStringAsFixed(1));
    _pricingController = TextEditingController(text: goat.pricing.toStringAsFixed(2));
    _notesController = TextEditingController(text: goat.notes);
    _gender = _genders.contains(goat.gender) ? goat.gender : 'Male';
    _healthStatus = _healthOptions.contains(goat.healthStatus) ? goat.healthStatus : 'Healthy';
    _monthlyPackage = _packages.contains(goat.monthlyPackage) ? goat.monthlyPackage : _packages.first;
    _farmArrivalDate = goat.farmArrivalDate ?? goat.checkInDate;
    _beforeImageBytes = goat.beforeImage;
    _beforeImageContentType = goat.beforeImageContentType;
  }

  @override
  void dispose() {
    _goatCodeController.dispose();
    _breedController.dispose();
    _colorController.dispose();
    _weightController.dispose();
    _pricingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickBeforePhoto() async {
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return;
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

  Future<void> _selectFarmArrivalDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _farmArrivalDate ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Select Goat Arrival Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );
    if (selected != null) setState(() => _farmArrivalDate = selected);
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    if (_farmArrivalDate == null) {
      _showSnack('Please select the date the goat came into the farm.', isError: true);
      return;
    }

    final weight = double.tryParse(_weightController.text.trim());
    if (weight == null || weight <= 0) {
      _showSnack('Please enter a valid goat weight.', isError: true);
      return;
    }

    final pricingText = _pricingController.text.trim();
    final pricing = pricingText.isEmpty ? 0.0 : double.tryParse(pricingText);
    if (pricing == null || pricing < 0) {
      _showSnack('Please enter a valid pricing amount.', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final updated = widget.goat.copyWith(
        goatCode: _goatCodeController.text.trim(),
        breed: _breedController.text.trim(),
        gender: _gender,
        color: _colorController.text.trim(),
        weightAtCheckIn: weight,
        healthStatus: _healthStatus,
        farmArrivalDate: _farmArrivalDate,
        monthlyPackage: _monthlyPackage,
        pricing: pricing,
        notes: _notesController.text.trim(),
        beforeImage: _beforeImageBytes,
        beforeImageContentType: _beforeImageContentType,
        updatedAt: DateTime.now(),
      );

      await FirestoreService.instance.updateGoatDetails(
        widget.farmId,
        widget.customerId,
        widget.goat.id,
        updated,
      );

      if (!mounted) return;
      _showSnack('Goat details updated.');
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not update goat details: $e', isError: true);
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
        title: Text('Edit Goat Details', style: AppTheme.heading(size: 17)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            _buildPhotoSection(),
            const SizedBox(height: 24),
            _sectionTitle('Goat Information'),
            const SizedBox(height: 12),
            _textField(
              controller: _goatCodeController,
              label: 'Goat Code',
              hint: 'e.g. GP-11',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            _textField(
              controller: _breedController,
              label: 'Breed',
              hint: 'e.g. Boer, Sirohi',
              icon: Icons.pets_outlined,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _dropdownField(
                    label: 'Gender',
                    value: _gender,
                    icon: Icons.wc_outlined,
                    options: _genders,
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField(
                    controller: _colorController,
                    label: 'Color',
                    hint: 'e.g. White',
                    optional: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _sectionTitle('Check-In Information'),
            const SizedBox(height: 12),
            _buildFarmArrivalDateField(),
            const SizedBox(height: 12),
            _textField(
              controller: _weightController,
              label: 'Weight (kg)',
              hint: 'e.g. 24.5',
              icon: Icons.monitor_weight_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            _dropdownField(
              label: 'Health Status',
              value: _healthStatus,
              icon: Icons.health_and_safety_outlined,
              options: _healthOptions,
              onChanged: (v) => setState(() => _healthStatus = v),
            ),
            const SizedBox(height: 16),
            _dropdownField(
              label: 'Monthly Package',
              value: _monthlyPackage,
              icon: Icons.card_membership_outlined,
              options: _packages,
              onChanged: (v) => setState(() => _monthlyPackage = v),
            ),
            const SizedBox(height: 16),
            _textField(
              controller: _pricingController,
              label: 'Pricing (₹/month)',
              hint: 'e.g. 2800',
              icon: Icons.currency_rupee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              optional: true,
            ),
            const SizedBox(height: 28),
            _sectionTitle('Additional Information'),
            const SizedBox(height: 12),
            _textField(
              controller: _notesController,
              label: 'Notes',
              hint: 'Any additional notes',
              maxLines: 3,
              optional: true,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _saving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _saving ? 'Saving...' : 'Save Changes',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickBeforePhoto,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryGreen.withOpacity(0.4), width: 1.5),
              ),
              child: _beforeImageBytes != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(_beforeImageBytes!, fit: BoxFit.cover),
              )
                  : const Icon(Icons.add_a_photo_outlined, color: AppColors.primaryGreen, size: 30),
            ),
          ),
          const SizedBox(height: 8),
          Text('Before Palai Photo', style: AppTheme.body(size: 11.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildFarmArrivalDateField() {
    final date = _farmArrivalDate;
    final dateText = date == null
        ? 'Select date'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return InkWell(
      onTap: _selectFarmArrivalDate,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date Goat Came Into Farm',
          hintText: 'Select arrival date',
          prefixIcon: Icon(Icons.calendar_month_outlined),
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dateText,
                style: TextStyle(color: date == null ? AppColors.textGrey : AppColors.textDark, fontSize: 16),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: AppTheme.heading(size: 18));

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool optional = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      validator: optional
          ? null
          : (value) {
        if (value == null || value.trim().isEmpty) return 'Required';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: options.map((option) => DropdownMenuItem<String>(value: option, child: Text(option))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}