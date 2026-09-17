import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../widgets/fast_route.dart';
import '../own_palai/move_to_own_palai_screen.dart';

/// Task 2.6 — Registration Completed screen.
///
/// Shown once a purchase's `pendingCount` reaches zero (every goat from
/// that purchase has been registered). Per the plan: shows Purchase ID,
/// Date, Total/Registered counts, registration date, and 4 exit
/// options — View Goat Stock, Move to Own Palai (Task 2.1, phase 3),
/// Sell Goat (stub for phase 3), Back to Trading.
class RegistrationCompletedScreen extends StatelessWidget {
  final String farmId;
  final TradingPurchase purchase;

  const RegistrationCompletedScreen({
    super.key,
    required this.farmId,
    required this.purchase,
  });

  void _phase3Stub(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming in a later phase.'),
        backgroundColor: AppColors.darkGreen,
      ),
    );
  }

  void _viewGoatStock(BuildContext context) {
    // Wired up once the Goat Stock screen exists (Task 3.1, next pair).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Goat Stock screen is coming next.'),
        backgroundColor: AppColors.darkGreen,
      ),
    );
  }

  void _moveToOwnPalai(BuildContext context) {
    Navigator.of(context).push(
      fastRoute(MoveToOwnPalaiScreen(farmId: farmId)),
    );
  }

  void _backToTrading(BuildContext context) {
    // Matches PurchaseSuccessScreen's "Go to Trading" — returns to the
    // root of the Trading tab's navigation stack.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registration Completed'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          child: Column(
            children: [
              const SizedBox(height: 12),

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
                'Registration Completed',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                'All goats from this purchase have been registered and '
                    'added to your Goat Stock.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 28),

              // Purchase summary card
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
                      'Purchase ID',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      purchase.id,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryStat(
                            'Purchase Date',
                            DateFormat('dd MMM yyyy').format(
                              purchase.purchaseDate,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _summaryStat(
                            'Registered On',
                            DateFormat('dd MMM yyyy').format(DateTime.now()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryStat(
                            'Total Goats',
                            '${purchase.totalGoats}',
                          ),
                        ),
                        Expanded(
                          child: _summaryStat(
                            'Registered',
                            '${purchase.registeredCount}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // View Goat Stock
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _viewGoatStock(context),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text(
                    'View Goat Stock',
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

              // Move to Own Palai (phase 3 stub)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _moveToOwnPalai(context),
                  icon: const Icon(Icons.holiday_village_outlined),
                  label: const Text(
                    'Move to Own Palai',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.tradingBlue,
                    side: const BorderSide(color: AppColors.tradingBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Sell Goat (phase 3 stub)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _phase3Stub(context, 'Sell Goat'),
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text(
                    'Sell Goat',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.tradingBlue,
                    side: const BorderSide(color: AppColors.tradingBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Back to Trading
              SizedBox(
                width: double.infinity,
                height: 50,
                child: TextButton(
                  onPressed: () => _backToTrading(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textGrey,
                  ),
                  child: const Text(
                    'Back to Trading',
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

  Widget _summaryStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}