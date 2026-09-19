import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/farm_model.dart';
import '../../../models/goat_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import '../own_palai/add_weight_entry_screen.dart';
import 'complete_booking_delivery_screen.dart';
import 'complete_wait_for_delivery_screen.dart';
import 'goat_stock_detail_screen.dart';
import '../purchase_goats/individual_goat_purchase_screen.dart';

// ============================================================================
// SHARED STATUS HELPERS
// ============================================================================

bool _hasStatus(Goat goat, String status) {
  return goat.currentStatus.trim().toLowerCase() ==
      status.toLowerCase();
}

Color _statusColor(String status) {
  switch (status.trim()) {
    case Goat.statusAvailable:
      return AppColors.success;

    case Goat.statusBooked:
      return AppColors.warning;

    case Goat.statusWaitOnDelivery:
      return AppColors.warning;

    case Goat.statusSold:
      return AppColors.error;

    case Goat.statusInCustomerPalai:
      return AppColors.info;

    case Goat.statusOwnPalai:
      return AppColors.tradingBlue;

    default:
      return AppColors.textGrey;
  }
}

/// Display label only. Filtering always uses the raw [Goat] status value.
String _statusLabel(String status) {
  return status.trim() == Goat.statusSold ? 'Sold Out' : status;
}

/// Darker shade of a status color, for text on its own pale tint.
Color _statusTextColor(Color color) {
  final hsl = HSLColor.fromColor(color);

  return hsl
      .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
      .toColor();
}

Color _healthColor(String health) {
  switch (health.trim()) {
    case 'Healthy':
      return AppColors.success;

    case 'Under Treatment':
      return AppColors.warning;

    case 'Sick':
      return AppColors.error;

    case 'Quarantined':
      return AppColors.info;

    default:
      return AppColors.textGrey;
  }
}

enum _StockSort {
  newest,
  oldest,
  heaviest,
  youngest,
}

extension on _StockSort {
  String get label {
    switch (this) {
      case _StockSort.newest:
        return 'Newest first';
      case _StockSort.oldest:
        return 'Oldest first';
      case _StockSort.heaviest:
        return 'Heaviest first';
      case _StockSort.youngest:
        return 'Youngest first';
    }
  }
}

class _SortFilterResult {
  final _StockSort sort;
  final String? gender;

  const _SortFilterResult({
    required this.sort,
    required this.gender,
  });
}

/// Goat Stock list.
///
/// Displays registered trading goats with:
/// - Header with farm name and sort / filter
/// - Compact stock summary (tap a stat to filter)
/// - Search
/// - Pinned status filter chips with counts
/// - Status-aware goat cards
/// - Floating "+" button to purchase an individual goat
/// - Skeleton loading
///
/// Farm ID is resolved internally, so this screen does not require a
/// farmId constructor parameter.
class GoatStockListScreen extends StatefulWidget {
  /// Pre-selects a status filter chip on open — lets other screens
  /// (like the Trading Dashboard's stat cards) deep-link straight to
  /// a filtered view instead of landing on the unfiltered list.
  /// `null` keeps the previous default of "All".
  final String? initialStatusFilter;

  const GoatStockListScreen({
    super.key,
    this.initialStatusFilter,
  });

  @override
  State<GoatStockListScreen> createState() =>
      _GoatStockListScreenState();
}

