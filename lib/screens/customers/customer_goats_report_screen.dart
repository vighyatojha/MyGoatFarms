import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/monthly_bill_model.dart' show MonthlyBill, GoatBillingLine;
import '../../models/palai_models.dart';
import '../../services/customer_goats_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_billing_service.dart';
import '../../widgets/fast_route.dart';
import 'monthly_bill_generate_screen.dart';

/// Lets the owner generate ONE consolidated report covering all (or a
/// chosen subset of) the goats under a single Palai customer — instead
/// of generating a report per goat one at a time.
///
/// Alongside the flat goat table, this screen carries the SAME
/// current-month billing machinery as CustomerGoatsProgressReportScreen
/// (goat-wise editable Palai amounts, Current Outstanding / Current
/// Advance read fresh from the customer's live balance, and a
/// redirect into Monthly Billing to fix a bill that already exists),
/// so whichever screen the owner happens to generate a report from,
/// the numbers can never disagree with each other — both ultimately
/// call [MonthlyBillingService.createCurrentMonthMonthlyBill] /
/// [MonthlyBillingService.updateCurrentMonthMonthlyBill].
///
///   Current Month Palai (per goat, editable)
///         +
///   Current Outstanding (customer's current balance — zero if none)
///         −
///   Current Advance (customer's current advance — zero if none)
///         =
///   Current Amount Due
///
/// Old bills, old payments, past months — none of it is re-summed here.
class CustomerGoatsReportScreen extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;

  const CustomerGoatsReportScreen({
    super.key,
    required this.farmId,
    required this.customer,
  });

  @override
  State<CustomerGoatsReportScreen> createState() =>
      _CustomerGoatsReportScreenState();
}

