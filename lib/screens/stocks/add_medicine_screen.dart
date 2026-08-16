import 'dart:async';

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _thresholdController = TextEditingController(text: '5');
  String _unit = 'bottle';
  bool _saving = false;

  static const List<String> _units = ['bottle', 'pack', 'strip', 'unit'];

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final farmId = await FirestoreService.instance.currentFarmId();
      if (farmId == null) {
        _showSnack('Could not find your farm profile. Please log in again.', isError: true);
        return;
      }

      final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;

      await FirestoreService.instance.addStock(
        farmId,
        itemName: _nameController.text.trim(),
        type: StockType.medicine,
        quantity: quantity,
        unit: _unit,
        lowStockThreshold: double.tryParse(_thresholdController.text.trim()) ?? 0,
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.medicineAdded,
          title: 'Medicine Stock Added',
          subtitle: '${quantity.toStringAsFixed(0)} $_unit of ${_nameController.text.trim()} added',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Medicine stock added');
    } on TimeoutException {
      _showSnack('This is taking too long. Check your connection and try again.', isError: true);
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
        title: Text('Add Medicine Stock', style: AppTheme.heading(size: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Medicine Name'),
              _field(_nameController, hint: 'e.g. Deworming Syrup'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Quantity'),
                        _field(_quantityController, hint: 'e.g. 10', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Unit'),
                        Container(
                          decoration: AppTheme.card(radius: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _unit,
                              isExpanded: true,
                              items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u, style: AppTheme.body(size: 13, color: AppColors.textDark)))).toList(),
                              onChanged: (v) => setState(() => _unit = v ?? _unit),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _label('Low Stock Alert Threshold'),
              _field(_thresholdController, hint: 'e.g. 5', keyboardType: TextInputType.number),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.breedingPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add to Stock', style: TextStyle(fontWeight: FontWeight.w600)),
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

  Widget _field(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        bool optional = false,
      }) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
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