import 'package:flutter/material.dart';
import '../app_theme.dart';

/// App-wide bottom navigation.
///
/// Order: Home | Palai | Stock (center, raised, brand color) | Reports | Profile
///
/// Use [currentIndex] 0..4 to highlight the active tab. Navigation between
/// top-level tabs is handled by the caller via [onTap] — each module screen
/// (Home/Palai/Stock) owns pushReplacement logic so we don't build a stack
/// of duplicate module screens.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const List<_NavItemData> _items = [
    _NavItemData(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _NavItemData(icon: Icons.home_work_outlined, activeIcon: Icons.home_work, label: 'Palai'),
    _NavItemData(icon: Icons.inventory_2, activeIcon: Icons.inventory_2, label: 'Stock'),
    _NavItemData(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Reports'),
    _NavItemData(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -2)),
              ],
            ),
            child: Row(
              children: List.generate(_items.length, (index) {
                // Leave a gap for the raised center Stock button.
                if (index == 2) {
                  return const Expanded(child: SizedBox());
                }
                final item = _items[index];
                final selected = currentIndex == index;
                return Expanded(
                  child: InkWell(
                    onTap: () => onTap(index),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? item.activeIcon : item.icon,
                            color: selected ? AppColors.primaryGreen : AppColors.textGrey,
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected ? AppColors.primaryGreen : AppColors.textGrey,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Raised, bigger, brand-colored center button for Stock.
          Positioned(
            top: -22,
            child: GestureDetector(
              onTap: () => onTap(2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: currentIndex == 2 ? AppColors.darkGreen : AppColors.primaryGreen,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.inventory_2, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Stock',
                    style: TextStyle(
                      fontSize: 11,
                      color: currentIndex == 2 ? AppColors.primaryGreen : AppColors.textGrey,
                      fontWeight: currentIndex == 2 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItemData({required this.icon, required this.activeIcon, required this.label});
}
