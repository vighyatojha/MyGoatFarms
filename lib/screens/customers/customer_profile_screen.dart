import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'customer_goats_progress_report_pdf_screen.dart';
import 'monthly_bills_screen.dart';
import 'customer_goats_report_screen.dart';
import '../../models/monthly_bill_model.dart';
import '../../services/monthly_billing_service.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../palai/add_customer_screen.dart';
import '../palai/customer_palai/customer_goat_registration_screen.dart';
import '../palai/multi_goat_checkout_screen.dart';

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

class _CustomerProfileScreenState
    extends State<CustomerProfileScreen> {
  late PalaiCustomer _customer;

  bool _loadingCustomer = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  // ================================================================
  // CHECK OUT GOAT(S)
  // ================================================================

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

  // ================================================================
  // REFRESH CUSTOMER
  // ================================================================

  Future<void> _refreshCustomer() async {
    if (_loadingCustomer) return;

    setState(() {
      _loadingCustomer = true;
    });

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

  // ================================================================
  // EDIT CUSTOMER
  // ================================================================

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

  // ================================================================
  // CHECK IN GOAT
  // ================================================================

  Future<void> _openRegisterGoat() async {
    final goat = await Navigator.of(context).push<PalaiGoat>(
      fastRoute(
        CustomerGoatRegistrationScreen(
          customerId: _customer.id,
        ),
      ),
    );

    if (!mounted || goat == null) {
      return;
    }

    await _refreshCustomer();
  }

  // ================================================================
// MONTHLY BILLS
// ================================================================

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
              builder: (context) {
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

  // ================================================================
  // ADD PAYMENT
  // ================================================================

  Future<void> _openAddPayment() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
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

  // ================================================================
  // ADD OUTSTANDING
  // ================================================================

  Future<void> _openAddOutstanding() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
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

  // ================================================================
  // PAYMENT HISTORY STREAM
  // ================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _paymentHistoryStream() {
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

  // ================================================================
  // GOAT HEALTH COLOR
  // ================================================================

  Color _healthColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;

      case 'Under Observation':
        return AppColors.warning;

      default:
        return AppColors.success;
    }
  }

  // ================================================================
  // BOARDED FOR
  // ================================================================

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

  // ================================================================
  // DATE FORMAT
  // ================================================================

  String _formatDate(dynamic value) {
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

  // ================================================================
  // RUPEES
  // ================================================================

  String _rupees(dynamic value) {
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

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final outstanding = _customer.pendingAmount;
    final advance = _customer.advanceAmount;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      // ============================================================
      // APP BAR
      // ============================================================

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 0,

        title: Text(
          _customer.name,
          style: AppTheme.heading(
            size: 17,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Edit customer',
            icon: const Icon(
              Icons.edit_outlined,
            ),
            onPressed: _openEdit,
          ),
        ],
      ),

      // ============================================================
      // BODY
      // ============================================================

      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _refreshCustomer,

        child: StreamBuilder<List<PalaiGoat>>(
          stream: FirestoreService.instance.goatsForCustomerStream(
            widget.farmId,
            _customer.id,
          ),

          builder: (context, goatSnapshot) {
            final goats = goatSnapshot.data ?? [];

            final activeGoats = goats
                .where(
                  (goat) => !goat.isCheckedOut,
            )
                .length;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),

              padding: const EdgeInsets.fromLTRB(
                20,
                8,
                20,
                32,
              ),

              children: [
                // ==================================================
                // 1. CUSTOMER INFORMATION
                // ==================================================

                FadeInDown(
                  duration: const Duration(
                    milliseconds: 180,
                  ),
                  child: _buildCustomerInformationSection(),
                ),

                const SizedBox(height: 24),

                // ==================================================
                // 2. PAYMENT INFORMATION
                // ==================================================

                _buildSectionHeader(
                  title: 'Payment Information',
                  icon: Icons.account_balance_wallet_outlined,
                ),

                const SizedBox(height: 12),

                _buildFinancialSummary(
                  outstanding,
                  advance,
                ),

                const SizedBox(height: 14),

                _buildFinancialActions(),

                const SizedBox(height: 20),

                _buildMonthlyBillingButton(),

                const SizedBox(height: 20),

                _buildGoatsReportButton(),

                const SizedBox(height: 20),

                _buildPaymentHistory(),

                const SizedBox(height: 26),

                // ==================================================
                // 3. CHECK OUT GOAT(S)
                // ==================================================

                _buildCheckoutButton(),

                const SizedBox(height: 28),

                // ==================================================
                // 4. GOATS
                // ==================================================

                _buildSectionHeader(
                  title: 'Goats',
                  icon: Icons.pets,
                ),

                const SizedBox(height: 12),

                if (!goatSnapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.only(
                      top: 30,
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  )
                else if (goats.isEmpty)
                  _emptyGoatsState()
                else ...[
                    _buildGoatStats(
                      goats.length,
                      activeGoats,
                    ),

                    const SizedBox(height: 12),

                    ...goats.asMap().entries.map(
                          (entry) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: 10,
                          ),
                          child: FadeInUp(
                            delay: Duration(
                              milliseconds: 20 *
                                  entry.key.clamp(
                                    0,
                                    8,
                                  ),
                            ),
                            duration: const Duration(
                              milliseconds: 200,
                            ),
                            child: _goatHistoryCard(
                              entry.value,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ================================================================
// MONTHLY BILLING BUTTON
// ================================================================

  Widget _buildMonthlyBillingButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        onTap: _openMonthlyBills,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primaryGreen,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Bills',
                      style: AppTheme.heading(
                        size: 14,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Generate and manage monthly bills',
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoatsReportButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        onTap: _openGoatsReport,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pets_outlined,
                  color: AppColors.primaryGreen,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Goats Report',
                      style: AppTheme.heading(
                        size: 14,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Generate one report for all goats at once',
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // SECTION HEADER
  // ================================================================

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: AppColors.lightGreen,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.primaryGreen,
          ),
        ),

        const SizedBox(width: 10),

        Text(
          title,
          style: AppTheme.heading(
            size: 17,
          ),
        ),
      ],
    );
  }

  // ================================================================
  // CHECKOUT BUTTON
  // ================================================================

  Widget _buildCheckoutButton() {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(
              0,
              5,
            ),
          ),
        ],
      ),

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
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(54),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // CUSTOMER INFORMATION
  // ================================================================

  Widget _buildCustomerInformationSection() {
    return Container(
      width: double.infinity,

      decoration: AppTheme.card(
        radius: 16,
      ),

      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,

                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),

                alignment: Alignment.center,

                child: Text(
                  _customer.name.isNotEmpty
                      ? _customer.name[0].toUpperCase()
                      : '?',

                  style: AppTheme.heading(
                    size: 20,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      _customer.name,
                      style: AppTheme.heading(
                        size: 16,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      _customer.mobileNumber,
                      style: AppTheme.body(
                        size: 12,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),

                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),

                child: Text(
                  _customer.package,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          if (_customer.address.isNotEmpty) ...[
            const Divider(
              height: 26,
            ),

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 17,
                  color: AppColors.textGrey,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    _customer.address,
                    style: AppTheme.body(
                      size: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const Divider(
            height: 26,
          ),

          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: AppColors.textGrey,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  'Joined ${DateFormat('dd MMM yyyy').format(_customer.joiningDate)}',
                  style: AppTheme.body(
                    size: 11,
                  ),
                ),
              ),

              if (_loadingCustomer)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryGreen,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================================
  // FINANCIAL SUMMARY
  // ================================================================

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

            const SizedBox(width: 12),

            Expanded(
              child: _financialCard(
                icon:
                Icons.account_balance_wallet_outlined,
                label: 'Advance',
                value: _rupees(advance),
                color: AppColors.success,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Container(
          width: double.infinity,

          decoration: AppTheme.card(
            radius: 14,
          ),

          padding: const EdgeInsets.all(15),

          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.account_balance_outlined,
                  color: AppColors.primaryGreen,
                  size: 21,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      'Current Balance',
                      style: AppTheme.body(
                        size: 11,
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
                        size: 13,
                        color: outstanding > 0
                            ? AppColors.error
                            : AppColors.darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================
  // FINANCIAL CARD
  // ================================================================

  Widget _financialCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      decoration: AppTheme.card(
        radius: 14,
      ),

      padding: const EdgeInsets.all(14),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

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

          const SizedBox(height: 9),

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
              size: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // FINANCIAL ACTIONS
  // ================================================================

  Widget _buildFinancialActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _openAddPayment,

            icon: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 19,
            ),

            label: const Text(
              'Add Payment',
            ),

            style: ElevatedButton.styleFrom(
              backgroundColor:
              AppColors.primaryGreen,
              foregroundColor: Colors.white,

              padding: const EdgeInsets.symmetric(
                vertical: 14,
              ),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openAddOutstanding,

            icon: const Icon(
              Icons.add_card_outlined,
              size: 19,
            ),

            label: const Text(
              'Add Outstanding',
            ),

            style: OutlinedButton.styleFrom(
              foregroundColor:
              AppColors.darkGreen,

              side: const BorderSide(
                color: AppColors.primaryGreen,
                width: 1.2,
              ),

              padding: const EdgeInsets.symmetric(
                vertical: 14,
              ),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ================================================================
  // PAYMENT HISTORY
  // ================================================================

  Widget _buildPaymentHistory() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Payment History',
                style: AppTheme.heading(
                  size: 15,
                ),
              ),
            ),

            Text(
              'All payments',
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: _paymentHistoryStream(),

          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _paymentErrorCard(
                snapshot.error.toString(),
              );
            }

            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.all(25),

                decoration: AppTheme.card(
                  radius: 14,
                ),

                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return _emptyPaymentHistory();
            }

            final sorted = [...docs];

            sorted.sort(
                  (a, b) {
                final aDate =
                _timestampToDate(
                  a.data()['date'],
                );

                final bDate =
                _timestampToDate(
                  b.data()['date'],
                );

                return bDate.compareTo(
                  aDate,
                );
              },
            );

            return Column(
              children: sorted.take(20).map(
                    (doc) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 9,
                    ),
                    child: _paymentCard(
                      doc,
                    ),
                  );
                },
              ).toList(),
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

  // ================================================================
  // PAYMENT CARD
  // ================================================================

  Widget _paymentCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();

    final amount = data['amount'] ?? 0;

    final method =
    (data['paymentMethod'] ?? 'Unknown').toString();

    final paymentNumber =
    (data['paymentNumber'] ?? '').toString();

    final note =
    (data['note'] ?? '').toString();

    // The amount actually still owed by the customer AFTER this payment
    // was recorded. Previously this line used `amountAppliedToPending` /
    // `amountAppliedToBill` — how much of THIS payment went toward the
    // balance, which is usually equal to the amount paid — so the red
    // "Pending ₹X" line was showing the paid amount instead of the real
    // remaining balance.
    final pendingAfter =
        data['pendingAfter'] ?? 0;

    final advance =
        data['advanceAmount'] ?? 0;

    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(14),

        onTap: () {
          _showPaymentDetails(data);
        },

        child: Container(
          decoration: AppTheme.card(
            radius: 14,
          ),

          padding: const EdgeInsets.all(13),

          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(
                    0.12,
                  ),
                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.payments_outlined,
                  color: AppColors.success,
                  size: 20,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      _rupees(amount),
                      style: AppTheme.heading(
                        size: 14,
                        color: AppColors.success,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      method,
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textDark,
                      ),
                    ),

                    if (paymentNumber.isNotEmpty)
                      Text(
                        paymentNumber,
                        style: AppTheme.body(
                          size: 9,
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
                          overflow:
                          TextOverflow.ellipsis,
                          style: AppTheme.body(
                            size: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Column(
                crossAxisAlignment:
                CrossAxisAlignment.end,

                children: [
                  Text(
                    _formatDate(data['date']),
                    style: AppTheme.body(
                      size: 9,
                    ),
                  ),

                  if ((pendingAfter is num && pendingAfter > 0) ||
                      (advance is num && advance > 0)) ...[
                    const SizedBox(height: 4),

                    if (pendingAfter is num && pendingAfter > 0)
                      Text(
                        'Pending ${_rupees(pendingAfter)}',
                        style: AppTheme.body(
                          size: 9,
                          color: AppColors.error,
                          weight: FontWeight.w600,
                        ),
                      ),

                    if (advance is num && advance > 0)
                      Text(
                        'Advance ${_rupees(advance)}',
                        style: AppTheme.body(
                          size: 9,
                          color: AppColors.darkGreen,
                          weight: FontWeight.w600,
                        ),
                      ),
                  ],
                ],
              ),

              const SizedBox(width: 4),

              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // EMPTY PAYMENT HISTORY
  // ================================================================

  Widget _emptyPaymentHistory() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(
        vertical: 28,
        horizontal: 20,
      ),

      decoration: AppTheme.card(
        radius: 14,
      ),

      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,

            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.payments_outlined,
              color: AppColors.primaryGreen,
              size: 24,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'No payments yet',
            style: AppTheme.heading(
              size: 13,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'Payments received from this customer will appear here.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // PAYMENT ERROR
  // ================================================================

  Widget _paymentErrorCard(String error) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: AppTheme.card(
        radius: 14,
      ),

      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 28,
          ),

          const SizedBox(height: 8),

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
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // PAYMENT DETAILS
  // ================================================================

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

    final pendingBefore =
        data['pendingBefore'] ?? 0;

    final applied =
        data['amountAppliedToPending'] ??
            data['amountAppliedToBill'] ??
            0;

    final pendingAfter =
        data['pendingAfter'] ?? 0;

    final advanceBefore =
        data['advanceBefore'] ?? 0;

    final advanceAdded =
        data['advanceAmount'] ?? 0;

    final advanceAfter =
        data['advanceAfter'] ?? 0;

    showModalBottomSheet<void>(
      context: context,

      backgroundColor: Colors.transparent,

      isScrollControlled: true,

      useSafeArea: true,

      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            25,
          ),

          decoration: const BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,

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

              const SizedBox(height: 18),

              Text(
                'Payment Details',
                style: AppTheme.heading(
                  size: 18,
                ),
              ),

              const SizedBox(height: 18),

              _detailRow(
                'Payment Number',
                paymentNumber.isEmpty
                    ? '—'
                    : paymentNumber,
              ),

              _detailRow(
                'Amount Received',
                _rupees(amount),
              ),

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
                'Applied to Pending',
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
                'Advance Added',
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

                const SizedBox(height: 4),

                Text(
                  note,
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textDark,
                  ),
                ),
              ],

              const SizedBox(height: 18),

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
                      vertical: 14,
                    ),

                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(12),
                    ),
                  ),

                  child: const Text(
                    'Close',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================================================================
  // DETAIL ROW
  // ================================================================

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
                size: 11,
                color: AppColors.textGrey,
              ),
            ),
          ),

          const SizedBox(width: 15),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.heading(
                size: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // GOAT STATS
  // ================================================================

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

        const SizedBox(width: 12),

        Expanded(
          child: _statCard(
            icon: Icons.login,
            label: 'Currently Boarded',
            value: '$active',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  // ================================================================
  // STAT CARD
  // ================================================================

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      decoration: AppTheme.card(
        radius: 14,
      ),

      padding: const EdgeInsets.all(14),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Container(
            width: 32,
            height: 32,

            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),

            child: Icon(
              icon,
              size: 16,
              color: color,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            value,
            style: AppTheme.heading(
              size: 18,
            ),
          ),

          Text(
            label,
            style: AppTheme.body(
              size: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // GOAT CARD
  // ================================================================

  Widget _goatHistoryCard(
      PalaiGoat goat,
      ) {
    final healthColor =
    _healthColor(goat.healthStatus);

    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        onTap: null,

        child: Container(
          decoration: AppTheme.card(
            radius: 16,
          ),

          padding: const EdgeInsets.all(12),

          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,

                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.lightGreen,

                  border: Border.all(
                    color: healthColor.withOpacity(
                      0.6,
                    ),
                    width: 2.5,
                  ),
                ),

                child: ClipOval(
                  child: goat.beforeImage != null
                      ? Image.memory(
                    goat.beforeImage!,
                    fit: BoxFit.cover,
                  )
                      : const Icon(
                    Icons.pets,
                    color:
                    AppColors.primaryGreen,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      goat.goatCode,
                      style: AppTheme.heading(
                        size: 13,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      '${goat.breed} · ${goat.gender}',
                      style: AppTheme.body(
                        size: 11,
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

                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),

                decoration: BoxDecoration(
                  color: goat.isCheckedOut
                      ? AppColors.lightGreen
                      : healthColor.withOpacity(0.12),

                  borderRadius:
                  BorderRadius.circular(8),
                ),

                child: Text(
                  goat.isCheckedOut
                      ? 'Checked Out'
                      : goat.healthStatus,

                  style: AppTheme.body(
                    size: 9,
                    color: goat.isCheckedOut
                        ? AppColors.darkGreen
                        : healthColor,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // EMPTY GOATS
  // ================================================================

  Widget _emptyGoatsState() {
    return Padding(
      padding: const EdgeInsets.only(
        top: 25,
      ),

      child: Column(
        children: [
          Container(
            width: 75,
            height: 75,

            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.pets,
              size: 32,
              color: AppColors.primaryGreen,
            ),
          ),

          const SizedBox(height: 12),

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
              size: 11,
            ),
          ),

          const SizedBox(height: 14),

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
              foregroundColor:
              AppColors.darkGreen,

              side: const BorderSide(
                color: AppColors.primaryGreen,
              ),

              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// ADD PAYMENT SHEET
// ====================================================================

// ====================================================================
// ADD PAYMENT SHEET
// ====================================================================

class _AddPaymentSheet extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;

  /// Null:
  ///   Normal customer payment.
  ///
  /// Non-null:
  ///   Payment is specifically being made against this Monthly Bill.
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

  // ================================================================
  // AMOUNT
  // ================================================================

  double get _amount {
    return double.tryParse(
      _amountController.text.trim(),
    ) ??
        0;
  }

  /// If this payment was opened from Monthly Bills,
  /// the maximum amount applied to that bill is the bill's
  /// remaining amount.
  ///
  /// Otherwise it is the customer's pending amount.
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

  double get _pendingAfter {
    return (widget.customer.pendingAmount -
        _applied)
        .clamp(
      0,
      double.infinity,
    )
        .toDouble();
  }

  double get _advanceAfter {
    return widget.customer.advanceAmount +
        _advanceAdded;
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _noteController.dispose();

    super.dispose();
  }

  // ================================================================
  // SAVE PAYMENT
  // ================================================================

  Future<void> _save() async {
    // --------------------------------------------------------------
    // VALIDATION
    // --------------------------------------------------------------

    if (_amount <= 0) {
      _error(
        'Enter a payment amount greater than ₹0.',
      );
      return;
    }

    if (_paymentLimit <= 0) {
      if (widget.bill != null) {
        _error(
          'This monthly bill has no remaining amount.',
        );
      } else {
        _error(
          'This customer has no outstanding amount.',
        );
      }

      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      // ============================================================
      // MONTHLY BILL PAYMENT
      // ============================================================

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

        // ----------------------------------------------------------
        // MONTHLY BILL SUCCESS DIALOG
        // ----------------------------------------------------------

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

                  const SizedBox(height: 14),

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
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'Done',
                  ),
                ),
              ],
            );
          },
        );

        if (!mounted) return;

        // ----------------------------------------------------------
        // TRUE = PAYMENT SUCCESSFUL
        // ----------------------------------------------------------

        Navigator.pop(
          context,
          true,
        );

        return;
      }

      // ============================================================
      // NORMAL CUSTOMER PAYMENT
      // ============================================================

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

      // ------------------------------------------------------------
      // NORMAL PAYMENT SUCCESS DIALOG
      // ------------------------------------------------------------

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

                const SizedBox(height: 14),

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
                  Navigator.pop(dialogContext);
                },
                child: const Text(
                  'Done',
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      // ------------------------------------------------------------
      // TRUE = NORMAL PAYMENT SUCCESSFUL
      // ------------------------------------------------------------

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

  // ================================================================
  // BUILD NOTE
  // ================================================================

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

  // ================================================================
  // ERROR
  // ================================================================

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================

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
            // --------------------------------------------------------
            // HANDLE
            // --------------------------------------------------------

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

            const SizedBox(height: 20),

            // --------------------------------------------------------
            // TITLE
            // --------------------------------------------------------

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
                size: 12,
              ),
            ),

            // --------------------------------------------------------
            // MONTHLY BILL INFORMATION
            // --------------------------------------------------------

            if (widget.bill != null) ...[
              const SizedBox(height: 8),

              Container(
                width: double.infinity,

                padding:
                const EdgeInsets.all(12),

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
                        color:
                        AppColors.darkGreen,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      DateFormat('MMMM yyyy')
                          .format(
                        widget.bill!.billingMonth,
                      ),
                      style: AppTheme.body(
                        size: 11,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Text(
                      'Bill Remaining: '
                          '₹${widget.bill!.remainingAmount.toStringAsFixed(0)}',
                      style: AppTheme.heading(
                        size: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // --------------------------------------------------------
            // BALANCE PREVIEW
            // --------------------------------------------------------

            _balancePreview(),

            const SizedBox(height: 20),

            // --------------------------------------------------------
            // PAYMENT AMOUNT
            // --------------------------------------------------------

            _fieldLabel(
              'Payment Amount',
            ),

            _outlinedField(
              controller:
              _amountController,

              hint: widget.bill != null
                  ? 'Maximum ₹${widget.bill!.remainingAmount.toStringAsFixed(0)}'
                  : 'Enter amount',

              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),

              prefix: const Text(
                '₹ ',
              ),

              onChanged: (_) {
                setState(() {});
              },
            ),

            const SizedBox(height: 17),

            // --------------------------------------------------------
            // PAYMENT METHOD
            // --------------------------------------------------------

            _fieldLabel(
              'Payment Method',
            ),

            _paymentMethodField(),

            const SizedBox(height: 17),

            // --------------------------------------------------------
            // REFERENCE
            // --------------------------------------------------------

            _fieldLabel(
              'Reference Number (optional)',
            ),

            _outlinedField(
              controller:
              _referenceController,

              hint:
              'UPI / transaction / cheque number',
            ),

            const SizedBox(height: 17),

            // --------------------------------------------------------
            // NOTE
            // --------------------------------------------------------

            _fieldLabel(
              'Note (optional)',
            ),

            _outlinedField(
              controller:
              _noteController,

              hint: 'Add a note',

              maxLines: 3,
            ),

            const SizedBox(height: 22),

            // --------------------------------------------------------
            // RECEIVE PAYMENT BUTTON
            // --------------------------------------------------------

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed:
                _saving ? null : _save,

                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,

                  foregroundColor:
                  Colors.white,

                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 15,
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
                    FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // BALANCE PREVIEW
  // ================================================================

  Widget _balancePreview() {
    final outstanding =
        widget.customer.pendingAmount;

    final advance =
        widget.customer.advanceAmount;

    return Container(
      padding: const EdgeInsets.all(14),

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
                    size: 10,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  '₹${_paymentLimit.toStringAsFixed(0)}',

                  style: AppTheme.heading(
                    size: 16,

                    color:
                    _paymentLimit > 0
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
                    size: 10,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  '₹${outstanding.toStringAsFixed(0)}',

                  style: AppTheme.heading(
                    size: 16,

                    color:
                    outstanding > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  'Advance ₹${advance.toStringAsFixed(0)}',

                  style: AppTheme.body(
                    size: 9,

                    color:
                    AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // PAYMENT METHOD
  // ================================================================

  Widget _paymentMethodField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(12),

        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
      ),

      padding:
      const EdgeInsets.symmetric(
        horizontal: 14,
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
              child: Text(
                'Bank Transfer',
              ),
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
            if (value == null) {
              return;
            }

            setState(() {
              _paymentMethod =
                  value;
            });
          },
        ),
      ),
    );
  }

  // ================================================================
  // TEXT FIELD
  // ================================================================

  Widget _outlinedField({
    required TextEditingController
    controller,

    String? hint,

    Widget? prefix,

    TextInputType? keyboardType,

    int maxLines = 1,

    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,

      keyboardType:
      keyboardType,

      maxLines: maxLines,

      onChanged: onChanged,

      decoration:
      InputDecoration(
        hintText: hint,

        prefix: prefix,

        filled: true,

        fillColor:
        Colors.white,

        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),

        border:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),

          borderSide:
          const BorderSide(
            color:
            AppColors.divider,
            width: 1,
          ),
        ),

        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),

          borderSide:
          const BorderSide(
            color:
            AppColors.divider,
            width: 1,
          ),
        ),

        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),

          borderSide:
          const BorderSide(
            color:
            AppColors.primaryGreen,
            width: 1.5,
          ),
        ),
      ),

      style: AppTheme.body(
        size: 13,
        color:
        AppColors.textDark,
      ),
    );
  }

  // ================================================================
  // FIELD LABEL
  // ================================================================

  Widget _fieldLabel(
      String text,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 7,
      ),

      child: Text(
        text,

        style: AppTheme.body(
          size: 11,
          color:
          AppColors.textDark,
          weight:
          FontWeight.w600,
        ),
      ),
    );
  }

  // ================================================================
  // RESULT ROW
  // ================================================================

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
        mainAxisAlignment:
        MainAxisAlignment.spaceBetween,

        children: [
          Expanded(
            child: Text(
              label,

              style:
              AppTheme.body(
                size: 11,
              ),
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Flexible(
            child: Text(
              value,

              textAlign:
              TextAlign.end,

              style:
              AppTheme.heading(
                size: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// ADD OUTSTANDING SHEET
// ====================================================================

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
  final _amountController =
  TextEditingController();

  final _noteController =
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
      final db = FirebaseFirestore.instance;

      final customerRef = db
          .collection('farms')
          .doc(widget.farmId)
          .collection('palaiCustomers')
          .doc(widget.customer.id);

      final billRef = db
          .collection('farms')
          .doc(widget.farmId)
          .collection('bills')
          .doc();

      final activityRef = db
          .collection('farms')
          .doc(widget.farmId)
          .collection('activities')
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

          // New outstanding is first netted against any
          // existing advance the customer is holding.
          final advanceUsed =
          _amount
              .clamp(0, oldAdvance)
              .toDouble();

          final remainingOutstanding =
              _amount - advanceUsed;

          final newAdvance =
              oldAdvance - advanceUsed;

          final newPending =
              oldPending + remainingOutstanding;

          transaction.update(
            customerRef,
            {
              'pendingAmount': newPending,
              'advanceAmount': newAdvance,
              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );

          transaction.set(
            billRef,
            {
              'billNumber': billNumber,
              'type': 'opening_balance',
              'customerId': widget.customer.id,
              'customerName': widget.customer.name,
              'description':
              'Outstanding amount added',
              'newCharges': _amount,
              'previousPending': oldPending,
              'advanceBefore': oldAdvance,
              'advanceUsed': advanceUsed,
              'totalDue': newPending,
              'amountPaid': 0,
              'pendingAfter': newPending,
              'advanceAfter': newAdvance,
              'note':
              _noteController.text.trim(),
              'status': 'pending',
              'createdAt':
              FieldValue.serverTimestamp(),
              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );

          transaction.set(
            activityRef,
            {
              'type': 'paymentReceived',
              'title': 'Outstanding Added',
              'subtitle':
              '${widget.customer.name} · ₹${_amount.toStringAsFixed(0)}',
              'module': 'palai',
              'timestamp':
              FieldValue.serverTimestamp(),
            },
          );
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '₹${_amount.toStringAsFixed(0)} outstanding added.',
          ),
          backgroundColor:
          AppColors.primaryGreen,
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
        FirestoreService.instance.describeError(e),
      );
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        widget.customer.pendingAmount;

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

            const SizedBox(height: 20),

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
                size: 12,
              ),
            ),

            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius:
                BorderRadius.circular(14),
              ),

              child: Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

                children: [
                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    children: [
                      Text(
                        'Current Outstanding',
                        style: AppTheme.body(
                          size: 10,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '₹${current.toStringAsFixed(0)}',
                        style: AppTheme.heading(
                          size: 16,
                          color: current > 0
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),

                  const Icon(
                    Icons.arrow_forward_outlined,
                    color: AppColors.textGrey,
                    size: 20,
                  ),

                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.end,

                    children: [
                      Text(
                        'After Addition',
                        style: AppTheme.body(
                          size: 10,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '₹${(current + _amount).toStringAsFixed(0)}',
                        style: AppTheme.heading(
                          size: 16,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Outstanding Amount',
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 7),

            TextField(
              controller: _amountController,

              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),

              onChanged: (_) =>
                  setState(() {}),

              decoration: InputDecoration(
                hintText: 'Enter amount',
                prefixText: '₹ ',

                filled: true,
                fillColor: Colors.white,

                contentPadding:
                const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(12),

                  borderSide:
                  const BorderSide(
                    color: AppColors.divider,
                  ),
                ),

                enabledBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(12),

                  borderSide:
                  const BorderSide(
                    color: AppColors.divider,
                  ),
                ),

                focusedBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(12),

                  borderSide:
                  const BorderSide(
                    color: AppColors.primaryGreen,
                    width: 1.5,
                  ),
                ),
              ),

              style: AppTheme.body(
                size: 13,
                color: AppColors.textDark,
              ),
            ),

            const SizedBox(height: 17),

            Text(
              'Note (optional)',
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 7),

            TextField(
              controller: _noteController,

              maxLines: 3,

              decoration: InputDecoration(
                hintText:
                'Why was this outstanding amount added?',

                filled: true,
                fillColor: Colors.white,

                contentPadding:
                const EdgeInsets.all(14),

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(12),

                  borderSide:
                  const BorderSide(
                    color: AppColors.divider,
                  ),
                ),

                enabledBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(12),

                  borderSide:
                  const BorderSide(
                    color: AppColors.divider,
                  ),
                ),

                focusedBorder:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(12),

                  borderSide:
                  const BorderSide(
                    color: AppColors.primaryGreen,
                    width: 1.5,
                  ),
                ),
              ),

              style: AppTheme.body(
                size: 12,
                color: AppColors.textDark,
              ),
            ),

            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed:
                _saving ? null : _save,

                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,
                  foregroundColor: Colors.white,

                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 15,
                  ),

                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),

                child: _saving
                    ? const SizedBox(
                  height: 20,
                  width: 20,

                  child:
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'Add Outstanding',
                  style: TextStyle(
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}