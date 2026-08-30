import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/monthly_bill_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_billing_service.dart';

/// Goat-wise Monthly Bill generation.
///
/// This screen replaced a single generic "Monthly Palai Charges" input
/// that made bills misleading — one blended number for every goat, with
/// no way to tell what was old vs. new, or which goat contributed what.
///
/// The new flow keeps everything separate, all the way through:
///
///   Goat-wise Current Month Palai (editable per goat)
///         +
///   Current Outstanding   (customer's real current balance — 0 if none)
///         −
///   Current Advance       (customer's real current advance — 0 if none)
///         =
///   Current Amount Due
///
///   Old Payments           -> shown for reference ONLY, never subtracted
///   Current Month Payment  -> optional, recorded separately as an actual
///                              payment against the bill just created
///
/// Old payment ≠ current payment. Old payments never silently affect the
/// current-month calculation.
class MonthlyBillGenerateScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String customerName;
  final int goatCount;
  final double suggestedMonthlyAmount;

  /// When set, this screen edits that EXISTING bill in place (via
  /// [MonthlyBillingService.updateCurrentMonthMonthlyBill]) instead of
  /// creating a new one — used to fix a bill that was generated with a
  /// mistake in it (most commonly ₹0 Current Month Palai). The month
  /// selector is locked to that bill's own billing month.
  final String? editBillId;

  /// True when this screen was opened as a redirect FROM the Customer
  /// Goat Progress Report screen (e.g. to fill in or fix this month's
  /// bill before/after generating a report), rather than opened
  /// directly from the Monthly Bills list. Purely cosmetic: it swaps
  /// the primary button's label to "Done" so the flow reads naturally
  /// when the owner is being sent back to finish something, without
  /// changing what the button actually does.
  final bool cameFromProgressReport;

  const MonthlyBillGenerateScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.customerName,
    this.goatCount = 0,
    this.suggestedMonthlyAmount = 0,
    this.editBillId,
    this.cameFromProgressReport = false,
  });

  @override
  State<MonthlyBillGenerateScreen> createState() =>
      _MonthlyBillGenerateScreenState();
}

