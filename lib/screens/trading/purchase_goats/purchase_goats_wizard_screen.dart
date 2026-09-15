import 'package:flutter/material.dart';

import '../../../../app_theme.dart';

/// Purchase Goats — Feature 2 of the Trading Module (4-step wizard).
///
/// Placeholder for now — built out in Task 3 (Section 3 of the phase-1
/// plan: shared PurchaseDraft + stepper controller, Steps 1-4, Save
/// logic, Success screen).
class PurchaseGoatsWizardScreen extends StatelessWidget {
  const PurchaseGoatsWizardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textDark),
                  ),
                  const SizedBox(width: 10),
                  Text('Purchase Goats', style: AppTheme.heading(size: 18)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.tradingBlue.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: AppColors.tradingBlue,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'The 4-step purchase wizard is coming next —\n'
                            'Seller Details, Purchase Details, Receiving &\n'
                            'Transport, and Summary.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 13, color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}