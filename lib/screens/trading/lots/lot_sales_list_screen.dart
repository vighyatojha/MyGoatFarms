import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../sale_receipt_screen.dart';

/// Every sale made straight out of a Purchase Lot.
///
/// Lot goats never become individual goat records, so they never show in
/// the Sold list of Goat Stock. This is where those sales live: newest
/// first, with the lot, the customer, the quantity and where each sale is
/// in its life (paid now, booked, waiting for delivery, ...).
///
/// Completed sales open their receipt. Booked and Wait-for-Delivery sales
/// are still open — they are finished from the Booking and Wait on
/// Delivery screens, which is also where their receipt is created.
class LotSalesListScreen extends StatefulWidget {
  final String farmId;

  const LotSalesListScreen({super.key, required this.farmId});

  @override
  State<LotSalesListScreen> createState() => _LotSalesListScreenState();
}

enum _Filter { all, completed, open }

class _LotSalesListScreenState extends State<LotSalesListScreen> {
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Sale>> _stream =
  TradingService.instance.lotSalesStream(widget.farmId);

  _Filter _filter = _Filter.all;

  /// Sales that still have to be delivered / picked up.
  static bool _isOpen(Sale sale) =>
      sale.status == Sale.statusBooked ||
          sale.status == Sale.statusWaitForDelivery;

  /// Only these have a receipt to show.
  static bool _hasReceipt(Sale sale) =>
      sale.status == Sale.statusSold ||
          sale.status == Sale.statusDeliveryCompleted ||
          sale.status == Sale.statusPickupCompleted;

  /// The goat price of a sale. A picked-up Wait-for-Delivery sale is
  /// repriced at pickup; holding charges are separate from the goat price.
  static double _amount(Sale sale) {
    if (sale.status == Sale.statusPickupCompleted) {
      return sale.finalPriceAfterPickup ?? sale.totalSaleAmount;
    }
    return sale.totalSaleAmount;
  }

  static String _statusLabel(Sale sale) {
    switch (sale.status) {
      case Sale.statusSold:
        return 'Sold';
      case Sale.statusBooked:
        return 'Booked';
      case Sale.statusDeliveryCompleted:
        return 'Delivered';
      case Sale.statusWaitForDelivery:
        return 'Waiting';
      case Sale.statusPickupCompleted:
        return 'Picked up';
      case Sale.statusTransferredToPalai:
        return 'In Palai';
      default:
        return sale.status.isEmpty ? 'Sold' : sale.status;
    }
  }

  static String _deliveryLabel(Sale sale) {
    switch (sale.deliveryType) {
      case Sale.deliveryTypeDeliverNow:
        return 'Deliver now';
      case Sale.deliveryTypeBooking:
        return 'Booking / Holding';
      case Sale.deliveryTypeWaitForDelivery:
        return 'Wait for delivery';
      case Sale.deliveryTypePalai:
        return 'Transfer to Palai';
      default:
        return '';
    }
  }

  Color _statusColor(Sale sale) {
    if (_isOpen(sale)) return AppColors.warning;
    if (sale.status == Sale.statusTransferredToPalai) {
      return AppColors.stockTeal;
    }
    return AppColors.success;
  }

  List<Sale> _visible(List<Sale> all) {
    switch (_filter) {
      case _Filter.all:
        return all;
      case _Filter.completed:
        return all.where((s) => !_isOpen(s)).toList();
      case _Filter.open:
        return all.where(_isOpen).toList();
    }
  }

  void _openReceipt(Sale sale) {
    Navigator.of(context).push(
      fastRoute(
        SaleReceiptScreen(farmId: widget.farmId, saleId: sale.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(title: const Text('Lot Sales')),
      body: StreamBuilder<List<Sale>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  FirestoreService.instance.describeError(snapshot.error!),
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 13),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;

          if (all.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 44,
                      color: AppColors.textGrey,
                    ),
                    const SizedBox(height: 12),
                    Text('No lot sales yet', style: AppTheme.heading(size: 16)),
                    const SizedBox(height: 4),
                    Text(
                      'Goats sold straight from a lot will be listed here.',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(size: 12.5),
                    ),
                  ],
                ),
              ),
            );
          }

          final visible = _visible(all);
          final openCount = all.where(_isOpen).length;

          return Column(
            children: [
              _summary(all),
              _filters(all.length, openCount),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                  child: Text(
                    _filter == _Filter.open
                        ? 'Nothing waiting for delivery.'
                        : 'No sales here.',
                    style: AppTheme.body(size: 13),
                  ),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _saleCard(visible[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SUMMARY + FILTERS
  // -------------------------------------------------------------------------

  Widget _summary(List<Sale> all) {
    final done = all.where((s) => !_isOpen(s)).toList();

    final goats = done.fold<int>(0, (sum, s) => sum + s.goatCount);
    final revenue = done.fold<double>(0, (sum, s) => sum + _amount(s));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(child: _stat('Completed sales', '${done.length}')),
          Expanded(child: _stat('Goats sold', '$goats')),
          Expanded(child: _stat('Sale amount', _money.format(revenue))),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 10.5)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: AppTheme.heading(size: 15)),
        ),
      ],
    );
  }

  Widget _filters(int total, int open) {
    Widget chip(_Filter value, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => setState(() => _filter = value),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          chip(_Filter.all, 'All ($total)'),
          chip(_Filter.completed, 'Completed (${total - open})'),
          chip(_Filter.open, 'Open ($open)'),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // CARD
  // -------------------------------------------------------------------------

  Widget _saleCard(Sale sale) {
    final color = _statusColor(sale);
    final date = sale.saleDate;
    final delivery = _deliveryLabel(sale);
    final tappable = _hasReceipt(sale);

    final customer =
    sale.customerName.trim().isEmpty ? 'Customer' : sale.customerName;

    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tappable ? () => _openReceipt(sale) : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sale.goatsReceiptLabel,
                      style: AppTheme.heading(size: 14.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(sale),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(customer, style: AppTheme.body(size: 13)),
              const SizedBox(height: 2),
              Text(
                [
                  if (date != null) _dateFormat.format(date),
                  if (delivery.isNotEmpty) delivery,
                ].join('  •  '),
                style: AppTheme.body(size: 11.5),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    _money.format(_amount(sale)),
                    style: AppTheme.heading(size: 15),
                  ),
                  const Spacer(),
                  if (tappable)
                    Row(
                      children: [
                        Text(
                          'Receipt',
                          style: AppTheme.body(
                            size: 12,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.primaryGreen,
                        ),
                      ],
                    )
                  else if (_isOpen(sale))
                    Text(
                      'Finish from Booking / Wait on Delivery',
                      style: AppTheme.body(size: 11),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}