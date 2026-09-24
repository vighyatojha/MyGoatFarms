import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/customer_credit.dart';
import '../../models/sale_model.dart';
import '../../services/firestore_service.dart';
import '../../services/sales_service.dart';
import '../../widgets/fast_route.dart';
import '../trading/sale_receipt_screen.dart';

/// One customer's outstanding goat-sale balance: the total they owe and
/// each unpaid sale, with a button to receive a payment on it and one to
/// open its receipt.
///
/// It listens to the same live list as [CreditCustomersScreen] and finds
/// the customer by [creditKey], so recording a payment updates the amounts
/// here straight away, and once the customer has paid everything the
/// screen says so instead of going blank.
class CreditCustomerDetailScreen extends StatefulWidget {
  final String farmId;

  /// [CustomerCredit.key] of the customer to show.
  final String creditKey;

  /// Only used for the title until the customer's details have loaded.
  final String customerName;

  const CreditCustomerDetailScreen({
    super.key,
    required this.farmId,
    required this.creditKey,
    this.customerName = '',
  });

  @override
  State<CreditCustomerDetailScreen> createState() =>
      _CreditCustomerDetailScreenState();
}

class _CreditCustomerDetailScreenState
    extends State<CreditCustomerDetailScreen> {
  late final Stream<List<CustomerCredit>> _stream;

  @override
  void initState() {
    super.initState();

    _stream = SalesService.instance.creditCustomersStream(widget.farmId);
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _deliveryLabel(Sale sale) {
    if (sale.isDeliverNow) return 'Deliver Now';
    if (sale.isBooking) return 'Booking / Holding';
    if (sale.isWaitForDelivery) return 'Wait for Delivery';
    if (sale.isPalaiTransfer) return 'Transfer to Palai';

    return sale.deliveryType;
  }

  Future<void> _receivePayment(Sale sale) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaleReceivePaymentSheet(
        farmId: widget.farmId,
        sale: sale,
      ),
    );

    if (recorded != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment recorded for ${sale.id}.'),
        backgroundColor: AppColors.darkGreen,
      ),
    );
  }

  void _openReceipt(Sale sale) {
    Navigator.of(context).push(
      fastRoute(
        SaleReceiptScreen(
          farmId: widget.farmId,
          saleId: sale.id,
        ),
      ),
    );
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
          widget.customerName.isEmpty
              ? 'Customer Credit'
              : widget.customerName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<CustomerCredit>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _message(
                icon: Icons.error_outline,
                color: AppColors.error,
                text: 'Could not load this customer.\n'
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

            CustomerCredit? credit;

            for (final item in snapshot.data!) {
              if (item.key == widget.creditKey) {
                credit = item;
                break;
              }
            }

            if (credit == null) {
              return _message(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                text: '${widget.customerName.isEmpty ? 'This customer' : widget.customerName} '
                    'has no pending payments.',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _header(credit),
                const SizedBox(height: 16),
                Text(
                  'Unpaid sales',
                  style: AppTheme.heading(size: 14, color: AppColors.textDark),
                ),
                const SizedBox(height: 10),
                for (final sale in credit.sales) _saleCard(sale),
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

  Widget _header(CustomerCredit credit) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.lightGreen,
                child: Text(
                  credit.name.isNotEmpty ? credit.name[0].toUpperCase() : '?',
                  style: AppTheme.body(
                    size: 16,
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
                      style: AppTheme.body(
                        size: 14,
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
                    if (credit.address.trim().isNotEmpty)
                      Text(
                        credit.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textGrey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Outstanding balance',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textGrey,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _currency(credit.totalDue),
                  style: AppTheme.heading(size: 18, color: AppColors.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _saleCard(Sale sale) {
    // The SALE date (when the order / booking was taken) — never the
    // delivery day. The delivery day is shown separately, after it.
    final date = sale.saleDate;
    final delivered = sale.deliveredOn;

    final dateParts = <String>[
      _deliveryLabel(sale),
      if (date != null) 'Sold ${DateFormat('dd MMM yyyy').format(date)}',
      if (delivered != null && !sale.isDeliverNow)
        'Delivered ${DateFormat('dd MMM yyyy').format(delivered)}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.id,
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      dateParts.join(' · '),
                      style: AppTheme.body(
                        size: 10.5,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              if (sale.onCredit)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'On credit',
                    style: AppTheme.body(
                      size: 10,
                      color: AppColors.warning,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          _amountRow('Customer total', sale.billCustomerTotal),
          const SizedBox(height: 6),
          _amountRow('Paid so far', sale.billAmountPaid),
          const SizedBox(height: 6),
          _amountRow('Balance due', sale.billBalanceDue, emphasized: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openReceipt(sale),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('View Receipt'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _receivePayment(sale),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text(
                    'Receive Payment',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amountRow(String label, double value, {bool emphasized = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? AppTheme.heading(size: 12, color: AppColors.textDark)
                : AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
        ),
        Text(
          _currency(value),
          style: emphasized
              ? AppTheme.heading(size: 14, color: AppColors.error)
              : AppTheme.body(
            size: 12,
            color: AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}