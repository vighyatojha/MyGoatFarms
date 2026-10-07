import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/lot_sales_summary.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_lot_death_model.dart';
import '../../../models/trading_lot_payment_model.dart';
import '../../../models/trading_lot_receiving_model.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/partner_access_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/permission_gate.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../register_goats/goat_registration_form_screen.dart';
import 'add_lot_payment_sheet.dart';
import 'cancel_lot_deal_screen.dart';
import 'edit_lot_screen.dart';
import '../sell_from_lot/sell_from_lot_wizard_screen.dart';
import 'lot_sales_cards.dart';
import 'lot_widgets.dart';
import 'receive_lot_screen.dart';
import 'record_lot_death_sheet.dart';
import 'transfer_to_customer_palai_wizard_screen.dart';
import 'transfer_to_own_palai_screen.dart';

/// Lot Detail — everything about one purchase lot in one place:
/// stock, purchase, receiving, supplier payments and the actions that
/// apply right now.
///
/// All figures are read live from the lot and its payment / receiving
/// records; nothing here is typed in or cached.
class LotDetailScreen extends StatefulWidget {
  final String farmId;

  /// Firestore document id of the lot (PUR-0007).
  final String lotDocId;

  /// The lot as the previous screen already had it. When given, the screen
  /// shows it at once (no loading spinner) and the live stream replaces it
  /// as soon as it arrives.
  final TradingPurchase? initialLot;

