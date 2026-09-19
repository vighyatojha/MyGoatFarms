
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/sale_model.dart';
import '../../services/firestore_service.dart';
import '../../services/sales_service.dart';

/// Read-only receipt screen for an already saved Trading sale.
/// PDF generation is intentionally handled as the next receipt task.
class SaleReceiptScreen extends StatefulWidget {
  final String farmId;
  final String saleId;

  const SaleReceiptScreen({
    super.key,
    required this.farmId,
    required this.saleId,
  });

  @override
  State<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends State<SaleReceiptScreen> {
  Sale? _sale;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSale();
  }

  Future<void> _loadSale() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sale = await SalesService.instance.getSale(
        widget.farmId,
        widget.saleId,
      );

      if (!mounted) return;

      if (sale == null) {
        setState(() {
          _loading = false;
          _error = 'Sale ' + widget.saleId + ' could not be found.';
        });
        return;
      }

      setState(() {
        _sale = sale;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FirestoreService.instance.describeError(e);
      });
    }
  }

  String _currency(num value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);

  String _date(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(value);
  }

  bool _completed(Sale sale) =>
      sale.status == Sale.statusSold ||
      sale.status == Sale.statusDeliveryCompleted ||
      sale.status == Sale.statusPickupCompleted;

  String _statusLabel(Sale sale) {
    if (sale.isDeliverNow) return 'Delivered & Sold';
    if (sale.isBooking) {
      return sale.status == Sale.statusDeliveryCompleted
          ? 'Sold — Delivery Completed'
          : 'Booked / On Hold';
    }
    if (sale.isWaitForDelivery) {
      return sale.status == Sale.statusPickupCompleted
          ? 'Sold — Pickup Completed'
          : 'Waiting for Delivery';
    }
    if (sale.isPalaiTransfer) return 'Transferred to Customer Palai';
    return sale.status;
  }

  Color _statusColor(Sale sale) {
    if (_completed(sale)) return AppColors.success;
    if (sale.isBooking || sale.isWaitForDelivery) return AppColors.warning;
    if (sale.isPalaiTransfer) return AppColors.info;
    return AppColors.primaryGreen;
  }

  double _paid(Sale sale) {
    if (sale.isDeliverNow) return sale.amountReceived ?? 0;
    if (sale.isBooking) return sale.bookingAmount ?? 0;
    if (sale.isWaitForDelivery) return sale.bookingAdvanceAmount ?? 0;
    return 0;
  }

  double _remaining(Sale sale) {
    if (sale.isBooking && sale.status == Sale.statusDeliveryCompleted) {
      return sale.finalAmountAfterHolding ?? 0;
    }
    if (sale.isWaitForDelivery &&
        sale.status == Sale.statusPickupCompleted) {
      return sale.finalPriceAfterPickup ?? 0;
    }

    final remaining = sale.totalSaleAmount - _paid(sale);
    return remaining < 0 ? 0 : remaining;
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
        title: Text('Sale Receipt', style: AppTheme.heading(size: 18)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              )
            : _error != null
                ? _errorState()
                : _receipt(_sale!),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 42,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadSale,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receipt(Sale sale) {
    final color = _statusColor(sale);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _statusCard(sale, color),
        const SizedBox(height: 12),
        _section('Sale Information', Icons.receipt_long_outlined, [
          _row('Receipt / Sale ID', sale.id),
          _row('Sale Date', _date(sale.createdAt)),
          _row('Status', _statusLabel(sale)),
        ]),
        const SizedBox(height: 12),
        _section('Customer', Icons.person_outline_rounded, [
          _row('Name', sale.customerName),
          _row('Mobile', sale.mobile),
          if (sale.address.trim().isNotEmpty) _row('Address', sale.address),
        ]),
        const SizedBox(height: 12),
        _section('Goat Details', Icons.pets_outlined, [
          _row('Goat(s)', sale.goatIds.isEmpty ? '-' : sale.goatIds.join(', ')),
          _row(
            'Selling Weight',
            sale.sellingWeight.toStringAsFixed(2) + ' kg',
          ),
          _row('Selling Price / kg', _currency(sale.sellingPricePerKg)),
        ]),
        const SizedBox(height: 12),
        _priceSection(sale),
        if (sale.isBooking ||
            sale.isWaitForDelivery ||
            sale.transportCost != null) ...[
          const SizedBox(height: 12),
          _transactionSection(sale),
        ],
        const SizedBox(height: 16),
        _bottomNotice(sale, color),
      ],
    );
  }

  Widget _statusCard(Sale sale, Color color) {
    final completed = _completed(sale);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              completed
                  ? Icons.check_circle_outline_rounded
                  : Icons.receipt_long_rounded,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            completed ? 'Goat Sale Completed' : 'Sale Record Created',
            textAlign: TextAlign.center,
            style: AppTheme.heading(size: 18, color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            _statusLabel(sale),
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 12,
              color: color,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              sale.id,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceSection(Sale sale) {
    final holding = sale.totalHoldingCharges ?? 0;
    final paid = _paid(sale);

    double total;
    String totalLabel;

    if (sale.isBooking && sale.status == Sale.statusDeliveryCompleted) {
      total = sale.finalAmountAfterHolding ?? sale.totalSaleAmount;
      totalLabel = 'Final Amount After Holding';
    } else if (sale.isWaitForDelivery &&
        sale.status == Sale.statusPickupCompleted) {
      total = sale.finalPriceAfterPickup ?? sale.totalSaleAmount;
      totalLabel = 'Final Sale Amount';
    } else {
      total = sale.totalSaleAmount + (sale.isBooking ? holding : 0);
      totalLabel = 'Total Sale Amount';
    }

    return _section('Price Breakdown', Icons.calculate_outlined, [
      _moneyRow('Goat Sale Amount', sale.totalSaleAmount),
      if (sale.isBooking && holding > 0)
        _moneyRow(
          'Holding Charges',
          holding,
          subtitle:
              (sale.actualHoldingDays ?? sale.holdingDays ?? 0).toString() +
              ' days × ' +
              _currency(sale.holdingChargePerDay ?? 0) +
              ' / day',
        ),
      if (sale.isWaitForDelivery &&
          sale.status == Sale.statusPickupCompleted)
        _moneyRow(
          'Pickup Weight × Booking Price / kg',
          sale.finalPriceAfterPickup ?? sale.totalSaleAmount,
        ),
      const Divider(height: 18),
      _moneyRow(totalLabel, total, emphasized: true),
      _moneyRow(
        sale.isBooking
            ? 'Booking Amount Paid'
            : sale.isWaitForDelivery
                ? 'Advance Paid'
                : 'Amount Received',
        paid,
      ),
      _moneyRow('Remaining Amount', _remaining(sale), emphasized: true),
    ]);
  }

  Widget _transactionSection(Sale sale) {
    return _section('Transaction Details', Icons.info_outline_rounded, [
      if (sale.isBooking) ...[
        _row(
          'Holding Days',
          (sale.actualHoldingDays ?? sale.holdingDays ?? 0).toString() +
              ' days',
        ),
        _row(
          'Holding Rate',
          _currency(sale.holdingChargePerDay ?? 0) + ' / day',
        ),
        if (sale.expectedDeliveryDate != null)
          _row(
            'Expected Delivery',
            DateFormat('dd MMM yyyy').format(sale.expectedDeliveryDate!),
          ),
      ],
      if (sale.isWaitForDelivery) ...[
        _row(
          'Booking Weight',
          (sale.bookingWeight ?? 0).toStringAsFixed(2) + ' kg',
        ),
        _row(
          'Booking Rate',
          _currency(sale.bookingPricePerKg ?? 0) + ' / kg',
        ),
        if (sale.pickupWeight != null)
          _row(
            'Pickup Weight',
            sale.pickupWeight!.toStringAsFixed(2) + ' kg',
          ),
      ],
      if (sale.transportCost != null)
        _row('Transport Cost Recorded', _currency(sale.transportCost!)),
    ]);
  }

  Widget _bottomNotice(Sale sale, Color color) {
    final completed = _completed(sale);
    final message = completed
        ? 'This receipt reflects the completed sale and the settlement values already saved in Firestore.'
        : sale.isBooking
            ? 'This is the booking receipt. Final holding charges are recalculated when delivery is completed.'
            : sale.isWaitForDelivery
                ? 'This sale is waiting for delivery. Final settlement uses the booking-time rate and pickup weight.'
                : sale.isPalaiTransfer
                    ? 'This record represents a Palai transfer rather than a completed cash delivery.'
                    : 'This sale is not yet marked as completed.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            completed ? Icons.verified_rounded : Icons.info_outline_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.body(size: 11, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(size: 13, color: AppColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String label,
    double value, {
    String? subtitle,
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: emphasized
                      ? AppTheme.heading(size: 13, color: AppColors.textDark)
                      : AppTheme.body(size: 11, color: AppColors.textGrey),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _currency(value),
                style: emphasized
                    ? AppTheme.heading(size: 14, color: AppColors.darkGreen)
                    : AppTheme.body(
                        size: 12,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTheme.body(size: 9.5, color: AppColors.textGrey),
            ),
          ],
        ],
      ),
    );
  }
}
