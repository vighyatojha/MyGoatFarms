import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/health_reminder_settings_model.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_goat_health_record.dart';
import '../../../models/trading_goat_weight_entry.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/health_reminder_scheduler.dart';
import '../../../services/image_service.dart';
import '../../../services/sales_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/reminder_cadence_selector.dart';
import '../../../widgets/reminder_date_selector.dart';
import '../../palai/fullscreen_image_viewer.dart';
import '../goat_stock/complete_wait_for_delivery_screen.dart';
import '../goat_stock/goat_stock_detail_screen.dart';
import '../sale_receipt_screen.dart';

/// Own Palai goat profile — same tabbed layout as the customer Palai
/// GoatProfileScreen, but:
///   • Purchase details get their own, much more detailed tab.
///   • No Monthly Reports / Final Report tabs (and no Payment / Checkout,
///     which only make sense for customer-owned goats).
///
/// STOCK PROFILE — a goat that is still Available stock (see
/// [Goat.isAvailable]) opens the same screen in a slimmer form: it has no
/// owner and nothing to track beyond its care, so it only has the Photos
/// and health tabs (Health, Vaccination, Hoof Cutting, Hair Trimming,
/// Medicine). Like an Own Palai goat it follows the farm's Health Reminder
/// Settings — its dates are armed from them when the profile opens (see
/// [FirestoreService.syncOwnPalaiFarmReminders]) and raise notifications
/// when due. The [tabOverview] / [tabPurchase] / [tabProgress] indexes are
/// simply not shown there, so a deep link to one of them opens on Photos.
///
/// WAIT ON DELIVERY PROFILE — a goat that has been sold on Wait for
/// Delivery (see [Goat.isWaitOnDelivery]) is still on the farm until the
/// customer picks it up, so the farm keeps looking after it. It opens this
/// same screen with every tab, so weight (with a photo) and health records
/// (Vaccination, Hoof Cutting, Hair Trimming, Medicine) are logged exactly
/// like an Own Palai goat. It differs in three small ways: the header and
/// Overview say "Wait on Delivery" instead of "Own Palai", the Overview
/// gains a Sale card (customer, price, advance), and a Complete Delivery
/// button sits at the bottom, which opens [CompleteWaitForDeliveryScreen].
class OwnPalaiGoatProfileScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  /// Tab to open on (e.g. from a reminder tap), as one of the `tab…`
  /// constants below. Defaults to Overview (Photos on a stock profile,
  /// which has no Overview).
  final int initialTabIndex;

  /// Opens the Progress tab with its "Log Weight Entry" form already
  /// expanded — used by Goat Stock's "Log weigh-in" shortcut. Has no
  /// effect on a stock profile, which has no Progress tab.
  final bool openWeightLog;

  const OwnPalaiGoatProfileScreen({
    super.key,
    required this.farmId,
    required this.goat,
    this.initialTabIndex = 0,
    this.openWeightLog = false,
  });

  // -------------------------------------------------------------------------
  // TAB INDEXES
  //
  // Public so other screens (Goat Stock's weigh-in shortcut, Notifications,
  // Health Records) can deep-link straight into a tab without hard-coding
  // magic numbers. Keep in sync with `_tabs` in the state class below.
  // -------------------------------------------------------------------------
  static const int tabOverview = 0;
  static const int tabPurchase = 1;
  static const int tabPhotos = 2;
  static const int tabHealth = 3;
  static const int tabVaccination = 4;
  static const int tabHoofCutting = 5;
  static const int tabHairTrimming = 6;
  static const int tabMedicine = 7;
  static const int tabProgress = 8; // Weight & Progress

  /// Maps a health record type key OR a notification `type` (e.g.
  /// `'vaccination'`, `'hoofCutting_due'`, `'hairTrimming_overdue'`,
  /// `'medicine_logged'`) to the tab that shows it. Anything unrecognised
  /// lands on the general Health tab.
  static int tabForRecordType(String type) {
    if (type.startsWith('vaccination')) return tabVaccination;
    if (type.startsWith('hoofCutting')) return tabHoofCutting;
    if (type.startsWith('hairTrimming')) return tabHairTrimming;
    if (type.startsWith('medicine')) return tabMedicine;
    return tabHealth;
  }

  @override
  State<OwnPalaiGoatProfileScreen> createState() =>
      _OwnPalaiGoatProfileScreenState();
}

