import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/partner_access_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Opens the Cancel Deal screen after checking the person may pay / settle
/// with suppliers and that the lot can still be cancelled.
///
/// Returns true when the deal was cancelled.
Future<bool?> openCancelLotDealScreen({
  required BuildContext context,
  required String farmId,
  required TradingPurchase lot,
}) async {
  if (!PartnerAccessService.instance
      .allows(PartnerPermissionKeys.tradingSupplierPayment)) {
    wizardSnack(
      context,
      'You don\u2019t have permission to settle with suppliers.',
      error: true,
    );
    return null;
  }

  if (!lot.canCancelDeal) {
    wizardSnack(
      context,
      lot.dealCancelled
          ? 'This deal is already cancelled.'
          : 'A deal can only be cancelled while all goats are still at the '
          'supplier.',
      error: true,
    );
    return null;
  }

  return Navigator.of(context).push<bool>(
    fastRoute(CancelLotDealScreen(farmId: farmId, lot: lot)),
  );
}

/// Cancel Deal — for a lot whose goats are all still at the supplier.
///
/// Whatever was paid to the supplier becomes a settlement:
///
///   loss = paid - refund        (paid 5,000, refunded 4,500 -> loss 500)
///
/// The refund and the loss are two linked text boxes — typing either one
/// fills in the other — and the Paid / Refunded / Loss figures are pinned to
/// the top of the screen and recalculated on every keystroke.
class CancelLotDealScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const CancelLotDealScreen({
    super.key,
    required this.farmId,
    required this.lot,
  });

  @override
  State<CancelLotDealScreen> createState() => _CancelLotDealScreenState();
}

class _CancelLotDealScreenState extends State<CancelLotDealScreen> {
  final _formKey = GlobalKey<FormState>();
  final _refundController = TextEditingController();
  final _lossController = TextEditingController();
  final _noteController = TextEditingController();

  String _method = 'Cash';
  DateTime _date = DateTime.now();
  bool _saving = false;

  TradingPurchase get _lot => widget.lot;

  double get _paid => PurchaseCosting.round2(_lot.paidAmount);

  bool get _nothingPaid => _paid <= 0;

  @override
  void initState() {
    super.initState();

    // Nothing refunded yet: the whole payment is lost until a refund is
    // typed in.
    _refundController.text = '';
    _lossController.text = _nothingPaid ? '' : PurchaseCosting.formatNumber(_paid);
  }

