import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_draft.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 4 — Purchase Summary.
///
/// Final review before saving, laid out the way the Trading flow PDF asks:
///
///   Weight Summary  -> goats, weight at purchase, weight after arrival,
///                      weight loss, mortality
///   Cost Summary    -> purchase amount, each expense, total expenses,
///                      grand total, effective cost per KG after arrival
///
/// Receiving can be completed now or left pending. When it is pending the
/// summary is built from [PurchaseDraft.finalCosting], which ignores anything
/// typed earlier on Step 3, so it only ever shows what will really be saved.
///
/// The actual Firestore save happens only through [save].
class Step4Summary extends StatefulWidget {
  final PurchaseDraft draft;

  final ValueChanged<TradingPurchase> onSaved;

  /// Lets the wizard's bottom bar show a spinner and disable its buttons
  /// while saving. (The bar lives in the parent, so it cannot see this
  /// State's `_saving` on its own — reading it in the parent's build never
  /// triggered a rebuild, which is why the spinner never appeared before.)
  final ValueNotifier<bool>? savingNotifier;

  const Step4Summary({
    super.key,
    required this.draft,
    required this.onSaved,
    this.savingNotifier,
  });

  @override
  State<Step4Summary> createState() => Step4SummaryState();
}

class Step4SummaryState extends State<Step4Summary> {
  bool _saving = false;

  /// True once the purchase is saved and navigation has started, so the
  /// buttons never re-enable during the page transition (which could allow
  /// a second, duplicate save).
  bool _completed = false;

  bool get isSaving => _saving;

  void _setSaving(bool value) {
    _saving = value;
    widget.savingNotifier?.value = value;

    if (mounted) setState(() {});
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;

    wizardSnack(context, text, error: error);
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> save() async {
    if (_saving) return;

    _setSaving(true);

    final draft = widget.draft;

    try {
      final farmId = await FirestoreService.instance.currentFarmId();

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
      final receivingStatus =
      draft.isReceivingCompleted ? 'completed' : 'pending';

      final completed = receivingStatus == 'completed';

      final saved = await TradingService.instance.savePurchase(
        farmId: farmId,

        // Seller
        sellerName: draft.sellerName.trim(),
        mobile: draft.mobile.trim(),
        market: draft.market.trim(),
        vehicleNumber: draft.vehicleNumber.trim(),
        purchaseDate: draft.purchaseDate,

        // Purchase
        totalGoats: draft.totalGoats,
        totalWeightAtPurchase: draft.totalWeightAtPurchase,
        pricePerKg: draft.pricePerKg,
        maleGoats: draft.maleGoats,
        femaleGoats: draft.femaleGoats,

        // Payment
        paymentMethod: draft.paymentMethod,

        // Receiving
        receivingStatus: receivingStatus,
        dateReceivedAtFarm: completed ? draft.dateReceivedAtFarm : null,
        totalWeightAfterArrival:
        completed ? draft.totalWeightAfterArrival : null,
        mortality: completed ? draft.mortality : 0,
        remarks: completed ? draft.remarks : '',

        // Transport / other expenses
        transportCost: completed ? draft.transportCost : 0,
        loadingCharges: completed ? draft.loadingCharges : 0,
        unloadingCharges: completed ? draft.unloadingCharges : 0,
        otherExpenses: completed ? draft.otherExpenses : 0,
      );

      if (!mounted) return;

      _completed = true;
      widget.onSaved(saved);
    } on TimeoutException {
      _message(
        'Connection is taking too long. Please try again.',
        error: true,
      );
    } on ArgumentError catch (e) {
      _message(
        e.message?.toString() ?? 'Please check the purchase details.',
        error: true,
      );
    } catch (e) {
      _message(
        FirestoreService.instance.describeError(e),
        error: true,
      );
    } finally {
      if (mounted && !_completed) {
        _setSaving(false);
      }
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final c = draft.finalCosting;
    final completed = draft.isReceivingCompleted;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _receivingStatusCard(completed: completed),

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
              value: draft.sellerName.trim(),
            ),
            WizardComputedRow(
              label: 'Mobile',
              value: draft.mobile.trim(),
            ),
            if (draft.market.trim().isNotEmpty)
              WizardComputedRow(
                label: 'Market',
                value: draft.market.trim(),
              ),
            if (draft.vehicleNumber.trim().isNotEmpty)
              WizardComputedRow(
                label: 'Vehicle No.',
                value: draft.vehicleNumber.trim(),
              ),
            WizardComputedRow(
              label: 'Purchase Date',
              value: wizardDate(draft.purchaseDate),
            ),
            WizardComputedRow(
              label: 'Payment Method',
              value: draft.paymentMethod,
            ),
          ],
        ),

        const SizedBox(height: 14),

        // =====================================================================
        // WEIGHT SUMMARY
        // =====================================================================

