import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/partner_access_service.dart';
import '../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Opens Cancel Deal for a lot after checking the person may settle with
/// suppliers and that the lot can still be cancelled.
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
      'You don’t have permission to settle with suppliers.',
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

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CancelLotDealSheet(farmId: farmId, lot: lot),
  );
}

enum _RefundChoice { full, none, part }

/// Cancel Deal for a lot whose goats are all still at the supplier. Same
/// layout as the Wait on Delivery / Booking Cancel Deal, read top to
/// bottom:
///  1. The deal: supplier, goats, purchase amount, paid so far.
///  2. When you cancel: exactly what changes in the lot, stock and Finance.
///  3. Money paid: Full refund / No refund / Part refund, with a live
///     "Supplier gives back | Farm loses" split and what Finance will show.
///  4. Date and why.
///
/// Saving uses [TradingService.cancelLotDeal] (unchanged):
///   loss = paid - refund
class CancelLotDealSheet extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const CancelLotDealSheet({super.key, required this.farmId, required this.lot});

  @override
  State<CancelLotDealSheet> createState() => _CancelLotDealSheetState();
}

class _CancelLotDealSheetState extends State<CancelLotDealSheet> {
  static final NumberFormat _inr =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  static const List<String> _quickReasons = [
    'Supplier could not deliver',
    'Price changed',
    'Goats not as agreed',
    'Deal called off',
    'Entered by mistake',
  ];

  final TextEditingController _refundController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  _RefundChoice _choice = _RefundChoice.full;
  String _method = 'Cash';
  DateTime _date = DateTime.now();
  String? _quickReason;
  bool _saving = false;
  String? _error;

  TradingPurchase get _lot => widget.lot;

  double get _paid => PurchaseCosting.round2(_lot.paidAmount);
  bool get _hasPaid => _paid > 0;

  // ---------------------------------------------------------------------
  // MONEY
  // ---------------------------------------------------------------------

  double get _typedRefund =>
      PurchaseCosting.round2(double.tryParse(_refundController.text.trim()) ?? 0);

  /// What the supplier gives back for the current choice.
  double get _refund {
    if (!_hasPaid) return 0;
    switch (_choice) {
      case _RefundChoice.full:
        return _paid;
      case _RefundChoice.none:
        return 0;
      case _RefundChoice.part:
        return _typedRefund;
    }
  }

  /// Paid minus refund, never negative.
  double get _loss {
    final v = PurchaseCosting.round2(_paid - _refund);
    return v < 0 ? 0 : v;
  }

  String? get _partError {
    if (_choice != _RefundChoice.part) return null;
    final text = _refundController.text.trim();
    if (text.isEmpty) return 'Enter how much the supplier gave back';
    final v = double.tryParse(text);
    if (v == null) return 'Enter a valid amount';
    if (v <= 0) return 'For nothing back, choose "No refund"';
    if (v >= _paid - 0.005) return 'That is everything paid — choose "Full refund"';
    return null;
  }

  bool get _canConfirm => !_saving && _partError == null;

  String get _noteText {
    final parts = <String>[
      if (_quickReason != null) _quickReason!,
      if (_noteController.text.trim().isNotEmpty) _noteController.text.trim(),
    ];
    return parts.join(' — ');
  }

  String get _financeLine {
    if (!_hasPaid) {
      return 'Nothing was paid to this supplier, so no money changes hands. '
          'Only the goat purchase entry is removed from Finance.';
    }
    if (_partError != null) {
      return 'Finance will show the refund as income and the rest as your loss.';
    }
    if (_refund <= 0) {
      return 'No refund is recorded. The ${_inr.format(_paid)} already paid '
          'stays as money out, so the farm’s loss is ${_inr.format(_loss)}.';
    }
    return 'The ${_inr.format(_refund)} refund is added to Finance as income '
        '(Supplier Refund). The ${_inr.format(_paid)} paid stays as money out, '
        'so the net loss is ${_inr.format(_loss)}.';
  }

  // ---------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------