  const LotDetailScreen({
    super.key,
    required this.farmId,
    required this.lotDocId,
    this.initialLot,
  });

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {
  late final Stream<TradingPurchase?> _lotStream;
  late final Stream<List<LotPayment>> _paymentsStream;
  late final Stream<List<LotReceiving>> _receivingsStream;
  late final Stream<List<LotDeath>> _deathsStream;
  late final Stream<List<Sale>> _salesStream;

  /// Same query as [_salesStream], for the "Lot at a glance" card (each
  /// StreamBuilder gets its own listener).
  late final Stream<List<Sale>> _glanceSalesStream;

  /// Optimistic state: payments being voided and deaths being undone. The
  /// row changes at once; the live data confirms it, or it springs back
  /// with an error message if the save fails.
  final Set<String> _voiding = <String>{};
  final Set<String> _undoing = <String>{};

  @override
  void initState() {
    super.initState();

    final service = TradingService.instance;

    _lotStream = service.lotStream(widget.farmId, widget.lotDocId);
    _paymentsStream = service.lotPaymentsStream(widget.farmId, widget.lotDocId);
    _receivingsStream =
        service.lotReceivingsStream(widget.farmId, widget.lotDocId);
    _deathsStream = service.lotDeathsStream(widget.farmId, widget.lotDocId);
    _salesStream = service.salesForLotStream(widget.farmId, widget.lotDocId);
    _glanceSalesStream =
        service.salesForLotStream(widget.farmId, widget.lotDocId);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.error : AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _editLot(TradingPurchase lot) async {
    final saved = await openEditLotScreen(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (saved == true) _snack('Lot updated.');
  }

  Future<void> _cancelDeal(TradingPurchase lot) async {
    final cancelled = await openCancelLotDealScreen(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (cancelled == true) _snack('Deal cancelled and settled.');
  }

  Future<void> _receive(TradingPurchase lot) async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(ReceiveLotScreen(farmId: widget.farmId, lot: lot)),
    );

    if (saved == true) _snack('Receiving saved.');
  }

  Future<void> _recordDeath(TradingPurchase lot) async {
    final saved = await showRecordLotDeathSheet(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (saved == true) _snack('Death recorded.');
  }

  Future<void> _undoDeath(LotDeath d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo this death?'),
        content: Text(
          '${d.qty} goat${d.qty == 1 ? '' : 's'} will be put back in the '
              'lot as alive at the farm, and the lot cost per goat goes back '
              'down. The record is kept and marked as undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo death'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _undoing.add(d.id));
    try {
      await TradingService.instance.undoLotFarmDeath(
        farmId: widget.farmId,
        lotDocId: widget.lotDocId,
        deathId: d.id,
      );
      if (mounted) _snack('Death undone.');
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceFirst(RegExp(r'^\w*(Error|Exception): '), ''),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _undoing.remove(d.id));
    }
  }

  Future<void> _addPayment(TradingPurchase lot) async {
    final saved = await showAddLotPaymentSheet(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (saved == true) _snack('Payment saved.');
  }

  /// Voids a supplier payment entered by mistake (to correct one: void it,
  /// then add the right payment). Needs the same permission as voiding an
  /// expense in Finance, because it voids that expense too.
  Future<void> _voidPayment(LotPayment p) async {
    final reasonController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void this payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${wizardCurrency(p.amount)} paid on ${wizardDate(p.date)} '
                  'will stop counting: the lot\'s Paid amount goes down, the '
                  'balance due goes up, and the matching Finance expense is '
                  'voided. The record is kept and marked as voided.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Typed wrong amount',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Void payment',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    final reason = reasonController.text;
    reasonController.dispose();

    if (ok != true) return;

    setState(() => _voiding.add(p.id));
    try {
      await TradingService.instance.voidSupplierPayment(
        farmId: widget.farmId,
        lotDocId: widget.lotDocId,
        paymentId: p.id,
        reason: reason,
      );
      if (mounted) _snack('Payment voided.');
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceFirst(RegExp(r'^\w*(Error|Exception): '), ''),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _voiding.remove(p.id));
    }
  }

  Future<void> _sellFromLot() async {
    // SellFromLotWizardScreen replaces itself with the sale receipt on
    // success, so there is no return value to check here — the lot's
    // live stream already reflects the sale by the time the person
    // comes back.
    await Navigator.of(context).push(
      fastRoute(const SellFromLotWizardScreen()),
    );
  }

  /// Optional: turns goats of this lot into individual goat records
  /// (G-0041 ...) that go straight to Available Stock. A lot never needs
  /// this — its goats can be sold, transferred or recorded as dead while
  /// they are still anonymous — so nothing prompts for it.
  Future<void> _registerGoats(TradingPurchase lot) async {
    await Navigator.of(context).push(
      fastRoute(
        GoatRegistrationFormScreen(farmId: widget.farmId, purchase: lot),
      ),
    );
    // The lot's live stream already shows the new numbers on return.
  }

  Future<void> _transferToOwnPalai(TradingPurchase lot) async {
    final ids = await Navigator.of(context).push<List<String>>(
      fastRoute(TransferToOwnPalaiScreen(farmId: widget.farmId, lot: lot)),
    );

    if (ids == null || ids.isEmpty) return;

    _snack(
      '${ids.length} goat${ids.length == 1 ? '' : 's'} transferred to '
          'Own Palai.',
    );
  }

  Future<void> _transferToCustomerPalai(TradingPurchase lot) async {
    // The wizard replaces itself with the sale receipt on success, so
    // there is no return value — the lot's live stream already reflects
    // the transfer by the time the person comes back.
    await Navigator.of(context).push(
      fastRoute(
        TransferToCustomerPalaiWizardScreen(farmId: widget.farmId, lot: lot),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: PartnerPermissionKeys.tradingView,
      child: StreamBuilder<TradingPurchase?>(
        stream: _lotStream,
        initialData: widget.initialLot,
        builder: (context, snapshot) {
          final lot = snapshot.data;

          return Scaffold(
            backgroundColor: AppColors.paleGreen,
            appBar: AppBar(
              title: Text(lot?.lotId ?? 'Lot'),
              actions: [
                if (lot != null &&
                    lot.isLot &&
                    !lot.dealCancelled &&
                    PartnerAccessService.instance
                        .allows(PartnerPermissionKeys.tradingManageStock))
                  IconButton(
                    tooltip: 'Edit lot',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editLot(lot),
                  ),
              ],
            ),
            body: _body(snapshot, lot),
          );
        },
      ),
    );
  }

  Widget _body(AsyncSnapshot<TradingPurchase?> snapshot, TradingPurchase? lot) {
    if (snapshot.hasError && lot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            FirestoreService.instance.describeError(snapshot.error!),
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13),
          ),
        ),
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting && lot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (lot == null) {
      return Center(
        child: Text('This lot could not be found.', style: AppTheme.body()),
      );
    }

    // Header on top, then swipeable tabs. The header scrolls away and the
    // tab bar stays pinned, so each tab gets the whole screen. Actions are
    // not a tab: they sit at the bottom of whichever tab is open.
    final tabs = <(String, IconData, List<Widget>)>[
      (
      'Overview',
      Icons.dashboard_outlined,
      [
        if (lot.isLot && !lot.dealCancelled) _glanceCard(lot),
        if (lot.dealCancelled) _cancelledCard(lot),
        if (!lot.isLot)
          const WizardNote(
            'This purchase was made before lots existed and has not been '
                'converted yet, so lot actions are unavailable.',
            tone: WizardNoteTone.warning,
          ),
      ],
      ),
      ('Stock', Icons.inventory_2_outlined, [_stockCard(lot)]),
      (
      'Sales',
      Icons.sell_outlined,
      [
        if (lot.isLot)
          _salesCards(lot)
        else
          const WizardNote('Sales by lot are not available for this purchase.'),
      ],
      ),
      ('Supplier', Icons.payments_outlined, [_paymentCard(lot)]),
      (
      'Details',
      Icons.receipt_long_outlined,
      [_purchaseCard(lot), _receivingCard(lot)],
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: _header(lot),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textDark,
                labelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  for (final t in tabs)
                    Tab(
                      height: 36,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.$2, size: 16),
                            const SizedBox(width: 6),
                            Text(t.$1),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            for (final t in tabs)
              _KeepAliveTab(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    for (var i = 0; i < t.$3.length; i++) ...[
                      if (i > 0) const SizedBox(height: 13),
                      _Compact(child: t.$3[i]),
                    ],
                    const SizedBox(height: 13),
                    _Compact(child: _actions(lot)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Sales & Profit + Lot history, both fed by one live query of this
  /// lot's sales. A failed query must not blank the rest of the screen, so
  /// errors collapse to a short note.
  Widget _salesCards(TradingPurchase lot) {
    return StreamBuilder<List<Sale>>(
      stream: _salesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return WizardNote(
            'Sales for this lot could not be loaded. '
                '${FirestoreService.instance.describeError(snapshot.error!)}',
            tone: WizardNoteTone.warning,
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final sales = snapshot.data!;

        // Farm-death events feed an informational line on the Sales &
        // Profit card. A failed/slow deaths read must never hide the sales,
        // so it just falls back to "no losses" until data arrives.
        return StreamBuilder<List<LotDeath>>(
          stream: _deathsStream,
          builder: (context, deathSnap) {
            final deaths = deathSnap.data ?? const <LotDeath>[];
            final lossAmount = deaths
                .where((d) => !d.reversed)
                .fold<double>(0, (sum, d) => sum + d.lossAmount);

            return LotSalesCards(
              farmId: widget.farmId,
              lot: lot,
              sales: sales,
              farmDeathLoss: lossAmount,
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------

  Widget _header(TradingPurchase lot) {
    final status = lot.paymentStatus;
    final completed = !lot.isActive && !lot.dealCancelled;

    final String badgeLabel;
    final Color badgeColor;
    final IconData badgeIcon;
    if (lot.dealCancelled) {
      badgeLabel = 'Deal Cancelled';
      badgeColor = AppColors.error;
      badgeIcon = Icons.block_rounded;
    } else if (completed || !lot.isLot) {
      badgeLabel = 'Completed';
      badgeColor = AppColors.success;
      badgeIcon = Icons.task_alt_rounded;
    } else {
      badgeLabel = lotLocationLabel(lot.location);
      badgeColor = lotLocationColor(lot.location);
      badgeIcon = lotLocationIcon(lot.location);
    }

    final List<(String, int, Color?)> columns = lot.dealCancelled
        ? [('PURCHASED', lot.totalGoats, null)]
        : completed
        ? [
      ('PURCHASED', lot.totalGoats, null),
      ('SOLD', lot.soldQty, null),
      ('DIED', lot.mortality, lot.mortality > 0 ? AppColors.error : null),
      ('REGISTERED', lot.registeredCount, null),
    ]
        : [
      ('PURCHASED', lot.totalGoats, null),
      ('SOLD', lot.soldQty, null),
      // Booked goats are promised to customers: shown on their own and not
      // counted as remaining until the deal is cancelled.
      if (lot.reservedQty > 0) ('BOOKED', lot.reservedQty, AppColors.warning),
      ('REMAINING', lot.availableForSaleQty, const Color(0xFF1E8A57)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                lot.lotId,
                style: AppTheme.heading(
                  size: 24,
                  color: AppColors.textDark,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: LotIconBadge(
                  label: badgeLabel,
                  color: badgeColor,
                  icon: badgeIcon,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 14, color: AppColors.textGrey),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${lot.sellerName}  •  ${wizardDate(lot.purchaseDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 12.5, color: AppColors.textGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // PURCHASED | SOLD | REMAINING
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.divider.withValues(alpha: 0.9),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            columns[i].$1,
                            style: AppTheme.body(
                              size: 10.5,
                              color: AppColors.textGrey,
                              weight: FontWeight.w600,
                            ).copyWith(letterSpacing: 0.6),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${columns[i].$2}',
                            style: AppTheme.heading(
                              size: 21,
                              color: columns[i].$3 ?? AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // At Supplier / At Farm
          if (lot.isLot && !lot.dealCancelled && !completed) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.lightGreen.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warehouse_outlined, size: 15, color: AppColors.textGrey),
                  const SizedBox(width: 5),
                  Text(
                    'At Supplier: ${lot.supplierAvailableQty}',
                    style: AppTheme.body(
                        size: 12, color: AppColors.textDark, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.home_outlined,
                    size: 15,
                    color: lot.farmAvailableQty > 0
                        ? AppColors.darkGreen
                        : AppColors.textGrey,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'At Farm: ${lot.farmAvailableQty}',
                    style: AppTheme.body(
                        size: 12, color: AppColors.textDark, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.divider.withValues(alpha: 0.7)),
          const SizedBox(height: 11),

          // Due / Settled
          Row(
            children: [
              Expanded(
                child: lot.dealCancelled
                    ? Text(
                  'Loss ${wizardCurrency(lot.cancelLossAmount)}  •  '
                      'Refunded ${wizardCurrency(lot.cancelRefundAmount)}',
                  style: AppTheme.body(
                      size: 12.5, color: AppColors.textDark, weight: FontWeight.w600),
                )
                    : lot.dueAmount >= 0.01
                    ? Text.rich(TextSpan(children: [
                  TextSpan(
                    text: 'Due: ',
                    style: AppTheme.body(size: 13, color: AppColors.textGrey),
                  ),
                  TextSpan(
                    text: wizardCurrency(lot.dueAmount),
                    style: AppTheme.heading(size: 18, color: AppColors.textDark),
                  ),
                ]))
                    : Text.rich(TextSpan(children: [
                  TextSpan(
                    text: 'Payment: ',
                    style: AppTheme.body(size: 13, color: AppColors.textGrey),
                  ),
                  TextSpan(
                    text: 'Settled (${wizardCurrency(0)} Due)',
                    style: AppTheme.heading(size: 15, color: AppColors.success),
                  ),
                ])),
              ),
              const SizedBox(width: 8),
              LotIconBadge(
                label: supplierPaymentStatusLabel(status),
                color: lotPaymentColor(status),
                icon: status == 'Paid' ? Icons.check_rounded : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // LOT AT A GLANCE: stock left, sales done, supplier payment pending
  // ---------------------------------------------------------------------

  Widget _glanceCard(TradingPurchase lot) {
    final canPay = PartnerAccessService.instance
        .allows(PartnerPermissionKeys.tradingSupplierPayment);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lot at a glance', style: AppTheme.heading(size: 15)),
          const SizedBox(height: 12),

          // 1. Stock still pending in the lot
          _glanceSection(
            icon: Icons.inventory_2_outlined,
            color: AppColors.primaryGreen,
            title: 'Stock left in lot',
            value: '${lot.availableForSaleQty} of ${lot.totalGoats}',
            lines: [
              'At supplier ${lot.supplierAvailableQty}  •  '
                  'At farm ${lot.farmAvailableQty}',
              'Available to sell now ${lot.availableForSaleQty}'
                  '${lot.reservedQty > 0 ? '  •  Booked ${lot.reservedQty}' : ''}',
              if (lot.unsoldOutLabel.isNotEmpty) '${lot.unsoldOutLabel} (not sold)',
            ],
          ),
          const Divider(height: 22, color: AppColors.divider),

          // 2. Sales made from this lot
          StreamBuilder<List<Sale>>(
            stream: _glanceSalesStream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return _glanceSection(
                  icon: Icons.sell_outlined,
                  color: AppColors.info,
                  title: 'Sales from this lot',
                  value: '${lot.soldQty} sold',
                  lines: const ['Loading sale amounts…'],
                );
              }
              final sales = LotSalesSummary.from(lot, snap.data!);
              return _glanceSection(
                icon: Icons.sell_outlined,
                color: AppColors.info,
                title: 'Sales from this lot',
                value: '${sales.goatsSold} sold',
                lines: [
                  'Sales ${wizardCurrency(sales.revenue)}'
                      '  •  Customers owe ${wizardCurrency(sales.customerPending)}',
                  if (sales.openGoats > 0)
                    '${sales.openGoats} goats booked, waiting for delivery',
                ],
                valueColor: AppColors.textDark,
              );
            },
          ),
          const Divider(height: 22, color: AppColors.divider),

          // 3. Supplier payment pending
          _glanceSection(
            icon: Icons.payments_outlined,
            color: lot.dueAmount >= 0.01 ? AppColors.error : AppColors.success,
            title: 'Supplier payment',
            value: lot.dueAmount >= 0.01
                ? '${wizardCurrency(lot.dueAmount)} due'
                : 'Fully paid',
            valueColor:
            lot.dueAmount >= 0.01 ? AppColors.error : AppColors.success,
            lines: [
              'Paid ${wizardCurrency(lot.paidAmount)} of '
                  '${wizardCurrency(lot.purchaseAmount)}  •  ${lot.sellerName}',
            ],
          ),
          if (lot.dueAmount >= 0.01 && canPay) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () => _addPayment(lot),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Pay supplier ${wizardCurrency(lot.dueAmount)}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _glanceSection({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required List<String> lines,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTheme.body(size: 12)),
                  ),
                  Text(
                    value,
                    style: AppTheme.heading(
                      size: 15,
                      color: valueColor ?? AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    line,
                    style: AppTheme.body(
                      size: 11.5,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // DEAL CANCELLED
  // ---------------------------------------------------------------------

  Widget _cancelledCard(TradingPurchase lot) {
    final lossed = lot.cancelLossAmount >= 0.01;

    return WizardSectionCard(
      title: 'Deal Cancelled',
      icon: Icons.cancel_outlined,
      children: [
        if (lot.cancelledAt != null)
          WizardComputedRow(
            label: 'Cancelled on',
            value: wizardDate(lot.cancelledAt!),
          ),
        WizardComputedRow(
          label: 'Paid to supplier',
          value: wizardCurrency(lot.cancelPaidAmount),
        ),
        WizardComputedRow(
          label: 'Refund received',
          value: wizardCurrency(lot.cancelRefundAmount),
        ),
        const Divider(height: 18, color: AppColors.divider),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Loss due to deal cancel',
                  style: AppTheme.body(
                    size: 14,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                wizardCurrency(lot.cancelLossAmount),
                style: AppTheme.heading(
                  size: 16,
                  color: lossed ? AppColors.error : AppColors.success,
                ),
              ),
            ],
          ),
        ),
        if (lot.cancelNote.trim().isNotEmpty)
          WizardComputedRow(label: 'Note', value: lot.cancelNote.trim()),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // STOCK
  // ---------------------------------------------------------------------

  /// Stock, made easy to read:
  ///  1. one coloured bar of every goat bought: sold / at supplier / at
  ///     farm / died / moved to individual goats;
  ///  2. big tiles for what can be done now;
  ///  3. a short list of where the goats went.
  /// Every number is the lot's own live figure.
  Widget _stockCard(TradingPurchase lot) {
    const sold = Color(0xFF3569A8);
    const supplier = Color(0xFF6757B7);
    const farm = Color(0xFF278B68);
    const died = AppColors.error;
    const moved = Color(0xFFB26A00);

    final segments = <(String, int, Color)>[
      ('Sold', lot.soldQty, sold),
      ('Booked', lot.reservedQty, AppColors.warning),
      ('At supplier', lot.supplierAvailableQty, supplier),
      ('At farm', lot.farmAvailableQty, farm),
      ('Died', lot.mortality, died),
      ('Individual goats', lot.registeredCount, moved),
    ].where((e) => e.$2 > 0).toList();

    final shown = segments.fold<int>(0, (s, e) => s + e.$2);
    final total = lot.totalGoats > shown ? lot.totalGoats : shown;

    Widget tile(String label, int value, String sub, Color color, IconData icon,
        {bool big = false}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                          size: 11.5, color: color, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$value',
                style: AppTheme.heading(size: big ? 28 : 22, color: AppColors.textDark),
              ),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 10.5)),
            ],
          ),
        ),
      );
    }

    Widget wentRow(Color color, String label, String value, {String? sub}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTheme.body(
                          size: 13, color: AppColors.textDark, weight: FontWeight.w500)),
                  if (sub != null) Text(sub, style: AppTheme.body(size: 11)),
                ],
              ),
            ),
            Text(value, style: AppTheme.heading(size: 15, color: AppColors.textDark)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + remaining
          Row(
            children: [
              Expanded(child: Text('Stock', style: AppTheme.heading(size: 16))),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${lot.availableForSaleQty}',
                    style: AppTheme.heading(size: 18, color: farm),
                  ),
                  TextSpan(
                    text: ' of ${lot.totalGoats} left',
                    style: AppTheme.body(size: 12.5),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. Where every goat is
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: total == 0
                  ? Container(color: AppColors.divider)
                  : Row(
                children: [
                  for (final e in segments)
                    Expanded(flex: e.$2, child: Container(color: e.$3)),
                  if (total > shown)
                    Expanded(
                      flex: total - shown,
                      child: Container(color: AppColors.divider),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final e in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: e.$3, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text('${e.$1} ${e.$2}',
                        style: AppTheme.body(size: 11, color: AppColors.textDark)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. What can be done now
          Row(
            children: [
              tile(
                'Available to sell',
                lot.availableForSaleQty,
                'Ready for a new sale now',
                AppColors.primaryGreen,
                Icons.sell_outlined,
                big: true,
              ),
              const SizedBox(width: 10),
              tile(
                'Booked',
                lot.reservedQty,
                lot.reservedQty == 0
                    ? 'No open bookings'
                    : 'Supplier ${lot.reservedSupplierQty} · Farm ${lot.reservedFarmQty}',
                AppColors.warning,
                Icons.event_available_outlined,
                big: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              tile(
                'At supplier',
                lot.supplierAvailableQty,
                lot.supplierQty == 0
                    ? 'All received'
                    : lot.reservedSupplierQty > 0
                    ? 'Not received · ${lot.reservedSupplierQty} booked'
                    : 'Not received yet',
                supplier,
                Icons.local_shipping_outlined,
              ),
              const SizedBox(width: 10),
              tile(
                'At farm',
                lot.farmAvailableQty,
                lot.farmQty == 0
                    ? 'None at the farm'
                    : lot.reservedFarmQty > 0
                    ? 'Free · ${lot.reservedFarmQty} booked'
                    : 'Received, not sold',
                farm,
                Icons.home_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Where they went
          Text('Where the goats went',
              style: AppTheme.heading(size: 13.5, color: AppColors.textGrey)),
          const SizedBox(height: 4),
          wentRow(
            sold,
            'Sold',
            '${lot.soldQty}',
            sub: 'From supplier ${lot.soldFromSupplierQty}  •  '
                'From farm ${lot.soldFromFarmQty}',
          ),
          if (lot.registeredCount > 0)
            wentRow(moved, 'Moved to individual goats', '${lot.registeredCount}',
                sub: 'Now in Available Stock or Palai'),
          if (lot.transitDeathQty > 0)
            wentRow(died, 'Died in transit', '${lot.transitDeathQty}'),
          if (lot.farmDeathQty > 0)
            wentRow(died, 'Died at farm', '${lot.farmDeathQty}'),
          const Divider(height: 18, color: AppColors.divider),
          if (lot.reservedQty > 0)
            wentRow(AppColors.warning, 'Booked for customers',
                '${lot.reservedQty}',
                sub: 'At supplier ${lot.reservedSupplierQty}  •  '
                    'At farm ${lot.reservedFarmQty}'),
          wentRow(farm, 'Still free in the lot', '${lot.availableForSaleQty}',
              sub: 'At supplier ${lot.supplierAvailableQty}  •  '
                  'At farm ${lot.farmAvailableQty}'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PURCHASE
  // ---------------------------------------------------------------------

  Widget _purchaseCard(TradingPurchase lot) {
    return WizardSectionCard(
      title: 'Purchase',
      icon: Icons.shopping_cart_outlined,
      children: [
        WizardComputedRow(label: 'Supplier', value: lot.sellerName),
        if (lot.mobile.trim().isNotEmpty)
          WizardComputedRow(label: 'Mobile', value: lot.mobile),
        if (lot.market.trim().isNotEmpty)
          WizardComputedRow(label: 'Market', value: lot.market),
        if (lot.vehicleNumber.trim().isNotEmpty)
          WizardComputedRow(label: 'Vehicle / Transport', value: lot.vehicleNumber),
        if (lot.remarks.trim().isNotEmpty)
          WizardComputedRow(label: 'Remarks', value: lot.remarks.trim()),
        if (lot.expectedDeliveryDate != null && lot.supplierQty > 0)
          WizardComputedRow(
            label: 'Expected delivery',
            value: wizardDate(lot.expectedDeliveryDate!),
          ),
        if (lot.maleGoats > 0 || lot.femaleGoats > 0)
          WizardComputedRow(
            label: 'Male / Female',
            value: '${lot.maleGoats} / ${lot.femaleGoats}',
          ),
        const Divider(height: 18, color: AppColors.divider),
        WizardComputedRow(
          label: 'Weight at purchase',
          value: '${PurchaseCosting.formatNumber(lot.totalWeightAtPurchase)} kg',
        ),
        WizardComputedRow(
          label: 'Pricing',
          value: lot.isFixedPrice ? 'Fixed Price' : 'By KG',
        ),
        WizardComputedRow(
          label: lot.isFixedPrice ? 'Effective price per kg' : 'Price per kg',
          value: wizardCurrency(lot.pricePerKg),
        ),
        WizardComputedRow(
          label: 'Purchase amount',
          value: wizardCurrency(lot.purchaseAmount),
          emphasize: true,
        ),
        if (lot.totalTransportExpenses > 0) ...[
          WizardComputedRow(
            label: 'Transport & other costs',
            value: wizardCurrency(lot.totalTransportExpenses),
          ),
          WizardComputedRow(
            label: 'Grand total',
            value: wizardCurrency(lot.grandTotal),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // RECEIVING
  // ---------------------------------------------------------------------

  Widget _receivingCard(TradingPurchase lot) {
    final received = lot.receivedTotalQty > 0;
    final diff = lot.receivingWeightDifference;

    return WizardSectionCard(
      title: 'Receiving',
      icon: Icons.local_shipping_outlined,
      children: [
        if (!received)
          Text(
            'Nothing has been received yet.',
            style: AppTheme.body(size: 12),
          )
        else ...[
          WizardComputedRow(
            label: 'Received alive',
            value: '${lot.arrivedAliveQty} of ${lot.totalGoats}',
          ),
          WizardComputedRow(
            label: 'Weight at purchase (received goats)',
            value:
            '${PurchaseCosting.formatNumber(lot.expectedWeightOfReceived)} kg',
          ),
          WizardComputedRow(
            label: 'Weight on arrival',
            value:
            '${PurchaseCosting.formatNumber(lot.totalWeightAfterArrival ?? 0)} kg',
          ),
          WizardComputedRow(
            label: diff < 0 ? 'Weight lost' : 'Weight difference',
            value: '${diff > 0 ? '+' : ''}'
                '${PurchaseCosting.formatNumber(diff)} kg',
            emphasize: true,
          ),
        ],

        StreamBuilder<List<LotReceiving>>(
          stream: _receivingsStream,
          builder: (context, snapshot) {
            final events = snapshot.data ?? const <LotReceiving>[];

            if (events.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 22, color: AppColors.divider),
                Text('Batches', style: AppTheme.body(size: 11)),
                const SizedBox(height: 6),
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${wizardDate(e.date)}'
                                '${e.isLegacy ? ' (earlier purchase)' : ''}',
                            style: AppTheme.body(
                              size: 12,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        Text(
                          '${e.arrivedQty} alive'
                              '${e.diedQty > 0 ? ' • ${e.diedQty} died' : ''}',
                          style: AppTheme.body(
                            size: 12,
                            color: AppColors.textDark,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),

        StreamBuilder<List<LotDeath>>(
          stream: _deathsStream,
          builder: (context, snapshot) {
            final deaths = snapshot.data ?? const <LotDeath>[];

            if (deaths.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 22, color: AppColors.divider),
                Text('Deaths at farm', style: AppTheme.body(size: 11)),
                const SizedBox(height: 6),
                for (final d in deaths) _deathRow(d),
              ],
            );
          },
        ),
      ],
    );
  }

  /// One farm death. While an undo is being saved it already shows as
  /// undone (optimistic); it springs back if the save fails.
  Widget _deathRow(LotDeath d) {
    final pending = _undoing.contains(d.id) && !d.reversed;
    final undone = d.reversed || pending;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${wizardDate(d.date)} • ${d.reason}'
                  '${d.note.trim().isEmpty ? '' : ' • ${d.note.trim()}'}'
                  '${d.reversed ? ' • Undone' : pending ? ' • Undoing…' : ''}',
              style: AppTheme.body(
                size: 12,
                color: undone ? AppColors.textGrey : AppColors.textDark,
              ).copyWith(
                decoration: undone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            '${d.qty} • ${wizardCurrency(d.lossAmount)}',
            style: AppTheme.body(
              size: 12,
              color: undone ? AppColors.textGrey : AppColors.error,
              weight: FontWeight.w600,
            ),
          ),
          if (!undone)
            IconButton(
              tooltip: 'Undo this death',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo_rounded, size: 18),
              onPressed: () => _undoDeath(d),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SUPPLIER PAYMENTS
  // ---------------------------------------------------------------------

  Widget _paymentCard(TradingPurchase lot) {
    final status = lot.paymentStatus;

    return WizardSectionCard(
      title: 'Supplier Payment',
      icon: Icons.payments_outlined,
      children: [
        Row(
          children: [
            Text('Status', style: AppTheme.body(size: 13)),
            const Spacer(),
            LotBadge(
              label: supplierPaymentStatusLabel(status),
              color: lotPaymentColor(status),
            ),
          ],
        ),
        WizardComputedRow(
          label: 'Purchase amount',
          value: wizardCurrency(lot.purchaseAmount),
        ),
        WizardComputedRow(
          label: 'Paid',
          value: wizardCurrency(lot.paidAmount),
        ),
        const Divider(height: 18, color: AppColors.divider),
        WizardComputedRow(
          label: 'Balance due',
          value: wizardCurrency(lot.dueAmount),
          emphasize: true,
        ),

        StreamBuilder<List<LotPayment>>(
          stream: _paymentsStream,
          builder: (context, snapshot) {
            final payments = snapshot.data ?? const <LotPayment>[];

            if (payments.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 22, color: AppColors.divider),
                Text('Payment history', style: AppTheme.body(size: 11)),
                const SizedBox(height: 6),
                for (final p in payments) _paymentRow(p, lot),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _paymentRow(LotPayment p, TradingPurchase lot) {
    final pendingVoid = _voiding.contains(p.id) && !p.voided;
    final canVoid = !p.voided &&
        !pendingVoid &&
        !lot.dealCancelled &&
        !p.isLegacy &&
        PartnerAccessService.instance
            .allows(PartnerPermissionKeys.financeExpenseVoid);

    final struck = p.voided || pendingVoid;
    final dim = struck ? AppColors.textGrey : AppColors.textDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${wizardDate(p.date)} • ${p.method}'
                      '${p.isLegacy ? ' (earlier purchase)' : ''}'
                      '${p.voided ? ' • Voided' : pendingVoid ? ' • Voiding…' : ''}',
                  style: AppTheme.body(size: 12, color: dim).copyWith(
                    decoration: struck ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (p.note.trim().isNotEmpty)
                  Text(p.note, style: AppTheme.body(size: 11)),
                if (p.voided && p.voidReason.trim().isNotEmpty)
                  Text(
                    'Voided: ${p.voidReason.trim()}',
                    style: AppTheme.body(size: 11),
                  ),
              ],
            ),
          ),
          Text(
            wizardCurrency(p.amount),
            style: AppTheme.body(
              size: 12.5,
              color: dim,
              weight: FontWeight.w700,
            ).copyWith(
              decoration: struck ? TextDecoration.lineThrough : null,
            ),
          ),
          if (canVoid)
            IconButton(
              tooltip: 'Void this payment',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.block_rounded, size: 18),
              onPressed: () => _voidPayment(p),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------

  Widget _actions(TradingPurchase lot) {
    // One permission per kind of action. The farm owner is unaffected (see
    // PartnerAccessService.allows); only an invited partner without the
    // matching permission is blocked on that button.
    final access = PartnerAccessService.instance;
    final canReceive = access.allows(PartnerPermissionKeys.tradingReceive);
    final canPay = access.allows(PartnerPermissionKeys.tradingSupplierPayment);
    final canSell = access.allows(PartnerPermissionKeys.tradingSell);
    final canManage = access.allows(PartnerPermissionKeys.tradingManageStock);

    return WizardSectionCard(
      title: 'Actions',
      icon: Icons.bolt_rounded,
      children: [
        _ActionButton(
          icon: Icons.edit_outlined,
          label: 'Edit Lot',
          hint: lot.dealCancelled
              ? 'This deal was cancelled'
              : lot.location == LotLocation.atSupplier
              ? 'Change supplier, goats, weight, price or costs'
              : 'Edit details — lot cost is recalculated',
          enabled: lot.isLot && canManage && !lot.dealCancelled,
          onTap: () => _editLot(lot),
        ),
        _ActionButton(
          icon: Icons.inventory_2_outlined,
          label: 'Receive Lot',
          hint: lot.supplierAvailableQty > 0
              ? '${lot.supplierAvailableQty} goats still at supplier'
              : lot.reservedSupplierQty > 0
              ? '${lot.reservedSupplierQty} at supplier are booked'
              : 'Nothing left at the supplier',
          enabled: lot.isLot && canReceive && lot.supplierAvailableQty > 0,
          onTap: () => _receive(lot),
        ),
        _ActionButton(
          icon: Icons.payments_outlined,
          label: 'Add Payment',
          hint: lot.dueAmount >= 0.01
              ? '${wizardCurrency(lot.dueAmount)} due'
              : 'Fully paid',
          enabled: lot.isLot && canPay && lot.dueAmount >= 0.01,
          onTap: () => _addPayment(lot),
        ),
        _ActionButton(
          icon: Icons.sell_outlined,
          label: 'Sell From Lot',
          hint: lot.availableForSaleQty > 0
              ? '${lot.availableForSaleQty} available'
              : 'No goats available to sell',
          enabled: lot.isLot && canSell && lot.availableForSaleQty > 0,
          onTap: _sellFromLot,
        ),
        _ActionButton(
          icon: Icons.app_registration_rounded,
          label: 'Register Goats (optional)',
          hint: lot.farmAvailableQty > 0
              ? '${lot.farmAvailableQty} at farm · add them to Available '
              'Stock one by one'
              : 'Needs goats at the farm',
          enabled: lot.isLot && canManage && lot.farmAvailableQty > 0,
          onTap: () => _registerGoats(lot),
        ),
        _ActionButton(
          icon: Icons.home_work_outlined,
          label: 'Transfer to Own Palai',
          hint: lot.farmAvailableQty > 0
              ? '${lot.farmAvailableQty} at farm'
              : 'Needs goats at the farm',
          enabled: lot.isLot && canManage && lot.farmAvailableQty > 0,
          onTap: () => _transferToOwnPalai(lot),
        ),
        _ActionButton(
          icon: Icons.groups_outlined,
          label: 'Transfer to Customer Palai',
          hint: lot.farmAvailableQty > 0
              ? '${lot.farmAvailableQty} at farm'
              : 'Needs goats at the farm',
          enabled: lot.isLot && canManage && lot.farmAvailableQty > 0,
          onTap: () => _transferToCustomerPalai(lot),
        ),
        _ActionButton(
          icon: Icons.cancel_outlined,
          label: 'Cancel Deal',
          hint: lot.dealCancelled
              ? 'Already cancelled'
              : lot.canCancelDeal
              ? 'Settle the paid amount: refund and loss'
              : 'Only while all goats are still at the supplier',
          enabled: lot.canCancelDeal && canPay,
          onTap: () => _cancelDeal(lot),
        ),
        _ActionButton(
          icon: Icons.warning_amber_rounded,
          label: 'Record Death',
          hint: lot.farmAvailableQty > 0
              ? '${lot.farmAvailableQty} at farm'
              : 'Needs goats at the farm',
          enabled: lot.isLot && canManage && lot.farmAvailableQty > 0,
          onTap: () => _recordDeath(lot),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.darkGreen : AppColors.textGrey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: enabled ? AppColors.lightGreen : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTheme.heading(size: 13.5, color: color)),
                      Text(hint, style: AppTheme.body(size: 11)),
                    ],
                  ),
                ),
                if (enabled)
                  Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned tab bar under the lot header.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  static const double _height = 52;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.paleGreen,
      alignment: Alignment.center,
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: tabBar,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate old) => old.tabBar != tabBar;
}

/// Keeps a tab alive while swiping, so its live data is not reloaded.
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Draws [child] about 7% smaller (text, icons, padding and all), using the
/// full width. Used for everything below the lot header card.
class _Compact extends StatelessWidget {
  const _Compact({required this.child});

  final Widget child;

  static const double _scale = 0.93;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth / _scale,
            child: child,
          ),
        );
      },
    );
  }
}