class _CustomerGoatsReportScreenState
    extends State<CustomerGoatsReportScreen> {
  Stream<List<PalaiGoat>>? _goatsStream;

  final Set<String> _selectedIds = {};
  List<PalaiGoat> _lastLoadedGoats = [];

  bool _generating = false;

  // ------------------------------------------------------------------
  // CURRENT-MONTH BILLING (same rule as the Progress Report screen)
  //
  //   Current Month Palai (sum of each goat's editable amount)
  //         +
  //   Current Outstanding (customer's live balance, 0 if none)
  //         −
  //   Current Advance (customer's live advance, 0 if none)
  //         =
  //   Current Amount Due
  //
  // Historical payments and old bills are never summed/subtracted
  // again here — Current Outstanding and Current Advance are read
  // fresh from the customer's live profile and nothing else feeds
  // into them.
  // ------------------------------------------------------------------

  /// One editable "Monthly Palai Amount" controller per selected goat,
  /// seeded from that goat's registered [PalaiGoat.pricing] as a
  /// starting point only — fully editable, and never affects any other
  /// goat's amount.
  final Map<String, TextEditingController> _palaiControllers = {};

  final TextEditingController _outstandingController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController();

  /// The customer's CURRENT outstanding balance, re-fetched fresh (not
  /// from `widget.customer`, which may be stale).
  double _currentOutstanding = 0;

  /// The customer's CURRENT advance balance, re-fetched fresh at the
  /// same time as [_currentOutstanding].
  double _currentAdvanceAvailable = 0;

  /// If a monthly bill for the current month already exists for this
  /// customer, it's loaded here so a fresh one is never created on top
  /// of it — its own saved numbers are shown/used instead.
  MonthlyBill? _existingMonthlyBill;

  bool _loadingBilling = true;
  String? _billingLoadError;

  @override
  void initState() {
    super.initState();
    _goatsStream = FirestoreService.instance.goatsForCustomerStream(
      widget.farmId,
      widget.customer.id,
    );
    _loadBillingInfo();
  }

  @override
  void dispose() {
    for (final controller in _palaiControllers.values) {
      controller.dispose();
    }
    _outstandingController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  // ================================================================
  // SELECTION
  // ================================================================

  void _toggleSelectAll(List<PalaiGoat> goats) {
    setState(() {
      if (_selectedIds.length == goats.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(goats.map((g) => g.id));
      }
    });
  }

  void _toggleGoat(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  List<PalaiGoat> get _selectedGoats =>
      _lastLoadedGoats.where((g) => _selectedIds.contains(g.id)).toList();

  // ================================================================
  // BILLING — LOAD
  // ================================================================

  /// Loads the customer's current outstanding/advance, and checks
  /// whether a monthly bill already exists for the current month so a
  /// duplicate is never created.
  Future<void> _loadBillingInfo() async {
    setState(() {
      _loadingBilling = true;
      _billingLoadError = null;
    });

    try {
      final freshCustomer = await FirestoreService.instance.getCustomer(
        widget.farmId,
        widget.customer.id,
      );

      final now = DateTime.now();
      final billId = _monthlyBillId(widget.customer.id, now.year, now.month);

      final existingBill = await MonthlyBillingService.instance.getMonthlyBill(
        farmId: widget.farmId,
        billId: billId,
      );

      if (!mounted) return;

      setState(() {
        _currentOutstanding = freshCustomer?.pendingAmount ?? widget.customer.pendingAmount;
        _currentAdvanceAvailable = freshCustomer?.advanceAmount ?? widget.customer.advanceAmount;
        _existingMonthlyBill = existingBill;
        _loadingBilling = false;

        if (existingBill == null) {
          // Prefilled ONLY from the customer's live current balance —
          // zero if there is none. This month's goat-wise Palai amount
          // is a completely separate line item and must never be
          // folded into Current Outstanding here.
          _outstandingController.text = _currentOutstanding.toStringAsFixed(2);
          _advanceController.text = _currentAdvanceAvailable.toStringAsFixed(2);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBilling = false;
        _billingLoadError = 'Could not load billing info: $e';
      });
    }
  }

  /// Mirrors MonthlyBillingService's private document-ID format so we
  /// can look up "does this month already have a bill" without a new
  /// public method on the service.
  String _monthlyBillId(String customerId, int year, int month) {
    final periodKey = '$year-${month.toString().padLeft(2, '0')}';
    return 'monthly_${customerId}_$periodKey';
  }

  /// Sends the owner to the goat-wise Monthly Billing screen to finish
  /// or fix this month's bill, then refreshes billing info on return.
  ///
  /// - If a bill already exists for this month with ₹0 Current Month
  ///   Palai, opens it in EDIT mode (same bill document is corrected).
  /// - Otherwise opens in CREATE mode for this month.
  ///
  /// `cameFromProgressReport: true` is passed either way so that
  /// screen shows "Done" instead of "Generate Monthly Bill".
  Future<void> _openMonthlyBillingToFix() async {
    final existing = _existingMonthlyBill;
    final needsFix = existing != null && existing.palaiCharges <= 0;

    await Navigator.of(context).push(
      fastRoute(
        MonthlyBillGenerateScreen(
          farmId: widget.farmId,
          customerId: widget.customer.id,
          customerName: widget.customer.name,
          goatCount: _selectedGoats.length,
          editBillId: needsFix ? existing.id : null,
          cameFromProgressReport: true,
        ),
      ),
    );

    if (!mounted) return;
    await _loadBillingInfo();
  }

  // ================================================================
  // BILLING — PER-GOAT PALAI
  // ================================================================

  TextEditingController _palaiControllerFor(PalaiGoat goat) {
    return _palaiControllers.putIfAbsent(
      goat.id,
          () => TextEditingController(text: goat.pricing.toStringAsFixed(2)),
    );
  }

  double _enteredPalai(PalaiGoat goat) {
    final controller = _palaiControllers[goat.id];
    if (controller == null) return goat.pricing;
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  /// Sum of each *selected* goat's current-month Palai amount, exactly
  /// as typed in that goat's own field. Never combined with Current
  /// Outstanding/Advance before display.
  double get _palaiChargesTotal =>
      _selectedGoats.fold<double>(0, (sum, g) => sum + _enteredPalai(g));

  /// Goat-wise breakdown, saved with the bill as a permanent snapshot.
  List<GoatBillingLine> get _goatBreakdown => _selectedGoats.map((g) {
    final label = g.name.trim().isNotEmpty
        ? g.name
        : (g.goatCode.trim().isNotEmpty ? g.goatCode : g.tagNumber);
    return GoatBillingLine(
      goatId: g.id,
      label: label,
      palaiAmount: _enteredPalai(g),
    );
  }).toList();

  double get _enteredOutstanding =>
      double.tryParse(_outstandingController.text.trim()) ?? 0;

  double get _enteredAdvance =>
      double.tryParse(_advanceController.text.trim()) ?? 0;

  /// Current Month Palai + Current Outstanding − Current Advance,
  /// floored at zero.
  double get _currentAmountDue =>
      (_palaiChargesTotal + _enteredOutstanding - _enteredAdvance)
          .clamp(0, double.infinity)
          .toDouble();

  /// True once billing is ready to include in the report: either an
  /// existing bill for this month was found, or every selected goat
  /// has a valid Palai amount entered.
  bool get _billingReady {
    if (_loadingBilling) return false;
    if (_existingMonthlyBill != null) return true;
    if (_selectedGoats.isEmpty) return false;
    return _selectedGoats.every((g) {
      final controller = _palaiControllers[g.id];
      if (controller == null) return false;
      final value = double.tryParse(controller.text.trim());
      return value != null && value >= 0;
    });
  }

  // ================================================================
  // GENERATE
  // ================================================================

  Future<void> _generate({required bool share}) async {
    if (_selectedGoats.isEmpty) {
      _showSnack('Select at least one goat to include in the report.');
      return;
    }

    if (!_billingReady) {
      _showSnack('Enter the Monthly Palai Amount for every goat before generating the report.');
      return;
    }

    setState(() => _generating = true);

    try {
      final farm = await FirestoreService.instance.getFarmById(widget.farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();
      final now = DateTime.now();

      // ------------------------------------------------------------
      // BILLING — reuse this month's bill if one already exists,
      // otherwise create it now from three separate numbers. These
      // are never merged before being saved.
      // ------------------------------------------------------------
      MonthlyBill monthlyBill;
      if (_existingMonthlyBill != null) {
        monthlyBill = _existingMonthlyBill!;
      } else {
        try {
          monthlyBill = await MonthlyBillingService.instance.createCurrentMonthMonthlyBill(
            farmId: widget.farmId,
            customerId: widget.customer.id,
            year: now.year,
            month: now.month,
            palaiCharges: _palaiChargesTotal,
            currentOutstanding: _enteredOutstanding,
            currentAdvance: _enteredAdvance,
            goatBreakdown: _goatBreakdown,
            goatCount: _selectedGoats.length,
            notes: 'Auto-generated with Goats Report.',
          );
        } on StateError {
          // Someone else generated this month's bill in the meantime —
          // fall back to reading it instead of failing the report.
          final billId = _monthlyBillId(widget.customer.id, now.year, now.month);
          final existing = await MonthlyBillingService.instance.getMonthlyBill(
            farmId: widget.farmId,
            billId: billId,
          );
          if (existing == null) rethrow;
          monthlyBill = existing;
        }
      }

      if (share) {
        await CustomerGoatsReportPdfService.instance.share(
          customer: widget.customer,
          goats: _selectedGoats,
          billSettings: billSettings,
          bill: monthlyBill,
        );
      } else {
        await CustomerGoatsReportPdfService.instance.preview(
          customer: widget.customer,
          goats: _selectedGoats,
          billSettings: billSettings,
          bill: monthlyBill,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not generate report: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ================================================================
  // HELPERS
  // ================================================================

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  String _currency(double value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(
          'Goats Report',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: StreamBuilder<List<PalaiGoat>>(
        stream: _goatsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }

          final goats = (snapshot.data ?? []).where((g) => !g.isCheckedOut).toList();
          _lastLoadedGoats = goats;

          // Default to everything selected the first time goats load.
          if (_selectedIds.isEmpty && goats.isNotEmpty) {
            _selectedIds.addAll(goats.map((g) => g.id));
          }

          if (goats.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              _buildHeaderCard(goats),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    for (final goat in goats) _goatTile(goat),
                    _buildBillingCard(),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(List<PalaiGoat> goats) {
    final allSelected = _selectedIds.length == goats.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer.name,
                    style: AppTheme.heading(size: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_selectedIds.length} of ${goats.length} goats selected',
                    style: AppTheme.body(size: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _toggleSelectAll(goats),
              child: Text(allSelected ? 'Deselect All' : 'Select All'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goatTile(PalaiGoat goat) {
    final selected = _selectedIds.contains(goat.id);

    final goatId = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(radius: 14),
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) => _toggleGoat(goat.id),
        activeColor: AppColors.primaryGreen,
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            Flexible(
              child: Text(
                goat.name.trim().isNotEmpty ? goat.name : goatId,
                style: AppTheme.heading(size: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ID: $goatId',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${goat.breed.isNotEmpty ? goat.breed : 'Breed unknown'} • '
              '${goat.healthStatus.isNotEmpty ? goat.healthStatus : 'No health status'}',
          style: AppTheme.body(size: 11, color: AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_generating || !_billingReady) ? null : () => _generate(share: false),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.primaryGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_generating || !_billingReady) ? null : () => _generate(share: true),
                icon: _generating
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.share_outlined),
                label: Text(_generating ? 'Generating...' : 'Share Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pets_outlined,
                size: 35,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 14),
            Text('No goats found', style: AppTheme.heading(size: 15)),
            const SizedBox(height: 6),
            Text(
              'This customer has no goats under Palai yet.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // BILLING CARD — same shape as the Progress Report screen's
  // ------------------------------------------------------------------

  Widget _buildBillingCard() {
    final existing = _existingMonthlyBill;
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.primaryGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Monthly Billing — $monthLabel', style: AppTheme.heading(size: 14)),
              ),
              if (existing == null)
                IconButton(
                  tooltip: 'Re-fetch live Outstanding & Advance',
                  icon: _loadingBilling
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.refresh, size: 18, color: AppColors.textMuted),
                  onPressed: _loadingBilling ? null : _loadBillingInfo,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            existing != null
                ? 'A bill for $monthLabel was already generated for this customer. Its saved amounts are shown below exactly as recorded — generating this report again will NOT create a duplicate bill or change these numbers.'
                : 'Set each goat\'s Monthly Palai Amount below, then Current Outstanding and Current Advance. Nothing here is combined for you — you always see exactly what each figure is.',
            style: AppTheme.body(size: 11, color: AppColors.textMuted),
          ),
          if (existing == null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current Month Calculation Only — previous monthly payments and historical transactions are not included in this calculation.',
                      style: AppTheme.body(size: 10.5, color: AppColors.textDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          if (_loadingBilling)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
              ),
            )
          else if (_billingLoadError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_billingLoadError!, style: AppTheme.body(size: 11, color: AppColors.error)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadBillingInfo,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            )
          else ...[
              if (existing != null) ...[
                if (existing.goatBreakdown.isNotEmpty) ...[
                  for (final line in existing.goatBreakdown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _billingRow(line.label, _currency(line.palaiAmount)),
                    ),
                  const Divider(height: 14),
                ],
                _billingRow('Current Month Palai', _currency(existing.palaiCharges)),
                const SizedBox(height: 4),
                _billingRow('Current Outstanding', _currency(existing.previousOutstanding)),
                const SizedBox(height: 4),
                _billingRow('Current Advance', '- ${_currency(existing.advanceApplied)}'),
                const Divider(height: 20),
                _billingRow('Current Amount Due', _currency(existing.totalDue), bold: true),
                if (existing.palaiCharges <= 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This month\'s bill shows ₹0 Current Month Palai. Fix it in Monthly Billing before sharing this report.',
                                style: AppTheme.body(size: 10.5, color: AppColors.textDark),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openMonthlyBillingToFix,
                            icon: const Icon(Icons.build_outlined, size: 16),
                            label: const Text('Fix in Monthly Billing'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              side: const BorderSide(color: AppColors.warning),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                _buildGoatWisePalaiEntry(),
                const SizedBox(height: 14),
                _billingRow('Current Month Palai', _currency(_palaiChargesTotal), bold: true),
                const SizedBox(height: 14),
                _billingField(
                  controller: _outstandingController,
                  label: 'Current Outstanding',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                const SizedBox(height: 10),
                _billingField(
                  controller: _advanceController,
                  label: 'Current Advance',
                  icon: Icons.savings_outlined,
                ),
                const Divider(height: 24),
                _billingRow(
                  'Current Amount Due',
                  _currency(_currentAmountDue),
                  bold: true,
                ),
                const SizedBox(height: 4),
                Text(
                  'This will be saved to the customer\'s profile the moment you generate this report.',
                  style: AppTheme.body(size: 10, color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: _openMonthlyBillingToFix,
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Fill in Monthly Billing instead'),
                  ),
                ),
              ],
            ],
        ],
      ),
    );
  }

  /// Editable, per-goat "Monthly Palai Amount" entry. Each goat gets
  /// its own card clearly labelled with its ID and reference Palai
  /// Price (e.g. "GP-11 — Palai Price: ₹2,800"), plus its own editable
  /// amount textbox. Changing one goat's amount only ever affects that
  /// goat's row and the overall total.
  Widget _buildGoatWisePalaiEntry() {
    if (_selectedGoats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Monthly Palai Amount (per goat)', style: AppTheme.body(size: 11, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        for (final goat in _selectedGoats) ...[
          _goatPalaiCard(goat),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _goatPalaiCard(PalaiGoat goat) {
    final goatId = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);
    final label = goat.name.trim().isNotEmpty ? goat.name : goatId;
    final controller = _palaiControllerFor(goat);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
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
            style: AppTheme.heading(size: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Monthly Palai Amount',
              labelStyle: AppTheme.body(size: 11, color: AppColors.textMuted),
              prefixText: '₹ ',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _billingRow(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold ? AppTheme.heading(size: 13) : AppTheme.body(size: 12, color: AppColors.textMuted),
          ),
        ),
        Text(
          value,
          style: bold
              ? AppTheme.heading(size: 14).copyWith(color: AppColors.primaryGreen)
              : AppTheme.body(size: 12),
        ),
      ],
    );
  }

  Widget _billingField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        prefixText: '₹ ',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}