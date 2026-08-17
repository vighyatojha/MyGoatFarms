import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/fast_route.dart';
import 'home/home_screen.dart';
import 'palai/palai_screen.dart';
import 'stocks/stock_screen.dart';
import 'customers/customer_management_screen.dart';
import 'profile/profile_screen.dart';

/// Persistent app shell for the four main tabs (Home, Palai, Stock, Customers).
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
    CustomerManagementScreen(),
  ];

  /// Tabs 0–3 (Home/Palai/Stock/Customers) just flip the visible child, so
  /// switching between them never rebuilds or refetches. Profile is a real
  /// screen — it opens on top of the shell so backing out returns to
  /// whichever tab was showing.
  void _onNavTap(int index) {
    switch (index) {
      case 0:
      case 1:
      case 2:
      case 3:
        if (index != _index) setState(() => _index = index);
        break;
      case 4:
        Navigator.of(context).push(fastRoute(const ProfileScreen()));
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