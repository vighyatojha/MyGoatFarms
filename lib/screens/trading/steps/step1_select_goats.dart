import 'package:flutter/material.dart';

import '../../../../app_theme.dart';
import '../../../../models/goat_model.dart';
import '../../../../models/sale_draft.dart';
import '../../../../services/goat_service.dart';

/// Step 1 — Select Goat(s).
///
/// Lists goats where `currentStatus` is Available or Own Palai — this is
/// the "Own Palai -> Sell" tie-in from PDF section 13: one query, two
/// source statuses, no separate screen needed (Task 2.1).
///
/// Supports multi-select. A goat already picked stays visible even while
/// searching, so the person doesn't lose track of an earlier pick.
class Step1SelectGoats extends StatefulWidget {
  final String farmId;
  final SaleDraft draft;

  const Step1SelectGoats({
    super.key,
    required this.farmId,
    required this.draft,
  });

  @override
  State<Step1SelectGoats> createState() => _Step1SelectGoatsState();
}

enum _SellableFilter { all, available, ownPalai }

class _Step1SelectGoatsState extends State<Step1SelectGoats> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  _SellableFilter _filter = _SellableFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSelected(Goat goat) {
    return widget.draft.selectedGoats.any((g) => g.id == goat.id);
  }

  void _toggle(Goat goat) {
    setState(() {
      final selected = widget.draft.selectedGoats;
      final index = selected.indexWhere((g) => g.id == goat.id);

      if (index >= 0) {
        selected.removeAt(index);
      } else {
        selected.add(goat);
      }
    });
  }

  List<Goat> _applyFilters(List<Goat> goats) {
    var result = goats.where((g) => g.isSellable);

    if (_filter == _SellableFilter.available) {
      result = result.where((g) => g.isAvailable);
    } else if (_filter == _SellableFilter.ownPalai) {
      result = result.where((g) => g.isOwnPalai);
    }

    final query = _search.trim().toLowerCase();

    if (query.isNotEmpty) {
      result = result.where(
            (g) =>
        g.id.toLowerCase().contains(query) ||
            g.breed.toLowerCase().contains(query),
      );
    }

    return result.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // -----------------------------------------------------------------
        // SEARCH + FILTER
        // -----------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _search = value;
                  });
                },
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.textDark,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by Goat ID or breed',
                  hintStyle: AppTheme.body(
                    size: 12,
                    color: AppColors.textGrey,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.primaryGreen,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                      color: AppColors.divider,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                      color: AppColors.divider,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _FilterChip(
                      label: 'All',
                      selected: _filter == _SellableFilter.all,
                      onTap: () {
                        setState(() {
                          _filter = _SellableFilter.all;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterChip(
                      label: 'Available',
                      selected: _filter == _SellableFilter.available,
                      onTap: () {
                        setState(() {
                          _filter = _SellableFilter.available;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterChip(
                      label: 'Own Palai',
                      selected: _filter == _SellableFilter.ownPalai,
                      onTap: () {
                        setState(() {
                          _filter = _SellableFilter.ownPalai;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // -----------------------------------------------------------------
        // SELECTED COUNT
        // -----------------------------------------------------------------

        if (widget.draft.selectedGoats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.draft.selectedGoats.length} '
                      'goat${widget.draft.selectedGoats.length == 1 ? '' : 's'} selected',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.primaryGreen,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

        // -----------------------------------------------------------------
        // LIST
        // -----------------------------------------------------------------

        Expanded(
          child: StreamBuilder<List<Goat>>(
            stream: GoatService.instance.goatsStream(widget.farmId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load goats.',
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.textGrey,
                    ),
                  ),
                );
              }

              final goats = _applyFilters(snapshot.data ?? []);

              if (goats.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pets_outlined,
                          size: 40,
                          color: AppColors.textGrey.withOpacity(0.5),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No sellable goats found',
                          style: AppTheme.body(
                            size: 13,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: goats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final goat = goats[index];

                  return _GoatSelectTile(
                    goat: goat,
                    selected: _isSelected(goat),
                    onTap: () => _toggle(goat),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FILTER CHIP
// ============================================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primaryGreen
                : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.body(
            size: 11,
            color: selected ? Colors.white : AppColors.textGrey,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// GOAT SELECT TILE
// ============================================================================

class _GoatSelectTile extends StatelessWidget {
  final Goat goat;
  final bool selected;
  final VoidCallback onTap;

  const _GoatSelectTile({
    required this.goat,
    required this.selected,
    required this.onTap,
  });

  Color get _statusColor {
    if (goat.isOwnPalai) return AppColors.tradingBlue;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primaryGreen
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // -------------------------------------------------------
              // PHOTO
              // -------------------------------------------------------

              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.stockTeal.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                clipBehavior: Clip.antiAlias,
                child: goat.photo != null
                    ? Image.memory(goat.photo!, fit: BoxFit.cover)
                    : const Icon(
                  Icons.pets_outlined,
                  color: AppColors.stockTeal,
                  size: 24,
                ),
              ),

              const SizedBox(width: 11),

              // -------------------------------------------------------
              // DETAILS
              // -------------------------------------------------------

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
                            style: AppTheme.heading(
                              size: 13,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            goat.currentStatus,
                            style: TextStyle(
                              color: _statusColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      goat.breed.isEmpty
                          ? 'Breed not specified'
                          : goat.breed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 12,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          goat.age,
                          style: AppTheme.body(
                            size: 10,
                            color: AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.monitor_weight_outlined,
                          size: 12,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${goat.weight.toStringAsFixed(1)} kg',
                          style: AppTheme.body(
                            size: 10,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // -------------------------------------------------------
              // CHECKBOX
              // -------------------------------------------------------

              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.divider,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}