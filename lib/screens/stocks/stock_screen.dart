import 'dart:async';

import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../home/widgets/home_widgets.dart';
import 'add_feed_stock_screen.dart';
import 'add_medicine_screen.dart';
import 'feed_used_screen.dart';
import 'medicine_used_screen.dart';
import '../home/notification_screen.dart';

/// Stock (Feed, Medicine & Expenses) module dashboard.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String? _farmId;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  Future<void> _confirmDelete(StockItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove ${item.name}?', style: AppTheme.heading(size: 16)),
        content: Text(
          'This removes the stock item from tracking. Its past add/use history stays in Recent Stock Activity.',
          style: AppTheme.body(size: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: AppTheme.body(size: 13, color: AppColors.textGrey))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove', style: AppTheme.body(size: 13, color: AppColors.error, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && _farmId != null) {
      try {
        await FirestoreService.instance.deleteStockItem(_farmId!, item.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.name} removed'), backgroundColor: AppColors.darkGreen),
        );
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is taking too long. Check your connection and try again.'), backgroundColor: AppColors.error),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : RefreshIndicator(
          color: AppColors.primaryGreen,
          onRefresh: () async {
            // Streams keep everything live; this just gives the
            // person a tactile "yep, up to date" gesture on pull.
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeInDown(duration: const Duration(milliseconds: 180), child: _buildHeader()),
                const SizedBox(height: 18),
                _buildSummary(_farmId!),
                const SizedBox(height: 20),
                Text('Quick Actions', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                _buildQuickActions(),
                const SizedBox(height: 24),
                Text('Feed Stock', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                _buildStockList(_farmId!, StockType.feed),
                const SizedBox(height: 24),
                Text('Medicine Stock', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                _buildStockList(_farmId!, StockType.medicine),
                const SizedBox(height: 24),
                Text('Recent Stock Activity', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                _buildMovements(_farmId!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
          child: const Icon(Icons.inventory_2, color: AppColors.primaryGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock', style: AppTheme.heading(size: 17)),
              Text('Feed, Medicine & Expenses', style: AppTheme.body(size: 12)),
            ],
          ),
        ),
        IconButton(onPressed: () => Navigator.of(context).push(fastRoute(const NotificationScreen())), icon: const Icon(Icons.notifications_none, color: AppColors.textDark)),
      ],
    );
  }

  Widget _buildSummary(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 38),
      duration: const Duration(milliseconds: 220),
      child: StreamBuilder<List<StockItem>>(
        stream: FirestoreService.instance.stockItemsStream(farmId),
        builder: (context, snap) {
          final items = snap.data ?? [];
          final feedItems = items.where((i) => i.type == StockType.feed).toList();
          final feedTotal = feedItems.fold<double>(0, (s, i) => s + i.quantity);
          // Feed can be tracked in Kg or Bag per item — only show a unit
          // suffix on the summary card when every feed item agrees on one,
          // otherwise the total would mix weight and bag counts.
          final feedUnits = feedItems.map((i) => i.unit).toSet();
          final feedUnitLabel = feedUnits.length == 1 ? feedUnits.first : '';
          final medicineCount = items.where((i) => i.type == StockType.medicine).length;
          final lowStockItems = items.where((i) => i.isLowStock).toList();

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.grass_outlined,
                      label: 'Total Feed Stock',
                      value: snap.hasData
                          ? '${feedTotal.toStringAsFixed(0)}${feedUnitLabel.isNotEmpty ? ' $feedUnitLabel' : ''}'
                          : '—',
                      color: AppColors.stockTeal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.medication_outlined,
                      label: 'Medicines Tracked',
                      value: snap.hasData ? '$medicineCount' : '—',
                      color: AppColors.breedingPurple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.inventory_outlined,
                      label: 'Items Tracked',
                      value: snap.hasData ? '${items.length}' : '—',
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.warning_amber_outlined,
                      label: 'Low Stock Alerts',
                      value: snap.hasData ? '${lowStockItems.length}' : '—',
                      color: lowStockItems.isEmpty ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
              if (snap.hasData && lowStockItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.error.withOpacity(0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Running low: ${lowStockItems.map((i) => i.name).join(', ')}',
                          style: AppTheme.body(size: 12, color: AppColors.error, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickActions() {
    return FadeInUp(
      delay: const Duration(milliseconds: 62),
      duration: const Duration(milliseconds: 220),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          QuickAction(
            icon: Icons.add,
            label: 'Add Feed\nStock',
            color: AppColors.stockTeal,
            onTap: () => Navigator.of(context).push(fastRoute(const AddFeedStockScreen())),
          ),
          QuickAction(
            icon: Icons.medication_outlined,
            label: 'Add\nMedicine',
            color: AppColors.breedingPurple,
            onTap: () => Navigator.of(context).push(fastRoute(const AddMedicineScreen())),
          ),
          QuickAction(
            icon: Icons.remove,
            label: 'Feed Used\nToday',
            color: AppColors.warning,
            onTap: () => Navigator.of(context).push(fastRoute(const FeedUsedScreen())),
          ),
          QuickAction(
            icon: Icons.medical_information_outlined,
            label: 'Medicine\nUsed',
            color: AppColors.error,
            onTap: () => Navigator.of(context).push(fastRoute(const MedicineUsedScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildStockList(String farmId, StockType type) {
    return FadeInUp(
      delay: const Duration(milliseconds: 75),
      duration: const Duration(milliseconds: 220),
      child: StreamBuilder<List<StockItem>>(
        stream: FirestoreService.instance.stockItemsStream(farmId, type: type),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: AppTheme.card(radius: 14),
              child: Column(
                children: [
                  Icon(
                    type == StockType.feed ? Icons.grass_outlined : Icons.medication_outlined,
                    color: AppColors.textGrey,
                    size: 26,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    type == StockType.feed ? 'No feed stock added yet.' : 'No medicine stock added yet.',
                    style: AppTheme.body(size: 12),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: items.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: item.isLowStock ? Border.all(color: AppColors.error.withOpacity(0.35)) : null,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (item.isLowStock ? AppColors.error : AppColors.stockTeal).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        type == StockType.feed ? Icons.grass_outlined : Icons.medication_outlined,
                        color: item.isLowStock ? AppColors.error : AppColors.stockTeal,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: AppTheme.heading(size: 13)),
                          if (item.isLowStock)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Low stock', style: AppTheme.body(size: 10, color: AppColors.error, weight: FontWeight.w600)),
                            )
                          else
                            Text('Updated ${DateFormat('dd MMM').format(item.lastUpdated)}', style: AppTheme.body(size: 11)),
                        ],
                      ),
                    ),
                    Text('${item.quantity.toStringAsFixed(0)} ${item.unit}', style: AppTheme.heading(size: 13)),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, color: AppColors.textGrey, size: 18),
                      onSelected: (v) {
                        if (v == 'delete') _confirmDelete(item);
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(value: 'delete', child: Text('Remove item')),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildMovements(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 100),
      duration: const Duration(milliseconds: 220),
      child: StreamBuilder<List<StockMovement>>(
        stream: FirestoreService.instance.stockMovementsStream(farmId, limit: 10),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
            );
          }
          final movements = snap.data!;
          if (movements.isEmpty) {
            return Text('No stock activity yet.', style: AppTheme.body(size: 12));
          }
          return Column(
            children: movements.map((m) {
              final isAddition = m.isAddition;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(radius: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isAddition ? AppColors.success : AppColors.warning).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAddition ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isAddition ? AppColors.success : AppColors.warning,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.itemName, style: AppTheme.heading(size: 13)),
                          Text(
                            m.notes.isEmpty
                                ? DateFormat('dd MMM, hh:mm a').format(m.date)
                                : '${DateFormat('dd MMM, hh:mm a').format(m.date)} · ${m.notes}',
                            style: AppTheme.body(size: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isAddition ? '+' : '-'}${m.quantity.toStringAsFixed(0)} ${m.unit}',
                      style: AppTheme.heading(size: 13, color: isAddition ? AppColors.success : AppColors.warning),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}