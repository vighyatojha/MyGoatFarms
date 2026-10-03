import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../services/payment_allocation_service.dart';
import '../../utils/billing_ledger.dart';

/// Generates the monthly STATEMENT for one customer.
///
/// Same engine as the Generate Bills button on the Customers screen, for
/// one customer only. The screen first shows a preview worked out with
/// the exact calculation the bill will use:
///
///   September charges (goat by goat, by days on the farm)
///   + Previous Outstanding (carried forward, never re-charged)
///   − Advance applied
///   = Total Payable
///
/// Nothing is typed in by hand: charges come from each goat's Palai
/// price and the days it was on the farm, and the previous outstanding
/// and advance come from the customer's live balance.
///
/// Pops `true` when at least one bill was generated.
class MonthlyBillGenerateScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;

  const MonthlyBillGenerateScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<MonthlyBillGenerateScreen> createState() =>
      _MonthlyBillGenerateScreenState();
}

class _MonthlyBillGenerateScreenState
    extends State<MonthlyBillGenerateScreen> {
  final MonthlyStatementEngine _engine = MonthlyStatementEngine.instance;

  final TextEditingController _paymentController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _paymentMethod = 'Cash';

  StatementPreview? _preview;
  String? _loadError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _paymentController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final preview = await _engine.previewNext(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = FirestoreService.instance.describeError(e);
      });
    }
  }

  double get _payment =>
      double.tryParse(_paymentController.text.trim()) ?? 0;

  // ===========================================================================
  // GENERATE
  // ===========================================================================

  Future<void> _generate() async {
    final preview = _preview;
    if (preview == null || !preview.canGenerate || _saving) return;

    FocusScope.of(context).unfocus();
    if (_payment < 0) {
      _snack('Payment cannot be negative.', error: true);
      return;
    }

    setState(() => _saving = true);

    List<StatementOutcome> outcomes;
    try {
      outcomes = await _engine.generateForCustomer(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(
        'Could not generate the bill: '
            '${FirestoreService.instance.describeError(e)}',
        error: true,
      );
      return;
    }

    final generated = outcomes
        .where((o) => o.kind == StatementOutcomeKind.generated)
        .toList();
    final failed = outcomes
        .where((o) => o.kind == StatementOutcomeKind.failed)
        .toList();

    // The payment is recorded only after the bill exists, through the
    // normal oldest-first payment rule. If it fails, the bill stays and
    // the owner is told plainly that the payment still needs recording.
    String? paymentProblem;
    if (generated.isNotEmpty && _payment > 0) {
      try {
        await PaymentAllocationService.instance.receivePayment(
          farmId: widget.farmId,
          customerId: widget.customerId,
          paidAmount: _payment,
          paymentMethod: _paymentMethod,
          note: _noteController.text.trim().isEmpty
              ? 'Payment received when the bill was generated.'
              : _noteController.text.trim(),
          fromBillId: generated.last.billId,
          paymentType: 'monthlyBillPayment',
          incomeCategory: 'Palai Monthly Bill Payment',
        );
      } catch (e) {
        paymentProblem = FirestoreService.instance.describeError(e);
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          generated.isNotEmpty ? 'Bill generated' : 'No bill generated',
          style: AppTheme.heading(size: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final outcome in outcomes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _outcomeLine(outcome),
                  style: AppTheme.body(
                    size: 13,
                    color: outcome.kind == StatementOutcomeKind.failed
                        ? AppColors.error
                        : AppColors.textDark,
                  ),
                ),
              ),
            if (paymentProblem != null) ...[
              const SizedBox(height: 6),
              Text(
                'The bill was generated, but the payment of '
                    '${_currency(_payment)} was not recorded: $paymentProblem. '
                    'Record it from Receive Payment.',
                style: AppTheme.body(size: 12.5, color: AppColors.error),
              ),
            ] else if (generated.isNotEmpty && _payment > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Payment of ${_currency(_payment)} recorded.',
                style: AppTheme.body(size: 12.5, color: AppColors.success),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (generated.isNotEmpty) {
      Navigator.of(context).pop(true);
    } else if (failed.isEmpty) {
      await _load();
    }
  }

  String _outcomeLine(StatementOutcome outcome) {
    final month = periodLabel(outcome.periodKey);
    switch (outcome.kind) {
      case StatementOutcomeKind.generated:
        return '$month: ${outcome.billNumber ?? ''} · '
            'Total payable ${_currency(outcome.totalPayable)}';
      case StatementOutcomeKind.alreadyBilled:
        return '$month: already billed.';
      case StatementOutcomeKind.nothingToBill:
        return '$month: no Palai charges.';
      case StatementOutcomeKind.failed:
        return '$month: ${outcome.message}';
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Generate bill', style: AppTheme.heading(size: 18)),
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      )
          : _loadError != null
          ? _buildError()
          : _buildBody(_preview!),
      bottomNavigationBar:
      _preview?.canGenerate == true && !_loading ? _buildBottomBar() : null,
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              'Could not work out the bill',
              style: AppTheme.heading(size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(StatementPreview preview) {
    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            widget.customerName,
            style: AppTheme.heading(size: 17),
          ),
          const SizedBox(height: 12),
          switch (preview.status) {
            StatementPreviewStatus.alreadyBilled =>
                _buildInfo(
                  icon: Icons.check_circle_outline,
                  color: AppColors.success,
                  title: preview.lastBilledKey == null
                      ? 'Already billed'
                      : 'Billed up to ${periodLabel(preview.lastBilledKey!)}',
                  message: _nextBillMessage(preview.lastBilledKey),
                ),
            StatementPreviewStatus.nothingToBill =>
                _buildInfo(
                  icon: Icons.info_outline,
                  color: AppColors.info,
                  title: 'No Palai charges for ${periodLabel(preview.periodKey)}',
                  message: 'No goat of this customer was on the farm that month, '
                      'or those days were already charged at checkout. Any '
                      'outstanding balance carries to the next bill.',
                ),
            StatementPreviewStatus.ready => _buildStatement(preview),
          },
        ],
      ),
    );
  }

  String _nextBillMessage(String? lastBilledKey) {
    if (lastBilledKey == null) {
      return 'There is nothing to generate right now.';
    }
    final next = nextPeriodKey(lastBilledKey);
    final availableFrom = periodStart(nextPeriodKey(next));
    return 'The ${periodLabel(next)} bill can be generated from '
        '${DateFormat('d MMMM yyyy').format(availableFrom)}.';
  }

  Widget _buildInfo({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.heading(size: 15)),
                const SizedBox(height: 4),
                Text(message, style: AppTheme.body(size: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatement(StatementPreview p) {
    final month = periodLabel(p.periodKey);
    final dateFormat = DateFormat('d MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.card(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$month statement', style: AppTheme.heading(size: 16)),
              const SizedBox(height: 2),
              Text(
                'Preview. Nothing is saved until you generate.',
                style: AppTheme.body(size: 11.5),
              ),
              const SizedBox(height: 14),

              // Goat lines.
              for (final line in p.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.label,
                              style: AppTheme.body(
                                size: 13,
                                color: AppColors.textDark,
                                weight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              line.days < line.daysInMonth
                                  ? '${line.days} of ${line.daysInMonth} days '
                                  '(${dateFormat.format(line.fromDate)} to '
                                  '${dateFormat.format(line.toDate)}) at '
                                  '${_currency(line.monthlyRate)}/month'
                                  : 'Full month at ${_currency(line.monthlyRate)}',
                              style: AppTheme.body(size: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currency(line.amount),
                        style: AppTheme.body(
                          size: 13,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 18),
              _row(
                '$month Palai charges (${p.lines.length} '
                    'goat${p.lines.length == 1 ? '' : 's'})',
                _currency(p.currentCharges),
              ),
              const SizedBox(height: 8),
              _row('Previous outstanding', _currency(p.previousOutstanding)),
              for (final line in p.previousBreakdown)
                _subRow(periodLabel(line.periodKey), _currency(line.amount)),
              if (p.earlierBalance > kMoneyEpsilon)
                _subRow('Earlier balance', _currency(p.earlierBalance)),
              if (p.advanceApplied > kMoneyEpsilon) ...[
                const SizedBox(height: 8),
                _row(
                  'Less: advance applied',
                  '− ${_currency(p.advanceApplied)}',
                  color: AppColors.success,
                ),
              ],
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text('Total payable', style: AppTheme.heading(size: 16)),
                  ),
                  Text(
                    _currency(p.totalPayable),
                    style: AppTheme.heading(
                      size: 20,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ],
              ),
              if (p.advanceAfter > kMoneyEpsilon) ...[
                const SizedBox(height: 4),
                Text(
                  'Advance left after this bill: ${_currency(p.advanceAfter)}',
                  style: AppTheme.body(size: 11.5),
                ),
              ],
            ],
          ),
        ),
        if (p.laterPeriods.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.history, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Missed month${p.laterPeriods.length == 1 ? '' : 's'} '
                        '${p.laterPeriods.map(periodLabel).join(', ')} will '
                        'also be billed, in order, right after $month.',
                    style: AppTheme.body(size: 12, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildPaymentCard(),
      ],
    );
  }

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment received now', style: AppTheme.heading(size: 14)),
          const SizedBox(height: 2),
          Text(
            'Optional. Applied to the oldest unpaid month first. '
                'Anything above the total payable becomes advance.',
            style: AppTheme.body(size: 11.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paymentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Amount',
              prefixText: '₹ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_payment > 0) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Payment method',
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                DropdownMenuItem(
                    value: 'Bank Transfer', child: Text('Bank Transfer')),
              ],
              onChanged: (v) => setState(() => _paymentMethod = v ?? 'Cash'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Note (optional)',
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final p = _preview!;
    final label = p.laterPeriods.isEmpty
        ? 'Generate ${periodLabel(p.periodKey)} bill'
        : 'Generate ${1 + p.laterPeriods.length} bills';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _generate,
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
                : Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Widget _row(String label, String value, {Color? color}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.body(size: 13, color: AppColors.textDark),
          ),
        ),
        Text(
          value,
          style: AppTheme.body(
            size: 13,
            color: color ?? AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _subRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.body(size: 12))),
          Text(value, style: AppTheme.body(size: 12)),
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