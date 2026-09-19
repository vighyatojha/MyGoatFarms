import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// `currentStatus` is [Goat.statusBooked]. Recomputes the final
/// settlement using the *actual* elapsed holding days rather than the
/// estimate made at booking time (Phase 4, Step 5) — see the plan's
/// Task 1.2 note — then hands off to
/// [SalesService.completeBookingDelivery] to save it.
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _actualHoldingDaysController;

  bool _loadingSale = true;
  bool _saving = false;
  String? _loadError;
  Sale? _sale;

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
    _actualHoldingDaysController = TextEditingController();
    _loadSale();
  }

  @override
  void dispose() {
    _actualHoldingDaysController.dispose();
    super.dispose();
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
        _actualHoldingDaysController.text =
            (sale.holdingDays ?? 0).toString();
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

  int get _actualHoldingDays =>
      int.tryParse(_actualHoldingDaysController.text.trim()) ?? 0;

  double get _actualHoldingCharges {
    final sale = _sale;
    if (sale == null) return 0;
    return _actualHoldingDays * (sale.holdingChargePerDay ?? 0);
  }

  /// What the customer still owes at pickup: goat sale + actual holding
  /// charges + the transportation charge billed to them - the booking
  /// amount already paid. Same figure SalesService stores as
  /// finalAmountAfterHolding.
  double get _finalAmount {
    final sale = _sale;
    if (sale == null) return 0;

    final raw = sale.totalSaleAmount +
        _actualHoldingCharges +
        (sale.transportCost ?? 0) -
        (sale.bookingAmount ?? 0);

    return raw < 0 ? 0 : raw;
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    if (_saving) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _saving = true;
    });

    try {
      await SalesService.instance.completeBookingDelivery(
        farmId: widget.farmId,
        saleId: _sale!.id,
        actualHoldingDays: _actualHoldingDays,
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
    return Form(
      key: _formKey,
      child: ListView(
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
                label: 'Originally Estimated Days',
                value: '${sale.holdingDays ?? 0}',
              ),
              if (sale.expectedDeliveryDate != null)
                WizardComputedRow(
                  label: 'Expected Delivery Date',
                  value: DateFormat('dd MMM yyyy')
                      .format(sale.expectedDeliveryDate!),
                ),
            ],
          ),

          const SizedBox(height: 12),

          WizardSectionCard(
            title: 'Actual Pickup',
            icon: Icons.today_outlined,
            children: [
              wizardField(
                controller: _actualHoldingDaysController,
                label: 'Actual Holding Days',
                hint: 'e.g. 5',
                icon: Icons.event_repeat_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter valid days';
                  }

                  return null;
                },
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
                  'Actual Holding Charges',
                  _currency(_actualHoldingCharges),
                ),
                const SizedBox(height: 8),
                if ((sale.transportCost ?? 0) > 0) ...[
                  _summaryRow(
                    'Transportation',
                    _currency(sale.transportCost!),
                  ),
                  const SizedBox(height: 8),
                ],
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
      ),
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