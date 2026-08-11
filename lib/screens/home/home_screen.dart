import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:animate_do/animate_do.dart';

import '../../app_theme.dart';
import '../../models/farm_model.dart';
import '../../services/firestore_service.dart';
import '../login_screen.dart';

/// Home / dashboard screen. Shows the farm's stats, the four main
/// modules, quick actions and recent activity, matching the mockup.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  FarmModel? _farm;
  bool _loadingFarm = true;

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
                FadeInUp(
                  delay: const Duration(milliseconds: 150),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.pets,
                          label: 'Total Goats',
                          value: _loadingFarm ? '—' : '245',
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.currency_rupee,
                          label: "Today's Income",
                          value: _loadingFarm ? '—' : '₹24,850',
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
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
                      _ModuleTile(
                        icon: Icons.home_work_outlined,
                        label: 'Palai',
                        sub: 'Boarding & Care',
                        color: AppColors.primaryGreen,
                        onTap: () => _comingSoon('Palai'),
                      ),
                      _ModuleTile(
                        icon: Icons.swap_horiz,
                        label: 'Trading',
                        sub: 'Buy & Sell',
                        color: const Color(0xFF64B5F6),
                        onTap: () => _comingSoon('Trading'),
                      ),
                      _ModuleTile(
                        icon: Icons.biotech_outlined,
                        label: 'Breeding',
                        sub: 'Records',
                        color: const Color(0xFFBA68C8),
                        onTap: () => _comingSoon('Breeding'),
                      ),
                      _ModuleTile(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stock',
                        sub: 'Feed & Med',
                        color: const Color(0xFF4DB6AC),
                        onTap: () => _comingSoon('Stock'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Quick Actions', style: AppTheme.heading(size: 16)),
                const SizedBox(height: 12),
                FadeInUp(
                  delay: const Duration(milliseconds: 350),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _QuickAction(
                        icon: Icons.add,
                        label: 'Add Goat',
                        color: AppColors.primaryGreen,
                        onTap: () => _comingSoon('Add Goat'),
                      ),
                      _QuickAction(
                        icon: Icons.payments_outlined,
                        label: 'Receive\nPayment',
                        color: AppColors.success,
                        onTap: () => _comingSoon('Receive Payment'),
                      ),
                      _QuickAction(
                        icon: Icons.remove,
                        label: 'Add\nExpense',
                        color: AppColors.error,
                        onTap: () => _comingSoon('Add Expense'),
                      ),
                      _QuickAction(
                        icon: Icons.grass_outlined,
                        label: 'Add Feed\nStock',
                        color: const Color(0xFF4FC3F7),
                        onTap: () => _comingSoon('Add Feed Stock'),
                      ),
                    ],
                  ),
                ),
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
                FadeInUp(
                  delay: const Duration(milliseconds: 450),
                  child: Column(
                    children: const [
                      _ActivityTile(
                        icon: Icons.payments_outlined,
                        color: AppColors.success,
                        title: 'Payment Received',
                        subtitle: 'Received ₹5,000 from Rameshbhai',
                        time: '10:30 AM',
                      ),
                      _ActivityTile(
                        icon: Icons.sell_outlined,
                        color: AppColors.warning,
                        title: 'Goat Sold',
                        subtitle: '1 goat sold to Maheshbhai',
                        time: 'Yesterday',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        selectedItemColor: AppColors.primaryGreen,
        unselectedItemColor: AppColors.textGrey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 4) {
            _showProfileMenu(context);
            return;
          }
          setState(() => _selectedTab = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_none), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
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
          onPressed: () => _comingSoon('Notifications'),
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(value, style: AppTheme.heading(size: 18)),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.body(size: 11)),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  const _ModuleTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              style: AppTheme.heading(size: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              sub,
              style: AppTheme.body(size: 8),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.body(size: 10), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  const _ActivityTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.heading(size: 13)),
                Text(subtitle, style: AppTheme.body(size: 11)),
              ],
            ),
          ),
          Text(time, style: AppTheme.body(size: 10)),
        ],
      ),
    );
  }
}