        WizardSectionCard(
          title: 'Weight Summary',
          icon: Icons.scale_outlined,
          children: [
            WizardComputedRow(
              label: 'Total Goats Purchased',
              value: '${c.totalGoats}',
            ),
            if (draft.maleGoats > 0 || draft.femaleGoats > 0)
              WizardComputedRow(
                label: 'Male / Female',
                value: '${draft.maleGoats} Male · '
                    '${draft.femaleGoats} Female',
              ),
            WizardComputedRow(
              label: 'Weight at Purchase',
              value: '${PurchaseCosting.formatNumber(c.weightAtPurchase)} kg',
            ),
            if (completed) ...[
              WizardComputedRow(
                label: 'Received at Farm',
                value: wizardDate(draft.dateReceivedAtFarm),
              ),
              WizardComputedRow(
                label: 'Weight After Arrival',
                value:
                '${PurchaseCosting.formatNumber(c.weightAfterArrival)} kg',
              ),
              WizardComputedRow(
                label: 'Weight Loss',
                value: '${PurchaseCosting.formatNumber(c.weightLoss)} kg '
                    '(${PurchaseCosting.formatNumber(c.weightLossPercent)}%)',
              ),
              WizardComputedRow(
                label: 'Mortality',
                value: c.safeMortality == 0
                    ? 'None'
                    : '${c.safeMortality} '
                    'goat${c.safeMortality == 1 ? '' : 's'}',
              ),
              const Divider(height: 18, color: AppColors.divider),
              WizardComputedRow(
                label: 'Goats to Register',
                value: '${c.survivingGoats}',
                emphasize: true,
              ),
              if (draft.remarks.trim().isNotEmpty)
                WizardComputedRow(
                  label: 'Remarks',
                  value: draft.remarks.trim(),
                ),
            ] else ...[
              const WizardComputedRow(
                label: 'Weight After Arrival',
                value: 'Pending',
              ),
              const WizardComputedRow(
                label: 'Mortality',
                value: 'Pending',
              ),
            ],
          ],
        ),

        const SizedBox(height: 14),

        // =====================================================================
        // COST SUMMARY
        // =====================================================================

        WizardSectionCard(
          title: 'Cost Summary',
          icon: Icons.currency_rupee_rounded,
          children: [
            WizardComputedRow(
              label:
              'Purchase Amount\n${PurchaseCosting.formatNumber(c.weightAtPurchase)} kg × ${wizardCurrency(c.pricePerKg)}',
              value: wizardCurrency(c.purchaseAmount),
            ),
            if (completed) ...[
              WizardComputedRow(
                label: 'Transport Cost',
                value: wizardCurrency(c.transportCost),
              ),
              WizardComputedRow(
                label: 'Loading Charges',
                value: wizardCurrency(c.loadingCharges),
              ),
              WizardComputedRow(
                label: 'Unloading Charges',
                value: wizardCurrency(c.unloadingCharges),
              ),
              WizardComputedRow(
                label: 'Other Expenses',
                value: wizardCurrency(c.otherExpenses),
              ),
              WizardComputedRow(
                label: 'Total Expenses',
                value: wizardCurrency(c.totalExpenses),
              ),
            ],
            const Divider(height: 18, color: AppColors.divider),
            WizardComputedRow(
              label: 'Grand Total',
              value: wizardCurrency(c.grandTotal),
              emphasize: true,
            ),
            if (completed) ...[
              WizardComputedRow(
                label: 'Effective Cost per KG After Arrival',
                value: wizardCurrency(c.effectiveCostPerKg),
                emphasize: true,
              ),
              WizardComputedRow(
                label: 'Cost per Surviving Goat',
                value: wizardCurrency(c.costPerSurvivingGoat),
              ),
              if (c.costIncreasePerKg > 0) ...[
                const SizedBox(height: 6),
                WizardNote(
                  'Each kg costs ${wizardCurrency(c.costIncreasePerKg)} more '
                      'than the ${wizardCurrency(c.pricePerKg)} / kg paid to '
                      'the seller, after transport and weight loss.',
                ),
              ],
              if (c.safeMortality > 0) ...[
                const SizedBox(height: 8),
                WizardNote(
                  '${c.safeMortality} goat${c.safeMortality == 1 ? '' : 's'} '
                      'lost in transit — about '
                      '${wizardCurrency(c.mortalityLoss)} of the purchase '
                      'amount, already included in the Grand Total.',
                  tone: WizardNoteTone.warning,
                ),
              ],
            ],
          ],
        ),

        if (!completed) ...[
          const SizedBox(height: 14),
          _pendingInformationCard(),
        ],
      ],
    );
  }

  // ===========================================================================
  // RECEIVING STATUS CARD
  // ===========================================================================

  Widget _receivingStatusCard({required bool completed}) {
    final Color foreground =
    completed ? AppColors.success : const Color(0xFFB26A00);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: foreground.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withOpacity(0.18)),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  completed
                      ? 'Receiving Details Filled'
                      : 'Receiving Details Pending',
                  style: AppTheme.heading(size: 14, color: foreground),
                ),
                const SizedBox(height: 4),
                Text(
                  completed
                      ? 'Arrival weight, mortality and transport costs are '
                      'saved with this purchase.'
                      : 'The purchase will be saved now. Complete the '
                      'receiving details later from the Trading Dashboard.',
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
              'This purchase will appear under Pending Receiving on the '
                  'Trading Dashboard. Transport costs, mortality and the '
                  'effective cost per KG are worked out when you complete '
                  'receiving. Goats can be registered after that.',
              style: AppTheme.body(size: 11),
            ),
          ),
        ],
      ),
    );
  }
}