import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/expense_categories.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Complete Delivery — Booking (Phase 5, Section 1).
///
/// Holding days run from the day holding started to the delivery date,
/// both days counted.
///
/// TRANSPORTATION — an optional charge entered at delivery. It is added
/// to what the customer owes and shows on the bill
/// ([Sale.billTransportCharges]), but it is passed on to the transport
/// team, so it is never farm revenue.
///
/// PAYMENT & CREDIT — once the final amount is known, the person says how
/// much the customer pays now and how:
///  * Whole amount received -> sale is Paid, nothing on credit.
///  * Part or none received -> "Sell on Credit" must be on; the unpaid
///    part becomes the customer's outstanding balance (Finance >
///    Customers on Credit).
/// The rules are enforced again by [SalesService.completeBookingDelivery].
class CompleteBookingDeliveryScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const CompleteBookingDeliveryScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<CompleteBookingDeliveryScreen> createState() =>
      _CompleteBookingDeliveryScreenState();
}

class _CompleteBookingDeliveryScreenState
    extends State<CompleteBookingDeliveryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountReceivedController;
  late final TextEditingController _transportController;

  DateTime _deliveryDate = _dayOnly(DateTime.now());

  bool _loadingSale = true;
  bool _saving = false;
  String? _loadError;
  Sale? _sale;

  /// Sell on Credit. Starts on whatever Step 5 saved on the sale.
  bool _onCredit = false;

  /// True once the person has typed in the amount field themselves.
  bool _amountEdited = false;

  String _method = FinancePaymentMethods.cash;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _plain(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _amountReceivedController = TextEditingController();
    _transportController = TextEditingController();
    _loadSale();
  }

  @override
  void dispose() {
    _amountReceivedController.dispose();
    _transportController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // LOAD SALE
  // ===========================================================================

  Future<void> _loadSale() async {
    final saleId = widget.goat.saleId;

    if (saleId == null || saleId.trim().isEmpty) {
      setState(() {
        _loadingSale = false;
        _loadError = 'This goat has no linked sale record.';
      });
      return;
    }

    setState(() {
      _loadingSale = true;
      _loadError = null;
    });

    try {
      final sale = await SalesService.instance.getSale(widget.farmId, saleId);

      if (!mounted) return;

      if (sale == null) {
        setState(() {
          _loadingSale = false;
          _loadError = 'Sale $saleId could not be found.';
        });
        return;
      }

      if (!sale.isBooking || sale.status != Sale.statusBooked) {
        setState(() {
          _loadingSale = false;
          _loadError = 'This sale is not an open Booking — it may already '
              'have been completed.';
        });
        return;
      }

      setState(() {
        _sale = sale;
        _loadingSale = false;

        final start = _dayOnly(sale.holdingStart);
        final today = _dayOnly(DateTime.now());
        _deliveryDate = today.isBefore(start) ? start : today;

        _onCredit = sale.onCredit;
        _amountEdited = false;
        _syncAutoAmount();
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSale = false;
        _loadError = FirestoreService.instance.describeError(e);
      });
    }
  }

  // ===========================================================================
  // LIVE CALCULATION
  // ===========================================================================

  int get _actualHoldingDays {
    final sale = _sale;
    if (sale == null) return 0;

    return Sale.holdingDaysBetween(sale.holdingStart, _deliveryDate);
  }

  double get _actualHoldingCharges {
    final sale = _sale;
    if (sale == null) return 0;
    return Sale.roundMoney(_actualHoldingDays * (sale.holdingChargePerDay ?? 0));
  }

  /// The transportation charge typed in (blank counts as 0). Collected
  /// from the customer on top of the goat sale and holding charges, and
  /// passed on to the transport team — it is not farm revenue.
  double get _transport {
    final text = _transportController.text.trim();
    if (text.isEmpty) return 0;

    final number = double.tryParse(text) ?? 0;
    return number <= 0 ? 0 : Sale.roundMoney(number);
  }

  /// Goat sale + holding charges + transportation - booking amount
  /// already paid.
  double get _finalAmount {
    final sale = _sale;
    if (sale == null) return 0;

    final raw = sale.totalSaleAmount +
        _actualHoldingCharges +
        _transport -
        (sale.bookingAmount ?? 0);

    return raw <= 0 ? 0 : Sale.roundMoney(raw);
  }

  double get _typedAmount {
    final text = _amountReceivedController.text.trim();
    if (text.isEmpty) return 0;
    return Sale.roundMoney(double.tryParse(text) ?? 0);
  }

  /// Nothing is asked for when there is nothing left to pay.
  double get _receivedNow => _finalAmount > 0 ? _typedAmount : 0;

  double get _remaining {
    final left = Sale.roundMoney(_finalAmount - _receivedNow);
    return left <= 0 ? 0 : left;
  }

  double get _extraReceived {
    final extra = Sale.roundMoney(_receivedNow - _finalAmount);
    return extra <= 0 ? 0 : extra;
  }

  /// While Sell on Credit is off (and the person hasn't typed their own
  /// figure) the field follows the final amount as the date changes.
  void _syncAutoAmount() {
    if (_onCredit || _amountEdited) return;

    final text = _finalAmount > 0 ? _plain(_finalAmount) : '';

    if (_amountReceivedController.text != text) {
      _amountReceivedController.text = text;
    }
  }

  String _buyerName(Sale sale) {
    final name = sale.customerName.trim();
    return name.isEmpty ? 'the customer' : name;
  }

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    final number = text.isEmpty ? 0.0 : double.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid amount';
    }

    final amount = Sale.roundMoney(number);

    if (amount > _finalAmount) {
      return 'More than the final amount due (${_currency(_finalAmount)})';
    }

    if (!_onCredit && amount < _finalAmount) {
      return 'Enter the full ${_currency(_finalAmount)}, or turn on '
          'Sell on Credit';
    }

    return null;
  }

  Future<void> _pickDeliveryDate(Sale sale) async {
    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: _dayOnly(sale.holdingStart),
      lastDate: _dayOnly(DateTime.now()),
      helpText: 'Delivery date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _deliveryDate = _dayOnly(picked);
      _syncAutoAmount(); // final amount changed with the holding days
    });
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    final sale = _sale;

    if (_saving || sale == null) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final received = _receivedNow;
    final remaining = _remaining;
    final owesNothing = _finalAmount <= 0;
    final onCredit = _finalAmount > 0 && _onCredit;
    final buyer = _buyerName(sale);

    setState(() {
      _saving = true;
    });

    try {
      await SalesService.instance.completeBookingDelivery(
        farmId: widget.farmId,
        saleId: sale.id,
        deliveryDate: _deliveryDate,
        transportCharges: _transport,
        amountReceivedNow: received,
        paymentMethod: _method,
        onCredit: onCredit,
      );

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      Navigator.of(context).pop(true);

      final message = owesNothing
          ? 'Delivery completed — the booking amount covered everything.'
          : remaining > 0
          ? 'Delivery completed — ${_currency(remaining)} added to '
          '$buyer\'s outstanding balance.'
          : 'Delivery completed — ${_currency(received)} received, '
          'paid in full.';

      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      final reason = e is StateError
          ? e.message
          : FirestoreService.instance.describeError(e);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not complete delivery: $reason'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 20,
        title: Text(
          'Complete Delivery',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: _loadingSale
            ? const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        )
            : _loadError != null
            ? _buildError(_loadError!)
            : _buildForm(_sale!),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(Sale sale) {
    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          WizardSectionCard(
            title: 'Booking Summary',
            icon: Icons.bookmark_outline_rounded,
            children: [
              WizardComputedRow(
                label: 'Customer',
                value: sale.customerName,
              ),
              WizardComputedRow(
                label: 'Goat Sale Amount',
                value: _currency(sale.totalSaleAmount),
              ),
              WizardComputedRow(
                label: 'Booking Amount Paid',
                value: _currency(sale.bookingAmount ?? 0),
              ),
              WizardComputedRow(
                label: 'Holding Charge / Day',
                value: _currency(sale.holdingChargePerDay ?? 0),
              ),
              WizardComputedRow(
                label: 'Holding Started',
                value: DateFormat('dd MMM yyyy').format(sale.holdingStart),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WizardSectionCard(
            title: 'Delivery',
            icon: Icons.today_outlined,
            children: [
              WizardDateField(
                label: 'Delivery Date',
                helper: 'The day the goat is handed over.',
                date: _deliveryDate,
                onTap: () => _pickDeliveryDate(sale),
              ),
              const SizedBox(height: 12),
              WizardComputedRow(
                label: 'Holding Days',
                value: '$_actualHoldingDays '
                    'day${_actualHoldingDays == 1 ? '' : 's'}',
              ),
              Text(
                '${DateFormat('dd MMM').format(sale.holdingStart)} to '
                    '${DateFormat('dd MMM').format(_deliveryDate)}, '
                    'both days counted.',
                style: AppTheme.body(size: 10, color: AppColors.textGrey),
              ),
              const SizedBox(height: 14),
              wizardField(
                controller: _transportController,
                label: 'Transportation Charge',
                hint: '0.00',
                icon: Icons.directions_car_outlined,
                suffix: 'Added to bill',
                helper: 'Optional — leave blank if there is none. Passed on '
                    'to the transport team, so it is not farm revenue.',
                optional: true,
                enabled: !_saving,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(_syncAutoAmount),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  if (text.isEmpty) return null;

                  final number = double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPaymentCard(sale),
          const SizedBox(height: 12),
          _buildSummaryCard(sale),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 1,
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
                'Complete Delivery',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PAYMENT
  // ---------------------------------------------------------------------------

  Widget _buildPaymentCard(Sale sale) {
    final List<Widget> children;

    if (_finalAmount <= 0) {
      children = [
        _infoLine(
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.success,
          text: 'The booking amount already covers the whole amount, so '
              'there is nothing more to collect from ${_buyerName(sale)}.',
        ),
      ];
    } else {
      children = [
        _creditSwitch(sale),
        const SizedBox(height: 14),
        wizardField(
          controller: _amountReceivedController,
          label: 'Amount Received Now',
          optional: _onCredit,
          helper: _onCredit
              ? 'Leave blank if nothing is received now — the whole '
              'amount stays on credit'
              : 'The full ${_currency(_finalAmount)} must be received',
          hint: '0.00',
          icon: Icons.payments_outlined,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          onChanged: (_) {
            setState(() {
              _amountEdited = true;
            });
          },
          validator: _validateAmount,
        ),
        if (_onCredit)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _saving
                  ? null
                  : () {
                setState(() {
                  _amountEdited = false;
                  _amountReceivedController.text = _plain(_finalAmount);
                });
              },
              child: const Text('Fill full amount'),
            ),
          ),
        if (_receivedNow > 0) ...[
          const SizedBox(height: 14),
          _paymentMethodPicker(),
        ],
      ];
    }

    return WizardSectionCard(
      title: 'Payment',
      icon: Icons.account_balance_wallet_outlined,
      children: children,
    );
  }

  Widget _creditSwitch(Sale sale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _onCredit
            ? AppColors.error.withOpacity(0.06)
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
                  _onCredit
                      ? 'Whatever is not received now is added to '
                      '${_buyerName(sale)}\'s outstanding balance.'
                      : 'Off — the full final amount is received now.',
                  style: AppTheme.body(size: 10, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          Switch(
            value: _onCredit,
            activeColor: AppColors.error,
            onChanged: _saving
                ? null
                : (value) {
              setState(() {
                _onCredit = value;

                if (value) {
                  if (!_amountEdited) {
                    _amountReceivedController.text = '';
                  }
                } else {
                  _amountEdited = false;
                  _syncAutoAmount();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodPicker() {
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
            final selected = _method == method;

            return ChoiceChip(
              label: Text(method),
              selected: selected,
              onSelected: _saving
                  ? null
                  : (_) {
                setState(() {
                  _method = method;
                });
              },
              selectedColor: AppColors.primaryGreen.withOpacity(0.15),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.darkGreen : AppColors.textDark,
              ),
              side: BorderSide(
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'How the amount above is being paid now.',
          style: AppTheme.body(size: 10, color: AppColors.textGrey),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY — live
  // ---------------------------------------------------------------------------

  Widget _buildSummaryCard(Sale sale) {
    final due = _finalAmount;
    final remaining = _remaining;
    final owes = due > 0;
    final onCreditBalance = owes && _onCredit && remaining > 0;

    final String? statusLabel;
    final Color statusColor;

    if (!owes) {
      statusLabel = null;
      statusColor = AppColors.textGrey;
    } else if (remaining <= 0) {
      statusLabel = 'Paid';
      statusColor = AppColors.success;
    } else if (_onCredit) {
      statusLabel = 'On Credit';
      statusColor = AppColors.warning;
    } else {
      statusLabel = 'Not fully paid';
      statusColor = AppColors.error;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Payment Summary',
                  style: AppTheme.heading(size: 13, color: AppColors.textDark),
                ),
              ),
              if (statusLabel != null)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          _summaryRow('Goat Sale', _currency(sale.totalSaleAmount)),
          const SizedBox(height: 8),
          _summaryRow(
            'Holding Charges ($_actualHoldingDays × '
                '${_currency(sale.holdingChargePerDay ?? 0)})',
            _currency(_actualHoldingCharges),
          ),
          if (_transport > 0) ...[
            const SizedBox(height: 8),
            _summaryRow(
              'Transportation',
              '+ ${_currency(_transport)}',
            ),
          ],
          const SizedBox(height: 8),
          _summaryRow(
            'Booking Amount Paid',
            '− ${_currency(sale.bookingAmount ?? 0)}',
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Final Amount Due',
            _currency(due),
            emphasized: true,
          ),
          if (owes) ...[
            const SizedBox(height: 8),
            _summaryRow('Received Now', _currency(_receivedNow)),
            const SizedBox(height: 8),
            _summaryRow(
              onCreditBalance ? 'Outstanding (On Credit)' : 'Remaining Balance',
              _currency(remaining),
              emphasized: true,
            ),
          ],
          if (onCreditBalance) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.warning,
              text: '${_currency(remaining)} will be added to '
                  '${_buyerName(sale)}\'s outstanding balance. It shows in '
                  'Finance under Customers on Credit, where the payment '
                  'can be received later.',
            ),
          ],
          if (owes && _onCredit && remaining <= 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.info_outline_rounded,
              color: AppColors.textGrey,
              text: 'The full amount is being received, so nothing is '
                  'left on credit.',
            ),
          ],
          if (owes && !_onCredit && remaining > 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              text: 'The final amount is not fully received. Enter the '
                  'full amount, or turn on Sell on Credit to keep '
                  '${_currency(remaining)} as outstanding.',
            ),
          ],
          if (owes && _extraReceived > 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              text: 'You entered ${_currency(_extraReceived)} more than '
                  'the final amount. Check the amount received before '
                  'saving.',
            ),
          ],
          if (_transport > 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.local_shipping_outlined,
              color: AppColors.textGrey,
              text: 'Transportation is passed on to the transport team, so '
                  'it is not counted as farm revenue.',
            ),
          ],
          if (owes && !_onCredit && remaining <= 0 && _extraReceived <= 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.verified_rounded,
              color: AppColors.success,
              text: 'Paid in full — this sale will be marked Paid and '
                  'nothing goes on credit.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoLine({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: AppTheme.body(size: 10.5, color: color)),
        ),
      ],
    );
  }

  Widget _summaryRow(
      String label,
      String value, {
        bool emphasized = false,
      }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? AppTheme.heading(size: 12, color: AppColors.textDark)
                : AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: emphasized
              ? AppTheme.heading(size: 15, color: AppColors.textDark)
              : AppTheme.body(
            size: 12,
            color: AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}