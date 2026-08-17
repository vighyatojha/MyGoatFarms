import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import 'check_in_screen.dart';
import 'check_out_screen.dart';

/// Lists every goat currently boarded in Palai: a circular "Before Palai"
/// photo (ringed by its health status color), the Goat ID, and how long
/// it's been boarded. Tapping a goat opens its Check-Out page.
class GoatListScreen extends StatefulWidget {
  const GoatListScreen({super.key});

  @override
  State<GoatListScreen> createState() => _GoatListScreenState();
}

class _GoatListScreenState extends State<GoatListScreen> {
  String? _farmId;

  // Created once, when the farm id resolves, and reused on every rebuild.
  // Calling FirestoreService.instance.allActiveGoatsStream(...) directly
  // inside `build()` would hand StreamBuilder a brand-new stream instance
  // every rebuild, forcing it to drop its subscription and flash back to
  // the loading state — this is what caused the screen to keep "reloading".
  Stream<List<PalaiGoat>>? _goatsStream;

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    FirestoreService.instance.currentFarmId().then((id) {
      if (!mounted) return;
      setState(() {
        _farmId = id;
        if (id != null) {
          _goatsStream = FirestoreService.instance.allActiveGoatsStream(id);
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// e.g. "2 mo 14 d", "18 days", "3 months" — how long a goat has been
  /// boarded, counted from its check-in date to now.
  String _boardedFor(DateTime checkInDate) {
    final now = DateTime.now();
    int months = (now.year - checkInDate.year) * 12 + (now.month - checkInDate.month);
    DateTime monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    if (monthsAgo.isAfter(now)) {
      months -= 1;
      monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    }
    final days = now.difference(monthsAgo).inDays;
    if (months <= 0) return '$days day${days == 1 ? '' : 's'}';
    if (days <= 0) return '$months month${months == 1 ? '' : 's'}';
    return '$months mo $days d';
  }

  Color _healthColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;
      case 'Under Observation':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  List<PalaiGoat> _filtered(List<PalaiGoat> goats) {
    final sorted = [...goats]..sort((a, b) => b.checkInDate.compareTo(a.checkInDate));
    if (_query.isEmpty) return sorted;
    return sorted.where((g) {
      return g.goatCode.toLowerCase().contains(_query) ||
          g.breed.toLowerCase().contains(_query) ||
          g.color.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 0,
        title: Text('Goats in Palai', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : StreamBuilder<List<PalaiGoat>>(
        stream: _goatsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }
          final allGoats = snap.data ?? [];

          if (allGoats.isEmpty) {
            return _emptyState();
          }

          final goats = _filtered(allGoats);

          return Column(
            children: [
              _summaryHeader(allGoats.length),
              _searchBar(),
              Expanded(
                child: goats.isEmpty
                    ? _noResultsState()
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: goats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _goatCard(goats[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryHeader(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
            child: const Icon(Icons.pets, color: AppColors.primaryGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$total goat${total == 1 ? '' : 's'} boarded',
                    style: AppTheme.heading(size: 15)),
                Text('Tap a goat to check it out', style: AppTheme.body(size: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: AppTheme.card(radius: 12),
        child: TextField(
          controller: _searchController,
          style: AppTheme.body(size: 13, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: 'Search by goat ID, breed or color',
            hintStyle: AppTheme.body(size: 13),
            prefixIcon: const Icon(Icons.search, color: AppColors.textGrey, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
              icon: const Icon(Icons.close, color: AppColors.textGrey, size: 18),
              onPressed: () => _searchController.clear(),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _goatCard(PalaiGoat goat) {
    final healthColor = _healthColor(goat.healthStatus);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(fastRoute(CheckOutGoatScreen(goat: goat))),
        child: Container(
          decoration: AppTheme.card(radius: 14),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.lightGreen,
                  border: Border.all(color: healthColor.withOpacity(0.55), width: 2),
                ),
                child: ClipOval(
                  child: goat.beforeImage != null
                      ? Image.memory(goat.beforeImage!, fit: BoxFit.cover, width: 54, height: 54)
                      : const Icon(Icons.pets, color: AppColors.primaryGreen),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goat.goatCode, style: AppTheme.heading(size: 14)),
                    const SizedBox(height: 3),
                    Text('${goat.breed} · ${goat.gender}', style: AppTheme.body(size: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: healthColor, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(goat.healthStatus, style: AppTheme.body(size: 11, color: healthColor, weight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      _boardedFor(goat.checkInDate),
                      style: AppTheme.body(size: 11, color: AppColors.darkGreen, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right, color: AppColors.textGrey, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
              child: const Icon(Icons.pets, size: 40, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 18),
            Text('No goats currently boarded', style: AppTheme.heading(size: 15)),
            const SizedBox(height: 6),
            Text(
              'Goats you check in to Palai will show up here.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(fastRoute(const CheckInGoatScreen())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Check In a Goat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 36, color: AppColors.textGrey),
            const SizedBox(height: 10),
            Text('No goats match "${_searchController.text}"', style: AppTheme.body(size: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}