class _MonthlyBillGenerateScreenState
    extends State<MonthlyBillGenerateScreen> {
  final MonthlyBillingService _billingService = MonthlyBillingService.instance;

  Stream<List<PalaiGoat>>? _goatsStream;
  List<PalaiGoat> _lastLoadedGoats = [];

  /// One editable "Current Month Palai" controller per goat, seeded from
  /// that goat's registered [PalaiGoat.pricing] as a starting point only.
  final Map<String, TextEditingController> _palaiControllers = {};

  final TextEditingController _outstandingController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController();
  final TextEditingController _currentPaymentController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _paymentMethod = 'Cash';

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool _loadingCustomer = true;
  String? _loadError;

  /// Sum of every past bill's amountPaid — reference/history only. This
  /// is NEVER subtracted from the current-month calculation; it exists
  /// purely so the owner can see what has already come in historically.
  double _oldPaymentsTotal = 0;

  bool _saving = false;

  bool get _isEditing => widget.editBillId != null;

  /// The bill being corrected, when [_isEditing]. Loaded once up front
  /// so the month selector can be locked to it and every field can be
  /// prefilled from its own saved snapshot rather than the customer's
  /// live state.
  MonthlyBill? _editingBill;

  @override
  void initState() {
    super.initState();
    _goatsStream = FirestoreService.instance.goatsForCustomerStream(
      widget.farmId,
      widget.customerId,
    );
    if (_isEditing) {
      _loadBillToEdit(widget.editBillId!);
    } else {
      _loadCurrentState();
    }
  }

  @override
  void dispose() {
    for (final controller in _palaiControllers.values) {
      controller.dispose();
    }
    _outstandingController.dispose();
    _advanceController.dispose();
    _currentPaymentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ================================================================
  // LOAD CURRENT STATE (never reconstructed from history)
  // ================================================================

  Future<void> _loadCurrentState() async {
    setState(() {
      _loadingCustomer = true;
      _loadError = null;
    });

    try {
      final customer = await FirestoreService.instance.getCustomer(
        widget.farmId,
        widget.customerId,
      );

      // Old Payments — reference-only history, kept completely separate
      // from the current calculation.
      final pastBills = await _billingService.getMonthlyBills(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
      final oldPaymentsTotal = pastBills.fold<double>(
        0,
            (sum, b) => sum + b.amountPaid,
      );

      if (!mounted) return;
      setState(() {
        _outstandingController.text =
            (customer?.pendingAmount ?? 0).toStringAsFixed(2);
        _advanceController.text =
            (customer?.advanceAmount ?? 0).toStringAsFixed(2);
        _oldPaymentsTotal = oldPaymentsTotal;
        _loadingCustomer = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCustomer = false;
        _loadError = 'Could not load current customer state: $e';
      });
    }
  }

  /// Loads the bill being fixed and prefills every field from ITS OWN
  /// saved snapshot — never from the customer's current live state,
  /// since that state has already moved on (it includes this bill's
  /// effect). The month selector is locked to this bill's own month;
  /// per-goat Palai controllers are seeded from its goatBreakdown so a
  /// bill that shows ₹0 Palai across the board actually starts blank
  /// rather than silently pulling in each goat's current registered
  /// price as if that were what was billed.
  Future<void> _loadBillToEdit(String billId) async {
    setState(() {
      _loadingCustomer = true;
      _loadError = null;
    });

    try {
      final bill = await _billingService.getMonthlyBill(
        farmId: widget.farmId,
        billId: billId,
      );

      if (bill == null) {
        if (!mounted) return;
        setState(() {
          _loadingCustomer = false;
          _loadError = 'This monthly bill could not be found.';
        });
        return;
      }

      final pastBills = await _billingService.getMonthlyBills(
        farmId: widget.farmId,
        customerId: widget.customerId,
      );
      final oldPaymentsTotal = pastBills
          .where((b) => b.id != billId)
          .fold<double>(0, (sum, b) => sum + b.amountPaid);

      if (!mounted) return;
      setState(() {
        _editingBill = bill;
        _selectedMonth = DateTime(bill.year, bill.month);
        _outstandingController.text = bill.previousOutstanding.toStringAsFixed(2);
        _advanceController.text = bill.advanceApplied.toStringAsFixed(2);
        _notesController.text = bill.notes;
        _oldPaymentsTotal = oldPaymentsTotal;
        _loadingCustomer = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCustomer = false;
        _loadError = 'Could not load this bill: $e';
      });
    }
  }

  // ================================================================
  // PER-GOAT PALAI
  // ================================================================

  TextEditingController _palaiControllerFor(PalaiGoat goat) {
    return _palaiControllers.putIfAbsent(goat.id, () {
      if (_isEditing) {
        // Editing an existing bill: seed from what was actually billed
        // for this goat, not its current registered price — a goat
        // with no line in the saved breakdown starts at ₹0 rather than
        // silently pulling in today's price for a past month.
        final breakdown = _editingBill?.goatBreakdown ?? const [];
        GoatBillingLine? savedLine;
        for (final line in breakdown) {
          if (line.goatId == goat.id) {
            savedLine = line;
            break;
          }
        }
        return TextEditingController(
          text: (savedLine?.palaiAmount ?? 0).toStringAsFixed(2),
        );
      }
      return TextEditingController(text: goat.pricing.toStringAsFixed(2));
    });
  }

  double _enteredPalai(PalaiGoat goat) {
    final controller = _palaiControllers[goat.id];
    if (controller == null) return goat.pricing;
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _palaiChargesTotal =>
      _lastLoadedGoats.fold<double>(0, (sum, g) => sum + _enteredPalai(g));

  List<GoatBillingLine> get _goatBreakdown => _lastLoadedGoats.map((g) {
    final label = g.name.trim().isNotEmpty
        ? g.name
        : (g.goatCode.trim().isNotEmpty ? g.goatCode : g.tagNumber);
    return GoatBillingLine(
      goatId: g.id,
      label: label,
      palaiAmount: _enteredPalai(g),
    );
  }).toList();

  // ================================================================
  // CURRENT-STATE FIELDS (never reconstructed from history)
  // ================================================================

  double get _currentOutstanding =>
      double.tryParse(_outstandingController.text.trim()) ?? 0;

  double get _currentAdvance =>
      double.tryParse(_advanceController.text.trim()) ?? 0;

  double get _currentMonthPayment =>
      double.tryParse(_currentPaymentController.text.trim()) ?? 0;

  /// Current Month Palai + Current Outstanding − Current Advance.
  double get _currentAmountDue =>
      (_palaiChargesTotal + _currentOutstanding - _currentAdvance)
          .clamp(0, double.infinity)
          .toDouble();

  /// Current Amount Due − Current Month Payment (the payment being
  /// recorded right now — never an old payment).
  double get _remainingBalance =>
      (_currentAmountDue - _currentMonthPayment)
          .clamp(0, double.infinity)
          .toDouble();

  String _currency(double value) {
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
        .format(value);
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Fix Monthly Bill' : 'Generate Monthly Bill'),
      ),
      body: StreamBuilder<List<PalaiGoat>>(
        stream: _goatsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _loadingCustomer) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_loadError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadCurrentState,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final goats = (snapshot.data ?? []).where((g) => !g.isCheckedOut).toList();
          _lastLoadedGoats = goats;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCustomerCard(goats.length),
              const SizedBox(height: 18),
              _buildMonthSelector(),
              const SizedBox(height: 18),
              _buildWarningBanner(),
              const SizedBox(height: 18),
              _buildGoatWisePalaiSection(goats),
              const SizedBox(height: 20),
              _buildCurrentStateSection(),
              const SizedBox(height: 20),
              _buildPaymentDetailsSection(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _buildSummaryCard(),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_saving || goats.isEmpty) ? null : _generateBill,
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(widget.cameFromProgressReport
                      ? Icons.check_circle_outline
                      : Icons.receipt_long),
                  label: Text(_saving
                      ? (_isEditing ? 'Saving...' : 'Generating...')
                      : (widget.cameFromProgressReport
                      ? 'Done'
                      : 'Generate Monthly Bill')),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCustomerCard(int goatCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(radius: 25, child: Icon(Icons.person_outline)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Customer', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 3),
                  Text(
                    widget.customerName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text('$goatCount goat(s)', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    final text = DateFormat('MMMM yyyy').format(_selectedMonth);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _isEditing ? null : _selectMonth,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Billing Month',
          prefixIcon: const Icon(Icons.calendar_month),
          border: const OutlineInputBorder(),
          suffixIcon: _isEditing
              ? const Tooltip(
            message: "A bill's month can't be changed once generated.",
            child: Icon(Icons.lock_outline, size: 18),
          )
              : null,
        ),
        child: Text(text, style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Current Month Calculation Only — previous monthly payments and historical transactions are not included in this calculation.',
              style: AppTheme.body(size: 11.5, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // GOAT-WISE PALAI
  // ----------------------------------------------------------------

  Widget _buildGoatWisePalaiSection(List<PalaiGoat> goats) {
    if (goats.isEmpty) {
      return Text(
        'This customer has no active goats under Palai.',
        style: AppTheme.body(size: 12, color: AppColors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Goat Billing', style: AppTheme.heading(size: 14)),
        const SizedBox(height: 8),
        for (final goat in goats) ...[
          _goatBillingCard(goat),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _goatBillingCard(PalaiGoat goat) {
    final goatId = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);
    final label = goat.name.trim().isNotEmpty ? goat.name : goatId;
    final controller = _palaiControllerFor(goat);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label, style: AppTheme.heading(size: 13)),
                TextSpan(
                  text: '  •  Palai Price: ${_currency(goat.pricing)}',
                  style: AppTheme.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Current Month Palai',
              prefixText: '₹ ',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // CURRENT OUTSTANDING / ADVANCE
  // ----------------------------------------------------------------

  Widget _buildCurrentStateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Current Financial State', style: AppTheme.heading(size: 14)),
        const SizedBox(height: 4),
        Text(
          'Only the customer\'s current outstanding and current advance are used. If there is none, leave it as ₹0 — old bills and old payments are never re-summed here.',
          style: AppTheme.body(size: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        _moneyField(
          controller: _outstandingController,
          label: 'Current Outstanding',
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 10),
        _moneyField(
          controller: _advanceController,
          label: 'Current Advance',
          icon: Icons.savings_outlined,
        ),
      ],
    );
  }

  // ----------------------------------------------------------------
  // PAYMENT DETAILS — Old (reference) vs Current Month (editable)
  // ----------------------------------------------------------------

  Widget _buildPaymentDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Details', style: AppTheme.heading(size: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Previous / Old Payments (all-time)', style: AppTheme.body(size: 12)),
                  ),
                  Text(_currency(_oldPaymentsTotal), style: AppTheme.heading(size: 13)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Reference only — NOT subtracted from the current calculation.',
                style: AppTheme.body(size: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _moneyField(
          controller: _currentPaymentController,
          label: 'Current Month Payment (optional)',
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: 10),
        _paymentMethodDropdown(),
      ],
    );
  }

  Widget _paymentMethodDropdown() {
    return Container(
      decoration: AppTheme.card(radius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _paymentMethod,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
            DropdownMenuItem(value: 'UPI', child: Text('UPI')),
            DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
            DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: _saving
              ? null
              : (value) {
            if (value == null) return;
            setState(() => _paymentMethod = value);
          },
        ),
      ),
    );
  }

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        final number = double.tryParse(value?.trim() ?? '');
        if (number == null) return 'Enter a valid amount';
        if (number < 0) return 'Amount cannot be negative';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        prefixText: '₹ ',
        border: const OutlineInputBorder(),
      ),
    );
  }

  // ----------------------------------------------------------------
  // SUMMARY
  // ----------------------------------------------------------------

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.calculate_outlined),
              SizedBox(width: 8),
              Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 14),
          _previewRow('Current Month Palai', _currency(_palaiChargesTotal)),
          _previewRow('Current Outstanding', _currency(_currentOutstanding)),
          _previewRow('Current Advance', '- ${_currency(_currentAdvance)}'),
          const Divider(),
          _previewRow('Current Amount Due', _currency(_currentAmountDue), bold: true),
          if (_currentMonthPayment > 0) ...[
            _previewRow('Current Month Payment', '- ${_currency(_currentMonthPayment)}'),
            const Divider(),
            _previewRow('Remaining Balance', _currency(_remainingBalance), bold: true),
          ],
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // ACTIONS
  // ================================================================

  Future<void> _selectMonth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Select any date in the billing month',
    );
    if (selected == null) return;
    setState(() {
      _selectedMonth = DateTime(selected.year, selected.month);
    });
  }

  Future<void> _generateBill() async {
    FocusScope.of(context).unfocus();

    if (_lastLoadedGoats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This customer has no active goats to bill.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final MonthlyBill bill;

      if (_isEditing) {
        // ---------------------------------------------------------
        // EDIT — correct the same bill document in place. No
        // duplicate-bill check needed since we're not creating one.
        // ---------------------------------------------------------
        bill = await _billingService.updateCurrentMonthMonthlyBill(
          farmId: widget.farmId,
          customerId: widget.customerId,
          billId: widget.editBillId!,
          palaiCharges: _palaiChargesTotal,
          currentOutstanding: _currentOutstanding,
          currentAdvance: _currentAdvance,
          goatBreakdown: _goatBreakdown,
          goatCount: _lastLoadedGoats.length,
          notes: _notesController.text.trim(),
        );
      } else {
        final exists = await _billingService.monthlyBillExists(
          farmId: widget.farmId,
          customerId: widget.customerId,
          year: _selectedMonth.year,
          month: _selectedMonth.month,
        );

        if (exists) {
          throw StateError(
            'A monthly bill already exists for '
                '${DateFormat('MMMM yyyy').format(_selectedMonth)}.',
          );
        }

        bill = await _billingService.createCurrentMonthMonthlyBill(
          farmId: widget.farmId,
          customerId: widget.customerId,
          year: _selectedMonth.year,
          month: _selectedMonth.month,
          palaiCharges: _palaiChargesTotal,
          currentOutstanding: _currentOutstanding,
          currentAdvance: _currentAdvance,
          goatBreakdown: _goatBreakdown,
          goatCount: _lastLoadedGoats.length,
          notes: _notesController.text.trim(),
        );
      }

      // Current Month Payment, if any, is recorded as an ACTUAL payment
      // against the bill just created/updated — completely separate
      // from Old Payments, and never folded into the calculation above.
      if (_currentMonthPayment > 0) {
        await _billingService.receiveMonthlyBillPayment(
          farmId: widget.farmId,
          customerId: widget.customerId,
          billId: bill.id,
          paidAmount: _currentMonthPayment,
          paymentMethod: _paymentMethod,
          note: _isEditing
              ? 'Current month payment recorded while fixing this bill.'
              : 'Current month payment recorded at bill generation.',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Monthly bill ${bill.billNumber} updated.'
              : 'Monthly bill ${bill.billNumber} generated.'),
        ),
      );

      Navigator.of(context).pop(bill);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to ${_isEditing ? 'update' : 'generate'} bill: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}