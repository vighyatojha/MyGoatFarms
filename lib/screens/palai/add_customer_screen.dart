import 'dart:async';

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Add / Edit form for a Palai customer.
///
/// Pass no [customer] to create a new one. Pass an existing [customer] to
/// edit it in place — the form pre-fills, the button becomes "Update
/// Customer", and a delete action appears in the app bar so the whole
/// create/read/update/delete flow lives in one screen.
class AddCustomerScreen extends StatefulWidget {
  final PalaiCustomer? customer;

  const AddCustomerScreen({super.key, this.customer});

  bool get isEditing => customer != null;

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.customer?.name ?? '');
  late final _mobileController = TextEditingController(text: widget.customer?.mobileNumber ?? '');
  late final _addressController = TextEditingController(text: widget.customer?.address ?? '');
  late final _pendingController =
      TextEditingController(text: widget.customer != null ? _trimZero(widget.customer!.pendingAmount) : '0');
  late String _package = widget.customer?.package ?? 'Basic Palai';
  bool _saving = false;
  bool _deleting = false;

  static const List<String> _packages = ['Basic Palai', 'Standard Palai', 'Special Palai'];

  static String _trimZero(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _pendingController.dispose();
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

    final pendingAmount = double.tryParse(_pendingController.text.trim()) ?? 0;

    try {
      if (widget.isEditing) {
        final updated = widget.customer!.copyWith(
          name: _nameController.text.trim(),
          mobileNumber: _mobileController.text.trim(),
          address: _addressController.text.trim(),
          package: _package,
          pendingAmount: pendingAmount,
        );
        await FirestoreService.instance.updateCustomer(farmId, updated);
        await FirestoreService.instance.logActivity(
          farmId,
          ActivityLog(
            id: '',
            type: ActivityType.customerUpdated,
            title: 'Customer Updated',
            subtitle: '${updated.name} · $_package',
            module: 'palai',
            timestamp: DateTime.now(),
          ),
        );
      } else {
        final customer = PalaiCustomer(
          id: '',
          name: _nameController.text.trim(),
          mobileNumber: _mobileController.text.trim(),
          address: _addressController.text.trim(),
          package: _package,
          joiningDate: DateTime.now(),
          pendingAmount: pendingAmount,
        );
        await FirestoreService.instance.addCustomer(farmId, customer);
        await FirestoreService.instance.logActivity(
          farmId,
          ActivityLog(
            id: '',
            type: ActivityType.customerAdded,
            title: 'New Customer Added',
            subtitle: '${customer.name} joined Palai ($_package)',
            module: 'palai',
            timestamp: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditing ? 'Customer updated successfully' : 'Customer added successfully'),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is taking too long. Check your connection and try again.'), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final customer = widget.customer;
    if (customer == null) return;

    final farmId = await FirestoreService.instance.currentFarmId();
    if (farmId == null) return;

    final hasActiveGoats = await FirestoreService.instance.customerHasActiveGoats(farmId, customer.id);
    if (!mounted) return;
    if (hasActiveGoats) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Cannot delete ${customer.name}', style: AppTheme.heading(size: 16)),
          content: Text(
            'This customer still has goats checked into Palai. Check out all of their goats before deleting the customer.',
            style: AppTheme.body(size: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('OK', style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w600))),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${customer.name}?', style: AppTheme.heading(size: 16)),
        content: Text(
          'This permanently removes the customer and their Palai history. This cannot be undone.',
          style: AppTheme.body(size: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: AppTheme.body(size: 13, color: AppColors.textGrey))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: AppTheme.body(size: 13, color: AppColors.error, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await FirestoreService.instance.deleteCustomer(farmId, customer.id);
      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.customerDeleted,
          title: 'Customer Deleted',
          subtitle: '${customer.name} removed from Palai',
          module: 'palai',
          timestamp: DateTime.now(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${customer.name} deleted'), backgroundColor: AppColors.darkGreen),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is taking too long. Check your connection and try again.'), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _deleting;
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(widget.isEditing ? 'Edit Customer' : 'Add Customer', style: AppTheme.heading(size: 17)),
        actions: [
          if (widget.isEditing)
            IconButton(
              onPressed: busy ? null : _confirmDelete,
              icon: _deleting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                  : const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Delete customer',
            ),
        ],
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
              const SizedBox(height: 16),
              _label('Pending Amount (₹)'),
              _textField(_pendingController, hint: '0', keyboardType: const TextInputType.numberWithOptions(decimal: true), optional: true),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.isEditing ? 'Update Customer' : 'Save Customer', style: const TextStyle(fontWeight: FontWeight.w600)),
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
