import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
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
      final Sale? sale = await SalesService.instance.getSale(
        widget.farmId,
        widget.saleId,
      );

      final FarmModel? farm = await FirestoreService.instance.getFarmById(
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

  /// Rounds to 2 decimals so floating-point drift never shows up in a
  /// figure (e.g. 27456.000000000004). Mirrors the PDF service.
  double _round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;

    final nudge = value >= 0 ? 1e-9 : -1e-9;

    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  double _paid(Sale sale) {
    if (sale.isDeliverNow) {
      return _round2(sale.amountReceived ?? 0);
    }

    if (sale.isBooking) {
      return _round2(sale.bookingAmount ?? 0);
    }

    if (sale.isWaitForDelivery) {
      return _round2(sale.bookingAdvanceAmount ?? 0);
    }

    return 0;
  }

  double _payable(Sale sale) {
    if (sale.isBooking &&
        sale.status == Sale.statusDeliveryCompleted) {
      return _round2(
        sale.finalAmountAfterHolding ?? sale.totalSaleAmount,
      );
    }

    if (sale.isWaitForDelivery &&
        sale.status == Sale.statusPickupCompleted) {
      return _round2(
        sale.finalPriceAfterPickup ?? sale.totalSaleAmount,
      );
    }

    return _round2(
      sale.totalSaleAmount +
          (sale.isBooking ? (sale.totalHoldingCharges ?? 0) : 0),
    );
  }

  double _remaining(Sale sale) {
    final value = _round2(_payable(sale) - _paid(sale));

    return value <= 0 ? 0.0 : value;
  }

  Future<void> _previewPdf() async {
    if (_sale == null) return;

    await _runPdfAction(
          () => SaleReceiptPdfService.instance.preview(
        sale: _sale!,
        billSettings: _billSettings ?? BillSettings(),
      ),
    );
  }

  Future<void> _sharePdf() async {
    if (_sale == null) return;

    await _runPdfAction(
          () => SaleReceiptPdfService.instance.share(
        sale: _sale!,
        billSettings: _billSettings ?? BillSettings(),
      ),
    );
  }

  Future<void> _savePdf() async {
    if (_sale == null) return;

    await _runPdfAction(() async {
      final path = await SaleReceiptPdfService.instance.save(
        sale: _sale!,
        billSettings: _billSettings ?? BillSettings(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Receipt saved successfully.',
          ),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
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
      // Always log the real error + stack — this is what makes a PDF
      // problem diagnosable from `flutter run` / logcat.
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

  /// User-facing text for a failed PDF action.
  ///
  /// Deliberately NOT routed through FirestoreService.describeError: that
  /// helper labels every unknown error "Could not reach Firestore", which
  /// is wrong (and misleading) for a PDF/font problem.
  String _pdfErrorMessage(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    // The receipt fonts (Noto Sans) are downloaded the first time a PDF is
    // built, so a network failure surfaces here.
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
          style: AppTheme.heading(
            size: 18,
          ),
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
      padding: const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        28,
      ),
      children: [
        _statusCard(sale, color),
        const SizedBox(height: 12),
        _actionCard(),
        const SizedBox(height: 12),
        _section(
          'Sale Information',
          Icons.receipt_long_outlined,
          [
            _row(
              'Receipt / Sale ID',
              sale.id,
            ),
            _row(
              'Sale Date',
              _date(sale.createdAt),
            ),
            _row(
              'Status',
              _statusLabel(sale),
            ),
            _row(
              'Delivery Type',
              _deliveryType(sale),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          'Customer',
          Icons.person_outline_rounded,
          [
            _row(
              'Name',
              sale.customerName,
            ),
            _row(
              'Mobile',
              sale.mobile,
            ),
            if (sale.address.trim().isNotEmpty)
              _row(
                'Address',
                sale.address,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          'Goat Details',
          Icons.pets_outlined,
          [
            _row(
              'Goat(s)',
              sale.goatIds.isEmpty
                  ? '-'
                  : sale.goatIds.join(', '),
            ),
            _row(
              'Selling Weight',
              '${sale.sellingWeight.toStringAsFixed(2)} kg',
            ),
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
            sale.isPalaiTransfer ||
            sale.transportCost != null) ...[
          const SizedBox(height: 12),
          _transactionSection(sale),
        ],
        const SizedBox(height: 16),
        _bottomNotice(sale, color),
      ],
    );
  }

  Widget _statusCard(
      Sale sale,
      Color color,
      ) {
    final completed = _completed(sale);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        16,
        18,
        16,
        16,
      ),
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
              onPressed: _pdfBusy
                  ? null
                  : _previewPdf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pdfButton(
              icon: Icons.share_outlined,
              label: 'Share',
              onPressed: _pdfBusy
                  ? null
                  : _sharePdf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pdfButton(
              icon: Icons.save_alt_outlined,
              label: 'Save',
              onPressed: _pdfBusy
                  ? null
                  : _savePdf,
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
        padding: const EdgeInsets.symmetric(
          vertical: 10,
        ),
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
    final holding =
        sale.totalHoldingCharges ?? 0;

    final finalAmount = _payable(sale);

    return _section(
      'Price Calculation',
      Icons.calculate_outlined,
      [
        _moneyRow(
          'Selling Weight',
          sale.sellingWeight,
          suffix: ' kg',
        ),
        _moneyRow(
          'Selling Price / kg',
          sale.sellingPricePerKg,
        ),
        const Divider(height: 18),
        _moneyRow(
          'Goat Sale Amount',
          sale.totalSaleAmount,
        ),
        if (sale.isBooking && holding > 0)
          _moneyRow(
            'Holding Charges',
            holding,
            subtitle:
            '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days × '
                '${_currency(sale.holdingChargePerDay ?? 0)} / day',
          ),
        if (sale.isWaitForDelivery &&
            sale.status == Sale.statusPickupCompleted)
          _moneyRow(
            'Pickup Weight',
            sale.pickupWeight ??
                sale.sellingWeight,
            suffix: ' kg',
            subtitle:
            'Final price uses booking rate '
                '${_currency(sale.bookingPricePerKg ?? sale.sellingPricePerKg)} / kg',
          ),
        const Divider(height: 18),
        _moneyRow(
          sale.isBooking &&
              sale.status ==
                  Sale.statusDeliveryCompleted
              ? 'Final Amount After Holding'
              : 'Total Payable',
          finalAmount,
          emphasized: true,
        ),
      ],
    );
  }

  Widget _paymentSection(Sale sale) {
    final paid = _paid(sale);
    final remaining = _remaining(sale);

    return _section(
      'Payment Summary',
      Icons.account_balance_wallet_outlined,
      [
        _moneyRow(
          sale.isBooking
              ? 'Booking Amount Paid'
              : sale.isWaitForDelivery
              ? 'Advance Paid'
              : 'Amount Received',
          paid,
        ),
        _moneyRow(
          'Remaining Amount',
          remaining,
          emphasized: true,
        ),
      ],
    );
  }

  Widget _transactionSection(Sale sale) {
    return _section(
      'Transaction Details',
      Icons.info_outline_rounded,
      [
        if (sale.isBooking) ...[
          _row(
            'Holding Days',
            '${sale.actualHoldingDays ?? sale.holdingDays ?? 0} days',
          ),
          _row(
            'Holding Rate',
            '${_currency(sale.holdingChargePerDay ?? 0)} / day',
          ),
          if (sale.expectedDeliveryDate != null)
            _row(
              'Expected Delivery',
              DateFormat('dd MMM yyyy')
                  .format(sale.expectedDeliveryDate!),
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
          if ((sale.palaiPackage ?? '')
              .trim()
              .isNotEmpty)
            _row(
              'Palai Package',
              sale.palaiPackage!,
            ),
          if (sale.monthlyPalaiCharge != null)
            _row(
              'Monthly Palai Charge',
              _currency(
                sale.monthlyPalaiCharge!,
              ),
            ),
        ],
        if (sale.transportCost != null)
          _row(
            'Transport Cost',
            _currency(sale.transportCost!),
          ),
      ],
    );
  }

  Widget _bottomNotice(
      Sale sale,
      Color color,
      ) {
    final message =
    sale.isBooking &&
        sale.status !=
            Sale.statusDeliveryCompleted
        ? 'This is the booking receipt. Final holding charges are recalculated when delivery is completed.'
        : sale.isWaitForDelivery &&
        sale.status !=
            Sale.statusPickupCompleted
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
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            sale.isBooking ||
                sale.isWaitForDelivery
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
      padding: const EdgeInsets.fromLTRB(
        14,
        14,
        14,
        12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
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

  Widget _row(
      String label,
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
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
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
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
    if (sale.isDeliverNow) {
      return 'Deliver Now';
    }

    if (sale.isBooking) {
      return 'Booking / Holding';
    }

    if (sale.isWaitForDelivery) {
      return 'Wait for Delivery';
    }

    if (sale.isPalaiTransfer) {
      return 'Transfer to Palai';
    }

    return sale.deliveryType;
  }
}