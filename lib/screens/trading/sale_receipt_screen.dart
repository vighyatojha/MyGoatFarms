import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../goat_icons.dart';
import '../../models/bill_settings_model.dart';
import '../../models/expense_categories.dart';
import '../../models/farm_model.dart';
import '../../models/sale_model.dart';
import '../../services/firestore_service.dart';
import '../../services/sale_receipt_pdf_service.dart';
import '../../services/sales_service.dart';

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
  FarmModel? _farm;
  BillSettings? _billSettings;

  bool _loading = true;
  bool _pdfBusy = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sale = await SalesService.instance.getSale(
        widget.farmId,
        widget.saleId,
      );

      final farm = await FirestoreService.instance.getFarmById(
        widget.farmId,
      );

      if (!mounted) return;

      if (sale == null) {
        setState(() {
          _loading = false;
          _error = 'Sale ${widget.saleId} could not be found.';
        });
        return;
      }

      setState(() {
        _sale = sale;
        _farm = farm;
        _billSettings = farm?.billSettings;
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

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _date(DateTime? value) {
    if (value == null) return '-';

    return DateFormat(
      'dd MMM yyyy, hh:mm a',
    ).format(value);
  }

  bool _completed(Sale sale) {
    return sale.status == Sale.statusSold ||
        sale.status == Sale.statusDeliveryCompleted ||
        sale.status == Sale.statusPickupCompleted;
  }

  String _statusLabel(Sale sale) {
    if (sale.isDeliverNow) {
      return 'Delivered & Sold';
    }

    if (sale.isBooking) {
      return sale.status == Sale.statusDeliveryCompleted
          ? 'Delivery Completed'
          : 'Booked / On Hold';
    }

    if (sale.isWaitForDelivery) {
      return sale.status == Sale.statusPickupCompleted
          ? 'Pickup Completed'
          : 'Waiting for Delivery';
    }

    if (sale.isPalaiTransfer) {
      return 'Transferred to Customer Palai';
    }

    return sale.status;
  }

  Color _statusColor(Sale sale) {
    if (_completed(sale)) {
      return AppColors.success;
    }

    if (sale.isBooking || sale.isWaitForDelivery) {
      return AppColors.warning;
    }

    if (sale.isPalaiTransfer) {
      return AppColors.info;
    }

    return AppColors.primaryGreen;
  }

  Future<void> _previewPdf() async {
    if (_sale == null) return;

    await _runPdfAction(
          () => SaleReceiptPdfService.instance.preview(
        sale: _sale!,
        billSettings: _billSettings ?? BillSettings(),
        farmLogo: _farm?.profileImage,
      ),
    );
  }

  Future<void> _sharePdf() async {
    if (_sale == null) return;

    await _runPdfAction(
          () => SaleReceiptPdfService.instance.share(
        sale: _sale!,
        billSettings: _billSettings ?? BillSettings(),
        farmLogo: _farm?.profileImage,
      ),
    );
  }

  Future<void> _savePdf() async {
    if (_sale == null) return;

    await _runPdfAction(() async {
      final path = await SaleReceiptPdfService.instance.save(
        sale: _sale!,
        billSettings: _billSettings ?? BillSettings(),
        farmLogo: _farm?.profileImage,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt saved successfully.'),
        ),
      );

      debugPrint('Sale receipt saved to: $path');
    });
  }

  Future<void> _runPdfAction(
      Future<void> Function() action,
      ) async {
    if (_sale == null || _pdfBusy) return;

    setState(() {
      _pdfBusy = true;
    });

    try {
      await action();
    } catch (e, stack) {
      debugPrint('Sale receipt PDF error: $e\n$stack');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pdfErrorMessage(e)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _pdfBusy = false;
        });
      }
    }
  }

  String _pdfErrorMessage(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('handshakeexception') ||
        lower.contains('timeoutexception')) {
      return 'Could not download the receipt font. '
          'Check your internet connection and try again.';
    }

    final cleaned = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '')
        .trim();

    return 'Could not generate receipt: '
        '${cleaned.isEmpty ? 'unknown error' : cleaned}';
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
          'Sale Receipt',
          style: AppTheme.heading(size: 18),
        ),
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
            : ((_sale!.isWaitForDelivery || _sale!.isBooking) &&
            !_completed(_sale!))
            ? _receiptPendingState(_sale!)
            : _receipt(_sale!),
      ),
    );
  }

  /// A Booking or Wait for Delivery sale has no receipt until the
  /// delivery is completed (holding charges / pickup weight and the final
  /// amount aren't known before that).
  Widget _receiptPendingState(Sale sale) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.schedule_outlined,
              size: 42,
              color: AppColors.warning,
            ),
            const SizedBox(height: 12),
            Text(
              'Receipt not generated yet',
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Sale ${sale.id} has not been delivered yet. The receipt is '
                  'generated when the delivery is completed.',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 13,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
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
              style: AppTheme.body(
                size: 13,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
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
        _actionCard(),
        const SizedBox(height: 12),
        _section(
          'Sale Information',
          Icons.receipt_long_outlined,
          [
            _row('Receipt / Sale ID', sale.id),
            _row('Sale Date', _date(sale.createdAt)),
            _row('Status', _statusLabel(sale)),
            _row('Delivery Type', _deliveryType(sale)),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          'Customer',
          Icons.person_outline_rounded,
          [
            _row('Name', sale.customerName),
            _row('Mobile', sale.mobile),
            if (sale.address.trim().isNotEmpty)
              _row('Address', sale.address),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          'Goat Details',
          GoatIcons.paw,
          [
            _row(
              'Goat(s)',
              sale.goatIds.isEmpty ? '-' : sale.goatIds.join(', '),
            ),
            _row(
              'Selling Weight',
              '${sale.sellingWeight.toStringAsFixed(2)} kg',
            ),
            if (sale.isFixedPrice)
              _row(
                'Selling Price',
                '${_currency(sale.fixedSalePrice ?? sale.totalSaleAmount)} '
                    '(fixed)',
              )
            else
              _row(
                'Selling Price / kg',
                _currency(sale.sellingPricePerKg),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _priceSection(sale),
        const SizedBox(height: 12),
        _paymentSection(sale),
        if (sale.isBooking ||
            sale.isWaitForDelivery ||
            sale.isPalaiTransfer) ...[
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
        border: Border.all(
          color: color.withOpacity(0.25),
        ),
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
            completed
                ? 'Goat Sale Completed'
                : 'Sale Record Created',
            textAlign: TextAlign.center,
            style: AppTheme.heading(
              size: 18,
              color: AppColors.textDark,
            ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
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

  Widget _actionCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _pdfButton(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Preview PDF',
              onPressed: _pdfBusy ? null : _previewPdf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pdfButton(
              icon: Icons.share_outlined,
              label: 'Share',
              onPressed: _pdfBusy ? null : _sharePdf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pdfButton(
              icon: Icons.save_alt_outlined,
              label: 'Save',
              onPressed: _pdfBusy ? null : _savePdf,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pdfButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        side: const BorderSide(
          color: AppColors.primaryGreen,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pdfBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          else
            Icon(
              icon,
              size: 19,
              color: AppColors.primaryGreen,
            ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.body(
              size: 9.5,
              color: AppColors.textDark,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceSection(Sale sale) {
    return _section(
      'Price Calculation',
      Icons.calculate_outlined,
      [
        if (sale.hasPickupSettlement) ...[
          _moneyRow(
            'Pickup Weight',
            sale.pickupWeight!,
            suffix: ' kg',
          ),
          if (sale.isFixedPrice)
            _moneyRow(
              'Fixed Price',
              sale.fixedSalePrice ?? sale.totalSaleAmount,
              subtitle: 'Agreed at booking — not changed by the weight',
            )
          else
            _moneyRow(
              'Booking Rate / kg',
              sale.bookingPricePerKg ?? sale.sellingPricePerKg,
              subtitle: 'Fixed at booking time, not today\'s rate',
            ),
        ] else ...[
          _moneyRow(
            'Selling Weight',
            sale.sellingWeight,
            suffix: ' kg',
          ),
          if (sale.isFixedPrice)
            _moneyRow(
              'Fixed Price',
              sale.fixedSalePrice ?? sale.totalSaleAmount,
              subtitle: 'Agreed price for all goats',
            )
          else
            _moneyRow(
              'Selling Price / kg',
              sale.sellingPricePerKg,
            ),
        ],
        const Divider(height: 18),
        _moneyRow('Goat Sale', sale.billGoatSale),
        if (sale.billHoldingCharges > 0)
          _moneyRow(
            'Holding Charges',
            sale.billHoldingCharges,
            subtitle:
            '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days × '
                '${_currency(sale.holdingChargePerDay ?? 0)} / day',
          ),
        if (sale.billTransportCharges > 0)
          _moneyRow(
            'Transportation',
            sale.billTransportCharges,
          ),
        const Divider(height: 18),
        _moneyRow(
          'Customer Total',
          sale.billCustomerTotal,
          emphasized: true,
        ),
      ],
    );
  }

  Widget _paymentSection(Sale sale) {
    final initialMethod = (sale.paymentMethod ?? '').trim();

    return _section(
      'Payment Summary',
      Icons.account_balance_wallet_outlined,
      [
        _moneyRow(
          sale.billInitialPaymentLabel,
          sale.billInitialPayment,
          subtitle: sale.billInitialPayment > 0 && initialMethod.isNotEmpty
              ? 'Paid by $initialMethod'
              : null,
        ),

        // Balance payments collected after delivery, oldest first.
        for (final payment in sale.payments)
          _moneyRow(
            'Balance Payment',
            payment.amount,
            subtitle: _paymentSubtitle(payment),
          ),

        if (sale.payments.isNotEmpty)
          _moneyRow(
            'Total Paid',
            sale.billAmountPaid,
          ),

        _moneyRow(
          'Remaining Amount',
          sale.billBalanceDue,
          emphasized: true,
        ),

        // A sale on credit: say so, and where the balance can be found.
        if (sale.onCredit && sale.billBalanceDue > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 14,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sold on credit — this balance is on '
                        '${sale.customerName}\'s outstanding balance '
                        '(Finance > Customers on Credit).',
                    style: AppTheme.body(
                      size: 10.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Only once the goat has been delivered and something is owed.
        if (sale.canCollectBalance) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _receivePayment,
              icon: const Icon(
                Icons.payments_outlined,
                size: 19,
              ),
              label: const Text(
                'Receive Balance Payment',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _paymentSubtitle(SalePayment payment) {
    final parts = <String>[
      DateFormat('dd MMM yyyy').format(payment.date),
      if (payment.method.trim().isNotEmpty) payment.method.trim(),
      if (payment.note.trim().isNotEmpty) payment.note.trim(),
    ];

    return parts.join(' · ');
  }

  /// Opens the balance-payment form. The payment itself is recorded by
  /// [SalesService.receiveBalancePayment] (which also writes the Finance
  /// entry, in the same transaction); on success the receipt is reloaded
  /// so the history, Remaining Amount and button reflect it.
  Future<void> _receivePayment() async {
    final sale = _sale;

    if (sale == null) return;

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

    await _load();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment recorded.'),
      ),
    );
  }

  Widget _transactionSection(Sale sale) {
    return _section(
      'Transaction Details',
      Icons.info_outline_rounded,
      [
        if (sale.isBooking) ...[
          _row(
            'Holding From',
            DateFormat('dd MMM yyyy').format(sale.holdingStart),
          ),
          if (sale.holdingEndDate != null)
            _row(
              'Holding Until',
              DateFormat('dd MMM yyyy').format(sale.holdingEndDate!),
            ),
          _row(
            'Holding Days',
            '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days',
          ),
          _row(
            'Holding Rate',
            '${_currency(sale.holdingChargePerDay ?? 0)} / day',
          ),
          if (sale.deliveryCompletedAt != null)
            _row(
              'Delivery Completed',
              _date(sale.deliveryCompletedAt),
            ),
        ],
        if (sale.isWaitForDelivery) ...[
          _row(
            'Booking Weight',
            '${(sale.bookingWeight ?? 0).toStringAsFixed(2)} kg',
          ),
          if (sale.isFixedPrice)
            _row(
              'Fixed Price',
              _currency(sale.fixedSalePrice ?? sale.totalSaleAmount),
            )
          else
            _row(
              'Booking Rate',
              '${_currency(sale.bookingPricePerKg ?? 0)} / kg',
            ),
          if (sale.pickupWeight != null)
            _row(
              'Pickup Weight',
              '${sale.pickupWeight!.toStringAsFixed(2)} kg',
            ),
        ],
        if (sale.isPalaiTransfer) ...[
          if (sale.transferDate != null)
            _row(
              'Transfer Date',
              DateFormat('dd MMM yyyy')
                  .format(sale.transferDate!),
            ),
          if ((sale.palaiPackage ?? '').trim().isNotEmpty)
            _row(
              'Palai Package',
              sale.palaiPackage!,
            ),
          if (sale.monthlyPalaiCharge != null)
            _row(
              'Monthly Palai Charge',
              _currency(sale.monthlyPalaiCharge!),
            ),
        ],
      ],
    );
  }

  Widget _bottomNotice(Sale sale, Color color) {
    final message =
    sale.isBooking &&
        sale.status != Sale.statusDeliveryCompleted
        ? 'This is the booking receipt. Final holding charges are recalculated when delivery is completed.'
        : sale.isWaitForDelivery &&
        sale.status != Sale.statusPickupCompleted
        ? 'This sale is waiting for delivery. Final settlement uses the booking-time rate and pickup weight.'
        : 'This receipt reflects the sale values currently saved in Firestore.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            sale.isBooking || sale.isWaitForDelivery
                ? Icons.info_outline_rounded
                : Icons.verified_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
      String title,
      IconData icon,
      List<Widget> children,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 13,
                    color: AppColors.textDark,
                  ),
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
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
              ),
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
      num value, {
        String suffix = '',
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
                      ? AppTheme.heading(
                    size: 13,
                    color: AppColors.textDark,
                  )
                      : AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                suffix.isEmpty
                    ? _currency(value)
                    : '${value.toStringAsFixed(2)}$suffix',
                style: emphasized
                    ? AppTheme.heading(
                  size: 14,
                  color: AppColors.darkGreen,
                )
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
              style: AppTheme.body(
                size: 9.5,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _deliveryType(Sale sale) {
    if (sale.isDeliverNow) return 'Deliver Now';
    if (sale.isBooking) return 'Booking / Holding';
    if (sale.isWaitForDelivery) return 'Wait for Delivery';
    if (sale.isPalaiTransfer) return 'Transfer to Palai';
    return sale.deliveryType;
  }
}

// =============================================================================
// RECEIVE BALANCE PAYMENT — bottom sheet
// =============================================================================

/// Public so the Customers on Credit screens can open the same sheet to
/// receive a payment on a sale. Pops `true` once the payment is recorded.
class SaleReceivePaymentSheet extends StatefulWidget {
  final String farmId;
  final Sale sale;

  const SaleReceivePaymentSheet({
    super.key,
    required this.farmId,
    required this.sale,
  });

  @override
  State<SaleReceivePaymentSheet> createState() =>
      _SaleReceivePaymentSheetState();
}

class _SaleReceivePaymentSheetState extends State<SaleReceivePaymentSheet> {
  late final TextEditingController _amountController;
  final TextEditingController _noteController = TextEditingController();

  String _method = FinancePaymentMethods.cash;
  bool _saving = false;
  String? _error;

  double get _due => widget.sale.billBalanceDue;

  @override
  void initState() {
    super.initState();

    _amountController = TextEditingController(text: _plain(_due));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _plain(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  Future<void> _submit() async {
    if (_saving) return;

    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'Enter an amount greater than zero.';
      });
      return;
    }

    if ((amount * 100).round() > (_due * 100).round()) {
      setState(() {
        _error = 'That is more than the balance due (${_currency(_due)}).';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await SalesService.instance.receiveBalancePayment(
        farmId: widget.farmId,
        saleId: widget.sale.id,
        amount: amount,
        paymentMethod: _method,
        note: _noteController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;

        // A StateError carries a message written for the person (amount
        // too high, nothing due, ...). Anything else is a connection
        // problem — the write may still have gone through, so say so
        // rather than inviting a second, duplicate payment.
        _error = e is StateError
            ? e.message
            : '${FirestoreService.instance.describeError(e)}\n'
            'Check the receipt before trying again, in case the '
            'payment was already saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Receive Balance Payment',
                  style: AppTheme.heading(
                    size: 17,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${sale.customerName} · ${sale.id}',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Balance due',
                          style: AppTheme.body(
                            size: 12,
                            color: AppColors.textGrey,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _currency(_due),
                        style: AppTheme.heading(
                          size: 16,
                          color: AppColors.darkGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _amountController,
                  enabled: !_saving,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  onChanged: (_) {
                    if (_error != null) {
                      setState(() {
                        _error = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '₹ ',
                    suffixIcon: TextButton(
                      onPressed: _saving
                          ? null
                          : () {
                        setState(() {
                          _amountController.text = _plain(_due);
                          _error = null;
                        });
                      },
                      child: const Text('Full balance'),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Payment method',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: FinancePaymentMethods.all.map((method) {
                    final selected = _method == method;

                    return ChoiceChip(
                      label: Text(method),
                      selected: selected,
                      onSelected: _saving
                          ? null
                          : (_) {
                        setState(() {
                          _method = method;
                        });
                      },
                      selectedColor:
                      AppColors.primaryGreen.withOpacity(0.15),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.darkGreen
                            : AppColors.textDark,
                      ),
                      side: BorderSide(
                        color: selected
                            ? AppColors.primaryGreen
                            : AppColors.divider,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteController,
                  enabled: !_saving,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppTheme.body(
                      size: 11.5,
                      color: AppColors.error,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'Record Payment',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}