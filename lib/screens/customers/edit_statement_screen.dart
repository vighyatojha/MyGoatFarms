import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/monthly_bill_model.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../utils/billing_ledger.dart';

/// Edit Bill: corrects the charges on a customer's LATEST, unlocked bill.
///
/// Laid out like the bill itself:
///   1. Bill header (number, period, issued, status).
///   2. Every goat: dates on the farm, days charged, monthly rate and the
///      amount, with the change against the issued bill. Days and rate
///      work the amount out automatically; the amount can also be typed
///      directly ("Set amount by hand").
///   3. Other charges and discount.
///   4. The full statement, issued → after edit: month charges, previous
///      outstanding (by month), advance, already paid, Total Payable,
///      paid on this bill, remaining, and how the customer's pending moves.
///   5. Reason (required) and bill notes.
///
/// Previous outstanding, advance and money already paid stay exactly as
/// issued; only the difference in this month's charges changes what the
/// customer owes. Pops `true` when saved.
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

/// Editing state of one goat line.
class _GoatEdit {
  _GoatEdit(this.line)
      : days = TextEditingController(text: '${line.billableDays ?? 0}'),
        rate = TextEditingController(
          text: (line.monthlyRate ?? 0).toStringAsFixed(2),
        ),
        amount = TextEditingController(
          text: line.palaiAmount.toStringAsFixed(2),
        ),
        manual = line.billableDays == null ||
            line.daysInMonth == null ||
            line.monthlyRate == null;

  final GoatBillingLine line;
  final TextEditingController days;
  final TextEditingController rate;
  final TextEditingController amount;

  /// True: amount typed by hand. False: worked out from days × rate.
  bool manual;

  bool get canCalculate => line.daysInMonth != null && line.daysInMonth! > 0;

  int get dayCount => int.tryParse(days.text.trim()) ?? 0;

  double get monthlyRate => double.tryParse(rate.text.trim()) ?? 0;

  double get value {
    if (manual || !canCalculate) {
      return roundMoney(double.tryParse(amount.text.trim()) ?? 0);
    }
    return roundMoney(monthlyRate / line.daysInMonth! * dayCount);
  }

  bool get daysOrRateChanged =>
      !manual &&
          canCalculate &&
          (dayCount != (line.billableDays ?? 0) ||
              (monthlyRate - (line.monthlyRate ?? 0)).abs() > 0.005);

  void reset() {
    days.text = '${line.billableDays ?? 0}';
    rate.text = (line.monthlyRate ?? 0).toStringAsFixed(2);
    amount.text = line.palaiAmount.toStringAsFixed(2);
    manual = line.billableDays == null ||
        line.daysInMonth == null ||
        line.monthlyRate == null;
  }

  void dispose() {
    days.dispose();
    rate.dispose();
    amount.dispose();
  }
}

class _EditStatementScreenState extends State<EditStatementScreen> {
  late final List<_GoatEdit> _goats;
  late final TextEditingController _otherController;
  late final TextEditingController _discountController;
  late final TextEditingController _reasonController;
  late final TextEditingController _notesController;

  bool _saving = false;

  MonthlyBill get _bill => widget.bill;

  @override
  void initState() {
    super.initState();
    _goats = [for (final line in _bill.goatBreakdown) _GoatEdit(line)];
    _otherController =
        TextEditingController(text: _bill.otherCharges.toStringAsFixed(2));
    _discountController =
        TextEditingController(text: _bill.discount.toStringAsFixed(2));
    _reasonController = TextEditingController();
    _notesController = TextEditingController(text: _bill.notes);
  }

