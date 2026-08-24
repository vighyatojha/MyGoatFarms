import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

import '../customers/customer_management_screen.dart';
import '../palai/customer_selection_screen.dart';
import '../home/income_detail_screen.dart';
import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/goat_count_builder.dart';
import '../home/widgets/home_widgets.dart';
import 'add_customer_screen.dart';
import 'customer_palai/customer_goat_registration_screen.dart';
import 'goat_list_screen.dart';
import 'own_farm/own_farm_palai_content.dart';
import '../monthly_report_screen.dart';
import '../home/notification_screen.dart';

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

  PalaiType _palaiType = PalaiType.customer;

  Stream<List<PalaiCustomer>>? _customersStream;
  Stream<double>? _incomeStream;
  Stream<double>? _pendingStream;
  Stream<List<ActivityLog>>? _activitiesStream;

  @override
  void initState() {
    super.initState();

    FirestoreService.instance.currentFarmId().then((id) {
      if (!mounted) {
        return;
      }

      setState(() {
        _farmId = id;

        if (id != null) {
          _customersStream =
              FirestoreService.instance.customersStream(id);

          _incomeStream =
              FirestoreService.instance.todaysIncomeStream(id);

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
      SnackBar(
        content: Text('$feature coming soon'),
        backgroundColor: AppColors.darkGreen,
      ),
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
  // The existing customer stream is used to obtain the customers already
  // belonging to this farm. After the user selects one, we redirect directly
  // to the existing CustomerGoatRegistrationScreen.
  //
  // No new registration screen is created.
  // ===========================================================================

  Future<void> _openGoatRegistration() async {
    if (_customersStream == null) {
      _showMessage(
        'Customers are still loading. Please try again.',
        isError: true,
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: const BoxConstraints(
              maxHeight: 520,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),

                // Small drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 16),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_add_alt,
                          color: AppColors.primaryGreen,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Customer',
                              style: AppTheme.heading(
                                size: 17,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Choose a customer to register a goat',
                              style: AppTheme.body(
                                size: 12,
                                color: AppColors.textGrey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                        },
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                ),

                // Customer list
                Flexible(
                  child: StreamBuilder<List<PalaiCustomer>>(
                    stream: _customersStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const SizedBox(
                          height: 180,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return SizedBox(
                          height: 180,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Unable to load customers.',
                                style: AppTheme.body(
                                  size: 13,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final customers = snapshot.data ?? [];

                      if (customers.isEmpty) {
                        return SizedBox(
                          height: 180,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.people_outline,
                                  size: 42,
                                  color: AppColors.textGrey,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No active customers found.',
                                  style: AppTheme.body(
                                    size: 13,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          20,
                        ),
                        itemCount: customers.length,
                        separatorBuilder: (_, __) {
                          return const SizedBox(height: 8);
                        },
                        itemBuilder: (context, index) {
                          final customer = customers[index];

                          return Material(
                            color: AppColors.lightGreen
                                .withOpacity(0.35),
                            borderRadius:
                            BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius:
                              BorderRadius.circular(14),
                              onTap: () {
                                // Close popup first
                                Navigator.of(sheetContext).pop();

                                // Then open existing registration screen
                                Navigator.of(context).push(
                                  fastRoute(
                                    CustomerGoatRegistrationScreen(
                                      customerId: customer.id,
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding:
                                const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 21,
                                      backgroundColor:
                                      AppColors.primaryGreen,
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customer.name,
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: AppTheme.body(
                                              size: 14,
                                              weight:
                                              FontWeight.w600,
                                              color:
                                              AppColors.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Active customer',
                                            style: AppTheme.body(
                                              size: 11,
                                              color:
                                              AppColors.textGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                        BorderRadius.circular(
                                          9,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 13,
                                        color:
                                        AppColors.primaryGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        )
            : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeInDown(
                duration:
                const Duration(milliseconds: 180),
                child: _buildHeader(),
              ),

              const SizedBox(height: 14),

              _buildPalaiTypeToggle(),

              const SizedBox(height: 18),

              if (_palaiType == PalaiType.customer) ...[
                _buildDashboard(),

                const SizedBox(height: 24),

                Text(
                  'Quick Actions',
                  style: AppTheme.heading(size: 16),
                ),

                const SizedBox(height: 12),

                _buildQuickActions(_farmId!),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Activities',
                      style:
                      AppTheme.heading(size: 16),
                    ),
                    GestureDetector(
                      onTap: () => _comingSoon(
                        'Full activity list',
                      ),
                      child: Text(
                        'View All',
                        style: AppTheme.body(
                          size: 13,
                          color:
                          AppColors.darkGreen,
                          weight:
                          FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _buildActivities(),

                const SizedBox(height: 20),

                _buildGenerateReportBanner(
                  _farmId!,
                ),
              ] else
                OwnFarmPalaiContent(
                  farmId: _farmId!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PALAI TYPE TOGGLE
  // ===========================================================================

  Widget _buildPalaiTypeToggle() {
    Widget segment(
        String label,
        PalaiType type,
        ) {
      final selected = _palaiType == type;

      return Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() {
              _palaiType = type;
            });
          },
          child: AnimatedContainer(
            duration:
            const Duration(milliseconds: 150),
            padding:
            const EdgeInsets.symmetric(
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryGreen
                  : Colors.transparent,
              borderRadius:
              BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTheme.body(
                size: 12,
                color: selected
                    ? Colors.white
                    : AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          segment(
            'Customer Palai',
            PalaiType.customer,
          ),
          segment(
            'Own Farm Palai',
            PalaiType.ownFarm,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.lightGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.home_work,
            color: AppColors.primaryGreen,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Palai',
                style:
                AppTheme.heading(size: 17),
              ),
              Text(
                'Goat Boarding & Care',
                style: AppTheme.body(size: 12),
              ),
            ],
          ),
        ),

        IconButton(
          onPressed: () {
            Navigator.of(context).push(
              fastRoute(
                const NotificationScreen(),
              ),
            );
          },
          icon: const Icon(
            Icons.notifications_none,
            color: AppColors.textDark,
          ),
        ),

        const SizedBox(width: 6),

        ElevatedButton.icon(
          onPressed: _palaiType == PalaiType.customer
              ? _openGoatRegistration
              : null,
          icon: const Icon(
            Icons.add,
            size: 16,
          ),
          label: const Text('Add Goat'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade400,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // DASHBOARD
  // ===========================================================================

  Widget _buildDashboard() {
    return FadeInUp(
      delay:
      const Duration(milliseconds: 38),
      duration:
      const Duration(milliseconds: 220),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GoatCountBuilder(
                  farmId: _farmId!,
                  builder:
                      (context, count) {
                    return StatCard(
                      icon: Icons.pets,
                      label:
                      'Total Goats in Palai',
                      value: count != null
                          ? '$count'
                          : '—',
                      color:
                      AppColors.primaryGreen,
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          fastRoute(
                            const GoatListScreen(),
                          ),
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
                    return StatCard(
                      icon: Icons.people_outline,
                      label: 'Total Customers',
                      value: snap.hasData
                          ? '${snap.data!.length}'
                          : '—',
                      color: AppColors.info,

                      // Open Customer Management Screen
                      onTap: () {
                        Navigator.of(context).push(
                          fastRoute(
                            const CustomerManagementScreen(),
                          ),
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
                child:
                StreamBuilder<double>(
                  stream:
                  FirestoreService
                      .instance
                      .monthlyPaymentsReceivedStream(
                    _farmId!,
                  ),
                  builder:
                      (context, snap) {
                    return StatCard(
                      icon:
                      Icons.receipt_long_outlined,
                      label:
                      'Payments',
                      value: snap.hasData
                          ? '₹${snap.data!.toStringAsFixed(0)}'
                          : '—',
                      color:
                      AppColors.warning,
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          fastRoute(
                            const IncomeDetailScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child:
                StreamBuilder<double>(
                  stream:
                  _pendingStream,
                  builder:
                      (context, snap) {
                    return StatCard(
                      icon:
                      Icons.credit_card_outlined,
                      label:
                      'Pending Payments',
                      value: snap.hasData
                          ? '₹${snap.data!.toStringAsFixed(0)}'
                          : '—',
                      color:
                      AppColors.error,
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

  // ===========================================================================
  // QUICK ACTIONS
  // ===========================================================================

  Widget _buildQuickActions(
      String farmId,
      ) {
    return FadeInUp(
      delay:
      const Duration(milliseconds: 62),
      duration:
      const Duration(milliseconds: 220),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics:
        const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
        children: [
          ModuleTile(
            icon:
            Icons.person_add_alt,
            label:
            'Add Customer',
            sub:
            'New',
            color:
            AppColors.primaryGreen,
            onTap: () {
              Navigator.of(context)
                  .push(
                fastRoute(
                  const AddCustomerScreen(),
                ),
              );
            },
          ),

          ModuleTile(
            icon:
            Icons.local_shipping_outlined,
            label:
            'Delivery',
            sub:
            'Return',
            color:
            AppColors.info,
            onTap: () {
              _comingSoon(
                'Delivery / Return',
              );
            },
          ),

          ModuleTile(
            icon:
            Icons.summarize_outlined,
            label:
            'Report',
            sub:
            'Monthly',
            color:
            AppColors.stockTeal,
            onTap: () {
              Navigator.of(context)
                  .push(
                fastRoute(
                  MonthlyReportScreen(
                    farmId: farmId,
                  ),
                ),
              );
            },
          ),

          ModuleTile(
            icon:
            Icons.more_horiz,
            label:
            'More',
            sub:
            '',
            color:
            AppColors.textGrey,
            onTap: () {
              _comingSoon(
                'More options',
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ACTIVITIES
  // ===========================================================================

  Widget _buildActivities() {
    return FadeInUp(
      delay:
      const Duration(milliseconds: 88),
      duration:
      const Duration(milliseconds: 220),
      child:
      StreamBuilder<List<ActivityLog>>(
        stream:
        _activitiesStream,
        builder:
            (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding:
              EdgeInsets.symmetric(
                vertical: 16,
              ),
              child: Center(
                child:
                CircularProgressIndicator(
                  color:
                  AppColors.primaryGreen,
                ),
              ),
            );
          }

          final activities =
          snap.data!;

          if (activities.isEmpty) {
            return Text(
              'No Palai activity yet.',
              style:
              AppTheme.body(size: 12),
            );
          }

          return Column(
            children:
            activities
                .map(
                  (activity) =>
                  ActivityTile(
                    activity:
                    activity,
                  ),
            )
                .toList(),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // MONTHLY REPORT
  // ===========================================================================

  Widget _buildGenerateReportBanner(
      String farmId,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(16),
      decoration:
      BoxDecoration(
        color:
        AppColors.darkGreen,
        borderRadius:
        BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            color: Colors.white,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate Monthly Report',
                  style:
                  AppTheme.heading(
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Send goat report with photos and weight updates to customer',
                  style:
                  AppTheme.body(
                    size: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          ElevatedButton(
            onPressed: () {
              Navigator.of(context)
                  .push(
                fastRoute(
                  MonthlyReportScreen(
                    farmId: farmId,
                  ),
                ),
              );
            },
            style:
            ElevatedButton.styleFrom(
              backgroundColor:
              Colors.white,
              foregroundColor:
              AppColors.darkGreen,
              shape:
              RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Generate',
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}