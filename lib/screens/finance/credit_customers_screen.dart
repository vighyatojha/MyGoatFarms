import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/customer_credit.dart';
import '../../services/firestore_service.dart';
import '../../services/sales_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/finance/payment_reminder_service.dart';
import 'credit_customer_detail_screen.dart';

/// Customers on Credit — every customer whose payment for a goat sale is
/// still pending, with what they owe.
///
/// A sale lands here when the customer did not pay the whole amount (sold
/// on credit, or simply short-paid): the unpaid part is the customer's
/// outstanding balance. Nothing is stored for this list — it is worked out
/// live from the sales ([SalesService.creditCustomersStream]), the same
/// figures Finance's Receivables total uses — so receiving a payment takes
/// the customer's balance down here straight away, and a customer who has
/// paid everything drops off the list.
///
/// Palai boarding customers' own outstanding (monthly bills etc.) stays in
/// the Customer Ledger; this list is for goat-sale balances.
class CreditCustomersScreen extends StatefulWidget {
  final String farmId;

  const CreditCustomersScreen({super.key, required this.farmId});

  @override
  State<CreditCustomersScreen> createState() =>
      _CreditCustomersScreenState();
}

class _CreditCustomersScreenState extends State<CreditCustomersScreen> {
  late final Stream<List<CustomerCredit>> _stream;

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  // Used in the WhatsApp reminder text ("...reminder from <farm name>").
  String _farmName = '';

  @override
  void initState() {
    super.initState();

    // Created once, so typing in the search box doesn't restart the
    // Firestore listener.
    _stream = SalesService.instance.creditCustomersStream(widget.farmId);
    _loadFarmName();
  }

  Future<void> _loadFarmName() async {
    final farm = await FirestoreService.instance.getFarmById(widget.farmId);
    if (!mounted) return;
    setState(() => _farmName = farm?.farmName ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Opens the WhatsApp reminder sheet for [targets], keeping only
  /// customers who actually still owe money.
  void _openReminders(List<CustomerCredit> targets) {
    final owing = targets
        .where((c) => c.totalDue > 0)
        .map(ReminderRecipient.fromCustomerCredit)
        .toList();
    showPaymentReminderSheet(
      context,
      customers: owing,
      farmName: _farmName,
    );
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  List<CustomerCredit> _filter(List<CustomerCredit> credits) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) return credits;

    return credits.where((credit) {
      return credit.name.toLowerCase().contains(query) ||
          credit.mobile.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text(
          'Customers on Credit',
          style: AppTheme.heading(size: 18),
        ),
        actions: [
          StreamBuilder<List<CustomerCredit>>(
            stream: _stream,
            builder: (context, snapshot) {
              final all = snapshot.data ?? const <CustomerCredit>[];
              return TextButton.icon(
                onPressed: all.isEmpty ? null : () => _openReminders(all),
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text(
                  'Send Reminder',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.darkGreen),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<CustomerCredit>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _message(
                icon: Icons.error_outline,
                color: AppColors.error,
                text: 'Could not load customers on credit.\n'
                    '${FirestoreService.instance.describeError(snapshot.error!)}',
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              );
            }

            final all = snapshot.data!;

            if (all.isEmpty) {
              return _message(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                text: 'No pending payments.\n'
                    'Every goat sale has been paid in full.',
              );
            }

            final credits = _filter(all);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _summary(all),
                const SizedBox(height: 12),
                _searchField(),
                const SizedBox(height: 12),
                if (credits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Center(
                      child: Text(
                        'No customers found.',
                        style: AppTheme.body(size: 13),
                      ),
                    ),
                  )
                else
                  for (final credit in credits) _customerCard(credit),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(List<CustomerCredit> all) {
    final total = CustomerCredit.totalOf(all);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total pending from customers',
                  style: AppTheme.body(size: 11, color: AppColors.textGrey),
                ),
                const SizedBox(height: 2),
                Text(
                  _currency(total),
                  style: AppTheme.heading(size: 20, color: AppColors.error),
                ),
              ],
            ),
          ),
          Text(
            '${all.length} customer${all.length == 1 ? '' : 's'}',
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _search = value),
      style: AppTheme.body(size: 13),
      decoration: InputDecoration(
        hintText: 'Search name or mobile number...',
        prefixIcon: const Icon(
          Icons.search,
          size: 20,
          color: AppColors.textGrey,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }

  Widget _customerCard(CustomerCredit credit) {
    final since = credit.oldestSaleDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              fastRoute(
                CreditCustomerDetailScreen(
                  farmId: widget.farmId,
                  creditKey: credit.key,
                  customerName: credit.name,
                ),
              ),
            );
          },
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(radius: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.lightGreen,
                  child: Text(
                    credit.name.isNotEmpty
                        ? credit.name[0].toUpperCase()
                        : '?',
                    style: AppTheme.body(
                      size: 15,
                      color: AppColors.darkGreen,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        credit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 13,
                          color: AppColors.textDark,
                          weight: FontWeight.w700,
                        ),
                      ),
                      if (credit.mobile.trim().isNotEmpty)
                        Text(
                          credit.mobile,
                          style: AppTheme.body(
                            size: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${credit.saleCount} sale'
                            '${credit.saleCount == 1 ? '' : 's'}'
                            '${since == null ? '' : ' · sold ${DateFormat('dd MMM yyyy').format(since)}'}',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (credit.totalDue > 0 && credit.mobile.trim().isNotEmpty)
                  IconButton(
                    tooltip: 'Send WhatsApp reminder',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openReminders([credit]),
                    icon: const Icon(
                      Icons.chat,
                      size: 20,
                      color: Color(0xFF25D366),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currency(credit.totalDue),
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.error,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      credit.hasCreditSale ? 'On credit' : 'Balance due',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textGrey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}