  @override
  void dispose() {
    for (final g in _goats) {
      g.dispose();
    }
    _otherController.dispose();
    _discountController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // FIGURES
  // ===========================================================================

  double _value(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  double get _palaiNew =>
      roundMoney(_goats.fold<double>(0, (s, g) => s + g.value));

  double get _palaiOld => roundMoney(
    _bill.goatBreakdown.fold<double>(0, (s, l) => s + l.palaiAmount),
  );

  double get _newCharges => roundMoney(
    _palaiNew + _value(_otherController) - _value(_discountController),
  );

  /// Advance used + money paid on a deleted bill: both were taken off this
  /// bill when it was made and stay taken off.
  double get _deductions =>
      roundMoney(_bill.advanceApplied + _bill.paidFromDeletedBill);

  ({StatementEdit? edit, String? problem}) get _preview {
    for (final g in _goats) {
      if (g.value < 0) {
        return (edit: null, problem: 'Amounts cannot be negative.');
      }
      if (!g.manual &&
          g.canCalculate &&
          (g.dayCount < 0 || g.dayCount > g.line.daysInMonth!)) {
        return (
        edit: null,
        problem: '${g.line.label}: days must be between 0 and '
            '${g.line.daysInMonth}.',
        );
      }
    }
    if (_value(_otherController) < 0 || _value(_discountController) < 0) {
      return (edit: null, problem: 'Amounts cannot be negative.');
    }
    try {
      final edit = computeStatementEdit(
        oldCharges: _bill.effectiveOwnCharges,
        newCharges: _newCharges,
        ownPaid: _bill.effectiveOwnPaid,
        previousOutstanding: _bill.previousOutstanding,
        advanceApplied: _deductions,
        amountPaid: _bill.amountPaid,
      );
      return (edit: edit, problem: null);
    } on StateError catch (e) {
      return (edit: null, problem: e.message);
    }
  }

  bool get _anythingChanged =>
      (_newCharges - _bill.effectiveOwnCharges).abs() > kMoneyEpsilon ||
          _goats.any((g) => g.daysOrRateChanged) ||
          _notesController.text.trim() != _bill.notes.trim();

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final preview = _preview;
    if (preview.edit == null) {
      _snack(preview.problem ?? 'Check the amounts.', error: true);
      return;
    }
    if (!_anythingChanged) {
      _snack('Nothing has changed.', error: true);
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
        goatAmounts: {for (final g in _goats) g.line.goatId: g.value},
        goatDetails: {
          for (final g in _goats)
            if (g.daysOrRateChanged)
              g.line.goatId: (days: g.dayCount, monthlyRate: g.monthlyRate),
        },
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

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final edit = preview.edit;
    final month = periodLabel(_bill.billingPeriodKey);

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          elevation: 0,
          foregroundColor: AppColors.textDark,
          title: Text('Edit $month bill', style: AppTheme.heading(size: 17)),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _buildHeader(month),
              const SizedBox(height: 14),
              _sectionTitle(
                'Goat charges',
                'Days on the farm × monthly rate. Change the days or rate, '
                    'or set the amount by hand.',
              ),
              for (final g in _goats) _buildGoatCard(g),
              if (_goats.isEmpty)
                _card(
                  child: Text(
                    'This bill has no goat lines.',
                    style: AppTheme.body(size: 12),
                  ),
                ),
              const SizedBox(height: 6),
              _buildExtrasCard(),
              const SizedBox(height: 14),
              _sectionTitle(
                'Statement',
                'How the bill changes. Previous outstanding, advance and '
                    'money already paid stay as issued.',
              ),
              _buildStatementCard(month, edit, preview.problem),
              const SizedBox(height: 14),
              _sectionTitle('Reason and notes', null),
              _card(
                child: Column(
                  children: [
                    TextField(
                      controller: _reasonController,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration(
                        'Reason for correction (required)',
                        hint: 'e.g. Goat G-12 left on 20 Sep',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration:
                      _decoration('Bill notes (shown on the bill)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomBar(edit),
      ),
    );
  }

  // ---------------------------------------------------------------- header
  Widget _buildHeader(String month) {
    final status = _bill.effectiveOwnStatus;
    final statusText = status == 'paid'
        ? 'Paid'
        : (status == 'partial' ? 'Partly paid' : 'Unpaid');
    final statusColor = status == 'paid'
        ? AppColors.success
        : (status == 'partial' ? AppColors.warning : AppColors.error);
    final start = periodStart(_bill.billingPeriodKey);
    final end = periodEnd(_bill.billingPeriodKey);
    final dayFmt = DateFormat('d MMM yyyy');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$month bill', style: AppTheme.heading(size: 16)),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: AppTheme.body(
                    size: 11,
                    color: statusColor,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _infoLine(Icons.tag, _bill.billNumber),
          _infoLine(
            Icons.date_range_outlined,
            'Period ${dayFmt.format(start)} – ${dayFmt.format(end)}',
          ),
          _infoLine(
            Icons.event_note_outlined,
            'Issued ${dayFmt.format(_bill.generatedAt)}',
          ),
          _infoLine(
            Icons.pets_outlined,
            '${_goats.length} goat${_goats.length == 1 ? '' : 's'} on this bill',
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ goat card
  Widget _buildGoatCard(_GoatEdit g) {
    final line = g.line;
    final dayFmt = DateFormat('d MMM');
    final diff = roundMoney(g.value - line.palaiAmount);
    final range = line.fromDate != null && line.toDate != null
        ? '${dayFmt.format(line.fromDate!)} – ${dayFmt.format(line.toDate!)}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
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
                  child: const Icon(
                    Icons.pets,
                    size: 18,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.label, style: AppTheme.heading(size: 14)),
                      Text(
                        [
                          if (range != null) range,
                          if (line.billableDays != null &&
                              line.daysInMonth != null)
                            'billed ${line.billableDays} of ${line.daysInMonth} days',
                        ].join(' · '),
                        style: AppTheme.body(size: 11),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currency(g.value),
                      style: AppTheme.heading(
                        size: 15,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    if (diff.abs() > kMoneyEpsilon)
                      Text(
                        '${diff > 0 ? '+' : '−'}${_currency(diff.abs())}',
                        style: AppTheme.body(
                          size: 11,
                          color: diff > 0 ? AppColors.error : AppColors.success,
                          weight: FontWeight.w700,
                        ),
                      )
                    else
                      Text('no change', style: AppTheme.body(size: 10.5)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (g.canCalculate && !g.manual) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: g.days,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration(
                        'Days',
                        suffix: 'of ${line.daysInMonth}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: g.rate,
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('Rate per month', prefix: '₹ '),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '₹${g.monthlyRate.toStringAsFixed(2)} ÷ ${line.daysInMonth} '
                    'days × ${g.dayCount} days = ${_currency(g.value)}',
                style: AppTheme.body(size: 11),
              ),
            ] else
              TextField(
                controller: g.amount,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Amount for this goat', prefix: '₹ '),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                if (g.canCalculate)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      if (!g.manual) {
                        g.amount.text = g.value.toStringAsFixed(2);
                      }
                      g.manual = !g.manual;
                    }),
                    icon: Icon(
                      g.manual ? Icons.calculate_outlined : Icons.edit_outlined,
                      size: 16,
                    ),
                    label: Text(
                      g.manual ? 'Work out from days' : 'Set amount by hand',
                    ),
                  ),
                if (g.value > kMoneyEpsilon)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      g.days.text = '0';
                      g.amount.text = '0';
                    }),
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    label: const Text('No charge'),
                  ),
                if (diff.abs() > kMoneyEpsilon || g.daysOrRateChanged)
                  TextButton.icon(
                    onPressed: () => setState(g.reset),
                    icon: const Icon(Icons.undo, size: 16),
                    label: Text('Undo (${_currency(line.palaiAmount)})'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- other/discount
  Widget _buildExtrasCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Other charges and discount',
            style: AppTheme.heading(size: 13.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _otherController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: _decoration('Other charges', prefix: '₹ '),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _discountController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: _decoration('Discount', prefix: '₹ '),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Issued with: other ${_currency(_bill.otherCharges)} · '
                'discount ${_currency(_bill.discount)}',
            style: AppTheme.body(size: 11),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ statement
  Widget _buildStatementCard(
      String month,
      StatementEdit? edit,
      String? problem,
      ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SizedBox()),
              SizedBox(
                width: 84,
                child: Text(
                  'Issued',
                  textAlign: TextAlign.right,
                  style: AppTheme.body(size: 10.5),
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  'After edit',
                  textAlign: TextAlign.right,
                  style: AppTheme.body(size: 10.5, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const Divider(height: 12),
          _compareRow(
            'Palai (${_goats.length} goat${_goats.length == 1 ? '' : 's'})',
            _palaiOld,
            _palaiNew,
          ),
          _compareRow(
            'Other charges',
            _bill.otherCharges,
            _value(_otherController),
          ),
          _compareRow(
            'Discount',
            -_bill.discount,
            -_value(_discountController),
          ),
          _compareRow(
            '$month charges',
            _bill.effectiveOwnCharges,
            _newCharges,
            bold: true,
          ),
          const SizedBox(height: 6),
          _compareRow(
            'Previous outstanding',
            _bill.previousOutstanding,
            _bill.previousOutstanding,
          ),
          for (final line in _bill.previousBreakdown)
            _compareRow(
              '   ${line.displayLabel}',
              line.amount,
              line.amount,
              muted: true,
            ),
          if (_bill.earlierBalance > kMoneyEpsilon)
            _compareRow(
              '   Earlier balance',
              _bill.earlierBalance,
              _bill.earlierBalance,
              muted: true,
            ),
          if (_bill.advanceApplied > kMoneyEpsilon)
            _compareRow(
              'Less: advance applied',
              -_bill.advanceApplied,
              -_bill.advanceApplied,
            ),
          if (_bill.paidFromDeletedBill > kMoneyEpsilon)
            _compareRow(
              'Less: already paid for $month',
              -_bill.paidFromDeletedBill,
              -_bill.paidFromDeletedBill,
            ),
          const Divider(height: 16),
          _compareRow(
            'Total payable',
            _bill.totalPayable,
            edit?.totalPayable,
            bold: true,
          ),
          if (_bill.amountPaid > kMoneyEpsilon)
            _compareRow(
              'Paid on this bill',
              _bill.amountPaid,
              _bill.amountPaid,
            ),
          _compareRow(
            'Remaining',
            _bill.remainingAmount,
            edit?.remaining,
            bold: true,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (edit == null ? AppColors.error : AppColors.info)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              edit == null
                  ? problem ?? ''
                  : edit.pendingDelta.abs() < kMoneyEpsilon
                  ? 'No change to what the customer owes.'
                  : 'Customer\'s total pending will '
                  '${edit.pendingDelta > 0 ? 'go up' : 'go down'} by '
                  '${_currency(edit.pendingDelta.abs())}.',
              style: AppTheme.body(
                size: 12,
                color: edit == null ? AppColors.error : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compareRow(
      String label,
      double before,
      double? after, {
        bool bold = false,
        bool muted = false,
      }) {
    final changed = after != null && (after - before).abs() > kMoneyEpsilon;
    final style = bold
        ? AppTheme.heading(size: 13)
        : AppTheme.body(
      size: muted ? 11 : 12,
      color: muted ? AppColors.textGrey : AppColors.textDark,
    );

    String money(double v) => v < 0 ? '− ${_currency(v.abs())}' : _currency(v);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          SizedBox(
            width: 84,
            child: Text(
              money(before),
              textAlign: TextAlign.right,
              style: style.copyWith(
                color: changed ? AppColors.textGrey : null,
                decoration: changed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              after == null ? '—' : money(after),
              textAlign: TextAlign.right,
              style: style.copyWith(
                color: changed ? AppColors.darkGreen : null,
                fontWeight: changed || bold ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- bottom bar
  Widget _buildBottomBar(StatementEdit? edit) {
    final diff =
    edit == null ? 0.0 : roundMoney(edit.totalPayable - _bill.totalPayable);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0x14000000))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New total payable', style: AppTheme.body(size: 11)),
                  Text(
                    edit == null ? '—' : _currency(edit.totalPayable),
                    style: AppTheme.heading(
                      size: 17,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  if (edit != null && diff.abs() > kMoneyEpsilon)
                    Text(
                      '${diff > 0 ? '+' : '−'}${_currency(diff.abs())} vs issued',
                      style: AppTheme.body(
                        size: 11,
                        color: diff > 0 ? AppColors.error : AppColors.success,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving || edit == null ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
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
                    : const Text(
                  'Save changes',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SMALL HELPERS
  // ===========================================================================

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: AppTheme.card(radius: 14),
    child: child,
  );

  Widget _sectionTitle(String title, String? subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.heading(size: 14.5)),
        if (subtitle != null) Text(subtitle, style: AppTheme.body(size: 11)),
      ],
    ),
  );

  Widget _infoLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textGrey),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: AppTheme.body(size: 12))),
      ],
    ),
  );

  InputDecoration _decoration(
      String label, {
        String? hint,
        String? prefix,
        String? suffix,
      }) =>
      InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        suffixText: suffix,
        // The app theme draws text fields with no border (white on white
        // cards), so every editable box here sets its own border:
        // grey normally, green while typing, red on an error.
        border: _border(const Color(0xFFBDBDBD)),
        enabledBorder: _border(const Color(0xFFBDBDBD)),
        focusedBorder: _border(AppColors.primaryGreen, width: 1.8),
        disabledBorder: _border(const Color(0xFFE0E0E0)),
        errorBorder: _border(AppColors.error),
        focusedErrorBorder: _border(AppColors.error, width: 1.8),
      );

  OutlineInputBorder _border(Color color, {double width = 1.2}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

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