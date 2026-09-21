import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/farm_model.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import '../own_palai/add_weight_entry_screen.dart';
import '../register_goats/goat_registration_form_screen.dart';
import 'complete_booking_delivery_screen.dart';
import 'complete_wait_for_delivery_screen.dart';
import 'goat_stock_detail_screen.dart';
import '../purchase_goats/individual_goat_purchase_screen.dart';

// ============================================================================
// SHARED STATUS HELPERS
// ============================================================================

/// Pseudo-status for the "Unregistered" tab. Unregistered goats have no goat
/// record (they only exist as a count on their purchase), so this is never
/// stored on a [Goat] — it only drives the tab / filter.
const String _kUnregistered = GoatStockListScreen.statusUnregistered;

/// Tabs shown after "All", in display order.
const List<String> _stockTabs = [
  Goat.statusAvailable,
  _kUnregistered,
  Goat.statusBooked,
  Goat.statusWaitOnDelivery,
  Goat.statusOwnPalai,
  Goat.statusSold,
];

/// The "All" tab shows Available goats (plus the unregistered batches).
/// Booked, Wait on Delivery, Own Palai and Sold goats live in their own tabs.
bool _showInAll(Goat goat) => _hasStatus(goat, Goat.statusAvailable);

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

    case Goat.statusOwnPalai:
      return AppColors.tradingBlue;

    case _kUnregistered:
      return AppColors.warning;

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
/// - Pinned filter tabs with counts: All, Available, Unregistered, Booked,
///   Wait on Delivery, Own Palai, Sold Out
///
/// "All" shows Available goats plus Unregistered goats. Unregistered goats
/// (received but not yet tagged/weighed) have no goat record yet, so they
/// appear as one card per purchase with a "Register Goats" action.
/// - Status-aware goat cards (Customer Palai goats are not shown here —
///   they are managed in the Customer Palai module)
/// - Floating "+" button to purchase an individual goat
/// - Skeleton loading
///
/// Farm ID is resolved internally, so this screen does not require a
/// farmId constructor parameter.
class GoatStockListScreen extends StatefulWidget {
  /// Value for [initialStatusFilter] that opens the "Unregistered" tab.
  static const String statusUnregistered = 'Unregistered';

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

  Stream<List<Goat>>? _goatsStream;
  Stream<FarmModel?>? _farmStream;

  /// Purchases (receiving completed) that still have goats to register.
  Stream<List<TradingPurchase>>? _unregisteredStream;

  final TextEditingController _searchController =
  TextEditingController();

  String _search = '';

  late String? _statusFilter =
  widget.initialStatusFilter == Goat.statusInCustomerPalai
      ? null
      : widget.initialStatusFilter;

  _StockSort _sort = _StockSort.newest;

  String? _genderFilter;

  bool get _hasSortOrGender =>
      _sort != _StockSort.newest || _genderFilter != null;

  // There are more tabs than fit on a phone screen, so the selected one is
  // scrolled into view (deep links and summary taps can select a tab that is
  // off-screen).
  final Map<String?, GlobalKey> _chipKeys = <String?, GlobalKey>{};
  bool _centerSelectedChip = true;

  void _setStatusFilter(String? status) {
    setState(() {
      _statusFilter = status;
      _centerSelectedChip = true;
    });
  }

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

      _unregisteredStream = farmId == null
          ? null
          : TradingService.instance.pendingRegistrationStream(farmId);

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

