import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../lots/add_lot_payment_sheet.dart';
import '../lots/lot_detail_screen.dart';
import '../register_goats/goat_registration_form_screen.dart';
import '../sell_from_lot/sell_from_lot_wizard_screen.dart';
import 'purchase_wizard_widgets.dart';

/// Shown after a Purchase Lot is saved.
///
/// Shows the LOT-#### id, where the goats are (At Supplier / At Farm) and
/// the supplier payment status, plus the next steps (Sell From Lot, View
/// Lot, Add Payment) and an OPTIONAL Register Goats action.
///
/// Registering is never required: goats stay anonymous inside the lot and
/// can be sold, transferred or recorded as dead that way. The action only
/// shows when goats are at the farm, and is for someone who wants
/// individual goat records (they go straight to Available Stock). It is
/// also available later from the lot's own screen.
class PurchaseSuccessScreen extends StatefulWidget {
  final TradingPurchase lot;

  const PurchaseSuccessScreen({
    super.key,
    required this.lot,
  });

  @override
  State<PurchaseSuccessScreen> createState() => _PurchaseSuccessScreenState();
}

class _PurchaseSuccessScreenState extends State<PurchaseSuccessScreen> {
  late TradingPurchase _lot = widget.lot;

  Future<String?> _farmId() async {
    final id = await FirestoreService.instance.currentFarmId();

    return id == null || id.trim().isEmpty ? null : id.trim();
  }

  /// Re-reads the lot so Paid / Balance Due / Status are current after a
  /// payment or sale made from this screen.
  Future<void> _refresh() async {
    final farmId = await _farmId();

    if (farmId == null) return;

    final fresh = await TradingService.instance.getPurchase(farmId, _lot.id);

    if (!mounted || fresh == null) return;

    setState(() => _lot = fresh);
  }

  Future<void> _sellFromLot() async {
    await Navigator.of(context).push(
      fastRoute(SellFromLotWizardScreen(initialLot: _lot)),
    );

    await _refresh();
  }

  /// Optional: opens the registration form for this lot's goats, then
  /// re-reads the lot so the counts on this screen are current.
  Future<void> _registerGoats() async {
    final farmId = await _farmId();

    if (farmId == null || !mounted) return;

    await Navigator.of(context).push(
      fastRoute(
        GoatRegistrationFormScreen(farmId: farmId, purchase: _lot),
      ),
    );

    await _refresh();
  }

  Future<void> _viewLot() async {
    final farmId = await _farmId();

    if (farmId == null || !mounted) return;

    await Navigator.of(context).push(
      fastRoute(LotDetailScreen(farmId: farmId, lotDocId: _lot.id)),
    );

    await _refresh();
  }

  Future<void> _addPayment() async {
    final farmId = await _farmId();

    if (farmId == null || !mounted) return;

    final saved = await showAddLotPaymentSheet(
      context: context,
      farmId: farmId,
      lot: _lot,
    );

    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lot = _lot;

    final atSupplier = lot.location == LotLocation.atSupplier;

    final Color statusColor;
    switch (lot.paymentStatus) {
      case 'Paid':
        statusColor = AppColors.success;
        break;
      case 'Partial':
        statusColor = const Color(0xFFB26A00);
        break;
      default:
        statusColor = AppColors.error;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lot Saved'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          child: Column(
            children: [
              const SizedBox(height: 20),

              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 64,
                  color: AppColors.primaryGreen,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Purchase Lot Created',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                atSupplier
                    ? '${lot.totalGoats} goats are with the supplier. You '
                    'can sell from the lot now, or receive the goats when '
                    'they arrive.'
                    : '${lot.receivedAliveQty} goats are at the farm and '
                    'ready to sell or transfer.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 28),

              // Lot ID card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Lot ID',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lot.lotId,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lot.sellerName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Where the goats are + payment
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(radius: 16),
                child: Column(
                  children: [
                    WizardComputedRow(
                      label: 'Supplier',
                      value: lot.sellerName,
                    ),
                    WizardComputedRow(
                      label: 'Purchase Date',
                      value: wizardDate(lot.purchaseDate),
                    ),
                    WizardComputedRow(
                      label: 'Goats in Lot',
                      value: '${lot.totalGoats}',
                    ),
                    WizardComputedRow(
                      label: 'Total Weight',
                      value:
                      '${PurchaseCosting.formatNumber(lot.totalWeightAtPurchase)} kg',
                    ),
                    WizardComputedRow(
                      label: 'Purchase Price / KG',
                      value: wizardCurrency(lot.pricePerKg),
                    ),
                    WizardComputedRow(
                      label: 'Remaining Goats',
                      value: '${lot.remainingQty}',
                    ),
                    WizardComputedRow(
                      label: 'Lot Status',
                      value: lot.isActive ? 'Active' : 'Completed',
                    ),
                    WizardComputedRow(
                      label: 'Location',
                      value: lot.location.label,
                    ),
                    if (lot.expectedDeliveryDate != null && atSupplier)
                      WizardComputedRow(
                        label: 'Expected Delivery',
                        value: wizardDate(lot.expectedDeliveryDate!),
                      ),
                    const Divider(height: 18, color: AppColors.divider),
                    WizardComputedRow(
                      label: 'Purchase Amount',
                      value: wizardCurrency(lot.purchaseAmount),
                    ),
                    WizardComputedRow(
                      label: 'Paid to Supplier',
                      value: wizardCurrency(lot.paidAmount),
                    ),
                    WizardComputedRow(
                      label: 'Balance Due',
                      value: wizardCurrency(lot.dueAmount),
                      emphasize: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Text(
                            'Payment Status',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              supplierPaymentStatusLabel(lot.paymentStatus),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              if (lot.availableForSaleQty > 0) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _sellFromLot,
                    icon: const Icon(Icons.sell_outlined),
                    label: const Text(
                      'Sell From Lot',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.tradingBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Optional — nothing here is required to use the lot.
              if (lot.farmAvailableQty > 0) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _registerGoats,
                    icon: const Icon(Icons.app_registration_rounded, size: 18),
                    label: const Text(
                      'Register Goats (optional)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: const BorderSide(color: AppColors.primaryGreen),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Only if you want individual goat records. You can do '
                      'this any time from the lot.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _viewLot,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text(
                          'View Lot',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          side: const BorderSide(color: AppColors.primaryGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (lot.dueAmount >= 0.01) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _addPayment,
                          icon: const Icon(
                            Icons.payments_outlined,
                            size: 18,
                          ),
                          label: const Text(
                            'Add Payment',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryGreen,
                            side: const BorderSide(
                              color: AppColors.primaryGreen,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil(
                          (route) => route.isFirst,
                    );
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text(
                    'Go to Trading',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}