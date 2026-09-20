import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/customer_credit.dart';
import '../screens/finance/credit_customer_detail_screen.dart';
import '../screens/finance/credit_customers_screen.dart';
import '../services/sales_service.dart';
import 'fast_route.dart';

String _money(num value) {
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  ).format(value);
}

/// "Goat sales on credit — ₹X pending from N customers". Tapping it opens
/// [CreditCustomersScreen], the list of every customer whose payment is
/// pending.
///
/// Shows nothing while there is nothing pending (or while loading, or if
/// the read fails), so it never puts an empty or broken box on a screen it
/// is added to.
class GoatCreditSummaryCard extends StatefulWidget {
  final String farmId;

  const GoatCreditSummaryCard({super.key, required this.farmId});

  @override
  State<GoatCreditSummaryCard> createState() => _GoatCreditSummaryCardState();
}

class _GoatCreditSummaryCardState extends State<GoatCreditSummaryCard> {
  late Stream<List<CustomerCredit>> _stream;

  @override
  void initState() {
    super.initState();

    _stream = SalesService.instance.creditCustomersStream(widget.farmId);
  }

  @override
  void didUpdateWidget(covariant GoatCreditSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.farmId != widget.farmId) {
      _stream = SalesService.instance.creditCustomersStream(widget.farmId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CustomerCredit>>(
      stream: _stream,
      builder: (context, snapshot) {
        final credits = snapshot.data;

        if (credits == null || credits.isEmpty) {
          return const SizedBox.shrink();
        }

        final total = CustomerCredit.totalOf(credits);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.of(context).push(
                fastRoute(CreditCustomersScreen(farmId: widget.farmId)),
              );
            },
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.error.withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.error,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Goat sales on credit',
                          style: AppTheme.body(
                            size: 12,
                            color: AppColors.textDark,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_money(total)} pending from '
                              '${credits.length} customer'
                              '${credits.length == 1 ? '' : 's'}',
                          style: AppTheme.body(
                            size: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textGrey,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A box for a customer's profile: what this customer still owes on goat
/// sales, with a button to view the unpaid sales and receive a payment.
///
/// The customer is matched by mobile number (or customer id), so a Palai
/// customer who also bought goats on credit sees that balance here, next to
/// their Palai outstanding. Shows nothing if they owe nothing on goat
/// sales.
class GoatCreditProfileCard extends StatefulWidget {
  final String farmId;
  final String customerId;
  final String mobile;
  final String name;

  const GoatCreditProfileCard({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.mobile,
    required this.name,
  });

  @override
  State<GoatCreditProfileCard> createState() => _GoatCreditProfileCardState();
}

class _GoatCreditProfileCardState extends State<GoatCreditProfileCard> {
  late Stream<List<CustomerCredit>> _stream;

  @override
  void initState() {
    super.initState();

    _stream = SalesService.instance.creditCustomersStream(widget.farmId);
  }

  @override
  void didUpdateWidget(covariant GoatCreditProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.farmId != widget.farmId) {
      _stream = SalesService.instance.creditCustomersStream(widget.farmId);
    }
  }

  CustomerCredit? _find(List<CustomerCredit> credits) {
    final key = CustomerCredit.keyFromParts(
      mobile: widget.mobile,
      customerId: widget.customerId,
      name: widget.name,
    );

    for (final credit in credits) {
      if (credit.key == key) return credit;
    }

    // Same customer record, saved under a different mobile format.
    for (final credit in credits) {
      if (credit.customerIds.contains(widget.customerId)) return credit;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CustomerCredit>>(
      stream: _stream,
      builder: (context, snapshot) {
        final credits = snapshot.data;

        if (credits == null) return const SizedBox.shrink();

        final credit = _find(credits);

        if (credit == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.error.withOpacity(0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Goat sale credit',
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.textDark,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _money(credit.totalDue),
                      style: AppTheme.heading(
                        size: 16,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Still owed on ${credit.saleCount} goat sale'
                      '${credit.saleCount == 1 ? '' : 's'}. This is separate '
                      'from the Palai outstanding above.',
                  style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
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
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('View sales & receive payment'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}