  @override
  void dispose() {
    _refundController.dispose();
    _lossController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // LIVE NUMBERS
  // ---------------------------------------------------------------------

  double get _refund =>
      PurchaseCosting.round2(double.tryParse(_refundController.text.trim()) ?? 0);

  /// Refund typed is more than what was paid.
  bool get _refundTooHigh => _refund > _paid + 0.005;

  /// Paid minus refund; never negative, and 0 while the refund is invalid so
  /// an impossible number is never shown as a "loss".
  double get _loss {
    if (_refundTooHigh) return 0;

    final v = PurchaseCosting.round2(_paid - _refund);
    return v < 0 ? 0 : v;
  }

  String _plain(double v) => v <= 0 ? '' : PurchaseCosting.formatNumber(v);

  /// Typing the refund fills in the loss.
  void _onRefundChanged(String _) {
    final refund = _refund;

    _lossController.text =
    refund > _paid + 0.005 ? '' : PurchaseCosting.formatNumber(_paid - refund);

    setState(() {});
  }

  /// Typing the loss fills in the refund.
  void _onLossChanged(String value) {
    final loss =
    PurchaseCosting.round2(double.tryParse(value.trim()) ?? 0);

    if (loss > _paid + 0.005) {
      _refundController.text = '';
    } else {
      _refundController.text = _plain(PurchaseCosting.round2(_paid - loss));
    }

    setState(() {});
  }

  void _setRefund(double value) {
    _refundController.text = _plain(value);
    _lossController.text = PurchaseCosting.formatNumber(_paid - value);
    setState(() {});
  }

  // ---------------------------------------------------------------------
  // DATE
  // ---------------------------------------------------------------------

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final purchaseDay = DateTime(
      _lot.purchaseDate.year,
      _lot.purchaseDate.month,
      _lot.purchaseDate.day,
    );

    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _date,
      firstDate: purchaseDay,
      lastDate: _today,
      helpText: 'Cancellation date',
    );

    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  // ---------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_refundTooHigh) {
      _fail('Refund cannot be more than ${wizardCurrency(_paid)} paid.');
      return;
    }

    final confirmed = await showWizardConfirm(
      context: context,
      title: 'Cancel this deal?',
      message: _nothingPaid
          ? '${_lot.lotId} will be cancelled. Nothing was paid, so there is '
          'no refund and no loss. This cannot be undone.'
          : '${_lot.lotId} will be cancelled.\n\n'
          'Paid ${wizardCurrency(_paid)}  •  Refund ${wizardCurrency(_refund)}'
          '\nLoss to the farm: ${wizardCurrency(_loss)}\n\n'
          'This cannot be undone.',
      confirmLabel: 'Cancel deal',
      cancelLabel: 'Go back',
      destructive: true,
      icon: Icons.cancel_outlined,
    );

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);

    try {
      await TradingService.instance.cancelLotDeal(
        farmId: widget.farmId,
        lotDocId: _lot.id,
        refundAmount: _nothingPaid ? 0 : _refund,
        refundMethod: _method,
        date: _date,
        note: _noteController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      _fail(e.message?.toString() ?? 'Please check the refund.');
    } on StateError catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail(FirestoreService.instance.describeError(e));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _saving = false);
    wizardSnack(context, message, error: true);
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lot = _lot;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(title: Text('Cancel ${lot.lotId}')),
      body: Column(
        children: [
          // Pinned: stays at the top while the form scrolls.
          _liveSettlement(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  WizardNote(
                    'All ${lot.supplierQty} goats are still at the supplier. '
                        'Cancelling closes the lot as Deal Cancelled, stops '
                        'counting its goats and cancels the amount owed to '
                        'the supplier.',
                  ),
                  const SizedBox(height: 14),
                  _dealCard(),
                  const SizedBox(height: 14),
                  _settlementCard(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Cancel Deal & Settle',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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

  /// Paid / Refunded / Loss, recalculated on every keystroke.
  Widget _liveSettlement() {
    final loss = _loss;
    final lossColor = _refundTooHigh
        ? AppColors.textGrey
        : loss >= 0.01
        ? AppColors.error
        : AppColors.success;

    Widget cell(String label, String value, Color color) {
      return Expanded(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: AppTheme.heading(size: 18, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTheme.body(size: 11)),
          ],
        ),
      );
    }

    Widget sign(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        s,
        style: AppTheme.heading(size: 18, color: AppColors.textGrey),
      ),
    );

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settlement (live)', style: AppTheme.heading(size: 13)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                cell('Paid to supplier', wizardCurrency(_paid),
                    AppColors.textDark),
                sign('\u2212'),
                cell(
                  'Refunded',
                  wizardCurrency(_refundTooHigh ? 0 : _refund),
                  AppColors.success,
                ),
                sign('='),
                cell('Loss to farm', wizardCurrency(loss), lossColor),
              ],
            ),
            if (_refundTooHigh) ...[
              const SizedBox(height: 8),
              Text(
                'Refund is more than the ${wizardCurrency(_paid)} paid.',
                style: AppTheme.body(size: 11, color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dealCard() {
    final lot = _lot;

    return WizardSectionCard(
      title: 'Deal',
      icon: Icons.handshake_outlined,
      children: [
        WizardComputedRow(label: 'Supplier', value: lot.sellerName),
        WizardComputedRow(label: 'Goats', value: '${lot.totalGoats}'),
        WizardComputedRow(
          label: 'Purchase amount',
          value: wizardCurrency(lot.purchaseAmount),
        ),
        const Divider(height: 18, color: AppColors.divider),
        WizardComputedRow(
          label: 'Paid so far',
          value: wizardCurrency(lot.paidAmount),
          emphasize: true,
        ),
      ],
    );
  }

  Widget _settlementCard() {
    return WizardSectionCard(
      title: 'Refund & loss',
      icon: Icons.currency_exchange_rounded,
      children: [
        if (_nothingPaid)
          const WizardNote(
            'Nothing was paid to this supplier, so there is no refund to '
                'receive and no loss.',
          )
        else ...[
          wizardField(
            controller: _refundController,
            label: 'Refund received from supplier',
            hint: '0.00',
            icon: Icons.currency_rupee_rounded,
            optional: true,
            keyboardType: wizardDecimalKeyboard,
            inputFormatters: wizardDecimalFormatters(),
            onChanged: _onRefundChanged,
            validator: (value) {
              final n = double.tryParse(value?.trim() ?? '') ?? 0;

              if (n > _paid + 0.005) {
                return 'Cannot be more than ${wizardCurrency(_paid)}';
              }

              return null;
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('No refund'),
                backgroundColor: AppColors.lightGreen,
                onPressed: () => _setRefund(0),
              ),
              ActionChip(
                label: const Text('Full refund'),
                backgroundColor: AppColors.lightGreen,
                onPressed: () => _setRefund(_paid),
              ),
            ],
          ),
          const SizedBox(height: 14),
          wizardField(
            controller: _lossController,
            label: 'Pending amount (loss due to deal cancel)',
            hint: '0.00',
            icon: Icons.trending_down_rounded,
            optional: true,
            keyboardType: wizardDecimalKeyboard,
            inputFormatters: wizardDecimalFormatters(),
            helper: 'Paid minus refund. Type here instead, and the refund '
                'fills in.',
            onChanged: _onLossChanged,
            validator: (value) {
              final n = double.tryParse(value?.trim() ?? '') ?? 0;

              if (n > _paid + 0.005) {
                return 'Cannot be more than ${wizardCurrency(_paid)}';
              }

              return null;
            },
          ),
          if (_refund > 0 && !_refundTooHigh) ...[
            const SizedBox(height: 14),
            Text('Refund received by', style: AppTheme.body(size: 11)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _methodChip('Cash', Icons.money_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: _methodChip(
                    'Online',
                    Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 14),
        WizardDateField(
          label: 'Cancellation date *',
          date: _date,
          onTap: _pickDate,
        ),
        const SizedBox(height: 14),
        wizardField(
          controller: _noteController,
          label: 'Reason / note',
          hint: 'e.g. Supplier could not deliver',
          icon: Icons.notes_rounded,
          optional: true,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
        ),
      ],
    );
  }

  Widget _methodChip(String title, IconData icon) {
    final selected = _method == title;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _method = title),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.darkGreen : AppColors.textGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 13,
                    color: selected ? AppColors.darkGreen : AppColors.textDark,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.primaryGreen,
                ),
            ],
          ),
        ),
      ),
    );
  }
}