import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../home/widgets/home_widgets.dart';
import 'add_customer_screen.dart';
import 'check_in_screen.dart';
import 'goat_list_screen.dart';
import 'health_records_screen.dart';
import 'billing_screen.dart';

/// Palai (Goat Boarding & Care) module dashboard.
///
/// Manages customers, goat check-in/check-out, health records, monthly
/// billing, payment collection and (eventually) automatic report generation
/// — matching the "Palai (Goat Boarding & Care)" spec.
class PalaiScreen extends StatefulWidget {
  const PalaiScreen({super.key});

  @override
  State<PalaiScreen> createState() => _PalaiScreenState();
}

class _PalaiScreenState extends State<PalaiScreen> {
  String? _farmId;

  // Created once, when the farm id resolves, and reused on every rebuild.
  // Calling these FirestoreService methods directly inside `build()` would
  // hand each StreamBuilder a brand-new stream instance on every rebuild
  // (e.g. during the FadeIn animations below), forcing it to drop its
  // subscription and flash back to the loading state — that's what caused
  // the dashboard cards to keep "reloading".
  Stream<List<PalaiGoat>>? _goatsStream;
  Stream<List<PalaiCustomer>>? _customersStream;
  Stream<double>? _incomeStream;
  Stream<double>? _pendingStream;
  Stream<List<ActivityLog>>? _activitiesStream;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (!mounted) return;
      setState(() {
        _farmId = id;
        if (id != null) {
          _goatsStream = FirestoreService.instance.allActiveGoatsStream(id);
          _customersStream = FirestoreService.instance.customersStream(id);
          _incomeStream = FirestoreService.instance.todaysIncomeStream(id);
          _pendingStream = FirestoreService.instance.totalPendingPaymentsStream(id);
          _activitiesStream = FirestoreService.instance.activitiesStream(id, module: 'palai', limit: 6);
        }
      });
    });
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), backgroundColor: AppColors.darkGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeInDown(duration: const Duration(milliseconds: 180), child: _buildHeader()),
              const SizedBox(height: 18),
              _buildDashboard(),
              const SizedBox(height: 24),
              Text('Quick Actions', style: AppTheme.heading(size: 16)),
              const SizedBox(height: 12),
              _buildQuickActions(_farmId!),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activities', style: AppTheme.heading(size: 16)),
                  GestureDetector(
                    onTap: () => _comingSoon('Full activity list'),
                    child: Text('View All', style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildActivities(),
              const SizedBox(height: 20),
              _buildGenerateReportBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
          child: const Icon(Icons.home_work, color: AppColors.primaryGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Palai', style: AppTheme.heading(size: 17)),
              Text('Goat Boarding & Care', style: AppTheme.body(size: 12)),
            ],
          ),
        ),
        IconButton(onPressed: () => _comingSoon('Notifications'), icon: const Icon(Icons.notifications_none, color: AppColors.textDark)),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).push(fastRoute(const CheckInGoatScreen())),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Goat'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    return FadeInUp(
      delay: const Duration(milliseconds: 38),
      duration: const Duration(milliseconds: 220),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StreamBuilder<List<PalaiGoat>>(
                  stream: _goatsStream,
                  builder: (context, snap) => StatCard(
                    icon: Icons.pets,
                    label: 'Total Goats in Palai',
                    value: snap.hasData ? '${snap.data!.length}' : '—',
                    color: AppColors.primaryGreen,
                    // Tapping the card takes you straight to the full
                    // goat list, same as the "Check-Out" quick action.
                    onTap: () => Navigator.of(context).push(fastRoute(const GoatListScreen())),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<List<PalaiCustomer>>(
                  stream: _customersStream,
                  builder: (context, snap) => StatCard(
                    icon: Icons.people_outline,
                    label: 'Total Customers',
                    value: snap.hasData ? '${snap.data!.length}' : '—',
                    color: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StreamBuilder<double>(
                  stream: _incomeStream,
                  builder: (context, snap) => StatCard(
                    icon: Icons.currency_rupee,
                    label: 'Monthly Income',
                    value: snap.hasData ? '₹${snap.data!.toStringAsFixed(0)}' : '—',
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<double>(
                  stream: _pendingStream,
                  builder: (context, snap) => StatCard(
                    icon: Icons.credit_card_outlined,
                    label: 'Pending Payments',
                    value: snap.hasData ? '₹${snap.data!.toStringAsFixed(0)}' : '—',
                    color: AppColors.error,
                  ),
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
      delay: const Duration(milliseconds: 62),
      duration: const Duration(milliseconds: 220),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
        children: [
          ModuleTile(
            icon: Icons.person_add_alt,
            label: 'Add Customer',
            sub: 'New',
            color: AppColors.primaryGreen,
            onTap: () => Navigator.of(context).push(fastRoute(const AddCustomerScreen())),
          ),
          ModuleTile(
            icon: Icons.login,
            label: 'Check-In',
            sub: 'Goat',
            color: AppColors.success,
            onTap: () => Navigator.of(context).push(fastRoute(const CheckInGoatScreen())),
          ),
          ModuleTile(
            icon: Icons.logout,
            label: 'Check-Out',
            sub: 'Goat',
            color: AppColors.error,
            // Check-Out now starts from the goat list — each goat carries
            // its own "Before Palai" photo, so the goat must be picked
            // there before opening its Check-Out page.
            onTap: () => Navigator.of(context).push(fastRoute(const GoatListScreen())),
          ),
          ModuleTile(
            icon: Icons.favorite_border,
            label: 'Health',
            sub: 'Records',
            color: AppColors.breedingPurple,
            onTap: () => Navigator.of(context).push(fastRoute(const HealthRecordsScreen())),
          ),
          ModuleTile(
            icon: Icons.receipt_long_outlined,
            label: 'Billing',
            sub: 'Generate',
            color: AppColors.warning,
            onTap: () => Navigator.of(context).push(fastRoute(const BillingScreen())),
          ),
          ModuleTile(
            icon: Icons.local_shipping_outlined,
            label: 'Delivery',
            sub: 'Return',
            color: AppColors.info,
            onTap: () => _comingSoon('Delivery / Return'),
          ),
          ModuleTile(
            icon: Icons.summarize_outlined,
            label: 'Report',
            sub: 'Monthly',
            color: AppColors.stockTeal,
            onTap: () => _comingSoon('Monthly report generator'),
          ),
          ModuleTile(
            icon: Icons.more_horiz,
            label: 'More',
            sub: '',
            color: AppColors.textGrey,
            onTap: () => _comingSoon('More options'),
          ),
        ],
      ),
    );
  }

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
              child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
            );
          }
          final activities = snap.data!;
          if (activities.isEmpty) {
            return Text('No Palai activity yet.', style: AppTheme.body(size: 12));
          }
          return Column(children: activities.map((a) => ActivityTile(activity: a)).toList());
        },
      ),
    );
  }

  Widget _buildGenerateReportBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.darkGreen, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Generate Monthly Report & Bill', style: AppTheme.heading(size: 13, color: Colors.white)),
                Text('Send goat report with photos, weight & bill to customer',
                    style: AppTheme.body(size: 11, color: Colors.white70)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _comingSoon('Report generator'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.darkGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Generate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}