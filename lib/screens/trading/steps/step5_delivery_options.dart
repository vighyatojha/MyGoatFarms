import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/expense_categories.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../../../models/sale_settlement.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 5 — Delivery Options (the branch).
///
/// Built as four independent sub-tasks per the plan, not one mega-form.
/// All four branches' creation forms are wired up:
///  - A: Deliver Now
///  - B: Booking / Holding
///  - C: Wait for Delivery
///  - D: Transfer to Palai
///
/// Each branch's own "Complete Delivery" follow-up action (B and C only)
/// is out of scope for this phase per the plan's Pair 7 note — this step
/// only ever creates the sale in its initial state (Booked /
/// WaitForDelivery), never completes it.
///
/// LIVE CALCULATIONS: every input writes into the [SaleDraft] on each
/// keystroke (see the `_sync*` methods). The summary cards read the same
/// draft getters that the save step uses, so what the person sees while
/// typing is exactly what gets saved — there is no second copy of the
/// maths on this screen.
///
/// SELL ON CREDIT: every branch has a "Sell on Credit" switch. The unpaid
/// part of the sale becomes the customer's outstanding balance (see
/// [SaleDraft.onCredit]). Deliver Now and Transfer to Palai require
/// the full amount unless it is on; Booking and Wait for Delivery keep the
/// choice and the balance left after delivery is the credit.
///
/// LOT EXCESS PAYMENT:
/// When a Sell From Lot delivery receives more than the final customer
/// total, the user MUST choose exactly one action:
///  - Add the excess to the customer's Advance
///  - Return the excess to the customer
///
/// The two choices are displayed as checkboxes but behave mutually
/// exclusively, so only one can be selected at a time.
///
/// Exposes [validate] via its State (same pattern as earlier steps) so
/// the wizard's Save action can block until the selected branch's
/// required fields are filled in.
class Step5DeliveryOptions extends StatefulWidget {
  final SaleDraft draft;

  /// Shows only the Transfer to Palai form, with no other delivery
  /// branch to pick. Used by the lot -> Customer Palai transfer, where
  /// the goats are being registered and boarded, so the sale can be
  /// nothing else. The draft's delivery type is set to Palai on entry.
  final bool palaiOnly;

  /// Lot sales only. A lot's goats are anonymous, so a Palai transfer
  /// cannot be saved from this form — each goat needs its own record.
  /// When this is given, goats at the farm get a "Transfer to Palai"
  /// card that calls it (the lot wizard opens the lot's Palai transfer
  /// wizard) instead of selecting a branch here.
  final VoidCallback? onTransferToPalai;

  const Step5DeliveryOptions({
    super.key,
    required this.draft,
    this.palaiOnly = false,
    this.onTransferToPalai,
  });

  @override
  State<Step5DeliveryOptions> createState() =>
      Step5DeliveryOptionsState();
}

class Step5DeliveryOptionsState extends State<Step5DeliveryOptions> {
  final GlobalKey<FormState> _deliverNowFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _bookingFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _waitForDeliveryFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _palaiFormKey = GlobalKey<FormState>();

  late final TextEditingController _transportCostController;
  late final TextEditingController _deliveryDiscountController;
  late final TextEditingController _amountReceivedController;

  late final TextEditingController _bookingAmountController;
  late final TextEditingController _holdingChargePerDayController;

  late final TextEditingController _bookingAdvanceController;

  late final TextEditingController _monthlyChargeController;
  late final TextEditingController _palaiAmountReceivedController;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _trimZero(double value) {
    return value == 0
        ? ''
        : value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _transportCostController = TextEditingController(
      text: _trimZero(draft.transportCost),
    );

    _deliveryDiscountController = TextEditingController(
      text: _trimZero(draft.deliveryDiscount),
    );

    _amountReceivedController = TextEditingController(
      text: _trimZero(draft.amountReceived),
    );

    _bookingAmountController = TextEditingController(
      text: _trimZero(draft.bookingAmount),
    );

    _holdingChargePerDayController = TextEditingController(
      text: _trimZero(draft.holdingChargePerDay),
    );

    _bookingAdvanceController = TextEditingController(
      text: _trimZero(draft.bookingAdvanceAmount),
    );

    _monthlyChargeController = TextEditingController(
      text: _trimZero(draft.monthlyPalaiCharge),
    );

    _palaiAmountReceivedController = TextEditingController(
      text: _trimZero(draft.palaiAmountReceived),
    );

    draft.transferDate ??= DateTime.now();

    if (widget.palaiOnly) {
      draft.deliveryType = Sale.deliveryTypePalai;
    }

    _settleLotDeliveryType();

    // The package is picked from a fixed list, so it always holds one of
    // them — the first until the person chooses another.
    if (!SaleDraft.palaiPackages.contains(draft.palaiPackage)) {
      draft.palaiPackage = SaleDraft.palaiPackages.first;
    }
  }

