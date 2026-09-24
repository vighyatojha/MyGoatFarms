import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/expense_categories.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_goat_health_record.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/sales_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Complete Delivery — Wait for Delivery (Phase 5, Section 2).
///
/// Reached from [GoatStockDetailScreen] for a goat whose
/// `currentStatus` is [Goat.statusWaitOnDelivery]. Unlike the Booking
/// branch, the final price here is never re-quoted at today's rate —
/// the plan's Section 5 note flags that as the easiest thing in this
/// phase to get backwards. The rate is always the one fixed at
/// booking time ([Sale.bookingPricePerKg]); only the weight is taken
/// fresh, at pickup:
///
///   Final Amount Due = Pickup Weight x Booking Price/Kg
///                      + Transportation - Advance Paid
///
/// A Fixed Price sale ([Sale.isFixedPrice]) is the exception: the agreed
/// price stands whatever the goat weighs, so the pickup weight is only
/// recorded and Final Amount Due = Fixed Price + Transportation - Advance
/// Paid.
///
/// TRANSPORTATION — an optional charge entered at pickup, because it is
/// only known once the goat is actually being handed over. It is added
/// to what the customer pays and shows on the bill
/// ([Sale.billTransportCharges]), but it is passed on to the transport
/// team, so it is never farm revenue.
///
/// HEALTH REMINDER — the goat is about to leave the farm, so the top of the
/// screen reminds the person to check its health before handover. It reads
/// the current health status and the care records (vaccination, hoof
/// cutting, hair trimming, medicine) of every goat in the sale, and
/// flags any that is not Healthy or has care that is overdue or due within
/// the next [_dueSoonDays] days. It is only a reminder: it never blocks
/// Complete Delivery.
///
/// The dates come from the farm's Health Reminder Settings (Profile >
/// Health Reminder Settings): a goat on Wait on Delivery is armed with the
/// farm's vaccination, hoof cutting and hair trimming schedule exactly
/// like an Own Palai goat (see FirestoreService.syncOwnPalaiFarmReminders),
/// and the same dates raise notifications in the Notifications screen until
/// the goat is picked up.
///
/// PAYMENT & CREDIT — once the final amount is known, the person says how
/// much the customer is paying right now and how:
///
///  * The whole amount received  -> the sale is Paid, nothing goes on
///    credit.
///  * Part or none received      -> "Sell on Credit" must be on. The
///    unpaid part becomes the customer's outstanding balance, shown in
///    Finance under Customers on Credit, where it is collected later.
///
/// The switch starts on the choice made in Step 5 (Delivery Options,
/// [Sale.onCredit]) and can be changed here, because the amount that is
/// actually owed is only known now. The rules are enforced again by
/// [SalesService.completeWaitForDeliveryPickup], so the screen and the
/// saved sale can never disagree.
class CompleteWaitForDeliveryScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const CompleteWaitForDeliveryScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<CompleteWaitForDeliveryScreen> createState() =>
      _CompleteWaitForDeliveryScreenState();
}