class _GoatStockListScreenState
    extends State<GoatStockListScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  /// Created once per farm so typing in the search box (which rebuilds
  /// this screen) doesn't re-subscribe to Firestore on every keystroke.
  Stream<List<Goat>>? _goatsStream;

  /// Same idea for the farm name shown in the header.
  Stream<FarmModel?>? _farmStream;

  final TextEditingController _searchController =
  TextEditingController();

  String _search = '';

  /// null = All.
  late String? _statusFilter = widget.initialStatusFilter;

  _StockSort _sort = _StockSort.newest;

  /// null = any. Otherwise one of [Goat.genderValues].
  String? _genderFilter;

  bool get _hasSortOrGender =>
      _sort != _StockSort.newest || _genderFilter != null;

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

    final id =
    await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    final farmId =
    id == null || id.trim().isEmpty ? null : id.trim();

    setState(() {
      _farmId = farmId;

      _goatsStream = farmId == null
          ? null
          : GoatService.instance.goatsStream(farmId);

      _farmStream = farmId == null
          ? null
          : FirestoreService.instance.farmDocStream(farmId);

      _loadingFarm = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  void _openDetail(Goat goat) {
    final farmId = _farmId;

    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        GoatStockDetailScreen(
          farmId: farmId,
          goat: goat,
        ),
      ),
    );
  }

  /// Card-level shortcut so a Booked / Wait-on-Delivery goat's
  /// "Complete Delivery" action doesn't require going through the
  /// detail screen first.
  void _openCompleteDelivery(Goat goat) {
    final farmId = _farmId;

    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        _hasStatus(goat, Goat.statusBooked)
            ? CompleteBookingDeliveryScreen(
          farmId: farmId,
          goat: goat,
        )
            : CompleteWaitForDeliveryScreen(
          farmId: farmId,
          goat: goat,
        ),
      ),
    );
  }

  /// Card-level shortcut for Own Palai goats.
  void _openLogWeighIn(Goat goat) {
    final farmId = _farmId;

    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        AddWeightEntryScreen(
          farmId: farmId,
          goatId: goat.id,
        ),
      ),
    );
  }

  /// Individual goat purchase (FAB). The goat list is a live stream, so
  /// the new goat appears on its own once the purchase screen pops.
  Future<void> _openPurchase() async {
    final farmId = _farmId;

    if (farmId == null) return;

    final goat = await Navigator.of(context).push<Goat>(
      fastRoute<Goat>(
        IndividualGoatPurchaseScreen(farmId: farmId),
      ),
    );

    if (goat == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${goat.id} purchased and added to stock.',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ===========================================================================
  // SORT / GENDER SHEET
  // ===========================================================================

  Future<void> _openSortFilterSheet() async {
    final result =
    await showModalBottomSheet<_SortFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var sort = _sort;
        String? gender = _genderFilter;

        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius:
                            BorderRadius.circular(20),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        'Sort & filter',
                        style: AppTheme.heading(size: 17),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Sort by',
                        style: AppTheme.body(
                          size: 11,
                          weight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _StockSort.values.map((value) {
                          return _sheetChip(
                            label: value.label,
                            selected: sort == value,
                            onTap: () {
                              setSheet(() {
                                sort = value;
                              });
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        'Gender',
                        style: AppTheme.body(
                          size: 11,
                          weight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _sheetChip(
                            label: 'Any',
                            selected: gender == null,
                            onTap: () {
                              setSheet(() {
                                gender = null;
                              });
                            },
                          ),
                          ...Goat.genderValues.map((value) {
                            return _sheetChip(
                              label: value,
                              selected: gender == value,
                              onTap: () {
                                setSheet(() {
                                  gender = value;
                                });
                              },
                            );
                          }),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'Only goats with a recorded gender match.',
                        style: AppTheme.body(size: 10),
                      ),

                      const SizedBox(height: 22),

                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop(
                                    const _SortFilterResult(
                                      sort: _StockSort.newest,
                                      gender: null,
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                  AppColors.textDark,
                                  side: const BorderSide(
                                    color: AppColors.divider,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Reset',
                                  style: AppTheme.heading(
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop(
                                    _SortFilterResult(
                                      sort: sort,
                                      gender: gender,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  AppColors.darkGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Apply',
                                  style: AppTheme.heading(
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _sort = result.sort;
      _genderFilter = result.gender;
    });
  }

  Widget _sheetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.textDark : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.textDark
                  : AppColors.divider,
            ),
          ),
          child: Text(
            label,
            style: AppTheme.body(
              size: 12,
              weight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      floatingActionButton: _farmId == null
          ? null
          : FloatingActionButton(
        onPressed: _openPurchase,
        tooltip: 'Purchase a goat',
        backgroundColor: AppColors.darkGreen,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.add_rounded,
          size: 30,
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _header() {
    final farmId = _farmId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          _roundButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 17,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Goat Stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 21),
                ),

                if (farmId != null)
                  StreamBuilder<FarmModel?>(
                    stream: _farmStream,
                    builder: (context, snapshot) {
                      final name =
                          snapshot.data?.farmName.trim() ?? '';

                      return Text(
                        name.isEmpty ? 'Trading' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.textGrey,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          if (farmId != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                _roundButton(
                  icon: Icons.tune_rounded,
                  iconSize: 20,
                  tooltip: 'Sort & filter',
                  onTap: _openSortFilterSheet,
                ),

                if (_hasSortOrGender)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.darkGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.paleGreen,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required double iconSize,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BODY
  // ===========================================================================

  Widget _buildBody() {
    if (_loadingFarm) {
      return const _GoatStockSkeleton();
    }

    final farmId = _farmId;
    final stream = _goatsStream;

    if (farmId == null || stream == null) {
      return FarmNotLinkedState(
        buttonColor: AppColors.primaryGreen,
        onRetry: _loadFarm,
      );
    }

    return StreamBuilder<List<Goat>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorState();
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _GoatStockSkeleton();
        }

        final allGoats = snapshot.data ?? [];

        return _buildContent(allGoats);
      },
    );
  }

  // ===========================================================================
  // CONTENT
  // ===========================================================================

  int _count(List<Goat> goats, String? status) {
    if (status == null) return goats.length;

    return goats.where((goat) => _hasStatus(goat, status)).length;
  }

  List<Goat> _visibleGoats(List<Goat> allGoats) {
    var goats = List<Goat>.from(allGoats);

    // Status
    final status = _statusFilter;

    if (status != null) {
      goats = goats.where((g) => _hasStatus(g, status)).toList();
    }

    // Gender
    final gender = _genderFilter;

    if (gender != null) {
      goats = goats
          .where(
            (g) => g.gender.trim().toLowerCase() ==
            gender.toLowerCase(),
      )
          .toList();
    }

    // Search
    if (_search.isNotEmpty) {
      goats = goats
          .where(
            (g) =>
        g.id.toLowerCase().contains(_search) ||
            g.breed.toLowerCase().contains(_search) ||
            g.color.toLowerCase().contains(_search),
      )
          .toList();
    }

    // Sort. The stream already arrives newest first.
    switch (_sort) {
      case _StockSort.newest:
        break;

      case _StockSort.oldest:
        goats = goats.reversed.toList();
        break;

      case _StockSort.heaviest:
        goats.sort((a, b) => b.weight.compareTo(a.weight));
        break;

      case _StockSort.youngest:
        goats.sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
        break;
    }

    return goats;
  }

  Widget _buildContent(List<Goat> allGoats) {
    final goats = _visibleGoats(allGoats);

    return CustomScrollView(
      keyboardDismissBehavior:
      ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        // ---------------------------------------------------------------------
        // SUMMARY
        // ---------------------------------------------------------------------

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: _summary(allGoats),
          ),
        ),

        // ---------------------------------------------------------------------
        // SEARCH
        // ---------------------------------------------------------------------

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _searchBox(),
          ),
        ),

        // ---------------------------------------------------------------------
        // FILTERS (pinned so they stay reachable while scrolling)
        // ---------------------------------------------------------------------

        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBarDelegate(
            height: 62,
            child: _filters(allGoats),
          ),
        ),

        // ---------------------------------------------------------------------
        // LIST
        // ---------------------------------------------------------------------

        if (goats.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(hasAnyGoats: allGoats.isNotEmpty),
          )
        else
          SliverPadding(
            // Extra bottom space so the floating "+" never covers the
            // last card's actions.
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 104),
            sliver: SliverList.separated(
              itemCount: goats.length,
              separatorBuilder: (_, __) =>
              const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final goat = goats[index];

                final canCompleteDelivery =
                    _hasStatus(goat, Goat.statusBooked) ||
                        _hasStatus(
                          goat,
                          Goat.statusWaitOnDelivery,
                        );

                return _GoatStockCard(
                  goat: goat,
                  onTap: () => _openDetail(goat),
                  onCompleteDelivery: canCompleteDelivery
                      ? () => _openCompleteDelivery(goat)
                      : null,
                  onLogWeighIn: _hasStatus(
                    goat,
                    Goat.statusOwnPalai,
                  )
                      ? () => _openLogWeighIn(goat)
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _summary(List<Goat> allGoats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 14,
      ),
      decoration: AppTheme.card(radius: 22).copyWith(
        border: Border.all(
          color: AppColors.divider.withOpacity(0.6),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _summaryItem(
                icon: Icons.inventory_2_outlined,
                label: 'Total Herd',
                value: allGoats.length,
                color: AppColors.stockTeal,
                status: null,
              ),
            ),

            _divider(),

            Expanded(
              child: _summaryItem(
                icon: Icons.check_circle_outline_rounded,
                label: 'Available',
                value: _count(allGoats, Goat.statusAvailable),
                color: AppColors.success,
                status: Goat.statusAvailable,
              ),
            ),

            _divider(),

            Expanded(
              child: _summaryItem(
                icon: Icons.bookmark_border_rounded,
                label: 'Booked',
                value: _count(allGoats, Goat.statusBooked),
                color: AppColors.warning,
                status: Goat.statusBooked,
              ),
            ),

            _divider(),

            Expanded(
              child: _summaryItem(
                icon: Icons.sell_outlined,
                label: 'Sold Out',
                value: _count(allGoats, Goat.statusSold),
                color: AppColors.error,
                status: Goat.statusSold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    required String? status,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _statusFilter = status;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: color,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              '$value',
              style: AppTheme.heading(
                size: 22,
                color: AppColors.textDark,
              ),
            ),

            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: AppColors.divider,
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  Widget _searchBox() {
    return Container(
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(
          color: AppColors.divider.withOpacity(0.6),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _search = value.trim().toLowerCase();
          });
        },
        textInputAction: TextInputAction.search,
        style: AppTheme.body(
          size: 13,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          hintText: 'Search ID, breed or color',
          hintStyle: AppTheme.body(
            size: 13,
            color: AppColors.textGrey,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 22,
            color: AppColors.textGrey,
          ),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              _searchController.clear();

              setState(() {
                _search = '';
              });
            },
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
              color: AppColors.textGrey,
            ),
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 15,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  Widget _filters(List<Goat> allGoats) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      scrollDirection: Axis.horizontal,
      children: [
        _filterChip(
          label: 'All Animals',
          status: null,
          count: allGoats.length,
        ),

        ...Goat.statusValues.map((status) {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _filterChip(
              label: _statusLabel(status),
              status: status,
              count: _count(allGoats, status),
            ),
          );
        }),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required String? status,
    required int count,
  }) {
    final selected = _statusFilter == status;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _statusFilter = status;
          });
        },
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.textDark : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? AppColors.textDark
                  : AppColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != null && !selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],

              Text(
                label,
                style: AppTheme.body(
                  size: 13,
                  weight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppColors.textDark,
                ),
              ),

              const SizedBox(width: 7),

              if (selected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.body(
                      size: 11,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Text(
                  '$count',
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // EMPTY STATE
  // ===========================================================================

  Widget _emptyState({required bool hasAnyGoats}) {
    final hasStatusFilter = _statusFilter != null;
    final hasSearch = _search.isNotEmpty;
    final hasGender = _genderFilter != null;

    String title;
    String subtitle;

    if (hasSearch) {
      title = 'No matching goats';
      subtitle = 'Try a different ID, breed or color.';
    } else if (hasStatusFilter || hasGender) {
      title = 'No goats match these filters';
      subtitle = hasStatusFilter
          ? 'There are no goats marked as '
          '"${_statusLabel(_statusFilter!)}"'
          '${hasGender ? ' with that gender' : ''}.'
          : 'No goats have the selected gender recorded.';
    } else {
      title = 'No goats registered';
      subtitle =
      'Purchase a goat to start building your stock.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.stockTeal.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 29,
                color: AppColors.stockTeal,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 16),
            ),

            const SizedBox(height: 5),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12),
            ),

            if (!hasAnyGoats && !hasSearch) ...[
              const SizedBox(height: 18),

              ElevatedButton.icon(
                onPressed: _openPurchase,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(
                  'Purchase a Goat',
                  style: AppTheme.heading(
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.error,
            ),

            const SizedBox(height: 12),

            Text(
              'Unable to load goat stock',
              style: AppTheme.heading(size: 16),
            ),

            const SizedBox(height: 5),

            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12),
            ),

            const SizedBox(height: 14),

            OutlinedButton(
              onPressed: _loadFarm,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PINNED BAR (filters)
// ============================================================================

class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _PinnedBarDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
    return Container(
      color: AppColors.paleGreen,
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedBarDelegate oldDelegate) {
    return true;
  }
}

// ============================================================================
// GOAT STOCK CARD
// ============================================================================

class _GoatStockCard extends StatelessWidget {
  final Goat goat;
  final VoidCallback onTap;

  /// Non-null only for Booked / Wait-on-Delivery goats — renders a
  /// "Complete Delivery" shortcut directly on the card when set.
  final VoidCallback? onCompleteDelivery;

  /// Non-null only for Own Palai goats — renders a "Log Weigh-in"
  /// shortcut in the card footer when set.
  final VoidCallback? onLogWeighIn;

  const _GoatStockCard({
    required this.goat,
    required this.onTap,
    this.onCompleteDelivery,
    this.onLogWeighIn,
  });

  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  /// "G-0003" -> "#03". Null when the id carries no number.
  String? get _badge {
    final match = RegExp(r'(\d+)$').firstMatch(goat.id);

    if (match == null) return null;

    final number = int.tryParse(match.group(1) ?? '');

    if (number == null) return null;

    return '#${number.toString().padLeft(2, '0')}';
  }

  String? get _genderLabel {
    switch (goat.gender.trim().toLowerCase()) {
      case 'male':
        return 'Buck (Male)';
      case 'female':
        return 'Doe (Female)';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final footer = _footer();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(radius: 22).copyWith(
            border: Border.all(
              color: AppColors.divider.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topRow(),

              if (footer != null) ...[
                const SizedBox(height: 12),
                const Divider(
                  height: 1,
                  color: AppColors.divider,
                ),
                const SizedBox(height: 12),
                footer,
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP ROW
  // ---------------------------------------------------------------------------

  Widget _topRow() {
    final color = _statusColor(goat.currentStatus);
    final gender = _genderLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _photo(),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ID + health dot ............ status pill
              LayoutBuilder(
                builder: (context, constraints) {
                  // The pill keeps its natural width but never takes
                  // more than ~60% of the row, so the ID always stays
                  // readable on narrow screens / large text sizes.
                  final maxPillWidth = constraints.maxWidth * 0.6;

                  return Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment:
                          MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                goat.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.heading(
                                  size: 17,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),

                            Tooltip(
                              message: goat.healthStatus,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: _healthColor(
                                    goat.healthStatus,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxPillWidth,
                        ),
                        child: _statusPill(color),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 2),

              Text(
                goat.breed.trim().isEmpty
                    ? 'Breed not specified'
                    : goat.breed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 12.5,
                  color: AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 9),

              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _infoChip(
                    Icons.calendar_month_outlined,
                    goat.age,
                  ),
                  _infoChip(
                    Icons.monitor_weight_outlined,
                    '${goat.weight.toStringAsFixed(1)} kg',
                  ),
                ],
              ),

              if (gender != null) ...[
                const SizedBox(height: 8),
                _tag(
                  gender,
                  goat.gender.trim().toLowerCase() == 'female'
                      ? AppColors.breedingPurple
                      : AppColors.success,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _photo() {
    final badge = _badge;

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.stockTeal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (goat.photo != null)
            Image.memory(
              goat.photo!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: 228,
            )
          else
            const Center(
              child: Icon(
                Icons.pets_outlined,
                size: 28,
                color: AppColors.stockTeal,
              ),
            ),

          if (badge != null)
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 5),

          Flexible(
            child: Text(
              _statusLabel(goat.currentStatus),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _statusTextColor(color),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.textGrey,
          ),

          const SizedBox(width: 5),

          Text(
            text,
            style: AppTheme.body(
              size: 11.5,
              color: AppColors.textDark,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _statusTextColor(color),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER (depends on status)
  // ---------------------------------------------------------------------------

  Widget? _footer() {
    // Booked / Wait on Delivery -> primary action.
    if (onCompleteDelivery != null) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: onCompleteDelivery,
                icon: const Icon(
                  Icons.check_rounded,
                  size: 19,
                ),
                label: Text(
                  'Complete Delivery',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          Tooltip(
            message: 'View details',
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Sold Out -> sale reference + details link.
    if (_hasStatus(goat, Goat.statusSold)) {
      final saleId = goat.saleId;

      return _footerRow(
        leading: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: AppColors.success,
            ),

            const SizedBox(width: 7),

            Expanded(
              child: Text(
                saleId == null || saleId.trim().isEmpty
                    ? 'Sold'
                    : 'Sale $saleId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 12,
                  color: AppColors.textGrey,
                ),
              ),
            ),
          ],
        ),
        action: _linkAction('Details'),
      );
    }

    // Own Palai -> since date + weigh-in shortcut.
    if (onLogWeighIn != null) {
      final since = goat.movedToOwnPalaiAt;

      return _footerRow(
        leading: Text(
          since == null
              ? 'In Own Palai'
              : 'In Own Palai since ${_dateFormat.format(since)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
          ),
        ),
        action: Material(
          color: AppColors.paleGreen,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onLogWeighIn,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: AppColors.textDark,
                  ),

                  const SizedBox(width: 4),

                  Text(
                    'Log Weigh-in',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Available / In Customer Palai / anything else.
    final purchased = _dateFormat.format(goat.purchaseDate);

    final reference = goat.purchaseId.trim().isEmpty
        ? 'Purchased $purchased'
        : 'Purchased $purchased · ${goat.purchaseId}';

    return _footerRow(
      leading: Text(
        reference,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.body(
          size: 12,
          color: AppColors.textGrey,
        ),
      ),
      action: _linkAction('Details'),
    );
  }

  Widget _footerRow({
    required Widget leading,
    required Widget action,
  }) {
    return Row(
      children: [
        Expanded(child: leading),
        const SizedBox(width: 10),
        action,
      ],
    );
  }

  /// Text link with a chevron. The whole card is already tappable, so this
  /// is purely a visual affordance and defers to [onTap].
  Widget _linkAction(String label) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.body(
                size: 13,
                color: AppColors.darkGreen,
                weight: FontWeight.w700,
              ),
            ),

            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.darkGreen,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SKELETON LOADING
// ============================================================================

class _GoatStockSkeleton extends StatefulWidget {
  const _GoatStockSkeleton();

  @override
  State<_GoatStockSkeleton> createState() =>
      _GoatStockSkeletonState();
}

class _GoatStockSkeletonState
    extends State<_GoatStockSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
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
        final opacity = 0.45 + (_controller.value * 0.25);

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
          child: Column(
            children: [
              _box(height: 112, radius: 22, opacity: opacity),

              const SizedBox(height: 14),

              _box(height: 52, radius: 18, opacity: opacity),

              const SizedBox(height: 14),

              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(flex: 5, child: _pill(opacity: opacity)),
                    const SizedBox(width: 8),
                    Expanded(flex: 4, child: _pill(opacity: opacity)),
                    const SizedBox(width: 8),
                    Expanded(flex: 4, child: _pill(opacity: opacity)),
                    const SizedBox(width: 8),
                    Expanded(flex: 4, child: _pill(opacity: opacity)),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              for (int i = 0; i < 4; i++) ...[
                _goatCardSkeleton(opacity: opacity),
                if (i != 3) const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _box({
    required double height,
    required double radius,
    required double opacity,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.divider.withOpacity(opacity),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _pill({required double opacity}) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.divider.withOpacity(opacity),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }

  Widget _bar({
    required double width,
    required double height,
    required double opacity,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.divider.withOpacity(opacity),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _goatCardSkeleton({required double opacity}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 22),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.divider.withOpacity(opacity),
              borderRadius: BorderRadius.circular(18),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(width: 110, height: 14, opacity: opacity),
                const SizedBox(height: 9),
                _bar(width: 150, height: 10, opacity: opacity),
                const SizedBox(height: 12),
                _bar(width: 120, height: 22, opacity: opacity),
              ],
            ),
          ),
        ],
      ),
    );
  }
}