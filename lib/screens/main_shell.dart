import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../widgets/app_bottom_nav.dart';
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
/// Example:
///
/// Home → Palai → Stock → Finance
///
/// Phone Back → Home
/// Phone Back → Exit
///
/// Profile:
///
/// Any screen → Profile
/// Phone Back → Home
/// Phone Back → Exit
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // --------------------------------------------------------------------------
  // CURRENT TAB
  // --------------------------------------------------------------------------

  int _index = 0;

  /// Previous tab.
  ///
  /// This is kept for the existing transition logic.
  int _previousIndex = 0;

  /// Whether the current screen was reached by pressing Back.
  ///
  /// This controls the direction of the existing tab animation.
  bool _isGoingBack = false;

  // --------------------------------------------------------------------------
  // MAIN TABS
  // --------------------------------------------------------------------------

  /// Main application screens.
  ///
  /// Customers is intentionally kept here because it may still be used
  /// internally by the application, even though it is not exposed through
  /// the bottom navigation bar.
  static const List<Widget> _tabs = [
    HomeScreen(),                    // 0
    PalaiScreen(),                   // 1
    StockScreen(),                   // 2
    CustomerManagementScreen(),      // 3 - internal only
    FinanceOverviewScreen(),         // 4
  ];

  // --------------------------------------------------------------------------
  // TAB NAVIGATION
  // --------------------------------------------------------------------------

  /// Handles bottom navigation tab selection.
  ///
  /// Navigation itself is completely independent of the Android Back button.
  ///
  /// The user can freely navigate:
  ///
  /// Home → Finance
  /// Finance → Palai
  /// Palai → Stock
  /// Stock → Home
  ///
  /// etc.
  void _navigateToTab(int newIndex) {
    if (!_isValidBottomTab(newIndex)) {
      return;
    }

    // Already on this screen.
    if (newIndex == _index) {
      return;
    }

    setState(() {
      _previousIndex = _index;
      _index = newIndex;

      // This was a direct navigation from the bottom navigation.
      _isGoingBack = false;
    });
  }

  /// Returns true only for screens that are actually exposed through
  /// the bottom navigation.
  ///
  /// 0 = Home
  /// 1 = Palai
  /// 2 = Stock
  /// 4 = Finance
  /// 5 = Profile
  ///
  /// Index 3 (Customers) is intentionally excluded.
  bool _isValidBottomTab(int index) {
    return index == 0 ||
        index == 1 ||
        index == 2 ||
        index == 4;
  }

  // --------------------------------------------------------------------------
  // PROFILE
  // --------------------------------------------------------------------------

  /// Opens Profile using the existing custom transition.
  ///
  /// Profile is intentionally pushed as a separate route because it already
  /// has its own screen/flow.
  Future<void> _openProfile() async {
    final result = await Navigator.of(context).push<int>(
      _profileRoute(),
    );

    if (!mounted) {
      return;
    }

    // ------------------------------------------------------------------------
    // Profile was closed using the Android/system Back button.
    //
    // In this case there is no result, so ALWAYS return to Home.
    //
    // Example:
    //
    // Palai → Profile → Back
    //
    // becomes:
    //
    // Palai → Profile → Home
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
    // Profile's own bottom navigation selected another destination.
    //
    // In that case we still respect the selected destination.
    // ------------------------------------------------------------------------
    if (_isValidBottomTab(result)) {
      _navigateToTab(result);
    }
  }

  /// Profile screen transition.
  ///
  /// This is kept from your existing implementation.
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

  /// Handles the Android phone Back button.
  ///
  /// IMPORTANT:
  ///
  /// There is deliberately NO navigation history here.
  ///
  /// The rule is:
  ///
  ///     Current screen != Home
  ///                 ↓
  ///               Home
  ///
  ///     Current screen == Home
  ///                 ↓
  ///             Exit app
  ///
  /// Therefore:
  ///
  /// Home → Palai → Stock → Finance
  ///
  /// Back → Home
  ///
  /// Back → Exit
  Future<bool> _handleBack() async {
    // ------------------------------------------------------------------------
    // ANY SCREEN OTHER THAN HOME
    // ------------------------------------------------------------------------

    if (_index != 0) {
      setState(() {
        _previousIndex = _index;

        // Always return directly to Home.
        _index = 0;

        // Tell the existing animation that this navigation happened
        // because of Back.
        _isGoingBack = true;
      });

      return false;
    }

    // ------------------------------------------------------------------------
    // ALREADY ON HOME
    // ------------------------------------------------------------------------
    //
    // There is nowhere else to navigate.
    //
    // The user wants the second Back press to exit the application.
    // ------------------------------------------------------------------------

    return true;
  }

  // --------------------------------------------------------------------------
  // SCREEN TRANSITION
  // --------------------------------------------------------------------------

  /// Builds the existing animated tab transition.
  ///
  /// This has intentionally NOT been replaced with a simple IndexedStack
  /// or a simple screen switch.
  ///
  /// The existing animation remains:
  ///
  /// - Fade
  /// - Small horizontal slide
  /// - easeOutCubic
  /// - easeInCubic
  ///
  /// Direct bottom navigation:
  ///
  ///     New screen enters from the right
  ///
  /// Back navigation:
  ///
  ///     Home enters from the left
  ///
  /// The direction is purely visual. It does NOT restrict which screen
  /// the user can navigate to.
  Widget _buildTabTransition() {
    final currentScreen = _tabs[_index];

    final Offset beginOffset;

    if (_isGoingBack) {
      // ----------------------------------------------------------------------
      // BACK ANIMATION
      //
      // Example:
      //
      // Finance → Back → Home
      //
      // Home enters gently from the left.
      // ----------------------------------------------------------------------

      beginOffset = const Offset(-0.035, 0);
    } else {
      // ----------------------------------------------------------------------
      // NORMAL BOTTOM-NAVIGATION ANIMATION
      //
      // The user can click ANY destination.
      //
      // Example:
      //
      // Stock → Finance
      // Finance → Palai
      // Palai → Home
      //
      // There is no navigation restriction.
      // ----------------------------------------------------------------------

      beginOffset = const Offset(0.035, 0);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),

      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,

      // Keep the existing layered transition behavior.
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

      // The key ensures the transition runs when the selected tab changes.
      child: KeyedSubtree(
        key: ValueKey(_index),
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
      // We handle the phone Back button ourselves.
      canPop: false,

      onPopInvokedWithResult: (
          didPop,
          result,
          ) async {
        // The system already handled the pop.
        if (didPop) {
          return;
        }

        final shouldExit = await _handleBack();

        // --------------------------------------------------------------------
        // HOME + BACK
        //
        // Exit the application.
        // --------------------------------------------------------------------

        if (shouldExit && mounted) {
          await SystemNavigator.pop();
        }
      },

      child: Scaffold(
        backgroundColor: AppColors.paleGreen,

        // --------------------------------------------------------------------
        // MAIN CONTENT
        // --------------------------------------------------------------------
        //
        // Existing animated transition remains here.
        // --------------------------------------------------------------------

        body: _buildTabTransition(),

        // --------------------------------------------------------------------
        // BOTTOM NAVIGATION
        // --------------------------------------------------------------------

        bottomNavigationBar: AppBottomNav(
          currentIndex: _index,

          onTap: (index) {
            // --------------------------------------------------------------
            // Profile
            // --------------------------------------------------------------

            if (index == 5) {
              _openProfile();
              return;
            }

            // --------------------------------------------------------------
            // Home / Palai / Stock / Finance
            // --------------------------------------------------------------

            _navigateToTab(index);
          },
        ),
      ),
    );
  }
}