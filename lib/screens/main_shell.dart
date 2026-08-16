import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/fast_route.dart';
import 'home/home_screen.dart';
import 'palai/palai_screen.dart';
import 'stocks/stock_screen.dart';
import 'profile/profile_screen.dart';

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

  /// Tabs 0–2 (Home/Palai/Stock) just flip the visible child. Customers isn't
  /// a tab with its own persisted content yet, so it stays a "coming soon"
  /// toast. Profile is a real screen — it opens on top of the shell so
  /// backing out returns to whichever tab was showing.
  void _onNavTap(int index) {
    switch (index) {
      case 0:
      case 1:
      case 2:
        if (index != _index) setState(() => _index = index);
        break;
      case 3:
        _comingSoon('Customers');
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