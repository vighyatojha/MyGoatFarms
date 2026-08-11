import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:animate_do/animate_do.dart';

import '../../app_theme.dart';
import '../../models/farm_model.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_bottom_nav.dart';
import 'widgets/home_widgets.dart';
import '../palai/palai_screen.dart';
import '../stocks/stock_screen.dart';
import 'notification_screen.dart';
import 'total_goats_screen.dart';
import 'income_detail_screen.dart';
import '../login_screen.dart';

/// Home / dashboard screen. Quick, at-a-glance view of the whole farm —
/// live totals, the four main modules, quick actions and recent activity.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _navIndex = 0;

  FarmModel? _farm;
  bool _loadingFarm = true;
  String? _farmId;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFarmData();
  }

  Future<void> _loadFarmData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final farm = await FirestoreService.instance.getFarmByAuthUid(uid);
    if (mounted) {
      setState(() {
        _farm = farm;
        _farmId = farm?.id;
        _loadingFarm = false;
      });
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature module coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    switch (index) {
      case 1:
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PalaiScreen()));
        break;
      case 2:
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StockScreen()));
        break;
      case 3:
        _comingSoon('Reports');
        break;
      case 4:
        _showProfileMenu(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = _farm?.ownerName.isNotEmpty == true
        ? _farm!.ownerName
        : FirebaseAuth.instance.currentUser?.displayName ?? 'Farmer';
    final farmName = _farm?.farmName.isNotEmpty == true ? _farm!.farmName : 'My Goat Farms';

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadFarmData,
          color: AppColors.primaryGreen,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeInDown(
                  duration: const Duration(milliseconds: 500),
                  child: _buildHeader(farmName, ownerName),
                ),
                const SizedBox(height: 20),
                Text('Alhamdulillah for everything', style: AppTheme.body(size: 13, weight: FontWeight.w500)),
                const SizedBox(height: 14),
                _buildSearchBar(),
                const SizedBox(height: 16),
                if (_farmId != null) _buildStatGrid(_farmId!) else _buildStatGridLoading(),
                const SizedBox(height: 24),
                Text('Main Modules', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                FadeInUp(
                  delay: const Duration(milliseconds: 250),
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.8,
                    children: [
                      ModuleTile(
                        icon: Icons.home_work_outlined,
                        label: 'Palai',
                        sub: 'Boarding & Care',
                        color: AppColors.primaryGreen,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const PalaiScreen())),
                      ),
                      ModuleTile(
                        icon: Icons.swap_horiz,
                        label: 'Trading',
                        sub: 'Buy & Sell',
                        color: AppColors.tradingBlue,
                        onTap: () => _comingSoon('Trading'),
                      ),
                      ModuleTile(
                        icon: Icons.biotech_outlined,
                        label: 'Breeding',
                        sub: 'Records',
                        color: AppColors.breedingPurple,
                        onTap: () => _comingSoon('Breeding'),
                      ),
                      ModuleTile(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stock',
                        sub: 'Feed & Med',
                        color: AppColors.stockTeal,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const StockScreen())),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Quick Actions', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                if (_farmId != null) _buildQuickActions(_farmId!),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Activities', style: AppTheme.heading(size: 16)),
                    GestureDetector(
                      onTap: () => _comingSoon('Activities'),
                      child: Text(
                        'View All',
                        style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_farmId != null) _buildActivities(_farmId!),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(currentIndex: _navIndex, onTap: _onNavTap),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search, color: AppColors.textGrey, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Goat ID, Customer, Batch, Invoice...',
                hintStyle: AppTheme.body(size: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ),
          Icon(Icons.tune, color: AppColors.primaryGreen, size: 20),
        ],
      ),
    );
  }

  Widget _buildStatGridLoading() {
    return Row(
      children: const [
        Expanded(child: SizedBox(height: 90)),
        SizedBox(width: 12),
        Expanded(child: SizedBox(height: 90)),
      ],
    );
  }

  Widget _buildStatGrid(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 150),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StreamBuilder<List<PalaiGoat>>(
                  stream: FirestoreService.instance.allActiveGoatsStream(farmId),
                  builder: (context, snap) {
                    final count = snap.data?.length ?? 0;
                    return StatCard(
                      icon: Icons.pets,
                      label: 'Total Goats',
                      value: snap.hasData ? '$count' : '—',
                      color: AppColors.primaryGreen,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const TotalGoatsScreen())),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<double>(
                  stream: FirestoreService.instance.todaysIncomeStream(farmId),
                  builder: (context, snap) {
                    final value = snap.data ?? 0;
                    return StatCard(
                      icon: Icons.currency_rupee,
                      label: "Today's Income",
                      value: snap.hasData ? '₹${value.toStringAsFixed(0)}' : '—',
                      color: AppColors.warning,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const IncomeDetailScreen())),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StreamBuilder<double>(
                  stream: FirestoreService.instance.totalPendingPaymentsStream(farmId),
                  builder: (context, snap) {
                    final value = snap.data ?? 0;
                    return StatCard(
                      icon: Icons.credit_card_outlined,
                      label: 'Pending Payments',
                      value: snap.hasData ? '₹${value.toStringAsFixed(0)}' : '—',
                      color: AppColors.error,
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<List<dynamic>>(
                  stream: FirestoreService.instance.stockItemsStream(farmId),
                  builder: (context, snap) {
                    final totalKg = (snap.data ?? [])
                        .fold<double>(0, (sum, item) => sum + (item.quantity as double));
                    return StatCard(
                      icon: Icons.grass_outlined,
                      label: 'Feed in Stock',
                      value: snap.hasData ? '${totalKg.toStringAsFixed(0)} kg' : '—',
                      color: AppColors.stockTeal,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const StockScreen())),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 350),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          QuickAction(
            icon: Icons.add,
            label: 'Add Goat',
            color: AppColors.primaryGreen,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PalaiScreen())),
          ),
          QuickAction(
            icon: Icons.payments_outlined,
            label: 'Receive\nPayment',
            color: AppColors.success,
            onTap: () => _comingSoon('Receive Payment'),
          ),
          QuickAction(
            icon: Icons.remove,
            label: 'Add\nExpense',
            color: AppColors.error,
            onTap: () => _comingSoon('Add Expense'),
          ),
          QuickAction(
            icon: Icons.grass_outlined,
            label: 'Add Feed\nStock',
            color: AppColors.info,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StockScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildActivities(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 450),
      child: StreamBuilder<List<ActivityLog>>(
        stream: FirestoreService.instance.activitiesStream(farmId, limit: 5),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
            );
          }
          final activities = snap.data!;
          if (activities.isEmpty) {
            return Text('No recent activity yet.', style: AppTheme.body(size: 12));
          }
          return Column(
            children: activities.map((a) => ActivityTile(activity: a)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildHeader(String farmName, String ownerName) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
          child: const Icon(Icons.pets, color: AppColors.primaryGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(farmName, style: AppTheme.heading(size: 16), overflow: TextOverflow.ellipsis),
              Text('Good Morning, $ownerName 👋', style: AppTheme.body(size: 12), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationScreen())),
          icon: const Icon(Icons.notifications_none, color: AppColors.textDark),
        ),
        GestureDetector(
          onTap: () => _showProfileMenu(context),
          child: const CircleAvatar(
            backgroundColor: AppColors.lightGreen,
            child: Icon(Icons.person, color: AppColors.primaryGreen),
          ),
        ),
      ],
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: Text('Logout', style: AppTheme.heading(size: 15, color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _logout();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
