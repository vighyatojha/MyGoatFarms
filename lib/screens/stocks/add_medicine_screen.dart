import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static const _units = ['bottle', 'pack', 'strip', 'unit'];

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : AppColors.primaryGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;

    if (quantity <= 0) {
      _message('Enter a quantity greater than 0.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final farmId = await FirestoreService.instance.currentFarmId();

      if (farmId == null) {
        _message('Could not find your farm profile. Please log in again.', error: true);
        return;
      }

      final name = _nameController.text.trim();

      await FirestoreService.instance.addStock(
        farmId,
        itemName: name,
        type: StockType.medicine,
        quantity: quantity,
        unit: _unit,
        lowStockThreshold: threshold,
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.medicineAdded,
          title: 'Medicine Stock Added',
          subtitle: '${quantity.toStringAsFixed(0)} $_unit of $name added',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Medicine stock added successfully');
    } on TimeoutException {
      _message('Connection is taking too long. Please try again.', error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
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
        titleSpacing: 4,
        title: Text('Add Medicine', style: AppTheme.heading(size: 18)),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(_saving ? 'Saving...' : 'Add to Medicine Stock'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _hero(),
              const SizedBox(height: 16),
              _section(
                title: 'Medicine details',
                icon: Icons.medication_outlined,
                children: [
                  _field(
                    controller: _nameController,
                    label: 'Medicine name',
                    hint: 'Deworming Syrup, Liver Tonic...',
                    icon: Icons.medication_rounded,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _field(
                          controller: _quantityController,
                          label: 'Quantity',
                          hint: '10',
                          icon: Icons.inventory_2_outlined,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: _unitSelector()),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Stock alert',
                icon: Icons.notifications_active_outlined,
                children: [
                  _field(
                    controller: _thresholdController,
                    label: 'Low-stock threshold',
                    hint: '5',
                    suffix: _unit,
                    icon: Icons.warning_amber_rounded,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use a threshold that should trigger an early reorder warning.',
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _infoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, AppColors.darkGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkGreen.withOpacity(.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.medication_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add medicine to inventory', style: AppTheme.heading(size: 17, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'Keep medicine quantities and reorder alerts accurate.',
                  style: AppTheme.body(size: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _unitSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unit', style: AppTheme.body(size: 11, color: AppColors.textGrey, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _unit,
              isExpanded: true,
              items: _units
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(u, style: AppTheme.body(size: 12, color: AppColors.textDark)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _unit = v ?? _unit),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
      style: AppTheme.body(size: 13, color: AppColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
        suffixText: suffix,
        labelStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        hintStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
        ),
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.darkGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Record medicines using the unit shown on the package. This makes usage history easier to understand.',
              style: AppTheme.body(size: 11, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
