import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import 'customer_goat_hair_screen.dart';
import 'customer_goat_hoof_screen.dart';
import 'customer_goat_medicine_screen.dart';
import 'customer_goat_vaccination_screen.dart';
import 'goat_checkout_tab.dart';
import 'goat_edit_details_screen.dart';
import 'goat_final_report_tab.dart';
import 'goat_health_tab.dart';
import 'goat_monthly_reports_tab.dart';
import 'goat_payment_tab.dart';
import 'goat_photos_growth_tab.dart';
import 'goat_weight_progress_tab.dart';

/// The new, unified Goat Profile screen.
///
///   GOAT LIST
///      │
///      └── Tap Goat
///             │
///             ▼
///        GOAT PROFILE
///             │
///             ├── 1. Overview
///             ├── 2. Photos & Growth
///             ├── 3. Health
///             ├── 4. Vaccination
///             ├── 5. Hoof Cutting
///             ├── 6. Hair Trimming
///             ├── 7. Medicine
///             ├── 8. Weight & Progress
///             ├── 9. Monthly Report
///             ├── 10. Payment
///             ├── 11. Final Report
///             └── 12. Checkout
///
/// This REPLACES the old goat action-sheet (Health & Care / Monthly
/// Report / Final Report & Check-Out as three disconnected
/// destinations) with one screen where every tab is scoped to this one
/// goat — the same principle already used by the per-goat billing math
/// elsewhere in the app: everything has an obvious owner, this goat.
///
/// STATUS: every tab is now backed by real data — Overview, Photos &
/// Growth, Health, Vaccination, Hoof Cutting, Hair Trimming, Medicine,
/// Weight & Progress, Monthly Reports (with per-goat date-range report
/// generation), Payment, Final Report, and Checkout.
class GoatProfileScreen extends StatefulWidget {
  final String farmId;
  final PalaiGoat goat;

  /// Which tab to open on. Defaults to Overview (0). Used when this
  /// screen is opened from a reminder tap (e.g. a due vaccination or
  /// hoof-cutting notification) so the owner lands directly on the
  /// relevant tab instead of Overview.
  final int initialTabIndex;

  const GoatProfileScreen({
    super.key,
    required this.farmId,
    required this.goat,
    this.initialTabIndex = 0,
  });

  @override
  State<GoatProfileScreen> createState() => _GoatProfileScreenState();
}