class _OwnPalaiGoatProfileScreenState extends State<OwnPalaiGoatProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Future<TradingPurchase?>? _purchaseFuture;

  /// Available stock goat: Photos + health tabs only (see class doc).
  bool get _stock => widget.goat.isAvailable;

  /// Sold on Wait for Delivery and not yet picked up (see class doc).
  bool get _waiting => widget.goat.isWaitOnDelivery;

  /// The open sale this goat is waiting on — read once, for the Overview
  /// Sale card. Null for every goat that is not waiting on delivery.
  Future<Sale?>? _saleFuture;

  /// The `OwnPalaiGoatProfileScreen.tab…` indexes that are shown.
  late final List<int> _visibleTabs = _stock
      ? const [
    OwnPalaiGoatProfileScreen.tabPhotos,
    OwnPalaiGoatProfileScreen.tabHealth,
    OwnPalaiGoatProfileScreen.tabVaccination,
    OwnPalaiGoatProfileScreen.tabHoofCutting,
    OwnPalaiGoatProfileScreen.tabHairTrimming,
    OwnPalaiGoatProfileScreen.tabMedicine,
  ]
      : List<int>.generate(_tabs.length, (i) => i);

  /// Position of a `tab…` index in the tab bar (0 when it is not shown).
  int _positionOf(int tab) {
    final position = _visibleTabs.indexOf(tab);

    return position < 0 ? 0 : position;
  }

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
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: _positionOf(widget.initialTabIndex),
    );
    final purchaseId = widget.goat.purchaseId.trim();
    _purchaseFuture = (_stock || purchaseId.isEmpty)
        ? Future.value(null)
        : TradingService.instance.getPurchase(widget.farmId, purchaseId);

    final saleId = (widget.goat.saleId ?? '').trim();
    _saleFuture = (_waiting && saleId.isNotEmpty)
        ? SalesService.instance.getSale(widget.farmId, saleId)
        : Future<Sale?>.value(null);

    // Apply the farm's Health Reminder Settings to this goat (Vaccination /
    // Hoof Cutting / Hair Trimming dates). This is what fixes a goat that
    // was already in Own Palai before its schedule existed, or whose farm
    // date changed since it last synced. The tabs below listen to the
    // goat's records live, so the dates simply appear once this writes.
    // Forced: opening the profile is exactly when it must be up to date.
    unawaited(
      HealthReminderScheduler.instance.syncOwnPalaiFarmReminders(
        widget.farmId,
        goatId: widget.goat.id,
        force: true,
      ),
    );
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

    // The Complete Delivery bar is hidden while the keyboard is up (weight
    // and notes forms), so it never covers the field being typed in.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      bottomNavigationBar:
      (_waiting && !keyboardOpen) ? _buildCompleteDeliveryBar() : null,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(goat.id, style: AppTheme.heading(size: 16)),
        actions: [
          // A stock profile has no Overview / Purchase tabs, so the goat's
          // full details (breed, colour, purchase & origin) stay one tap
          // away. A Wait on Delivery goat gets the same button, which is
          // also the way to its sale receipt.
          if (_stock || _waiting)
            IconButton(
              tooltip: 'Goat details',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => Navigator.of(context).push(
                fastRoute(
                  GoatStockDetailScreen(
                    farmId: widget.farmId,
                    goat: goat,
                  ),
                ),
              ),
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
              labelColor: AppColors.stockTeal,
              unselectedLabelColor: AppColors.textGrey,
              indicatorColor: AppColors.stockTeal,
              labelStyle: AppTheme.body(size: 11.5, weight: FontWeight.w600),
              unselectedLabelStyle: AppTheme.body(size: 11.5),
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final index in _visibleTabs)
                  Tab(
                    height: 40,
                    icon: Icon(_tabs[index].$2, size: 16),
                    text: _tabs[index].$1,
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
                for (final index in _visibleTabs) _tabBody(goat, index),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The content of one tab, by its `OwnPalaiGoatProfileScreen.tab…`
  /// index.
  Widget _tabBody(Goat goat, int index) {
    switch (index) {
      case OwnPalaiGoatProfileScreen.tabOverview:
        return _buildOverviewTab(goat);

      case OwnPalaiGoatProfileScreen.tabPurchase:
        return _buildPurchaseTab(goat);

      case OwnPalaiGoatProfileScreen.tabPhotos:
        return _PhotosTab(
          farmId: widget.farmId,
          goat: goat,
          emptyMessage: _stock
              ? 'No photos yet. The photo taken when the goat was '
              'registered shows here.'
              : 'No photos yet. Add one while logging a weight entry.',
        );

      case OwnPalaiGoatProfileScreen.tabHealth:
        return _HealthSummaryTab(
          farmId: widget.farmId,
          goat: goat,
          types: _healthTypes,
          // _healthTypes is ordered vaccination, hoof, hair, medicine — the
          // same order as the four consecutive tabs starting at
          // tabVaccination.
          onOpenType: (i) => _tabController.animateTo(
            _positionOf(OwnPalaiGoatProfileScreen.tabVaccination + i),
          ),
        );

      case OwnPalaiGoatProfileScreen.tabProgress:
        return _ProgressTab(
          farmId: widget.farmId,
          goat: goat,
          purchaseFuture: _purchaseFuture,
          initiallyOpen: widget.openWeightLog,
        );

      default:
      // Vaccination / Hoof Cutting / Hair Trimming / Medicine.
        final type = _healthTypes[index -
            OwnPalaiGoatProfileScreen.tabVaccination];

        return _HealthTypeTab(
          farmId: widget.farmId,
          goatId: goat.id,
          type: type,
        );
    }
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
                    _stock
                        ? _pill('Available', AppColors.success)
                        : _waiting
                        ? _pill('Wait on Delivery', AppColors.info)
                        : _pill('Own Palai', AppColors.stockTeal),
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
                    if (_stock) ...[
                      _miniStat(
                          'Gender', goat.gender.isEmpty ? '—' : goat.gender),
                      if (goat.breed.trim().isNotEmpty)
                        _miniStat('Breed', goat.breed.trim()),
                    ] else if (_waiting && goat.waitOnDeliveryAt != null) ...[
                      _miniStat(
                          'Waiting',
                          '${DateTime.now().difference(goat.waitOnDeliveryAt!).inDays} days'),
                      _miniStat('Since',
                          DateFormat('d MMM').format(goat.waitOnDeliveryAt!)),
                    ] else ...[
                      _miniStat('Days Owned', '$daysOwned'),
                      _miniStat('Bought',
                          DateFormat('d MMM').format(goat.purchaseDate)),
                    ],
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
            ('Length', goat.hasLength ? goat.lengthLabel : 'Not recorded'),
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
              Icon(Icons.circle,
                  size: 10,
                  color: _waiting ? AppColors.info : AppColors.success),
              const SizedBox(width: 8),
              Text(
                _waiting
                    ? 'Wait on Delivery — awaiting pickup'
                    : 'Active in Own Palai',
                style: AppTheme.body(size: 12.5),
              ),
            ],
          ),
        ),
        if (_waiting) ...[
          const SizedBox(height: 12),
          _buildSaleCard(),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // WAIT ON DELIVERY — sale card + Complete Delivery
  // ---------------------------------------------------------------------------

  /// Who the goat is waiting for and what was agreed. Read-only — the
  /// money side is handled on the Complete Delivery screen.
  Widget _buildSaleCard() {
    return FutureBuilder<Sale?>(
      future: _saleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SectionCard(
            title: 'Sale',
            child: _SectionSkeleton(rows: 4),
          );
        }

        if (snapshot.hasError) {
          return _SectionCard(
            title: 'Sale',
            child: _errorText('Could not load sale', snapshot.error!),
          );
        }

        final sale = snapshot.data;

        if (sale == null) {
          return _SectionCard(
            title: 'Sale',
            child: _emptyMessage(
              Icons.info_outline,
              'No linked sale record was found for this goat.',
            ),
          );
        }

        final booked = sale.bookingWeight ?? 0;

        return _SectionCard(
          title: 'Sale',
          child: _kvColumn([
            ('Customer', sale.customerName),
            if (sale.mobile.trim().isNotEmpty) ('Mobile', sale.mobile),
            (
            'Price',
            sale.isFixedPrice
                ? '${_money(sale.fixedSalePrice ?? sale.totalSaleAmount)}  (fixed price)'
                : '₹${(sale.bookingPricePerKg ?? sale.sellingPricePerKg).toStringAsFixed(2)}/kg  (booked rate)',
            ),
            (
            'Advance Paid',
            _money(sale.bookingAdvanceAmount ?? 0),
            ),
            if (booked > 0)
              ('Weight at Booking', '${booked.toStringAsFixed(1)} kg'),
          ]),
        );
      },
    );
  }

  /// Bottom bar of a Wait on Delivery profile: the way on to the existing
  /// Complete Delivery screen.
  Widget _buildCompleteDeliveryBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: const BoxDecoration(
          color: AppColors.paleGreen,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _openCompleteDelivery,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text(
              'Complete Delivery',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Same hand-off as Goat Stock's details screen: Complete Delivery pops
  /// `true` once the pickup is saved, and the person lands on the sale
  /// receipt in place of this profile (the goat is no longer waiting, so
  /// this profile would be out of date).
  Future<void> _openCompleteDelivery() async {
    final completed = await Navigator.of(context).push<bool>(
      fastRoute(
        CompleteWaitForDeliveryScreen(
          farmId: widget.farmId,
          goat: widget.goat,
        ),
      ),
    );

    if (completed != true || !mounted) return;

    final saleId = (widget.goat.saleId ?? '').trim();

    if (saleId.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushReplacement(
      fastRoute(
        SaleReceiptScreen(
          farmId: widget.farmId,
          saleId: saleId,
        ),
      ),
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

/// Turns a Firestore list stream into one that never leaves its screen
/// loading for long. If the first snapshot has not arrived after [wait]
/// (a goat with nothing saved yet, or a slow / offline connection), an
/// empty list is emitted so the tab can say "no data" instead of showing a
/// skeleton forever. Real data still replaces it the moment it arrives.
///
/// The result is a BROADCAST stream: a tab's StreamBuilder is torn down and
/// rebuilt as the person scrolls or switches tabs, so it can be listened
/// to more than once (a single-subscription stream throws "Stream has
/// already been listened to" on the second listen). Every new listener
/// starts its own fresh wait.
Stream<List<T>> _orEmptyAfter<T>(
    Stream<List<T>> source, {
      Duration wait = const Duration(seconds: 2),
    }) {
  StreamSubscription<List<T>>? subscription;
  Timer? timer;
  late final StreamController<List<T>> controller;

  controller = StreamController<List<T>>.broadcast(
    onListen: () {
      var gotFirst = false;

      timer?.cancel();
      timer = Timer(wait, () {
        if (!gotFirst && controller.hasListener) {
          controller.add(<T>[]);
        }
      });

      subscription = source.listen(
            (data) {
          gotFirst = true;
          timer?.cancel();
          controller.add(data);
        },
        onError: (Object error, StackTrace stack) {
          gotFirst = true;
          timer?.cancel();
          controller.addError(error, stack);
        },
      );
    },
    // A broadcast controller's onCancel must return void, so the source
    // subscription is cancelled without being awaited.
    onCancel: () {
      timer?.cancel();
      timer = null;

      final active = subscription;
      subscription = null;

      unawaited(active?.cancel());
    },
  );

  return controller.stream;
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

// ----------------------------------------------------------------------------
// Small pieces shared by the inline log forms (health record forms)
// ----------------------------------------------------------------------------

Widget _logFieldIcon(IconData icon, Color color) {
  return Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: color.withOpacity(0.09),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 16, color: color),
  );
}

Widget _logFieldLabel(String text, IconData icon, Color color) {
  return Row(
    children: [
      _logFieldIcon(icon, color),
      const SizedBox(width: 8),
      Text(text, style: AppTheme.heading(size: 12.5)),
    ],
  );
}

InputDecoration _logInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTheme.body(size: 11.5, color: AppColors.textGrey),
    filled: true,
    fillColor: AppColors.paleGreen.withOpacity(0.55),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: AppColors.divider.withOpacity(0.6)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: const BorderSide(color: AppColors.stockTeal, width: 1.2),
    ),
    contentPadding: const EdgeInsets.all(12),
  );
}

/// What the profile shows for ONE care type (vaccination / hoof cutting /
/// hair trimming), derived from all of that type's records.
class _CareSnapshot {
  /// The most recent care that was actually performed — a logged record.
  /// Farm-schedule records ([GoatHealthRecord.isAuto]) are a schedule, not
  /// something that happened, so they never count as "done".
  final GoatHealthRecord? lastDone;

  /// The record holding the reminder that is still active (earliest
  /// `nextDueDate`). Normally the farm-schedule record; once the owner logs
  /// the care, that new record. Null when nothing is scheduled.
  final GoatHealthRecord? scheduled;

  const _CareSnapshot({this.lastDone, this.scheduled});

  bool get isEmpty => lastDone == null && scheduled == null;
}

/// [records] are one care type's records, newest first (the stream's order).
_CareSnapshot _careSnapshot(List<GoatHealthRecord> records) {
  GoatHealthRecord? lastDone;
  for (final r in records) {
    if (!r.isAuto) {
      lastDone = r;
      break;
    }
  }

  GoatHealthRecord? scheduled;
  for (final r in records) {
    final due = r.nextDueDate;
    if (due == null) continue;
    if (scheduled == null || due.isBefore(scheduled.nextDueDate!)) {
      scheduled = r;
    }
  }

  return _CareSnapshot(lastDone: lastDone, scheduled: scheduled);
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
  final String emptyMessage;

  const _PhotosTab({
    required this.farmId,
    required this.goat,
    required this.emptyMessage,
  });

  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  late final Stream<List<GoatWeightEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _orEmptyAfter(
      GoatService.instance.weightHistoryStream(
        farmId: widget.farmId,
        goatId: widget.goat.id,
      ),
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
                  ? _emptyMessage(Icons.photo_outlined, widget.emptyMessage)
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
    _stream = _orEmptyAfter(
      GoatService.instance.healthRecordsStream(
        farmId: widget.farmId,
        goatId: widget.goat.id,
      ),
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
    final snap = _careSnapshot(records);
    final color = _healthTypeColor(type);
    final fmt = DateFormat('d MMM yyyy');
    final summaryText = snap.isEmpty
        ? 'No records yet'
        : [
      snap.lastDone != null
          ? 'Last: ${fmt.format(snap.lastDone!.date)}'
          : 'Not done yet',
      if (snap.scheduled != null)
        'Next: ${fmt.format(snap.scheduled!.nextDueDate!)}',
    ].join(' · ');

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
                  summaryText,
                  style: AppTheme.body(size: 10, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          _dueBadge(snap.scheduled),
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

  const _HealthTypeTab({
    required this.farmId,
    required this.goatId,
    required this.type,
  });

  @override
  State<_HealthTypeTab> createState() => _HealthTypeTabState();
}

class _HealthTypeTabState extends State<_HealthTypeTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<GoatHealthRecord>> _stream;

  // Log form -----------------------------------------------------------------
  final TextEditingController _notesController = TextEditingController();

  bool _formOpen = false;
  DateTime _date = DateTime.now();

  /// Medicine only: a reminder the person sets by hand.
  bool _setNextDueDate = false;
  DateTime? _manualNextDueDate;

  /// Vaccination / Hoof Cutting / Hair Trimming: the farm's Health Reminder
  /// Settings decide the next due date, so it is shown but never edited.
  DateTime? _farmReminderDate;
  int? _farmReminderDays;
  bool _loadingReminderSetting = false;

  bool _saving = false;

  bool get _usesFarmSettings => widget.type != GoatHealthRecordType.medicine;

  // Keeps a half-filled form when the person swipes to another tab.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stream = _orEmptyAfter(
      GoatService.instance.healthRecordsStream(
        farmId: widget.farmId,
        goatId: widget.goatId,
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LOG FORM
  // ---------------------------------------------------------------------------

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _openForm() {
    setState(() {
      _formOpen = true;
    });

    if (_usesFarmSettings) {
      _loadFarmReminderSetting();
    }
  }

  /// Reads the farm's current reminder setting each time the form opens, so
  /// a date changed in Health Reminder Settings is always the one shown.
  Future<void> _loadFarmReminderSetting() async {
    setState(() {
      _loadingReminderSetting = true;
    });

    try {
      final HealthReminderSettings settings =
      await FirestoreService.instance.getHealthReminderSettings(
        widget.farmId,
      );

      if (!mounted) return;

      setState(() {
        switch (widget.type) {
          case GoatHealthRecordType.vaccination:
            _farmReminderDate = settings.vaccinationNextDueDate;
            break;

          case GoatHealthRecordType.hairTrimming:
            _farmReminderDate = settings.hairTrimmingNextDueDate;
            break;

          case GoatHealthRecordType.hoofCutting:
            _farmReminderDays = settings.hoofCuttingReminderDays;
            break;

          case GoatHealthRecordType.medicine:
            break;
        }

        _loadingReminderSetting = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadingReminderSetting = false;
      });
    }
  }

  DateTime? get _resolvedNextDueDate {
    switch (widget.type) {
      case GoatHealthRecordType.vaccination:
      case GoatHealthRecordType.hairTrimming:
        return _farmReminderDate;

      case GoatHealthRecordType.hoofCutting:
        return _farmReminderDays != null
            ? _date.add(Duration(days: _farmReminderDays!))
            : null;

      case GoatHealthRecordType.medicine:
        return _setNextDueDate ? _manualNextDueDate : null;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null && mounted) {
      setState(() {
        _date = picked;
      });
    }
  }

  Future<void> _pickManualNextDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
      _manualNextDueDate ?? _date.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      setState(() {
        _manualNextDueDate = picked;
      });
    }
  }

  void _resetForm() {
    _notesController.clear();
    _date = DateTime.now();
    _setNextDueDate = false;
    _manualNextDueDate = null;
  }

  Future<void> _save() async {
    if (_saving || _loadingReminderSetting) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
    });

    final type = widget.type;
    final nextDueDate = _resolvedNextDueDate;

    try {
      final recordId = await GoatService.instance.addHealthRecord(
        farmId: widget.farmId,
        goatId: widget.goatId,
        record: GoatHealthRecord(
          id: '',
          type: type,
          date: _date,
          notes: _notesController.text.trim(),
          nextDueDate: nextDueDate,
        ),
      );

      unawaited(
        HealthReminderScheduler.instance.scheduleTradingHealthReminder(
          farmId: widget.farmId,
          goatId: widget.goatId,
          goatCode: widget.goatId,
          recordType: type.name,
          recordId: recordId,
          label: type.label,
          dueDate: nextDueDate,
        ),
      );

      // GoatService.addHealthRecord just switched off this goat's
      // farm-schedule reminder for this care type (the new record carries
      // the next due date now) — cancel that schedule's alarms too, so the
      // goat doesn't get a second, stale notification for the same care.
      if (GoatHealthRecord.followsFarmSettings(type)) {
        unawaited(
          HealthReminderScheduler.instance.cancelForTradingRecord(
            goatId: widget.goatId,
            recordType: type.name,
            recordId: GoatHealthRecord.farmScheduleId(type),
          ),
        );
      }

      unawaited(
        FirestoreService.instance.addNotification(
          farmId: widget.farmId,
          docId:
          'health_trading_${widget.goatId}_${type.name}_${recordId}_logged',
          type: '${type.name}_logged',
          category: 'health',
          priority: 'normal',
          title: '${type.label} recorded',
          message: '${widget.goatId}: ${type.label} logged.',
          reference: {
            'goatId': widget.goatId,
            'recordId': recordId,
          },
        ),
      );

      if (!mounted) return;

      setState(() {
        _resetForm();
        _formOpen = false;
        _saving = false;
      });

      _snack('${type.label} record logged.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _snack(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  Widget _buildLogForm(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Record date ------------------------------------------------------
        _logFieldLabel('Record Date', Icons.calendar_today_outlined, color),
        const SizedBox(height: 8),
        InkWell(
          onTap: _saving ? null : _pickDate,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 17, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    DateFormat('dd MMM yyyy').format(_date),
                    style: AppTheme.body(
                      size: 12.5,
                      color: AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.edit_calendar_outlined,
                    size: 17, color: AppColors.textGrey),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Notes ------------------------------------------------------------
        _logFieldLabel('Notes', Icons.notes_outlined, AppColors.warning),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          enabled: !_saving,
          style: AppTheme.body(size: 12.5, color: AppColors.textDark),
          decoration: _logInputDecoration('Optional notes about this record'),
        ),

        const SizedBox(height: 14),

        // Reminder ---------------------------------------------------------
        _logFieldLabel(
            'Reminder', Icons.notifications_none_outlined, AppColors.info),
        const SizedBox(height: 8),
        _buildReminderContent(),

        const SizedBox(height: 16),

        // Save -------------------------------------------------------------
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_saving || _loadingReminderSetting) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color.withOpacity(0.5),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 18),
                const SizedBox(width: 7),
                Text(
                  'Save ${widget.type.label} Record',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReminderContent() {
    if (_loadingReminderSetting) {
      return const _SectionSkeleton(rows: 2);
    }

    if (!_usesFarmSettings) {
      return _buildMedicineReminder();
    }

    if (widget.type == GoatHealthRecordType.hoofCutting) {
      return ReminderCadenceSelector(
        value: _farmReminderDays,
        onChanged: (_) {},
        locked: true,
        lockedNote: 'This reminder schedule is controlled from '
            'Profile → Health Reminder Settings and applies '
            'to the farm.',
      );
    }

    return ReminderDateSelector(
      value: _farmReminderDate,
      onChanged: (_) {},
      locked: true,
      lockedNote: 'This due date is controlled from Profile → '
          'Health Reminder Settings and applies to the farm.',
    );
  }

  void _setReminderOn(bool value) {
    setState(() {
      _setNextDueDate = value;

      if (value) {
        _manualNextDueDate ??= _date.add(const Duration(days: 30));
      }
    });
  }

  Widget _buildMedicineReminder() {
    return Column(
      children: [
        InkWell(
          onTap: _saving ? null : () => _setReminderOn(!_setNextDueDate),
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: _setNextDueDate
                  ? AppColors.info.withOpacity(0.07)
                  : AppColors.paleGreen.withOpacity(0.55),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                _logFieldIcon(
                  _setNextDueDate
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_outlined,
                  AppColors.info,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set next due date',
                        style: AppTheme.body(
                          size: 12.5,
                          color: AppColors.textDark,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Create a reminder for this medicine',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _setNextDueDate,
                  activeColor: AppColors.info,
                  onChanged: _saving ? null : _setReminderOn,
                ),
              ],
            ),
          ),
        ),
        if (_setNextDueDate) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: _saving ? null : _pickManualNextDueDate,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.06),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.info.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_repeat_outlined,
                      size: 17, color: AppColors.info),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _manualNextDueDate != null
                          ? DateFormat('dd MMM yyyy')
                          .format(_manualNextDueDate!)
                          : 'Choose a due date',
                      style: AppTheme.body(
                        size: 12.5,
                        color: AppColors.textDark,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textGrey),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    final type = widget.type;
    final color = _healthTypeColor(type);
    final fmt = DateFormat('d MMM yyyy');

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        if (_formOpen) ...[
          _SectionCard(
            title: 'Log ${type.label}',
            trailing: TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                _formOpen = false;
              }),
              icon: const Icon(Icons.close, size: 14),
              label: const Text('Close'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textGrey,
                padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            child: _buildLogForm(color),
          ),
          const SizedBox(height: 12),
        ],
        _SectionCard(
          title: type.label,
          trailing: _formOpen ? null : _logButton(color, _openForm),
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

              final snap = _careSnapshot(records);
              final lastDone = snap.lastDone;
              final scheduled = snap.scheduled;

              // A farm-schedule record with no due date is an inactive
              // placeholder (completed / switched off) — not history.
              final history = records
                  .where((r) => !r.isAuto || r.nextDueDate != null)
                  .toList();

              if (snap.isEmpty && history.isEmpty) {
                return _emptyMessage(_healthIcon(type),
                    'No ${type.label.toLowerCase()} data yet. Tap Log to add the first record.');
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'Last Done',
                          value: lastDone == null
                              ? '—'
                              : fmt.format(lastDone.date),
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          label: 'Next Due',
                          value: scheduled == null
                              ? '—'
                              : fmt.format(scheduled.nextDueDate!),
                          color: AppColors.tradingBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _dueBadge(scheduled)),
                  if (scheduled != null && scheduled.isAuto) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.event_repeat_outlined,
                            size: 13, color: AppColors.textGrey),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Scheduled automatically from the farm\'s '
                                'Health Reminder Settings.',
                            style: AppTheme.body(
                                size: 9.5, color: AppColors.textGrey),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text('History',
                      style: AppTheme.body(
                          size: 10.5,
                          color: AppColors.textGrey,
                          weight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final r in history)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 7,
                            height: 7,
                            // Hollow dot = scheduled, filled = done.
                            decoration: BoxDecoration(
                              color: r.isAuto ? Colors.transparent : color,
                              shape: BoxShape.circle,
                              border: r.isAuto
                                  ? Border.all(color: color, width: 1.3)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.isAuto
                                      ? 'Scheduled · Due: ${fmt.format(r.nextDueDate!)}'
                                      : fmt.format(r.date) +
                                      (r.nextDueDate != null
                                          ? ' · Due: ${fmt.format(r.nextDueDate!)}'
                                          : ''),
                                  style: AppTheme.body(
                                      size: 11,
                                      color: AppColors.textDark,
                                      weight: FontWeight.w600),
                                ),
                                if (r.isAuto)
                                  Text('Auto · from farm Health Reminder Settings',
                                      style: AppTheme.body(
                                          size: 10, color: AppColors.textGrey))
                                else if (r.notes.trim().isNotEmpty)
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

  /// Whether the "Log Weight Entry" form starts expanded.
  final bool initiallyOpen;

  const _ProgressTab({
    required this.farmId,
    required this.goat,
    required this.purchaseFuture,
    this.initiallyOpen = false,
  });

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<GoatWeightEntry>> _stream;

  // Log Weight Entry form ----------------------------------------------------
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late bool _formOpen = widget.initiallyOpen;
  DateTime _date = DateTime.now();
  Uint8List? _photoBytes;
  String? _photoContentType;
  bool _saving = false;

  // Keeps a half-filled form when the person swipes to another tab.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stream = _orEmptyAfter(
      GoatService.instance.weightHistoryStream(
        farmId: widget.farmId,
        goatId: widget.goat.id,
      ),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LOG WEIGHT ENTRY
  // ---------------------------------------------------------------------------

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await showImageSourceSheet(
        context,
        isGoatPhoto: true,
      );

      if (picked == null || !mounted) return;

      setState(() {
        _photoBytes = picked.bytes;
        _photoContentType = picked.contentType;
      });
    } on ImageTooLargeException catch (e) {
      _snack(e.message, isError: true);
    } catch (_) {
      _snack('Could not add photo. Please try again.', isError: true);
    }
  }

  void _removePhoto() {
    setState(() {
      _photoBytes = null;
      _photoContentType = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.stockTeal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _date = picked;
      });
    }
  }

  void _resetForm() {
    _weightController.clear();
    _notesController.clear();
    _date = DateTime.now();
    _photoBytes = null;
    _photoContentType = null;
  }

  Future<void> _save() async {
    if (_saving) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final weight = double.tryParse(_weightController.text.trim());

    if (weight == null || weight <= 0) {
      _snack('Enter a valid weight.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
    });

    try {
      await GoatService.instance.addWeightEntry(
        farmId: widget.farmId,
        goatId: widget.goat.id,
        entry: GoatWeightEntry(
          id: '',
          weight: weight,
          date: _date,
          photo: _photoBytes,
          photoContentType: _photoContentType,
          notes: _notesController.text.trim(),
        ),
      );

      if (!mounted) return;

      setState(() {
        _resetForm();
        _formOpen = false;
        _saving = false;
      });

      _snack('Weight entry logged.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _snack(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        if (_formOpen) ...[
          _SectionCard(
            title: 'Log Weight Entry',
            trailing: TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                _formOpen = false;
              }),
              icon: const Icon(Icons.close, size: 14),
              label: const Text('Close'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textGrey,
                padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            child: _buildLogForm(),
          ),
          const SizedBox(height: 12),
        ],
        _SectionCard(
          title: 'Weight & Progress',
          trailing: _formOpen
              ? null
              : _logButton(
            AppColors.stockTeal,
                () => setState(() {
              _formOpen = true;
            }),
          ),
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
                    'No weight data yet. Tap Log to add the first entry.');
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

  // ---------------------------------------------------------------------------
  // LOG FORM WIDGETS
  // ---------------------------------------------------------------------------

  Widget _buildLogForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monthly photo -----------------------------------------------------
          Row(
            children: [
              _fieldIcon(Icons.camera_alt_outlined, AppColors.stockTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly Photo', style: AppTheme.heading(size: 12.5)),
                    const SizedBox(height: 2),
                    Text(
                      _photoBytes == null
                          ? 'Optional photo for this weight check'
                          : 'Photo added',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 10.5,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CompactPhotoPicker(
                imageBytes: _photoBytes,
                onTap: _saving ? null : _pickPhoto,
                onRemove: _saving ? null : _removePhoto,
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),

          // Weight ------------------------------------------------------------
          _fieldLabel('Weight', Icons.monitor_weight_outlined,
              AppColors.stockTeal),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _logTextField(
                  _weightController,
                  hint: 'e.g. 24.5',
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final weight = double.tryParse((value ?? '').trim());

                    if (weight == null || weight <= 0) {
                      return 'Enter a valid weight';
                    }

                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: AppColors.stockTeal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  'kg',
                  style: AppTheme.heading(size: 12)
                      .copyWith(color: AppColors.stockTeal),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Date --------------------------------------------------------------
          _fieldLabel('Weight Check Date', Icons.calendar_today_outlined,
              AppColors.tradingBlue),
          const SizedBox(height: 8),
          InkWell(
            onTap: _saving ? null : _pickDate,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.tradingBlue.withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 17, color: AppColors.tradingBlue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      DateFormat('dd MMM yyyy').format(_date),
                      style: AppTheme.body(
                        size: 12.5,
                        color: AppColors.textDark,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 18, color: AppColors.textGrey),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Notes -------------------------------------------------------------
          _fieldLabel('Notes', Icons.notes_outlined, AppColors.warning),
          const SizedBox(height: 8),
          _logTextField(
            _notesController,
            hint: 'Optional notes about this weight check',
            maxLines: 3,
            optional: true,
          ),

          const SizedBox(height: 16),

          // Save --------------------------------------------------------------
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.stockTeal,
                disabledBackgroundColor:
                AppColors.stockTeal.withOpacity(0.55),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
                  : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 18),
                  SizedBox(width: 7),
                  Text(
                    'Save Weight Entry',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldIcon(IconData icon, Color color) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _fieldLabel(String text, IconData icon, Color color) {
    return Row(
      children: [
        _fieldIcon(icon, color),
        const SizedBox(width: 8),
        Text(text, style: AppTheme.heading(size: 12.5)),
      ],
    );
  }

  Widget _logTextField(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        bool optional = false,
        String? Function(String?)? validator,
      }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: !_saving,
      validator: validator ??
              (value) {
            if (!optional && (value == null || value.trim().isEmpty)) {
              return 'Required';
            }

            return null;
          },
      style: AppTheme.body(size: 12.5, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.body(size: 11.5, color: AppColors.textGrey),
        filled: true,
        fillColor: AppColors.paleGreen.withOpacity(0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: AppColors.divider.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide:
          const BorderSide(color: AppColors.stockTeal, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
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

// ============================================================================
// COMPACT PHOTO PICKER (Log Weight Entry form)
// ============================================================================

class _CompactPhotoPicker extends StatelessWidget {
  final Uint8List? imageBytes;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _CompactPhotoPicker({
    required this.imageBytes,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.stockTeal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.stockTeal.withOpacity(0.18),
                    width: 1,
                  ),
                ),
                child: imageBytes == null
                    ? const Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.stockTeal,
                  size: 21,
                )
                    : ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.memory(
                    imageBytes!,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          if (imageBytes != null)
            Positioned(
              right: -4,
              top: -4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}