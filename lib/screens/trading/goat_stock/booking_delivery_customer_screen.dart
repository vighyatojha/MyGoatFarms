import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/booking_delivery_group.dart';
import '../../../models/expense_categories.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/booking_delivery_service.dart';
import '../../../services/goat_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Booking / Holding — one customer.
///
/// Flow: Goat Stock -> Booked tab -> this customer's goats, grouped by
/// booking -> Deliver All at Once.
///
/// Unlike Wait for Delivery, a Booking sale is never repriced by weight:
/// its final amount is
///
///   Goat Sale Amount + Holding Charges − Booking Amount
///   Holding Charges = Holding Days × Holding Charge/Day
///
/// counted inclusively from the day holding started to the delivery
/// date — the exact formula CompleteBookingDeliveryScreen shows and
/// SalesService.completeBookingDelivery saves. Because the amount depends
/// on the delivery date rather than a per-goat field, one delivery date
/// is chosen for the whole batch (defaulting to today, never before the
/// latest holding-start among the selected bookings) instead of a
/// per-goat weight input.
///
/// PAYMENT & CREDIT — same rule as the single-goat Complete Delivery
/// screen: once a booking's final amount is known, either it is received
/// in full right now, or Sell on Credit is on and whatever is left
/// becomes the customer's outstanding balance. One Sell on Credit switch
/// and one payment method apply to every booking delivered in this
/// batch; each booking still gets its own "amount received now" field.
/// The rules are enforced again by SalesService per booking, so this
/// screen and the saved sale can never disagree.
class BookingDeliveryCustomerScreen extends StatefulWidget {
  final String farmId;

  /// [BookingDeliveryCustomer.key] of the customer to show.
  final String customerKey;

  /// Only used for the header while loading, or once nothing is left.
  final String customerName;

  const BookingDeliveryCustomerScreen({
    super.key,
    required this.farmId,
    required this.customerKey,
    required this.customerName,
  });

  @override
  State<BookingDeliveryCustomerScreen> createState() =>
      _BookingDeliveryCustomerScreenState();
}

