import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:mygoatfarms/screens/finance/finance_overview_screen.dart';

import '../customers/customer_management_screen.dart';
import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/goat_count_builder.dart';
import '../../widgets/customer_selection_sheet.dart';
import '../home/widgets/home_widgets.dart';
import '../finance/customer_ledger_screen.dart';
import 'add_customer_screen.dart';
import 'customer_palai/customer_goat_registration_screen.dart';
import 'goat_list_screen.dart';
import 'own_farm/own_farm_palai_content.dart';
import '../../widgets/farm_not_linked_state.dart';

/// Which kind of Palai this screen is showing.
enum PalaiType {
  customer,
  ownFarm,
}

/// Palai module dashboard.
///
/// Customer Palai:
/// - Customer management
/// - Goat registration
/// - Goat check-in/check-out
/// - Health records
/// - Monthly billing
/// - Payments
///
/// Own Farm Palai:
/// - Farm-owned goat lifecycle
/// - Growth
/// - Health
/// - Breeding
/// - Expenses
class PalaiScreen extends StatefulWidget {
  const PalaiScreen({super.key});

  @override
  State<PalaiScreen> createState() => _PalaiScreenState();
}

class _PalaiScreenState extends State<PalaiScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  PalaiType _palaiType = PalaiType.customer;

  Stream<List<PalaiCustomer>>? _customersStream;
  Stream<double>? _pendingStream;
  Stream<List<ActivityLog>>? _activitiesStream;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  void _loadFarm() {
    FirestoreService.instance.currentFarmId().then((id) {
      if (!mounted) {
        return;
      }

      setState(() {
        _farmId = id;
        _loadingFarm = false;

        if (id != null) {
          _customersStream =
              FirestoreService.instance.customersStream(id);
          _pendingStream =
              FirestoreService.instance.totalPendingPaymentsStream(id);

          _activitiesStream =
              FirestoreService.instance.activitiesStream(
                id,
                module: 'palai',
                limit: 6,
              );
        }
      });
    });
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  void _showMessage(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? AppColors.error
            : AppColors.darkGreen,
      ),
    );
  }

  // ===========================================================================
  // ADD GOAT
  // ===========================================================================
  //
  // CustomerGoatRegistrationScreen requires a customerId.
  //
  // PalaiScreen itself does not represent one particular customer, so we
  // cannot use `customer.id` directly here.
  //
  // The person first picks a customer from `showCustomerSelectionSheet`
  // (a shared, timeout/retry-safe bottom sheet — see
  // widgets/customer_selection_sheet.dart), then we redirect straight to
  // the existing CustomerGoatRegistrationScreen with that customer's id.
  //
  // NOTE: this used to be an inline modal bound to `_customersStream`, a
  // stream field only ever assigned once during `initState()`'s async
  // callback. If that listener ever stalled for any reason, the sheet's
  // StreamBuilder had no way out of `ConnectionState.waiting` and looked
  // like it was "loading infinitely." `showCustomerSelectionSheet` fixes
  // this: it starts a brand-new fetch when the sheet opens (or on Retry)
  // and applies an explicit timeout, so the sheet always resolves to
  // data, an error, or a timeout — never an indefinite spinner.
  // ===========================================================================

  Future<void> _openGoatRegistration() async {
    final farmId = _farmId;

    if (farmId == null) {
      _showMessage(
        'Farm information is still loading. Please try again.',
        isError: true,
      );
      return;
    }

    final customer = await showCustomerSelectionSheet(
      context,
      farmId: farmId,
      title: 'Select Customer',
      subtitle: 'Choose a customer to register a goat',
    );

    if (customer == null || !mounted) {
      return;
    }

    Navigator.of(context).push(
      fastRoute(
        CustomerGoatRegistrationScreen(
          customerId: customer.id,
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  Widget _buildNotLinkedState() {
    return FarmNotLinkedState(
      buttonColor: AppColors.primaryGreen,
      onRetry: () {
        setState(() => _loadingFarm = true);
        _loadFarm();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _loadingFarm
            ? const _PalaiLoadingState()
            : _farmId == null
            ? _buildNotLinkedState()
            : RefreshIndicator(
          color: AppColors.primaryGreen,
          backgroundColor: Colors.white,
          onRefresh: () async {
            setState(() => _loadingFarm = true);
            _loadFarm();
            await Future<void>.delayed(
              const Duration(milliseconds: 350),
            );
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeInDown(
                  duration: const Duration(milliseconds: 220),
                  child: _buildHeader(),
                ),
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 25),
                  duration: const Duration(milliseconds: 220),
                  child: _buildPalaiTypeToggle(),
                ),
                const SizedBox(height: 18),
                if (_palaiType == PalaiType.customer) ...[
                  _buildDashboard(),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    'Quick Actions',
                    'Manage your Palai operations',
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActions(),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    'Recent Activities',
                    'Latest Palai updates',
                    actionLabel: 'View All',
                    onAction: () =>
                        _comingSoon('Full activity list'),
                  ),
                  const SizedBox(height: 12),
                  _buildActivities(),
                ] else
                  OwnFarmPalaiContent(
                    farmId: _farmId!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      String title,
      String subtitle, {
        String? actionLabel,
        VoidCallback? onAction,
      }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.heading(size: 17),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: AppTheme.body(
                  size: 11.5,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: AppTheme.body(
                size: 12.5,
                color: AppColors.darkGreen,
                weight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // PALAI TYPE TOGGLE
  // ===========================================================================

  Widget _buildPalaiTypeToggle() {
    Widget segment(String label, PalaiType type, IconData icon) {
      final selected = _palaiType == type;

      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_palaiType == type) return;
            setState(() => _palaiType = type);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                BoxShadow(
                  color: AppColors.primaryGreen.withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected
                      ? AppColors.primaryGreen
                      : AppColors.textGrey,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 12,
                      color: selected
                          ? AppColors.darkGreen
                          : AppColors.textGrey,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          segment(
            'Customer Palai',
            PalaiType.customer,
            Icons.people_alt_outlined,
          ),
          const SizedBox(width: 4),
          segment(
            'Own Farm',
            PalaiType.ownFarm,
            Icons.home_work_outlined,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: AppTheme.card(radius: 20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.home_work_rounded,
              color: AppColors.primaryGreen,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Palai',
                  style: AppTheme.heading(size: 19),
                ),
                const SizedBox(height: 3),
                Text(
                  'Goat Boarding & Care',
                  style: AppTheme.body(
                    size: 11.5,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          if (_palaiType == PalaiType.customer)
            ElevatedButton.icon(
              onPressed: _openGoatRegistration,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Add Goat'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.home_work_outlined,
                color: AppColors.darkGreen,
                size: 19,
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DASHBOARD
  // ===========================================================================

  Widget _buildDashboard() {
    return FadeInUp(
      delay: const Duration(milliseconds: 38),
      duration: const Duration(milliseconds: 220),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GoatCountBuilder(
                  farmId: _farmId!,
                  builder: (context, count) {
                    return _buildDashboardStat(
                      icon: Icons.pets_rounded,
                      label: 'Total Goats',
                      value: count != null ? '$count' : '—',
                      color: AppColors.primaryGreen,
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(const GoatListScreen()),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<List<PalaiCustomer>>(
                  stream: _customersStream,
                  builder: (context, snap) {
                    return _buildDashboardStat(
                      icon: Icons.people_alt_outlined,
                      label: 'Customers',
                      value: snap.hasData ? '${snap.data!.length}' : '—',
                      color: AppColors.info,
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(const CustomerManagementScreen()),
                        );
                      },
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
                  stream: FirestoreService.instance
                      .monthlyPaymentsReceivedStream(_farmId!),
                  builder: (context, snap) {
                    return _buildDashboardStat(
                      icon: Icons.currency_rupee_rounded,
                      label: 'Payments',
                      value: snap.hasData
                          ? '₹${snap.data!.toStringAsFixed(0)}'
                          : '—',
                      color: AppColors.warning,
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(const FinanceOverviewScreen()),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<double>(
                  stream: _pendingStream,
                  builder: (context, snap) {
                    return _buildDashboardStat(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Pending',
                      value: snap.hasData
                          ? '₹${snap.data!.toStringAsFixed(0)}'
                          : '—',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(const CustomerLedgerScreen()),
                        );
                      },
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

  Widget _buildDashboardStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 98),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withOpacity(0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: color,
                    ),
                  ),
                  const Expanded(child: SizedBox.shrink()),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: AppColors.textGrey.withOpacity(0.65),
                  ),
                ],
              ),
              // NOTE: `Spacer()` needs a bounded parent height, but this
              // Column sits inside a Row -> Expanded, whose cross axis
              // (height) is loose/unbounded by default. That caused a
              // layout exception here which cascaded up and blanked the
              // whole screen. Fixed height gaps below instead.
              const SizedBox(height: 18),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(
                  size: 18,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 10.5,
                  color: AppColors.textGrey,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // QUICK ACTIONS
  // ===========================================================================

  Widget _buildQuickActions() {
    return FadeInUp(
      delay: const Duration(milliseconds: 62),
      duration: const Duration(milliseconds: 220),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.card(radius: 18),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.15,
          children: [
            _buildQuickActionTile(
              icon: Icons.person_add_alt_rounded,
              label: 'Add Customer',
              subtitle: 'Create new customer',
              color: AppColors.primaryGreen,
              onTap: () {
                Navigator.of(context).push(
                  fastRoute(const AddCustomerScreen()),
                );
              },
            ),
            _buildQuickActionTile(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              subtitle: 'More options',
              color: AppColors.textGrey,
              onTap: () => _comingSoon('More options'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: AppColors.paleGreen,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withOpacity(0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 11.5,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 9.5,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ACTIVITIES
  // ===========================================================================

  Widget _buildActivities() {
    return FadeInUp(
      delay: const Duration(milliseconds: 88),
      duration: const Duration(milliseconds: 220),
      child: StreamBuilder<List<ActivityLog>>(
        stream: _activitiesStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              ),
            );
          }

          final activities = snap.data!;

          if (activities.isEmpty) {
            return Text(
              'No Palai activity yet.',
              style: AppTheme.body(size: 12),
            );
          }

          return Container(
            decoration: AppTheme.card(radius: 18),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: activities
                  .map(
                    (activity) => ActivityTile(
                  activity: activity,
                ),
              )
                  .toList(),
            ),
          );
        },
      ),
    );
  }

}

// ===========================================================================
// PALAI LOADING STATE
// ===========================================================================

class _PalaiLoadingState extends StatelessWidget {
  const _PalaiLoadingState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        children: [
          Container(
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _SkeletonCard()),
              const SizedBox(width: 12),
              Expanded(child: _SkeletonCard()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _SkeletonCard()),
              const SizedBox(width: 12),
              Expanded(child: _SkeletonCard()),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 125,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}