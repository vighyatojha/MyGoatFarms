import 'package:flutter/material.dart';

import '../../../app_theme.dart';
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

  const LotDetailScreen({
    super.key,
    required this.farmId,
    required this.lotDocId,
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _header(lot),
        const SizedBox(height: 14),

        if (lot.dealCancelled) ...[
          _cancelledCard(lot),
          const SizedBox(height: 14),
        ],

        if (!lot.isLot) ...[
          const WizardNote(
            'This purchase was made before lots existed and has not been '
                'converted yet, so lot actions are unavailable.',
            tone: WizardNoteTone.warning,
          ),
          const SizedBox(height: 14),
        ],

        _stockCard(lot),
        const SizedBox(height: 14),
        _purchaseCard(lot),
        const SizedBox(height: 14),
        _receivingCard(lot),
        const SizedBox(height: 14),
        _paymentCard(lot),
        const SizedBox(height: 14),
        if (lot.isLot) ...[
          _salesCards(lot),
          const SizedBox(height: 14),
        ],
        _actions(lot),
      ],
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                lot.lotId,
                style: AppTheme.heading(size: 22, color: AppColors.primaryGreen),
              ),
              const Spacer(),
              LotBadge(
                label: lot.dealCancelled
                    ? 'Deal Cancelled'
                    : lot.isActive
                    ? 'Active'
                    : 'Completed',
                color: lot.dealCancelled
                    ? AppColors.error
                    : lot.isActive
                    ? AppColors.info
                    : AppColors.textGrey,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${lot.sellerName} • ${wizardDate(lot.purchaseDate)}',
            style: AppTheme.body(size: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (lot.isLot && !lot.dealCancelled)
                LotBadge(
                  label: lotLocationLabel(lot.location),
                  color: lotLocationColor(lot.location),
                ),
              LotBadge(
                label: 'Payment: ${supplierPaymentStatusLabel(status)}',
                color: lotPaymentColor(status),
              ),
            ],
          ),
        ],
      ),
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

  Widget _stockCard(TradingPurchase lot) {
    return WizardSectionCard(
      title: 'Stock',
      icon: Icons.inventory_2_outlined,
      children: [
        WizardComputedRow(label: 'Purchased', value: '${lot.totalGoats}'),
        WizardComputedRow(
          label: 'Sold',
          value: '${lot.soldQty} '
              '(supplier ${lot.soldFromSupplierQty} • farm ${lot.soldFromFarmQty})',
        ),
        if (lot.registeredCount > 0)
          WizardComputedRow(
            label: 'Moved to individual goats',
            value: '${lot.registeredCount}',
          ),
        if (lot.transitDeathQty > 0)
          WizardComputedRow(
            label: 'Died in transit',
            value: '${lot.transitDeathQty}',
          ),
        if (lot.farmDeathQty > 0)
          WizardComputedRow(
            label: 'Died at farm',
            value: '${lot.farmDeathQty}',
          ),
        const Divider(height: 18, color: AppColors.divider),
        WizardComputedRow(
          label: 'At supplier',
          value: '${lot.supplierQty}',
        ),
        WizardComputedRow(
          label: 'At farm',
          value: '${lot.farmQty}',
        ),
        if (lot.reservedFarmQty > 0)
          WizardComputedRow(
            label: 'Reserved at farm (booked)',
            value: '${lot.reservedFarmQty}',
          ),
        if (lot.reservedSupplierQty > 0)
          WizardComputedRow(
            label: 'Reserved at supplier (booked)',
            value: '${lot.reservedSupplierQty}',
          ),
        WizardComputedRow(
          label: 'Remaining in lot',
          value: '${lot.remainingQty}',
          emphasize: true,
        ),
        WizardComputedRow(
          label: 'Available to sell now',
          value: '${lot.availableForSaleQty}',
        ),
      ],
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
                for (final d in deaths)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${wizardDate(d.date)} • ${d.reason}'
                                '${d.note.trim().isEmpty ? '' : ' • ${d.note.trim()}'}'
                                '${d.reversed ? ' • Undone' : ''}',
                            style: AppTheme.body(
                              size: 12,
                              color: d.reversed
                                  ? AppColors.textGrey
                                  : AppColors.textDark,
                            ).copyWith(
                              decoration: d.reversed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        Text(
                          '${d.qty} • ${wizardCurrency(d.lossAmount)}',
                          style: AppTheme.body(
                            size: 12,
                            color: d.reversed
                                ? AppColors.textGrey
                                : AppColors.error,
                            weight: FontWeight.w600,
                          ),
                        ),
                        if (!d.reversed)
                          IconButton(
                            tooltip: 'Undo this death',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            onPressed: () => _undoDeath(d),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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
    final canVoid = !p.voided &&
        !lot.dealCancelled &&
        !p.isLegacy &&
        PartnerAccessService.instance
            .allows(PartnerPermissionKeys.financeExpenseVoid);

    final dim = p.voided ? AppColors.textGrey : AppColors.textDark;

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
                      '${p.voided ? ' • Voided' : ''}',
                  style: AppTheme.body(size: 12, color: dim).copyWith(
                    decoration: p.voided ? TextDecoration.lineThrough : null,
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
              decoration: p.voided ? TextDecoration.lineThrough : null,
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