import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/death_record.dart';
import '../../models/palai_models.dart';
import '../../services/death_settlement_service.dart';

/// Record Death & Settlement for a Customer Palai goat.
///
/// Lets the user settle the goat's death against the customer's account
/// either as a credit (customer owes less) or a debit (customer owes
/// more) — see DeathSettlementService.recordCustomerPalaiDeath.
class RecordCustomerGoatDeathScreen extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;
  final PalaiGoat goat;

  const RecordCustomerGoatDeathScreen({
    super.key,
    required this.farmId,
    required this.customer,
    required this.goat,
  });

  @override
  State<RecordCustomerGoatDeathScreen> createState() =>
      _RecordCustomerGoatDeathScreenState();
}

class _RecordCustomerGoatDeathScreenState
    extends State<RecordCustomerGoatDeathScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  final _amountController = TextEditingController();

  DateTime _deathDate = DateTime.now();
  String _direction = DeathRecord.directionCredit;
  bool _saving = false;

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deathDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _deathDate = picked);
    }
  }

  String get _goatLabel {
    if (widget.goat.tagNumber.trim().isNotEmpty) return widget.goat.tagNumber;
    if (widget.goat.goatCode.trim().isNotEmpty) return widget.goat.goatCode;
    if (widget.goat.name.trim().isNotEmpty) return widget.goat.name;
    return 'Goat';
  }

  Future<void> _confirmAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = _amount;
    final isCredit = _direction == DeathRecord.directionCredit;
    final currentPending = widget.customer.pendingAmount;
    final pendingAfter = amount <= 0
        ? currentPending
        : (isCredit ? currentPending - amount : currentPending + amount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Goat Death'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Goat: $_goatLabel'),
              Text('Customer: ${widget.customer.name}'),
              Text('Death Date: ${DateFormat('dd MMM yyyy').format(_deathDate)}'),
              Text('Reason: ${_reasonController.text.trim()}'),
              const SizedBox(height: 10),
              if (amount > 0)
                Text(
                  '${isCredit ? '+' : '-'} ₹${amount.toStringAsFixed(0)} '
                      '${isCredit ? 'Customer Credit' : 'Customer Debit'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )
              else
                const Text('No settlement amount — death recorded only.'),
              const SizedBox(height: 6),
              Text(
                'Customer Pending: ₹${currentPending.toStringAsFixed(0)} '
                    '→ ₹${pendingAfter.toStringAsFixed(0)}',
              ),
              const SizedBox(height: 10),
              const Text(
                'The goat will be marked Dead, its history will remain '
                    'available, and no future charges will be generated for it.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Death'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);

    try {
      await DeathSettlementService.instance.recordCustomerPalaiDeath(
        farmId: widget.farmId,
        customerId: widget.customer.id,
        goatId: widget.goat.id,
        deathDate: _deathDate,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim(),
        settlementAmount: amount,
        direction: amount > 0 ? _direction : null,
      );

      if (!mounted) return;
      _showSnack('Goat death recorded and settled.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not record death: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Record Death & Settlement'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pets_outlined, color: AppColors.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_goatLabel, style: AppTheme.heading(size: 14)),
                        Text(
                          widget.customer.name,
                          style: AppTheme.body(size: 11, color: AppColors.textGrey),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Pending: ₹${widget.customer.pendingAmount.toStringAsFixed(0)}',
                    style: AppTheme.body(size: 11, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Death Date', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textGrey),
                    const SizedBox(width: 10),
                    Text(DateFormat('dd MMM yyyy').format(_deathDate)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Reason', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _reasonController,
              decoration: InputDecoration(
                hintText: 'e.g. Illness, Accident',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
            ),
            const SizedBox(height: 16),

            Text('Notes (optional)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Any additional notes',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            Text('Settlement (optional)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 4),
            Text(
              'Leave the amount blank if no money should move either way.',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Settlement Amount (₹)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim());
                if (v != null && v.trim().isNotEmpty && amount == null) {
                  return 'Enter a valid amount';
                }
                if (amount != null && amount < 0) {
                  return 'Amount cannot be negative';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),

            if (_amount > 0) ...[
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: DeathRecord.directionCredit,
                groupValue: _direction,
                onChanged: (v) => setState(() => _direction = v!),
                title: const Text(
                  'Add to customer account',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: const Text(
                  'Customer owes less (credit)',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: DeathRecord.directionDebit,
                groupValue: _direction,
                onChanged: (v) => setState(() => _direction = v!),
                title: const Text(
                  'Deduct from customer account',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: const Text(
                  'Customer owes more (debit)',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Customer Pending: ₹${widget.customer.pendingAmount.toStringAsFixed(0)} → '
                    '₹${(_direction == DeathRecord.directionCredit ? widget.customer.pendingAmount - _amount : widget.customer.pendingAmount + _amount).toStringAsFixed(0)}',
                style: AppTheme.body(size: 12, weight: FontWeight.w700, color: AppColors.textDark),
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _confirmAndSave,
                icon: _saving
                    ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.pets_outlined),
                label: Text(_saving ? 'Saving...' : 'Record Death'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}