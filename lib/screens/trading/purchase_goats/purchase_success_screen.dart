import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_model.dart';
import 'purchase_wizard_widgets.dart';

/// Shown after a Purchase Lot is saved.
///
/// Shows the LOT-#### id, where the goats are (At Supplier / At Farm) and
/// the supplier payment status. There is deliberately no "register goats"
/// action: goats stay anonymous inside the lot and are only registered
/// when transferred to a Palai.
class PurchaseSuccessScreen extends StatelessWidget {
  final TradingPurchase lot;

  const PurchaseSuccessScreen({
    super.key,
    required this.lot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  color: AppColors.primaryGreen.withOpacity(0.12),
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
                  color: AppColors.primaryGreen.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primaryGreen.withOpacity(0.18),
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
                      label: 'Goats in Lot',
                      value: '${lot.totalGoats}',
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
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              lot.paymentStatus,
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

              const SizedBox(height: 32),

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