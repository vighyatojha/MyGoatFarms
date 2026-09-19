import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/farm_not_linked_state.dart';
import 'complete_booking_delivery_screen.dart';
import 'complete_wait_for_delivery_screen.dart';
import 'goat_stock_detail_screen.dart';

/// Goat Stock list.
///
/// Displays registered trading goats with:
/// - Compact stock summary
/// - Search
/// - Status filters
/// - Compact goat cards
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

  final TextEditingController _searchController =
  TextEditingController();

  String _search = '';

  /// null = All.
  late String? _statusFilter = widget.initialStatusFilter;

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

    setState(() {
      _farmId =
      id == null || id.trim().isEmpty
          ? null
          : id.trim();

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
        GoatStockDetailScreen(
          farmId: farmId,
          goat: goat,
        ),
      ),
    );
  }

  /// Card-level shortcut so a Booked / Wait-on-Delivery goat's
  /// "Complete Delivery" action doesn't require going through the
  /// detail screen first — added on top of Phase 5's original wiring
  /// (detail screen only) since it was easy to miss there.
  void _openCompleteDelivery(Goat goat) {
    final farmId = _farmId;

    if (farmId == null) return;

    Navigator.of(context).push(
      fastRoute(
        goat.currentStatus == Goat.statusBooked
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        titleSpacing: 20,
        title: Text(
          'Goat Stock',
          style: AppTheme.heading(
            size: 17,
          ),
        ),
      ),

      body: SafeArea(
        child: _buildBody(),
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

    if (farmId == null) {
      return FarmNotLinkedState(
        buttonColor: AppColors.primaryGreen,
        onRetry: _loadFarm,
      );
    }

    return StreamBuilder<List<Goat>>(
      stream: GoatService.instance.goatsStream(farmId),
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

  Widget _buildContent(List<Goat> allGoats) {
    final available = allGoats
        .where(
          (goat) =>
      goat.currentStatus ==
          Goat.statusAvailable,
    )
        .length;

    final booked = allGoats
        .where(
          (goat) =>
      goat.currentStatus ==
          Goat.statusBooked,
    )
        .length;

    final sold = allGoats
        .where(
          (goat) =>
      goat.currentStatus ==
          Goat.statusSold,
    )
        .length;

    var goats = List<Goat>.from(allGoats);

    // -------------------------------------------------------------------------
    // STATUS FILTER
    // -------------------------------------------------------------------------

    if (_statusFilter != null) {
      goats = goats
          .where(
            (goat) =>
        goat.currentStatus ==
            _statusFilter,
      )
          .toList();
    }

    // -------------------------------------------------------------------------
    // SEARCH
    // -------------------------------------------------------------------------

    if (_search.isNotEmpty) {
      goats = goats
          .where(
            (goat) =>
        goat.id
            .toLowerCase()
            .contains(_search) ||
            goat.breed
                .toLowerCase()
                .contains(_search) ||
            goat.color
                .toLowerCase()
                .contains(_search),
      )
          .toList();
    }

    return Column(
      children: [
        // ---------------------------------------------------------------------
        // SUMMARY
        // ---------------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            6,
            16,
            12,
          ),
          child: _summary(
            total: allGoats.length,
            available: available,
            booked: booked,
            sold: sold,
          ),
        ),

        // ---------------------------------------------------------------------
        // SEARCH
        // ---------------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: _searchBox(),
        ),

        const SizedBox(height: 10),

        // ---------------------------------------------------------------------
        // FILTERS
        // ---------------------------------------------------------------------

        _filters(),

        const SizedBox(height: 8),

        // ---------------------------------------------------------------------
        // LIST
        // ---------------------------------------------------------------------

        Expanded(
          child: goats.isEmpty
              ? _emptyState()
              : ListView.separated(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              6,
              16,
              24,
            ),
            itemCount: goats.length,
            separatorBuilder: (_, __) =>
            const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final goat = goats[index];

              return _GoatStockCard(
                goat: goat,
                onTap: () =>
                    _openDetail(goat),
                onCompleteDelivery:
                (goat.currentStatus == Goat.statusBooked ||
                    goat.currentStatus ==
                        Goat.statusWaitOnDelivery)
                    ? () => _openCompleteDelivery(goat)
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

  Widget _summary({
    required int total,
    required int available,
    required int booked,
    required int sold,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(
        radius: 15,
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryItem(
              icon: Icons.pets_outlined,
              label: 'Total',
              value: total,
              color: AppColors.stockTeal,
            ),
          ),

          _divider(),

          Expanded(
            child: _summaryItem(
              icon: Icons.check_circle_outline,
              label: 'Available',
              value: available,
              color: AppColors.success,
            ),
          ),

          _divider(),

          Expanded(
            child: _summaryItem(
              icon: Icons.bookmark_border_rounded,
              label: 'Booked',
              value: booked,
              color: AppColors.warning,
            ),
          ),

          _divider(),

          Expanded(
            child: _summaryItem(
              icon: Icons.sell_outlined,
              label: 'Sold',
              value: sold,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius:
            BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 16,
            color: color,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          '$value',
          style: AppTheme.heading(
            size: 14,
            color: AppColors.textDark,
          ),
        ),

        const SizedBox(height: 1),

        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body(
            size: 8,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 42,
      color: AppColors.divider,
      margin:
      const EdgeInsets.symmetric(
        horizontal: 3,
      ),
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  Widget _searchBox() {
    return Container(
      height: 48,
      decoration: AppTheme.card(
        radius: 13,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _search =
                value.trim().toLowerCase();
          });
        },
        style: AppTheme.body(
          size: 12,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          hintText:
          'Search ID, breed or color',
          hintStyle: AppTheme.body(
            size: 11,
            color: AppColors.textGrey,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 19,
            color: AppColors.textGrey,
          ),
          suffixIcon:
          _search.isEmpty
              ? null
              : IconButton(
            onPressed: () {
              _searchController
                  .clear();

              setState(() {
                _search = '';
              });
            },
            icon: const Icon(
              Icons.close_rounded,
              size: 17,
            ),
          ),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(
            vertical: 13,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FILTERS
  // ===========================================================================

  Widget _filters() {
    return SizedBox(
      height: 35,
      child: ListView(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 16,
        ),
        scrollDirection:
        Axis.horizontal,
        children: [
          _filterChip(
            label: 'All',
            status: null,
          ),
          const SizedBox(width: 7),
          ...Goat.statusValues.map(
                (status) {
              return Padding(
                padding:
                const EdgeInsets.only(
                  right: 7,
                ),
                child: _filterChip(
                  label: status,
                  status: status,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String? status,
  }) {
    final selected =
        _statusFilter == status;

    final color =
    _filterColor(status);

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _statusFilter = status;
        });
      },
      showCheckmark: false,
      labelStyle: AppTheme.body(
        size: 10,
        weight: FontWeight.w600,
        color: selected
            ? Colors.white
            : AppColors.textDark,
      ),
      selectedColor: color,
      backgroundColor:
      AppColors.cardWhite,
      side: BorderSide(
        color: selected
            ? color
            : AppColors.divider,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(20),
      ),
    );
  }

  Color _filterColor(String? status) {
    switch (status) {
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
        return AppColors.stockTeal;
    }
  }

  // ===========================================================================
  // EMPTY STATE
  // ===========================================================================

  Widget _emptyState() {
    final hasFilter = _statusFilter != null;
    final hasSearch = _search.isNotEmpty;

    String title;
    String subtitle;

    if (hasSearch) {
      title = 'No matching goats';
      subtitle =
      'Try a different ID, breed or color.';
    } else if (hasFilter) {
      title = 'No goats in this status';
      subtitle =
      'There are no goats marked as '
          '"$_statusFilter".';
    } else {
      title = 'No goats registered';
      subtitle =
      'Registered goats will appear here.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.stockTeal
                    .withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 27,
                color: AppColors.stockTeal,
              ),
            ),

            const SizedBox(height: 13),

            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.heading(
                size: 14,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 11,
              ),
            ),
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
              size: 42,
              color: AppColors.error,
            ),

            const SizedBox(height: 12),

            Text(
              'Unable to load goat stock',
              style: AppTheme.heading(
                size: 14,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 11,
              ),
            ),

            const SizedBox(height: 14),

            OutlinedButton(
              onPressed: _loadFarm,
              child: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
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

  const _GoatStockCard({
    required this.goat,
    required this.onTap,
    this.onCompleteDelivery,
  });

  Color _statusColor() {
    switch (goat.currentStatus) {
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

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: AppTheme.card(
            radius: 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardRow(statusColor),
              if (onCompleteDelivery != null) ...[
                const SizedBox(height: 9),
                _completeDeliveryButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardRow(Color statusColor) {
    return Row(
      children: [
        // --------------------------------------------------------------
        // PHOTO
        // --------------------------------------------------------------

        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AppColors.stockTeal
                .withOpacity(0.10),
            borderRadius:
            BorderRadius.circular(12),
          ),
          clipBehavior:
          Clip.antiAlias,
          child: goat.photo != null
              ? Image.memory(
            goat.photo!,
            fit: BoxFit.cover,
          )
              : const Icon(
            Icons.pets_outlined,
            color:
            AppColors.stockTeal,
            size: 25,
          ),
        ),

        const SizedBox(width: 11),

        // --------------------------------------------------------------
        // DETAILS
        // --------------------------------------------------------------

        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goat.id,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      AppTheme.heading(
                        size: 13,
                        color:
                        AppColors
                            .textDark,
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  Container(
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration:
                    BoxDecoration(
                      color: statusColor
                          .withOpacity(
                        0.10,
                      ),
                      borderRadius:
                      BorderRadius
                          .circular(
                        20,
                      ),
                    ),
                    child: Text(
                      goat.currentStatus,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 8,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Text(
                goat.breed.isEmpty
                    ? 'Breed not specified'
                    : goat.breed,
                maxLines: 1,
                overflow:
                TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 10,
                  color:
                  AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 7),

              Row(
                children: [
                  _detail(
                    Icons
                        .calendar_month_outlined,
                    goat.age,
                  ),

                  const SizedBox(width: 12),

                  _detail(
                    Icons
                        .monitor_weight_outlined,
                    '${goat.weight.toStringAsFixed(1)} kg',
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(width: 7),

        const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: AppColors.textGrey,
        ),
      ],
    );
  }

  Widget _completeDeliveryButton() {
    return Material(
      color: AppColors.primaryGreen.withOpacity(0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onCompleteDelivery,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 15,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(width: 6),
              Text(
                'Complete Delivery',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.primaryGreen,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(
      IconData icon,
      String text,
      ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: AppColors.stockTeal,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTheme.body(
            size: 9,
            color: AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
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
      duration:
      const Duration(milliseconds: 1100),
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
          padding:
          const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24,
          ),
          child: Column(
            children: [
              _box(
                height: 92,
                opacity: opacity,
              ),

              const SizedBox(height: 12),

              _box(
                height: 48,
                opacity: opacity,
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  _smallBox(
                    width: 65,
                    opacity: opacity,
                  ),
                  const SizedBox(width: 7),
                  _smallBox(
                    width: 80,
                    opacity: opacity,
                  ),
                  const SizedBox(width: 7),
                  _smallBox(
                    width: 65,
                    opacity: opacity,
                  ),
                ],
              ),

              const SizedBox(height: 14),

              for (int i = 0; i < 6; i++) ...[
                _goatCardSkeleton(
                  opacity: opacity,
                ),
                if (i != 5)
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
    required double opacity,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.divider
            .withOpacity(opacity),
        borderRadius:
        BorderRadius.circular(14),
      ),
    );
  }

  Widget _smallBox({
    required double width,
    required double opacity,
  }) {
    return Container(
      width: width,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.divider
            .withOpacity(opacity),
        borderRadius:
        BorderRadius.circular(18),
      ),
    );
  }

  Widget _goatCardSkeleton({
    required double opacity,
  }) {
    return Container(
      height: 82,
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: AppTheme.card(
        radius: 14,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.divider
                  .withOpacity(opacity),
              borderRadius:
              BorderRadius.circular(12),
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.divider
                        .withOpacity(opacity),
                    borderRadius:
                    BorderRadius.circular(5),
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  width: 145,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.divider
                        .withOpacity(opacity),
                    borderRadius:
                    BorderRadius.circular(5),
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  width: 100,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.divider
                        .withOpacity(opacity),
                    borderRadius:
                    BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}