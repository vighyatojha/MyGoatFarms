import 'dart:async';

import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
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

/// Stock dashboard for feed and medicine inventory.
///
/// The screen intentionally keeps the existing Firestore/service flow intact,
/// while presenting the information in a faster, more visual mobile layout.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String? _farmId;

  bool _searchOpen = false;
  String _searchQuery = '';
  bool _lowStockOnly = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    try {
      final id = await FirestoreService.instance.currentFarmId();
      if (!mounted) return;
      setState(() => _farmId = id);
    } catch (e) {
      debugPrint('Could not load farm: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _lowStockOnly = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Future<void> _confirmDelete(StockItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Remove ${item.name}?',
          style: AppTheme.heading(size: 17),
        ),
        content: Text(
          'This removes the item from current stock tracking. Its past add/use history will remain available in Recent Activity.',
          style: AppTheme.body(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTheme.body(
                size: 13,
                color: AppColors.textGrey,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: AppTheme.body(
                size: 13,
                color: AppColors.error,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || _farmId == null) return;

    try {
      await FirestoreService.instance.deleteStockItem(
        _farmId!,
        item.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name} removed from stock'),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This is taking too long. Check your connection and try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirestoreService.instance.describeError(e),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openAddFeed() {
    Navigator.of(context).push(
      fastRoute(const AddFeedStockScreen()),
    );
  }

  void _openAddMedicine() {
    Navigator.of(context).push(
      fastRoute(const AddMedicineScreen()),
    );
  }

  void _openFeedUsed() {
    Navigator.of(context).push(
      fastRoute(const FeedUsedScreen()),
    );
  }

  void _openMedicineUsed() {
    Navigator.of(context).push(
      fastRoute(const MedicineUsedScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              )
            : RefreshIndicator(
                color: AppColors.primaryGreen,
                onRefresh: () async {
                  await Future.delayed(
                    const Duration(milliseconds: 450),
                  );
                  await _loadFarm();
                },
                child: StreamBuilder<List<StockItem>>(
                  stream: FirestoreService.instance.stockItemsStream(
                    _farmId!,
                  ),
                  builder: (context, snap) {
                    final allItems = snap.data ?? <StockItem>[];
                    final feedItems = allItems
                        .where((item) => item.type == StockType.feed)
                        .toList();
                    final medicineItems = allItems
                        .where((item) => item.type == StockType.medicine)
                        .toList();
                    final lowStockItems = allItems
                        .where((item) => item.isLowStock)
                        .toList();

                    final filteredFeed = _filterItems(feedItems);
                    final filteredMedicine = _filterItems(medicineItems);

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        10,
                        16,
                        30,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeInDown(
                            duration: const Duration(milliseconds: 220),
                            child: _buildHeader(),
                          ),

                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _searchOpen
                                ? _buildSearchBar()
                                : const SizedBox.shrink(),
                          ),

                          const SizedBox(height: 14),

                          FadeInUp(
                            delay: const Duration(milliseconds: 30),
                            duration: const Duration(milliseconds: 220),
                            child: _buildSummary(
                              allItems: allItems,
                              feedItems: feedItems,
                              medicineItems: medicineItems,
                              lowStockItems: lowStockItems,
                              loading: !snap.hasData,
                            ),
                          ),

                          if (lowStockItems.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            FadeInUp(
                              delay: const Duration(milliseconds: 45),
                              duration: const Duration(milliseconds: 220),
                              child: _buildLowStockAlert(lowStockItems),
                            ),
                          ],

                          const SizedBox(height: 22),

                          _sectionTitle(
                            'Quick Actions',
                            subtitle: 'Common stock operations',
                          ),
                          const SizedBox(height: 11),
                          _buildQuickActions(),

                          const SizedBox(height: 24),

                          _sectionTitle(
                            'Feed Stock',
                            subtitle: '${feedItems.length} item${feedItems.length == 1 ? '' : 's'} tracked',
                            actionLabel: 'Add',
                            onAction: _openAddFeed,
                          ),
                          const SizedBox(height: 11),
                          _buildStockGrid(
                            filteredFeed,
                            StockType.feed,
                            emptyMessage: _searchQuery.isNotEmpty || _lowStockOnly
                                ? 'No feed matches the current filter.'
                                : 'No feed stock added yet.',
                          ),

                          const SizedBox(height: 24),

                          _sectionTitle(
                            'Medicine Stock',
                            subtitle: '${medicineItems.length} item${medicineItems.length == 1 ? '' : 's'} tracked',
                            actionLabel: 'Add',
                            onAction: _openAddMedicine,
                          ),
                          const SizedBox(height: 11),
                          _buildStockGrid(
                            filteredMedicine,
                            StockType.medicine,
                            emptyMessage: _searchQuery.isNotEmpty || _lowStockOnly
                                ? 'No medicine matches the current filter.'
                                : 'No medicine stock added yet.',
                          ),

                          const SizedBox(height: 24),

                          _sectionTitle(
                            'Recent Activity',
                            subtitle: 'Latest stock movements',
                          ),
                          const SizedBox(height: 11),
                          _buildMovements(_farmId!),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  List<StockItem> _filterItems(List<StockItem> items) {
    final query = _searchQuery.trim().toLowerCase();

    return items.where((item) {
      final matchesSearch = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.unit.toLowerCase().contains(query);

      final matchesLowStock = !_lowStockOnly || item.isLowStock;

      return matchesSearch && matchesLowStock;
    }).toList();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkGreen.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stock',
                  style: AppTheme.heading(
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Feed, medicine & inventory',
                  style: AppTheme.body(
                    size: 11,
                    color: Colors.white.withOpacity(0.88),
                  ),
                ),
              ],
            ),
          ),

          _headerIconButton(
            icon: _searchOpen
                ? Icons.close_rounded
                : Icons.search_rounded,
            tooltip: _searchOpen ? 'Close search' : 'Search stock',
            onTap: _toggleSearch,
          ),

          const SizedBox(width: 4),

          _headerIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            badge: 3,
            onTap: () {
              Navigator.of(context).push(
                fastRoute(const NotificationScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    int? badge,
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withOpacity(0.14),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 23,
                ),
              ),
            ),
          ),

          if (badge != null)
            Positioned(
              right: -2,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primaryGreen,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      key: const ValueKey('stock-search'),
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: AppColors.primaryGreen.withOpacity(0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (value) {
            setState(() {
              _searchQuery = value.trim();
            });
          },
          style: AppTheme.body(
            size: 13,
            color: AppColors.textDark,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.primaryGreen,
              size: 21,
            ),
            hintText: 'Search feed, medicine or unit',
            hintStyle: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textGrey,
                      size: 18,
                    ),
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary({
    required List<StockItem> allItems,
    required List<StockItem> feedItems,
    required List<StockItem> medicineItems,
    required List<StockItem> lowStockItems,
    required bool loading,
  }) {
    final feedUnits = feedItems.map((item) => item.unit).toSet();
    final feedTotal = feedItems.fold<double>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final feedUnit = feedUnits.length == 1 ? feedUnits.first : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Inventory overview',
                style: AppTheme.heading(size: 16),
              ),
            ),
            if (_lowStockOnly || _searchQuery.isNotEmpty)
              TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Clear filters',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              switch (index) {
                case 0:
                  return _summaryCard(
                    icon: Icons.grass_rounded,
                    label: 'Feed Stock',
                    value: loading
                        ? '—'
                        : feedTotal.toStringAsFixed(0),
                    unit: feedUnit,
                    color: AppColors.stockTeal,
                  );
                case 1:
                  return _summaryCard(
                    icon: Icons.medication_rounded,
                    label: 'Medicines',
                    value: loading ? '—' : '${medicineItems.length}',
                    unit: 'items',
                    color: AppColors.breedingPurple,
                  );
                case 2:
                  return _summaryCard(
                    icon: Icons.warning_amber_rounded,
                    label: 'Low Stock',
                    value: loading ? '—' : '${lowStockItems.length}',
                    unit: 'alerts',
                    color: lowStockItems.isEmpty
                        ? AppColors.success
                        : AppColors.error,
                  );
                default:
                  return _summaryCard(
                    icon: Icons.inventory_2_rounded,
                    label: 'Total Items',
                    value: loading ? '—' : '${allItems.length}',
                    unit: 'tracked',
                    color: AppColors.info,
                  );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: AppColors.divider.withOpacity(0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 19,
            ),
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTheme.heading(
                  size: 19,
                  color: color,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    unit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 9,
                      color: color,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(List<StockItem> items) {
    final names = items.map((item) => item.name).take(3).join(', ');
    final extra = items.length > 3 ? ' +${items.length - 3} more' : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () {
          setState(() => _lowStockOnly = !_lowStockOnly);
        },
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.07),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: AppColors.error.withOpacity(0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${items.length} low-stock alert${items.length == 1 ? '' : 's'}',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.error,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$names$extra',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _lowStockOnly ? 'Show all' : 'View',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.error,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.error,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.heading(size: 16),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(
              Icons.add_rounded,
              size: 16,
            ),
            label: Text(actionLabel),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.85,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _quickActionTile(
          icon: Icons.add_box_rounded,
          title: 'Add Feed',
          subtitle: 'Purchase / refill stock',
          color: AppColors.stockTeal,
          onTap: _openAddFeed,
        ),
        _quickActionTile(
          icon: Icons.medication_rounded,
          title: 'Add Medicine',
          subtitle: 'Add a medicine item',
          color: AppColors.breedingPurple,
          onTap: _openAddMedicine,
        ),
        _quickActionTile(
          icon: Icons.remove_circle_outline_rounded,
          title: 'Feed Used',
          subtitle: 'Record daily usage',
          color: AppColors.warning,
          onTap: _openFeedUsed,
        ),
        _quickActionTile(
          icon: Icons.medical_information_rounded,
          title: 'Medicine Used',
          subtitle: 'Record medicine usage',
          color: AppColors.error,
          onTap: _openMedicineUsed,
        ),
      ],
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: color.withOpacity(0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 10,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.textDark,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 9,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: color.withOpacity(0.65),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStockGrid(
    List<StockItem> items,
    StockType type, {
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return _emptyStockCard(type, emptyMessage);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 650 ? 3 : 2;
        final aspect = constraints.maxWidth >= 650 ? 1.45 : 1.18;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: aspect,
          ),
          itemBuilder: (context, index) {
            return _stockCard(
              items[index],
              type,
              index,
            );
          },
        );
      },
    );
  }

  Widget _stockCard(
    StockItem item,
    StockType type,
    int index,
  ) {
    final low = item.isLowStock;
    final color = low
        ? AppColors.error
        : type == StockType.feed
            ? AppColors.stockTeal
            : AppColors.breedingPurple;

    return FadeInUp(
      delay: Duration(milliseconds: 20 * (index > 8 ? 8 : index)),
      duration: const Duration(milliseconds: 220),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: () => _confirmDelete(item),
          onTap: () => _showStockDetails(item, color),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: low
                    ? AppColors.error.withOpacity(0.25)
                    : AppColors.divider.withOpacity(0.75),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          type == StockType.feed
                              ? Icons.grass_rounded
                              : Icons.medication_rounded,
                          color: color,
                          size: 21,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: AppColors.textGrey,
                          size: 19,
                        ),
                        onSelected: (value) {
                          if (value == 'remove') {
                            _confirmDelete(item);
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove item'),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textDark,
                      weight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          item.quantity.toStringAsFixed(0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.heading(
                            size: 18,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.unit,
                        style: AppTheme.body(
                          size: 9,
                          color: AppColors.textGrey,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      low ? 'Low stock' : 'Good stock',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTheme.body(
                        size: 9,
                        color: color,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyStockCard(
    StockType type,
    String message,
  ) {
    final isFeed = type == StockType.feed;
    final color = isFeed
        ? AppColors.stockTeal
        : AppColors.breedingPurple;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.divider.withOpacity(0.75),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFeed
                  ? Icons.grass_rounded
                  : Icons.medication_rounded,
              color: color,
              size: 25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
          ),
          if (_searchQuery.isEmpty && !_lowStockOnly) ...[
            const SizedBox(height: 11),
            OutlinedButton.icon(
              onPressed: isFeed ? _openAddFeed : _openAddMedicine,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(isFeed ? 'Add Feed' : 'Add Medicine'),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withOpacity(0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showStockDetails(
    StockItem item,
    Color color,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.type == StockType.feed
                            ? Icons.grass_rounded
                            : Icons.medication_rounded,
                        color: color,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: AppTheme.heading(size: 17),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.type == StockType.feed
                                ? 'Feed stock'
                                : 'Medicine stock',
                            style: AppTheme.body(
                              size: 11,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _detailMetric(
                        'Available',
                        '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                        color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _detailMetric(
                        'Threshold',
                        '${item.lowStockThreshold.toStringAsFixed(0)} ${item.unit}',
                        item.isLowStock
                            ? AppColors.error
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.isLowStock
                        ? AppColors.error.withOpacity(0.07)
                        : AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.isLowStock
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        color: item.isLowStock
                            ? AppColors.error
                            : AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.isLowStock
                              ? 'This item needs attention.'
                              : 'Stock level is currently healthy.',
                          style: AppTheme.body(
                            size: 11,
                            color: AppColors.textDark,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Last updated ${DateFormat('dd MMM yyyy, hh:mm a').format(item.lastUpdated)}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          if (item.type == StockType.feed) {
                            _openAddFeed();
                          } else {
                            _openAddMedicine();
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Stock'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withOpacity(0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          if (item.type == StockType.feed) {
                            _openFeedUsed();
                          } else {
                            _openMedicineUsed();
                          }
                        },
                        icon: const Icon(Icons.remove_rounded, size: 18),
                        label: const Text('Record Used'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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

  Widget _detailMetric(
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.body(
              size: 9,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 13,
              color: color,
              weight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovements(String farmId) {
    return StreamBuilder<List<StockMovement>>(
      stream: FirestoreService.instance.stockMovementsStream(
        farmId,
        limit: 6,
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            height: 120,
            alignment: Alignment.center,
            decoration: AppTheme.card(radius: 17),
            child: const CircularProgressIndicator(
              color: AppColors.primaryGreen,
              strokeWidth: 2,
            ),
          );
        }

        final movements = snap.data!;

        if (movements.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.card(radius: 17),
            child: Column(
              children: [
                const Icon(
                  Icons.history_rounded,
                  color: AppColors.textGrey,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  'No stock activity yet',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Purchases and usage will appear here.',
                  style: AppTheme.body(size: 10),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.divider.withOpacity(0.75),
            ),
          ),
          child: Column(
            children: List.generate(
              movements.length,
              (index) {
                final movement = movements[index];
                return _activityTile(
                  movement,
                  isLast: index == movements.length - 1,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _activityTile(
    StockMovement movement, {
    required bool isLast,
  }) {
    final isAddition = movement.isAddition;
    final color = isAddition
        ? AppColors.success
        : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(
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
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAddition
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      movement.notes.isEmpty
                          ? DateFormat('dd MMM, hh:mm a').format(movement.date)
                          : '${DateFormat('dd MMM, hh:mm a').format(movement.date)} · ${movement.notes}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 9,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isAddition ? '+' : '-'}${movement.quantity.toStringAsFixed(0)} ${movement.unit}',
                    style: AppTheme.body(
                      size: 11,
                      color: color,
                      weight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAddition ? 'Added' : 'Used',
                    style: AppTheme.body(
                      size: 8,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!isLast) ...[
            const SizedBox(height: 11),
            Divider(
              height: 1,
              color: AppColors.divider.withOpacity(0.65),
            ),
          ],
        ],
      ),
    );
  }
}
