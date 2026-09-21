import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_goat_health_record.dart';
import '../../../models/trading_goat_weight_entry.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../palai/fullscreen_image_viewer.dart';
import 'add_health_record_screen.dart';
import 'add_weight_entry_screen.dart';

/// Own Palai goat profile — same tabbed layout as the customer Palai
/// GoatProfileScreen, but:
///   • Purchase details get their own, much more detailed tab.
///   • No Monthly Reports / Final Report tabs (and no Payment / Checkout,
///     which only make sense for customer-owned goats).
class OwnPalaiGoatProfileScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  /// Tab to open on (e.g. from a reminder tap). Defaults to Overview.
  final int initialTabIndex;

  const OwnPalaiGoatProfileScreen({
    super.key,
    required this.farmId,
    required this.goat,
    this.initialTabIndex = 0,
  });

  @override
  State<OwnPalaiGoatProfileScreen> createState() =>
      _OwnPalaiGoatProfileScreenState();
}

class _OwnPalaiGoatProfileScreenState extends State<OwnPalaiGoatProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Future<TradingPurchase?>? _purchaseFuture;

  static const _tabs = [
    ('Overview', Icons.dashboard_outlined),
    ('Purchase', Icons.receipt_long_outlined),
    ('Photos', Icons.photo_library_outlined),
    ('Health', Icons.health_and_safety_outlined),
    ('Vaccination', Icons.vaccines_outlined),
    ('Hoof Cutting', Icons.content_cut_outlined),
    ('Hair Trimming', Icons.brush_outlined),
    ('Medicine', Icons.medication_outlined),
    ('Progress', Icons.trending_up),
  ];

  static const List<GoatHealthRecordType> _healthTypes = [
    GoatHealthRecordType.vaccination,
    GoatHealthRecordType.hoofCutting,
    GoatHealthRecordType.hairTrimming,
    GoatHealthRecordType.medicine,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    final purchaseId = widget.goat.purchaseId.trim();
    _purchaseFuture = purchaseId.isEmpty
        ? Future.value(null)
        : TradingService.instance.getPurchase(widget.farmId, purchaseId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(goat.id, style: AppTheme.heading(size: 16)),
      ),
      body: Column(
        children: [
          _buildHeaderCard(goat),
          Material(
            color: AppColors.paleGreen,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.stockTeal,
              unselectedLabelColor: AppColors.textGrey,
              indicatorColor: AppColors.stockTeal,
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
                _buildOverviewTab(goat),
                _buildPurchaseTab(goat),
                _PhotosTab(farmId: widget.farmId, goat: goat),
                _HealthSummaryTab(
                  farmId: widget.farmId,
                  goat: goat,
                  types: _healthTypes,
                  onOpenType: (i) => _tabController.animateTo(4 + i),
                ),
                for (final type in _healthTypes)
                  _HealthTypeTab(
                    farmId: widget.farmId,
                    goatId: goat.id,
                    type: type,
                    onLog: () => _openAddHealthRecord(type),
                  ),
                _ProgressTab(
                  farmId: widget.farmId,
                  goat: goat,
                  purchaseFuture: _purchaseFuture,
                  onLog: _openAddWeightEntry,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildHeaderCard(Goat goat) {
    final color = _healthColor(goat.healthStatus);
    final daysOwned = DateTime.now().difference(goat.purchaseDate).inDays;
    final hasPhoto = goat.photo != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: !hasPhoto
                ? null
                : () => Navigator.of(context).push(
              fastRoute(
                FullscreenImageViewer(
                  imageBytes: goat.photo!,
                  title: goat.id,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasPhoto
                  ? Image.memory(goat.photo!,
                  width: 64, height: 64, fit: BoxFit.cover)
                  : Container(
                width: 64,
                height: 64,
                color: AppColors.stockTeal.withOpacity(0.10),
                child: const Icon(GoatIcons.paw,
                    color: AppColors.stockTeal, size: 26),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        goat.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heading(size: 13.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _pill('Own Palai', AppColors.stockTeal),
                    const SizedBox(width: 4),
                    Flexible(
                      child: _pill(
                        goat.healthStatus.isEmpty ? 'Unknown' : goat.healthStatus,
                        color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _miniStat('Current', '${goat.weight.toStringAsFixed(1)} kg'),
                    _miniStat('Age', goat.age.isEmpty ? '—' : goat.age),
                    _miniStat('Days Owned', '$daysOwned'),
                    _miniStat('Bought',
                        DateFormat('d MMM').format(goat.purchaseDate)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.body(size: 9.5, color: color, weight: FontWeight.w600),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 9.5, color: AppColors.textGrey)),
        Text(value, style: AppTheme.heading(size: 11.5)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW TAB
  // ---------------------------------------------------------------------------

  Widget _buildOverviewTab(Goat goat) {
    final daysOwned = DateTime.now().difference(goat.purchaseDate).inDays;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _SectionCard(
          title: 'Basic Details',
          child: _kvColumn([
            ('Goat ID', goat.id),
            ('Breed', goat.breed),
            ('Color', goat.color),
            if (goat.gender.isNotEmpty) ('Gender', goat.gender),
            ('Age', goat.age),
            ('Height', goat.hasHeight ? goat.heightLabel : 'Not recorded'),
            if (goat.notes.trim().isNotEmpty) ('Notes', goat.notes),
          ]),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Current Condition',
          child: _kvColumn([
            ('Current Weight', '${goat.weight.toStringAsFixed(1)} kg'),
            ('Health Status',
            goat.healthStatus.isNotEmpty ? goat.healthStatus : 'Not recorded'),
            ('Purchased On', DateFormat('d MMM yyyy').format(goat.purchaseDate)),
            ('Days Owned', '$daysOwned days'),
            if (goat.movedToOwnPalaiAt != null)
              ('Moved to Own Palai',
              DateFormat('d MMM yyyy').format(goat.movedToOwnPalaiAt!)),
          ]),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Status',
          child: Row(
            children: [
              const Icon(Icons.circle, size: 10, color: AppColors.success),
              const SizedBox(width: 8),
              Text('Active in Own Palai', style: AppTheme.body(size: 12.5)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PURCHASE TAB (detailed)
  // ---------------------------------------------------------------------------

  Widget _buildPurchaseTab(Goat goat) {
    return FutureBuilder<TradingPurchase?>(
      future: _purchaseFuture,
      builder: (context, snapshot) {
        const pad = EdgeInsets.fromLTRB(14, 12, 14, 24);

        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView(
            padding: pad,
            children: const [
              _SectionCard(
                  title: 'Purchase Details', child: _SectionSkeleton(rows: 8)),
            ],
          );
        }

        if (snapshot.hasError) {
          return ListView(
            padding: pad,
            children: [
              _SectionCard(
                title: 'Purchase Details',
                child: _errorText(
                    'Could not load purchase details', snapshot.error!),
              ),
            ],
          );
        }

        final purchase = snapshot.data;
        final date = DateFormat('d MMM yyyy');

        if (purchase == null) {
          return ListView(
            padding: pad,
            children: [
              _SectionCard(
                title: 'Purchase Details',
                child: _kvColumn([
                  ('Purchase ID',
                  goat.purchaseId.isEmpty ? '—' : goat.purchaseId),
                  ('Purchase Date', date.format(goat.purchaseDate)),
                ]),
              ),
              const SizedBox(height: 12),
              _emptyMessage(Icons.info_outline,
                  'Full purchase record was not found for this goat.'),
            ],
          );
        }

        // Same costing engine the Trading screens use, so every figure here
        // matches what the purchase wizard / receiving screen showed.
        final c = purchase.costing;
        final received = c.hasArrival;
        final goatsBase = received ? c.survivingGoats : purchase.totalGoats;

        final purchasePerGoat = c.purchaseAmountPerGoat;
        final expensesPerGoat = goatsBase > 0
            ? PurchaseCosting.round2(c.totalExpenses / goatsBase)
            : 0.0;
        final mortalityShare = received && c.survivingGoats > 0
            ? PurchaseCosting.round2(c.mortalityLoss / c.survivingGoats)
            : 0.0;
        final costPerGoat = received
            ? c.costPerSurvivingGoat
            : (purchase.totalGoats > 0
            ? PurchaseCosting.round2(c.grandTotal / purchase.totalGoats)
            : 0.0);
        final atRate =
        PurchaseCosting.round2(goat.weight * purchase.pricePerKg);
        final daysSince =
            DateTime.now().difference(purchase.purchaseDate).inDays;

        return ListView(
          padding: pad,
          children: [
            // ---- This goat's cost -------------------------------------
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Purchase Price (this goat)',
                    value: _money(purchasePerGoat),
                    color: AppColors.tradingBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    label: received
                        ? 'Total Cost (this goat)'
                        : 'Est. Total Cost (this goat)',
                    value: _money(costPerGoat),
                    color: AppColors.stockTeal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Cost Breakdown (this goat)',
              child: Column(
                children: [
                  _kvColumn([
                    ('Purchase Price',
                    '${_money(purchasePerGoat)}  (avg of ${purchase.totalGoats} goats)'),
                    ('Expenses Share',
                    '${_money(expensesPerGoat)}  (split across $goatsBase goats)'),
                    if (mortalityShare > 0)
                      ('Mortality Share',
                      '${_money(mortalityShare)}  (${purchase.mortality} lost in transit)'),
                    ('Total Cost', _money(costPerGoat)),
                    ('Registered Weight',
                    '${goat.weight.toStringAsFixed(1)} kg'),
                    ('At Purchase Rate',
                    '${_money(atRate)}  (${goat.weight.toStringAsFixed(1)} kg × ₹${purchase.pricePerKg.toStringAsFixed(2)})'),
                  ]),
                  if (!received) ...[
                    const SizedBox(height: 8),
                    _emptyMessage(Icons.info_outline,
                        'Receiving is still pending, so this is an estimate '
                            '(grand total ÷ goats bought).'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- Purchase info ----------------------------------------
            _SectionCard(
              title: 'Purchase Info',
              child: _kvColumn([
                ('Purchase ID', purchase.id),
                ('Purchase Date', date.format(purchase.purchaseDate)),
                ('Days Since', '$daysSince days'),
                ('Payment Method', purchase.paymentMethod),
                if (purchase.remarks.trim().isNotEmpty)
                  ('Remarks', purchase.remarks.trim()),
              ]),
            ),
            const SizedBox(height: 12),

            // ---- Seller -----------------------------------------------
            _SectionCard(
              title: 'Seller Details',
              child: _kvColumn([
                ('Seller', purchase.sellerName),
                ('Mobile', purchase.mobile),
                ('Market', purchase.market),
                ('Vehicle No.', purchase.vehicleNumber),
              ]),
            ),
            const SizedBox(height: 12),

            // ---- Receiving --------------------------------------------
            _SectionCard(
              title: 'Receiving',
              child: _kvColumn([
                ('Status', received || purchase.isReceivingCompleted
                    ? 'Completed'
                    : 'Pending'),
                ('Received On',
                purchase.dateReceivedAtFarm == null
                    ? '—'
                    : date.format(purchase.dateReceivedAtFarm!)),
                ('Weight at Purchase',
                '${purchase.totalWeightAtPurchase.toStringAsFixed(1)} kg'),
                ('Weight After Arrival',
                received
                    ? '${c.weightAfterArrival.toStringAsFixed(1)} kg'
                    : '—'),
                ('Weight Loss',
                received
                    ? '${c.weightLoss.toStringAsFixed(1)} kg (${c.weightLossPercent.toStringAsFixed(2)}%)'
                    : '—'),
                ('Mortality',
                '${purchase.mortality} of ${purchase.totalGoats} goats'),
                ('Goats Registered',
                '${purchase.registeredCount} registered · ${purchase.pendingCount} pending'),
              ]),
            ),
            const SizedBox(height: 12),

            // ---- Expenses ---------------------------------------------
            _SectionCard(
              title: 'Purchase Expenses (whole purchase)',
              child: _kvColumn([
                ('Transport', _money(purchase.transportCost)),
                ('Loading', _money(purchase.loadingCharges)),
                ('Unloading', _money(purchase.unloadingCharges)),
                ('Other', _money(purchase.otherExpenses)),
                ('Total Expenses', _money(c.totalExpenses)),
              ]),
            ),
            const SizedBox(height: 12),

            // ---- Whole purchase ---------------------------------------
            _SectionCard(
              title: 'Whole Purchase (all ${purchase.totalGoats} goats)',
              child: _kvColumn([
                ('Total Weight',
                '${purchase.totalWeightAtPurchase.toStringAsFixed(1)} kg'),
                ('Rate', '₹${purchase.pricePerKg.toStringAsFixed(2)}/kg'),
                ('Purchase Amount', _money(c.purchaseAmount)),
                ('Total Expenses', _money(c.totalExpenses)),
                ('Grand Total', _money(c.grandTotal)),
                ('Effective Cost/kg',
                received
                    ? '₹${c.effectiveCostPerKg.toStringAsFixed(2)}/kg'
                    : '—'),
                ('Cost / Surviving Goat',
                received ? _money(c.costPerSurvivingGoat) : '—'),
              ]),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _openAddWeightEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(
        AddWeightEntryScreen(farmId: widget.farmId, goatId: widget.goat.id),
      ),
    );
    if (saved == true && mounted) _snack('Weight entry logged.');
  }

  Future<void> _openAddHealthRecord(GoatHealthRecordType type) async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(
        AddHealthRecordScreen(
          farmId: widget.farmId,
          goatId: widget.goat.id,
          type: type,
        ),
      ),
    );
    if (saved == true && mounted) _snack('${type.label} record logged.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================================
// SHARED HELPERS
// ============================================================================

final NumberFormat _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

String _money(double v) => _inr.format(v);

Color _healthColor(String status) {
  switch (status) {
    case 'Healthy':
      return AppColors.success;
    case 'Under Treatment':
      return AppColors.warning;
    default:
      return AppColors.error;
  }
}

IconData _healthIcon(GoatHealthRecordType type) {
  switch (type) {
    case GoatHealthRecordType.vaccination:
      return Icons.vaccines_outlined;
    case GoatHealthRecordType.hoofCutting:
      return Icons.content_cut_outlined;
    case GoatHealthRecordType.hairTrimming:
      return Icons.brush_outlined;
    case GoatHealthRecordType.medicine:
      return Icons.medication_outlined;
  }
}

Color _healthTypeColor(GoatHealthRecordType type) {
  switch (type) {
    case GoatHealthRecordType.vaccination:
      return AppColors.success;
    case GoatHealthRecordType.hoofCutting:
      return AppColors.warning;
    case GoatHealthRecordType.hairTrimming:
      return AppColors.info;
    case GoatHealthRecordType.medicine:
      return AppColors.error;
  }
}

Widget _kvColumn(List<(String, String)> pairs) {
  return Column(
    children: [
      for (final pair in pairs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(pair.$1,
                    style: AppTheme.body(size: 11.5, color: AppColors.textGrey)),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  pair.$2.isEmpty ? '—' : pair.$2,
                  style: AppTheme.body(size: 12, weight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

Widget _emptyMessage(IconData icon, String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    decoration: BoxDecoration(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppColors.textGrey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: AppTheme.body(size: 10.5, color: AppColors.textGrey)),
        ),
      ],
    ),
  );
}

Widget _errorText(String prefix, Object error) {
  return Text(
    '$prefix: ${FirestoreService.instance.describeError(error)}',
    style: AppTheme.body(size: 11, color: AppColors.error),
  );
}

Widget _logButton(Color color, VoidCallback onTap) {
  return TextButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.add, size: 14),
    label: const Text('Log'),
    style: TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

Widget _dueBadge(GoatHealthRecord? latest) {
  if (latest == null || latest.nextDueDate == null) {
    return const SizedBox.shrink();
  }
  final overdue = latest.isOverdue;
  final dueSoon = !overdue &&
      latest.isDueWithin(
        const Duration(days: kHealthRecordPendingWindowDays),
      );
  if (!overdue && !dueSoon) return const SizedBox.shrink();

  final color = overdue ? AppColors.error : AppColors.warning;
  return Container(
    margin: const EdgeInsets.only(right: 2),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      overdue ? 'Overdue' : 'Due soon',
      style: AppTheme.body(size: 8, color: color, weight: FontWeight.w700),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTheme.heading(size: 13))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTheme.body(size: 9.5, color: AppColors.textGrey)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(size: 14)
                .copyWith(color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PHOTOS TAB
// ============================================================================

class _PhotosTab extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const _PhotosTab({required this.farmId, required this.goat});

  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  late final Stream<List<GoatWeightEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = GoatService.instance.weightHistoryStream(
      farmId: widget.farmId,
      goatId: widget.goat.id,
    );
  }

  void _open(BuildContext context, dynamic bytes, String title) {
    Navigator.of(context).push(
      fastRoute(FullscreenImageViewer(imageBytes: bytes, title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;

    return StreamBuilder<List<GoatWeightEntry>>(
      stream: _stream,
      builder: (context, snapshot) {
        final entries = (snapshot.data ?? const <GoatWeightEntry>[])
            .where((e) => e.hasPhoto)
            .toList()
            .reversed
            .toList();

        final tiles = <(dynamic, String, String)>[
          if (goat.photo != null)
            (goat.photo, 'Profile', DateFormat('d MMM yyyy').format(goat.purchaseDate)),
          for (final e in entries)
            (
            e.photo,
            '${e.weight.toStringAsFixed(1)} kg',
            DateFormat('d MMM yyyy').format(e.date),
            ),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _SectionCard(
              title: 'Photos & Growth',
              child: snapshot.hasError
                  ? _errorText('Could not load photos', snapshot.error!)
                  : snapshot.connectionState == ConnectionState.waiting
                  ? const _SectionSkeleton(rows: 4)
                  : tiles.isEmpty
                  ? _emptyMessage(Icons.photo_outlined,
                  'No photos yet. Add one while logging a weight entry.')
                  : GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final t in tiles)
                    GestureDetector(
                      onTap: () => _open(context, t.$1, t.$3),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(t.$1,
                                fit: BoxFit.cover),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                const BorderRadius.vertical(
                                  bottom: Radius.circular(10),
                                ),
                              ),
                              child: Text(
                                '${t.$2} · ${t.$3}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// HEALTH SUMMARY TAB
// ============================================================================

class _HealthSummaryTab extends StatefulWidget {
  final String farmId;
  final Goat goat;
  final List<GoatHealthRecordType> types;
  final void Function(int index) onOpenType;

  const _HealthSummaryTab({
    required this.farmId,
    required this.goat,
    required this.types,
    required this.onOpenType,
  });

  @override
  State<_HealthSummaryTab> createState() => _HealthSummaryTabState();
}

class _HealthSummaryTabState extends State<_HealthSummaryTab> {
  late final Stream<List<GoatHealthRecord>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = GoatService.instance.healthRecordsStream(
      farmId: widget.farmId,
      goatId: widget.goat.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;
    final statusColor = _healthColor(goat.healthStatus);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _SectionCard(
          title: 'Current Health',
          child: Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  goat.healthStatus.isEmpty ? 'Not recorded' : goat.healthStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Care Overview',
          child: StreamBuilder<List<GoatHealthRecord>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _SectionSkeleton(rows: 4);
              }
              if (snapshot.hasError) {
                return _errorText('Could not load health records', snapshot.error!);
              }
              final records = snapshot.data ?? const <GoatHealthRecord>[];

              return Column(
                children: [
                  for (int i = 0; i < widget.types.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                    _summaryRow(
                      widget.types[i],
                      records.where((r) => r.type == widget.types[i]).toList(),
                          () => widget.onOpenType(i),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
      GoatHealthRecordType type,
      List<GoatHealthRecord> records,
      VoidCallback onTap,
      ) {
    final latest = records.isNotEmpty ? records.first : null;
    final color = _healthTypeColor(type);

    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_healthIcon(type), size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label, style: AppTheme.heading(size: 12)),
                Text(
                  latest == null
                      ? 'No records yet'
                      : 'Last: ${DateFormat('d MMM yyyy').format(latest.date)}'
                      '${latest.nextDueDate != null ? ' · Next: ${DateFormat('d MMM yyyy').format(latest.nextDueDate!)}' : ''}',
                  style: AppTheme.body(size: 10, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          _dueBadge(latest),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textGrey),
        ],
      ),
    );
  }
}

// ============================================================================
// PER-TYPE HEALTH TAB (Vaccination / Hoof / Hair / Medicine)
// ============================================================================

class _HealthTypeTab extends StatefulWidget {
  final String farmId;
  final String goatId;
  final GoatHealthRecordType type;
  final VoidCallback onLog;

  const _HealthTypeTab({
    required this.farmId,
    required this.goatId,
    required this.type,
    required this.onLog,
  });

  @override
  State<_HealthTypeTab> createState() => _HealthTypeTabState();
}

class _HealthTypeTabState extends State<_HealthTypeTab> {
  late final Stream<List<GoatHealthRecord>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = GoatService.instance.healthRecordsStream(
      farmId: widget.farmId,
      goatId: widget.goatId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final color = _healthTypeColor(type);
    final fmt = DateFormat('d MMM yyyy');

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _SectionCard(
          title: type.label,
          trailing: _logButton(color, widget.onLog),
          child: StreamBuilder<List<GoatHealthRecord>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _SectionSkeleton(rows: 4);
              }
              if (snapshot.hasError) {
                return _errorText('Could not load records', snapshot.error!);
              }

              final records = (snapshot.data ?? const <GoatHealthRecord>[])
                  .where((r) => r.type == type)
                  .toList();

              if (records.isEmpty) {
                return _emptyMessage(_healthIcon(type),
                    'No ${type.label.toLowerCase()} records yet. Tap Log to add one.');
              }

              final latest = records.first;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'Last Done',
                          value: fmt.format(latest.date),
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          label: 'Next Due',
                          value: latest.nextDueDate == null
                              ? '—'
                              : fmt.format(latest.nextDueDate!),
                          color: AppColors.tradingBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _dueBadge(latest)),
                  const SizedBox(height: 10),
                  Text('History',
                      style: AppTheme.body(
                          size: 10.5,
                          color: AppColors.textGrey,
                          weight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final r in records)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fmt.format(r.date) +
                                      (r.nextDueDate != null
                                          ? ' · Due: ${fmt.format(r.nextDueDate!)}'
                                          : ''),
                                  style: AppTheme.body(
                                      size: 11,
                                      color: AppColors.textDark,
                                      weight: FontWeight.w600),
                                ),
                                if (r.notes.trim().isNotEmpty)
                                  Text(r.notes.trim(),
                                      style: AppTheme.body(
                                          size: 10, color: AppColors.textGrey)),
                              ],
                            ),
                          ),
                        ],
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

// ============================================================================
// PROGRESS TAB
// ============================================================================

class _ProgressTab extends StatefulWidget {
  final String farmId;
  final Goat goat;
  final Future<TradingPurchase?>? purchaseFuture;
  final VoidCallback onLog;

  const _ProgressTab({
    required this.farmId,
    required this.goat,
    required this.purchaseFuture,
    required this.onLog,
  });

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  late final Stream<List<GoatWeightEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = GoatService.instance.weightHistoryStream(
      farmId: widget.farmId,
      goatId: widget.goat.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _SectionCard(
          title: 'Weight & Progress',
          trailing: _logButton(AppColors.stockTeal, widget.onLog),
          child: StreamBuilder<List<GoatWeightEntry>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _SectionSkeleton(rows: 4);
              }
              if (snapshot.hasError) {
                return _errorText('Could not load weight history', snapshot.error!);
              }

              final entries = snapshot.data ?? const <GoatWeightEntry>[];
              if (entries.isEmpty) {
                return _emptyMessage(Icons.monitor_weight_outlined,
                    'No weight entries yet. Log the first weight check.');
              }

              final current = entries.last;
              final previous =
              entries.length > 1 ? entries[entries.length - 2] : null;
              final gain =
              previous == null ? null : current.weight - previous.weight;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'Current',
                          value: '${current.weight.toStringAsFixed(1)} kg',
                          color: AppColors.stockTeal,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _StatTile(
                          label: 'Previous',
                          value: previous == null
                              ? '—'
                              : '${previous.weight.toStringAsFixed(1)} kg',
                          color: AppColors.tradingBlue,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _StatTile(
                          label: 'Gain',
                          value: gain == null
                              ? '—'
                              : '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg',
                          color: gain == null
                              ? AppColors.textGrey
                              : gain >= 0
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Weight History',
                      style: AppTheme.body(
                          size: 10.5,
                          color: AppColors.textGrey,
                          weight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  for (int i = entries.length - 1; i >= 0; i--)
                    _weightTile(
                      entries[i],
                      i > 0 ? entries[i - 1] : null,
                      isLast: i == 0,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _weightTile(
      GoatWeightEntry entry,
      GoatWeightEntry? previous, {
        required bool isLast,
      }) {
    final gain = previous == null ? null : entry.weight - previous.weight;
    final dotColor = gain == null
        ? AppColors.textGrey
        : gain >= 0
        ? AppColors.success
        : AppColors.error;
    final dateText = DateFormat('d MMM yyyy').format(entry.date);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.2, color: AppColors.divider),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  if (entry.hasPhoto) ...[
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        fastRoute(
                          FullscreenImageViewer(
                            imageBytes: entry.photo!,
                            title: dateText,
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.memory(entry.photo!,
                            width: 34, height: 34, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateText,
                            style: AppTheme.body(
                                size: 10, color: AppColors.textGrey)),
                        if (entry.notes.trim().isNotEmpty)
                          Text(entry.notes,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(
                                  size: 9.5, color: AppColors.textGrey)),
                      ],
                    ),
                  ),
                  Text('${entry.weight.toStringAsFixed(1)} kg',
                      style: AppTheme.heading(size: 11.5)),
                  if (gain != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                      style: AppTheme.body(
                          size: 9.5, color: dotColor, weight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SECTION SKELETON
// ============================================================================

class _SectionSkeleton extends StatefulWidget {
  final int rows;

  const _SectionSkeleton({this.rows = 4});

  @override
  State<_SectionSkeleton> createState() => _SectionSkeletonState();
}

class _SectionSkeletonState extends State<_SectionSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _box(double width, double height) {
    return Opacity(
      opacity: 0.35 + (_controller.value * 0.35),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Column(
        children: [
          for (int i = 0; i < widget.rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  _box(85, 10),
                  const SizedBox(width: 12),
                  Expanded(child: _box(double.infinity, 10)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}