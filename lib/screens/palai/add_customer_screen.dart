import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  String _package = 'Basic Palai';
  bool _saving = false;

  static const List<String> _packages = ['Basic Palai', 'Standard Palai', 'Special Palai'];

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final farmId = await FirestoreService.instance.currentFarmId();
    if (farmId == null) {
      setState(() => _saving = false);
      return;
    }

    final customer = PalaiCustomer(
      id: '',
      name: _nameController.text.trim(),
      mobileNumber: _mobileController.text.trim(),
      address: _addressController.text.trim(),
      package: _package,
      joiningDate: DateTime.now(),
      pendingAmount: 0,
    );

    await FirestoreService.instance.addCustomer(farmId, customer);
    await FirestoreService.instance.logActivity(
      farmId,
      ActivityLog(
        id: '',
        type: ActivityType.goatCheckIn,
        title: 'New Customer Added',
        subtitle: '${customer.name} joined Palai ($_package)',
        module: 'palai',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Customer added successfully'), backgroundColor: AppColors.primaryGreen),
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
        title: Text('Add Customer', style: AppTheme.heading(size: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Customer Name'),
              _textField(_nameController, hint: 'e.g. Rameshbhai Patel'),
              const SizedBox(height: 16),
              _label('Mobile Number'),
              _textField(_mobileController, hint: '10-digit mobile number', keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              _label('Address'),
              _textField(_addressController, hint: 'Village / City, District', maxLines: 2, optional: true),
              const SizedBox(height: 16),
              _label('Palai Package'),
              Container(
                decoration: AppTheme.card(radius: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _package,
                    isExpanded: true,
                    items: _packages.map((p) => DropdownMenuItem(value: p, child: Text(p, style: AppTheme.body(size: 13, color: AppColors.textDark)))).toList(),
                    onChanged: (v) => setState(() => _package = v ?? _package),
                  ),
                ),
              ),
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
                      : const Text('Save Customer', style: TextStyle(fontWeight: FontWeight.w600)),
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