  void _setChoice(_RefundChoice choice) {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _choice = choice;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(
        _lot.purchaseDate.year,
        _lot.purchaseDate.month,
        _lot.purchaseDate.day,
      ),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Cancellation date',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await TradingService.instance.cancelLotDeal(
        farmId: widget.farmId,
        lotDocId: _lot.id,
        refundAmount: _refund,
        refundMethod: _method,
        date: _date,
        note: _noteText,
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
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  @override
  void dispose() {
    _refundController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: AppColors.paleGreen,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabber(),
              _header(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _dealCard(),
                    const SizedBox(height: 12),
                    _whatHappensCard(),
                    const SizedBox(height: 12),
                    _moneyCard(),
                    const SizedBox(height: 12),
                    _reasonCard(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _note(_error!,
                          icon: Icons.error_outline_rounded, color: AppColors.error),
                    ],
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grabber() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.cancel_outlined, color: AppColors.error, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cancel Deal', style: AppTheme.heading(size: 19)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(_lot.lotId, style: AppTheme.body(size: 12)),
                    const SizedBox(width: 6),
                    _chip('Goat purchase lot', AppColors.info),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textGrey,
          ),
        ],
      ),
    );
  }

  // 1. THE DEAL ------------------------------------------------------------

  Widget _dealCard() {
    final lot = _lot;
    return _card(
      title: 'The deal',
      icon: Icons.receipt_long_outlined,
      children: [
        _row('Supplier', lot.sellerName.trim().isEmpty ? '—' : lot.sellerName.trim()),
        if (lot.mobile.trim().isNotEmpty) _row('Mobile', lot.mobile.trim()),
        _row('Goats', '${lot.totalGoats} (all still at the supplier)'),
        _row('Bought on', _dateFormat.format(lot.purchaseDate)),
        _row(
          lot.isFixedPrice ? 'Purchase amount (fixed)' : 'Purchase amount',
          _inr.format(lot.purchaseAmount),
        ),
        if (lot.dueAmount >= 0.01) _row('Still owed to supplier', _inr.format(lot.dueAmount)),
        const Divider(height: 18, color: AppColors.divider),
        _row('Paid to supplier so far', _inr.format(_paid), strong: true),
      ],
    );
  }

  // 2. WHAT HAPPENS --------------------------------------------------------

  Widget _whatHappensCard() {
    final lot = _lot;
    final n = lot.totalGoats;
    return _card(
      title: 'When you cancel',
      icon: Icons.checklist_rounded,
      children: [
        _step(
          Icons.inventory_2_outlined,
          '${lot.lotId} closes as "Deal Cancelled" and moves to Completed. '
              'Its $n goat${n == 1 ? '' : 's'} stop counting in your stock and '
              'the dashboard.',
        ),
        _step(
          Icons.money_off_rounded,
          lot.dueAmount >= 0.01
              ? 'The ${_inr.format(lot.dueAmount)} still owed to the supplier is '
              'cancelled. You will not owe them anything for this lot.'
              : 'Nothing more is owed to the supplier for this lot.',
        ),
        _step(
          Icons.receipt_outlined,
          'The goat purchase entry for this lot is removed from Finance, '
              'because nothing was bought.',
        ),
        _step(
          Icons.history_rounded,
          'Paid, refunded and loss are saved on the lot with your reason, '
              'so the history is never lost.',
        ),
        _step(
          Icons.block_rounded,
          'This cannot be undone. To buy from this supplier again, create a '
              'new lot.',
          color: AppColors.error,
        ),
      ],
    );
  }

  // 3. MONEY PAID -----------------------------------------------------------

  Widget _moneyCard() {
    if (!_hasPaid) {
      return _card(
        title: 'Money paid',
        icon: Icons.payments_outlined,
        children: [
          _note(
            'Nothing was paid to this supplier, so there is no refund to '
                'receive and no loss.',
            icon: Icons.info_outline_rounded,
            color: AppColors.info,
          ),
        ],
      );
    }

    return _card(
      title: 'Money paid — ${_inr.format(_paid)}',
      icon: Icons.payments_outlined,
      children: [
        Text(
          'What happens to the money you paid the supplier?',
          style: AppTheme.body(size: 12, color: AppColors.textDark),
        ),
        const SizedBox(height: 10),
        _choiceTile(
          _RefundChoice.full,
          title: 'Full refund',
          subtitle: 'The supplier gives back all ${_inr.format(_paid)}. No loss.',
          icon: Icons.keyboard_return_rounded,
        ),
        const SizedBox(height: 8),
        _choiceTile(
          _RefundChoice.none,
          title: 'No refund',
          subtitle: 'The supplier keeps it. The whole amount is your loss.',
          icon: Icons.money_off_rounded,
        ),
        const SizedBox(height: 8),
        _choiceTile(
          _RefundChoice.part,
          title: 'Part refund',
          subtitle: 'The supplier gives some back. The rest is your loss.',
          icon: Icons.call_split_rounded,
        ),
        if (_choice == _RefundChoice.part) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _refundController,
            enabled: !_saving,
            autofocus: _refundController.text.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() => _error = null),
            decoration: _inputDecoration(
              label: 'Refund received from supplier',
              icon: Icons.currency_rupee_rounded,
              helper: 'Out of ${_inr.format(_paid)} paid',
            ).copyWith(
              errorText: _refundController.text.isEmpty ? null : _partError,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _splitBar(),
        if (_refund > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Refund received by',
            style: AppTheme.body(size: 11, color: AppColors.textGrey, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const ['Cash', 'Online'])
                ChoiceChip(
                  label: Text(m),
                  selected: _method == m,
                  onSelected: _saving ? null : (_) => setState(() => _method = m),
                  selectedColor: AppColors.lightGreen,
                  labelStyle: AppTheme.body(
                    size: 12,
                    color: _method == m ? AppColors.darkGreen : AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _note(_financeLine, icon: Icons.account_balance_outlined, color: AppColors.darkGreen),
      ],
    );
  }

  /// "Supplier gives back ₹X | Farm loses ₹Y": always visible.
  Widget _splitBar() {
    Widget half(String label, double value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.body(size: 10.5)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_inr.format(value), style: AppTheme.heading(size: 16, color: color)),
              ),
            ],
          ),
        ),
      );
    }

    final invalid = _partError != null;
    return Row(
      children: [
        half('Supplier gives back', invalid ? 0 : _refund, AppColors.success),
        const SizedBox(width: 8),
        half('Farm loses', invalid ? 0 : _loss, AppColors.error),
      ],
    );
  }

  Widget _choiceTile(
      _RefundChoice value, {
        required String title,
        required String subtitle,
        required IconData icon,
      }) {
    final selected = _choice == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saving ? null : () => _setChoice(value),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.darkGreen : AppColors.textGrey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.heading(
                        size: 13.5,
                        color: selected ? AppColors.darkGreen : AppColors.textDark,
                      ),
                    ),
                    Text(subtitle, style: AppTheme.body(size: 11)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 4. DATE AND WHY ---------------------------------------------------------

  Widget _reasonCard() {
    return _card(
      title: 'When and why?',
      icon: Icons.edit_note_rounded,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _saving ? null : _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined, size: 20, color: AppColors.darkGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Cancellation date', style: AppTheme.body(size: 12)),
                  ),
                  Text(
                    _dateFormat.format(_date),
                    style: AppTheme.heading(size: 13, color: AppColors.textDark),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _quickReasons)
              ChoiceChip(
                label: Text(r),
                selected: _quickReason == r,
                onSelected:
                _saving ? null : (on) => setState(() => _quickReason = on ? r : null),
                selectedColor: AppColors.lightGreen,
                labelStyle: AppTheme.body(
                  size: 11.5,
                  color: _quickReason == r ? AppColors.darkGreen : AppColors.textDark,
                  weight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          enabled: !_saving,
          maxLength: 160,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(label: 'Note (optional)', icon: Icons.notes_rounded),
        ),
      ],
    );
  }

  // BOTTOM BAR --------------------------------------------------------------

  Widget _bottomBar() {
    final label = !_hasPaid
        ? 'Cancel Deal'
        : _refund > 0
        ? 'Cancel · Refund ${_inr.format(_refund)}'
        : 'Cancel · Loss ${_inr.format(_loss)}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.darkGreen,
                      side: BorderSide(color: AppColors.primaryGreen.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Keep Deal', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _canConfirm ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.error.withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // SMALL PIECES ------------------------------------------------------------

  Widget _card({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.darkGreen),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTheme.heading(size: 14.5))),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: AppTheme.body(size: 12))),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: strong
                  ? AppTheme.heading(size: 14.5, color: AppColors.darkGreen)
                  : AppTheme.body(size: 12.5, color: AppColors.textDark, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.darkGreen;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: AppTheme.body(size: 12, color: AppColors.textDark)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text, {required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTheme.body(size: 11.5, color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: AppTheme.body(size: 10.5, color: color, weight: FontWeight.w600)),
    );
  }

  InputDecoration _inputDecoration({required String label, required IconData icon, String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon, size: 20, color: AppColors.darkGreen),
      filled: true,
      fillColor: Colors.white,
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.4),
      ),
    );
  }
}