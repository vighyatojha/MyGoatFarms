import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/finance_scope.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import 'finance_range.dart';
import 'palai_finance_view.dart';
import 'trading_finance_view.dart';

/// Finance tab — two sides, one screen:
///
///   [ Palai ]  [ Trading ]
///
///  * Palai    customers, their bills / payments / receivables, and the
///             farm's own running costs.
///  * Trading  goat purchases, goat sales, sale credit.
///
/// The two sides never share a total. One date-range selector at the top
/// drives whichever side is showing, and each side keeps its own state
/// when you switch back and forth.
class FinanceHomeScreen extends StatefulWidget {
  final FinanceScope initialScope;

  const FinanceHomeScreen({
    super.key,
    this.initialScope = FinanceScope.palai,
  });

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  late FinanceScope _scope = widget.initialScope;
  FinanceRangePreset _preset = FinanceRangePreset.all;

  /// The Trading side is only built the first time it is opened, so
  /// opening Finance doesn't run both sides' queries up front.
  late bool _tradingVisited = widget.initialScope == FinanceScope.trading;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final id = await FirestoreService.instance.currentFarmId();
    if (!mounted) return;
    setState(() {
      _farmId = id;
      _loadingFarm = false;
    });
  }

  Color _accent(FinanceScope scope) =>
      scope == FinanceScope.palai ? AppColors.primaryGreen : AppColors.info;

  void _selectScope(FinanceScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      if (scope == FinanceScope.trading) _tradingVisited = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _loadingFarm
            ? const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        )
            : _farmId == null
            ? Column(
          children: [
            _header(),
            Expanded(
              child: FarmNotLinkedState(
                buttonColor: AppColors.primaryGreen,
                onRetry: () {
                  setState(() => _loadingFarm = true);
                  _loadFarm();
                },
              ),
            ),
          ],
        )
            : Column(
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _scopeSwitch(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: FinanceRangeSelector(
                selected: _preset,
                accent: _accent(_scope),
                onChanged: (p) => setState(() => _preset = p),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _scope == FinanceScope.palai ? 0 : 1,
                children: [
                  PalaiFinanceView(farmId: _farmId!, preset: _preset),
                  if (_tradingVisited)
                    TradingFinanceView(farmId: _farmId!, preset: _preset)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Branded header — same logo-avatar style as the Home screen.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          if (Navigator.of(context).canPop()) ...[
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.savings_rounded,
                  color: AppColors.primaryGreen,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finance', style: AppTheme.heading(size: 18)),
                Text(
                  _scope.longLabel,
                  style: AppTheme.body(size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Two-sided switch: Palai on one side, Trading on the other.
  Widget _scopeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _scopeButton(
              scope: FinanceScope.palai,
              icon: Icons.people_alt_outlined,
              title: 'Palai',
              subtitle: 'Customers',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _scopeButton(
              scope: FinanceScope.trading,
              icon: Icons.swap_horiz_rounded,
              title: 'Trading',
              subtitle: 'Buy & Sell',
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeButton({
    required FinanceScope scope,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _scope == scope;
    final accent = _accent(scope);

    return GestureDetector(
      onTap: () => _selectScope(scope),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppColors.textGrey,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.heading(
                    size: 13,
                    color: selected ? Colors.white : AppColors.textDark,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTheme.body(
                    size: 9.5,
                    color: selected ? Colors.white70 : AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}