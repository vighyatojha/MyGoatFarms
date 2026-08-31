import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../multi_goat_checkout_screen.dart';

/// Checkout tab — shows this goat's current state (weight, health,
/// photo) as a final confirmation summary, then hands off to the real
/// checkout flow ([MultiGoatCheckoutScreen], already built and used
/// elsewhere) with this goat pre-selected and selection locked, so
/// checkout logic stays in one place rather than being duplicated here.
class GoatCheckoutTab extends StatelessWidget {
  final PalaiGoat goat;

  const GoatCheckoutTab({super.key, required this.goat});

  Future<void> _startCheckout(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiGoatCheckoutScreen(
          customerId: goat.customerId,
          initialSelectedGoats: [goat],
          allowSelection: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (goat.isCheckedOut) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 32, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text('Already checked out', style: AppTheme.heading(size: 14)),
              const SizedBox(height: 6),
              Text(
                goat.checkOutDate != null
                    ? 'Checked out on ${DateFormat('d MMM yyyy').format(goat.checkOutDate!)}.'
                    : 'This goat has been checked out of Palai.',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 11.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final currentWeight = goat.currentWeight ?? goat.weightAtCheckIn;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Container(
          decoration: AppTheme.card(radius: 14),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Before you check out', style: AppTheme.heading(size: 13)),
              const SizedBox(height: 8),
              Text(
                'Checkout confirms this goat\'s final weight, health status, and photo, then closes out its Palai billing. Review the summary below, then continue to Checkout.',
                style: AppTheme.body(size: 11.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              _row('Current Weight', '${currentWeight.toStringAsFixed(1)} kg'),
              _row('Health Status', goat.healthStatus.isNotEmpty ? goat.healthStatus : 'Not recorded'),
              _row('Arrival Date', DateFormat('d MMM yyyy').format(goat.farmArrivalDate ?? goat.checkInDate)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startCheckout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Continue to Checkout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: AppTheme.body(size: 11.5, color: AppColors.textMuted))),
          Expanded(flex: 3, child: Text(value, style: AppTheme.body(size: 12, weight: FontWeight.w500))),
        ],
      ),
    );
  }
}