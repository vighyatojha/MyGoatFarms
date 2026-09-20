import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import 'goat_registration_form_screen.dart';

/// Task 2.1 — Select Purchase screen.
///
/// Shows purchases that have completed receiving but still have goats
/// waiting to be registered.
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

    try {
      final id = await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId = id == null || id.trim().isEmpty ? null : id.trim();
        _loadingFarm = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _farmId = null;
        _loadingFarm = false;
      });
    }
  }

  void _openGoatForm(TradingPurchase purchase) {
    final farmId = _farmId;

    if (farmId == null || farmId.isEmpty) return;

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
        titleSpacing: 16,
        title: Text(
          'Select Purchase',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingFarm) {
      return const _PurchaseSkeletonList();
    }

    final farmId = _farmId;

    if (farmId == null || farmId.isEmpty) {
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
          return const _PurchaseSkeletonList();
        }

        final purchases = snapshot.data ?? <TradingPurchase>[];

        if (purchases.isEmpty) {
          return _message(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.primaryGreen,
            title: 'Nothing to Register',
            subtitle: 'All received goats have already been registered.',
          );
        }

        return RefreshIndicator(
          color: AppColors.primaryGreen,
          onRefresh: () async {
            setState(() {});
            await Future<void>.delayed(
              const Duration(milliseconds: 350),
            );
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: purchases.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final purchase = purchases[index];

              return _PurchaseCard(
                purchase: purchase,
                onTap: () => _openGoatForm(purchase),
              );
            },
          ),
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
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          decoration: AppTheme.card(radius: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTheme.heading(size: 15),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
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

// ============================================================================
// PURCHASE CARD
// ============================================================================

class _PurchaseCard extends StatelessWidget {
  final TradingPurchase purchase;
  final VoidCallback onTap;

  const _PurchaseCard({
    required this.purchase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pending = purchase.pendingCount;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: AppTheme.card(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------------------
              // TOP
              // ----------------------------------------------------------------
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.tradingBlue.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.how_to_reg_outlined,
                      color: AppColors.tradingBlue,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          purchase.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.heading(size: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          purchase.sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$pending Pending',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ----------------------------------------------------------------
              // INFO
              // ----------------------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: _InfoItem(
                      icon: GoatIcons.paw,
                      label: 'Goats',
                      value: '${purchase.totalGoats}',
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  Expanded(
                    child: _InfoItem(
                      icon: Icons.calendar_today_outlined,
                      label: 'Purchase',
                      value: DateFormat('dd MMM yyyy')
                          .format(purchase.purchaseDate),
                      color: AppColors.tradingBlue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ----------------------------------------------------------------
              // REGISTRATION PROGRESS
              // ----------------------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.paleGreen,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      color: AppColors.primaryGreen,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${purchase.registeredCount}/${purchase.totalGoats} registered',
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textDark,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Register now',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.primaryGreen,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.primaryGreen,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// INFO ITEM
// ============================================================================

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.body(size: 9),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textDark,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SKELETON LOADING
// ============================================================================

class _PurchaseSkeletonList extends StatelessWidget {
  const _PurchaseSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const _PurchaseSkeletonCard(),
    );
  }
}

class _PurchaseSkeletonCard extends StatelessWidget {
  const _PurchaseSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        children: [
          Row(
            children: [
              _SkeletonBox(
                width: 40,
                height: 40,
                radius: 12,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(
                      width: 110,
                      height: 13,
                      radius: 5,
                    ),
                    SizedBox(height: 6),
                    _SkeletonBox(
                      width: 75,
                      height: 9,
                      radius: 4,
                    ),
                  ],
                ),
              ),
              _SkeletonBox(
                width: 65,
                height: 23,
                radius: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _SkeletonBox(
                      width: 30,
                      height: 30,
                      radius: 9,
                    ),
                    SizedBox(width: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(
                          width: 35,
                          height: 8,
                          radius: 4,
                        ),
                        SizedBox(height: 4),
                        _SkeletonBox(
                          width: 50,
                          height: 10,
                          radius: 4,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    _SkeletonBox(
                      width: 30,
                      height: 30,
                      radius: 9,
                    ),
                    SizedBox(width: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(
                          width: 45,
                          height: 8,
                          radius: 4,
                        ),
                        SizedBox(height: 4),
                        _SkeletonBox(
                          width: 75,
                          height: 10,
                          radius: 4,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _SkeletonBox(
            width: double.infinity,
            height: 38,
            radius: 11,
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.divider.withOpacity(0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}