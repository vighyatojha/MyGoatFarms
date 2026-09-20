import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Complete Delivery — Booking (Phase 5, Section 1).
///
/// Reached from [GoatStockDetailScreen] for a goat whose
/// `currentStatus` is [Goat.statusBooked]. This is where the holding
/// days and holding charges are worked out: from the day the holding
/// started to the delivery date, both days counted (booked 20 Sept,
/// delivered 23 Sept = 4 days). Booking carries no transportation
/// charge. It then hands off to [SalesService.completeBookingDelivery]
/// to save it, and the sale receipt is generated once it is completed.
class CompleteBookingDeliveryScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const CompleteBookingDeliveryScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<CompleteBookingDeliveryScreen> createState() =>
      _CompleteBookingDeliveryScreenState();
}

class _CompleteBookingDeliveryScreenState
    extends State<CompleteBookingDeliveryScreen> {
  /// The day the goat is actually delivered. Defaults to today.
  DateTime _deliveryDate = _dayOnly(DateTime.now());

  bool _loadingSale = true;
  bool _saving = false;
  String? _loadError;
  Sale? _sale;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  void initState() {
    super.initState();
    _loadSale();
  }

  // ===========================================================================
  // LOAD SALE
  // ===========================================================================

  Future<void> _loadSale() async {
    final saleId = widget.goat.saleId;

    if (saleId == null || saleId.trim().isEmpty) {
      setState(() {
        _loadingSale = false;
        _loadError = 'This goat has no linked sale record.';
      });
      return;
    }

    setState(() {
      _loadingSale = true;
      _loadError = null;
    });

    try {
      final sale =
      await SalesService.instance.getSale(widget.farmId, saleId);

      if (!mounted) return;

      if (sale == null) {
        setState(() {
          _loadingSale = false;
          _loadError = 'Sale $saleId could not be found.';
        });
        return;
      }

      if (!sale.isBooking || sale.status != Sale.statusBooked) {
        setState(() {
          _loadingSale = false;
          _loadError =
          'This sale is not an open Booking — it may already '
              'have been completed.';
        });
        return;
      }

      setState(() {
        _sale = sale;
        _loadingSale = false;

        // Today, unless the holding started later than that (which
        // can't normally happen).
        final start = _dayOnly(sale.holdingStart);
        final today = _dayOnly(DateTime.now());

        _deliveryDate = today.isBefore(start) ? start : today;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSale = false;
        _loadError = FirestoreService.instance.describeError(e);
      });
    }
  }

  // ===========================================================================
  // LIVE CALCULATION
  // ===========================================================================

  /// Holding days from the day holding started to the delivery date,
  /// both days counted. Same rule SalesService applies when saving.
  int get _actualHoldingDays {
    final sale = _sale;
    if (sale == null) return 0;

    return Sale.holdingDaysBetween(sale.holdingStart, _deliveryDate);
  }

  double get _actualHoldingCharges {
    final sale = _sale;
    if (sale == null) return 0;
    return _actualHoldingDays * (sale.holdingChargePerDay ?? 0);
  }

  /// What the customer still owes at pickup: goat sale + holding charges
  /// - the booking amount already paid. Same figure SalesService stores
  /// as finalAmountAfterHolding. (No transportation on a booking.)
  double get _finalAmount {
    final sale = _sale;
    if (sale == null) return 0;

    final raw = sale.totalSaleAmount +
        _actualHoldingCharges -
        (sale.bookingAmount ?? 0);

    return raw < 0 ? 0 : raw;
  }

  Future<void> _pickDeliveryDate(Sale sale) async {
    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: _dayOnly(sale.holdingStart),
      lastDate: _dayOnly(DateTime.now()),
      helpText: 'Delivery date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _deliveryDate = _dayOnly(picked);
    });
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      await SalesService.instance.completeBookingDelivery(
        farmId: widget.farmId,
        saleId: _sale!.id,
        deliveryDate: _deliveryDate,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delivery completed — final amount '
                '${_currency(_finalAmount)}.',
          ),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not complete delivery: '
                '${FirestoreService.instance.describeError(e)}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 20,
        title: Text(
          'Complete Delivery',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: _loadingSale
            ? const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        )
            : _loadError != null
            ? _buildError(_loadError!)
            : _buildForm(_sale!),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
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

  Widget _buildForm(Sale sale) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        WizardSectionCard(
          title: 'Booking Summary',
          icon: Icons.bookmark_outline_rounded,
          children: [
            WizardComputedRow(
              label: 'Customer',
              value: sale.customerName,
            ),
            WizardComputedRow(
              label: 'Goat Sale Amount',
              value: _currency(sale.totalSaleAmount),
            ),
            WizardComputedRow(
              label: 'Booking Amount Paid',
              value: _currency(sale.bookingAmount ?? 0),
            ),
            WizardComputedRow(
              label: 'Holding Charge / Day',
              value: _currency(sale.holdingChargePerDay ?? 0),
            ),
            WizardComputedRow(
              label: 'Holding Started',
              value: DateFormat('dd MMM yyyy')
                  .format(sale.holdingStart),
            ),
          ],
        ),

        const SizedBox(height: 12),

        WizardSectionCard(
          title: 'Delivery',
          icon: Icons.today_outlined,
          children: [
            WizardDateField(
              label: 'Delivery Date',
              helper: 'The day the goat is handed over.',
              date: _deliveryDate,
              onTap: () => _pickDeliveryDate(sale),
            ),
            const SizedBox(height: 12),
            WizardComputedRow(
              label: 'Holding Days',
              value: '$_actualHoldingDays '
                  'day${_actualHoldingDays == 1 ? '' : 's'}',
            ),
            Text(
              '${DateFormat('dd MMM').format(sale.holdingStart)} to '
                  '${DateFormat('dd MMM').format(_deliveryDate)}, '
                  'both days counted.',
              style: AppTheme.body(size: 10, color: AppColors.textGrey),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              _summaryRow(
                'Holding Charges '
                    '($_actualHoldingDays × '
                    '${_currency(sale.holdingChargePerDay ?? 0)})',
                _currency(_actualHoldingCharges),
              ),
              const SizedBox(height: 8),
              _summaryRow(
                'Final Amount Due',
                _currency(_finalAmount),
                emphasized: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: _saving
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
                : const Text(
              'Complete Delivery',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
      String label,
      String value, {
        bool emphasized = false,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTheme.body(size: 11, color: AppColors.textGrey),
        ),
        Text(
          value,
          style: emphasized
              ? AppTheme.heading(size: 15, color: AppColors.textDark)
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