class _GoatProfileScreenState extends State<GoatProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _customerName = '';

  /// Mutable local copy of the goat, seeded from [widget.goat]. Kept
  /// separate so editing details (via [GoatEditDetailsScreen]) can
  /// refresh the header/tabs in place without needing to pop this whole
  /// screen and re-navigate from the goat list.
  late PalaiGoat _goat;

  static const _tabs = [
    ('Overview', Icons.dashboard_outlined),
    ('Photos', Icons.photo_library_outlined),
    ('Health', Icons.health_and_safety_outlined),
    ('Vaccination', Icons.vaccines_outlined),
    ('Hoof Cutting', Icons.content_cut_outlined),
    ('Hair Trimming', Icons.brush_outlined),
    ('Medicine', Icons.medication_outlined),
    ('Progress', Icons.trending_up),
    ('Reports', Icons.description_outlined),
    ('Payment', Icons.payments_outlined),
    ('Final Report', Icons.summarize_outlined),
    ('Checkout', Icons.logout_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _goat = widget.goat;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    _loadCustomerName();
  }

  Future<void> _loadCustomerName() async {
    final customer = await FirestoreService.instance.getCustomer(widget.farmId, _goat.customerId);
    if (!mounted || customer == null) return;
    setState(() => _customerName = customer.name);
  }

  Future<void> _openEditDetails() async {
    final updated = await Navigator.of(context).push<PalaiGoat>(
      MaterialPageRoute<PalaiGoat>(
        builder: (_) => GoatEditDetailsScreen(
          farmId: widget.farmId,
          customerId: _goat.customerId,
          goat: _goat,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _goat = updated);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _healthColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;
      case 'Under Observation':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _goatDisplayId(PalaiGoat goat) {
    if (goat.goatCode.trim().isNotEmpty) return goat.goatCode;
    if (goat.tagNumber.trim().isNotEmpty) return goat.tagNumber;
    return goat.id;
  }

  @override
  Widget build(BuildContext context) {
    final goat = _goat;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(
          goat.name.trim().isNotEmpty ? goat.name : _goatDisplayId(goat),
          style: AppTheme.heading(size: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Edit Goat Details',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _openEditDetails,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeaderCard(goat),
          Material(
            color: AppColors.paleGreen,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primaryGreen,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primaryGreen,
              labelStyle: AppTheme.body(size: 11.5, weight: FontWeight.w600),
              unselectedLabelStyle: AppTheme.body(size: 11.5),
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final tab in _tabs)
                  Tab(
                    height: 40,
                    icon: Icon(tab.$2, size: 16),
                    text: tab.$1,
                    iconMargin: const EdgeInsets.only(bottom: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _GoatOverviewTab(goat: goat),
                GoatPhotosGrowthTab(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                GoatHealthTab(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                CustomerGoatVaccinationScreen(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                CustomerGoatHoofScreen(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                CustomerGoatHairScreen(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                CustomerGoatMedicineScreen(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                GoatWeightProgressTab(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                GoatMonthlyReportsTab(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  customerName: _customerName,
                  goat: goat,
                ),
                GoatPaymentTab(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  goat: goat,
                ),
                GoatFinalReportTab(
                  farmId: widget.farmId,
                  customerId: goat.customerId,
                  customerName: _customerName,
                  goat: goat,
                ),
                GoatCheckoutTab(goat: goat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // HEADER — large photo + quick summary, shared across every tab
  // ------------------------------------------------------------------

  Widget _buildHeaderCard(PalaiGoat goat) {
    final color = _healthColor(goat.healthStatus);
    final currentWeight = goat.currentWeight ?? goat.weightAtCheckIn;
    final gain = currentWeight - goat.weightAtCheckIn;
    final arrivalDate = goat.farmArrivalDate ?? goat.checkInDate;
    final daysAtFarm = DateTime.now().difference(arrivalDate).inDays;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: goat.beforeImage != null
                ? Image.memory(goat.beforeImage!, width: 64, height: 64, fit: BoxFit.cover)
                : Container(
              width: 64,
              height: 64,
              color: AppColors.lightGreen,
              child: const Icon(Icons.pets, color: AppColors.primaryGreen, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_goatDisplayId(goat), style: AppTheme.heading(size: 13.5)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        goat.isCheckedOut ? 'Checked Out' : (goat.healthStatus.isNotEmpty ? goat.healthStatus : 'Active'),
                        style: AppTheme.body(size: 9.5, color: color, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _miniStat('Current', '${currentWeight.toStringAsFixed(1)} kg'),
                    _miniStat('Gain', '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg'),
                    _miniStat('Days', '$daysAtFarm'),
                    _miniStat('Arrived', DateFormat('d MMM').format(arrivalDate)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 9.5, color: AppColors.textMuted)),
        Text(value, style: AppTheme.heading(size: 11.5)),
      ],
    );
  }
}

// ============================================================================
// OVERVIEW TAB
// ============================================================================

class _GoatOverviewTab extends StatelessWidget {
  final PalaiGoat goat;

  const _GoatOverviewTab({required this.goat});

  @override
  Widget build(BuildContext context) {
    final arrivalDate = goat.farmArrivalDate ?? goat.checkInDate;
    final currentWeight = goat.currentWeight ?? goat.weightAtCheckIn;
    final gain = currentWeight - goat.weightAtCheckIn;
    final daysAtFarm = DateTime.now().difference(arrivalDate).inDays;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _sectionCard(
          title: 'Basic Details',
          child: _kvColumn([
            ('Goat ID', goat.goatCode.trim().isNotEmpty ? goat.goatCode : goat.tagNumber),
            ('Name', goat.name.trim().isNotEmpty ? goat.name : '—'),
            ('Breed', goat.breed.isNotEmpty ? goat.breed : '—'),
            ('Gender', goat.gender.isNotEmpty ? goat.gender : '—'),
            ('Arrival Date', DateFormat('d MMM yyyy').format(arrivalDate)),
            ('Monthly Package', goat.monthlyPackage.isNotEmpty ? goat.monthlyPackage : '—'),
            ('Palai Price', goat.pricing > 0 ? '₹${goat.pricing.toStringAsFixed(0)}/month' : '—'),
          ]),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Current Condition',
          child: _kvColumn([
            ('Arrival Weight', '${goat.weightAtCheckIn.toStringAsFixed(1)} kg'),
            ('Current Weight', '${currentWeight.toStringAsFixed(1)} kg'),
            ('Weight Gain', '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg'),
            ('Days at Farm', '$daysAtFarm days'),
            ('Health Status', goat.healthStatus.isNotEmpty ? goat.healthStatus : 'Not recorded'),
          ]),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Status',
          child: Row(
            children: [
              Icon(
                goat.isCheckedOut ? Icons.check_circle_outline : Icons.circle,
                size: goat.isCheckedOut ? 18 : 10,
                color: goat.isCheckedOut ? AppColors.textMuted : AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                goat.isCheckedOut ? 'Checked out of Palai' : 'Active in Palai',
                style: AppTheme.body(size: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.heading(size: 13)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _kvColumn(List<(String, String)> pairs) {
    return Column(
      children: [
        for (final pair in pairs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(pair.$1, style: AppTheme.body(size: 11.5, color: AppColors.textMuted)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(pair.$2, style: AppTheme.body(size: 12, weight: FontWeight.w500)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}