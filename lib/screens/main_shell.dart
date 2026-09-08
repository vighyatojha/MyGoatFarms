import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/health_reminder_scheduler.dart';
import 'home/home_screen.dart';
import 'palai/palai_screen.dart';
import 'stocks/stock_screen.dart';
import 'customers/customer_management_screen.dart';
import 'finance/finance_overview_screen.dart';
import 'profile/profile_screen.dart';

/// Main application shell.
///
/// Bottom navigation:
///
/// Home | Palai | Stock | Finance | Profile
///
/// Customers remains available internally through the Palai module,
/// but is not exposed as a bottom navigation destination.
///
/// Back-button behavior:
///
/// Any main screen → Home
/// Home → Exit application
///
/// Profile:
///
/// Any screen → Profile
/// Profile → Home
/// Home → Exit
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  // --------------------------------------------------------------------------
  // CURRENT TAB
  // --------------------------------------------------------------------------

  int _index = 0;

  /// Previous tab.
  ///
  /// Kept for the existing transition logic.
  int _previousIndex = 0;

  /// Whether the current screen was reached by pressing Back.
  bool _isGoingBack = false;

  /// Set once currentFarmId() resolves — used only to drive the unread
  /// badge on the Home tab (see AppBottomNav.showHomeBadge). Everything
  /// else in this shell resolves farmId locally where it's needed, so
  /// this field exists purely for that one stream.
  String? _farmId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPushNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches up the in-app Notifications feed for anything that became
    // due while the app was backgrounded or fully closed — the OS-level
    // alarm still fires its own heads-up notification independently of
    // this, but NotificationScreen only reflects it once this runs,
    // since a killed app can't write to Firestore the instant the alarm
    // itself goes off.
    if (state == AppLifecycleState.resumed) {
      _runDueCheckOnly();
    }
  }

  Future<void> _runDueCheckOnly() async {
    final farmId = await FirestoreService.instance.currentFarmId();
    if (farmId == null || !mounted) return;
    unawaited(HealthReminderScheduler.instance.runDueCheck(farmId));
  }

  /// Requests notification permission and saves this device's FCM token
  /// under the current farm, so the backend notification engine (see
  /// NotificationService docs) knows where to deliver pushes.
  ///
  /// Runs every time MainShell is reached (app start, or right after
  /// login) rather than only once at registration — this is what keeps
  /// a rotated/expired token fresh and re-enables a device that was
  /// disabled on a previous logout.
  Future<void> _initPushNotifications() async {
    final farmId = await FirestoreService.instance.currentFarmId();
    if (farmId == null || !mounted) return;
    setState(() => _farmId = farmId);
    await NotificationService.instance.initForFarm(farmId);

    // Re-arm any health due-date reminders lost to a device reboot, and
    // backfill Firestore's notification history for anything already
    // due/overdue so NotificationScreen has it even if a scheduled
    // on-device alarm was missed. Neither needs to block startup.
    unawaited(HealthReminderScheduler.instance.rescheduleAllForFarm(farmId));
    unawaited(HealthReminderScheduler.instance.runDueCheck(farmId));
  }

  // --------------------------------------------------------------------------
  // MAIN TABS
  // --------------------------------------------------------------------------

  /// Main application screens.
  ///
  /// Customers remains available internally even though it is not exposed
  /// through the bottom navigation.
  ///
  /// IMPORTANT:
  ///
  /// Profile is NOT placed in this list because Profile is opened as its
  /// own route using _profileRoute().
  static const List<Widget> _tabs = [
    HomeScreen(),                   // 0
    PalaiScreen(),                  // 1
    StockScreen(),                  // 2
    CustomerManagementScreen(),     // 3 - internal only
    FinanceOverviewScreen(),        // 4
  ];

  // --------------------------------------------------------------------------
  // TAB NAVIGATION
  // --------------------------------------------------------------------------

  void _navigateToTab(int newIndex) {
    if (!_isValidBottomTab(newIndex)) {
      return;
    }

    if (newIndex == _index) {
      return;
    }

    setState(() {
      _previousIndex = _index;
      _index = newIndex;

      _isGoingBack = false;
    });
  }

  /// Valid bottom navigation destinations inside MainShell.
  ///
  /// 0 = Home
  /// 1 = Palai
  /// 2 = Stock
  /// 4 = Finance
  /// 5 = Profile
  ///
  /// Profile is handled separately because it is a pushed route.
  bool _isValidBottomTab(int index) {
    return index == 0 ||
        index == 1 ||
        index == 2 ||
        index == 4 ||
        index == 5;
  }

  // --------------------------------------------------------------------------
  // PROFILE
  // --------------------------------------------------------------------------

  Future<void> _openProfile() async {
    // ------------------------------------------------------------------------
    // IMPORTANT FIX
    //
    // Set the shell's selected index to Profile BEFORE pushing ProfileScreen.
    //
    // Previously the shell remained on Finance (index 4), so when Profile
    // opened, the bottom navigation still highlighted Finance.
    // ------------------------------------------------------------------------

    if (mounted) {
      setState(() {
        _previousIndex = _index;

        // Profile is index 5 in AppBottomNav.
        _index = 5;

        _isGoingBack = false;
      });
    }

    final result = await Navigator.of(context).push<int>(
      _profileRoute(),
    );

    if (!mounted) {
      return;
    }

    // ------------------------------------------------------------------------
    // Profile was closed with Android/system Back.
    //
    // Always return to Home according to the requested navigation behavior.
    // ------------------------------------------------------------------------

    if (result == null) {
      if (_index != 0) {
        setState(() {
          _previousIndex = _index;
          _index = 0;
          _isGoingBack = true;
        });
      }

      return;
    }

    // ------------------------------------------------------------------------
    // Profile's bottom navigation selected another destination.
    // ------------------------------------------------------------------------

    if (_isValidBottomTab(result)) {
      if (result == 5) {
        // Already on Profile.
        return;
      }

      _navigateToTab(result);
    }
  }

  /// Profile screen transition.
  ///
  /// Existing animation intentionally preserved.
  PageRoute<int> _profileRoute() {
    return PageRouteBuilder<int>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),

      pageBuilder: (
          context,
          animation,
          secondaryAnimation,
          ) {
        return const ProfileScreen();
      },

      transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
          ) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // ANDROID / SYSTEM BACK
  // --------------------------------------------------------------------------

  Future<bool> _handleBack() async {
    // ------------------------------------------------------------------------
    // ANY SCREEN OTHER THAN HOME
    // ------------------------------------------------------------------------

    if (_index != 0) {
      setState(() {
        _previousIndex = _index;

        // Always return directly to Home.
        _index = 0;

        _isGoingBack = true;
      });

      return false;
    }

    // ------------------------------------------------------------------------
    // ALREADY ON HOME
    //
    // Second Back exits the application.
    // ------------------------------------------------------------------------

    return true;
  }

  // --------------------------------------------------------------------------
  // SCREEN TRANSITION
  // --------------------------------------------------------------------------

  Widget _buildTabTransition() {
    // ------------------------------------------------------------------------
    // Profile is a separate route.
    //
    // While Profile is open, this widget is underneath the Profile route,
    // so _tabs[_index] must NOT be accessed when _index == 5.
    // ------------------------------------------------------------------------

    final tabIndex = _index == 5 ? 0 : _index;
    final currentScreen = _tabs[tabIndex];

    final Offset beginOffset;

    if (_isGoingBack) {
      beginOffset = const Offset(-0.035, 0);
    } else {
      beginOffset = const Offset(0.035, 0);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),

      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,

      layoutBuilder: (
          currentChild,
          previousChildren,
          ) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },

      transitionBuilder: (
          child,
          animation,
          ) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },

      child: KeyedSubtree(
        key: ValueKey(tabIndex),
        child: currentScreen,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,

      onPopInvokedWithResult: (
          didPop,
          result,
          ) async {
        if (didPop) {
          return;
        }

        // --------------------------------------------------------------
        // IMPORTANT:
        //
        // If Profile is currently open, its own route should handle
        // the Back button and return null to _openProfile().
        //
        // We therefore do not handle Profile Back here.
        // --------------------------------------------------------------

        if (_index == 5) {
          return;
        }

        final shouldExit = await _handleBack();

        if (shouldExit && mounted) {
          await SystemNavigator.pop();
        }
      },

      child: Scaffold(
        backgroundColor: AppColors.paleGreen,

        body: _buildTabTransition(),

        bottomNavigationBar: _farmId == null
            ? AppBottomNav(
          currentIndex: _index,

          onTap: (index) {
            if (index == 5) {
              _openProfile();
              return;
            }
            _navigateToTab(index);
          },
        )
            : StreamBuilder<bool>(
          stream: FirestoreService.instance.hasUnreadNotificationsStream(_farmId!),
          builder: (context, snap) {
            return AppBottomNav(
              currentIndex: _index,
              showHomeBadge: snap.data ?? false,

              onTap: (index) {
                // ------------------------------------------------------------
                // Profile
                // ------------------------------------------------------------

                if (index == 5) {
                  _openProfile();
                  return;
                }

                // ------------------------------------------------------------
                // Home / Palai / Stock / Finance
                // ------------------------------------------------------------

                _navigateToTab(index);
              },
            );
          },
        ),
      ),
    );
  }
}