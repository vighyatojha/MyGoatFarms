import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/services/sale_adjustment_service.dart';

/// Cancel Deal for an open Booking / Holding or Wait for Delivery.
///
/// One screen, four clear parts, read top to bottom:
///  1. The deal  — who, how many goats, booked when, deal value, advance.
///  2. What happens — exactly what cancelling changes (goats, lists,
///     dashboard, archive). Nothing is hidden.
///  3. The advance — Refund all / Keep all / Refund part, with the
///     refund method and a live line saying what Finance will show.
///     Booking / Holding also offers "keep holding charges so far".
///  4. Why — quick reasons plus an optional note (saved in the archive
///     and the activity log).
///
/// The save runs inside the sheet, so an error is shown in place and
/// nothing typed is lost. Returns the [CancelDealOutcome] on success, or
/// null when the person backs out.
Future<CancelDealOutcome?> showCancelDealSheet(
    BuildContext context, {
      required String farmId,
      required Sale sale,
    }) {
  return showModalBottomSheet<CancelDealOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CancelDealSheet(farmId: farmId, sale: sale),
  );
}

enum _AdvanceChoice { refundAll, keepAll, refundPart }

class _CancelDealSheet extends StatefulWidget {
  final String farmId;
  final Sale sale;

  const _CancelDealSheet({required this.farmId, required this.sale});

  @override
  State<_CancelDealSheet> createState() => _CancelDealSheetState();
}

class _CancelDealSheetState extends State<_CancelDealSheet> {
  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  static final DateFormat _date = DateFormat('dd MMM yyyy');

  static const List<String> _methods = ['Cash', 'UPI', 'Bank Transfer'];

  static const List<String> _quickReasons = [
    'Customer backed out',
    'Price not agreed',
    'Goat sick or died',
    'Customer not reachable',
    'Entered by mistake',
  ];

  final TextEditingController _refundController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  _AdvanceChoice _choice = _AdvanceChoice.refundAll;
  String _method = 'Cash';
  String? _quickReason;
  bool _saving = false;
  String? _error;

  Sale get _sale => widget.sale;

  double get _advance => SaleAdjustmentService.instance.advanceOf(_sale);

  bool get _hasAdvance => _advance > 0;

  // ---------------------------------------------------------------------
  // HOLDING CHARGES SO FAR (Booking / Holding only)
  // ---------------------------------------------------------------------

  double get _holdingRate =>
      _sale.isBooking ? (_sale.holdingChargePerDay ?? 0) : 0;

  int get _holdingDays => _sale.isBooking
      ? Sale.holdingDaysBetween(_sale.holdingStart, DateTime.now())
      : 0;

  double get _holdingSoFar => _round2(_holdingRate * _holdingDays);

  // ---------------------------------------------------------------------
  // MONEY
  // ---------------------------------------------------------------------

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  double get _typedRefund =>
      double.tryParse(_refundController.text.trim()) ?? 0;

  /// What goes back to the customer for the current choice.
  double get _refund {
    if (!_hasAdvance) return 0;

    switch (_choice) {
      case _AdvanceChoice.refundAll:
        return _advance;
      case _AdvanceChoice.keepAll:
        return 0;
      case _AdvanceChoice.refundPart:
        return _round2(_typedRefund);
    }
  }

  double get _kept {
    final v = _round2(_advance - _refund);
    return v < 0 ? 0 : v;
  }

  /// Why the part refund cannot be saved yet, or null.
  String? get _partError {
    if (_choice != _AdvanceChoice.refundPart) return null;

    final text = _refundController.text.trim();
    if (text.isEmpty) return 'Enter how much to give back';

    final v = double.tryParse(text);
    if (v == null) return 'Enter a valid amount';
    if (v <= 0) return 'For no refund, choose "Keep all"';
    if (v >= _advance - 0.005) return 'That is the full advance — choose "Refund all"';

    return null;
  }

  bool get _canConfirm => !_saving && _partError == null;