  // ===========================================================================
  // LOT SALES — which options are offered
  // ===========================================================================

  bool get _isLot => widget.draft.isLotSale;

  bool get _fromSupplier =>
      _isLot && widget.draft.sourceLocation == Sale.sourceSupplier;

  bool get _offersHolding => !_fromSupplier;

  bool get _offersPalai => !_isLot || widget.palaiOnly;

  /// A lot sale at the farm shows a Transfer to Palai card that hands
  /// over to the lot's own Palai transfer wizard.
  bool get _showsLotPalaiCard =>
      _isLot &&
          !_fromSupplier &&
          !widget.palaiOnly &&
          widget.onTransferToPalai != null;

  /// Whether [type] may be used for this sale.
  bool _isAllowed(String type) {
    // Palai-only (lot -> Customer Palai transfer): nothing else is valid.
    if (widget.palaiOnly) {
      return type == Sale.deliveryTypePalai;
    }

    if (type == Sale.deliveryTypeDeliverNow) {
      return true;
    }

    if (type == Sale.deliveryTypeBooking ||
        type == Sale.deliveryTypeWaitForDelivery) {
      return _offersHolding;
    }

    if (type == Sale.deliveryTypePalai) {
      return _offersPalai;
    }

    return false;
  }

  /// Drops a choice the current lot source no longer allows.
  void _settleLotDeliveryType() {
    if (!_isLot) return;

    final draft = widget.draft;

    if (_fromSupplier) {
      if (draft.deliveryType != Sale.deliveryTypeDeliverNow) {
        draft.onCredit = false;
        draft.deliveryType = Sale.deliveryTypeDeliverNow;
      }
      return;
    }

    if (draft.deliveryType.isNotEmpty &&
        !_isAllowed(draft.deliveryType)) {
      draft.onCredit = false;
      draft.deliveryType = '';
    }
  }

  String _theGoats(SaleDraft draft) =>
      draft.saleGoatCount > 1 ? 'the goats' : 'the goat';

  String _isAre(SaleDraft draft) =>
      draft.saleGoatCount > 1 ? 'are' : 'is';

