import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Complete Delivery — Wait for Delivery (Phase 5, Section 2).
///
/// Reached from [GoatStockDetailScreen] for a goat whose
/// `currentStatus` is [Goat.statusWaitOnDelivery]. Unlike the Booking
/// branch, the final price here is never re-quoted at today's rate —
/// the plan's Section 5 note flags that as the easiest thing in this
/// phase to get backwards. The rate is always the one fixed at
/// booking time ([Sale.bookingPricePerKg]); only the weight is taken
/// fresh, at pickup:
///
///   Final Price = Pickup Weight x Booking Price/Kg
///                 + Transportation Charge - Advance Paid
class CompleteWaitForDeliveryScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const CompleteWaitForDeliveryScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<CompleteWaitForDeliveryScreen> createState() =>
      _CompleteWaitForDeliveryScreenState();
}

class _CompleteWaitForDeliveryScreenState
    extends State<CompleteWaitForDeliveryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _pickupWeightController;

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
    _pickupWeightController = TextEditingController();
    _loadSale();
  }

  @override
  void dispose() {
    _pickupWeightController.dispose();
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

      if (!sale.isWaitForDelivery ||
          sale.status != Sale.statusWaitForDelivery) {
        setState(() {
          _loadingSale = false;
          _loadError =
          'This sale is not an open Wait for Delivery — it may '
              'already have been completed.';
        });
        return;
      }

      setState(() {
        _sale = sale;
        _loadingSale = false;
        // Pre-fill with the weight recorded at booking time — the
        // customer's goat may have gained or lost weight by pickup,
        // so this is editable, same as the Booking branch pre-fills
        // (and does not lock) the original holding-days estimate.
        _pickupWeightController.text =
        (sale.bookingWeight ?? 0) == 0
            ? ''
            : _trimZeros(sale.bookingWeight!);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSale = false;
        _loadError = FirestoreService.instance.describeError(e);
      });
    }
  }

  String _trimZeros(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  // ===========================================================================
  // LIVE CALCULATION
  // ===========================================================================

  double get _pickupWeight =>
      double.tryParse(_pickupWeightController.text.trim()) ?? 0;

  /// What the customer still owes at pickup: pickup weight x the
  /// booking-time rate + the transportation charge billed to them - the
  /// advance already paid. Same figure SalesService stores as
  /// finalPriceAfterPickup.
  double get _finalPrice {
    final sale = _sale;
    if (sale == null) return 0;

    final raw = _pickupWeight * (sale.bookingPricePerKg ?? 0) +
        (sale.transportCost ?? 0) -
        (sale.bookingAdvanceAmount ?? 0);

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
      await SalesService.instance.completeWaitForDeliveryPickup(
        farmId: widget.farmId,
        saleId: _sale!.id,
        pickupWeight: _pickupWeight,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delivery completed — final amount '
                '${_currency(_finalPrice)}.',
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
            icon: Icons.local_shipping_outlined,
            children: [
              WizardComputedRow(
                label: 'Customer',
                value: sale.customerName,
              ),
              WizardComputedRow(
                label: 'Booking Price / Kg',
                value: _currency(sale.bookingPricePerKg ?? 0),
              ),
              WizardComputedRow(
                label: 'Weight at Booking',
                value: '${_trimZeros(sale.bookingWeight ?? 0)} kg',
              ),
              WizardComputedRow(
                label: 'Advance Paid',
                value: _currency(sale.bookingAdvanceAmount ?? 0),
              ),
            ],
          ),

          const SizedBox(height: 12),

          WizardSectionCard(
            title: 'Actual Pickup',
            icon: Icons.scale_outlined,
            children: [
              wizardField(
                controller: _pickupWeightController,
                label: 'Pickup Weight (kg)',
                hint: 'e.g. 38',
                icon: Icons.monitor_weight_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number <= 0) {
                    return 'Enter valid weight';
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
                  'Pickup Weight × Booking Price/Kg',
                  _currency(
                    _pickupWeight * (sale.bookingPricePerKg ?? 0),
                  ),
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
                  _currency(_finalPrice),
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