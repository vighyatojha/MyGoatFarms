import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import 'move_to_own_palai_screen.dart';

/// Task 2.2 — Own Palai list screen.
///
/// Same card-list pattern as the (not-yet-built) Goat Stock list —
/// streams `tradingGoats` filtered to Own Palai goats via
/// [GoatService.ownPalaiGoatsStream] and shows each as a card (Photo,
/// Goat ID, Breed, Weight, Status), per the phase 3 plan.
///
/// These are the exact same `tradingGoats/{goatId}` docs Goat Stock
/// shows — nothing is "carried forward" or duplicated (Task 2.3);
/// they're just filtered to `currentStatus == 'Own Palai'` here.
class OwnPalaiListScreen extends StatefulWidget {
  const OwnPalaiListScreen({super.key});

  @override
  State<OwnPalaiListScreen> createState() => _OwnPalaiListScreenState();
}

class _OwnPalaiListScreenState extends State<OwnPalaiListScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  void _loadFarm() {
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) {
        setState(() {
          _farmId = id;
          _loadingFarm = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildNotLinkedState() {
    return FarmNotLinkedState(
      buttonColor: AppColors.tradingBlue,
      onRetry: () {
        setState(() => _loadingFarm = true);
        _loadFarm();
      },
    );
  }

  Color _healthColor(String healthStatus) {
    switch (healthStatus) {
      case 'Healthy':
        return AppColors.success;
      case 'Under Treatment':
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }

  void _openProfile(Goat goat) {
    // Feature 6 (Own Palai Goat Profile) is the next pair — wire this
    // up to the real profile screen once it exists.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${goat.id} profile is coming next.'),
        backgroundColor: AppColors.darkGreen,
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
        title: Text('Own Palai', style: AppTheme.heading(size: 17)),
        actions: [
          if (_farmId != null)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Move a goat to Own Palai',
              onPressed: () => Navigator.of(context).push(
                fastRoute(MoveToOwnPalaiScreen(farmId: _farmId!)),
              ),
            ),
        ],
      ),
      body: _loadingFarm
          ? const Center(
        child: CircularProgressIndicator(color: AppColors.tradingBlue),
      )
          : _farmId == null
          ? _buildNotLinkedState()
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Container(
              decoration: AppTheme.card(radius: 12),
              child: TextField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _search = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search by Goat ID or breed',
                  hintStyle: AppTheme.body(size: 12),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: InputBorder.none,
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 12),
                ),
                style: AppTheme.body(size: 13, color: AppColors.textDark),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Goat>>(
              stream: GoatService.instance.ownPalaiGoatsStream(_farmId!),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.tradingBlue,
                    ),
                  );
                }

                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load Own Palai goats: ${snap.error}',
                        style: AppTheme.body(size: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                var goats = snap.data!;

                if (_search.isNotEmpty) {
                  goats = goats
                      .where(
                        (g) =>
                    g.id.toLowerCase().contains(_search) ||
                        g.breed.toLowerCase().contains(_search),
                  )
                      .toList();
                }

                if (goats.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.holiday_village_outlined,
                            size: 40,
                            color: AppColors.textGrey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No goats in Own Palai yet.',
                            style: AppTheme.body(size: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Move an Available goat from Goat Stock '
                                'using the + button above.',
                            style: AppTheme.body(
                              size: 11.5,
                              color: AppColors.textGrey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: goats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _goatCard(goats[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatCard(Goat goat) {
    final statusColor = _healthColor(goat.healthStatus);

    return GestureDetector(
      onTap: () => _openProfile(goat),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.lightGreen,
              backgroundImage: goat.photo != null ? MemoryImage(goat.photo!) : null,
              child: goat.photo == null
                  ? const Icon(Icons.pets, color: AppColors.primaryGreen)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goat.id, style: AppTheme.heading(size: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${goat.breed} · ${goat.age}',
                    style: AppTheme.body(size: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${goat.weight.toStringAsFixed(1)} kg',
                    style: AppTheme.body(size: 12, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                goat.healthStatus,
                style: AppTheme.body(size: 10, color: statusColor, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}