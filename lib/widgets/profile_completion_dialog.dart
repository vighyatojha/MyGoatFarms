import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../l10n/app_strings.dart';

/// The nudge shown on Home while the farm profile is under 100% complete.
///
/// Deliberately not dismissible by tapping outside (`barrierDismissible:
/// false`) — the person has to make an explicit choice — but "Remind me
/// later" always lets them get on with their day. [HomeScreen] re-shows
/// this every time the app is opened while the profile is still
/// incomplete, and again immediately after they back out of the Profile
/// screen without finishing it.
Future<void> showProfileCompletionDialog(
  BuildContext context, {
  required int percent,
  required VoidCallback onCompleteNow,
  required VoidCallback onLater,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProfileCompletionDialog(
      percent: percent,
      onCompleteNow: onCompleteNow,
      onLater: onLater,
    ),
  );
}

class _ProfileCompletionDialog extends StatelessWidget {
  final int percent;
  final VoidCallback onCompleteNow;
  final VoidCallback onLater;

  const _ProfileCompletionDialog({
    required this.percent,
    required this.onCompleteNow,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '$percent%',
                    style: AppTheme.heading(size: 19, color: AppColors.darkGreen),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                AppStrings.t(context, 'not_complete_title'),
                style: AppTheme.heading(size: 17),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.t(context, 'not_complete_body'),
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 13),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 10,
                  backgroundColor: AppColors.lightGreen,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onCompleteNow();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(
                    AppStrings.t(context, 'complete_now'),
                    style: AppTheme.heading(size: 15, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onLater();
                },
                child: Text(
                  AppStrings.t(context, 'remind_later'),
                  style: AppTheme.body(size: 13, color: AppColors.textGrey, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
