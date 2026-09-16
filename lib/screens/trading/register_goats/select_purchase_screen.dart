import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import 'goat_registration_form_screen.dart';

/// Task 2.1 — Select Purchase screen.
///
/// Lists purchases that still have goats waiting to be registered
/// (`pendingCount > 0`, receiving already completed). Tapping one opens
/// the goat registration form for that purchase.
class SelectPurchaseScreen extends StatefulWidget {
  const SelectPurchaseScreen({super.key});

  @override
  State<SelectPurchaseScreen> createState() => _SelectPurchaseScreenState();
}

class _SelectPurchaseScreenState extends State<SelectPurchaseScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    if (mounted) {
      setState(() {
        _loadingFarm = true;
      });
    }

    final id = await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    setState(() {
      _farmId = id == null || id.trim().isEmpty ? null : id.trim();
      _loadingFarm = false;
    });
  }

  void _openGoatForm(TradingPurchase purchase) {
    final farmId = _farmId;
    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        GoatRegistrationFormScreen(
          farmId: farmId,
          purchase: purchase,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Select Purchase', style: AppTheme.heading(size: 17)),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loadingFarm) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    final farmId = _farmId;

    if (farmId == null) {
      return FarmNotLinkedState(
        buttonColor: AppColors.primaryGreen,
        onRetry: _loadFarm,
      );
    }

    return StreamBuilder<List<TradingPurchase>>(
      stream: TradingService.instance.pendingRegistrationStream(farmId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message(
            icon: Icons.error_outline,
            iconColor: AppColors.error,
            title: 'Unable to load purchases',
            subtitle: 'Please try again.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        }

        final purchases = snapshot.data ?? [];

        if (purchases.isEmpty) {
          return _message(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.primaryGreen,
            title: 'Nothing to Register',
            subtitle:
            'All received goats have already been registered.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: purchases.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _PurchaseCard(
              purchase: purchases[index],
              onTap: () => _openGoatForm(purchases[index]),
            );
          },
        );
      },
    );
  }

  Widget _message({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 14),
            Text(title, style: AppTheme.heading(size: 15)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  final TradingPurchase purchase;
  final VoidCallback onTap;

  const _PurchaseCard({required this.purchase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.card(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.tradingBlue.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.how_to_reg_outlined,
                    color: AppColors.tradingBlue,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(purchase.id, style: AppTheme.heading(size: 16)),
                      const SizedBox(height: 2),
                      Text(
                        purchase.sellerName,
                        style: AppTheme.body(size: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey.withOpacity(0.6),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _stat(
                    '${purchase.totalGoats} Goats',
                    Icons.pets_outlined,
                  ),
                ),
                Expanded(
                  child: _stat(
                    DateFormat('dd MMM yyyy').format(purchase.purchaseDate),
                    Icons.calendar_today_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${purchase.registeredCount}/${purchase.totalGoats} Registered — '
                    '${purchase.pendingCount} Pending Registration',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primaryGreen),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 12, color: AppColors.textDark),
          ),
        ),
      ],
    );
  }
}