import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/partner_access_service.dart';

/// Wraps a screen (or part of one) so it only shows [child] when the
/// signed-in account is allowed [permission] — see
/// [PartnerAccessService.allows] for what "allowed" means for the farm
/// owner vs. an invited partner.
///
/// This is the first place in the app that enforces a
/// [PartnerPermissionKeys] value in the UI; no other screen (old or new)
/// currently checks permissions at all. Used as a whole-screen guard —
/// for gating one button or action inline instead, call
/// `PartnerAccessService.instance.allows(...)` directly and disable the
/// widget, the way [LotDetailScreen]'s action buttons already do for
/// quantity-based rules.
class PermissionGate extends StatelessWidget {
  final String permission;
  final Widget child;

  /// Shown instead of [child] when access is denied. Defaults to a
  /// generic "not authorized" panel.
  final String? deniedMessage;

  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.deniedMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (PartnerAccessService.instance.allows(permission)) {
      return child;
    }

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Not Available'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 48,
                color: AppColors.textGrey,
              ),
              const SizedBox(height: 16),
              Text(
                'You don\u2019t have access to this',
                textAlign: TextAlign.center,
                style: AppTheme.heading(size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                deniedMessage ??
                    'Ask the farm owner to grant this permission on your '
                        'partner account.',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}