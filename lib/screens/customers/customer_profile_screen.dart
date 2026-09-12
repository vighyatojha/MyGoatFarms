import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/monthly_bill_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_billing_service.dart';
import '../../widgets/fast_route.dart';

import '../finance/customer_ledger_screen.dart';
import '../palai/add_customer_screen.dart';
import '../palai/customer_palai/customer_goat_registration_screen.dart';
import '../palai/customer_palai/goat_profile_screen.dart';
import '../palai/multi_goat_checkout_screen.dart';
import 'customer_goats_progress_report_pdf_screen.dart';
import 'monthly_bills_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  final PalaiCustomer customer;
  final String farmId;

  const CustomerProfileScreen({
    super.key,
    required this.customer,
    required this.farmId,
  });

  @override
  State<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  late PalaiCustomer _customer;

  bool _loadingCustomer = false;
  bool _syncingOutstanding = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _farmSub;

  @override
  void initState() {
    super.initState();

    _customer = widget.customer;

    // Keep the farm/customer screen lightweight.
    // This listener is intentionally limited to the farm document.
    _farmSub = FirebaseFirestore.instance
        .collection('farms')
        .doc(widget.farmId)
        .snapshots()
        .listen((_) {});
  }

  @override
  void dispose() {
    _farmSub?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // CUSTOMER ACTIONS
  // ===========================================================================

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      fastRoute(
        AddCustomerScreen(
          customer: _customer,
        ),
      ),
    );

    if (!mounted) return;

    await _refreshCustomer();
  }

  Future<void> _openRegisterGoat() async {
    final goat = await Navigator.of(context).push<PalaiGoat>(
      fastRoute(
        CustomerGoatRegistrationScreen(
          customerId: _customer.id,
        ),
      ),
    );

    if (!mounted || goat == null) return;

    await _refreshCustomer();
  }

  Future<void> _openMultiGoatCheckout() async {
    await Navigator.of(context).push(
      fastRoute(
        MultiGoatCheckoutScreen(
          customerId: _customer.id,
          initialSelectedGoats: const [],
          allowSelection: true,
        ),
      ),
    );

    if (!mounted) return;

    await _refreshCustomer();
  }

  Future<void> _openMonthlyBills() async {
    await Navigator.of(context).push(
      fastRoute(
        MonthlyBillsScreen(
          farmId: widget.farmId,
          customerId: _customer.id,
          customerName: _customer.name,
          onAddPayment: (bill) async {
            final result = await showModalBottomSheet<bool>(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) {
                return _AddPaymentSheet(
                  farmId: widget.farmId,
                  customer: _customer,
                  bill: bill,
                );
              },
            );

            if (!mounted) return false;

            if (result == true) {
              await _refreshCustomer();
              return true;
            }

            return false;
          },
        ),
      ),
    );

    if (!mounted) return;

    await _refreshCustomer();
  }

  Future<void> _openGoatsReport() async {
    await Navigator.of(context).push(
      fastRoute(
        CustomerGoatsProgressReportScreen(
          farmId: widget.farmId,
          customer: _customer,
        ),
      ),
    );
  }

  // ===========================================================================
  // CUSTOMER REFRESH
  // ===========================================================================

  Future<void> _refreshCustomer() async {
    if (_loadingCustomer) return;

    if (mounted) {
      setState(() {
        _loadingCustomer = true;
      });
    }

    try {
      final customer = await FirestoreService.instance.getCustomer(
        widget.farmId,
        _customer.id,
      );

      if (!mounted) return;

      if (customer != null) {
        setState(() {
          _customer = customer;
        });
      }
    } catch (e) {
      debugPrint('Customer refresh error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCustomer = false;
        });
      }
    }
  }

  // ===========================================================================
  // OUTSTANDING SYNC
  // ===========================================================================

  Future<void> _syncOutstandingWithBills() async {
    if (_syncingOutstanding) return;

    setState(() {
      _syncingOutstanding = true;
    });

    try {
      final trueOutstanding =
      await MonthlyBillingService.instance.reconcileCustomerOutstanding(
        farmId: widget.farmId,
        customerId: _customer.id,
      );

      if (!mounted) return;

      await _refreshCustomer();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Outstanding synced: ₹${trueOutstanding.toStringAsFixed(0)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not sync outstanding: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncingOutstanding = false;
        });
      }
    }
  }

  // ===========================================================================
  // PAYMENT HISTORY
  // ===========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> _paymentHistoryStream() {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(widget.farmId)
        .collection('payments')
        .where(
      'customerId',
      isEqualTo: _customer.id,
    )
        .snapshots();
  }

  // ===========================================================================
  // OPEN CUSTOMER LEDGER
  // ===========================================================================

  Future<void> _openCustomerLedger() async {
    await Navigator.of(context).push(
      fastRoute(
        const CustomerLedgerScreen(),
      ),
    );

    if (!mounted) return;

    await _refreshCustomer();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final outstanding = _customer.pendingAmount;
    final advance = _customer.advanceAmount;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text(
          _customer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.heading(
            size: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Edit customer',
            onPressed: _openEdit,
            icon: const Icon(
              Icons.edit_outlined,
            ),
          ),
        ],
      ),

      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _refreshCustomer,

        child: StreamBuilder<List<PalaiGoat>>(
          stream: FirestoreService.instance.goatsForCustomerStream(
            widget.farmId,
            _customer.id,
          ),

          builder: (context, goatSnapshot) {
            final goats = goatSnapshot.data ?? const <PalaiGoat>[];

            final activeGoats = goats
                .where(
                  (goat) => !goat.isCheckedOut,
            )
                .length;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                32,
              ),

              children: [
                // ============================================================
                // CUSTOMER INFORMATION
                // ============================================================

                _buildCustomerInformationSection(),

                const SizedBox(height: 18),

                // ============================================================
                // FINANCIAL SUMMARY
                // ============================================================

                _buildSectionHeader(
                  title: 'Payment Information',
                  icon: Icons.account_balance_wallet_outlined,
                ),

                const SizedBox(height: 10),

                _buildFinancialSummary(
                  outstanding,
                  advance,
                ),

                const SizedBox(height: 12),

                _buildFinancialActions(),

                const SizedBox(height: 14),

                _buildMonthlyBillingButton(),

                const SizedBox(height: 10),

                _buildGoatsReportButton(),

                const SizedBox(height: 16),

                // ============================================================
                // CHECKOUT
                // ============================================================

                _buildCheckoutButton(),

                const SizedBox(height: 24),

                // ============================================================
                // GOAT LIST — NOW BEFORE PAYMENT HISTORY
                // ============================================================

                _buildSectionHeader(
                  title: 'Goats',
                  icon: Icons.pets,
                  trailing: TextButton.icon(
                    onPressed: _openRegisterGoat,
                    icon: const Icon(
                      Icons.add,
                      size: 18,
                    ),
                    label: const Text('Add Goat'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                if (!goatSnapshot.hasData)
                  const _GoatListSkeleton()
                else if (goats.isEmpty)
                  _emptyGoatsState()
                else ...[
                    _buildGoatStats(
                      goats.length,
                      activeGoats,
                    ),

                    const SizedBox(height: 10),

                    // Keep goat cards light and simple.
                    // Images are decoded at a small cache width.
                    for (final goat in goats)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 9,
                        ),
                        child: _goatHistoryCard(goat),
                      ),
                  ],

                const SizedBox(height: 22),

                // ============================================================
                // PAYMENT HISTORY — ALWAYS LAST SECTION
                // ============================================================

                _buildPaymentHistory(),

                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION HEADER
  // ===========================================================================

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.lightGreen,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 19,
            color: AppColors.primaryGreen,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Text(
            title,
            style: AppTheme.heading(
              size: 17,
            ),
          ),
        ),

        if (trailing != null) trailing,
      ],
    );
  }

  // ===========================================================================
  // CUSTOMER INFORMATION
  // ===========================================================================

  Widget _buildCustomerInformationSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(
        radius: 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _customer.name.trim().isNotEmpty
                      ? _customer.name.trim()[0].toUpperCase()
                      : '?',
                  style: AppTheme.heading(
                    size: 21,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 17,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 14,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _customer.mobileNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              size: 11,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_loadingCustomer)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryGreen,
                  ),
                ),
            ],
          ),

          if (_customer.address.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.paleGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 17,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _customer.address,
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 13),

          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: AppColors.textGrey,
              ),
              const SizedBox(width: 7),
              Text(
                'Joined ${DateFormat('dd MMM yyyy').format(_customer.joiningDate)}',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FINANCIAL SUMMARY
  // ===========================================================================

  Widget _buildFinancialSummary(
      double outstanding,
      double advance,
      ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _financialCard(
                icon: Icons.receipt_long_outlined,
                label: 'Outstanding',
                value: _rupees(outstanding),
                color: outstanding > 0
                    ? AppColors.error
                    : AppColors.success,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: _financialCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Advance',
                value: _rupees(advance),
                color: AppColors.success,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: AppTheme.card(
            radius: 14,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Balance',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      outstanding > 0
                          ? 'Customer owes ${_rupees(outstanding)}'
                          : advance > 0
                          ? 'Customer has ${_rupees(advance)} advance'
                          : 'Account is settled',
                      style: AppTheme.heading(
                        size: 12,
                        color: outstanding > 0
                            ? AppColors.error
                            : AppColors.darkGreen,
                      ),
                    ),
                  ],
                ),
              ),

              IconButton(
                tooltip: 'Sync with Monthly Bills',
                onPressed: _syncingOutstanding
                    ? null
                    : _syncOutstandingWithBills,
                icon: _syncingOutstanding
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(
                  Icons.sync_rounded,
                  size: 20,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _financialCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
        radius: 15,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 17,
              color: color,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            value,
            style: AppTheme.heading(
              size: 18,
              color: color,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            label,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FINANCIAL ACTIONS
  // ===========================================================================

  Widget _buildFinancialActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _openAddPayment,
            icon: const Icon(
              Icons.payments_outlined,
              size: 18,
            ),
            label: const Text(
              'Add Payment',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                vertical: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        const SizedBox(width: 9),

        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openAddOutstanding,
            icon: const Icon(
              Icons.add_card_outlined,
              size: 18,
            ),
            label: const Text(
              'Add Outstanding',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              side: const BorderSide(
                color: AppColors.primaryGreen,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MONTHLY BILLS
  // ===========================================================================

  Widget _buildMonthlyBillingButton() {
    return _actionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Monthly Bills',
      subtitle: 'Generate and manage monthly bills',
      onTap: _openMonthlyBills,
    );
  }

  Widget _buildGoatsReportButton() {
    return _actionCard(
      icon: Icons.analytics_outlined,
      title: 'Goats Report',
      subtitle: 'Generate a progress report for this customer',
      onTap: _openGoatsReport,
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: AppTheme.card(
            radius: 15,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.heading(
                        size: 13,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textGrey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CHECKOUT
  // ===========================================================================

  Widget _buildCheckoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _openMultiGoatCheckout,
        icon: const Icon(
          Icons.logout_rounded,
          size: 20,
        ),
        label: const Text(
          'CHECK OUT GOAT(S)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // GOAT STATS
  // ===========================================================================

  Widget _buildGoatStats(
      int total,
      int active,
      ) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.pets,
            label: 'Total Goats',
            value: '$total',
            color: AppColors.primaryGreen,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: _statCard(
            icon: Icons.login_rounded,
            label: 'Currently Boarded',
            value: '$active',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(
        radius: 14,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 17,
              color: color,
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTheme.heading(
                    size: 17,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 9,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GOAT CARD
  // ===========================================================================

  Widget _goatHistoryCard(
      PalaiGoat goat,
      ) {
    final healthColor = _healthColor(
      goat.healthStatus,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            fastRoute(
              GoatProfileScreen(
                farmId: widget.farmId,
                goat: goat,
              ),
            ),
          );

          if (mounted) {
            setState(() {});
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(
            radius: 16,
          ),
          child: Row(
            children: [
              _goatAvatar(goat, healthColor),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goat.goatCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 13,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      '${goat.breed} · ${goat.gender}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      goat.isCheckedOut
                          ? 'Checked out · ${_boardedFor(
                        goat.checkInDate,
                        goat.checkOutDate,
                      )}'
                          : 'Boarded · ${_boardedFor(
                        goat.checkInDate,
                        null,
                      )}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 9,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                constraints: const BoxConstraints(
                  maxWidth: 88,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: goat.isCheckedOut
                      ? AppColors.lightGreen
                      : healthColor.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  goat.isCheckedOut
                      ? 'Checked Out'
                      : goat.healthStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 8.5,
                    color: goat.isCheckedOut
                        ? AppColors.darkGreen
                        : healthColor,
                    weight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(width: 2),

              const Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goatAvatar(
      PalaiGoat goat,
      Color healthColor,
      ) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.lightGreen,
        border: Border.all(
          color: healthColor.withOpacity(0.55),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: goat.beforeImage != null &&
            goat.beforeImage!.isNotEmpty
            ? Image.memory(
          goat.beforeImage!,
          fit: BoxFit.cover,

          // Decode the image close to its actual display size.
          // This avoids decoding large camera images at full
          // resolution just to show a 48px avatar.
          cacheWidth: 96,
          cacheHeight: 96,

          errorBuilder: (_, __, ___) {
            return const Icon(
              Icons.pets,
              color: AppColors.primaryGreen,
              size: 22,
            );
          },
        )
            : const Icon(
          Icons.pets,
          color: AppColors.primaryGreen,
          size: 22,
        ),
      ),
    );
  }

  // ===========================================================================
  // EMPTY GOATS
  // ===========================================================================

  Widget _emptyGoatsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 28,
        horizontal: 20,
      ),
      decoration: AppTheme.card(
        radius: 16,
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.pets,
              size: 29,
              color: AppColors.primaryGreen,
            ),
          ),

          const SizedBox(height: 11),

          Text(
            'No goats yet',
            style: AppTheme.heading(
              size: 14,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'Goats checked in for ${_customer.name} will appear here.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          ),

          const SizedBox(height: 13),

          OutlinedButton.icon(
            onPressed: _openRegisterGoat,
            icon: const Icon(
              Icons.add,
              size: 17,
            ),
            label: const Text(
              'Check In Goat',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              side: const BorderSide(
                color: AppColors.primaryGreen,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYMENT HISTORY
  //
  // IMPORTANT:
  // This is deliberately the LAST section of the Customer Profile.
  //
  // The outer Customer Profile scroll does NOT control the payment list.
  // Only the inner payment list scrolls.
  // ===========================================================================

  Widget _buildPaymentHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.lightGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 19,
                color: AppColors.primaryGreen,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment History',
                    style: AppTheme.heading(
                      size: 16,
                    ),
                  ),
                  Text(
                    'Recent payments and outstanding changes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 9,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),

            // ================================================================
            // ALL PAYMENTS → CUSTOMER LEDGER
            // ================================================================

            TextButton(
              onPressed: _openCustomerLedger,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'All payments',
                    style: AppTheme.body(
                      size: 10,
                      color: AppColors.primaryGreen,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _paymentHistoryStream(),

          builder: (context, snapshot) {
            // ================================================================
            // ERROR
            // ================================================================

            if (snapshot.hasError) {
              return _paymentErrorCard(
                snapshot.error.toString(),
              );
            }

            // ================================================================
            // SKELETON
            // ================================================================

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _PaymentHistorySkeleton();
            }

            final docs = snapshot.data?.docs ?? [];

            // ================================================================
            // EMPTY
            // ================================================================

            if (docs.isEmpty) {
              return _emptyPaymentHistory();
            }

            // ================================================================
            // SORT
            //
            // Firestore query intentionally does not require an index here.
            // Sorting locally also supports old payment documents where
            // `date` may be missing.
            // ================================================================

            final sorted = [...docs];

            sorted.sort(
                  (a, b) {
                final aDate = _timestampToDate(
                  a.data()['date'],
                );

                final bDate = _timestampToDate(
                  b.data()['date'],
                );

                return bDate.compareTo(aDate);
              },
            );

            // ================================================================
            // FIXED HEIGHT
            //
            // This is the important part:
            //
            // Customer Profile scroll
            //        ↓
            // Goat list
            //        ↓
            // Payment History
            //        ↓
            // ┌─────────────────────────────┐
            // │ payment 1                  │
            // │ payment 2                  │  ← ONLY THIS AREA SCROLLS
            // │ payment 3                  │
            // │ payment 4                  │
            // └─────────────────────────────┘
            //
            // The payment history can never push the rest of the screen
            // indefinitely downward.
            // ================================================================

            return Container(
              width: double.infinity,
              height: 310,

              decoration: AppTheme.card(
                radius: 16,
              ),

              clipBehavior: Clip.antiAlias,

              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  10,
                  10,
                  10,
                  10,
                ),

                physics: const ClampingScrollPhysics(),

                itemCount: sorted.length,

                itemBuilder: (context, index) {
                  final doc = sorted[index];

                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 8,
                    ),
                    child: _paymentCard(
                      doc,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ===========================================================================
  // PAYMENT CARD
  // ===========================================================================

  Widget _paymentCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();

    final isOutstanding =
        data['type'] == 'outstandingAdded';

    final amount = data['amount'] ?? 0;

    final method = isOutstanding
        ? 'Outstanding Added'
        : (data['paymentMethod'] ?? 'Unknown').toString();

    final paymentNumber =
    (data['paymentNumber'] ?? '').toString();

    final note =
    (data['note'] ?? '').toString();

    final pendingAfter =
        data['pendingAfter'] ?? 0;

    final advance =
        data['advanceAmount'] ?? 0;

    final cardColor = isOutstanding
        ? AppColors.error
        : AppColors.success;

    final cardIcon = isOutstanding
        ? Icons.trending_up_rounded
        : Icons.payments_outlined;

    final amountText = isOutstanding
        ? '+${_rupees(amount)}'
        : _rupees(amount);

    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: () {
          _showPaymentDetails(data);
        },

        borderRadius: BorderRadius.circular(13),

        child: Container(
          padding: const EdgeInsets.all(11),

          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: AppColors.divider,
              width: 0.8,
            ),
          ),

          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.11),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  cardIcon,
                  color: cardColor,
                  size: 19,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      amountText,
                      style: AppTheme.heading(
                        size: 13,
                        color: cardColor,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      method,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textDark,
                        weight: FontWeight.w600,
                      ),
                    ),

                    if (paymentNumber.isNotEmpty)
                      Text(
                        paymentNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 8,
                          color: AppColors.textGrey,
                        ),
                      ),

                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 2,
                        ),
                        child: Text(
                          note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            size: 8,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 7),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(data['date']),
                    maxLines: 1,
                    style: AppTheme.body(
                      size: 8,
                      color: AppColors.textGrey,
                    ),
                  ),

                  if (pendingAfter is num &&
                      pendingAfter > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Pending ${_rupees(pendingAfter)}',
                      style: AppTheme.body(
                        size: 8,
                        color: AppColors.error,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],

                  if (advance is num &&
                      advance > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Advance ${_rupees(advance)}',
                      style: AppTheme.body(
                        size: 8,
                        color: AppColors.darkGreen,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(width: 3),

              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // EMPTY PAYMENT HISTORY
  // ===========================================================================

  Widget _emptyPaymentHistory() {
    return Container(
      width: double.infinity,
      height: 190,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.card(
        radius: 16,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: AppColors.primaryGreen,
              size: 23,
            ),
          ),

          const SizedBox(height: 9),

          Text(
            'No payments yet',
            style: AppTheme.heading(
              size: 13,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            'Payments received from this customer will appear here.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 9,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYMENT ERROR
  // ===========================================================================

  Widget _paymentErrorCard(
      String error,
      ) {
    return Container(
      width: double.infinity,
      height: 190,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(
        radius: 16,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 28,
          ),

          const SizedBox(height: 7),

          Text(
            'Could not load payment history.',
            style: AppTheme.heading(
              size: 12,
              color: AppColors.error,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            error,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 8,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYMENT DETAILS
  // ===========================================================================

  void _showPaymentDetails(
      Map<String, dynamic> data,
      ) {
    final amount = data['amount'] ?? 0;

    final method =
    (data['paymentMethod'] ?? '').toString();

    final paymentNumber =
    (data['paymentNumber'] ?? '').toString();

    final note =
    (data['note'] ?? '').toString();

    final isOutstanding =
        data['type'] == 'outstandingAdded';

    final pendingBefore =
        data['pendingBefore'] ?? 0;

    final applied = isOutstanding
        ? (data['pendingAdded'] ?? 0)
        : (data['amountAppliedToPending'] ??
        data['amountAppliedToBill'] ??
        0);

    final pendingAfter =
        data['pendingAfter'] ?? 0;

    final advanceBefore =
        data['advanceBefore'] ?? 0;

    final advanceAdded = isOutstanding
        ? (data['advanceUsed'] ?? 0)
        : (data['advanceAmount'] ?? 0);

    final advanceAfter =
        data['advanceAfter'] ?? 0;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        return Container(
          constraints: BoxConstraints(
            maxHeight:
            MediaQuery.of(context).size.height * 0.82,
          ),

          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20,
          ),

          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),

          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius:
                      BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 17),

                Text(
                  isOutstanding
                      ? 'Outstanding Details'
                      : 'Payment Details',
                  style: AppTheme.heading(
                    size: 18,
                  ),
                ),

                const SizedBox(height: 15),

                _detailRow(
                  isOutstanding
                      ? 'Reference Number'
                      : 'Payment Number',
                  paymentNumber.isEmpty
                      ? '—'
                      : paymentNumber,
                ),

                _detailRow(
                  isOutstanding
                      ? 'Amount Added'
                      : 'Amount Received',
                  _rupees(amount),
                ),

                if (!isOutstanding)
                  _detailRow(
                    'Payment Method',
                    method.isEmpty
                        ? '—'
                        : method,
                  ),

                _detailRow(
                  'Pending Before',
                  _rupees(pendingBefore),
                ),

                _detailRow(
                  isOutstanding
                      ? 'Added to Pending'
                      : 'Applied to Pending',
                  _rupees(applied),
                ),

                _detailRow(
                  'Pending After',
                  _rupees(pendingAfter),
                ),

                _detailRow(
                  'Advance Before',
                  _rupees(advanceBefore),
                ),

                _detailRow(
                  isOutstanding
                      ? 'Advance Used'
                      : 'Advance Added',
                  _rupees(advanceAdded),
                ),

                _detailRow(
                  'Advance After',
                  _rupees(advanceAfter),
                ),

                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),

                  Text(
                    'Note',
                    style: AppTheme.heading(
                      size: 12,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    note,
                    style: AppTheme.body(
                      size: 11,
                      color: AppColors.textDark,
                    ),
                  ),
                ],

                const SizedBox(height: 17),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding:
                      const EdgeInsets.symmetric(
                        vertical: 13,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
      String label,
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.heading(
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Color _healthColor(
      String status,
      ) {
    switch (status) {
      case 'Sick':
        return AppColors.error;

      case 'Under Observation':
        return AppColors.warning;

      default:
        return AppColors.success;
    }
  }

  String _boardedFor(
      DateTime checkInDate,
      DateTime? checkOutDate,
      ) {
    final end = checkOutDate ?? DateTime.now();

    int months =
        (end.year - checkInDate.year) * 12 +
            (end.month - checkInDate.month);

    DateTime monthsAgo = DateTime(
      checkInDate.year,
      checkInDate.month + months,
      checkInDate.day,
    );

    if (monthsAgo.isAfter(end)) {
      months -= 1;

      monthsAgo = DateTime(
        checkInDate.year,
        checkInDate.month + months,
        checkInDate.day,
      );
    }

    final days = end.difference(monthsAgo).inDays;

    if (months <= 0) {
      return '$days day${days == 1 ? '' : 's'}';
    }

    if (days <= 0) {
      return '$months month${months == 1 ? '' : 's'}';
    }

    return '$months mo $days d';
  }

  String _formatDate(
      dynamic value,
      ) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return 'Date unavailable';
    }

    return DateFormat(
      'dd MMM yyyy · hh:mm a',
    ).format(date);
  }

  String _rupees(
      dynamic value,
      ) {
    double amount = 0;

    if (value is num) {
      amount = value.toDouble();
    } else {
      amount = double.tryParse(
        value?.toString() ?? '',
      ) ??
          0;
    }

    return '₹${amount.toStringAsFixed(0)}';
  }

  // ===========================================================================
  // ADD PAYMENT
  // ===========================================================================

  Future<void> _openAddPayment() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        return _AddPaymentSheet(
          farmId: widget.farmId,
          customer: _customer,
        );
      },
    );

    if (!mounted) return;

    if (result == true) {
      await _refreshCustomer();
    }
  }

  // ===========================================================================
  // ADD OUTSTANDING
  // ===========================================================================

  Future<void> _openAddOutstanding() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        return _AddOutstandingSheet(
          farmId: widget.farmId,
          customer: _customer,
        );
      },
    );

    if (!mounted) return;

    if (result == true) {
      await _refreshCustomer();
    }
  }
}

// ============================================================================
// GOAT LIST SKELETON
// ============================================================================

class _GoatListSkeleton extends StatelessWidget {
  const _GoatListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: const [
            Expanded(
              child: _SkeletonBox(
                height: 66,
                radius: 14,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _SkeletonBox(
                height: 66,
                radius: 14,
              ),
            ),
          ],
        ),

        SizedBox(height: 10),

        _SkeletonGoatCard(),
        SizedBox(height: 9),
        _SkeletonGoatCard(),
        SizedBox(height: 9),
        _SkeletonGoatCard(),
      ],
    );
  }
}

class _SkeletonGoatCard extends StatelessWidget {
  const _SkeletonGoatCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(
        radius: 16,
      ),
      child: Row(
        children: const [
          _SkeletonBox(
            width: 48,
            height: 48,
            radius: 24,
          ),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                _SkeletonBox(
                  width: 105,
                  height: 12,
                  radius: 5,
                ),
                SizedBox(height: 7),
                _SkeletonBox(
                  width: 145,
                  height: 9,
                  radius: 4,
                ),
                SizedBox(height: 6),
                _SkeletonBox(
                  width: 115,
                  height: 8,
                  radius: 4,
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          _SkeletonBox(
            width: 58,
            height: 22,
            radius: 7,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PAYMENT HISTORY SKELETON
// ============================================================================

class _PaymentHistorySkeleton extends StatelessWidget {
  const _PaymentHistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 310,
      padding: const EdgeInsets.all(10),
      decoration: AppTheme.card(
        radius: 16,
      ),
      child: Column(
        children: const [
          Expanded(
            child: _SkeletonPaymentCard(),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _SkeletonPaymentCard(),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _SkeletonPaymentCard(),
          ),
        ],
      ),
    );
  }
}

class _SkeletonPaymentCard extends StatelessWidget {
  const _SkeletonPaymentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.divider,
          width: 0.8,
        ),
      ),
      child: Row(
        children: const [
          _SkeletonBox(
            width: 39,
            height: 39,
            radius: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                _SkeletonBox(
                  width: 75,
                  height: 12,
                  radius: 4,
                ),
                SizedBox(height: 6),
                _SkeletonBox(
                  width: 100,
                  height: 9,
                  radius: 4,
                ),
                SizedBox(height: 5),
                _SkeletonBox(
                  width: 70,
                  height: 7,
                  radius: 3,
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            crossAxisAlignment:
            CrossAxisAlignment.end,
            children: [
              _SkeletonBox(
                width: 70,
                height: 8,
                radius: 3,
              ),
              SizedBox(height: 6),
              _SkeletonBox(
                width: 65,
                height: 8,
                radius: 3,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SIMPLE SKELETON BOX
// ============================================================================

class _SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const _SkeletonBox({
    this.width,
    required this.height,
    required this.radius,
  });

  @override
  State<_SkeletonBox> createState() =>
      _SkeletonBoxState();
}

class _SkeletonBoxState
    extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1200,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity =
            0.45 +
                (_controller.value * 0.25);

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(opacity),
            borderRadius:
            BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

// ============================================================================
// ADD PAYMENT SHEET
// ============================================================================

class _AddPaymentSheet extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;
  final MonthlyBill? bill;

  const _AddPaymentSheet({
    required this.farmId,
    required this.customer,
    this.bill,
  });

  @override
  State<_AddPaymentSheet> createState() =>
      _AddPaymentSheetState();
}

class _AddPaymentSheetState
    extends State<_AddPaymentSheet> {
  final TextEditingController _amountController =
  TextEditingController();

  final TextEditingController _referenceController =
  TextEditingController();

  final TextEditingController _noteController =
  TextEditingController();

  String _paymentMethod = 'Cash';

  bool _saving = false;

  double get _amount =>
      double.tryParse(
        _amountController.text.trim(),
      ) ??
          0;

  double get _paymentLimit {
    if (widget.bill != null) {
      return widget.bill!.remainingAmount;
    }

    return widget.customer.pendingAmount;
  }

  double get _applied {
    return _amount
        .clamp(
      0,
      _paymentLimit,
    )
        .toDouble();
  }

  double get _advanceAdded {
    return (_amount - _applied)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_amount <= 0) {
      _error(
        'Enter a payment amount greater than ₹0.',
      );
      return;
    }

    if (_paymentLimit <= 0) {
      _error(
        widget.bill != null
            ? 'This monthly bill has no remaining amount.'
            : 'This customer has no outstanding amount.',
      );
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      if (widget.bill != null) {
        final result =
        await MonthlyBillingService.instance
            .receiveMonthlyBillPayment(
          farmId: widget.farmId,
          customerId: widget.customer.id,
          billId: widget.bill!.id,
          paidAmount: _amount,
          paymentMethod: _paymentMethod,
          note: _buildNote(),
        );

        if (!mounted) return;

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text(
                'Payment Recorded',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    result.paymentNumber,
                    style: AppTheme.heading(
                      size: 14,
                    ),
                  ),
                  const SizedBox(height: 13),
                  _resultRow(
                    'Bill',
                    result.billNumber,
                  ),
                  _resultRow(
                    'Amount',
                    '₹${result.amountReceived.toStringAsFixed(0)}',
                  ),
                  _resultRow(
                    'Bill Remaining',
                    '₹${result.billRemainingAfter.toStringAsFixed(0)}',
                  ),
                  _resultRow(
                    'Customer Pending',
                    '₹${result.pendingAfter.toStringAsFixed(0)}',
                  ),
                  if (result.advanceAfter > 0)
                    _resultRow(
                      'Customer Advance',
                      '₹${result.advanceAfter.toStringAsFixed(0)}',
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );

        if (!mounted) return;

        Navigator.pop(
          context,
          true,
        );

        return;
      }

      final result =
      await FirestoreService.instance
          .receivePalaiPayment(
        farmId: widget.farmId,
        customerId: widget.customer.id,
        paidAmount: _amount,
        paymentMethod: _paymentMethod,
        note: _buildNote(),
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Payment Recorded',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  result.paymentNumber,
                  style: AppTheme.heading(
                    size: 14,
                  ),
                ),
                const SizedBox(height: 13),
                _resultRow(
                  'Amount',
                  '₹${result.amountReceived.toStringAsFixed(0)}',
                ),
                _resultRow(
                  'Applied to Pending',
                  '₹${result.amountAppliedToPending.toStringAsFixed(0)}',
                ),
                _resultRow(
                  'Pending After',
                  '₹${result.pendingAfter.toStringAsFixed(0)}',
                ),
                if (result.advanceAdded > 0)
                  _resultRow(
                    'Advance Added',
                    '₹${result.advanceAdded.toStringAsFixed(0)}',
                  ),
                _resultRow(
                  'Total Advance',
                  '₹${result.advanceAfter.toStringAsFixed(0)}',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (!mounted) return;

      _error(
        FirestoreService.instance.describeError(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _buildNote() {
    final note =
    _noteController.text.trim();

    final reference =
    _referenceController.text.trim();

    if (reference.isEmpty) {
      return note;
    }

    if (note.isEmpty) {
      return 'Reference: $reference';
    }

    return '$note · Reference: $reference';
  }

  void _error(
      String message,
      ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 +
            MediaQuery.of(context)
                .viewInsets
                .bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            _sheetHandle(),

            const SizedBox(height: 18),

            Text(
              widget.bill != null
                  ? 'Pay Monthly Bill'
                  : 'Add New Payment',
              style: AppTheme.heading(
                size: 20,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              widget.customer.name,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
              ),
            ),

            if (widget.bill != null) ...[
              const SizedBox(height: 9),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius:
                  BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.bill!.billNumber,
                      style: AppTheme.heading(
                        size: 13,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('MMMM yyyy').format(
                        widget.bill!.billingMonth,
                      ),
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bill Remaining: ₹${widget.bill!.remainingAmount.toStringAsFixed(0)}',
                      style: AppTheme.heading(
                        size: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 17),

            _balancePreview(),

            const SizedBox(height: 18),

            _fieldLabel(
              'Payment Amount',
            ),

            _outlinedField(
              controller: _amountController,
              hint: widget.bill != null
                  ? 'Maximum ₹${widget.bill!.remainingAmount.toStringAsFixed(0)}'
                  : 'Enter amount',
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              prefix: const Text('₹ '),
              onChanged: (_) {
                setState(() {});
              },
            ),

            const SizedBox(height: 15),

            _fieldLabel(
              'Payment Method',
            ),

            _paymentMethodField(),

            const SizedBox(height: 15),

            _fieldLabel(
              'Reference Number (optional)',
            ),

            _outlinedField(
              controller: _referenceController,
              hint:
              'UPI / transaction / cheque number',
            ),

            const SizedBox(height: 15),

            _fieldLabel(
              'Note (optional)',
            ),

            _outlinedField(
              controller: _noteController,
              hint: 'Add a note',
              maxLines: 3,
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                _saving ? null : _save,
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Text(
                  widget.bill != null
                      ? 'Pay Monthly Bill'
                      : 'Receive Payment',
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius:
          BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _balancePreview() {
    final outstanding =
        widget.customer.pendingAmount;

    final advance =
        widget.customer.advanceAmount;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius:
        BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  widget.bill != null
                      ? 'Bill Remaining'
                      : 'Outstanding',
                  style: AppTheme.body(
                    size: 9,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '₹${_paymentLimit.toStringAsFixed(0)}',
                  style: AppTheme.heading(
                    size: 16,
                    color: _paymentLimit > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.end,
              children: [
                Text(
                  'Customer Pending',
                  style: AppTheme.body(
                    size: 9,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '₹${outstanding.toStringAsFixed(0)}',
                  style: AppTheme.heading(
                    size: 16,
                    color: outstanding > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Advance ₹${advance.toStringAsFixed(0)}',
                  style: AppTheme.body(
                    size: 8,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodField() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child:
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _paymentMethod,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'Cash',
              child: Text('Cash'),
            ),
            DropdownMenuItem(
              value: 'UPI',
              child: Text('UPI'),
            ),
            DropdownMenuItem(
              value: 'Bank Transfer',
              child: Text('Bank Transfer'),
            ),
            DropdownMenuItem(
              value: 'Cheque',
              child: Text('Cheque'),
            ),
            DropdownMenuItem(
              value: 'Other',
              child: Text('Other'),
            ),
          ],
          onChanged: _saving
              ? null
              : (value) {
            if (value == null) return;

            setState(() {
              _paymentMethod =
                  value;
            });
          },
        ),
      ),
    );
  }

  Widget _outlinedField({
    required TextEditingController controller,
    String? hint,
    Widget? prefix,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefix: prefix,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.divider,
          ),
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.divider,
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.5,
          ),
        ),
      ),
      style: AppTheme.body(
        size: 12,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _fieldLabel(
      String text,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 6,
      ),
      child: Text(
        text,
        style: AppTheme.body(
          size: 10,
          color: AppColors.textDark,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _resultRow(
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.heading(
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ADD OUTSTANDING SHEET
// ============================================================================

class _AddOutstandingSheet
    extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;

  const _AddOutstandingSheet({
    required this.farmId,
    required this.customer,
  });

  @override
  State<_AddOutstandingSheet> createState() =>
      _AddOutstandingSheetState();
}

class _AddOutstandingSheetState
    extends State<_AddOutstandingSheet> {
  final TextEditingController
  _amountController =
  TextEditingController();

  final TextEditingController
  _noteController =
  TextEditingController();

  bool _saving = false;

  double get _amount =>
      double.tryParse(
        _amountController.text.trim(),
      ) ??
          0;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_amount <= 0) {
      _error(
        'Enter an outstanding amount greater than ₹0.',
      );
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final db =
          FirebaseFirestore.instance;

      final farmRef =
      db.collection('farms').doc(
        widget.farmId,
      );

      final customerRef = farmRef
          .collection('palaiCustomers')
          .doc(widget.customer.id);

      final billRef =
      farmRef.collection('bills').doc();

      final activityRef = farmRef
          .collection('activities')
          .doc();

      final paymentRef = farmRef
          .collection('payments')
          .doc();

      final now = DateTime.now();

      final billNumber =
          'OPEN-${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '-${billRef.id.substring(0, 6).toUpperCase()}';

      await db.runTransaction(
            (transaction) async {
          final snapshot =
          await transaction.get(
            customerRef,
          );

          if (!snapshot.exists) {
            throw StateError(
              'Customer no longer exists.',
            );
          }

          final data =
              snapshot.data() ?? {};

          final oldPending =
          (data['pendingAmount'] ?? 0)
              .toDouble();

          final oldAdvance =
          (data['advanceAmount'] ?? 0)
              .toDouble();

          final advanceUsed =
          _amount
              .clamp(0, oldAdvance)
              .toDouble();

          final remainingOutstanding =
              _amount - advanceUsed;

          final newAdvance =
              oldAdvance - advanceUsed;

          final newPending =
              oldPending +
                  remainingOutstanding;

          transaction.update(
            customerRef,
            {
              'pendingAmount':
              newPending,
              'advanceAmount':
              newAdvance,
              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );

          transaction.set(
            billRef,
            {
              'billNumber':
              billNumber,
              'type':
              'opening_balance',
              'customerId':
              widget.customer.id,
              'customerName':
              widget.customer.name,
              'description':
              'Outstanding amount added',
              'newCharges':
              _amount,
              'previousPending':
              oldPending,
              'advanceBefore':
              oldAdvance,
              'advanceUsed':
              advanceUsed,
              'totalDue':
              newPending,
              'amountPaid':
              0,
              'pendingAfter':
              newPending,
              'advanceAfter':
              newAdvance,
              'note':
              _noteController.text
                  .trim(),
              'status':
              'pending',
              'createdAt':
              FieldValue.serverTimestamp(),
              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );

          transaction.set(
            paymentRef,
            {
              'customerId':
              widget.customer.id,
              'customerName':
              widget.customer.name,
              'type':
              'outstandingAdded',
              'amount':
              _amount,
              'paymentMethod':
              'Outstanding Added',
              'paymentNumber':
              billNumber,
              'note':
              _noteController.text
                  .trim(),
              'pendingBefore':
              oldPending,
              'pendingAdded':
              remainingOutstanding,
              'pendingAfter':
              newPending,
              'advanceBefore':
              oldAdvance,
              'advanceUsed':
              advanceUsed,
              'advanceAmount':
              0,
              'advanceAfter':
              newAdvance,
              'date':
              FieldValue.serverTimestamp(),
              'createdAt':
              FieldValue.serverTimestamp(),
            },
          );

          transaction.set(
            activityRef,
            {
              'type':
              'paymentReceived',
              'title':
              'Outstanding Added',
              'subtitle':
              '${widget.customer.name} · ₹${_amount.toStringAsFixed(0)}',
              'module':
              'palai',
              'timestamp':
              FieldValue.serverTimestamp(),
            },
          );
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            '₹${_amount.toStringAsFixed(0)} outstanding added.',
          ),
          backgroundColor:
          AppColors.primaryGreen,
          behavior:
          SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _error(
        FirestoreService.instance
            .describeError(e),
      );
    }
  }

  void _error(
      String message,
      ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        AppColors.error,
        behavior:
        SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        widget.customer.pendingAmount;

    final after =
        current + _amount;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 +
            MediaQuery.of(context)
                .viewInsets
                .bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration:
                BoxDecoration(
                  color:
                  Colors.grey.shade300,
                  borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Text(
              'Add Outstanding',
              style: AppTheme.heading(
                size: 20,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              widget.customer.name,
              style: AppTheme.body(
                size: 11,
                color:
                AppColors.textGrey,
              ),
            ),

            const SizedBox(height: 17),

            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.all(15),
              decoration:
              BoxDecoration(
                color: Colors.white,
                borderRadius:
                BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color:
                  AppColors.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'OUTSTANDING SUMMARY',
                          style:
                          AppTheme.heading(
                            size: 13,
                            color: AppColors
                                .primaryGreen,
                          ),
                        ),
                      ),
                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration:
                        BoxDecoration(
                          color: AppColors
                              .error
                              .withOpacity(
                            0.10,
                          ),
                          borderRadius:
                          BorderRadius
                              .circular(
                            7,
                          ),
                        ),
                        child: Text(
                          'OUTSTANDING',
                          style: AppTheme
                              .body(
                            size: 8,
                            color: AppColors
                                .error,
                            weight:
                            FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 11),

                  const Divider(
                    height: 1,
                  ),

                  const SizedBox(height: 11),

                  _summaryRow(
                    'Current Outstanding',
                    '₹${current.toStringAsFixed(0)}',
                  ),

                  const SizedBox(height: 8),

                  _summaryRow(
                    'Amount Being Added',
                    '₹${_amount.toStringAsFixed(0)}',
                  ),

                  const SizedBox(height: 11),

                  const Divider(
                    height: 1,
                  ),

                  const SizedBox(height: 11),

                  _summaryRow(
                    'Total Outstanding',
                    '₹${after.toStringAsFixed(0)}',
                    bold: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 19),

            _fieldLabel(
              'Outstanding Amount',
            ),

            TextField(
              controller:
              _amountController,
              keyboardType:
              const TextInputType
                  .numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) {
                setState(() {});
              },
              decoration:
              InputDecoration(
                hintText:
                'Enter amount',
                prefixText: '₹ ',
                filled: true,
                fillColor:
                Colors.white,
                contentPadding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    12,
                  ),
                  borderSide:
                  const BorderSide(
                    color:
                    AppColors.divider,
                  ),
                ),
                enabledBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    12,
                  ),
                  borderSide:
                  const BorderSide(
                    color:
                    AppColors.divider,
                  ),
                ),
                focusedBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    12,
                  ),
                  borderSide:
                  const BorderSide(
                    color: AppColors
                        .primaryGreen,
                    width: 1.5,
                  ),
                ),
              ),
              style: AppTheme.body(
                size: 12,
                color:
                AppColors.textDark,
              ),
            ),

            const SizedBox(height: 15),

            _fieldLabel(
              'Note (optional)',
            ),

            TextField(
              controller:
              _noteController,
              maxLines: 3,
              decoration:
              InputDecoration(
                hintText:
                'Why was this outstanding amount added?',
                filled: true,
                fillColor:
                Colors.white,
                contentPadding:
                const EdgeInsets.all(
                  14,
                ),
                border:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    12,
                  ),
                  borderSide:
                  const BorderSide(
                    color:
                    AppColors.divider,
                  ),
                ),
                enabledBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    12,
                  ),
                  borderSide:
                  const BorderSide(
                    color:
                    AppColors.divider,
                  ),
                ),
                focusedBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    12,
                  ),
                  borderSide:
                  const BorderSide(
                    color: AppColors
                        .primaryGreen,
                    width: 1.5,
                  ),
                ),
              ),
              style: AppTheme.body(
                size: 12,
                color:
                AppColors.textDark,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                _saving ? null : _save,
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors
                      .primaryGreen,
                  foregroundColor:
                  Colors.white,
                  padding:
                  const EdgeInsets
                      .symmetric(
                    vertical: 14,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius
                        .circular(
                      12,
                    ),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child:
                  CircularProgressIndicator(
                    color:
                    Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'Add Outstanding',
                  style:
                  TextStyle(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
      String label,
      String value, {
        bool bold = false,
      }) {
    return Row(
      mainAxisAlignment:
      MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: bold
                ? AppTheme.heading(
              size: 13,
            )
                : AppTheme.body(
              size: 10,
              color:
              AppColors.textGrey,
            ),
          ),
        ),
        Text(
          value,
          style: bold
              ? AppTheme.heading(
            size: 16,
            color:
            AppColors.primaryGreen,
          )
              : AppTheme.body(
            size: 11,
            color:
            AppColors.textDark,
            weight:
            FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(
      String text,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 6,
      ),
      child: Text(
        text,
        style: AppTheme.body(
          size: 10,
          color:
          AppColors.textDark,
          weight:
          FontWeight.w600,
        ),
      ),
    );
  }
}