  void _openRegister(TradingPurchase purchase) {
    final farmId = _farmId;

    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        GoatRegistrationFormScreen(
          farmId: farmId,
          purchase: purchase,
        ),
      ),
    );
  }

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
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  18,
                  10,
                  18,
                  18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius:
                            BorderRadius.circular(20),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'Sort & filter',
                        style: AppTheme.heading(size: 16),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'Sort by',
                        style: AppTheme.body(
                          size: 10.5,
                          weight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
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

                      const SizedBox(height: 15),

                      Text(
                        'Gender',
                        style: AppTheme.body(
                          size: 10.5,
                          weight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
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

                      const SizedBox(height: 5),

                      Text(
                        'Only goats with a recorded gender match. Unregistered goats '
                            'have none yet, so they are hidden.',
                        style: AppTheme.body(size: 9.5),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
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
                                    BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Reset',
                                  style: AppTheme.heading(
                                    size: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 44,
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
                                    BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Apply',
                                  style: AppTheme.heading(
                                    size: 13,
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.textDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.textDark
                  : AppColors.divider,
            ),
          ),
          child: Text(
            label,
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : AppColors.textDark,
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
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.add_rounded,
          size: 27,
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
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        children: [
          _roundButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 15,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Goat Stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 19),
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
                          size: 10.5,
                          color: AppColors.textGrey,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(width: 9),

          if (farmId != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                _roundButton(
                  icon: Icons.tune_rounded,
                  iconSize: 18,
                  tooltip: 'Sort & filter',
                  onTap: _openSortFilterSheet,
                ),

                if (_hasSortOrGender)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 9,
                      height: 9,
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
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
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

        // Goats kept for a customer live in the Customer Palai module, not
        // in Trading stock — they are left out of the list AND the counts.
        final allGoats = (snapshot.data ?? <Goat>[])
            .where((goat) => !goat.isInCustomerPalai)
            .toList();

        // Second source: purchases that still have goats waiting to be
        // registered. Those goats have no goat record yet.
        return StreamBuilder<List<TradingPurchase>>(
          stream: _unregisteredStream,
          builder: (context, batchSnapshot) {
            if (batchSnapshot.connectionState ==
                ConnectionState.waiting &&
                !batchSnapshot.hasData) {
              return const _GoatStockSkeleton();
            }

            // If this stream fails, the registered goats are still shown
            // rather than blocking the whole screen.
            final batches =
                batchSnapshot.data ?? const <TradingPurchase>[];

            return _buildContent(allGoats, batches);
          },
        );
      },
    );
  }

  // ===========================================================================
  // CONTENT
  // ===========================================================================

  /// Goats waiting to be registered, across all purchases.
  int _unregisteredTotal(List<TradingPurchase> batches) {
    return batches.fold<int>(0, (sum, p) => sum + p.pendingCount);
  }

  /// Number shown on a tab / summary stat. [status] null = "All".
  int _count(
      List<Goat> goats,
      List<TradingPurchase> batches,
      String? status,
      ) {
    if (status == null) {
      return goats.where(_showInAll).length +
          _unregisteredTotal(batches);
    }

    if (status == _kUnregistered) {
      return _unregisteredTotal(batches);
    }

    return goats.where((goat) => _hasStatus(goat, status)).length;
  }

  List<Goat> _visibleGoats(List<Goat> allGoats) {
    final status = _statusFilter;

    // "All" = Available only (unregistered batches are added separately).
    // The Unregistered tab has no registered goats at all.
    var goats = status == null
        ? allGoats.where(_showInAll).toList()
        : status == _kUnregistered
        ? <Goat>[]
        : allGoats.where((g) => _hasStatus(g, status)).toList();

    final gender = _genderFilter;

    if (gender != null) {
      goats = goats
          .where(
            (g) =>
        g.gender.trim().toLowerCase() ==
            gender.toLowerCase(),
      )
          .toList();
    }

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

  /// Unregistered batches that pass the current tab / search / sort.
  List<TradingPurchase> _visibleBatches(List<TradingPurchase> batches) {
    final status = _statusFilter;

    // Batches belong to "All" and "Unregistered" only.
    if (status != null && status != _kUnregistered) {
      return const <TradingPurchase>[];
    }

    // No gender is recorded for unregistered goats.
    if (_genderFilter != null) {
      return const <TradingPurchase>[];
    }

    var result = List<TradingPurchase>.from(batches);

    if (_search.isNotEmpty) {
      result = result
          .where(
            (p) =>
        p.id.toLowerCase().contains(_search) ||
            p.sellerName.toLowerCase().contains(_search),
      )
          .toList();
    }

    // Weight / age sorts don't apply to a batch, so those keep the stream
    // order (newest first). Only "Oldest first" flips it.
    if (_sort == _StockSort.oldest) {
      result = result.reversed.toList();
    }

    return result;
  }

  Widget _buildContent(
      List<Goat> allGoats,
      List<TradingPurchase> batches,
      ) {
    final goats = _visibleGoats(allGoats);
    final visibleBatches = _visibleBatches(batches);
    final itemCount = goats.length + visibleBatches.length;

    return CustomScrollView(
      keyboardDismissBehavior:
      ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 1, 14, 10),
            child: _summary(allGoats, batches),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _searchBox(),
          ),
        ),

        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBarDelegate(
            height: 56,
            child: _filters(allGoats, batches),
          ),
        ),

        if (itemCount == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(
              hasAnyGoats:
              allGoats.isNotEmpty || batches.isNotEmpty,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 94),
            sliver: SliverList.separated(
              itemCount: itemCount,
              separatorBuilder: (_, __) =>
              const SizedBox(height: 9),
              itemBuilder: (context, index) {
                // Registered goats first, unregistered batches after.
                if (index >= goats.length) {
                  final purchase =
                  visibleBatches[index - goats.length];

                  return _UnregisteredBatchCard(
                    purchase: purchase,
                    onRegister: () => _openRegister(purchase),
                  );
                }

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
                  onCompleteDelivery:
                  canCompleteDelivery
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

  Widget _summary(
      List<Goat> allGoats,
      List<TradingPurchase> batches,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: 10,
      ),
      decoration: AppTheme.card(radius: 18).copyWith(
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
                icon: Icons.check_circle_outline_rounded,
                label: 'Available',
                value: _count(
                  allGoats,
                  batches,
                  Goat.statusAvailable,
                ),
                color: AppColors.success,
                status: Goat.statusAvailable,
              ),
            ),

            _divider(),

            Expanded(
              child: _summaryItem(
                icon: Icons.how_to_reg_outlined,
                label: 'Unregistered',
                value: _count(
                  allGoats,
                  batches,
                  _kUnregistered,
                ),
                color: AppColors.warning,
                status: _kUnregistered,
              ),
            ),

            _divider(),

            Expanded(
              child: _summaryItem(
                icon: Icons.bookmark_border_rounded,
                label: 'Booked',
                value: _count(
                  allGoats,
                  batches,
                  Goat.statusBooked,
                ),
                color: AppColors.warning,
                status: Goat.statusBooked,
              ),
            ),

            _divider(),

            Expanded(
              child: _summaryItem(
                icon: Icons.sell_outlined,
                label: 'Sold Out',
                value: _count(
                  allGoats,
                  batches,
                  Goat.statusSold,
                ),
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
      onTap: () => _setStatusFilter(status),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 1,
          vertical: 1,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 17,
                color: color,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              '$value',
              style: AppTheme.heading(
                size: 19,
                color: AppColors.textDark,
              ),
            ),

            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 9.5,
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
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: AppColors.divider,
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  Widget _searchBox() {
    return Container(
      height: 46,
      decoration: AppTheme.card(radius: 15).copyWith(
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
          size: 12,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          hintText: 'Search ID, breed, color or seller',
          hintStyle: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 20,
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
              size: 17,
              color: AppColors.textGrey,
            ),
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  Widget _filters(
      List<Goat> allGoats,
      List<TradingPurchase> batches,
      ) {
    // After this frame, scroll the selected tab into view (a deep link or a
    // summary tap can select a tab that is off-screen).
    if (_centerSelectedChip) {
      _centerSelectedChip = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final chipContext = _chipKeys[_statusFilter]?.currentContext;
        if (chipContext == null) return;

        Scrollable.ensureVisible(
          chipContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      scrollDirection: Axis.horizontal,
      // Build every tab up front so an off-screen selected tab can be
      // scrolled to (there are only a handful).
      cacheExtent: 1500,
      children: [
        _filterChip(
          label: 'All',
          status: null,
          count: _count(allGoats, batches, null),
        ),

        for (final status in _stockTabs)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _filterChip(
              label: _statusLabel(status),
              status: status,
              count: _count(allGoats, batches, status),
            ),
          ),
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
      key: _chipKeys.putIfAbsent(status, () => GlobalKey()),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _setStatusFilter(status),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.textDark
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
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
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],

              Text(
                label,
                style: AppTheme.body(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppColors.textDark,
                ),
              ),

              const SizedBox(width: 5),

              if (selected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.body(
                      size: 10,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Text(
                  '$count',
                  style: AppTheme.body(
                    size: 10.5,
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
    final status = _statusFilter;
    final hasSearch = _search.isNotEmpty;
    final hasGender = _genderFilter != null;

    String title;
    String subtitle;

    if (hasSearch) {
      title = 'No matching goats';
      subtitle = 'Try a different ID, breed, color or seller.';
    } else if (hasGender) {
      title = 'No goats match these filters';
      subtitle = status != null && status != _kUnregistered
          ? 'There are no goats marked as '
          '"${_statusLabel(status)}" with that gender.'
          : 'No goats have the selected gender recorded.';
    } else if (status == _kUnregistered) {
      title = 'No unregistered goats';
      subtitle = 'Every received goat has been registered.';
    } else if (status != null) {
      title = 'No goats match these filters';
      subtitle = 'There are no goats marked as '
          '"${_statusLabel(status)}".';
    } else if (hasAnyGoats) {
      // "All" only lists Available + Unregistered goats.
      title = 'No available or unregistered goats';
      subtitle =
      'Booked, sold and other goats are under their own tabs.';
    } else {
      title = 'No goats registered';
      subtitle =
      'Purchase a goat to start building your stock.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          24,
          18,
          24,
          100,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.stockTeal.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 25,
                color: AppColors.stockTeal,
              ),
            ),

            const SizedBox(height: 11),

            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 15),
            ),

            const SizedBox(height: 4),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),

            if (!hasAnyGoats && !hasSearch) ...[
              const SizedBox(height: 15),

              ElevatedButton.icon(
                onPressed: _openPurchase,
                icon: const Icon(
                  Icons.add_rounded,
                  size: 18,
                ),
                label: Text(
                  'Purchase a Goat',
                  style: AppTheme.heading(
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.error,
            ),

            const SizedBox(height: 10),

            Text(
              'Unable to load goat stock',
              style: AppTheme.heading(size: 15),
            ),

            const SizedBox(height: 4),

            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),

            const SizedBox(height: 12),

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
  final VoidCallback? onCompleteDelivery;
  final VoidCallback? onLogWeighIn;

  const _GoatStockCard({
    required this.goat,
    required this.onTap,
    this.onCompleteDelivery,
    this.onLogWeighIn,
  });

  static final DateFormat _dateFormat =
  DateFormat('d MMM yyyy');

  String? get _badge {
    final match = RegExp(r'(\d+)$').firstMatch(goat.id);

    if (match == null) return null;

    final number =
    int.tryParse(match.group(1) ?? '');

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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: AppTheme.card(radius: 18).copyWith(
            border: Border.all(
              color: AppColors.divider.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topRow(),

              if (footer != null) ...[
                const SizedBox(height: 9),
                const Divider(
                  height: 1,
                  color: AppColors.divider,
                ),
                const SizedBox(height: 9),
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

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxPillWidth =
                      constraints.maxWidth * 0.55;

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
                                overflow:
                                TextOverflow.ellipsis,
                                style: AppTheme.heading(
                                  size: 15.5,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),

                            const SizedBox(width: 5),

                            Tooltip(
                              message: goat.healthStatus,
                              child: Container(
                                width: 6,
                                height: 6,
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

                      const SizedBox(width: 6),

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

              const SizedBox(height: 1),

              Text(
                goat.breed.trim().isEmpty
                    ? 'Breed not specified'
                    : goat.breed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 11.5,
                  color: AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 7),

              Wrap(
                spacing: 5,
                runSpacing: 5,
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
                const SizedBox(height: 6),
                _tag(
                  gender,
                  goat.gender.trim().toLowerCase() ==
                      'female'
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
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.stockTeal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(15),
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
              cacheWidth: 186,
            )
          else
            const Center(
              child: Icon(
                GoatIcons.paw,
                size: 24,
                color: AppColors.stockTeal,
              ),
            ),

          if (badge != null)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
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
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 4),

          Flexible(
            child: Text(
              _statusLabel(goat.currentStatus),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _statusTextColor(color),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(
      IconData icon,
      String text,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: AppColors.textGrey,
          ),

          const SizedBox(width: 4),

          Text(
            text,
            style: AppTheme.body(
              size: 10,
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
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _statusTextColor(color),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER
  // ---------------------------------------------------------------------------

  Widget? _footer() {
    if (onCompleteDelivery != null) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: onCompleteDelivery,
                icon: const Icon(
                  Icons.check_rounded,
                  size: 17,
                ),
                label: Text(
                  'Complete Delivery',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 12.5,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          Tooltip(
            message: 'View details',
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: AppColors.divider,
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_hasStatus(goat, Goat.statusSold)) {
      final saleId = goat.saleId;

      return _footerRow(
        leading: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: AppColors.success,
            ),

            const SizedBox(width: 6),

            Expanded(
              child: Text(
                saleId == null ||
                    saleId.trim().isEmpty
                    ? 'Sold'
                    : 'Sale $saleId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                ),
              ),
            ),
          ],
        ),
        action: _linkAction('Details'),
      );
    }

    if (onLogWeighIn != null) {
      final since = goat.movedToOwnPalaiAt;

      return _footerRow(
        leading: Text(
          since == null
              ? 'In Own Palai'
              : 'In Own Palai since '
              '${_dateFormat.format(since)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body(
            size: 11,
            color: AppColors.textGrey,
          ),
        ),
        action: Material(
          color: AppColors.paleGreen,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onLogWeighIn,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 14,
                    color: AppColors.textDark,
                  ),

                  const SizedBox(width: 3),

                  Text(
                    'Log Weigh-in',
                    style: AppTheme.body(
                      size: 10.5,
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

    final purchased =
    _dateFormat.format(goat.purchaseDate);

    final reference = goat.purchaseId.trim().isEmpty
        ? 'Purchased $purchased'
        : 'Purchased $purchased · ${goat.purchaseId}';

    return _footerRow(
      leading: Text(
        reference,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.body(
          size: 11,
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
        const SizedBox(width: 8),
        action,
      ],
    );
  }

  Widget _linkAction(String label) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 3,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.body(
                size: 11.5,
                color: AppColors.darkGreen,
                weight: FontWeight.w700,
              ),
            ),

            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.darkGreen,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// UNREGISTERED BATCH CARD
// ============================================================================

/// One card per purchase that still has goats waiting to be registered.
///
/// Unregistered goats have no goat record yet — they exist only as a count
/// on their purchase — so they are shown as a batch ("8 goats") instead of
/// one identical card per goat. The whole card and the button open the
/// registration form for that purchase.
class _UnregisteredBatchCard extends StatelessWidget {
  final TradingPurchase purchase;
  final VoidCallback onRegister;

  const _UnregisteredBatchCard({
    required this.purchase,
    required this.onRegister,
  });

  static final DateFormat _dateFormat =
  DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(_kUnregistered);
    final pending = purchase.pendingCount;
    final registered = purchase.registeredCount;
    final seller = purchase.sellerName.trim();
    final received =
        purchase.dateReceivedAtFarm ?? purchase.purchaseDate;

    final reference = seller.isEmpty
        ? 'Purchase ${purchase.id}'
        : 'Purchase ${purchase.id} · $seller';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRegister,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: AppTheme.card(radius: 18).copyWith(
            border: Border.all(
              color: AppColors.divider.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.how_to_reg_outlined,
                      size: 26,
                      color: _statusTextColor(color),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                pending == 1
                                    ? '1 goat'
                                    : '$pending goats',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.heading(
                                  size: 15.5,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),

                            _statusPill(color),
                          ],
                        ),

                        const SizedBox(height: 1),

                        Text(
                          reference,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            size: 11.5,
                            color: AppColors.textGrey,
                          ),
                        ),

                        const SizedBox(height: 7),

                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            _infoChip(
                              Icons.calendar_month_outlined,
                              'Received '
                                  '${_dateFormat.format(received)}',
                            ),
                            _infoChip(
                              Icons.checklist_rounded,
                              '$registered of '
                                  '${registered + pending} '
                                  'registered',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 9),
              const Divider(
                height: 1,
                color: AppColors.divider,
              ),
              const SizedBox(height: 9),

              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: onRegister,
                  icon: const Icon(
                    Icons.how_to_reg_outlined,
                    size: 17,
                  ),
                  label: Text(
                    'Register Goats',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(
                      size: 12.5,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 4),

          Text(
            _statusLabel(_kUnregistered),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: _statusTextColor(color),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(
      IconData icon,
      String text,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: AppColors.textGrey,
          ),

          const SizedBox(width: 4),

          Text(
            text,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textDark,
              weight: FontWeight.w500,
            ),
          ),
        ],
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
        final opacity =
            0.45 + (_controller.value * 0.25);

        return SingleChildScrollView(
          physics:
          const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            14,
            1,
            14,
            20,
          ),
          child: Column(
            children: [
              _box(
                height: 94,
                radius: 18,
                opacity: opacity,
              ),

              const SizedBox(height: 10),

              _box(
                height: 46,
                radius: 15,
                opacity: opacity,
              ),

              const SizedBox(height: 10),

              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _pill(
                        opacity: opacity,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: _pill(
                        opacity: opacity,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: _pill(
                        opacity: opacity,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: _pill(
                        opacity: opacity,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              for (int i = 0; i < 4; i++) ...[
                _goatCardSkeleton(
                  opacity: opacity,
                ),
                if (i != 3)
                  const SizedBox(height: 9),
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

  Widget _pill({
    required double opacity,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.divider.withOpacity(opacity),
        borderRadius: BorderRadius.circular(18),
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
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }

  Widget _goatCardSkeleton({
    required double opacity,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: AppTheme.card(radius: 18),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color:
              AppColors.divider.withOpacity(opacity),
              borderRadius: BorderRadius.circular(15),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                _bar(
                  width: 95,
                  height: 12,
                  opacity: opacity,
                ),
                const SizedBox(height: 7),
                _bar(
                  width: 130,
                  height: 9,
                  opacity: opacity,
                ),
                const SizedBox(height: 9),
                _bar(
                  width: 105,
                  height: 19,
                  opacity: opacity,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}