  String get _reasonText {
    final parts = <String>[
      if (_quickReason != null) _quickReason!,
      if (_noteController.text.trim().isNotEmpty) _noteController.text.trim(),
    ];
    return parts.join(' — ');
  }

  // ---------------------------------------------------------------------
  // LABELS
  // ---------------------------------------------------------------------

  String get _dealType =>
      _sale.isBooking ? 'Booking / Holding' : 'Wait for Delivery';

  String get _goatsLabel {
    final n = _sale.goatCount;
    final goats = '$n goat${n == 1 ? '' : 's'}';

    if (_sale.isLotSale) {
      return '$goats from ${_lotId(_sale.lotDocId)}';
    }

    if (_sale.goatIds.length <= 3) {
      return '$goats · ${_sale.goatIds.join(', ')}';
    }

    return '$goats · ${_sale.goatIds.take(3).join(', ')} +${_sale.goatIds.length - 3}';
  }

  static String _lotId(String docId) {
    final dash = docId.indexOf('-');
    return dash < 0 ? docId : 'LOT-${docId.substring(dash + 1)}';
  }

  String get _goatsGoTo {
    final n = _sale.goatCount;
    final they = n == 1 ? 'The goat goes' : 'The $n goats go';

    if (_sale.isLotSale) {
      final where = _sale.sourceLocation == Sale.sourceSupplier
          ? 'at the supplier'
          : 'at the farm';
      return '$they back into ${_lotId(_sale.lotDocId)} ($where), free to '
          'sell again.';
    }

    return '$they back to the stock they came from (Available or Own '
        'Palai), free to sell again.';
  }

  /// One line saying what Finance will show after the cancel.
  String get _financeLine {
    if (!_hasAdvance) {
      return 'No advance was taken, so Finance does not change.';
    }

    final booking = _sale.isBooking;

    switch (_choice) {
      case _AdvanceChoice.refundAll:
        return booking
            ? 'The ${_inr.format(_advance)} recorded as income on the '
            'booking day is voided in Finance.'
            : 'This advance was never added to Finance, so nothing '
            'changes there.';
      case _AdvanceChoice.keepAll:
        return booking
            ? 'The ${_inr.format(_advance)} already in Finance stays as '
            'income.'
            : '${_inr.format(_advance)} is added to Finance today as '
            'income (advance kept).';
      case _AdvanceChoice.refundPart:
        return _partError != null
            ? 'Finance will keep only the part you do not give back.'
            : 'Finance will show ${_inr.format(_kept)} as income '
            '(cancellation charge). The ${_inr.format(_refund)} given back '
            'is not counted.';
    }
  }

  // ---------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------

