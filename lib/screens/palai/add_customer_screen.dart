import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../utils/billing_ledger.dart';

/// Add / Edit form for a Palai customer.
///
/// Pass no [customer] to create a new one. Pass an existing [customer] to
/// edit it in place — the form pre-fills, the button becomes "Update
/// Customer", and a delete action appears in the app bar so the whole
/// create/read/update/delete flow lives in one screen.
///
/// New customers: the farm ENROLLMENT DATE decides where billing starts.
/// If they enrolled before the month the next Generate Bills run covers
/// (e.g. enrolled 25 July, added 4 October → first bill is September),
/// the form asks whether July – August are fully paid. If not, the amount
/// still owed is saved as an opening balance ('Pending before September
/// 2026') that is carried forward on the first bill, never charged again.
///
/// Editing never changes the pending amount: balances move only through
/// bills, payments, checkout, death settlement and corrections.
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
  /// New customers only: amount still owed for the months before the
  /// first bill, when the owner says they are not fully paid.
  final _openingController = TextEditingController();

  /// New customers only: date the customer joined the farm.
  DateTime _enrollmentDate = DateUtils.dateOnly(DateTime.now());

  /// New customers only: answer to "Are <months> fully paid?".
  /// Null until answered.
  bool? _earlierMonthsPaid;
  late final _priceController =
  TextEditingController(text: widget.customer != null ? _trimZero(widget.customer!.price) : '');
  late String _package = widget.customer?.package ?? 'Basic Palai';
  bool _saving = false;
  bool _deleting = false;

  static String _trimZero(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _openingController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  EnrollmentBilling get _plan => enrollmentBilling(
    enrollmentDate: _enrollmentDate,
    today: DateTime.now(),
  );

  double get _openingAmount =>
      double.tryParse(_openingController.text.trim()) ?? 0;

  Future<void> _pickEnrollmentDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _enrollmentDate,
      firstDate: DateTime(today.year - 10),
      lastDate: today,
      helpText: 'Farm enrollment date',
    );
    if (picked == null) return;
    setState(() {
      _enrollmentDate = DateUtils.dateOnly(picked);
      // Different months may now be asked about.
      _earlierMonthsPaid = null;
      _openingController.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (!widget.isEditing && _plan.asksAboutEarlierMonths) {
      if (_earlierMonthsPaid == null) {
        _showError('Answer whether ${_plan.monthsBeforeLabel} is fully paid.');
        return;
      }
      if (_earlierMonthsPaid == false && _openingAmount <= 0) {
        _showError('Enter the total pending for ${_plan.monthsBeforeLabel}.');
        return;
      }
    }

    setState(() => _saving = true);

    final farmId = await FirestoreService.instance.currentFarmId();
    if (farmId == null) {
      setState(() => _saving = false);
      return;
    }

    final price = double.tryParse(_priceController.text.trim()) ?? 0;

    try {
      if (widget.isEditing) {
        final updated = widget.customer!.copyWith(
          name: _nameController.text.trim(),
          mobileNumber: _mobileController.text.trim(),
          address: _addressController.text.trim(),
          package: _package,
          price: price,
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
          joiningDate: _enrollmentDate,
          pendingAmount: 0,
          price: price,
        );
        await MonthlyStatementEngine.instance.addCustomerWithEnrollment(
          farmId: farmId,
          customer: customer,
          pendingBeforeBilling: _plan.asksAboutEarlierMonths &&
              _earlierMonthsPaid == false
              ? _openingAmount
              : 0,
        );
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
              if (widget.isEditing)
                _buildPendingReadOnly()
              else
                _buildEnrollment(),
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

  // ===========================================================================
  // ENROLLMENT (new customers)
  // ===========================================================================

  Widget _buildEnrollment() {
    final plan = _plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Farm Enrollment Date'),
        InkWell(
          onTap: _saving ? null : _pickEnrollmentDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(radius: 12),
            child: Row(
              children: [
                const Icon(Icons.event_outlined, size: 18, color: AppColors.primaryGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DateFormat('d MMMM yyyy').format(_enrollmentDate),
                    style: AppTheme.body(size: 13, color: AppColors.textDark),
                  ),
                ),
                const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.textGrey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'The app bills this customer from ${periodLabel(plan.firstBilledKey)}.',
          style: AppTheme.body(size: 11.5),
        ),
        if (plan.asksAboutEarlierMonths) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(radius: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are the ${plan.monthsBeforeLabel} Palai bills fully paid?',
                  style: AppTheme.heading(size: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'These months are before the app\'s first bill, so the app '
                      'will not charge them.',
                  style: AppTheme.body(size: 11.5),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('Yes, fully paid'),
                      selected: _earlierMonthsPaid == true,
                      selectedColor: AppColors.lightGreen,
                      onSelected: (_) => setState(() {
                        _earlierMonthsPaid = true;
                        _openingController.clear();
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('No, amount pending'),
                      selected: _earlierMonthsPaid == false,
                      selectedColor: AppColors.lightGreen,
                      onSelected: (_) =>
                          setState(() => _earlierMonthsPaid = false),
                    ),
                  ],
                ),
                if (_earlierMonthsPaid == false) ...[
                  const SizedBox(height: 14),
                  _label('Total pending for ${plan.monthsBeforeLabel} (₹)'),
                  _textField(
                    _openingController,
                    hint: 'e.g. 5000',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Shown on the first bill as "${plan.openingBalanceLabel}" '
                        'and carried forward. It is never charged again.',
                    style: AppTheme.body(size: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPendingReadOnly() {
    final customer = widget.customer!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Pending amount', style: AppTheme.heading(size: 13)),
              ),
              Text(
                '₹${_trimZero(customer.pendingAmount)}',
                style: AppTheme.heading(size: 14, color: AppColors.darkGreen),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Changes only through bills, payments, checkout and corrections, '
                'so it cannot be edited here.',
            style: AppTheme.body(size: 11.5),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
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