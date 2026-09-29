import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
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
import 'add_lot_payment_sheet.dart';
import '../sell_from_lot/sell_from_lot_wizard_screen.dart';
import 'lot_widgets.dart';
import 'receive_lot_screen.dart';

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

  @override
  void initState() {
    super.initState();

    final service = TradingService.instance;

    _lotStream = service.lotStream(widget.farmId, widget.lotDocId);
    _paymentsStream = service.lotPaymentsStream(widget.farmId, widget.lotDocId);
    _receivingsStream =
        service.lotReceivingsStream(widget.farmId, widget.lotDocId);
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

  Future<void> _receive(TradingPurchase lot) async {
    final saved = await Navigator.of(context).push<bool>(
      fastRoute(ReceiveLotScreen(farmId: widget.farmId, lot: lot)),
    );

    if (saved == true) _snack('Receiving saved.');
  }

  Future<void> _addPayment(TradingPurchase lot) async {
    final saved = await showAddLotPaymentSheet(
      context: context,
      farmId: widget.farmId,
      lot: lot,
    );

    if (saved == true) _snack('Payment saved.');
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

  /// The Palai transfers are built in a later step. The button already
  /// follows the real quantity rules so the screen does not need to
  /// change when that screen arrives.
  void _comingSoon(String what) {
    _snack('$what is coming in an upcoming update.');
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
        _actions(lot),
      ],
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
        color: AppColors.primaryGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.18)),
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
                label: lot.isActive ? 'Active' : 'Completed',
                color: lot.isActive ? AppColors.info : AppColors.textGrey,
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
              if (lot.isLot)
                LotBadge(
                  label: lotLocationLabel(lot.location),
                  color: lotLocationColor(lot.location),
                ),
              LotBadge(
                label: 'Payment: $status',
                color: lotPaymentColor(status),
              ),
            ],
          ),
        ],
      ),
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
        if (lot.mortality > 0)
          WizardComputedRow(
            label: 'Died in transit',
            value: '${lot.mortality}',
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
            label: 'Reserved (booked)',
            value: '${lot.reservedFarmQty}',
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
          WizardComputedRow(label: 'Vehicle', value: lot.vehicleNumber),
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
          label: 'Price per kg',
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
            value: '${lot.receivedAliveQty} of ${lot.totalGoats}',
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
            LotBadge(label: status, color: lotPaymentColor(status)),
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
                for (final p in payments) _paymentRow(p),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _paymentRow(LotPayment p) {
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
                      '${p.isLegacy ? ' (earlier purchase)' : ''}',
                  style: AppTheme.body(size: 12, color: AppColors.textDark),
                ),
                if (p.note.trim().isNotEmpty)
                  Text(p.note, style: AppTheme.body(size: 11)),
              ],
            ),
          ),
          Text(
            wizardCurrency(p.amount),
            style: AppTheme.body(
              size: 12.5,
              color: AppColors.textDark,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------

  Widget _actions(TradingPurchase lot) {
    // No dedicated permission exists yet for receiving/paying/selling a
    // lot — tradingPurchaseCreate is the closest existing key (the only
    // trading mutation permission in PartnerPermissionKeys today). The
    // farm owner is unaffected either way (see PartnerAccessService.
    // allows); only an invited partner without this permission is
    // blocked here.
    final canMutate =
    PartnerAccessService.instance.allows(PartnerPermissionKeys.tradingPurchaseCreate);
    final lotOk = lot.isLot && canMutate;

    return WizardSectionCard(
      title: 'Actions',
      icon: Icons.bolt_rounded,
      children: [
        _ActionButton(
          icon: Icons.inventory_2_outlined,
          label: 'Receive Lot',
          hint: lot.supplierQty > 0
              ? '${lot.supplierQty} goats still at supplier'
              : 'Nothing left at the supplier',
          enabled: lotOk && lot.supplierQty > 0,
          onTap: () => _receive(lot),
        ),
        _ActionButton(
          icon: Icons.payments_outlined,
          label: 'Add Payment',
          hint: lot.dueAmount >= 0.01
              ? '${wizardCurrency(lot.dueAmount)} due'
              : 'Fully paid',
          enabled: lotOk && lot.dueAmount >= 0.01,
          onTap: () => _addPayment(lot),
        ),
        _ActionButton(
          icon: Icons.sell_outlined,
          label: 'Sell From Lot',
          hint: lot.availableForSaleQty > 0
              ? '${lot.availableForSaleQty} available'
              : 'No goats available to sell',
          enabled: lotOk && lot.availableForSaleQty > 0,
          onTap: _sellFromLot,
        ),
        _ActionButton(
          icon: Icons.home_work_outlined,
          label: 'Transfer to Own Palai',
          hint: lot.farmAvailableQty > 0
              ? '${lot.farmAvailableQty} at farm'
              : 'Needs goats at the farm',
          enabled: lotOk && lot.farmAvailableQty > 0,
          onTap: () => _comingSoon('Transfer to Own Palai'),
        ),
        _ActionButton(
          icon: Icons.groups_outlined,
          label: 'Transfer to Customer Palai',
          hint: lot.farmAvailableQty > 0
              ? '${lot.farmAvailableQty} at farm'
              : 'Needs goats at the farm',
          enabled: lotOk && lot.farmAvailableQty > 0,
          onTap: () => _comingSoon('Transfer to Customer Palai'),
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