  void _setChoice(_AdvanceChoice choice) {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _choice = choice;
      _error = null;
    });
  }

  /// Booking / Holding shortcut: keep the holding charges so far and give
  /// the rest back.
  void _keepHoldingCharges() {
    final keep = _holdingSoFar >= _advance ? _advance : _holdingSoFar;
    final refund = _round2(_advance - keep);

    setState(() {
      _error = null;

      if (refund <= 0) {
        _choice = _AdvanceChoice.keepAll;
      } else if (keep <= 0) {
        _choice = _AdvanceChoice.refundAll;
      } else {
        _choice = _AdvanceChoice.refundPart;
        _refundController.text = refund.toStringAsFixed(
          refund == refund.roundToDouble() ? 0 : 2,
        );
      }
    });
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final outcome = await SaleAdjustmentService.instance.cancelDeal(
        farmId: widget.farmId,
        saleId: _sale.id,
        refundAmount: _refund,
        refundMethod: _method,
        reason: _reasonText,
      );

      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e
            .toString()
            .replaceFirst(RegExp(r'^\w*(Error|Exception): '), '');
      });
    }
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
                  keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _dealCard(),
                    const SizedBox(height: 12),
                    _whatHappensCard(),
                    const SizedBox(height: 12),
                    _advanceCard(),
                    const SizedBox(height: 12),
                    _reasonCard(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _note(
                        _error!,
                        icon: Icons.error_outline_rounded,
                        color: AppColors.error,
                      ),
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
            child: const Icon(
              Icons.event_busy_rounded,
              color: AppColors.error,
              size: 24,
            ),
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
                    Flexible(
                      child: Text(
                        _sale.id,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chip(
                      _dealType,
                      _sale.isBooking ? Colors.deepPurple : AppColors.stockTeal,
                    ),
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
    final date = _sale.saleDate;

    return _card(
      title: 'The deal',
      icon: Icons.receipt_long_outlined,
      children: [
        _row('Customer', _sale.customerName.trim().isEmpty
            ? '—'
            : _sale.customerName.trim()),
        if (_sale.mobile.trim().isNotEmpty) _row('Mobile', _sale.mobile.trim()),
        _row('Goats', _goatsLabel),
        if (date != null) _row('Booked on', _date.format(date)),
        _row(
          _sale.isFixedPrice ? 'Deal value (fixed)' : 'Deal value',
          _inr.format(_sale.totalSaleAmount),
        ),
        const Divider(height: 18, color: AppColors.divider),
        _row(
          _sale.isBooking ? 'Booking amount paid' : 'Advance paid',
          _inr.format(_advance),
          strong: true,
        ),
      ],
    );
  }

  // 2. WHAT HAPPENS --------------------------------------------------------

  Widget _whatHappensCard() {
    final list = _sale.isBooking ? 'Booking / Holding' : 'Wait for Delivery';

    return _card(
      title: 'When you cancel',
      icon: Icons.checklist_rounded,
      children: [
        _step(Icons.undo_rounded, _goatsGoTo),
        _step(
          Icons.playlist_remove_rounded,
          'The deal is removed from the $list list and the dashboard '
              'count goes down.',
        ),
        _step(
          Icons.inventory_2_outlined,
          'A full copy is kept in the archive with the reason, so the '
              'history is never lost.',
        ),
        _step(
          Icons.block_rounded,
          'This cannot be undone. To sell these goats again, make a new '
              'sale.',
          color: AppColors.error,
        ),
      ],
    );
  }

  // 3. THE ADVANCE ---------------------------------------------------------

  Widget _advanceCard() {
    if (!_hasAdvance) {
      return _card(
        title: 'The advance',
        icon: Icons.payments_outlined,
        children: [
          _note(
            'No advance was taken for this deal, so no money changes '
                'hands and Finance does not change.',
            icon: Icons.info_outline_rounded,
            color: AppColors.info,
          ),
        ],
      );
    }

    final showHoldingShortcut =
        _sale.isBooking && _holdingRate > 0 && _holdingSoFar > 0;

    return _card(
      title: 'The advance — ${_inr.format(_advance)}',
      icon: Icons.payments_outlined,
      children: [
        Text(
          'What happens to the money the customer paid?',
          style: AppTheme.body(size: 12, color: AppColors.textDark),
        ),
        const SizedBox(height: 10),
        _choiceTile(
          _AdvanceChoice.refundAll,
          title: 'Refund all',
          subtitle: 'Give the full ${_inr.format(_advance)} back.',
          icon: Icons.keyboard_return_rounded,
        ),
        const SizedBox(height: 8),
        _choiceTile(
          _AdvanceChoice.keepAll,
          title: 'Keep all',
          subtitle: 'The customer forfeits the advance.',
          icon: Icons.savings_outlined,
        ),
        const SizedBox(height: 8),
        _choiceTile(
          _AdvanceChoice.refundPart,
          title: 'Refund part',
          subtitle: 'Keep a cancellation charge, give the rest back.',
          icon: Icons.call_split_rounded,
        ),
        if (showHoldingShortcut) ...[
          const SizedBox(height: 10),
          Material(
            color: Colors.deepPurple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _saving ? null : _keepHoldingCharges,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.home_work_outlined,
                      size: 18,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keep holding charges so far: $_holdingDays '
                            'day${_holdingDays == 1 ? '' : 's'} × '
                            '${_inr.format(_holdingRate)} = '
                            '${_inr.format(_holdingSoFar)}',
                        style: AppTheme.body(
                          size: 11.5,
                          color: AppColors.textDark,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      'Apply',
                      style: AppTheme.heading(
                        size: 12,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (_choice == _AdvanceChoice.refundPart) ...[
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
              label: 'Give back to customer',
              icon: Icons.currency_rupee_rounded,
              helper: 'Out of ${_inr.format(_advance)}',
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
            'Refund paid by',
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _methods)
                ChoiceChip(
                  label: Text(m),
                  selected: _method == m,
                  onSelected:
                  _saving ? null : (_) => setState(() => _method = m),
                  selectedColor: AppColors.lightGreen,
                  labelStyle: AppTheme.body(
                    size: 12,
                    color: _method == m
                        ? AppColors.darkGreen
                        : AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _note(
          _financeLine,
          icon: Icons.account_balance_outlined,
          color: AppColors.darkGreen,
        ),
      ],
    );
  }

  /// "Customer gets back ₹X  |  Farm keeps ₹Y" — always visible, so the
  /// split is never a surprise.
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
                child: Text(
                  _inr.format(value),
                  style: AppTheme.heading(size: 16, color: color),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final partInvalid = _partError != null;

    return Row(
      children: [
        half(
          'Customer gets back',
          partInvalid ? 0 : _refund,
          AppColors.info,
        ),
        const SizedBox(width: 8),
        half(
          'Farm keeps',
          partInvalid ? 0 : _kept,
          AppColors.darkGreen,
        ),
      ],
    );
  }

  Widget _choiceTile(
      _AdvanceChoice value, {
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
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.darkGreen : AppColors.textGrey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.heading(
                        size: 13.5,
                        color: selected
                            ? AppColors.darkGreen
                            : AppColors.textDark,
                      ),
                    ),
                    Text(subtitle, style: AppTheme.body(size: 11)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 4. WHY -----------------------------------------------------------------

  Widget _reasonCard() {
    return _card(
      title: 'Why is it cancelled?',
      icon: Icons.edit_note_rounded,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _quickReasons)
              ChoiceChip(
                label: Text(r),
                selected: _quickReason == r,
                onSelected: _saving
                    ? null
                    : (on) => setState(() => _quickReason = on ? r : null),
                selectedColor: AppColors.lightGreen,
                labelStyle: AppTheme.body(
                  size: 11.5,
                  color: _quickReason == r
                      ? AppColors.darkGreen
                      : AppColors.textDark,
                  weight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          enabled: !_saving,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(
            label: 'Note (optional)',
            icon: Icons.notes_rounded,
          ),
        ),
        if (_quickReason == 'Entered by mistake')
          _note(
            'If this deal should not exist at all, Delete Sale removes it '
                'the same way and refunds the full advance.',
            icon: Icons.lightbulb_outline_rounded,
            color: AppColors.warning,
          ),
      ],
    );
  }

  // BOTTOM BAR --------------------------------------------------------------

  Widget _bottomBar() {
    final label = !_hasAdvance
        ? 'Cancel Deal'
        : _refund > 0
        ? 'Cancel & Refund ${_inr.format(_refund)}'
        : 'Cancel & Keep ${_inr.format(_kept)}';

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
                    onPressed:
                    _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.darkGreen,
                      side: BorderSide(
                        color: AppColors.primaryGreen.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Keep Deal',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
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
                      disabledBackgroundColor:
                      AppColors.error.withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
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

  Widget _card({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
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
              Expanded(
                child: Text(title, style: AppTheme.heading(size: 14.5)),
              ),
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
          SizedBox(
            width: 128,
            child: Text(label, style: AppTheme.body(size: 12)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: strong
                  ? AppTheme.heading(size: 14.5, color: AppColors.darkGreen)
                  : AppTheme.body(
                size: 12.5,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
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
              child: Text(
                text,
                style: AppTheme.body(size: 12, color: AppColors.textDark),
              ),
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
            child: Text(
              text,
              style: AppTheme.body(size: 11.5, color: AppColors.textDark),
            ),
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
      child: Text(
        text,
        style: AppTheme.body(size: 10.5, color: color, weight: FontWeight.w600),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? helper,
  }) {
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