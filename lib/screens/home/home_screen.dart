import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:animate_do/animate_do.dart';

import '../../app_theme.dart';
import '../../models/farm_model.dart';
import '../../models/activity_model.dart';
import '../../models/partner_model.dart';
import '../../models/palai_models.dart';
import '../../models/stock_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/profile_completion_dialog.dart';
import '../../widgets/customer_selection_sheet.dart';
import '../finance/finance_overview_screen.dart';
import '../finance/add_edit_expense_screen.dart';
import '../finance/customer_ledger_screen.dart';
import 'widgets/home_widgets.dart';
import '../palai/customer_palai/customer_goat_registration_screen.dart';
import '../stocks/stock_screen.dart';
import '../stocks/add_feed_stock_screen.dart';
import '../profile/profile_screen.dart';
import 'notification_screen.dart';
import 'health_records_screen.dart';
import '../palai/goat_list_screen.dart';
import '../palai/receive_payment_screen.dart';
import '../../widgets/goat_count_builder.dart';

/// Home / dashboard screen. Quick, at-a-glance view of the whole farm —
/// live totals, the four main modules, quick actions and recent activity.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FarmModel? _farm;
  bool _loadingFarm = true;
  String? _farmId;
  List<PartnerModel> _partners = [];
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<FarmModel?>? _farmSub;
  StreamSubscription<List<PartnerModel>>? _partnerSub;

  /// Shown once per app session while incomplete; re-armed after the
  /// person backs out of Profile without finishing it, so it keeps
  /// nudging them without stacking multiple popups on top of each other.
  bool _popupPending = false;

  @override
  void initState() {
    super.initState();
    _loadFarmData();
  }

  @override
  void dispose() {
    _farmSub?.cancel();
    _partnerSub?.cancel();
    super.dispose();
  }

  Future<void> _loadFarmData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Resolves the farm for BOTH farm owners and partners — a partner's
    // uid never matches a farm's own `authUid`, so looking that up alone
    // (the old behaviour) left partners stuck with `_farm`/`_farmId`
    // permanently null and the dashboard permanently empty.
    final farm = await FirestoreService.instance.getFarmForUser(uid);
    if (!mounted) return;
    setState(() {
      _farm = farm;
      _farmId = farm?.id;
      _loadingFarm = false;
    });

    if (farm == null) return;

    _popupPending = true; // arm the popup for this fresh load

    _farmSub?.cancel();
    _farmSub = FirestoreService.instance.farmDocStream(farm.id).listen((f) {
      if (f == null || !mounted) return;
      setState(() => _farm = f);
      _maybeShowCompletionPopup();
    });

    _partnerSub?.cancel();
    _partnerSub = FirestoreService.instance.partnersStream(farm.id).listen((partners) {
      if (!mounted) return;
      setState(() => _partners = partners);
      _maybeShowCompletionPopup();
    });
  }

  void _maybeShowCompletionPopup() {
    final farm = _farm;
    if (farm == null || !_popupPending) return;
    final percent = farm.completionPercent(partnerCount: _partners.length);
    if (percent >= 100) {
      _popupPending = false;
      return;
    }
    _popupPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showProfileCompletionDialog(
        context,
        percent: percent,
        onCompleteNow: () {
          Navigator.of(context).push(fastRoute(const ProfileScreen())).then((_) {
            _popupPending = true;
            _maybeShowCompletionPopup();
          });
        },
        onLater: () {
          // Will nudge again next time the app is opened while incomplete.
        },
      );
    });
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature module coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.darkGreen,
      ),
    );
  }

  /// Time-of-day greeting, based on the device's local time/timezone
  /// (`DateTime.now()` is always local, never UTC) — so a farmer in a
  /// different timezone always sees a greeting that matches their own
  /// clock, not the server's.
  ///
  ///   05:00–11:59  → Good Morning
  ///   12:00–16:59  → Good Afternoon
  ///   17:00–20:59  → Good Evening
  ///   21:00–04:59  → Good Night
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    if (hour >= 17 && hour < 21) return 'Good Evening';
    return 'Good Night';
  }

  // ===========================================================================
  // QUICK ACTION: ADD GOAT
  // ===========================================================================
  //
  // Same pattern as PalaiScreen's "Add Goat" button: the person first
  // picks which customer the goat belongs to (via the shared, timeout
  // /retry-safe `showCustomerSelectionSheet`), then we open the same
  // register-goat screen the Palai screen uses, passing that customer's id.
  // ===========================================================================

  Future<void> _openAddGoat() async {
    final farmId = _farmId;
    if (farmId == null) {
      _showMessage('Farm information is still loading. Please try again.', isError: true);
      return;
    }

    final PalaiCustomer? customer = await showCustomerSelectionSheet(
      context,
      farmId: farmId,
      title: 'Select Customer',
      subtitle: 'Choose a customer to register a goat',
    );

    if (customer == null || !mounted) return;

    Navigator.of(context).push(
      fastRoute(CustomerGoatRegistrationScreen(customerId: customer.id)),
    );
  }

  // ===========================================================================
  // QUICK ACTION: RECEIVE PAYMENT
  // ===========================================================================
  //
  // Same idea: pick the customer first via the shared selection sheet,
  // then open the payment sheet pre-filled with that customer's id.
  // ===========================================================================

  Future<void> _openReceivePayment() async {
    final farmId = _farmId;
    if (farmId == null) {
      _showMessage('Farm information is still loading. Please try again.', isError: true);
      return;
    }

    final PalaiCustomer? customer = await showCustomerSelectionSheet(
      context,
      farmId: farmId,
      title: 'Select Customer',
      subtitle: 'Choose a customer to receive a payment from',
    );

    if (customer == null || !mounted) return;

    Navigator.of(context).push(
      fastRoute(ReceivePaymentScreen(presetCustomer: customer)),
    );
  }

  // ===========================================================================
  // QUICK ACTION: ADD EXPENSE
  // ===========================================================================
  //
  // Opens the Finance module's expense form directly. On success it pops
  // back here with `true`, which just triggers a friendly confirmation —
  // the expense form itself already shows its own snackbar before
  // popping, so this is only an extra nudge, not the source of truth.
  // ===========================================================================

  Future<void> _openAddExpense() async {
    final result = await Navigator.of(context).push<bool>(
      fastRoute(const AddEditExpenseScreen()),
    );
    if (result == true) {
      _showMessage('Expense added');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = _farm?.ownerName.isNotEmpty == true
        ? _farm!.ownerName
        : FirebaseAuth.instance.currentUser?.displayName ?? 'Farmer';
    final farmName = _farm?.farmName.isNotEmpty == true ? _farm!.farmName : 'My Goat Farms';

    // Still resolving the farm/partner lookup — show the same skeleton
    // shape the loaded dashboard will have, instead of a bare spinner on
    // an empty screen (and instead of a second, different loading style
    // than the one used further down for the stat grid/activities).
    if (_loadingFarm) {
      return const Scaffold(
        backgroundColor: AppColors.paleGreen,
        body: SafeArea(child: _HomeSkeleton()),
      );
    }

    // Resolution finished but this account isn't linked to any farm as
    // either an owner or a partner — surface that instead of silently
    // leaving the dashboard permanently empty (which looked like it was
    // "stuck loading" with nothing ever appearing).
    if (_farm == null) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.link_off, size: 48, color: AppColors.textGrey),
                  const SizedBox(height: 16),
                  Text(
                    'This account isn\'t linked to any farm yet',
                    style: AppTheme.heading(size: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you were added as a partner, ask the farm owner to '
                        'double-check your invite, or pull down to refresh.',
                    style: AppTheme.body(size: 13, color: AppColors.textGrey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _loadingFarm = true);
                      _loadFarmData();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                    child: const Text('Try again', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                  duration: const Duration(milliseconds: 225),
                  child: _buildHeader(farmName, ownerName),
                ),
                const SizedBox(height: 18),
                _buildSearchBar(),
                const SizedBox(height: 16),
                if (_farmId != null) _buildStatGrid(_farmId!) else _buildStatGridLoading(),
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
    );
  }

  /// Search bar styled to match the rest of the app's card language
  /// (white card, soft shadow, icon-in-a-tinted-circle) — same visual
  /// vocabulary the Finance Overview screen uses for its stat tiles and
  /// nav chips, instead of a plain bordered text field. No trailing
  /// filter icon — search here is a single free-text field, not a
  /// filtered query, so a "tune" icon that did nothing was misleading.
  Widget _buildSearchBar() {
    return Container(
      decoration: AppTheme.card(radius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded, color: AppColors.primaryGreen, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Goat ID, Customer, Batch, Invoice...',
                hintStyle: AppTheme.body(size: 12.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  /// Shimmer skeleton cards for the stat grid, shown while `_farmId` is
  /// still resolving — same shape as the loaded grid so nothing jumps
  /// around once real data arrives, and no separate circular spinner.
  Widget _buildStatGridLoading() {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatGrid(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 38),
      duration: const Duration(milliseconds: 220),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GoatCountBuilder(
                  farmId: farmId,
                  builder: (context, count) => StatCard(
                    icon: Icons.pets,
                    label: 'Total Goats',
                    value: count != null ? '$count' : '—',
                    color: AppColors.primaryGreen,
                    onTap: () => Navigator.of(context)
                        .push(fastRoute(const GoatListScreen())),
                  ),
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
                      label: "Income & Payments",
                      value: snap.hasData ? '₹${value.toStringAsFixed(0)}' : '—',
                      color: AppColors.warning,
                      onTap: () => Navigator.of(context)
                          .push(fastRoute(const FinanceOverviewScreen())),
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
                      onTap: () => Navigator.of(context)
                          .push(fastRoute(const CustomerLedgerScreen())),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<List<StockItem>>(
                  stream: FirestoreService.instance.stockItemsStream(farmId, type: StockType.feed),
                  builder: (context, snap) {
                    final totalKg = (snap.data ?? [])
                        .fold<double>(0, (sum, item) => sum + item.quantity);
                    return StatCard(
                      icon: Icons.grass_outlined,
                      label: 'Feed in Stock',
                      value: snap.hasData ? '${totalKg.toStringAsFixed(0)} kg' : '—',
                      color: AppColors.stockTeal,
                      onTap: () => Navigator.of(context)
                          .push(fastRoute(const StockScreen())),
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
      delay: const Duration(milliseconds: 88),
      duration: const Duration(milliseconds: 220),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            QuickAction(
              icon: Icons.add,
              label: 'Add Goat',
              color: AppColors.primaryGreen,
              onTap: _openAddGoat,
            ),
            const SizedBox(width: 18),
            QuickAction(
              icon: Icons.payments_outlined,
              label: 'Receive\nPayment',
              color: AppColors.success,
              onTap: _openReceivePayment,
            ),
            const SizedBox(width: 18),
            QuickAction(
              icon: Icons.remove,
              label: 'Add\nExpense',
              color: AppColors.error,
              onTap: _openAddExpense,
            ),
            const SizedBox(width: 18),
            QuickAction(
              icon: Icons.grass_outlined,
              label: 'Add Feed\nStock',
              color: AppColors.info,
              onTap: () => Navigator.of(context).push(fastRoute(const AddFeedStockScreen())),
            ),
            const SizedBox(width: 18),
            QuickAction(
              icon: Icons.health_and_safety_outlined,
              label: 'Health\nRecords',
              color: AppColors.warning,
              onTap: () => Navigator.of(context).push(fastRoute(const HealthRecordsScreen())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivities(String farmId) {
    return FadeInUp(
      delay: const Duration(milliseconds: 112),
      duration: const Duration(milliseconds: 220),
      child: StreamBuilder<List<ActivityLog>>(
        stream: FirestoreService.instance.activitiesStream(farmId, limit: 5),
        builder: (context, snap) {
          if (!snap.hasData) {
            // Skeleton tiles matching ActivityTile's shape, instead of
            // a circular spinner — consistent with every other loading
            // state on this screen.
            return const Column(
              children: [
                _SkeletonBox(height: 62, radius: 14),
                SizedBox(height: 10),
                _SkeletonBox(height: 62, radius: 14),
                SizedBox(height: 10),
                _SkeletonBox(height: 62, radius: 14),
              ],
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

  /// Header: profile picture (opens Profile, same as before) leads on
  /// the left where the generic paw-print logo used to sit — every
  /// farm already has its own branding via `_buildQuickActions`/the
  /// stat cards, so a decorative paw icon here didn't add anything a
  /// person's own photo doesn't already give them faster recognition
  /// of "this is MY account". Farm name + a time-of-day greeting sit
  /// next to it, and the notification bell anchors the far right edge.
  Widget _buildHeader(String farmName, String ownerName) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(fastRoute(const ProfileScreen())).then((_) {
            _popupPending = true;
            _maybeShowCompletionPopup();
          }),
          child: CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.lightGreen,
            backgroundImage: _farm?.profileImage != null ? MemoryImage(_farm!.profileImage!) : null,
            child: _farm?.profileImage == null
                ? const Icon(Icons.person, color: AppColors.primaryGreen)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(farmName, style: AppTheme.heading(size: 16), overflow: TextOverflow.ellipsis),
              Text('${_greeting()}, $ownerName 👋', style: AppTheme.body(size: 12), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.of(context).push(fastRoute(const NotificationScreen())),
          icon: _farmId == null
              ? const Icon(Icons.notifications_none, color: AppColors.textDark)
              : StreamBuilder<bool>(
            stream: FirestoreService.instance.hasUnreadNotificationsStream(_farmId!),
            builder: (context, snap) {
              final hasUnread = snap.data ?? false;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none, color: AppColors.textDark),
                  if (hasUnread)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.paleGreen, width: 1.4),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Full-dashboard skeleton shown while the farm/partner lookup resolves
/// — mirrors the loaded screen's layout (header / search bar / stat
/// grid / quick actions / activities) so there's no visual "jump" once
/// real content swaps in, and no separate circular-spinner loading
/// style competing with the shimmer skeletons used elsewhere on this
/// screen.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Row(
          children: [
            _SkeletonBox(height: 46, width: 46, radius: 23),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(height: 14, width: 120, radius: 6),
                  SizedBox(height: 6),
                  _SkeletonBox(height: 11, width: 160, radius: 6),
                ],
              ),
            ),
            SizedBox(width: 8),
            _SkeletonBox(height: 28, width: 28, radius: 14),
          ],
        ),
        SizedBox(height: 18),
        _SkeletonBox(height: 52, radius: 16),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: _SkeletonBox(height: 90, radius: 18)),
          ],
        ),
        SizedBox(height: 24),
        _SkeletonBox(height: 16, width: 110, radius: 6),
        SizedBox(height: 12),
        Row(
          children: [
            _SkeletonBox(height: 50, width: 50, radius: 25),
            SizedBox(width: 18),
            _SkeletonBox(height: 50, width: 50, radius: 25),
            SizedBox(width: 18),
            _SkeletonBox(height: 50, width: 50, radius: 25),
            SizedBox(width: 18),
            _SkeletonBox(height: 50, width: 50, radius: 25),
          ],
        ),
        SizedBox(height: 24),
        _SkeletonBox(height: 16, width: 140, radius: 6),
        SizedBox(height: 12),
        _SkeletonBox(height: 62, radius: 14),
        SizedBox(height: 10),
        _SkeletonBox(height: 62, radius: 14),
        SizedBox(height: 10),
        _SkeletonBox(height: 62, radius: 14),
      ],
    );
  }
}

/// One shimmering placeholder block — the single building block every
/// loading state on this screen is made of (header, search bar, stat
/// grid, quick actions, activities), so there's exactly one loading
/// visual language on this screen instead of skeletons in some places
/// and a spinner in others.
class _SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const _SkeletonBox({required this.height, this.width, required this.radius});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Lightweight shimmer sweep used by [_SkeletonBox].
class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              colors: [
                AppColors.lightGreen.withOpacity(0.5),
                Colors.white,
                AppColors.lightGreen.withOpacity(0.5),
              ],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}