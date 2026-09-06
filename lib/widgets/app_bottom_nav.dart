import 'package:flutter/material.dart';

import '../app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavItemData> _items = [
    _NavItemData(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
      shellIndex: 0,
    ),
    _NavItemData(
      icon: Icons.home_work_outlined,
      activeIcon: Icons.home_work_rounded,
      label: 'Palai',
      shellIndex: 1,
    ),
    _NavItemData(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
      label: 'Stock',
      shellIndex: 2,
    ),
    _NavItemData(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Finance',
      shellIndex: 4,
    ),
    _NavItemData(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
      shellIndex: 5,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 61,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // --------------------------------------------------------------
            // Minimal navigation bar
            // --------------------------------------------------------------
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.055),
                      blurRadius: 12,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildNavItem(_items[0]),
                    ),
                    Expanded(
                      child: _buildNavItem(_items[1]),
                    ),

                    // Space reserved for Stock.
                    const Expanded(
                      child: SizedBox(),
                    ),

                    Expanded(
                      child: _buildNavItem(_items[3]),
                    ),
                    Expanded(
                      child: _buildNavItem(_items[4]),
                    ),
                  ],
                ),
              ),
            ),

            // --------------------------------------------------------------
            // Raised Stock button
            // --------------------------------------------------------------
            Positioned(
              left: 0,
              right: 0,
              top: -22,
              child: Center(
                child: _StockButton(
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(_NavItemData item) {
    final selected = currentIndex == item.shellIndex;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(item.shellIndex),
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.primaryGreen.withOpacity(0.07),
        highlightColor: AppColors.primaryGreen.withOpacity(0.03),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 64,
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryGreen.withOpacity(0.09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (
                  child,
                  animation,
                  ) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: animation,
                    child: child,
                  ),
                );
              },
              child: Column(
                key: ValueKey(selected),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected
                        ? item.activeIcon
                        : item.icon,
                    size: selected ? 21 : 20,
                    color: selected
                        ? AppColors.primaryGreen
                        : AppColors.textGrey,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1,
                      color: selected
                          ? AppColors.primaryGreen
                          : AppColors.textGrey,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
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
}

class _StockButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _StockButton({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppColors.darkGreen
                    : AppColors.primaryGreen,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withOpacity(
                      selected ? 0.30 : 0.20,
                    ),
                    blurRadius: selected ? 13 : 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                selected
                    ? Icons.inventory_2_rounded
                    : Icons.inventory_2_outlined,
                color: Colors.white,
                size: 25,
              ),
            ),

            const SizedBox(height: 1),

            Text(
              'Stock',
              style: TextStyle(
                fontSize: 9.5,
                height: 1,
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.textGrey,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int shellIndex;

  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.shellIndex,
  });
}