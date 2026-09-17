import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import 'goat_stock_detail_screen.dart';

/// Task 3.1 — Goat Stock list screen.
///
/// Streams the `tradingGoats` collection — the same records Feature 3
/// (Goat Registration) wrote — and shows each as a row: Photo, Goat ID,
/// Breed, Age, Weight, Status, per the phase 2 plan. No new writes
/// happen here, this is a read-only list/detail view.
///
/// A status filter chip row is included so this screen keeps working
/// once later phases (Own Palai, Sale) start moving goats out of
/// "Available" — phase 2 itself only ever writes that one status, so by
/// default "Available" is selected, matching the plan's suggestion to
/// filter on `currentStatus: 'Available'`. "All" is one tap away.
class GoatStockListScreen extends StatefulWidget {
  const GoatStockListScreen({super.key});

  @override
  State<GoatStockListScreen> createState() => _GoatStockListScreenState();
}

class _GoatStockListScreenState extends State<GoatStockListScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  final _searchController = TextEditingController();
  String _search = '';

  /// null == "All".
  String? _statusFilter = Goat.statusAvailable;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    if (mounted) setState(() => _loadingFarm = true);

    final id = await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    setState(() {
      _farmId = id == null || id.trim().isEmpty ? null : id.trim();
      _loadingFarm = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetail(Goat goat) {
    final farmId = _farmId;
    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        GoatStockDetailScreen(farmId: farmId, goat: goat),
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
        title: Text('Goat Stock', style: AppTheme.heading(size: 17)),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _statusChip(null, 'All'),
                const SizedBox(width: 8),
                for (final status in Goat.statusValues) ...[
                  _statusChip(status, status),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Goat>>(
            stream: GoatService.instance.goatsStream(
              farmId,
              currentStatus: _statusFilter,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _message(
                  icon: Icons.error_outline,
                  iconColor: AppColors.error,
                  title: 'Unable to load goat stock',
                  subtitle: 'Please try again.',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryGreen),
                );
              }

              var goats = snapshot.data ?? [];

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
                return _message(
                  icon: Icons.inventory_2_outlined,
                  iconColor: AppColors.stockTeal,
                  title: 'No Goats Found',
                  subtitle: _statusFilter == null
                      ? 'Registered goats will show up here.'
                      : 'No goats with status "$_statusFilter" yet.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: goats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final goat = goats[index];
                  return _GoatStockCard(
                    goat: goat,
                    onTap: () => _openDetail(goat),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String? status, String label) {
    final selected = _statusFilter == status;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _statusFilter = status),
      showCheckmark: false,
      labelStyle: AppTheme.body(
        size: 12,
        color: selected ? Colors.white : AppColors.textDark,
        weight: FontWeight.w600,
      ),
      selectedColor: AppColors.stockTeal,
      backgroundColor: AppColors.cardWhite,
      side: BorderSide(
        color: selected ? AppColors.stockTeal : AppColors.divider,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
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

// ============================================================================
// STOCK CARD
// ============================================================================

class _GoatStockCard extends StatelessWidget {
  final Goat goat;
  final VoidCallback onTap;

  const _GoatStockCard({required this.goat, required this.onTap});

  Color _statusColor() {
    switch (goat.currentStatus) {
      case Goat.statusAvailable:
        return AppColors.success;
      case Goat.statusBooked:
        return AppColors.warning;
      case Goat.statusSold:
        return AppColors.error;
      case Goat.statusInCustomerPalai:
        return AppColors.info;
      default:
        return AppColors.textGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.stockTeal.withOpacity(0.14),
              backgroundImage: goat.photo != null ? MemoryImage(goat.photo!) : null,
              child: goat.photo == null
                  ? const Icon(Icons.pets, color: AppColors.stockTeal)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goat.id, style: AppTheme.heading(size: 15)),
                  const SizedBox(height: 3),
                  Text(
                    '${goat.breed} · ${goat.age}',
                    style: AppTheme.body(size: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${goat.weight.toStringAsFixed(1)} kg',
                    style: AppTheme.body(size: 12, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    goat.currentStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey.withOpacity(0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}