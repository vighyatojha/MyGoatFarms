import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';

/// Shared fallback shown across every screen when farm resolution
/// (`currentFarmId()` / `getFarmForUser()`) finished but came back null —
/// i.e. this signed-in account isn't linked to any farm as either an
/// owner or a partner.
///
/// In debug builds this also shows [FirestoreService.instance
/// .lastFarmResolutionError], which explains *why* resolution failed
/// (missing index, denied read, dangling partner doc, etc.) — otherwise
/// "not linked" looks identical whether the account genuinely isn't
/// linked or something is silently broken. That detail is hidden in
/// release builds so end users never see raw Firebase error text.
class FarmNotLinkedState extends StatelessWidget {
  final VoidCallback onRetry;
  final Color buttonColor;

  const FarmNotLinkedState({
    super.key,
    required this.onRetry,
    this.buttonColor = AppColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final debugDetail = FirestoreService.instance.lastFarmResolutionError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off, size: 48, color: AppColors.textGrey),
            const SizedBox(height: 16),
            Text(
              "This account isn't linked to any farm yet",
              style: AppTheme.heading(size: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'If you were added as a partner, ask the farm owner to '
                  'double-check your invite, or pull down to refresh.',
              style: AppTheme.body(size: 13, color: AppColors.textGrey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: buttonColor),
              child: const Text('Try again', style: TextStyle(color: Colors.white)),
            ),
            if (kDebugMode && debugDetail != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEBUG ONLY — why resolution failed:',
                      style: AppTheme.body(size: 11, color: AppColors.textGrey)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      debugDetail,
                      style: AppTheme.body(size: 11, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
