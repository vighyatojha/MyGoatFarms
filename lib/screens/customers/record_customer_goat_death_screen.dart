import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/death_settlement_service.dart';

/// Record Death & Settlement for a Customer Palai goat.
///
/// The farm owner enters two numbers: what was pending for this
/// specific goat, and what the customer will actually be asked to pay.
/// Whatever gap is waived between the two is recorded as a Goat Death
/// Loss — see DeathSettlementService.recordCustomerPalaiDeath.
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
  final _pendingChargeController = TextEditingController();
  final _amountToPayController = TextEditingController();

  DateTime _deathDate = DateTime.now();
  bool _saving = false;

  double get _pendingCharge =>
      double.tryParse(_pendingChargeController.text.trim()) ?? 0;

  double get _amountToPay =>
      double.tryParse(_amountToPayController.text.trim()) ?? 0;

  /// Waived amount — this is what gets recorded as a farm loss.
  double get _loss => (_pendingCharge - _amountToPay).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    // Default assumption: the customer pays in full (no loss) unless the
    // farm owner deliberately lowers it. Pre-filling the pending charge
    // with the customer's current combined balance is only a starting
    // point when this is their only goat — it's always editable, since
    // the app doesn't track a live per-goat balance.
    _amountToPayController.addListener(() {});
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    _pendingChargeController.dispose();
    _amountToPayController.dispose();
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

    final pendingCharge = _pendingCharge;
    final amountToPay = _amountToPay;
    final loss = _loss;
    final currentPending = widget.customer.pendingAmount;
    final pendingAfter = currentPending - pendingCharge + amountToPay;

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
              Text('This Goat\'s Pending Charge: ₹${pendingCharge.toStringAsFixed(0)}'),
              Text('Customer Will Pay: ₹${amountToPay.toStringAsFixed(0)}'),
              const SizedBox(height: 6),
              if (loss > 0)
                Text(
                  'Farm Loss: ₹${loss.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                )
              else
                const Text(
                  'No farm loss — the customer is paying the full pending charge.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
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
        goatPendingCharge: pendingCharge,
        customerAmountToPay: amountToPay,
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
                    'Customer Pending: ₹${widget.customer.pendingAmount.toStringAsFixed(0)}',
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

            Text('This Goat\'s Settlement', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 4),
            Text(
              'Enter what was pending specifically for this goat, and what '
                  'the customer will actually pay. Anything waived is '
                  'recorded as a farm loss. Leave both blank if nothing was '
                  'pending for this goat.',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
            const SizedBox(height: 10),

            Text(
              'This Goat\'s Pending Charge (₹)',
              style: AppTheme.body(size: 11, weight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _pendingChargeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g. 5000',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: _validateAmount,
              onChanged: (v) {
                setState(() {
                  // Default the "will pay" field to match, so the common
                  // case (pay in full, no loss) needs no second entry —
                  // the farm owner only edits it when waiving something.
                  if (_amountToPayController.text.trim().isEmpty ||
                      _amountToPayController.text.trim() ==
                          _lastAutoFilledPendingCharge) {
                    _amountToPayController.text = v;
                  }
                  _lastAutoFilledPendingCharge = v;
                });
              },
            ),
            const SizedBox(height: 14),

            Text(
              'Amount Customer Will Pay (₹)',
              style: AppTheme.body(size: 11, weight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountToPayController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g. 2000',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: _validateAmount,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _loss > 0
                    ? AppColors.error.withOpacity(0.08)
                    : AppColors.primaryGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _loss > 0
                        ? 'Farm Loss: ₹${_loss.toStringAsFixed(0)}'
                        : 'No farm loss — full amount will be collected.',
                    style: AppTheme.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: _loss > 0 ? AppColors.error : AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Customer Pending: ₹${widget.customer.pendingAmount.toStringAsFixed(0)} → '
                        '₹${(widget.customer.pendingAmount - _pendingCharge + _amountToPay).toStringAsFixed(0)}',
                    style: AppTheme.body(size: 11, color: AppColors.textDark),
                  ),
                ],
              ),
            ),

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

  // Tracks the last value we auto-filled into "amount to pay" from the
  // pending-charge field, so we stop overwriting it the moment the farm
  // owner types their own figure in — see the pending-charge onChanged
  // above.
  String _lastAutoFilledPendingCharge = '';

  String? _validateAmount(String? v) {
    final amount = double.tryParse((v ?? '').trim());
    if (v != null && v.trim().isNotEmpty && amount == null) {
      return 'Enter a valid amount';
    }
    if (amount != null && amount < 0) {
      return 'Amount cannot be negative';
    }
    return null;
  }
}