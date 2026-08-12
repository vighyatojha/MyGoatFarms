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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeInDown(duration: const Duration(milliseconds: 180), child: _buildHeader()),
              const SizedBox(height: 18),
              _buildSummary(_farmId!),
              const SizedBox(height: 24),
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
        IconButton(onPressed: () => _comingSoon('Notifications'), icon: const Icon(Icons.notifications_none, color: AppColors.textDark)),
      ],
    );
  }

  Widget _buildSummary(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 38),
      duration: const Duration(milliseconds: 220),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<List<StockItem>>(
              stream: FirestoreService.instance.stockItemsStream(farmId, type: StockType.feed),
              builder: (context, snap) {
                final total = (snap.data ?? []).fold<double>(0, (s, i) => s + i.quantity);
                return StatCard(
                  icon: Icons.grass_outlined,
                  label: 'Total Feed Stock',
                  value: snap.hasData ? '${total.toStringAsFixed(0)} kg' : '—',
                  color: AppColors.stockTeal,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<List<StockItem>>(
              stream: FirestoreService.instance.stockItemsStream(farmId, type: StockType.medicine),
              builder: (context, snap) {
                final total = (snap.data ?? []).fold<double>(0, (s, i) => s + i.quantity);
                return StatCard(
                  icon: Icons.medication_outlined,
                  label: 'Medicine Units',
                  value: snap.hasData ? total.toStringAsFixed(0) : '—',
                  color: AppColors.breedingPurple,
                );
              },
            ),
          ),
        ],
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
            return Text(
              type == StockType.feed ? 'No feed stock added yet.' : 'No medicine stock added yet.',
              style: AppTheme.body(size: 12),
            );
          }
          return Column(
            children: items.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(radius: 14),
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
                            Text('Low stock', style: AppTheme.body(size: 11, color: AppColors.error)),
                        ],
                      ),
                    ),
                    Text('${item.quantity.toStringAsFixed(0)} ${item.unit}', style: AppTheme.heading(size: 13)),
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
                          Text(DateFormat('dd MMM, hh:mm a').format(m.date), style: AppTheme.body(size: 11)),
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