  @override
  void dispose() {
    _transportCostController.dispose();
    _deliveryDiscountController.dispose();
    _amountReceivedController.dispose();
    _bookingAmountController.dispose();
    _holdingChargePerDayController.dispose();
    _bookingAdvanceController.dispose();
    _monthlyChargeController.dispose();
    _palaiAmountReceivedController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // LIVE SYNC — controllers -> draft
  // ===========================================================================

  double _money(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  void _syncDeliverNow() {
    final draft = widget.draft;

    draft.transportCost = _money(_transportCostController);
    draft.deliveryDiscount = _money(_deliveryDiscountController);
    draft.amountReceived = _money(_amountReceivedController);

    // An excess action only makes sense while there is actually
    // an excess amount.
    //
    // If the user previously selected Advance/Refund and then reduces
    // Amount Received so that there is no longer an excess, clear the
    // old selection.
    if (!_isLot || draft.extraReceivedDeliverNow <= 0) {
      draft.clearExcessAction();
    }
  }

  void _syncBooking() {
    final draft = widget.draft;

    draft.bookingAmount = _money(_bookingAmountController);
    draft.holdingChargePerDay = _money(_holdingChargePerDayController);
  }

  void _syncWaitForDelivery() {
    final draft = widget.draft;

    draft.bookingAdvanceAmount = _money(_bookingAdvanceController);
  }

  void _syncPalai() {
    final draft = widget.draft;

    draft.monthlyPalaiCharge = _money(_monthlyChargeController);
    draft.palaiAmountReceived = _money(_palaiAmountReceivedController);
  }

  // ===========================================================================
  // VALIDATE
  // ===========================================================================

  bool validate() {
    final draft = widget.draft;

    if (draft.deliveryType.isEmpty) {
      wizardSnack(
        context,
        'Choose a delivery option to continue.',
        error: true,
      );
      return false;
    }

    // Backstop for the UI: SalesService also rejects these.
    if (!_isAllowed(draft.deliveryType)) {
      wizardSnack(
        context,
        _fromSupplier
            ? 'Goats still at the supplier can only be sold with '
            'Deliver Now.'
            : 'This delivery option is not available for a lot sale.',
        error: true,
      );
      return false;
    }

    if (draft.isDeliverNow) {
      final valid =
          _deliverNowFormKey.currentState?.validate() ?? false;

      if (!valid) return false;

      _syncDeliverNow();

      // IMPORTANT:
      // Sell From Lot allows the customer to have paid more than
      // the final customer total, but the user must explicitly
      // decide what happens to that excess.
      if (_isLot && draft.extraReceivedDeliverNow > 0) {
        if (!draft.hasExcessActionSelected) {
          wizardSnack(
            context,
            'Choose what to do with the remaining '
                '${_currency(draft.extraReceivedDeliverNow)}.',
            error: true,
          );
          return false;
        }
      }

      return true;
    }

    if (draft.isBooking) {
      final valid =
          _bookingFormKey.currentState?.validate() ?? false;

      if (!valid) return false;

      _syncBooking();

      return true;
    }

    if (draft.isWaitForDelivery) {
      final valid =
          _waitForDeliveryFormKey.currentState?.validate() ?? false;

      if (!valid) return false;

      _syncWaitForDelivery();

      return true;
    }

    if (draft.isPalaiTransfer) {
      final valid =
          _palaiFormKey.currentState?.validate() ?? false;

      if (!valid) return false;

      _syncPalai();

      return true;
    }

    return false;
  }

  // ===========================================================================
  // BRANCH SELECTION
  // ===========================================================================

  void _selectBranch(String type) {
    setState(() {
      // Credit is chosen per option — never carried over from another.
      if (widget.draft.deliveryType != type) {
        widget.draft.onCredit = false;
      }

      widget.draft.deliveryType = type;
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    // The person may have gone back and switched the lot source to the
    // supplier — keep the draft on its only valid option.
    if (_fromSupplier &&
        draft.deliveryType != Sale.deliveryTypeDeliverNow) {
      draft.onCredit = false;
      draft.deliveryType = Sale.deliveryTypeDeliverNow;
    }

    return ListView(
      keyboardDismissBehavior:
      ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (widget.palaiOnly) ...[
          Text(
            draft.saleGoatCount > 1
                ? 'Palai transfer for ${draft.saleGoatCount} goats'
                : 'Palai transfer',
            style: AppTheme.heading(
              size: 14,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The customer keeps boarding ${_theGoats(draft)} here.',
            style: AppTheme.body(size: 12),
          ),
        ] else if (_fromSupplier) ...[
          // Goats still at the supplier can only be handed over now,
          // so there is nothing to choose — go straight to the form.
        ] else ...[
          Text(
            _isLot
                ? 'How are these goats leaving?'
                : draft.saleGoatCount > 1
                ? 'How are these goats leaving the farm?'
                : 'How is this goat leaving the farm?',
            style: AppTheme.heading(
              size: 14,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),

          _BranchCard(
            title: 'Deliver Now',
            subtitle: 'Handed over today, paid on the spot',
            icon: Icons.local_shipping_outlined,
            selected:
            draft.deliveryType == Sale.deliveryTypeDeliverNow,
            onTap: () =>
                _selectBranch(Sale.deliveryTypeDeliverNow),
          ),

          if (_offersHolding) ...[
            const SizedBox(height: 10),
            _BranchCard(
              title: 'Booking / Holding',
              subtitle:
              'Held here after payment, picked up later',
              icon: Icons.bookmark_outline_rounded,
              selected:
              draft.deliveryType == Sale.deliveryTypeBooking,
              onTap: () =>
                  _selectBranch(Sale.deliveryTypeBooking),
            ),
            const SizedBox(height: 10),
            _BranchCard(
              title: 'Wait for Delivery',
              subtitle:
              'Booked now at today\'s rate, weighed at pickup',
              icon: Icons.schedule_outlined,
              selected: draft.deliveryType ==
                  Sale.deliveryTypeWaitForDelivery,
              onTap: () => _selectBranch(
                Sale.deliveryTypeWaitForDelivery,
              ),
            ),
          ],

          if (_offersPalai || _showsLotPalaiCard) ...[
            const SizedBox(height: 10),
            _BranchCard(
              title: 'Transfer to Palai',
              subtitle:
              'Customer keeps boarding ${_theGoats(draft)} here',
              icon: Icons.holiday_village_outlined,
              selected:
              draft.deliveryType == Sale.deliveryTypePalai,
              onTap: _showsLotPalaiCard
                  ? widget.onTransferToPalai!
                  : () =>
                  _selectBranch(Sale.deliveryTypePalai),
            ),
          ],
        ],

        SizedBox(height: _fromSupplier ? 4 : 18),

        if (draft.isDeliverNow)
          _buildDeliverNowForm(draft),

        if (draft.isBooking)
          _buildBookingForm(draft),

        if (draft.isWaitForDelivery)
          _buildWaitForDeliveryForm(draft),

        if (draft.isPalaiTransfer)
          _buildPalaiTransferForm(draft),
      ],
    );
  }

  // ===========================================================================
  // SELL ON CREDIT
  // ===========================================================================

  Widget _creditSwitch(
      SaleDraft draft, {
        required String onText,
        required String offText,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: draft.onCredit
            ? AppColors.error.withValues(alpha: 0.06)
            : AppColors.paleGreen,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sell on Credit',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),
                Text(
                  draft.onCredit ? onText : offText,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: draft.onCredit,
            activeColor: AppColors.error,
            onChanged: (value) {
              setState(() {
                draft.onCredit = value;
              });
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYMENT METHOD
  // ===========================================================================

  Widget _paymentMethodPicker(SaleDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FinancePaymentMethods.all.map((method) {
            final selected = draft.paymentMethod == method;

            return ChoiceChip(
              label: Text(method),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  draft.paymentMethod = method;
                });
              },
              selectedColor:
              AppColors.primaryGreen.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.darkGreen
                    : AppColors.textDark,
              ),
              side: BorderSide(
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.divider,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'How the amount above is being paid now.',
          style: AppTheme.body(
            size: 10,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // LOT EXCESS ACTION
  // ===========================================================================

  /// Shows the required choice when a Sell From Lot customer has paid
  /// more than the final customer total.
  ///
  /// The controls intentionally use CheckboxListTile because the user
  /// requested checkboxes, but the state is mutually exclusive:
  /// selecting one automatically deselects the other.
  Widget _buildLotExcessActionSelector(SaleDraft draft) {
    final extra = draft.extraReceivedDeliverNow;

    if (!_isLot || extra <= 0) {
      return const SizedBox.shrink();
    }

    final selectedAction = draft.excessAction;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        8,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 19,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extra Amount Received',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_currency(extra)} was received above the '
                          'final customer total. Select what should '
                          'happen to this remaining amount.',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value:
            selectedAction == ExcessAction.carryToAdvance,
            controlAffinity:
            ListTileControlAffinity.leading,
            activeColor: AppColors.primaryGreen,
            title: Text(
              'Add remaining amount to customer Advance',
              style: AppTheme.body(
                size: 12,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${_currency(extra)} will be added to '
                  '${_buyer(draft)}\'s customer advance balance.',
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
            onChanged: (value) {
              if (value != true) return;

              setState(() {
                draft.excessAction =
                    ExcessAction.carryToAdvance;
              });
            },
          ),

          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value:
            selectedAction == ExcessAction.refundToCustomer,
            controlAffinity:
            ListTileControlAffinity.leading,
            activeColor: AppColors.primaryGreen,
            title: Text(
              'Return remaining amount to customer',
              style: AppTheme.body(
                size: 12,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${_currency(extra)} will be recorded as money '
                  'returned to ${_buyer(draft)}.',
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
            onChanged: (value) {
              if (value != true) return;

              setState(() {
                draft.excessAction =
                    ExcessAction.refundToCustomer;
              });
            },
          ),

          if (selectedAction == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                2,
                12,
                4,
              ),
              child: Text(
                'Please select one option before saving.',
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.error,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BRANCH A — DELIVER NOW
  // ===========================================================================

  Widget _buildDeliverNowForm(SaleDraft draft) {
    return Form(
      key: _deliverNowFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Deliver Now',
            icon: Icons.local_shipping_outlined,
            children: [
              wizardField(
                controller: _transportCostController,
                label: 'Transportation Charge',
                hint: '0.00',
                icon: Icons.directions_car_outlined,
                suffix: 'Added to bill',
                optional: true,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncDeliverNow),
                validator: (_) => null,
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _deliveryDiscountController,
                label: 'Delivery Discount',
                hint: '0.00',
                icon: Icons.discount_outlined,
                suffix: 'Off goat amount',
                optional: true,
                helper: 'Extra discount given while delivering. '
                    'It comes off the goat amount only, not '
                    'transportation, and adds to any discount '
                    'from Sale Details.',
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncDeliverNow),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  if (text.isEmpty) return null;

                  final number = double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid discount';
                  }

                  final available =
                      draft.saleAmountAfterSaleDiscount;

                  if (SaleDraft.round2(number) > available) {
                    return 'Discount cannot be more than the goat '
                        'amount (${_currency(available)})';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _creditSwitch(
                draft,
                onText: 'Whatever is not paid now is added to '
                    '${_buyer(draft)}\'s outstanding balance.',
                offText:
                'Off — the full amount is received now.',
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _amountReceivedController,
                label: 'Amount Received',
                optional: draft.onCredit,
                helper: draft.onCredit
                    ? 'Leave blank if nothing was received — '
                    'the whole amount stays on credit'
                    : _isLot
                    ? 'Enter the amount actually received. '
                    'If it is more than the customer total, '
                    'you will choose what happens to the '
                    'remaining amount.'
                    : 'The full customer total must be received',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncDeliverNow),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  // Blank counts as 0.
                  final number =
                  text.isEmpty ? 0.0 : double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  // Not on credit -> everything is paid now.
                  //
                  // IMPORTANT:
                  // Do NOT reject an amount above the total.
                  // For lot sales, an excess amount is allowed and
                  // must be handled using the Advance/Refund choice.
                  if (!draft.onCredit &&
                      SaleDraft.round2(number) <
                          draft.customerTotalDeliverNow) {
                    return 'Enter the full '
                        '${_currency(draft.customerTotalDeliverNow)}, '
                        'or turn on Sell on Credit';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _paymentMethodPicker(draft),

              if (_isLot &&
                  draft.extraReceivedDeliverNow > 0) ...[
                const SizedBox(height: 14),
                _buildLotExcessActionSelector(draft),
              ],
            ],
          ),

          const SizedBox(height: 12),

          _buildDeliverNowSummary(draft),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case Sale.paymentStatusPaid:
        return AppColors.success;
      case Sale.paymentStatusPartial:
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }

  String _buyer(SaleDraft draft) {
    final name = draft.customerName.trim();

    return name.isEmpty ? 'the customer' : name;
  }

  // ===========================================================================
  // DELIVER NOW SUMMARY
  // ===========================================================================

  Widget _buildDeliverNowSummary(SaleDraft draft) {
    final status = draft.paymentStatusDeliverNow;
    final extra = draft.extraReceivedDeliverNow;
    final remaining = draft.remainingBalanceDeliverNow;
    final onCreditBalance =
        draft.onCredit && remaining > 0;

    return _buildSummaryCard(
      [
        if (draft.appliedDeliveryDiscount > 0) ...[
          _SummaryRow(
            'Goat Amount',
            _currency(draft.grossSaleAmount),
          ),
          _SummaryRow(
            'Discount',
            '− ${_currency(draft.appliedDiscount)}',
          ),
        ],

        _SummaryRow(
          'Goat Sale',
          _currency(draft.totalSaleAmount),
        ),

        if (draft.transportCost > 0)
          _SummaryRow(
            'Transportation',
            _currency(draft.transportCost),
          ),

        _SummaryRow(
          'Customer Total',
          _currency(draft.customerTotalDeliverNow),
        ),

        _SummaryRow(
          'Amount Received',
          _currency(draft.amountReceived),
        ),

        _SummaryRow(
          onCreditBalance
              ? 'Outstanding (On Credit)'
              : 'Remaining Balance',
          _currency(remaining),
          emphasized: true,
        ),

        if (_isLot && extra > 0)
          _SummaryRow(
            'Extra Received',
            _currency(extra),
            emphasized: true,
          ),
      ],
      title: 'Payment Summary',
      statusLabel:
      onCreditBalance ? 'On Credit' : status,
      statusColor: _statusColor(status),
      notes: [
        if (onCreditBalance)
          _SummaryNote(
            '${_currency(remaining)} will be added to '
                '${_buyer(draft)}\'s outstanding balance. It shows '
                'in Finance under customers on credit, where the '
                'payment can be received later.',
            color: AppColors.warning,
            icon:
            Icons.account_balance_wallet_outlined,
          ),

        if (!draft.onCredit && remaining > 0)
          _SummaryNote(
            'The customer total is not fully received. Enter '
                'the full amount, or turn on Sell on Credit to keep '
                '${_currency(remaining)} as outstanding.',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),

        if (extra > 0 && _isLot)
          _SummaryNote(
            'The customer has paid ${_currency(extra)} more than '
                'the final customer total. Select either '
                '"Add remaining amount to customer Advance" or '
                '"Return remaining amount to customer".',
            color: AppColors.warning,
            icon: Icons.info_outline_rounded,
          ),

        if (extra > 0 && !_isLot)
          _SummaryNote(
            'You entered ${_currency(extra)} more than the '
                'customer total. Check the amount received before saving.',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),

        if (draft.transportCost > 0)
          _SummaryNote(
            'Transportation charge '
                '(${_currency(draft.transportCost)}) is added to '
                'the customer\'s bill. It is not recorded as a farm '
                'expense.',
            color: AppColors.textGrey,
            icon: Icons.info_outline_rounded,
          ),
      ],
    );
  }

  // ===========================================================================
  // BRANCH B — BOOKING / HOLDING
  // ===========================================================================

  Widget _buildBookingForm(SaleDraft draft) {
    return Form(
      key: _bookingFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Booking / Holding',
            icon: Icons.bookmark_outline_rounded,
            children: [
              wizardField(
                controller: _bookingAmountController,
                label: 'Booking Amount',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncBooking),
                validator: (value) {
                  final number =
                  double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _paymentMethodPicker(draft),

              const SizedBox(height: 14),

              _creditSwitch(
                draft,
                onText: '${_buyer(draft)} takes ${_theGoats(draft)} '
                    'and pays the remaining balance later. What is '
                    'unpaid after the delivery is added to their '
                    'outstanding balance.',
                offText:
                'Off — the remaining balance is paid at pickup.',
              ),

              const SizedBox(height: 14),

              wizardField(
                controller:
                _holdingChargePerDayController,
                label: 'Holding Charge / Day',
                optional: true,
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                suffix: '/ day',
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncBooking),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  if (text.isEmpty) return null;

                  final number = double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid charge';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSummaryCard(
            [
              _SummaryRow(
                'Goat Sale',
                _currency(draft.totalSaleAmount),
              ),
              _SummaryRow(
                'Booking Amount Paid',
                _currency(draft.bookingAmount),
              ),
              _SummaryRow(
                'Balance (before holding charges)',
                _currency(draft.remainingBalanceBooking),
                emphasized: true,
              ),
              if (draft.holdingChargePerDay > 0)
                _SummaryRow(
                  'Holding Charge',
                  '${_currency(draft.holdingChargePerDay)} / day',
                ),
            ],
            title: 'Booking Summary',
            notes: [
              if (draft.bookingAmount >
                  draft.totalSaleAmount)
                _SummaryNote(
                  'The booking amount is more than the goat sale '
                      '(${_currency(draft.totalSaleAmount)}). Check '
                      'the amount before saving.',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),

              if (draft.onCredit)
                _SummaryNote(
                  'On credit: the balance is worked out when the '
                      'delivery is completed (goat sale + holding '
                      'charges - booking amount). Whatever is unpaid '
                      'then is added to ${_buyer(draft)}\'s outstanding '
                      'balance.',
                  color: AppColors.warning,
                  icon:
                  Icons.account_balance_wallet_outlined,
                ),

              _SummaryNote(
                'Holding is counted from today until the day '
                    '${_theGoats(draft)} ${_isAre(draft)} delivered, '
                    'both days included (booked 20 Sept, delivered '
                    '23 Sept = 4 days). The holding charges are '
                    'calculated and added when the delivery is '
                    'completed.',
                color: AppColors.textGrey,
                icon: Icons.info_outline_rounded,
              ),

              _SummaryNote(
                'No receipt is generated now — this booking is '
                    'only kept as a record. The receipt is generated '
                    'when the delivery is completed.',
                color: AppColors.textGrey,
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUMMARY CARD
  // ===========================================================================

  Widget _buildSummaryCard(
      List<_SummaryRow> rows, {
        String? title,
        String? statusLabel,
        Color? statusColor,
        List<_SummaryNote> notes = const [],
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          if (title != null || statusLabel != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? '',
                    style: AppTheme.heading(
                      size: 13,
                      color: AppColors.textDark,
                    ),
                  ),
                ),

                if (statusLabel != null)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (statusColor ??
                          AppColors.textGrey)
                          .withValues(alpha: 0.10),
                      borderRadius:
                      BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor ??
                            AppColors.textGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            Divider(
              color: AppColors.divider,
              height: 1,
            ),

            const SizedBox(height: 10),
          ],

          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const SizedBox(height: 8),

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: rows[i].emphasized
                        ? AppTheme.heading(
                      size: 12,
                      color: AppColors.textDark,
                    )
                        : AppTheme.body(
                      size: 11,
                      color: AppColors.textGrey,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Text(
                  rows[i].value,
                  textAlign: TextAlign.right,
                  style: rows[i].emphasized
                      ? AppTheme.heading(
                    size: 14,
                    color: AppColors.textDark,
                  )
                      : AppTheme.body(
                    size: 12,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          for (final note in notes) ...[
            const SizedBox(height: 10),

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                  const EdgeInsets.only(top: 1),
                  child: Icon(
                    note.icon,
                    size: 14,
                    color: note.color,
                  ),
                ),

                const SizedBox(width: 6),

                Expanded(
                  child: Text(
                    note.text,
                    style: AppTheme.body(
                      size: 10,
                      color: note.color,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // BRANCH C — WAIT FOR DELIVERY
  // ===========================================================================

  Widget _buildWaitForDeliveryForm(SaleDraft draft) {
    return Form(
      key: _waitForDeliveryFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Wait for Delivery',
            icon: Icons.schedule_outlined,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                  AppColors.warning.withValues(
                    alpha: 0.08,
                  ),
                  borderRadius:
                  BorderRadius.circular(12),
                  border: Border.all(
                    color:
                    AppColors.warning.withValues(
                      alpha: 0.35,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_clock_outlined,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        draft.isFixedPrice
                            ? 'The fixed price of '
                            '${_currency(draft.totalSaleAmount)} '
                            'is locked in now. When this delivery '
                            'is completed later, the pickup weight '
                            'is only recorded — the amount stays '
                            'the same, whatever ${_theGoats(draft)} '
                            '${draft.saleGoatCount > 1 ? 'weigh' : 'weighs'}.'
                            : 'Price/kg is locked in at '
                            '${_currency(draft.bookingPricePerKg)} '
                            'now. When this delivery is completed '
                            'later, use this same rate with the '
                            'new pickup weight — never the market '
                            'rate on that day.',
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _bookingAdvanceController,
                label: 'Booking / Advance Amount',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncWaitForDelivery),
                validator: (value) {
                  final number =
                  double.tryParse(value?.trim() ?? '');

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _paymentMethodPicker(draft),

              const SizedBox(height: 14),

              _creditSwitch(
                draft,
                onText: '${_buyer(draft)} takes ${_theGoats(draft)} '
                    'and pays the remaining balance later. What is '
                    'unpaid after the pickup is added to their '
                    'outstanding balance.',
                offText:
                'Off — the remaining balance is paid at pickup.',
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSummaryCard(
            [
              _SummaryRow(
                'Booking Weight',
                '${SaleDraft.formatWeight(
                  draft.bookingWeightTotal,
                )} kg',
              ),

              if (draft.isFixedPrice)
                _SummaryRow(
                  'Fixed Price',
                  _currency(draft.totalSaleAmount),
                )
              else
                _SummaryRow(
                  'Booking Price/Kg',
                  _currency(draft.bookingPricePerKg),
                ),

              if (!draft.isFixedPrice)
                _SummaryRow(
                  'Goat Sale (Estimated)',
                  _currency(draft.totalSaleAmount),
                ),

              _SummaryRow(
                draft.isFixedPrice
                    ? 'Customer Total'
                    : 'Estimated Customer Total',
                _currency(
                  draft.customerTotalWaitForDelivery,
                ),
              ),

              _SummaryRow(
                'Advance Paid',
                _currency(draft.bookingAdvanceAmount),
              ),

              _SummaryRow(
                draft.isFixedPrice
                    ? 'Remaining'
                    : 'Estimated Remaining',
                _currency(
                  draft.remainingAdvanceBalanceWaitForDelivery,
                ),
                emphasized: true,
              ),
            ],
            title: 'Booking Summary',
            notes: [
              if (draft.bookingAdvanceAmount >
                  draft.customerTotalWaitForDelivery)
                _SummaryNote(
                  'The advance is more than the estimated customer '
                      'total (${_currency(
                    draft.customerTotalWaitForDelivery,
                  )}). Check the amount before saving.',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),

              if (draft.onCredit)
                _SummaryNote(
                  'On credit: the final amount is worked out at pickup '
                      '(${draft.isFixedPrice ? 'fixed price' : 'pickup weight × rate'} '
                      '- advance). Whatever is unpaid then is added to '
                      '${_buyer(draft)}\'s outstanding balance.',
                  color: AppColors.warning,
                  icon:
                  Icons.account_balance_wallet_outlined,
                ),

              _SummaryNote(
                draft.isFixedPrice
                    ? 'The price is fixed. At pickup ${_theGoats(draft)} '
                    '${_isAre(draft)} weighed again for the record, '
                    'but the final amount is always: fixed price − advance.'
                    : 'Estimated at today\'s weight. At pickup '
                    '${_theGoats(draft)} ${_isAre(draft)} weighed '
                    'again and the final amount is: pickup weight '
                    '× ${_currency(draft.bookingPricePerKg)}/kg − advance.',
                color: AppColors.textGrey,
                icon: Icons.info_outline_rounded,
              ),

              _SummaryNote(
                'No receipt is generated now — this sale is only kept '
                    'as a record. The receipt is generated when the delivery '
                    'is completed.',
                color: AppColors.textGrey,
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BRANCH D — TRANSFER TO PALAI
  // ===========================================================================

  Widget _buildPalaiTransferForm(SaleDraft draft) {
    return Form(
      key: _palaiFormKey,
      child: Column(
        children: [
          WizardSectionCard(
            title: 'Transfer to Palai',
            icon: Icons.holiday_village_outlined,
            children: [
              Text(
                'The ongoing monthly billing and health tracking for '
                    '${draft.saleGoatCount > 1 ? 'these goats' : 'this goat'} '
                    'is handled by the Customer Palai module from here on — '
                    'this just captures the handoff.',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 14),

              WizardDateField(
                label: 'Transfer Date',
                date:
                draft.transferDate ?? DateTime.now(),
                onTap: () async {
                  final picked =
                  await showWizardDatePicker(
                    context: context,
                    initialDate:
                    draft.transferDate ??
                        DateTime.now(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now(),
                    helpText: 'Transfer date',
                  );

                  if (picked == null) return;

                  setState(() {
                    draft.transferDate = picked;
                  });
                },
              ),

              const SizedBox(height: 14),

              wizardDropdown(
                label: 'Palai Package',
                icon: Icons.card_giftcard_outlined,
                value: draft.palaiPackage,
                options: SaleDraft.palaiPackages,
                onChanged: (value) {
                  setState(() {
                    draft.palaiPackage = value;
                  });
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _monthlyChargeController,
                label: 'Monthly Palai Charge',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                suffix: '/ month',
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => _syncPalai(),
                validator: (value) {
                  final number =
                  double.tryParse(value?.trim() ?? '');

                  if (number == null || number <= 0) {
                    return 'Enter a valid monthly charge';
                  }

                  return null;
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          WizardSectionCard(
            title: 'Goat Price Payment',
            icon: Icons.payments_outlined,
            children: [
              Text(
                '${draft.saleGoatCount > 1 ? 'The goats are' : 'The goat is'} '
                    'sold to the customer at '
                    '${_currency(draft.totalSaleAmount)} '
                    '(from the sale details). This is separate from the '
                    'monthly Palai charge above.',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 14),

              _creditSwitch(
                draft,
                onText: 'Whatever is not paid now is added to '
                    '${_buyer(draft)}\'s outstanding balance.',
                offText:
                'Off — the full goat price is received now.',
              ),

              const SizedBox(height: 14),

              wizardField(
                controller:
                _palaiAmountReceivedController,
                label: 'Amount Received',
                optional: draft.onCredit,
                helper: draft.onCredit
                    ? 'Leave blank if nothing was received — '
                    'the whole goat price stays on credit'
                    : 'The full goat price must be received',
                hint: '0.00',
                icon: Icons.payments_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) =>
                    setState(_syncPalai),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  final number =
                  text.isEmpty
                      ? 0.0
                      : double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  if (!draft.onCredit &&
                      SaleDraft.round2(number) <
                          draft.customerTotalPalai) {
                    return 'Enter the full '
                        '${_currency(draft.customerTotalPalai)}, '
                        'or turn on Sell on Credit';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              _paymentMethodPicker(draft),
            ],
          ),

          const SizedBox(height: 12),

          _buildPalaiSummary(draft),
        ],
      ),
    );
  }

  Widget _buildPalaiSummary(SaleDraft draft) {
    final status = draft.paymentStatusPalai;
    final extra = draft.extraReceivedPalai;
    final remaining = draft.remainingBalancePalai;
    final onCreditBalance =
        draft.onCredit && remaining > 0;

    return _buildSummaryCard(
      [
        _SummaryRow(
          'Goat Sale',
          _currency(draft.customerTotalPalai),
        ),

        _SummaryRow(
          'Amount Received',
          _currency(draft.palaiAmountReceived),
        ),

        _SummaryRow(
          onCreditBalance
              ? 'Outstanding (On Credit)'
              : 'Remaining Balance',
          _currency(remaining),
          emphasized: true,
        ),
      ],
      title: 'Goat Price Summary',
      statusLabel:
      onCreditBalance ? 'On Credit' : status,
      statusColor: _statusColor(status),
      notes: [
        if (extra > 0)
          _SummaryNote(
            'You entered ${_currency(extra)} more than the goat '
                'price. Check the amount received before saving.',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),

        if (onCreditBalance)
          _SummaryNote(
            '${_currency(remaining)} will be added to '
                '${_buyer(draft)}\'s outstanding balance. It shows '
                'in Finance under customers on credit, where the '
                'payment can be received later.',
            color: AppColors.warning,
            icon:
            Icons.account_balance_wallet_outlined,
          ),

        if (!draft.onCredit && remaining > 0)
          _SummaryNote(
            'The goat price is not fully received. Enter the full '
                'amount, or turn on Sell on Credit to keep '
                '${_currency(remaining)} as outstanding.',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),
      ],
    );
  }
}

// ============================================================================
// SUMMARY ROW
// ============================================================================

class _SummaryRow {
  final String label;
  final String value;
  final bool emphasized;

  const _SummaryRow(
      this.label,
      this.value, {
        this.emphasized = false,
      });
}

/// Small explanatory / warning line under a summary card.
class _SummaryNote {
  final String text;
  final Color color;
  final IconData icon;

  const _SummaryNote(
      this.text, {
        required this.color,
        required this.icon,
      });
}

// ============================================================================
// BRANCH CARD
// ============================================================================

class _BranchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _BranchCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (selected
                        ? AppColors.primaryGreen
                        : AppColors.textGrey)
                        .withValues(alpha: 0.10),
                    borderRadius:
                    BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? AppColors.primaryGreen
                        : AppColors.textGrey,
                    size: 21,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.heading(
                          size: 13,
                          color: AppColors.textDark,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        subtitle,
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? AppColors.primaryGreen
                      : AppColors.divider,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}