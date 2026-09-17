import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../services/goat_service.dart';

/// Task 2.1 — "Move to Own Palai" action.
///
/// Reached from RegistrationCompletedScreen's exit option (and can
/// equally be reached from a future Goat Stock detail view — see the
/// phase 3 plan's "and/or" wording for this task; there's no Goat
/// Stock screen yet, so this is a standalone farm-wide picker rather
/// than a per-goat button on a detail screen that doesn't exist).
///
/// Lists every [Goat.statusAvailable] goat for the farm and lets the
/// person move one to Own Palai. Tapping a goat only ever updates that
/// goat's existing `tradingGoats/{goatId}` doc via
/// [GoatService.moveToOwnPalai] — no new goat, no new ID (see the
/// "No duplicate Goat IDs" note on [Goat]).
class MoveToOwnPalaiScreen extends StatefulWidget {
  final String farmId;

  const MoveToOwnPalaiScreen({super.key, required this.farmId});

  @override
  State<MoveToOwnPalaiScreen> createState() => _MoveToOwnPalaiScreenState();
}

class _MoveToOwnPalaiScreenState extends State<MoveToOwnPalaiScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  /// Goat IDs currently mid-move, so a double-tap can't fire two
  /// transactions for the same goat while the first is still in
  /// flight.
  final Set<String> _moving = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndMove(Goat goat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to Own Palai?'),
        content: Text(
          '${goat.id} (${goat.breed}) will move from Goat Stock into '
              'Own Palai. This does not create a new goat record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.tradingBlue,
            ),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _moving.add(goat.id));

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
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not move ${goat.id}: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _moving.remove(goat.id));
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
        title: Text('Move to Own Palai', style: AppTheme.heading(size: 17)),
      ),
      body: Column(
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
            child: StreamBuilder<List<Goat>>(
              stream: GoatService.instance.goatsStream(widget.farmId),
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
                        'Could not load goats: ${snap.error}',
                        style: AppTheme.body(size: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                var goats = snap.data!.where((g) => g.isAvailable).toList();

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
                      child: Text(
                        'No Available goats to move. Goats already in '
                            'Own Palai, Sold, or Booked won\'t show up here.',
                        style: AppTheme.body(size: 13),
                        textAlign: TextAlign.center,
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
    final isMoving = _moving.contains(goat.id);

    return Container(
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
          SizedBox(
            height: 34,
            child: isMoving
                ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.tradingBlue,
                ),
              ),
            )
                : OutlinedButton(
              onPressed: () => _confirmAndMove(goat),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.tradingBlue,
                side: const BorderSide(color: AppColors.tradingBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Move',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}