class _BookingDeliveryCustomerScreenState
    extends State<BookingDeliveryCustomerScreen> {
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Goat>> _goatsStream =
  GoatService.instance.goatsStream(widget.farmId);

  late final Stream<List<Sale>> _salesStream =
  BookingDeliveryService.instance.openSalesStream(widget.farmId);

  /// Booking (sale) IDs picked for delivery.
  final Set<String> _selected = <String>{};

  /// Booking IDs already seen, so each booking is pre-selected exactly
  /// once (a booking the person un-ticks must not be re-ticked by the
  /// next stream update).
  final Set<String> _seen = <String>{};

  /// Amount received now per booking, keyed by sale ID.
  final Map<String, TextEditingController> _amounts =
  <String, TextEditingController>{};

  /// Bookings whose amount field the person has typed in themselves.
  /// Until then it follows the final amount as the delivery date
  /// changes, same as the single-goat screen.
  final Set<String> _amountEdited = <String>{};

  /// Delivery date shared across every booking in this batch — holding
  /// charges are computed against it. Set once the customer's bookings
  /// are known (never before the latest holding-start among them).
  DateTime? _deliveryDate;

  /// Sell on Credit for this batch. Whatever is left after the amount
  /// received goes onto the customer's outstanding balance instead of
  /// blocking the delivery.
  bool _onCredit = false;

  /// How the money received now is being paid, for every booking in
  /// this batch.
  String _method = FinancePaymentMethods.cash;

  bool _submitted = false;
  bool _delivering = false;

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }

    super.dispose();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _plainMoney(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  DateTime _deliveryDateOr(BookingDeliveryCustomer customer) {
    final chosen = _deliveryDate;

    if (chosen != null) return chosen;

    final today = _dayOnly(DateTime.now());
    final earliestStart = _dayOnly(customer.earliestHoldingStart);

    return today.isBefore(earliestStart) ? earliestStart : today;
  }

  double _finalAmountOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    return entry.finalAmountAt(_deliveryDateOr(customer));
  }

  int _holdingDaysOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    return entry.holdingDaysAt(_deliveryDateOr(customer));
  }

  double _holdingChargesOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    return entry.holdingChargesAt(_deliveryDateOr(customer));
  }

  TextEditingController _amountControllerFor(BookingDeliverySale entry) {
    return _amounts.putIfAbsent(
      entry.id,
          () => TextEditingController(),
    );
  }

  double _typedAmount(BookingDeliverySale entry) {
    final text = _amountControllerFor(entry).text.trim();

    if (text.isEmpty) return 0;

    return Sale.roundMoney(double.tryParse(text) ?? 0);
  }

  /// What is being received now for this booking. Nothing is asked for
  /// when the holding total already comes to 0.
  double _receivedNowOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final due = _finalAmountOf(customer, entry);

    return due > 0 ? _typedAmount(entry) : 0;
  }

  double _leftAfterReceiptOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final due = _finalAmountOf(customer, entry);
    final left = Sale.roundMoney(due - _receivedNowOf(customer, entry));

    return left <= 0 ? 0 : left;
  }

  /// While Sell on Credit is off, a booking's amount field simply follows
  /// its full final amount as the delivery date changes, until the
  /// person types their own figure.
  void _syncAutoAmount(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    if (_onCredit || _amountEdited.contains(entry.id)) return;

    final due = _finalAmountOf(customer, entry);
    final text = due > 0 ? _plainMoney(due) : '';
    final controller = _amountControllerFor(entry);

    if (controller.text != text) {
      controller.text = text;
    }
  }

  void _syncAllAutoAmounts(BookingDeliveryCustomer customer) {
    for (final entry in customer.sales) {
      if (_selected.contains(entry.id)) {
        _syncAutoAmount(customer, entry);
      }
    }
  }

  /// Ticks new bookings, drops bookings that are no longer open, and
  /// keeps every selected booking's amount field following its final
  /// amount while Sell on Credit is off.
  void _syncSelection(BookingDeliveryCustomer customer) {
    final ids = customer.sales.map((entry) => entry.id).toSet();

    for (final id in ids) {
      if (_seen.add(id)) {
        _selected.add(id);
      }
    }

    _selected.removeWhere((id) => !ids.contains(id));

    _syncAllAutoAmounts(customer);
  }

  List<BookingDeliverySale> _picked(BookingDeliveryCustomer customer) {
    return customer.sales
        .where((entry) => _selected.contains(entry.id))
        .toList();
  }

  double _totalDue(BookingDeliveryCustomer customer, List<BookingDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _finalAmountOf(customer, entry)),
    );
  }

  double _totalReceivedNow(BookingDeliveryCustomer customer, List<BookingDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _receivedNowOf(customer, entry)),
    );
  }

  double _totalLeftAfterReceipt(BookingDeliveryCustomer customer, List<BookingDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _leftAfterReceiptOf(customer, entry)),
    );
  }

  int _goatCountOf(List<BookingDeliverySale> picked) {
    return picked.fold<int>(0, (sum, entry) => sum + entry.goats.length);
  }

  String _goats(int count) => count == 1 ? '1 goat' : '$count goats';

  /// True while every selected booking's typed amount is a valid entry
  /// (within range, and equal to the full final amount when credit is
  /// off). Mirrors the single-goat screen's validator.
  bool _amountValid(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final due = _finalAmountOf(customer, entry);

    if (due <= 0) return true;

    final typed = _typedAmount(entry);

    if (typed < 0 || typed > due) return false;
    if (!_onCredit && typed < due) return false;

    return true;
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ===========================================================================
  // DELIVERY DATE
  // ===========================================================================

  Future<void> _pickDeliveryDate(BookingDeliveryCustomer customer) async {
    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _deliveryDateOr(customer),
      firstDate: _dayOnly(customer.earliestHoldingStart),
      lastDate: _dayOnly(DateTime.now()),
      helpText: 'Delivery date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _deliveryDate = _dayOnly(picked);
      // Final amount changed with the holding days for every booking.
      _amountEdited.clear();
      _syncAllAutoAmounts(customer);
    });
  }

  // ===========================================================================
  // DELIVER
  // ===========================================================================

  Future<void> _deliver(BookingDeliveryCustomer customer) async {
    if (_delivering) return;

    final picked = _picked(customer);

    if (picked.isEmpty) return;

    final invalidAmount =
    picked.any((entry) => !_amountValid(customer, entry));

    if (invalidAmount) {
      setState(() {
        _submitted = true;
      });

      _snack(
        'Check the amount received for every selected booking.',
        error: true,
      );

      return;
    }

    final deliveryDate = _deliveryDateOr(customer);
    final confirmed = await _confirmSheet(customer, picked, deliveryDate);

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final payments = <String, BookingDeliveryPayment>{};

    for (final entry in picked) {
      final due = entry.finalAmountAt(deliveryDate);

      payments[entry.id] = BookingDeliveryPayment(
        expectedRemaining: due,
        amountReceivedNow: due > 0 ? _receivedNowOf(customer, entry) : 0,
        onCredit: due > 0 && _onCredit,
      );
    }

    setState(() {
      _delivering = true;
    });

    final result = await BookingDeliveryService.instance.deliverSales(
      farmId: widget.farmId,
      deliveryDate: deliveryDate,
      payments: payments,
      paymentMethod: _method,
    );

    if (!mounted) return;

    setState(() {
      _delivering = false;
      _submitted = false;
    });

    if (result.failed.isNotEmpty) {
      await _showFailures(picked, result);
    } else {
      final delivered = _goatCountOf(picked);
      final left = result.totalRemainingDelivered;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            left > 0
                ? '${_goats(delivered)} delivered — '
                '${_money.format(left)} added to outstanding balance.'
                : '${_goats(delivered)} delivered — paid in full.',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    // Everything for this customer is done — nothing left to show.
    if (mounted &&
        result.allDelivered &&
        picked.length == customer.sales.length) {
      navigator.pop(true);
    }
  }

  Future<void> _showFailures(
      List<BookingDeliverySale> picked,
      BookingDeliveryBatchResult result,
      ) async {
    final deliveredGoats = picked
        .where((entry) => result.delivered.any((o) => o.saleId == entry.id))
        .fold<int>(0, (sum, entry) => sum + entry.goats.length);

    final leftOnDelivered = result.totalRemainingDelivered;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Some bookings were not delivered',
            style: AppTheme.heading(size: 15),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.delivered.isNotEmpty) ...[
                  Text(
                    leftOnDelivered > 0
                        ? '${_goats(deliveredGoats)} delivered — '
                        '${_money.format(leftOnDelivered)} added to '
                        'outstanding balance.'
                        : '${_goats(deliveredGoats)} delivered — paid in '
                        'full.',
                    style: AppTheme.body(
                      size: 11.5,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final outcome in result.failed) ...[
                  Text(
                    'Booking ${outcome.saleId}',
                    style: AppTheme.heading(size: 12.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    outcome.error ?? 'Could not be delivered.',
                    style: AppTheme.body(
                      size: 11,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'Bookings that failed are still Booked — you can try '
                      'them again.',
                  style: AppTheme.body(size: 10.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'OK',
                style: AppTheme.heading(
                  size: 13,
                  color: AppColors.darkGreen,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmSheet(
      BookingDeliveryCustomer customer,
      List<BookingDeliverySale> picked,
      DateTime deliveryDate,
      ) {
    final due = _totalDue(customer, picked);
    final receivedNow = _totalReceivedNow(customer, picked);
    final left = _totalLeftAfterReceipt(customer, picked);
    final goatCount = _goatCountOf(picked);

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: SingleChildScrollView(
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
                  Text('Confirm delivery', style: AppTheme.heading(size: 16)),
                  const SizedBox(height: 3),
                  Text(
                    '${customer.name} · ${_goats(goatCount)} will be '
                        'marked as Sold, delivered on '
                        '${_dateFormat.format(deliveryDate)}.',
                    style: AppTheme.body(size: 11),
                  ),
                  const SizedBox(height: 14),
                  for (final entry in picked) ...[
                    _confirmRow(customer, entry),
                    const SizedBox(height: 10),
                  ],
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 10),
                  _confirmTotalRow('Goat value + holding charges total', due),
                  const SizedBox(height: 6),
                  _confirmTotalRow('Received now', receivedNow),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          left > 0 ? 'Outstanding (On Credit)' : 'Remaining',
                          style: AppTheme.heading(size: 14),
                        ),
                      ),
                      Text(
                        _money.format(left),
                        style: AppTheme.heading(
                          size: 17,
                          color: left > 0
                              ? AppColors.warning
                              : AppColors.darkGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    left > 0
                        ? 'Added to the customer\'s outstanding balance — '
                        'shown in Finance under Customers on Credit.'
                        : 'Nothing is left owing on these bookings.',
                    style: AppTheme.body(size: 10),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textDark,
                              side:
                              const BorderSide(color: AppColors.divider),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: AppTheme.heading(size: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.darkGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Confirm Delivery',
                              style: AppTheme.heading(
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _confirmRow(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final due = _finalAmountOf(customer, entry);
    final receivedNow = due > 0 ? _receivedNowOf(customer, entry) : 0.0;
    final days = _holdingDaysOf(customer, entry);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking ${entry.id} · ${_goats(entry.goats.length)}',
                style: AppTheme.heading(size: 12.5),
              ),
              const SizedBox(height: 1),
              Text(
                '$days holding day${days == 1 ? '' : 's'} × '
                    '${_money.format(entry.holdingChargePerDay)} − '
                    '${_money.format(entry.bookingAmount)} booking amount',
                style: AppTheme.body(size: 10),
              ),
              if (due > 0)
                Text(
                  'Received now: ${_money.format(receivedNow)}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _money.format(due),
          style: AppTheme.heading(size: 13, color: AppColors.textDark),
        ),
      ],
    );
  }

  Widget _confirmTotalRow(String label, double value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTheme.body(size: 11))),
        Text(
          _money.format(value),
          style: AppTheme.body(
            size: 12,
            color: AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      // Leaving mid-delivery would drop the result message, so back is
      // held until the batch finishes.
      canPop: !_delivering,
      child: StreamBuilder<List<Goat>>(
        stream: _goatsStream,
        builder: (context, goatSnap) {
          return StreamBuilder<List<Sale>>(
            stream: _salesStream,
            builder: (context, saleSnap) {
              if (goatSnap.hasError || saleSnap.hasError) {
                return _shell(
                  title: widget.customerName,
                  body: _messageState(
                    icon: Icons.error_outline_rounded,
                    color: AppColors.error,
                    title: 'Unable to load bookings',
                    subtitle: 'Please check your connection and try again.',
                  ),
                );
              }

              if (!goatSnap.hasData || !saleSnap.hasData) {
                return _shell(
                  title: widget.customerName,
                  body: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryGreen,
                    ),
                  ),
                );
              }

              final customers = BookingDeliveryCustomer.group(
                sales: saleSnap.data!,
                goats: goatSnap.data!,
              );

              BookingDeliveryCustomer? customer;

              for (final candidate in customers) {
                if (candidate.key == widget.customerKey) {
                  customer = candidate;
                  break;
                }
              }

              if (customer == null) {
                return _shell(
                  title: widget.customerName,
                  body: _messageState(
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    title: 'No open bookings',
                    subtitle:
                    'Every booking for this customer has been delivered.',
                  ),
                );
              }

              _syncSelection(customer);

              return _shell(
                title: customer.name,
                subtitle: customer.mobile.isEmpty ? null : customer.mobile,
                body: _body(customer),
                bottom: keyboardOpen ? null : _bottomBar(customer),
              );
            },
          );
        },
      ),
    );
  }

  Widget _shell({
    required String title,
    String? subtitle,
    required Widget body,
    Widget? bottom,
  }) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      bottomNavigationBar: bottom,
      body: SafeArea(
        child: Column(
          children: [
            _header(title, subtitle),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _header(String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Back',
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: _delivering
                    ? null
                    : () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 19),
                ),
                Text(
                  subtitle == null
                      ? 'Booking / Holding'
                      : 'Booking / Holding · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageState({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(height: 11),
            Text(title, textAlign: TextAlign.center, style: AppTheme.heading(size: 15)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: AppTheme.body(size: 11)),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BODY
  // ===========================================================================

  Widget _body(BookingDeliveryCustomer customer) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
      child: Column(
        children: [
          _summaryCard(customer),
          const SizedBox(height: 12),
          _deliveryDateCard(customer),
          const SizedBox(height: 12),
          _selectorBar(customer),
          const SizedBox(height: 9),
          for (var i = 0; i < customer.sales.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _bookingCard(customer, customer.sales[i]),
          ],
          const SizedBox(height: 12),
          _batchPaymentCard(customer, _picked(customer)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  Widget _summaryCard(BookingDeliveryCustomer customer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.divider.withOpacity(0.6)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _summaryStat('${customer.goatCount}', 'Goats held'),
            ),
            _statDivider(),
            Expanded(
              child: _summaryStat(
                '${customer.sales.length}',
                customer.sales.length == 1 ? 'Booking' : 'Bookings',
              ),
            ),
            _statDivider(),
            Expanded(
              child: _summaryStat(
                _money.format(customer.bookingAmountTotal),
                'Booking amount',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(String value, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: AppTheme.heading(size: 17)),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body(size: 9.5),
        ),
      ],
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.divider,
    );
  }

  // ---------------------------------------------------------------------------
  // DELIVERY DATE — shared across the whole batch.
  // ---------------------------------------------------------------------------

  Widget _deliveryDateCard(BookingDeliveryCustomer customer) {
    final date = _deliveryDateOr(customer);

    return WizardSectionCard(
      title: 'Delivery',
      icon: Icons.today_outlined,
      children: [
        WizardDateField(
          label: 'Delivery Date',
          helper: 'Applies to every selected booking below.',
          date: date,
          onTap: _delivering ? () {} : () => _pickDeliveryDate(customer),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTOR
  // ---------------------------------------------------------------------------

  Widget _selectorBar(BookingDeliveryCustomer customer) {
    final total = customer.sales.length;
    final count = _picked(customer).length;

    final bool? value = count == total ? true : (count == 0 ? false : null);

    void toggleAll() {
      if (_delivering) return;

      setState(() {
        if (count == total) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(customer.sales.map((entry) => entry.id));

          _syncAllAutoAmounts(customer);
        }
      });
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: toggleAll,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Checkbox(
                value: value,
                tristate: true,
                activeColor: AppColors.darkGreen,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: _delivering ? null : (_) => toggleAll(),
              ),
              Expanded(
                child: Text(
                  'Select all bookings',
                  style: AppTheme.body(
                    size: 11.5,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text('$count of $total selected', style: AppTheme.body(size: 10.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOOKING CARD
  // ---------------------------------------------------------------------------

  Widget _bookingCard(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final selected = _selected.contains(entry.id);
    final due = _finalAmountOf(customer, entry);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(
          color: selected
              ? AppColors.darkGreen.withOpacity(0.55)
              : AppColors.divider.withOpacity(0.6),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _delivering
                ? null
                : () {
              setState(() {
                if (selected) {
                  _selected.remove(entry.id);
                } else {
                  _selected.add(entry.id);
                  _syncAutoAmount(customer, entry);
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  activeColor: AppColors.darkGreen,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: _delivering
                      ? null
                      : (value) {
                    setState(() {
                      if (value == true) {
                        _selected.add(entry.id);
                        _syncAutoAmount(customer, entry);
                      } else {
                        _selected.remove(entry.id);
                      }
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking ${entry.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heading(size: 14),
                      ),
                      Text(
                        '${_goats(entry.goats.length)} · Booked '
                            '${_dateFormat.format(entry.bookedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 10.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money.format(due),
                      style: AppTheme.heading(
                        size: 14,
                        color: selected ? AppColors.darkGreen : AppColors.textGrey,
                      ),
                    ),
                    Text('Due', style: AppTheme.body(size: 9.5)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _infoChip(
                      Icons.calendar_today_outlined,
                      'Holding since ${_dateFormat.format(entry.holdingStart)}',
                    ),
                    _infoChip(
                      Icons.payments_outlined,
                      '${_money.format(entry.bookingAmount)} booking amount',
                    ),
                  ],
                ),
                const Divider(height: 18, color: AppColors.divider),
                for (final goat in entry.goats) _goatRow(goat),
                const SizedBox(height: 12),
                _calcBox(customer, entry, due),
                if (selected && due > 0) ...[
                  const SizedBox(height: 10),
                  _bookingAmountField(customer, entry, due),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatRow(Goat goat) {
    final breed = goat.breed.trim().isEmpty ? 'Breed not specified' : goat.breed.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _goatAvatar(goat),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goat.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(size: 13.5),
                  ),
                  Text(
                    '$breed · ${goat.age}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatAvatar(Goat goat) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.stockTeal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: goat.photo != null
          ? Image.memory(
        goat.photo!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: 132,
      )
          : const Center(
        child: Icon(GoatIcons.paw, size: 19, color: AppColors.stockTeal),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textGrey),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTheme.body(size: 10, color: AppColors.textDark, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _calcBox(BookingDeliveryCustomer customer, BookingDeliverySale entry, double due) {
    final days = _holdingDaysOf(customer, entry);
    final charges = _holdingChargesOf(customer, entry);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _calcRow('Goat Sale Amount', _money.format(entry.sale.totalSaleAmount)),
          const SizedBox(height: 6),
          _calcRow(
            'Holding Charges ($days day${days == 1 ? '' : 's'} × '
                '${_money.format(entry.holdingChargePerDay)})',
            _money.format(charges),
          ),
          const SizedBox(height: 6),
          _calcRow('Booking Amount Paid', '− ${_money.format(entry.bookingAmount)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          _calcRow('Final Amount Due', _money.format(due), emphasized: true),
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value, {bool emphasized = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: emphasized ? AppTheme.heading(size: 12.5) : AppTheme.body(size: 10.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: emphasized
              ? AppTheme.heading(size: 14, color: AppColors.darkGreen)
              : AppTheme.body(size: 11, color: AppColors.textDark, weight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Per-booking "amount received now" field, shown once a booking with
  /// something due is selected.
  Widget _bookingAmountField(BookingDeliveryCustomer customer, BookingDeliverySale entry, double due) {
    final controller = _amountControllerFor(entry);
    final invalid = _submitted && !_amountValid(customer, entry);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !_delivering,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) {
              setState(() {
                _amountEdited.add(entry.id);
              });
            },
            style: AppTheme.body(size: 12.5, color: AppColors.textDark, weight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Amount Received Now',
              labelStyle: AppTheme.body(size: 10.5),
              prefixText: '₹ ',
              prefixStyle: AppTheme.body(size: 12),
              errorText: invalid
                  ? (_onCredit ? 'More than the amount due' : 'Must equal the full ${_money.format(due)}')
                  : null,
              errorStyle: const TextStyle(fontSize: 9.5),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.darkGreen, width: 1.4),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.error, width: 1.4),
              ),
            ),
          ),
        ),
        if (_onCredit) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: _delivering
                ? null
                : () {
              setState(() {
                _amountEdited.remove(entry.id);
                controller.text = _plainMoney(due);
              });
            },
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(
              'Full',
              style: AppTheme.body(size: 11, color: AppColors.darkGreen, weight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BATCH PAYMENT — Sell on Credit + payment method, applies to every
  // selected booking. This is the option the old single-sale-only
  // Booking / Holding batch flow was missing.
  // ---------------------------------------------------------------------------

  Widget _batchPaymentCard(BookingDeliveryCustomer customer, List<BookingDeliverySale> picked) {
    final anyDue = picked.any((entry) => _finalAmountOf(customer, entry) > 0);

    if (picked.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 16),
        child: Text('Select at least one booking to deliver.', style: AppTheme.body(size: 11.5)),
      );
    }

    if (!anyDue) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 16),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The booking amount already covers every selected booking — '
                    'nothing more to collect.',
                style: AppTheme.body(size: 11),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment (applies to selected bookings)', style: AppTheme.heading(size: 12.5)),
          const SizedBox(height: 10),
          _creditSwitch(customer),
          if (_totalReceivedNow(customer, picked) > 0) ...[
            const SizedBox(height: 12),
            _paymentMethodPicker(),
          ],
        ],
      ),
    );
  }

  Widget _creditSwitch(BookingDeliveryCustomer customer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _onCredit ? AppColors.error.withOpacity(0.06) : AppColors.paleGreen,
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
                  style: AppTheme.body(size: 12, color: AppColors.textDark, weight: FontWeight.w700),
                ),
                Text(
                  _onCredit
                      ? 'Whatever is not received now is added to the '
                      'customer\'s outstanding balance.'
                      : 'Off — the full amount due is received now on '
                      'every selected booking.',
                  style: AppTheme.body(size: 10, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          Switch(
            value: _onCredit,
            activeColor: AppColors.error,
            onChanged: _delivering
                ? null
                : (value) {
              setState(() {
                _onCredit = value;

                if (value) {
                  // Nothing is assumed paid until the person says so.
                  for (final controller in _amounts.entries) {
                    if (!_amountEdited.contains(controller.key)) {
                      controller.value.text = '';
                    }
                  }
                } else {
                  // Off -> the full amount is expected on every booking.
                  _amountEdited.clear();
                  for (final controller in _amounts.values) {
                    controller.text = '';
                  }
                  _syncAllAutoAmounts(customer);
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
          style: AppTheme.body(size: 12, color: AppColors.textGrey, weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: BookingDeliveryService.instance.paymentMethods.map((method) {
            final selected = _method == method;

            return ChoiceChip(
              label: Text(method),
              selected: selected,
              onSelected: _delivering
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
              side: BorderSide(color: selected ? AppColors.primaryGreen : AppColors.divider),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'How the amount received now is being paid, across every '
              'selected booking.',
          style: AppTheme.body(size: 10, color: AppColors.textGrey),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM BAR
  // ---------------------------------------------------------------------------

  Widget _bottomBar(BookingDeliveryCustomer customer) {
    final picked = _picked(customer);
    final goatCount = _goatCountOf(picked);
    final left = _totalLeftAfterReceipt(customer, picked);
    final all = picked.length == customer.sales.length;
    final canDeliver = picked.isNotEmpty && !_delivering;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, -3)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        left > 0 ? 'Stays outstanding' : 'Total to collect',
                        style: AppTheme.body(size: 10.5),
                      ),
                      Text(
                        picked.isEmpty
                            ? 'No booking selected'
                            : '${_goats(goatCount)} · ${picked.length} '
                            '${picked.length == 1 ? 'booking' : 'bookings'}',
                        style: AppTheme.body(size: 9.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  _money.format(left > 0 ? left : _totalReceivedNow(customer, picked)),
                  style: AppTheme.heading(
                    size: 19,
                    color: left > 0 ? AppColors.warning : AppColors.darkGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: canDeliver ? () => _deliver(customer) : null,
                icon: _delivering
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
                    : const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(
                  _delivering ? 'Delivering…' : (all ? 'Deliver All at Once' : 'Deliver Selected'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 13.5, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.darkGreen.withOpacity(0.35),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}