import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app_theme.dart';
import '../../../../models/trading_purchase_draft.dart';
import '../../../../models/trading_purchase_model.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 4 — Purchase Summary.
///
/// This is the final review screen for a new goat purchase.
///
/// Receiving can be:
/// - Completed now
/// - Pending / completed later
///
/// The actual Firestore save happens only through [save].
class Step4Summary extends StatefulWidget {
  final PurchaseDraft draft;

  final ValueChanged<TradingPurchase> onSaved;

  const Step4Summary({
    super.key,
    required this.draft,
    required this.onSaved,
  });

  @override
  State<Step4Summary> createState() => Step4SummaryState();
}

class Step4SummaryState extends State<Step4Summary> {
  bool _saving = false;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  void _message(
      String text, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
        error ? AppColors.error : AppColors.primaryGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> save() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    final draft = widget.draft;

    try {
      final farmId =
      await FirestoreService.instance.currentFarmId();

      if (farmId == null) {
        _message(
          'Could not find your farm profile. Please log in again.',
          error: true,
        );
        return;
      }

      // Make sure the payment method is strictly Cash or Online.
      draft.setPaymentMethod(draft.paymentMethod);

      // When receiving was not filled now, force pending status.
      //
      // When receiving was filled, Step 3 validation has already happened
      // in the wizard and the draft is marked completed.
      final receivingStatus =
      draft.isReceivingCompleted ? 'completed' : 'pending';

      final saved =
      await TradingService.instance.savePurchase(
        farmId: farmId,

        // -------------------------------------------------------------------
        // SELLER
        // -------------------------------------------------------------------
        sellerName: draft.sellerName,
        mobile: draft.mobile,
        market: draft.market,
        vehicleNumber: draft.vehicleNumber,
        purchaseDate: draft.purchaseDate,

        // -------------------------------------------------------------------
        // PURCHASE
        // -------------------------------------------------------------------
        totalGoats: draft.totalGoats,
        totalWeightAtPurchase:
        draft.totalWeightAtPurchase,
        pricePerKg: draft.pricePerKg,

        // -------------------------------------------------------------------
        // PAYMENT
        // -------------------------------------------------------------------
        paymentMethod: draft.paymentMethod,

        // -------------------------------------------------------------------
        // RECEIVING
        // -------------------------------------------------------------------
        receivingStatus: receivingStatus,

        dateReceivedAtFarm:
        receivingStatus == 'completed'
            ? draft.dateReceivedAtFarm
            : null,

        totalWeightAfterArrival:
        receivingStatus == 'completed'
            ? draft.totalWeightAfterArrival
            : null,

        mortality:
        receivingStatus == 'completed'
            ? draft.mortality
            : 0,

        remarks:
        receivingStatus == 'completed'
            ? draft.remarks
            : '',

        // -------------------------------------------------------------------
        // TRANSPORT / OTHER EXPENSES
        // -------------------------------------------------------------------
        transportCost:
        receivingStatus == 'completed'
            ? draft.transportCost
            : 0,

        loadingCharges:
        receivingStatus == 'completed'
            ? draft.loadingCharges
            : 0,

        unloadingCharges:
        receivingStatus == 'completed'
            ? draft.unloadingCharges
            : 0,

        otherExpenses:
        receivingStatus == 'completed'
            ? draft.otherExpenses
            : 0,
      );

      if (!mounted) return;

      widget.onSaved(saved);
    } on TimeoutException {
      _message(
        'Connection is taking too long. Please try again.',
        error: true,
      );
    } on ArgumentError catch (e) {
      _message(
        e.message?.toString() ??
            'Please check the purchase details.',
        error: true,
      );
    } catch (e) {
      _message(
        FirestoreService.instance.describeError(e),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  bool get isSaving => _saving;

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    final bool receivingCompleted =
        draft.isReceivingCompleted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24,
      ),
      children: [
        // =====================================================================
        // RECEIVING STATUS
        // =====================================================================

        _receivingStatusCard(
          completed: receivingCompleted,
        ),

        const SizedBox(height: 14),

        // =====================================================================
        // SELLER & PURCHASE
        // =====================================================================

        WizardSectionCard(
          title: 'Seller & Purchase',
          icon: Icons.receipt_long_outlined,
          children: [
            WizardComputedRow(
              label: 'Seller',
              value: draft.sellerName,
            ),
            WizardComputedRow(
              label: 'Mobile',
              value: draft.mobile,
            ),

            if (draft.market.trim().isNotEmpty)
              WizardComputedRow(
                label: 'Market',
                value: draft.market,
              ),

            if (draft.vehicleNumber.trim().isNotEmpty)
              WizardComputedRow(
                label: 'Vehicle No.',
                value: draft.vehicleNumber,
              ),

            WizardComputedRow(
              label: 'Purchase Date',
              value: _date(draft.purchaseDate),
            ),

            WizardComputedRow(
              label: 'Payment Method',
              value: draft.paymentMethod,
            ),
          ],
        ),

        const SizedBox(height: 14),

        // =====================================================================
        // PURCHASE WEIGHT
        // =====================================================================

        WizardSectionCard(
          title: 'Purchase Details',
          icon: Icons.scale_outlined,
          children: [
            WizardComputedRow(
              label: 'Total Goats',
              value: '${draft.totalGoats}',
            ),
            WizardComputedRow(
              label: 'Weight at Purchase',
              value:
              '${_trimZero(draft.totalWeightAtPurchase)} kg',
            ),
            WizardComputedRow(
              label: 'Price per KG',
              value: _currency(draft.pricePerKg),
            ),
            WizardComputedRow(
              label: 'Purchase Amount',
              value: _currency(draft.purchaseAmount),
              emphasize: true,
            ),
          ],
        ),

        const SizedBox(height: 14),

        // =====================================================================
        // RECEIVING DETAILS
        // =====================================================================

        if (receivingCompleted) ...[
          WizardSectionCard(
            title: 'Receiving Details',
            icon: Icons.local_shipping_outlined,
            children: [
              WizardComputedRow(
                label: 'Received at Farm',
                value: _date(
                  draft.dateReceivedAtFarm,
                ),
              ),
              WizardComputedRow(
                label: 'Weight After Arrival',
                value:
                '${_trimZero(draft.totalWeightAfterArrival)} kg',
              ),
              WizardComputedRow(
                label: 'Weight Loss',
                value:
                '${_trimZero(draft.weightLoss)} kg',
              ),
              WizardComputedRow(
                label: 'Mortality',
                value: '${draft.mortality}',
              ),

              if (draft.remarks.trim().isNotEmpty)
                WizardComputedRow(
                  label: 'Remarks',
                  value: draft.remarks,
                ),
            ],
          ),

          const SizedBox(height: 14),

          // ===================================================================
          // TRANSPORT EXPENSES
          // ===================================================================

          WizardSectionCard(
            title: 'Transportation & Other Expenses',
            icon: Icons.local_shipping_outlined,
            children: [
              if (draft.transportCost > 0)
                WizardComputedRow(
                  label: 'Transport Cost',
                  value:
                  _currency(draft.transportCost),
                ),

              if (draft.loadingCharges > 0)
                WizardComputedRow(
                  label: 'Loading Charges',
                  value:
                  _currency(draft.loadingCharges),
                ),

              if (draft.unloadingCharges > 0)
                WizardComputedRow(
                  label: 'Unloading Charges',
                  value:
                  _currency(draft.unloadingCharges),
                ),

              if (draft.otherExpenses > 0)
                WizardComputedRow(
                  label: 'Other Expenses',
                  value:
                  _currency(draft.otherExpenses),
                ),

              if (draft.totalTransportExpenses <= 0)
                WizardComputedRow(
                  label: 'Total Additional Expenses',
                  value: _currency(0),
                ),

              const Divider(
                height: 20,
                color: AppColors.divider,
              ),

              WizardComputedRow(
                label: 'Total Additional Expenses',
                value:
                _currency(draft.totalTransportExpenses),
              ),
            ],
          ),

          const SizedBox(height: 14),
        ],

        // =====================================================================
        // COST SUMMARY
        // =====================================================================

        WizardSectionCard(
          title: 'Cost Summary',
          icon: Icons.currency_rupee_rounded,
          children: [
            WizardComputedRow(
              label: 'Purchase Amount',
              value: _currency(draft.purchaseAmount),
            ),

            WizardComputedRow(
              label: 'Total Expenses',
              value:
              _currency(draft.totalExpenses),
            ),

            const Divider(
              height: 20,
              color: AppColors.divider,
            ),

            WizardComputedRow(
              label: 'Grand Total',
              value:
              _currency(draft.grandTotal),
              emphasize: true,
            ),

            if (receivingCompleted)
              WizardComputedRow(
                label:
                'Effective Cost per KG After Arrival',
                value:
                _currency(draft.effectiveCostPerKg),
                emphasize: true,
              ),
          ],
        ),

        const SizedBox(height: 14),

        // =====================================================================
        // FINAL INFORMATION
        // =====================================================================

        if (!receivingCompleted)
          _pendingInformationCard(),
      ],
    );
  }

  // ===========================================================================
  // RECEIVING STATUS CARD
  // ===========================================================================

  Widget _receivingStatusCard({
    required bool completed,
  }) {
    final Color background =
    completed
        ? AppColors.success.withOpacity(0.10)
        : AppColors.warning.withOpacity(0.10);

    final Color foreground =
    completed
        ? AppColors.success
        : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: foreground.withOpacity(0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: foreground.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              completed
                  ? Icons.check_circle_outline_rounded
                  : Icons.schedule_outlined,
              color: foreground,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  completed
                      ? 'Receiving Details Filled'
                      : 'Receiving Details Pending',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  completed
                      ? 'The goats have been received at the farm and the arrival details will be saved with this purchase.'
                      : 'The purchase will be saved now. You can complete the receiving details later from the Trading Dashboard.',
                  style: AppTheme.body(size: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PENDING INFORMATION
  // ===========================================================================

  Widget _pendingInformationCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: AppTheme.card(radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primaryGreen,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This purchase will appear under Pending Receiving on the Trading Dashboard until the receiving details are completed.',
              style: AppTheme.body(size: 11),
            ),
          ),
        ],
      ),
    );
  }
}