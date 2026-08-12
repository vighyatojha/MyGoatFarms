import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'home/home_screen.dart';
import 'palai/palai_screen.dart';
import 'stocks/stock_screen.dart';
import 'login_screen.dart';

/// Persistent app shell for the three main tabs (Home, Palai, Stock).
///
/// Previously each of these screens was its own full [Scaffold] with its
/// own [AppBottomNav], so switching tabs meant destroying and rebuilding
/// the whole screen — refetching farm data, replaying every entrance
/// animation, and running a full page-transition — every single time.
///
/// Here they live side-by-side in an [IndexedStack] under ONE bottom nav.
/// Switching tabs just swaps which child is visible: no rebuild, no
/// refetch, no transition animation. Each tab keeps its scroll position
/// and already-loaded data exactly as you left it.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const List<Widget> _tabs = [
    HomeScreen(),
    PalaiScreen(),
    StockScreen(),
  ];

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  void _showProfileMenu() {
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

  /// Tabs 0–2 (Home/Palai/Stock) just flip the visible child. Reports and
  /// Profile aren't tabs with their own persisted content, so they behave
  /// the same as before (a "coming soon" toast / the profile sheet) rather
  /// than becoming a 4th and 5th IndexedStack child.
  void _onNavTap(int index) {
    switch (index) {
      case 0:
      case 1:
      case 2:
        if (index != _index) setState(() => _index = index);
        break;
      case 3:
        _comingSoon('Reports');
        break;
      case 4:
        _showProfileMenu();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: AppBottomNav(currentIndex: _index, onTap: _onNavTap),
    );
  }
}