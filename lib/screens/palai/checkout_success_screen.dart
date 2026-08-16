import 'dart:typed_data';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../services/pdf_bill_service.dart';
import '../../widgets/fast_route.dart';
import 'checkout_details_screen.dart';

/// Shown right after a goat is checked out: a "popping" check-mark
/// animation, then "View Details" and "Share" (shares the final bill as
/// a PDF).
class CheckoutSuccessScreen extends StatelessWidget {
  final PalaiGoat goat;
  final double finalWeight;
  final String healthStatus;
  final String deliveryStatus;
  final double totalCharges;
  final Uint8List? beforeImage;
  final Uint8List? afterImage;
  final BillSettings billSettings;

  const CheckoutSuccessScreen({
    super.key,
    required this.goat,
    required this.finalWeight,
    required this.healthStatus,
    required this.deliveryStatus,
    required this.totalCharges,
    this.beforeImage,
    this.afterImage,
    this.billSettings = const BillSettings(),
  });

  Future<void> _share(BuildContext context) async {
    try {
      await PdfBillService.instance.shareBill(
        goat: goat,
        finalWeight: finalWeight,
        healthStatus: healthStatus,
        deliveryStatus: deliveryStatus,
        totalCharges: totalCharges,
        billSettings: billSettings,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share the bill. Please try again.'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElasticIn(
                  duration: const Duration(milliseconds: 700),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryGreen),
                    child: const Icon(Icons.check, color: Colors.white, size: 60),
                  ),
                ),
                const SizedBox(height: 26),
                FadeInUp(
                  delay: const Duration(milliseconds: 250),
                  duration: const Duration(milliseconds: 300),
                  child: Text('Checked Out!', style: AppTheme.heading(size: 22)),
                ),
                const SizedBox(height: 8),
                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    '${goat.goatCode} has been checked out successfully.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(size: 13),
                  ),
                ),
                const SizedBox(height: 36),
                FadeInUp(
                  delay: const Duration(milliseconds: 350),
                  duration: const Duration(milliseconds: 300),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(fastRoute(CheckoutDetailsScreen(
                            goat: goat,
                            finalWeight: finalWeight,
                            healthStatus: healthStatus,
                            deliveryStatus: deliveryStatus,
                            totalCharges: totalCharges,
                            beforeImage: beforeImage,
                            afterImage: afterImage,
                            billSettings: billSettings,
                          ))),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            side: const BorderSide(color: AppColors.primaryGreen),
                          ),
                          child: Text('View Details', style: AppTheme.heading(size: 13, color: AppColors.primaryGreen)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _share(context),
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: Text('Share', style: AppTheme.heading(size: 13, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  duration: const Duration(milliseconds: 300),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    child: Text('Done', style: AppTheme.body(size: 13, color: AppColors.textGrey)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
