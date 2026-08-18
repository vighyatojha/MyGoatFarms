import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

import '../../../app_theme.dart';
import '../../../models/own_farm_models.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/fast_route.dart';
import '../../home/widgets/home_widgets.dart';
import 'add_own_farm_goat_screen.dart';
import 'own_farm_goat_list_screen.dart';

/// Dashboard content for the "Own Farm Palai" tab — goats owned by My
/// Goat Farms rather than boarded for a customer. Embedded directly
/// inside [PalaiScreen]'s scroll view (no Scaffold/AppBar of its own) so
/// switching between "Customer Palai" and "Own Farm Palai" feels instant.
class OwnFarmPalaiContent extends StatelessWidget {
  final String farmId;
  const OwnFarmPalaiContent({super.key, required this.farmId});

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeInUp(
          duration: const Duration(milliseconds: 200),
          child: StreamBuilder<List<OwnFarmGoat>>(
            stream: FirestoreService.instance.ownFarmGoatsStream(farmId),
            builder: (context, snap) {
              final goats = snap.data ?? [];
              final healthy = goats.where((g) => g.healthStatus == 'Healthy').length;
              final avgWeight = goats.isEmpty ? 0 : goats.fold<double>(0, (s, g) => s + g.currentWeight) / goats.length;
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          icon: Icons.pets,
                          label: 'Total Farm Goats',
                          value: snap.hasData ? '${goats.length}' : '—',
                          color: AppColors.primaryGreen,
                          onTap: () => Navigator.of(context).push(fastRoute(const OwnFarmGoatListScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          icon: Icons.health_and_safety_outlined,
                          label: 'Healthy Goats',
                          value: snap.hasData ? '$healthy' : '—',
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          icon: Icons.monitor_weight_outlined,
                          label: 'Avg. Weight',
                          value: snap.hasData ? '${avgWeight.toStringAsFixed(1)} kg' : '—',
                          color: AppColors.stockTeal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StreamBuilder<double>(
                          stream: FirestoreService.instance.ownFarmExpensesThisMonthStream(farmId),
                          builder: (context, expSnap) => StatCard(
                            icon: Icons.currency_rupee,
                            label: 'Expenses (Month)',
                            value: expSnap.hasData ? '₹${expSnap.data!.toStringAsFixed(0)}' : '—',
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Text('Quick Actions', style: AppTheme.heading(size: 16)),
        const SizedBox(height: 12),
        FadeInUp(
          duration: const Duration(milliseconds: 220),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: [
              ModuleTile(
                icon: Icons.pets,
                label: 'Register',
                sub: 'Goat',
                color: AppColors.primaryGreen,
                onTap: () => Navigator.of(context).push(fastRoute(const AddOwnFarmGoatScreen())),
              ),
              ModuleTile(
                icon: Icons.list_alt,
                label: 'Goat List',
                sub: 'All',
                color: AppColors.info,
                onTap: () => Navigator.of(context).push(fastRoute(const OwnFarmGoatListScreen())),
              ),
              ModuleTile(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight',
                sub: 'Tracking',
                color: AppColors.stockTeal,
                onTap: () => Navigator.of(context).push(fastRoute(const OwnFarmGoatListScreen())),
              ),
              ModuleTile(
                icon: Icons.favorite_border,
                label: 'Health',
                sub: 'Records',
                color: AppColors.breedingPurple,
                onTap: () => Navigator.of(context).push(fastRoute(const OwnFarmGoatListScreen())),
              ),
              ModuleTile(
                icon: Icons.family_restroom,
                label: 'Breeding',
                sub: 'Details',
                color: AppColors.breedingPurple,
                onTap: () => Navigator.of(context).push(fastRoute(const OwnFarmGoatListScreen())),
              ),
              ModuleTile(
                icon: Icons.currency_rupee,
                label: 'Expenses',
                sub: 'Feed/Health',
                color: AppColors.warning,
                onTap: () => Navigator.of(context).push(fastRoute(const OwnFarmGoatListScreen())),
              ),
              ModuleTile(
                icon: Icons.summarize_outlined,
                label: 'Reports',
                sub: 'Farm',
                color: AppColors.darkGreen,
                onTap: () => _comingSoon(context, 'Own Farm reports'),
              ),
              ModuleTile(
                icon: Icons.more_horiz,
                label: 'More',
                sub: '',
                color: AppColors.textGrey,
                onTap: () => _comingSoon(context, 'More options'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
