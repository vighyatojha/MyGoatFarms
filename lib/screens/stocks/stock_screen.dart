import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';

import 'add_feed_stock_screen.dart';
import 'add_medicine_screen.dart';
import 'feed_used_screen.dart';
import 'medicine_used_screen.dart';

import '../home/notification_screen.dart';
import '../../widgets/farm_not_linked_state.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  final TextEditingController _searchController =
  TextEditingController();

  String _searchQuery = '';
  bool _searchOpen = false;
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    try {
      final id =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId = id;
        _loadingFarm = false;
      });
    } catch (e) {
      debugPrint('Could not load farm: $e');
      if (!mounted) return;
      setState(() => _loadingFarm = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  void _openAddFeed() {
    Navigator.of(context).push(
      fastRoute(
        const AddFeedStockScreen(),
      ),
    );
  }

  void _openAddMedicine() {
    Navigator.of(context).push(
      fastRoute(
        const AddMedicineScreen(),
      ),
    );
  }

  void _openFeedUsed() {
    Navigator.of(context).push(
      fastRoute(
        const FeedUsedScreen(),
      ),
    );
  }

  void _openMedicineUsed() {
    Navigator.of(context).push(
      fastRoute(
        const MedicineUsedScreen(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;

      if (!_searchOpen) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
    });
  }

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _lowStockOnly = false;
    });
  }

  List<StockItem> _filterItems(
      List<StockItem> items,
      ) {
    final query =
    _searchQuery.trim().toLowerCase();

    return items.where((item) {
      final matchesSearch =
          query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.unit.toLowerCase().contains(query);

      final matchesLowStock =
          !_lowStockOnly || item.isLowStock;

      return matchesSearch && matchesLowStock;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------

  Future<void> _confirmDelete(
      StockItem item,
      ) async {
    final confirmed =
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(20),
          ),
          title: Text(
            'Remove ${item.name}?',
            style: AppTheme.heading(
              size: 17,
            ),
          ),
          content: Text(
            'This removes the item from current stock tracking. Existing stock movement history will remain.',
            style: AppTheme.body(
              size: 13,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(false);
              },
              child: Text(
                'Cancel',
                style: AppTheme.body(
                  size: 13,
                  color:
                  AppColors.textGrey,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(true);
              },
              child: Text(
                'Remove',
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.error,
                  weight:
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        _farmId == null) {
      return;
    }

    try {
      await FirestoreService.instance
          .deleteStockItem(
        _farmId!,
        item.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            '${item.name} removed from stock',
          ),
          backgroundColor:
          AppColors.darkGreen,
          behavior:
          SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(12),
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'This is taking too long. Check your connection and try again.',
          ),
          backgroundColor:
          AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            FirestoreService.instance
                .describeError(e),
          ),
          backgroundColor:
          AppColors.error,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  Widget _buildNotLinkedState() {
    return FarmNotLinkedState(
      buttonColor: AppColors.primaryGreen,
      onRetry: () {
        setState(() => _loadingFarm = true);
        _loadFarm();
      },
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      AppColors.paleGreen,

      body: SafeArea(
        child: _loadingFarm
            ? const Center(
          child:
          CircularProgressIndicator(
            color:
            AppColors.primaryGreen,
          ),
        )
            : _farmId == null
            ? _buildNotLinkedState()
            : RefreshIndicator(
          color:
          AppColors.primaryGreen,
          onRefresh: () async {
            await _loadFarm();

            await Future.delayed(
              const Duration(
                milliseconds: 300,
              ),
            );
          },
          child:
          StreamBuilder<
              List<StockItem>>(
            stream:
            FirestoreService
                .instance
                .stockItemsStream(
              _farmId!,
            ),
            builder:
                (context, snapshot) {
              final allItems =
                  snapshot.data ??
                      <StockItem>[];

              final feedItems =
              allItems
                  .where(
                    (item) =>
                item.type ==
                    StockType.feed,
              )
                  .toList();

              final medicineItems =
              allItems
                  .where(
                    (item) =>
                item.type ==
                    StockType.medicine,
              )
                  .toList();

              final lowStockItems =
              allItems
                  .where(
                    (item) =>
                item.isLowStock,
              )
                  .toList();

              final filteredFeed =
              _filterItems(
                feedItems,
              );

              final filteredMedicine =
              _filterItems(
                medicineItems,
              );

              return SingleChildScrollView(
                physics:
                const AlwaysScrollableScrollPhysics(),
                padding:
                const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  32,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    _buildHeader(),

                    if (_searchOpen)
                      _buildSearchBar(),

                    const SizedBox(
                      height: 16,
                    ),

                    _buildOverview(
                      allItems:
                      allItems,
                      feedItems:
                      feedItems,
                      medicineItems:
                      medicineItems,
                      lowStockItems:
                      lowStockItems,
                    ),

                    if (lowStockItems
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 14,
                      ),
                      _buildLowStockAlert(
                        lowStockItems,
                      ),
                    ],

                    const SizedBox(
                      height: 24,
                    ),

                    _buildSectionHeader(
                      title:
                      'Quick Actions',
                      subtitle:
                      'Manage your stock quickly',
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _buildQuickActions(),

                    const SizedBox(
                      height: 26,
                    ),

                    _buildSectionHeader(
                      title:
                      'Feed Stock',
                      subtitle:
                      '${feedItems.length} item${feedItems.length == 1 ? '' : 's'} tracked',
                      actionText:
                      'Add',
                      onAction:
                      _openAddFeed,
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _buildStockGrid(
                      filteredFeed,
                      StockType.feed,
                      emptyMessage:
                      _searchQuery
                          .isNotEmpty ||
                          _lowStockOnly
                          ? 'No feed matches the current filter.'
                          : 'No feed stock added yet.',
                    ),

                    const SizedBox(
                      height: 26,
                    ),

                    _buildSectionHeader(
                      title:
                      'Medicine Stock',
                      subtitle:
                      '${medicineItems.length} item${medicineItems.length == 1 ? '' : 's'} tracked',
                      actionText:
                      'Add',
                      onAction:
                      _openAddMedicine,
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _buildStockGrid(
                      filteredMedicine,
                      StockType.medicine,
                      emptyMessage:
                      _searchQuery
                          .isNotEmpty ||
                          _lowStockOnly
                          ? 'No medicine matches the current filter.'
                          : 'No medicine stock added yet.',
                    ),

                    const SizedBox(
                      height: 26,
                    ),

                    _buildSectionHeader(
                      title:
                      'Recent Activity',
                      subtitle:
                      'Latest stock movements',
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _buildRecentActivity(
                      _farmId!,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.fromLTRB(
        18,
        17,
        12,
        17,
      ),
      decoration:
      const BoxDecoration(
        gradient: LinearGradient(
          colors:
          AppColors.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
        BorderRadius.all(
          Radius.circular(22),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration:
            BoxDecoration(
              color:
              Colors.white
                  .withOpacity(
                0.16,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  'Stock',
                  style:
                  AppTheme.heading(
                    size: 22,
                    color:
                    Colors.white,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  'Feed, medicine & inventory',
                  style:
                  AppTheme.body(
                    size: 10,
                    color: Colors.white
                        .withOpacity(
                      0.88,
                    ),
                  ),
                ),
              ],
            ),
          ),

          _headerButton(
            icon:
            _searchOpen
                ? Icons.close_rounded
                : Icons.search_rounded,
            tooltip:
            _searchOpen
                ? 'Close search'
                : 'Search',
            onTap:
            _toggleSearch,
          ),

          const SizedBox(
            width: 5,
          ),

          _headerButton(
            icon:
            Icons.notifications_none_rounded,
            tooltip:
            'Notifications',
            badge: 3,
            onTap: () {
              Navigator.of(context)
                  .push(
                fastRoute(
                  const NotificationScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    int? badge,
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior:
        Clip.none,
        children: [
          Material(
            color: Colors.white
                .withOpacity(
              0.14,
            ),
            shape:
            const CircleBorder(),
            child: InkWell(
              customBorder:
              const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 43,
                height: 43,
                child: Icon(
                  icon,
                  color:
                  Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),

          if (badge != null)
            Positioned(
              top: -3,
              right: -2,
              child: Container(
                constraints:
                const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 4,
                ),
                decoration:
                BoxDecoration(
                  color:
                  AppColors.error,
                  shape:
                  BoxShape.circle,
                  border:
                  Border.all(
                    color:
                    AppColors
                        .primaryGreen,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$badge',
                  textAlign:
                  TextAlign.center,
                  style:
                  const TextStyle(
                    color:
                    Colors.white,
                    fontSize: 9,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH BAR
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar() {
    return Padding(
      padding:
      const EdgeInsets.only(
        top: 12,
      ),
      child: Container(
        decoration:
        BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.circular(
            15,
          ),
          border:
          Border.all(
            color: AppColors
                .primaryGreen
                .withOpacity(
              0.16,
            ),
          ),
        ),
        child: TextField(
          controller:
          _searchController,
          autofocus: true,
          onChanged: (value) {
            setState(() {
              _searchQuery =
                  value.trim();
            });
          },
          style:
          AppTheme.body(
            size: 13,
            color:
            AppColors.textDark,
          ),
          decoration:
          InputDecoration(
            prefixIcon:
            const Icon(
              Icons.search_rounded,
              color:
              AppColors
                  .primaryGreen,
            ),
            hintText:
            'Search feed, medicine or unit',
            hintStyle:
            AppTheme.body(
              size: 12,
              color:
              AppColors.textGrey,
            ),
            suffixIcon:
            _searchQuery.isEmpty
                ? null
                : IconButton(
              onPressed:
              _clearSearch,
              icon:
              const Icon(
                Icons
                    .close_rounded,
                size: 18,
                color:
                AppColors
                    .textGrey,
              ),
            ),
            border:
            InputBorder.none,
            contentPadding:
            const EdgeInsets
                .symmetric(
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _buildOverview({
    required List<StockItem> allItems,
    required List<StockItem> feedItems,
    required List<StockItem> medicineItems,
    required List<StockItem> lowStockItems,
  }) {
    final feedTotal =
    feedItems.fold<double>(
      0,
          (sum, item) =>
      sum + item.quantity,
    );

    final feedUnits = feedItems
        .map(
          (item) => item.unit,
    )
        .toSet();

    final feedUnit =
    feedUnits.length == 1
        ? feedUnits.first
        : '';

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment
          .start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Inventory Overview',
                style:
                AppTheme.heading(
                  size: 16,
                ),
              ),
            ),

            if (_searchQuery
                .isNotEmpty ||
                _lowStockOnly)
              TextButton(
                onPressed:
                _clearFilters,
                child: Text(
                  'Clear',
                  style:
                  AppTheme.body(
                    size: 11,
                    color:
                    AppColors
                        .darkGreen,
                    weight:
                    FontWeight
                        .w700,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(
          height: 10,
        ),

        SizedBox(
          height: 116,
          child:
          ListView(
            scrollDirection:
            Axis.horizontal,
            physics:
            const BouncingScrollPhysics(),
            children: [
              _summaryCard(
                icon:
                Icons.grass_rounded,
                title:
                'Feed Stock',
                value:
                feedTotal
                    .toStringAsFixed(
                  0,
                ),
                unit:
                feedUnit.isEmpty
                    ? 'units'
                    : feedUnit,
                color:
                AppColors
                    .primaryGreen,
              ),

              const SizedBox(
                width: 10,
              ),

              _summaryCard(
                icon:
                Icons.medication_rounded,
                title:
                'Medicine',
                value:
                '${medicineItems.length}',
                unit:
                'items',
                color:
                AppColors.info,
              ),

              const SizedBox(
                width: 10,
              ),

              _summaryCard(
                icon:
                Icons
                    .warning_amber_rounded,
                title:
                'Low Stock',
                value:
                '${lowStockItems.length}',
                unit:
                'alerts',
                color:
                lowStockItems
                    .isEmpty
                    ? AppColors
                    .success
                    : AppColors
                    .error,
              ),

              const SizedBox(
                width: 10,
              ),

              _summaryCard(
                icon:
                Icons
                    .inventory_2_rounded,
                title:
                'Total Items',
                value:
                '${allItems.length}',
                unit:
                'tracked',
                color:
                AppColors
                    .darkGreen,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      width: 148,
      padding:
      const EdgeInsets.all(
        13,
      ),
      decoration:
      BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        border:
        Border.all(
          color: AppColors.divider
              .withOpacity(
            0.7,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(
              0.035,
            ),
            blurRadius: 10,
            offset:
            const Offset(
              0,
              4,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment
            .start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration:
            BoxDecoration(
              color: color
                  .withOpacity(
                0.10,
              ),
              shape:
              BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 19,
            ),
          ),

          const Spacer(),

          Text(
            title,
            maxLines: 1,
            overflow:
            TextOverflow
                .ellipsis,
            style:
            AppTheme.body(
              size: 10,
              color:
              AppColors.textGrey,
              weight:
              FontWeight.w600,
            ),
          ),

          const SizedBox(
            height: 2,
          ),

          Row(
            crossAxisAlignment:
            CrossAxisAlignment
                .baseline,
            textBaseline:
            TextBaseline
                .alphabetic,
            children: [
              Text(
                value,
                style:
                AppTheme.heading(
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(
                width: 4,
              ),
              Flexible(
                child: Text(
                  unit,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  AppTheme.body(
                    size: 9,
                    color: color,
                    weight:
                    FontWeight
                        .w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOW STOCK
  // ---------------------------------------------------------------------------

  Widget _buildLowStockAlert(
      List<StockItem> items,
      ) {
    final names = items
        .take(3)
        .map(
          (item) => item.name,
    )
        .join(', ');

    final extra =
    items.length > 3
        ? ' +${items.length - 3} more'
        : '';

    return Material(
      color:
      Colors.transparent,
      child: InkWell(
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        onTap: () {
          setState(() {
            _lowStockOnly =
            !_lowStockOnly;
          });
        },
        child: Container(
          width:
          double.infinity,
          padding:
          const EdgeInsets.all(
            13,
          ),
          decoration:
          BoxDecoration(
            color: AppColors.error
                .withOpacity(
              0.07,
            ),
            borderRadius:
            BorderRadius.circular(
              17,
            ),
            border:
            Border.all(
              color: AppColors.error
                  .withOpacity(
                0.20,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                BoxDecoration(
                  color: AppColors
                      .error
                      .withOpacity(
                    0.11,
                  ),
                  shape:
                  BoxShape.circle,
                ),
                child:
                const Icon(
                  Icons
                      .warning_amber_rounded,
                  color:
                  AppColors.error,
                  size: 21,
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      '${items.length} low-stock alert${items.length == 1 ? '' : 's'}',
                      style:
                      AppTheme.body(
                        size: 12,
                        color:
                        AppColors
                            .error,
                        weight:
                        FontWeight
                            .w800,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      '$names$extra',
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      AppTheme.body(
                        size: 10,
                        color:
                        AppColors
                            .textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Text(
                _lowStockOnly
                    ? 'Show All'
                    : 'View',
                style:
                AppTheme.body(
                  size: 10,
                  color:
                  AppColors.error,
                  weight:
                  FontWeight.w800,
                ),
              ),

              const Icon(
                Icons
                    .chevron_right_rounded,
                color:
                AppColors.error,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION HEADER
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              Text(
                title,
                style:
                AppTheme.heading(
                  size: 16,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding:
                  const EdgeInsets
                      .only(
                    top: 2,
                  ),
                  child: Text(
                    subtitle,
                    style:
                    AppTheme.body(
                      size: 10,
                      color:
                      AppColors
                          .textGrey,
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (actionText != null &&
            onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(
              Icons.add_rounded,
              size: 16,
            ),
            label:
            Text(actionText),
            style:
            TextButton.styleFrom(
              foregroundColor:
              AppColors
                  .darkGreen,
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 8,
              ),
              minimumSize:
              Size.zero,
              tapTargetSize:
              MaterialTapTargetSize
                  .shrinkWrap,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // QUICK ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildQuickActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 4 : 2;
        // Fixed tile height prevents pixel overflow on smaller Android screens.
        final tileHeight = columns == 4 ? 118.0 : 128.0;

        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: tileHeight,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _quickAction(
              icon: Icons.add_box_rounded,
              title: 'Add Feed',
              subtitle: 'Purchase stock',
              color: AppColors.primaryGreen,
              onTap: _openAddFeed,
            ),
            _quickAction(
              icon: Icons.medication_rounded,
              title: 'Add Medicine',
              subtitle: 'Add medicine',
              color: AppColors.info,
              onTap: _openAddMedicine,
            ),
            _quickAction(
              icon: Icons.remove_circle_outline_rounded,
              title: 'Feed Used',
              subtitle: 'Record usage',
              color: AppColors.warning,
              onTap: _openFeedUsed,
            ),
            _quickAction(
              icon: Icons.medical_information_rounded,
              title: 'Medicine Used',
              subtitle: 'Record usage',
              color: AppColors.error,
              onTap: _openMedicineUsed,
            ),
          ],
        );
      },
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color:
      Colors.transparent,
      child: InkWell(
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        onTap: onTap,
        child: Ink(
          decoration:
          BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(
              17,
            ),
            border:
            Border.all(
              color: color
                  .withOpacity(
                0.16,
              ),
            ),
          ),
          child: Padding(
            padding:
            const EdgeInsets.all(
              11,
            ),
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment
                  .center,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration:
                  BoxDecoration(
                    color: color
                        .withOpacity(
                      0.10,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      13,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 22,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                Text(
                  title,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  textAlign:
                  TextAlign.center,
                  style:
                  AppTheme.body(
                    size: 11,
                    color:
                    AppColors
                        .textDark,
                    weight:
                    FontWeight
                        .w800,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  subtitle,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  textAlign:
                  TextAlign.center,
                  style:
                  AppTheme.body(
                    size: 8,
                    color:
                    AppColors
                        .textGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STOCK GRID
  // ---------------------------------------------------------------------------

  Widget _buildStockGrid(
      List<StockItem> items,
      StockType type, {
        required String emptyMessage,
      }) {
    if (items.isEmpty) {
      return _emptyStockCard(
        type,
        emptyMessage,
      );
    }

    return LayoutBuilder(
      builder:
          (context, constraints) {
        final columns =
        constraints.maxWidth >=
            700
            ? 4
            : constraints.maxWidth >=
            450
            ? 3
            : 2;

        final aspect =
        columns == 2
            ? 0.93
            : columns == 3
            ? 1.0
            : 1.05;

        return GridView.builder(
          shrinkWrap: true,
          physics:
          const NeverScrollableScrollPhysics(),
          itemCount:
          items.length,
          gridDelegate:
          SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
            columns,
            crossAxisSpacing:
            10,
            mainAxisSpacing:
            10,
            childAspectRatio:
            aspect,
          ),
          itemBuilder:
              (context, index) {
            return _stockCard(
              items[index],
              type,
            );
          },
        );
      },
    );
  }

  Widget _stockCard(
      StockItem item,
      StockType type,
      ) {
    final low =
        item.isLowStock;

    final color = low
        ? AppColors.error
        : type == StockType.feed
        ? AppColors.primaryGreen
        : AppColors.info;

    return Material(
      color:
      Colors.transparent,
      child: InkWell(
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        onTap: () {
          _showStockDetails(
            item,
            color,
          );
        },
        onLongPress: () {
          _confirmDelete(item);
        },
        child: Ink(
          decoration:
          BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(
              18,
            ),
            border:
            Border.all(
              color: low
                  ? AppColors.error
                  .withOpacity(
                0.25,
              )
                  : AppColors.divider
                  .withOpacity(
                0.75,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(
                  0.025,
                ),
                blurRadius: 9,
                offset:
                const Offset(
                  0,
                  3,
                ),
              ),
            ],
          ),
          child: Padding(
            padding:
            const EdgeInsets.all(
              11,
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration:
                      BoxDecoration(
                        color: color
                            .withOpacity(
                          0.10,
                        ),
                        shape:
                        BoxShape
                            .circle,
                      ),
                      child: Icon(
                        type ==
                            StockType
                                .feed
                            ? Icons
                            .grass_rounded
                            : Icons
                            .medication_rounded,
                        color: color,
                        size: 21,
                      ),
                    ),

                    const Spacer(),

                    Container(
                      width: 28,
                      height: 28,
                      decoration:
                      BoxDecoration(
                        color: AppColors
                            .paleGreen,
                        borderRadius:
                        BorderRadius
                            .circular(
                          9,
                        ),
                      ),
                      child:
                      const Icon(
                        Icons
                            .arrow_forward_ios_rounded,
                        size: 11,
                        color:
                        AppColors
                            .textGrey,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                Text(
                  item.name,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  AppTheme.body(
                    size: 12,
                    color:
                    AppColors
                        .textDark,
                    weight:
                    FontWeight
                        .w700,
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                Row(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .baseline,
                  textBaseline:
                  TextBaseline
                      .alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        item.quantity
                            .toStringAsFixed(
                          0,
                        ),
                        maxLines: 1,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style:
                        AppTheme
                            .heading(
                          size: 19,
                          color: color,
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 4,
                    ),

                    Text(
                      item.unit,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      AppTheme.body(
                        size: 9,
                        color:
                        AppColors
                            .textGrey,
                        weight:
                        FontWeight
                            .w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 6,
                ),

                Container(
                  width:
                  double.infinity,
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration:
                  BoxDecoration(
                    color: color
                        .withOpacity(
                      0.08,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      8,
                    ),
                  ),
                  child: Text(
                    low
                        ? 'Low stock'
                        : 'Good stock',
                    maxLines: 1,
                    overflow:
                    TextOverflow
                        .ellipsis,
                    textAlign:
                    TextAlign.center,
                    style:
                    AppTheme.body(
                      size: 9,
                      color: color,
                      weight:
                      FontWeight
                          .w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY STOCK
  // ---------------------------------------------------------------------------

  Widget _emptyStockCard(
      StockType type,
      String message,
      ) {
    final isFeed =
        type == StockType.feed;

    final color = isFeed
        ? AppColors.primaryGreen
        : AppColors.info;

    return Container(
      width:
      double.infinity,
      padding:
      const EdgeInsets.all(
        22,
      ),
      decoration:
      BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        border:
        Border.all(
          color: AppColors.divider
              .withOpacity(
            0.7,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration:
            BoxDecoration(
              color: color
                  .withOpacity(
                0.09,
              ),
              shape:
              BoxShape.circle,
            ),
            child: Icon(
              isFeed
                  ? Icons
                  .grass_rounded
                  : Icons
                  .medication_rounded,
              color: color,
              size: 27,
            ),
          ),

          const SizedBox(
            height: 11,
          ),

          Text(
            message,
            textAlign:
            TextAlign.center,
            style:
            AppTheme.body(
              size: 12,
              color:
              AppColors.textGrey,
            ),
          ),

          if (_searchQuery
              .isEmpty &&
              !_lowStockOnly) ...[
            const SizedBox(
              height: 12,
            ),

            OutlinedButton.icon(
              onPressed: isFeed
                  ? _openAddFeed
                  : _openAddMedicine,
              icon:
              const Icon(
                Icons.add_rounded,
                size: 17,
              ),
              label: Text(
                isFeed
                    ? 'Add Feed'
                    : 'Add Medicine',
              ),
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                color,
                side:
                BorderSide(
                  color: color
                      .withOpacity(
                    0.35,
                  ),
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    11,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STOCK DETAILS
  // ---------------------------------------------------------------------------

  Future<void> _showStockDetails(
      StockItem item,
      Color color,
      ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
      Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            padding:
            const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              22,
            ),
            decoration:
            const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(
                top: Radius.circular(
                  26,
                ),
              ),
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration:
                    BoxDecoration(
                      color: Colors
                          .grey
                          .shade300,
                      borderRadius:
                      BorderRadius
                          .circular(
                        10,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration:
                      BoxDecoration(
                        color: color
                            .withOpacity(
                          0.10,
                        ),
                        shape:
                        BoxShape
                            .circle,
                      ),
                      child: Icon(
                        item.type ==
                            StockType
                                .feed
                            ? Icons
                            .grass_rounded
                            : Icons
                            .medication_rounded,
                        color: color,
                        size: 26,
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style:
                            AppTheme
                                .heading(
                              size: 17,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            item.type ==
                                StockType
                                    .feed
                                ? 'Feed Stock'
                                : 'Medicine Stock',
                            style:
                            AppTheme
                                .body(
                              size: 11,
                              color:
                              AppColors
                                  .textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 18,
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                      _detailMetric(
                        title:
                        'Available',
                        value:
                        '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                        color:
                        color,
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                      _detailMetric(
                        title:
                        'Low Threshold',
                        value:
                        '${item.lowStockThreshold.toStringAsFixed(0)} ${item.unit}',
                        color:
                        item.isLowStock
                            ? AppColors
                            .error
                            : AppColors
                            .textDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 10,
                ),

                Container(
                  width:
                  double.infinity,
                  padding:
                  const EdgeInsets.all(
                    12,
                  ),
                  decoration:
                  BoxDecoration(
                    color: item
                        .isLowStock
                        ? AppColors.error
                        .withOpacity(
                      0.07,
                    )
                        : AppColors
                        .lightGreen,
                    borderRadius:
                    BorderRadius
                        .circular(
                      13,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.isLowStock
                            ? Icons
                            .warning_amber_rounded
                            : Icons
                            .check_circle_outline_rounded,
                        color: item
                            .isLowStock
                            ? AppColors
                            .error
                            : AppColors
                            .success,
                        size: 19,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Expanded(
                        child: Text(
                          item.isLowStock
                              ? 'Stock is below the safe threshold.'
                              : 'Stock level is currently healthy.',
                          style:
                          AppTheme
                              .body(
                            size: 11,
                            color:
                            AppColors
                                .textDark,
                            weight:
                            FontWeight
                                .w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  height: 9,
                ),

                Text(
                  'Last updated ${DateFormat('dd MMM yyyy, hh:mm a').format(item.lastUpdated)}',
                  style:
                  AppTheme.body(
                    size: 10,
                    color:
                    AppColors
                        .textGrey,
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(
                            sheetContext,
                          ).pop();

                          if (item.type ==
                              StockType
                                  .feed) {
                            _openAddFeed();
                          } else {
                            _openAddMedicine();
                          }
                        },
                        icon:
                        const Icon(
                          Icons
                              .add_rounded,
                          size: 18,
                        ),
                        label:
                        const Text(
                          'Add Stock',
                        ),
                        style:
                        OutlinedButton
                            .styleFrom(
                          foregroundColor:
                          color,
                          side:
                          BorderSide(
                            color: color
                                .withOpacity(
                              0.35,
                            ),
                          ),
                          padding:
                          const EdgeInsets
                              .symmetric(
                            vertical: 13,
                          ),
                          shape:
                          RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius
                                .circular(
                              12,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(
                            sheetContext,
                          ).pop();

                          if (item.type ==
                              StockType
                                  .feed) {
                            _openFeedUsed();
                          } else {
                            _openMedicineUsed();
                          }
                        },
                        icon:
                        const Icon(
                          Icons
                              .remove_rounded,
                          size: 18,
                        ),
                        label:
                        const Text(
                          'Record Used',
                        ),
                        style:
                        ElevatedButton
                            .styleFrom(
                          backgroundColor:
                          color,
                          foregroundColor:
                          Colors.white,
                          elevation: 0,
                          padding:
                          const EdgeInsets
                              .symmetric(
                            vertical: 13,
                          ),
                          shape:
                          RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius
                                .circular(
                              12,
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
        );
      },
    );
  }

  Widget _detailMetric({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding:
      const EdgeInsets.all(
        12,
      ),
      decoration:
      BoxDecoration(
        color:
        AppColors.paleGreen,
        borderRadius:
        BorderRadius.circular(
          13,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment
            .start,
        children: [
          Text(
            title,
            style:
            AppTheme.body(
              size: 9,
              color:
              AppColors.textGrey,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            value,
            maxLines: 1,
            overflow:
            TextOverflow
                .ellipsis,
            style:
            AppTheme.body(
              size: 13,
              color: color,
              weight:
              FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RECENT ACTIVITY
  // ---------------------------------------------------------------------------

  Widget _buildRecentActivity(
      String farmId,
      ) {
    return StreamBuilder<
        List<StockMovement>>(
      stream:
      FirestoreService.instance
          .stockMovementsStream(
        farmId,
        limit: 6,
      ),
      builder:
          (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 130,
            alignment:
            Alignment.center,
            decoration:
            AppTheme.card(
              radius: 17,
            ),
            child:
            const CircularProgressIndicator(
              color: AppColors
                  .primaryGreen,
              strokeWidth: 2,
            ),
          );
        }

        final movements =
        snapshot.data!;

        if (movements.isEmpty) {
          return Container(
            width:
            double.infinity,
            padding:
            const EdgeInsets.all(
              22,
            ),
            decoration:
            AppTheme.card(
              radius: 17,
            ),
            child: Column(
              children: [
                const Icon(
                  Icons
                      .history_rounded,
                  color:
                  AppColors
                      .textGrey,
                  size: 30,
                ),
                const SizedBox(
                  height: 9,
                ),
                Text(
                  'No stock activity yet',
                  style:
                  AppTheme.body(
                    size: 12,
                    color:
                    AppColors
                        .textGrey,
                    weight:
                    FontWeight
                        .w600,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  'Purchases and usage will appear here.',
                  style:
                  AppTheme.body(
                    size: 10,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration:
          BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(
              18,
            ),
            border:
            Border.all(
              color: AppColors
                  .divider
                  .withOpacity(
                0.7,
              ),
            ),
          ),
          child: Column(
            children:
            List.generate(
              movements.length,
                  (index) {
                return _activityItem(
                  movements[index],
                  isLast:
                  index ==
                      movements
                          .length -
                          1,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _activityItem(
      StockMovement movement, {
        required bool isLast,
      }) {
    final isAddition =
        movement.isAddition;

    final color = isAddition
        ? AppColors.success
        : AppColors.warning;

    return Padding(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration:
                BoxDecoration(
                  color: color
                      .withOpacity(
                    0.10,
                  ),
                  shape:
                  BoxShape.circle,
                ),
                child: Icon(
                  isAddition
                      ? Icons
                      .arrow_downward_rounded
                      : Icons
                      .arrow_upward_rounded,
                  color: color,
                  size: 18,
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      movement.itemName,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      AppTheme.body(
                        size: 12,
                        color:
                        AppColors
                            .textDark,
                        weight:
                        FontWeight
                            .w700,
                      ),
                    ),

                    const SizedBox(
                      height: 2,
                    ),

                    Text(
                      movement.notes
                          .isEmpty
                          ? DateFormat(
                        'dd MMM, hh:mm a',
                      ).format(
                        movement.date,
                      )
                          : '${DateFormat('dd MMM, hh:mm a').format(movement.date)} · ${movement.notes}',
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      AppTheme.body(
                        size: 9,
                        color:
                        AppColors
                            .textGrey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .end,
                children: [
                  Text(
                    '${isAddition ? '+' : '-'}${movement.quantity.toStringAsFixed(0)} ${movement.unit}',
                    style:
                    AppTheme.body(
                      size: 11,
                      color: color,
                      weight:
                      FontWeight
                          .w800,
                    ),
                  ),
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    isAddition
                        ? 'Added'
                        : 'Used',
                    style:
                    AppTheme.body(
                      size: 8,
                      color:
                      AppColors
                          .textGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (!isLast) ...[
            const SizedBox(
              height: 11,
            ),
            Divider(
              height: 1,
              color: AppColors
                  .divider
                  .withOpacity(
                0.65,
              ),
            ),
          ],
        ],
      ),
    );
  }
}