class _CompleteWaitForDeliveryScreenState
    extends State<CompleteWaitForDeliveryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _pickupWeightController;
  late final TextEditingController _transportController;
  late final TextEditingController _amountReceivedController;

  bool _loadingSale = true;
  bool _saving = false;
  String? _loadError;
  Sale? _sale;

  /// Sell on Credit. Starts on whatever Step 5 saved on the sale.
  bool _onCredit = false;

  /// True once the person has typed in the amount field themselves. Until
  /// then the field follows the final amount (see [_syncAutoAmount]).
  bool _amountEdited = false;

  /// How the money received now is being paid.
  String _method = FinancePaymentMethods.cash;

  /// Care due within this many days (or already overdue) is flagged in the
  /// Health Reminder card.
  static const int _dueSoonDays = 7;

  bool _loadingHealth = false;

  /// True when the health records of at least one goat could not be read,
  /// so "all good" is not claimed on incomplete information.
  bool _healthLoadFailed = false;

  /// Only goats that need attention: not Healthy, or care due / overdue.
  List<_GoatHealthAlert> _healthAlerts = const [];

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  void initState() {
    super.initState();
    _pickupWeightController = TextEditingController();
    _transportController = TextEditingController();
    _amountReceivedController = TextEditingController();
    _loadSale();
  }

  @override
  void dispose() {
    _pickupWeightController.dispose();
    _transportController.dispose();
    _amountReceivedController.dispose();
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
      final sale =
      await SalesService.instance.getSale(widget.farmId, saleId);

      if (!mounted) return;

      if (sale == null) {
        setState(() {
          _loadingSale = false;
          _loadError = 'Sale $saleId could not be found.';
        });
        return;
      }

      if (!sale.isWaitForDelivery ||
          sale.status != Sale.statusWaitForDelivery) {
        setState(() {
          _loadingSale = false;
          _loadError =
          'This sale is not an open Wait for Delivery — it may '
              'already have been completed.';
        });
        return;
      }

      setState(() {
        _sale = sale;
        _loadingSale = false;

        // Pre-fill with the weight recorded at booking time — the
        // customer's goat may have gained or lost weight by pickup,
        // so this is editable, same as the Booking branch pre-fills
        // (and does not lock) the original holding-days estimate.
        _pickupWeightController.text =
        (sale.bookingWeight ?? 0) == 0
            ? ''
            : _trimZeros(sale.bookingWeight!);

        // The credit choice made in Step 5 (Delivery Options). If it was
        // off, the full amount is expected, so the field starts filled in.
        _onCredit = sale.onCredit;
        _amountEdited = false;
        _syncAutoAmount();
      });

      unawaited(_loadHealthReminders(sale));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSale = false;
        _loadError = FirestoreService.instance.describeError(e);
      });
    }
  }

  String _trimZeros(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// A money value as plain text for an input field: 14760, or 14760.50.
  String _plain(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  // ===========================================================================
  // HEALTH REMINDER
  // ===========================================================================

  Future<void> _loadHealthReminders(Sale sale) async {
    if (!mounted) return;

    setState(() {
      _loadingHealth = true;
      _healthLoadFailed = false;
    });

    final alerts = <_GoatHealthAlert>[];
    var failed = false;

    for (final goatId in sale.goatIds) {
      try {
        final goat = await GoatService.instance.getGoat(widget.farmId, goatId);

        if (goat == null) continue;

        var records = <GoatHealthRecord>[];

        try {
          records = await GoatService.instance
              .healthRecordsStream(farmId: widget.farmId, goatId: goatId)
              .first
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // The health status is still shown; only the care dates are
          // missing.
          failed = true;
        }

        final status = goat.healthStatus.trim();
        final pending = _pendingCare(records);
        final unwell = status.isNotEmpty && status != 'Healthy';

        if (unwell || pending.isNotEmpty) {
          alerts.add(
            _GoatHealthAlert(
              goatId: goat.id,
              healthStatus: status,
              isUnwell: unwell,
              pendingCare: pending,
            ),
          );
        }
      } catch (_) {
        failed = true;
      }
    }

    if (!mounted) return;

    setState(() {
      _healthAlerts = alerts;
      _healthLoadFailed = failed;
      _loadingHealth = false;
    });
  }

  /// For each care type, the newest record decides — an older record's
  /// due date is superseded once a newer one exists, so it is not flagged
  /// as overdue forever. Only what is overdue or due soon is returned,
  /// earliest first.
  List<GoatHealthRecord> _pendingCare(List<GoatHealthRecord> records) {
    final seen = <GoatHealthRecordType>{};
    final pending = <GoatHealthRecord>[];

    // [records] arrive newest first (see GoatService.healthRecordsStream).
    for (final record in records) {
      if (!seen.add(record.type)) continue;

      if (record.nextDueDate == null) continue;

      if (record.isOverdue ||
          record.isDueWithin(const Duration(days: _dueSoonDays))) {
        pending.add(record);
      }
    }

    pending.sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));

    return pending;
  }

  Color _healthStatusColor(String status) {
    switch (status.trim()) {
      case 'Healthy':
        return AppColors.success;
      case 'Under Treatment':
        return AppColors.warning;
      case 'Sick':
        return AppColors.error;
      case 'Quarantined':
        return AppColors.info;
      default:
        return AppColors.textGrey;
    }
  }

  // ===========================================================================
  // LIVE CALCULATION
  // ===========================================================================

  double get _pickupWeight =>
      double.tryParse(_pickupWeightController.text.trim()) ?? 0;

  /// Pickup weight x the booking-time rate. Never today's rate. For a
  /// Fixed Price sale it is the agreed price instead, whatever the
  /// pickup weight is.
  ///
  /// Nothing is due until a pickup weight has been entered — the weight
  /// is required either way, so it is recorded for the goat.
  double get _goatSaleValue {
    final sale = _sale;
    if (sale == null || _pickupWeight <= 0) return 0;

    return sale.goatValueAtWeight(_pickupWeight);
  }

  double get _advancePaid => _sale?.bookingAdvanceAmount ?? 0;

  /// The transportation charge typed in (blank counts as 0). Collected
  /// from the customer on top of the goat value, and passed on to the
  /// transport team — it is not farm revenue.
  double get _transport {
    final text = _transportController.text.trim();

    if (text.isEmpty) return 0;

    final number = double.tryParse(text) ?? 0;

    return number <= 0 ? 0 : Sale.roundMoney(number);
  }

  /// What the customer still owes at pickup: pickup weight x the
  /// booking-time rate + transportation - the advance already paid. Same
  /// figure SalesService stores as finalPriceAfterPickup.
  double get _finalPrice {
    // Nothing is due until a pickup weight has been entered.
    if (_pickupWeight <= 0) return 0;

    final raw = _goatSaleValue + _transport - _advancePaid;

    return raw <= 0 ? 0 : Sale.roundMoney(raw);
  }

  /// The amount typed in "Amount Received Now" (blank counts as 0).
  double get _typedAmount {
    final text = _amountReceivedController.text.trim();

    if (text.isEmpty) return 0;

    return Sale.roundMoney(double.tryParse(text) ?? 0);
  }

  /// What is being received right now. Nothing is asked for when there is
  /// nothing left to pay (the advance already covered everything).
  double get _receivedNow => _finalPrice > 0 ? _typedAmount : 0;

  /// The part of the final amount that is still unpaid after
  /// [_receivedNow]. If Sell on Credit is on, this is what becomes the
  /// customer's outstanding balance.
  double get _remaining {
    final left = Sale.roundMoney(_finalPrice - _receivedNow);

    return left <= 0 ? 0 : left;
  }

  /// More than the final amount was entered.
  double get _extraReceived {
    final extra = Sale.roundMoney(_receivedNow - _finalPrice);

    return extra <= 0 ? 0 : extra;
  }

  /// While Sell on Credit is off, the amount field simply follows the full
  /// final amount as the pickup weight changes — until the person types
  /// their own figure.
  void _syncAutoAmount() {
    if (_onCredit || _amountEdited) return;

    final text = _finalPrice > 0 ? _plain(_finalPrice) : '';

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

    // Blank counts as 0.
    final number = text.isEmpty ? 0.0 : double.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid amount';
    }

    final amount = Sale.roundMoney(number);

    if (amount > _finalPrice) {
      return 'More than the final amount due (${_currency(_finalPrice)})';
    }

    // Not on credit -> everything is paid now.
    if (!_onCredit && amount < _finalPrice) {
      return 'Enter the full ${_currency(_finalPrice)}, or turn on '
          'Sell on Credit';
    }

    return null;
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    final sale = _sale;

    if (_saving || sale == null) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    // Worked out once, before saving, for the confirmation message. The
    // service re-checks all of it against the saved sale.
    final received = _receivedNow;
    final remaining = _remaining;
    final owesNothing = _finalPrice <= 0;
    final onCredit = _finalPrice > 0 && _onCredit;
    final buyer = _buyerName(sale);

    setState(() {
      _saving = true;
    });

    try {
      await SalesService.instance.completeWaitForDeliveryPickup(
        farmId: widget.farmId,
        saleId: sale.id,
        pickupWeight: _pickupWeight,
        transportCharges: _transport,
        amountReceivedNow: received,
        paymentMethod: _method,
        onCredit: onCredit,
      );

      if (!mounted) return;

      // Grab the messenger before leaving this screen.
      final messenger = ScaffoldMessenger.of(context);

      Navigator.of(context).pop(true);

      final message = owesNothing
          ? 'Delivery completed — the advance covered the full amount.'
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

      // A StateError carries a message written for the person (amount too
      // high, not fully paid, already completed, ...). Anything else is a
      // connection problem.
      final reason =
      e is StateError ? e.message : FirestoreService.instance.describeError(e);

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
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 13,
                color: AppColors.textDark,
              ),
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
          _buildHealthReminderCard(sale),

          const SizedBox(height: 12),

          WizardSectionCard(
            title: 'Booking Summary',
            icon: Icons.local_shipping_outlined,
            children: [
              WizardComputedRow(
                label: 'Customer',
                value: sale.customerName,
              ),
              if (sale.isFixedPrice)
                WizardComputedRow(
                  label: 'Fixed Price',
                  value: _currency(sale.fixedSalePrice ?? sale.totalSaleAmount),
                )
              else
                WizardComputedRow(
                  label: 'Booking Price / Kg',
                  value: _currency(sale.bookingPricePerKg ?? 0),
                ),
              WizardComputedRow(
                label: 'Weight at Booking',
                value: '${_trimZeros(sale.bookingWeight ?? 0)} kg',
              ),
              WizardComputedRow(
                label: 'Advance Paid',
                value: _currency(sale.bookingAdvanceAmount ?? 0),
              ),
            ],
          ),

          const SizedBox(height: 12),

          WizardSectionCard(
            title: 'Actual Pickup',
            icon: Icons.scale_outlined,
            children: [
              wizardField(
                controller: _pickupWeightController,
                label: 'Pickup Weight (kg)',
                hint: 'e.g. 38',
                icon: Icons.monitor_weight_outlined,
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
                  final number = double.tryParse(value?.trim() ?? '');

                  if (number == null || number <= 0) {
                    return 'Enter valid weight';
                  }

                  return null;
                },
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
  // HEALTH REMINDER CARD
  // ---------------------------------------------------------------------------

  Widget _buildHealthReminderCard(Sale sale) {
    final buyer = _buyerName(sale);

    final children = <Widget>[
      _infoLine(
        icon: Icons.info_outline_rounded,
        color: AppColors.textGrey,
        text: 'Check the goat\'s health before handing it over to $buyer.',
      ),
    ];

    if (_loadingHealth) {
      children.addAll([
        const SizedBox(height: 10),
        _infoLine(
          icon: Icons.hourglass_empty_rounded,
          color: AppColors.textGrey,
          text: 'Checking health records…',
        ),
      ]);
    } else {
      for (final alert in _healthAlerts) {
        children.addAll([
          const SizedBox(height: 12),
          _healthAlertTile(alert, buyer),
        ]);
      }

      if (_healthLoadFailed) {
        children.addAll([
          const SizedBox(height: 10),
          _infoLine(
            icon: Icons.cloud_off_rounded,
            color: AppColors.warning,
            text: 'Some health records could not be read right now, so '
                'this list may be incomplete.',
          ),
        ]);
      } else if (_healthAlerts.isEmpty) {
        children.addAll([
          const SizedBox(height: 10),
          _infoLine(
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            text: 'All good — marked Healthy, with no vaccination, hoof '
                'cutting, hair trimming or medicine due or overdue.',
          ),
        ]);
      }
    }

    return WizardSectionCard(
      title: 'Health Reminder',
      icon: Icons.medical_services_outlined,
      children: children,
    );
  }

  Widget _healthAlertTile(_GoatHealthAlert alert, String buyer) {
    final statusColor = _healthStatusColor(alert.healthStatus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Goat ${alert.goatId}',
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (alert.isUnwell)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    alert.healthStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (alert.isUnwell) ...[
            const SizedBox(height: 8),
            _infoLine(
              icon: Icons.warning_amber_rounded,
              color: statusColor,
              text: 'Marked ${alert.healthStatus}. Let $buyer know before '
                  'handover.',
            ),
          ],
          for (final record in alert.pendingCare) ...[
            const SizedBox(height: 8),
            _careLine(record),
          ],
        ],
      ),
    );
  }

  Widget _careLine(GoatHealthRecord record) {
    final due = record.nextDueDate!;
    final overdue = record.isOverdue;

    final today = DateTime.now();
    final days = DateTime.utc(due.year, due.month, due.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;

    final dateText = DateFormat('d MMM yyyy').format(due);

    final String when;

    if (overdue) {
      when = 'overdue since $dateText';
    } else if (days <= 0) {
      when = 'due today';
    } else if (days == 1) {
      when = 'due tomorrow';
    } else {
      when = 'due in $days days ($dateText)';
    }

    return _infoLine(
      icon: overdue ? Icons.error_outline_rounded : Icons.schedule_rounded,
      color: overdue ? AppColors.error : AppColors.warning,
      text: '${record.type.label} — $when',
    );
  }

  // ---------------------------------------------------------------------------
  // PAYMENT — amount received now, method, Sell on Credit
  // ---------------------------------------------------------------------------

  Widget _buildPaymentCard(Sale sale) {
    final List<Widget> children;

    if (_pickupWeight <= 0) {
      children = [
        _infoLine(
          icon: Icons.info_outline_rounded,
          color: AppColors.textGrey,
          text: 'Enter the pickup weight to see the final amount due.',
        ),
      ];
    } else if (_finalPrice <= 0) {
      children = [
        _infoLine(
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.success,
          text: 'The advance already covers the whole amount, so there '
              'is nothing more to collect from ${_buyerName(sale)}.',
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
              : 'The full ${_currency(_finalPrice)} must be received',
          hint: '0.00',
          icon: Icons.payments_outlined,
          enabled: !_saving,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
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
                  _amountReceivedController.text =
                      _plain(_finalPrice);
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

  /// Same look as the "Sell on Credit" switch in Step 5 (Delivery Options).
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
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
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
                  // Nothing is assumed paid until the person says so.
                  if (!_amountEdited) {
                    _amountReceivedController.text = '';
                  }
                } else {
                  // Off -> the full amount is expected.
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
  // PAYMENT SUMMARY — live
  // ---------------------------------------------------------------------------

  Widget _buildSummaryCard(Sale sale) {
    final rate = sale.bookingPricePerKg ?? 0;
    final ready = _pickupWeight > 0;
    final due = _finalPrice;
    final remaining = _remaining;
    final owes = ready && due > 0;
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
                  style: AppTheme.heading(
                    size: 13,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (statusLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
          _summaryRow(
            sale.isFixedPrice
                ? 'Goat Sale (fixed price)'
                : 'Goat Sale (${_trimZeros(_pickupWeight)} kg × '
                '${_currency(rate)})',
            _currency(_goatSaleValue),
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
            'Advance Paid',
            '− ${_currency(_advancePaid)}',
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Final Amount Due',
            _currency(due),
            emphasized: true,
          ),
          if (owes) ...[
            const SizedBox(height: 8),
            _summaryRow(
              'Received Now',
              _currency(_receivedNow),
            ),
            const SizedBox(height: 8),
            _summaryRow(
              onCreditBalance
                  ? 'Outstanding (On Credit)'
                  : 'Remaining Balance',
              _currency(remaining),
              emphasized: true,
            ),
          ],
          if (owes && onCreditBalance) ...[
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
          if (owes && !_onCredit && remaining <= 0 && _extraReceived <= 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.verified_rounded,
              color: AppColors.success,
              text: 'Paid in full — this sale will be marked Paid and '
                  'nothing goes on credit.',
            ),
          ],
          if (ready && _transport > 0) ...[
            const SizedBox(height: 10),
            _infoLine(
              icon: Icons.local_shipping_outlined,
              color: AppColors.textGrey,
              text: 'Transportation is passed on to the transport team, so '
                  'it is not counted as farm revenue.',
            ),
          ],
          const SizedBox(height: 10),
          _infoLine(
            icon: Icons.lock_clock_outlined,
            color: AppColors.textGrey,
            text: 'Uses the rate fixed at booking time (${_currency(rate)} '
                '/ kg), not today\'s rate.',
          ),
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
          child: Text(
            text,
            style: AppTheme.body(size: 10.5, color: color),
          ),
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
        // Expanded label so a long label wraps instead of overflowing.
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

/// One goat in the sale that needs attention before handover: it is not
/// marked Healthy, or it has care that is overdue or due soon. Goats with
/// nothing to flag are not listed.
class _GoatHealthAlert {
  final String goatId;
  final String healthStatus;
  final bool isUnwell;

  /// Overdue or due-soon care, earliest first.
  final List<GoatHealthRecord> pendingCare;

  const _GoatHealthAlert({
    required this.goatId,
    required this.healthStatus,
    required this.isUnwell,
    required this.pendingCare,
  });
}