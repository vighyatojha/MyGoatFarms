import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/monthly_bill_model.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../utils/billing_ledger.dart';

/// Corrects the charges on a customer's LATEST, unlocked statement.
///
/// Each goat's amount, other charges and discount can be changed. The
/// previous outstanding and advance applied stay exactly as issued, and
/// only the difference between the new and old charge moves the
/// customer's pending. Pops `true` when saved.
class EditStatementScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final MonthlyBill bill;

  const EditStatementScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.bill,
  });

  @override
  State<EditStatementScreen> createState() => _EditStatementScreenState();
}

class _EditStatementScreenState extends State<EditStatementScreen> {
  final Map<String, TextEditingController> _goatControllers = {};
  late final TextEditingController _otherController;
  late final TextEditingController _discountController;
  late final TextEditingController _reasonController;
  late final TextEditingController _notesController;

  bool _saving = false;

  MonthlyBill get _bill => widget.bill;

  @override
  void initState() {
    super.initState();
    for (final line in _bill.goatBreakdown) {
      _goatControllers[line.goatId] = TextEditingController(
        text: line.palaiAmount.toStringAsFixed(2),
      );
    }
    _otherController =
        TextEditingController(text: _bill.otherCharges.toStringAsFixed(2));
    _discountController =
        TextEditingController(text: _bill.discount.toStringAsFixed(2));
    _reasonController = TextEditingController();
    _notesController = TextEditingController(text: _bill.notes);
  }

  @override
  void dispose() {
    for (final c in _goatControllers.values) {
      c.dispose();
    }
    _otherController.dispose();
    _discountController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double _value(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  Map<String, double> get _goatAmounts => {
    for (final entry in _goatControllers.entries)
      entry.key: _value(entry.value),
  };

  double get _newCharges => roundMoney(
    _goatAmounts.values.fold<double>(0, (s, v) => s + v) +
        _value(_otherController) -
        _value(_discountController),
  );

  /// Live preview with the same rule the save uses.
  ({StatementEdit? edit, String? problem}) get _preview {
    try {
      final edit = computeStatementEdit(
        oldCharges: _bill.effectiveOwnCharges,
        newCharges: _newCharges,
        ownPaid: _bill.effectiveOwnPaid,
        previousOutstanding: _bill.previousOutstanding,
        advanceApplied: _bill.advanceApplied,
        amountPaid: _bill.amountPaid,
      );
      return (edit: edit, problem: null);
    } on StateError catch (e) {
      return (edit: null, problem: e.message);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final preview = _preview;
    if (preview.edit == null) {
      _snack(preview.problem ?? 'Check the amounts.', error: true);
      return;
    }
    if (_goatAmounts.values.any((v) => v < 0) ||
        _value(_otherController) < 0 ||
        _value(_discountController) < 0) {
      _snack('Amounts cannot be negative.', error: true);
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      _snack('Add a short reason for the correction.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await MonthlyStatementEngine.instance.editStatement(
        farmId: widget.farmId,
        customerId: widget.customerId,
        billId: _bill.id,
        goatAmounts: _goatAmounts,
        otherCharges: _value(_otherController),
        discount: _value(_discountController),
        notes: _notesController.text,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      _snack('Bill ${_bill.billNumber} corrected.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(
        'Could not save: ${FirestoreService.instance.describeError(e)}',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final edit = preview.edit;
    final month = periodLabel(_bill.billingPeriodKey);

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Correct $month bill', style: AppTheme.heading(size: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '${_bill.billNumber}. Previous outstanding and advance stay as '
                'issued; only the difference in this month\'s charges changes '
                'what the customer owes.',
            style: AppTheme.body(size: 12),
          ),
          const SizedBox(height: 14),
          _card(
            title: '$month charges',
            children: [
              for (final line in _bill.goatBreakdown) ...[
                _amountField(
                  controller: _goatControllers[line.goatId]!,
                  label: line.displayLabel,
                ),
                const SizedBox(height: 10),
              ],
              _amountField(controller: _otherController, label: 'Other charges'),
              const SizedBox(height: 10),
              _amountField(controller: _discountController, label: 'Discount'),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Result',
            children: [
              _row('$month charges', _currency(_bill.effectiveOwnCharges),
                  _currency(_newCharges)),
              _row('Total payable', _currency(_bill.totalPayable),
                  edit == null ? '—' : _currency(edit.totalPayable)),
              _row('Remaining on bill', _currency(_bill.remainingAmount),
                  edit == null ? '—' : _currency(edit.remaining)),
              const Divider(height: 18),
              Text(
                edit == null
                    ? preview.problem ?? ''
                    : edit.pendingDelta.abs() < kMoneyEpsilon
                    ? 'No change to what the customer owes.'
                    : 'Customer pending will '
                    '${edit.pendingDelta > 0 ? 'go up' : 'go down'} by '
                    '${_currency(edit.pendingDelta.abs())}.',
                style: AppTheme.body(
                  size: 12.5,
                  color: edit == null ? AppColors.error : AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Reason and notes',
            children: [
              TextField(
                controller: _reasonController,
                decoration: _decoration('Reason for correction (required)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: _decoration('Bill notes'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            onPressed: _saving || edit == null ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Text('Save correction'),
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.heading(size: 14)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: _decoration(label).copyWith(prefixText: '₹ '),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    isDense: true,
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _row(String label, String before, String after) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(size: 12.5, color: AppColors.textDark),
            ),
          ),
          Text(before, style: AppTheme.body(size: 12)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 14, color: AppColors.textGrey),
          ),
          Text(
            after,
            style: AppTheme.body(
              size: 12.5,
              color: AppColors.textDark,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _currency(double value) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  ).format(value);

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
      ),
    );
  }
}