import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/own_farm_models.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/fast_route.dart';
import 'add_own_farm_goat_screen.dart';
import 'own_farm_goat_detail_screen.dart';

/// Lists every goat owned by the farm itself. Tapping a goat opens its
/// full profile — weight history, health/vaccination records, breeding,
/// expenses and photos.
class OwnFarmGoatListScreen extends StatefulWidget {
  const OwnFarmGoatListScreen({super.key});

  @override
  State<OwnFarmGoatListScreen> createState() => _OwnFarmGoatListScreenState();
}

class _OwnFarmGoatListScreenState extends State<OwnFarmGoatListScreen> {
  String? _farmId;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Own Farm Goats', style: AppTheme.heading(size: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(fastRoute(const AddOwnFarmGoatScreen())),
          ),
        ],
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Container(
                    decoration: AppTheme.card(radius: 12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search by Goat ID or breed',
                        hintStyle: AppTheme.body(size: 12),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      style: AppTheme.body(size: 13, color: AppColors.textDark),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<OwnFarmGoat>>(
                    stream: FirestoreService.instance.ownFarmGoatsStream(_farmId!),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                      }
                      var goats = snap.data!;
                      if (_search.isNotEmpty) {
                        goats = goats
                            .where((g) => g.goatCode.toLowerCase().contains(_search) || g.breed.toLowerCase().contains(_search))
                            .toList();
                      }
                      if (goats.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('No farm goats registered yet. Tap + to add one.', style: AppTheme.body(size: 13)),
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

  Widget _goatCard(OwnFarmGoat goat) {
    final statusColor = goat.healthStatus == 'Healthy'
        ? AppColors.success
        : goat.healthStatus == 'Under Treatment'
            ? AppColors.warning
            : AppColors.error;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(fastRoute(OwnFarmGoatDetailScreen(goat: goat))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.lightGreen,
              backgroundImage: goat.photo != null ? MemoryImage(goat.photo!) : null,
              child: goat.photo == null ? const Icon(Icons.pets, color: AppColors.primaryGreen) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goat.goatCode, style: AppTheme.heading(size: 14)),
                  const SizedBox(height: 2),
                  Text('${goat.breed} · ${goat.gender} · ${goat.ageInMonths} mo', style: AppTheme.body(size: 11)),
                  const SizedBox(height: 4),
                  Text('${goat.currentWeight.toStringAsFixed(1)} kg', style: AppTheme.body(size: 12, color: AppColors.textDark)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(goat.healthStatus, style: AppTheme.body(size: 10, color: statusColor, weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
