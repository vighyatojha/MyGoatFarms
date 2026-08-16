import 'dart:async';

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

class AddFeedStockScreen extends StatefulWidget {
  const AddFeedStockScreen({super.key});

  @override
  State<AddFeedStockScreen> createState() => _AddFeedStockScreenState();
}

class _AddFeedStockScreenState extends State<AddFeedStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Mix Feed');
  final _quantityController = TextEditingController();
  final _thresholdController = TextEditingController(text: '20');
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _thresholdController.dispose();
    _notesController.dispose();
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
        type: StockType.feed,
        quantity: quantity,
        unit: 'kg',
        lowStockThreshold: double.tryParse(_thresholdController.text.trim()) ?? 0,
        notes: _notesController.text.trim(),
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.feedStockAdded,
          title: 'Feed Stock Added',
          subtitle: '${quantity.toStringAsFixed(0)} kg of ${_nameController.text.trim()} added',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Feed stock added');
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
        title: Text('Add Feed Stock', style: AppTheme.heading(size: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Feed Name'),
              _field(_nameController, hint: 'e.g. Mix Feed, Green Fodder'),
              const SizedBox(height: 16),
              _label('Quantity (kg)'),
              _field(_quantityController, hint: 'e.g. 100', keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _label('Low Stock Alert Threshold (kg)'),
              _field(_thresholdController, hint: 'e.g. 20', keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _label('Notes'),
              _field(_notesController, hint: 'Optional', maxLines: 2, optional: true),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.stockTeal,
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