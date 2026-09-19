import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import 'move_to_own_palai_screen.dart';
import 'own_palai_goat_profile_screen.dart';

class OwnPalaiListScreen extends StatefulWidget {
  const OwnPalaiListScreen({super.key});

  @override
  State<OwnPalaiListScreen> createState() => _OwnPalaiListScreenState();
}

class _OwnPalaiListScreenState extends State<OwnPalaiListScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    try {
      final id = await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId = id;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final farmId = _farmId;
    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        OwnPalaiGoatProfileScreen(
          farmId: farmId,
          goat: goat,
        ),
      ),
    );
  }

  void _openMoveScreen() {
    final farmId = _farmId;
    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        MoveToOwnPalaiScreen(farmId: farmId),
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
        titleSpacing: 20,
        title: _farmId == null
            ? Text(
          'Own Palai',
          style: AppTheme.heading(size: 18),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Own Palai',
              style: AppTheme.heading(size: 18),
            ),
            StreamBuilder<List<Goat>>(
              stream: GoatService.instance
                  .ownPalaiGoatsStream(_farmId!),
              builder: (context, snapshot) {
                final count = snapshot.data?.length;

                return Text(
                  count == null
                      ? 'Goats boarded at your farm'
                      : count == 1
                      ? '1 goat boarded here'
                      : '$count goats boarded here',
                  style: AppTheme.body(
                    size: 11.5,
                    color: AppColors.textGrey,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          if (_farmId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: 'Move goat to Own Palai',
                child: Material(
                  color: AppColors.primaryGreen.withOpacity(0.10),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _openMoveScreen,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loadingFarm
          ? const _OwnPalaiSkeleton()
          : _farmId == null
          ? FarmNotLinkedState(
        buttonColor: AppColors.primaryGreen,
        onRetry: () {
          setState(() {
            _loadingFarm = true;
          });
          _loadFarm();
        },
      )
          : Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<List<Goat>>(
              stream: GoatService.instance
                  .ownPalaiGoatsStream(_farmId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const _OwnPalaiListSkeleton();
                }

                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error);
                }

                var goats = snapshot.data ?? <Goat>[];

                if (_search.isNotEmpty) {
                  goats = goats.where((goat) {
                    final id = goat.id.toLowerCase();
                    final breed = goat.breed.toLowerCase();
                    final search = _search.toLowerCase();

                    return id.contains(search) ||
                        breed.contains(search);
                  }).toList();
                }

                if (goats.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    24,
                  ),
                  itemCount: goats.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    return _goatCard(goats[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Container(
        height: 46,
        decoration: AppTheme.card(radius: 13),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _search = value.trim().toLowerCase();
            });
          },
          style: AppTheme.body(
            size: 13,
            color: AppColors.textDark,
          ),
          decoration: InputDecoration(
            hintText: 'Search goat ID or breed',
            hintStyle: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
            prefixIcon: const Icon(
              Icons.search,
              size: 19,
              color: AppColors.textGrey,
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _search = '';
                });
              },
              icon: const Icon(
                Icons.close,
                size: 17,
                color: AppColors.textGrey,
              ),
            )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _goatCard(Goat goat) {
    final healthColor = _healthColor(goat.healthStatus);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _openProfile(goat),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: AppTheme.card(radius: 15),
          child: Row(
            children: [
              _goatPhoto(goat),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goat.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.heading(size: 14),
                          ),
                        ),
                        _statusChip(
                          goat.healthStatus,
                          healthColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      goat.breed.isEmpty ? 'Breed not specified' : goat.breed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 11.5,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _miniInfo(
                          Icons.cake_outlined,
                          goat.age,
                          AppColors.stockTeal,
                        ),
                        const SizedBox(width: 14),
                        _miniInfo(
                          Icons.monitor_weight_outlined,
                          '${goat.weight.toStringAsFixed(1)} kg',
                          AppColors.primaryGreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goatPhoto(Goat goat) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: goat.photo != null
          ? Image.memory(
        goat.photo!,
        fit: BoxFit.cover,
      )
          : const Icon(
        Icons.pets,
        size: 27,
        color: AppColors.primaryGreen,
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.body(
          size: 9.5,
          color: color,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _miniInfo(
      IconData icon,
      String text,
      Color color,
      ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTheme.body(
            size: 10.5,
            color: AppColors.textDark,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final searching = _search.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.pets_outlined,
                size: 32,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              searching
                  ? 'No goats found'
                  : 'No goats in Own Palai',
              style: AppTheme.heading(size: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              searching
                  ? 'Try a different goat ID or breed.'
                  : 'Move an available goat from Goat Stock to start your Own Palai.',
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.textGrey,
              ),
              textAlign: TextAlign.center,
            ),
            if (!searching) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _openMoveScreen,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Move Goat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.error,
            ),
            const SizedBox(height: 10),
            Text(
              'Could not load Own Palai goats',
              style: AppTheme.heading(size: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              '$error',
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => setState(() {}),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                side: const BorderSide(
                  color: AppColors.primaryGreen,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* Skeleton loading                                                           */
/* -------------------------------------------------------------------------- */

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.45 + (_controller.value * 0.35);

        return Opacity(
          opacity: opacity,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        );
      },
    );
  }
}

class _OwnPalaiSkeleton extends StatelessWidget {
  const _OwnPalaiSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: _SkeletonBox(
            width: double.infinity,
            height: 46,
            radius: 13,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (_, __) => const _OwnPalaiSkeletonCard(),
          ),
        ),
      ],
    );
  }
}

class _OwnPalaiListSkeleton extends StatelessWidget {
  const _OwnPalaiListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, __) => const _OwnPalaiSkeletonCard(),
    );
  }
}

class _OwnPalaiSkeletonCard extends StatelessWidget {
  const _OwnPalaiSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(11),
      decoration: AppTheme.card(radius: 15),
      child: Row(
        children: [
          const _SkeletonBox(
            width: 62,
            height: 62,
            radius: 14,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: const [
                    _SkeletonBox(
                      width: 90,
                      height: 14,
                      radius: 5,
                    ),
                    Spacer(),
                    _SkeletonBox(
                      width: 55,
                      height: 18,
                      radius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const _SkeletonBox(
                  width: 115,
                  height: 10,
                  radius: 5,
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    _SkeletonBox(
                      width: 70,
                      height: 10,
                      radius: 5,
                    ),
                    SizedBox(width: 14),
                    _SkeletonBox(
                      width: 65,
                      height: 10,
                      radius: 5,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}