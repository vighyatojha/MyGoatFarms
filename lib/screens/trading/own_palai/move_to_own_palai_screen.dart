import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../services/goat_service.dart';

class MoveToOwnPalaiScreen extends StatefulWidget {
  final String farmId;

  const MoveToOwnPalaiScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<MoveToOwnPalaiScreen> createState() => _MoveToOwnPalaiScreenState();
}

class _MoveToOwnPalaiScreenState extends State<MoveToOwnPalaiScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _search = '';

  /// Goat IDs currently being moved.
  final Set<String> _moving = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndMove(Goat goat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Move to Own Palai?',
            style: AppTheme.heading(size: 17),
          ),
          content: Text(
            '${goat.id} will move from Goat Stock to Own Palai.\n\n'
                'The existing goat record will be updated. No duplicate goat '
                'will be created.',
            style: AppTheme.body(
              size: 13,
              color: AppColors.textGrey,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(
                'Cancel',
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.textGrey,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tradingBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Move'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _moving.add(goat.id);
    });

    try {
      await GoatService.instance.moveToOwnPalai(
        farmId: widget.farmId,
        goatId: goat.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${goat.id} moved to Own Palai.'),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not move ${goat.id}: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _moving.remove(goat.id);
        });
      }
    }
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
        title: Text(
          'Move to Own Palai',
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: Column(
        children: [
          _buildHeaderInfo(),
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<List<Goat>>(
              stream: GoatService.instance.goatsStream(widget.farmId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const _MoveGoatListSkeleton();
                }

                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error);
                }

                var goats = (snapshot.data ?? <Goat>[])
                    .where((goat) => goat.isAvailable)
                    .toList();

                if (_search.isNotEmpty) {
                  goats = goats.where((goat) {
                    final id = goat.id.toLowerCase();
                    final breed = goat.breed.toLowerCase();

                    return id.contains(_search) ||
                        breed.contains(_search);
                  }).toList();
                }

                if (goats.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    2,
                    16,
                    24,
                  ),
                  itemCount: goats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
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

  Widget _buildHeaderInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: AppColors.tradingBlue.withOpacity(0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.tradingBlue.withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.tradingBlue.withOpacity(0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.swap_horiz,
                size: 19,
                color: AppColors.tradingBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Select an Available goat to move it into Own Palai.',
                style: AppTheme.body(
                  size: 11.5,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
    final isMoving = _moving.contains(goat.id);

    return Material(
      color: Colors.transparent,
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
                      _availableChip(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    goat.breed.isEmpty
                        ? 'Breed not specified'
                        : goat.breed,
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
                        AppColors.tradingBlue,
                      ),
                      const SizedBox(width: 13),
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
            const SizedBox(width: 7),
            _moveButton(goat, isMoving),
          ],
        ),
      ),
    );
  }

  Widget _goatPhoto(Goat goat) {
    return Container(
      width: 60,
      height: 60,
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
        size: 26,
        color: AppColors.primaryGreen,
      ),
    );
  }

  Widget _availableChip() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Available',
        style: AppTheme.body(
          size: 9,
          color: AppColors.success,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _moveButton(Goat goat, bool isMoving) {
    return SizedBox(
      height: 34,
      child: isMoving
          ? Container(
        width: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.tradingBlue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const _TinySkeleton(),
      )
          : ElevatedButton(
        onPressed: () => _confirmAndMove(goat),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.tradingBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'Move',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
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
                color: AppColors.tradingBlue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.swap_horiz,
                size: 32,
                color: AppColors.tradingBlue,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              searching
                  ? 'No goats found'
                  : 'No Available goats',
              style: AppTheme.heading(size: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              searching
                  ? 'Try a different goat ID or breed.'
                  : 'There are currently no Available goats in Goat Stock to move.',
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

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 30,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load goats',
              style: AppTheme.heading(size: 14),
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
                foregroundColor: AppColors.tradingBlue,
                side: const BorderSide(
                  color: AppColors.tradingBlue,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
/* Skeletons                                                                  */
/* -------------------------------------------------------------------------- */

class _TinySkeleton extends StatefulWidget {
  const _TinySkeleton();

  @override
  State<_TinySkeleton> createState() => _TinySkeletonState();
}

class _TinySkeletonState extends State<_TinySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
      builder: (_, __) {
        return Opacity(
          opacity: 0.45 + (_controller.value * 0.4),
          child: Container(
            width: 20,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        );
      },
    );
  }
}

class _MoveGoatListSkeleton extends StatelessWidget {
  const _MoveGoatListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        16,
        2,
        16,
        24,
      ),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, __) => const _MoveGoatSkeletonCard(),
    );
  }
}

class _MoveGoatSkeletonCard extends StatefulWidget {
  const _MoveGoatSkeletonCard();

  @override
  State<_MoveGoatSkeletonCard> createState() =>
      _MoveGoatSkeletonCardState();
}

class _MoveGoatSkeletonCardState extends State<_MoveGoatSkeletonCard>
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

  Widget _box(
      double width,
      double height, {
        double radius = 6,
      }) {
    return Opacity(
      opacity: 0.45 + (_controller.value * 0.35),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Container(
          height: 84,
          padding: const EdgeInsets.all(11),
          decoration: AppTheme.card(radius: 15),
          child: Row(
            children: [
              _box(60, 60, radius: 14),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _box(78, 13),
                        const Spacer(),
                        _box(52, 18, radius: 20),
                      ],
                    ),
                    const SizedBox(height: 7),
                    _box(110, 10),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _box(65, 10),
                        const SizedBox(width: 13),
                        _box(62, 10),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              _box(52, 34, radius: 10),
            ],
          ),
        );
      },
    );
  }
}