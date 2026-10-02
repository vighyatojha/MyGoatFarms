import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/goat_model.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/models/wait_delivery_group.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/wait_booking_split_service.dart';

/// Edit Booking for a Wait on Delivery booking.
///
/// Lets the person pick how many (or which) goats are delivered now and
/// what happens to the rest — keep them on a booking, or take them off it
/// and return them to stock. Saving trims the booking to the goats being
/// delivered (see [WaitBookingSplitService]); delivery itself is then done
/// from the Wait on Delivery screen as usual.
///
/// Returns the [WaitBookingSplitResult] when the booking was changed, or
/// null when the sheet was dismissed.
Future<WaitBookingSplitResult?> showEditWaitBookingSheet(
    BuildContext context, {
      required String farmId,
      required WaitDeliverySale entry,
    }) {
  return showModalBottomSheet<WaitBookingSplitResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditWaitBookingSheet(farmId: farmId, entry: entry),
  );
}

class _EditWaitBookingSheet extends StatefulWidget {
  final String farmId;
  final WaitDeliverySale entry;

  const _EditWaitBookingSheet({
    required this.farmId,
    required this.entry,
  });

  @override
  State<_EditWaitBookingSheet> createState() => _EditWaitBookingSheetState();
}

class _EditWaitBookingSheetState extends State<_EditWaitBookingSheet> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Individual-goat booking: the goats going out now.
  late final Set<String> _deliverIds =
  widget.entry.goats.map((goat) => goat.id).toSet();

  /// Lot booking: how many of the held goats go out now.
  late int _qty = widget.entry.goatCount;

  LeftoverGoatsAction _action = LeftoverGoatsAction.keepBooked;

  final TextEditingController _advance = TextEditingController();
  final TextEditingController _fixed = TextEditingController();

  /// Until the person types in a field it follows the proportional share.
  bool _advanceEdited = false;
  bool _fixedEdited = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshDefaults();
  }

  @override
  void dispose() {
    _advance.dispose();
    _fixed.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // STATE HELPERS
  // ---------------------------------------------------------------------

  WaitDeliverySale get _entry => widget.entry;

  Sale get _sale => widget.entry.sale;

  int get _total => _entry.goatCount;

  int get _deliverCount => _entry.isLotSale ? _qty : _deliverIds.length;

  int get _leftCount => _total - _deliverCount;

  /// True when at least one goat goes out and at least one is left over.
  bool get _changed => _deliverCount > 0 && _leftCount > 0;

  bool get _keep => _action == LeftoverGoatsAction.keepBooked;

  String _goats(int count) => count == 1 ? '1 goat' : '$count goats';

  String _plain(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  double get _share {
    if (_entry.isLotSale) {
      return WaitBookingSplitService.shareOf(
        deliverCount: _qty,
        totalCount: _total,
      );
    }

    return WaitBookingSplitService.shareOf(
      deliverCount: _deliverCount,
      totalCount: _total,
      deliverWeights: [
        for (final goat in _entry.goats)
          if (_deliverIds.contains(goat.id)) goat.weight,
      ],
      leftoverWeights: [
        for (final goat in _entry.goats)
          if (!_deliverIds.contains(goat.id)) goat.weight,
      ],
    );
  }

  double? _typed(TextEditingController controller) {
    final text = controller.text.trim();

    if (text.isEmpty) return null;

    return double.tryParse(text);
  }

  double? get _advanceOverride =>
      _advanceEdited && _keep ? _typed(_advance) : null;

  double? get _fixedOverride =>
      _fixedEdited && _sale.isFixedPrice ? _typed(_fixed) : null;

  WaitBookingSplitFigures get _figures {
    return WaitBookingSplitService.figures(
      sale: _sale,
      share: _share,
      action: _action,
      deliverAdvance: _advanceOverride,
      deliverFixedPrice: _fixedOverride,
    );
  }

  /// Keeps the money fields on the proportional default until the person
  /// types their own figure.
  void _refreshDefaults() {
    final defaults = WaitBookingSplitService.figures(
      sale: _sale,
      share: _share,
      action: _action,
    );

    if (!_advanceEdited) {
      _advance.text = _plain(defaults.deliverAdvance);
    }

    final fixed = defaults.deliverFixedPrice;

    if (!_fixedEdited && fixed != null) {
      _fixed.text = _plain(fixed);
    }
  }

  String? get _advanceError {
    if (!_changed || !_keep || !_advanceEdited) return null;

    final typed = _typed(_advance);
    final total = _sale.bookingAdvanceAmount ?? 0;

    if (typed == null) return 'Enter an amount';
    if (typed > total) return 'More than the advance paid';

    return null;
  }

  String? get _fixedError {
    if (!_changed || !_sale.isFixedPrice || !_fixedEdited) return null;

    final typed = _typed(_fixed);
    final total = _sale.fixedSalePrice ?? 0;

    if (typed == null || typed <= 0) return 'Enter the price';
    if (typed > total) return 'More than the agreed price';

    return null;
  }

  bool get _valid =>
      _changed && _advanceError == null && _fixedError == null;

  // ---------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------

  Future<void> _save() async {
    if (_saving || !_valid) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await WaitBookingSplitService.instance.splitBooking(
        farmId: widget.farmId,
        saleId: _entry.id,
        deliverGoatIds:
        _entry.isLotSale ? null : Set<String>.from(_deliverIds),
        deliverQuantity: _entry.isLotSale ? _qty : null,
        leftover: _action,
        deliverAdvance: _advanceOverride,
        deliverFixedPrice: _fixedOverride,
      );

      if (!mounted) return;

      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = e is StateError
            ? e.message
            : FirestoreService.instance.describeError(e);
      });
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Edit booking ${_entry.id}',
                    style: AppTheme.heading(size: 16),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_sale.customerName} · ${_goats(_total)} booked. '
                        'Choose what goes out now.',
                    style: AppTheme.body(size: 11),
                  ),
                  const SizedBox(height: 14),
                  _pickGoats(),
                  if (_leftCount > 0 && _deliverCount > 0) ...[
                    const SizedBox(height: 14),
                    _leftoverChoice(),
                    const SizedBox(height: 14),
                    _moneyBox(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.error,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Nothing is delivered yet. After saving, deliver the '
                        'booking from the Wait on Delivery screen as usual.',
                    style: AppTheme.body(size: 10),
                  ),
                  const SizedBox(height: 14),
                  _buttons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 1. WHICH GOATS GO OUT NOW
  // ---------------------------------------------------------------------

  Widget _sectionTitle(String text) {
    return Text(text, style: AppTheme.heading(size: 12.5));
  }

  Widget _pickGoats() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Goats to deliver now'),
          const SizedBox(height: 6),
          if (_entry.isLotSale) _lotStepper() else _goatChecklist(),
        ],
      ),
    );
  }

  Widget _lotStepper() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sale.lotDisplayId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(size: 13),
              ),
              Text(
                '$_qty of ${_goats(_total)} held from this lot',
                style: AppTheme.body(size: 10.5),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Fewer',
          onPressed: _saving || _qty <= 1
              ? null
              : () {
            setState(() {
              _qty--;
              _refreshDefaults();
            });
          },
          icon: const Icon(Icons.remove_circle_outline),
          color: AppColors.darkGreen,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$_qty',
            textAlign: TextAlign.center,
            style: AppTheme.heading(size: 16),
          ),
        ),
        IconButton(
          tooltip: 'More',
          onPressed: _saving || _qty >= _total
              ? null
              : () {
            setState(() {
              _qty++;
              _refreshDefaults();
            });
          },
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.darkGreen,
        ),
      ],
    );
  }

  Widget _goatChecklist() {
    return Column(
      children: [
        for (final goat in _entry.goats) _goatTile(goat),
      ],
    );
  }

  Widget _goatTile(Goat goat) {
    final breed =
    goat.breed.trim().isEmpty ? 'Breed not specified' : goat.breed.trim();

    final weight = goat.weight > 0 ? ' · ${_trim(goat.weight)} kg' : '';

    final selected = _deliverIds.contains(goat.id);

    return CheckboxListTile(
      value: selected,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.darkGreen,
      onChanged: _saving
          ? null
          : (value) {
        setState(() {
          if (value == true) {
            _deliverIds.add(goat.id);
          } else if (_deliverIds.length > 1) {
            // At least one goat must go out.
            _deliverIds.remove(goat.id);
          }

          _refreshDefaults();
        });
      },
      title: Text(goat.id, style: AppTheme.heading(size: 13)),
      subtitle: Text(
        '$breed · ${goat.age}$weight',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.body(size: 10.5),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 2. KEEP OR REMOVE THE REST
  // ---------------------------------------------------------------------

  Widget _leftoverChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _leftCount == 1
              ? 'What about the other goat?'
              : 'What about the other $_leftCount goats?',
        ),
        const SizedBox(height: 4),
        _choiceTile(
          value: LeftoverGoatsAction.keepBooked,
          title: 'Keep on booking',
          subtitle: 'They stay waiting for delivery as a new booking for '
              'the same customer, at the same rate.',
        ),
        _choiceTile(
          value: LeftoverGoatsAction.returnToStock,
          title: 'Remove from booking',
          subtitle: 'They go back to stock and are no longer held for '
              'this customer.',
        ),
      ],
    );
  }

  Widget _choiceTile({
    required LeftoverGoatsAction value,
    required String title,
    required String subtitle,
  }) {
    final selected = _action == value;

    return InkWell(
      onTap: _saving
          ? null
          : () {
        setState(() {
          _action = value;
          _refreshDefaults();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.darkGreen.withValues(alpha: 0.07)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.darkGreen.withValues(alpha: 0.6)
                : AppColors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.darkGreen : AppColors.textGrey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.heading(size: 12.5)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: AppTheme.body(size: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 3. HOW THE MONEY SPLITS
  // ---------------------------------------------------------------------

  InputDecoration _decoration(String label, {String? error}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: AppTheme.body(size: 10.5),
      prefixText: '₹ ',
      errorText: error,
      errorStyle: const TextStyle(fontSize: 9.5),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border(AppColors.divider),
      enabledBorder: border(AppColors.divider),
      focusedBorder: border(AppColors.darkGreen, 1.4),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.4),
    );
  }

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required String? error,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: onChanged,
      style: AppTheme.body(
        size: 12.5,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      decoration: _decoration(label, error: error),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: bold
                  ? AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w700,
              )
                  : AppTheme.body(size: 11),
            ),
          ),
          Text(
            value,
            style: AppTheme.body(
              size: 11.5,
              color: AppColors.textDark,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyBox() {
    final money = _figures;
    final fixed = _sale.isFixedPrice;
    final totalAdvance = _sale.bookingAdvanceAmount ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('How the money is split'),
          const SizedBox(height: 4),
          Text(
            fixed
                ? 'This booking has an agreed price, so it is divided '
                'between the goats. You can change the split below.'
                : '${_money.format(_entry.ratePerKg)}/kg stays the same. '
                'The final amount is worked out from the pickup weight '
                'when you deliver.',
            style: AppTheme.body(size: 10.5),
          ),

          if (fixed) ...[
            const SizedBox(height: 10),
            _moneyField(
              controller: _fixed,
              label: 'Agreed price for the goats going out now',
              error: _fixedError,
              onChanged: (_) {
                setState(() {
                  _fixedEdited = true;
                });
              },
            ),
            if (_keep)
              _line(
                'Agreed price for the kept goats',
                _money.format(money.leftFixedPrice ?? 0),
              ),
          ],

          if (totalAdvance > 0) ...[
            const SizedBox(height: 10),
            if (_keep) ...[
              _moneyField(
                controller: _advance,
                label: 'Advance for the goats going out now',
                error: _advanceError,
                onChanged: (_) {
                  setState(() {
                    _advanceEdited = true;
                  });
                },
              ),
              _line(
                'Advance moving to the kept goats',
                _money.format(money.leftAdvance),
              ),
            ] else ...[
              _line(
                'Advance staying with the goats going out',
                _money.format(totalAdvance),
              ),
              const SizedBox(height: 4),
              Text(
                'The goats going back to stock take no advance with them. '
                    'If the advance is more than the final bill you can '
                    'carry the extra to the customer\'s advance or refund '
                    'it when you deliver.',
                style: AppTheme.body(size: 10),
              ),
            ],
          ],

          if (_sale.appliedDiscount > 0) ...[
            const SizedBox(height: 6),
            _line(
              'Discount on the goats going out',
              _money.format(money.deliverDiscount),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // BUTTONS
  // ---------------------------------------------------------------------

  Widget _buttons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textDark,
                side: const BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Cancel', style: AppTheme.heading(size: 13)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _valid && !_saving ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                AppColors.darkGreen.withValues(alpha: 0.3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : Text(
                _changed
                    ? (_keep ? 'Save & keep the rest' : 'Save & remove the rest')
                    : 'Pick fewer goats to edit',
                style: AppTheme.heading(
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}