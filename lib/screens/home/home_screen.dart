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
import 'widgets/home_widgets.dart';
import '../palai/customer_palai/customer_goat_registration_screen.dart';
import '../stocks/stock_screen.dart';
import '../stocks/add_feed_stock_screen.dart';
import '../profile/profile_screen.dart';
import 'notification_screen.dart';
import '../palai/goat_list_screen.dart';
import '../palai/receive_payment_screen.dart';
import 'income_detail_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final ownerName = _farm?.ownerName.isNotEmpty == true
        ? _farm!.ownerName
        : FirebaseAuth.instance.currentUser?.displayName ?? 'Farmer';
    final farmName = _farm?.farmName.isNotEmpty == true ? _farm!.farmName : 'My Goat Farms';

    // Still resolving the farm/partner lookup — show a real spinner
    // instead of the empty placeholder boxes.
    if (_loadingFarm) {
      return const Scaffold(
        backgroundColor: AppColors.paleGreen,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
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
                const SizedBox(height: 20),
                Text('Alhamdulillah for everything', style: AppTheme.body(size: 13, weight: FontWeight.w500)),
                const SizedBox(height: 14),
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

  Widget _buildSearchBar() {
    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search, color: AppColors.textGrey, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Goat ID, Customer, Batch, Invoice...',
                hintStyle: AppTheme.body(size: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ),
          Icon(Icons.tune, color: AppColors.primaryGreen, size: 20),
        ],
      ),
    );
  }

  Widget _buildStatGridLoading() {
    return Row(
      children: const [
        Expanded(child: SizedBox(height: 90)),
        SizedBox(width: 12),
        Expanded(child: SizedBox(height: 90)),
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
                          .push(fastRoute(const IncomeDetailScreen())),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          QuickAction(
            icon: Icons.add,
            label: 'Add Goat',
            color: AppColors.primaryGreen,
            onTap: _openAddGoat,
          ),
          QuickAction(
            icon: Icons.payments_outlined,
            label: 'Receive\nPayment',
            color: AppColors.success,
            onTap: _openReceivePayment,
          ),
          QuickAction(
            icon: Icons.remove,
            label: 'Add\nExpense',
            color: AppColors.error,
            onTap: () => _comingSoon('Add Expense'),
          ),
          QuickAction(
            icon: Icons.grass_outlined,
            label: 'Add Feed\nStock',
            color: AppColors.info,
            onTap: () => Navigator.of(context).push(fastRoute(const AddFeedStockScreen())),
          ),
        ],
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
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
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
          onPressed: () => Navigator.of(context).push(fastRoute(const NotificationScreen())),
          icon: const Icon(Icons.notifications_none, color: AppColors.textDark),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).push(fastRoute(const ProfileScreen())).then((_) {
            _popupPending = true;
            _maybeShowCompletionPopup();
          }),
          child: CircleAvatar(
            backgroundColor: AppColors.lightGreen,
            backgroundImage: _farm?.profileImage != null ? MemoryImage(_farm!.profileImage!) : null,
            child: _farm?.profileImage == null
                ? const Icon(Icons.person, color: AppColors.primaryGreen)
                : null,
          ),
        ),
      ],
    );
  }
}