import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../goat_icons.dart';
import '../../models/bill_settings_model.dart';
import '../../models/customer_credit.dart';
import '../../models/monthly_bill_model.dart' show MonthlyBill;
import '../../models/palai_models.dart';
import '../../services/customer_goats_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../services/sales_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/latest_statement_card.dart';
import 'monthly_bills_screen.dart';

/// Lets the owner generate ONE consolidated report covering all (or a
/// chosen subset of) the goats under a single Palai customer — instead
/// of generating a report per goat one at a time.
///
/// Billing on this report is READ-ONLY: it shows the customer's latest
/// monthly statement and what they owe today (see [LatestStatementCard]).
/// Reports never create or change bills; bills are statements for the
/// previous month, made by [MonthlyStatementEngine].
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
  // BILLING (read-only, see LatestStatementCard)
  // ------------------------------------------------------------------

  /// The customer's CURRENT outstanding balance, re-fetched fresh (not
  /// from `widget.customer`, which may be stale).
  double _currentOutstanding = 0;

  /// The customer's CURRENT advance balance, re-fetched fresh at the
  /// same time as [_currentOutstanding].
  double _currentAdvanceAvailable = 0;

  /// This customer's unpaid Trading goat sales (e.g. a goat "Transfer to
  /// Palai" sale that still has a balance due), re-fetched fresh at the
  /// same time as [_currentOutstanding]. Null when they owe nothing on
  /// any sale.
  ///
  /// This is a SEPARATE figure from [_currentOutstanding]
  /// (`customer.pendingAmount`, which only tracks Palai boarding dues) —
  /// it is never merged into it or saved on top of it, since
  /// `pendingAmount` is also what payment settlement
  /// (`settleSalesInTransaction`) reads and writes. It is only surfaced
  /// here as its own labelled line and folded into the on-screen
  /// "Current Amount Due" total so the report never silently excludes a
  /// pending Trading balance.
  CustomerCredit? _goatSaleCredit;


  /// The customer's newest monthly bill (any month), or null if they
  /// have none yet. Included in the report as issued.
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
  // BILLING — LOAD (read-only)
  // ================================================================

  /// Loads the customer's live balance, their latest monthly bill and
  /// any unpaid Trading goat sales. Nothing is written.
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

      // The newest bill from the new billing; reports never create one.
      final latestBill = await MonthlyStatementEngine.instance.latestBill(
        farmId: widget.farmId,
        customerId: widget.customer.id,
        preferStatement: true,
      );

      // Same lookup the Goat sale credit card on the customer's profile
      // uses, so this report and that card always agree.
      final goatSaleCredit = await SalesService.instance.creditForPerson(
        widget.farmId,
        customerId: widget.customer.id,
        mobile: freshCustomer?.mobileNumber ?? widget.customer.mobileNumber,
        name: freshCustomer?.name ?? widget.customer.name,
      );

      if (!mounted) return;

      setState(() {
        _currentOutstanding =
            freshCustomer?.pendingAmount ?? widget.customer.pendingAmount;
        _currentAdvanceAvailable =
            freshCustomer?.advanceAmount ?? widget.customer.advanceAmount;
        _goatSaleCredit = goatSaleCredit;
        _existingMonthlyBill = latestBill;
        _loadingBilling = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBilling = false;
        _billingLoadError = 'Could not load billing info: $e';
      });
    }
  }

  Future<void> _openMonthlyBills() async {
    await Navigator.of(context).push(
      fastRoute(
        MonthlyBillsScreen(
          farmId: widget.farmId,
          customerId: widget.customer.id,
          customerName: widget.customer.name,
        ),
      ),
    );

    if (!mounted) return;
    await _loadBillingInfo();
  }

  /// Billing is ready once it has loaded. A customer without any bill
  /// yet can still get a report; it simply has no bill in it.
  bool get _billingReady => !_loadingBilling && _billingLoadError == null;

  // ================================================================
  // GENERATE
  // ================================================================

  Future<void> _generate({required bool share}) async {
    if (_selectedGoats.isEmpty) {
      _showSnack('Select at least one goat to include in the report.');
      return;
    }

    if (!_billingReady) {
      _showSnack('Billing is still loading. Try again in a moment.');
      return;
    }

    setState(() => _generating = true);

    try {
      final farm = await FirestoreService.instance.getFarmById(widget.farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();
      // Billing is read-only: the latest bill as issued (may be null).
      final monthlyBill = _existingMonthlyBill;

      if (share) {
        await CustomerGoatsReportPdfService.instance.share(
          customer: widget.customer,
          goats: _selectedGoats,
          billSettings: billSettings,
          bill: monthlyBill,
          goatSaleCredit: _goatSaleCredit,
        );
      } else {
        await CustomerGoatsReportPdfService.instance.preview(
          customer: widget.customer,
          goats: _selectedGoats,
          billSettings: billSettings,
          bill: monthlyBill,
          goatSaleCredit: _goatSaleCredit,
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
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
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
            color: Colors.black.withValues(alpha: 0.05),
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
                color: AppColors.primaryGreen.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                GoatIcons.paw,
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
  // BILLING CARD (read-only)
  // ------------------------------------------------------------------

  Widget _buildBillingCard() {
    return LatestStatementCard(
      bill: _existingMonthlyBill,
      livePending: _currentOutstanding,
      liveAdvance: _currentAdvanceAvailable,
      loading: _loadingBilling,
      error: _billingLoadError,
      onRetry: _loadBillingInfo,
      goatSaleCredit: _goatSaleCredit,
      onOpenBills: _openMonthlyBills,
    );
  }
}