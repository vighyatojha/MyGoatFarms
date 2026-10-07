import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/goat_icons.dart';
import 'package:mygoatfarms/models/booking_delivery_group.dart';
import 'package:mygoatfarms/models/expense_categories.dart';
import 'package:mygoatfarms/models/goat_model.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/models/sale_settlement.dart';
import 'package:mygoatfarms/models/wait_delivery_group.dart';
import 'package:mygoatfarms/services/booking_delivery_service.dart';
import 'package:mygoatfarms/services/goat_service.dart';
import 'package:mygoatfarms/widgets/lot_origin_card.dart';
import 'package:mygoatfarms/widgets/edit_wait_booking_sheet.dart';
import 'package:mygoatfarms/widgets/sale_actions.dart';
import 'package:mygoatfarms/widgets/excess_action_picker.dart';
import 'package:mygoatfarms/screens/trading/purchase_goats/purchase_wizard_widgets.dart';

/// Booking / Holding — one customer.
///
/// Flow: Goat Stock -> Booked tab -> this customer's goats, grouped by
/// booking -> Deliver All at Once.
///
/// Unlike Wait for Delivery, a Booking sale is never repriced by weight:
/// its final amount is
///
///   Goat Sale Amount + Holding Charges + Transportation − Booking Amount
///   Holding Charges = Holding Days × Holding Charge/Day
///
/// Transportation is an optional charge typed per booking at delivery.
/// It is added to the amount due and shown on the bill, but it is passed
/// on to the transport team, so it is never farm revenue.
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

  /// When set, ONLY these bookings (sale IDs) are shown and delivered —
  /// used by the dashboard's Complete → Select goats flow
  /// (CompleteGoatsSelectorScreen), which passes the bookings of the goats
  /// that were ticked. Everything else on this screen (delivery date,
  /// holding charges, booking amount paid, remaining balance, discount,
  /// transport, credit, excess handling and saving) works exactly as
  /// before. Null = every open booking of the customer, the original
  /// behaviour.
  final Set<String>? onlySaleIds;

  const BookingDeliveryCustomerScreen({
    super.key,
    required this.farmId,
    required this.customerKey,
    required this.customerName,
    this.onlySaleIds,
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

  /// Optional transportation charge per booking, keyed by sale ID. It is
  /// added to the amount due but is passed on to the transport team, so
  /// it is not farm revenue.
  final Map<String, TextEditingController> _transports =
  <String, TextEditingController>{};

  /// Holding charge per day per booking, keyed by sale ID. Starts at the
  /// rate agreed at booking and can be edited here at delivery (type 0 to
  /// waive it). Blank falls back to the booked rate.
  final Map<String, TextEditingController> _holdingRates =
  <String, TextEditingController>{};

  /// Optional extra discount per booking, given at delivery. Comes off the
  /// goat amount only — never holding charges or transport.
  final Map<String, TextEditingController> _discounts =
  <String, TextEditingController>{};

  /// Bookings whose amount field the person has typed in themselves.
  /// Until then it follows the final amount as the delivery date
  /// changes, same as the single-goat screen.
  final Set<String> _amountEdited = <String>{};

  /// What each booking looked like the last time it was drawn, so the
  /// amount received can follow the new final amount once a booking has
  /// been edited (goats split off) — here or on another device.
  final Map<String, ({int goats, double total, double paid})> _signatures =
  <String, ({int goats, double total, double paid})>{};

  /// Delivery date shared across every booking in this batch — holding
  /// charges are computed against it. Set once the customer's bookings
  /// are known (never before the latest holding-start among them).
  DateTime? _deliveryDate;

  /// The customer's bookings in the order they are shown. Dues are
  /// covered in this order when the ticked bookings are netted against
  /// each other.
  List<BookingDeliverySale> _ordered = const <BookingDeliverySale>[];

  /// Sell on Credit for this batch. Whatever is left after the amount
  /// received goes onto the customer's outstanding balance instead of
  /// blocking the delivery.
  bool _onCredit = false;

  /// How the money received now is being paid, for every booking in
  /// this batch.
  String _method = FinancePaymentMethods.cash;

  /// What to do with any booking amount that turns out to be MORE than a
  /// booking's final bill. One choice for the whole batch; only used when
  /// there is an extra.
  ExcessAction _excessAction = ExcessAction.carryToAdvance;

  bool _submitted = false;
  bool _delivering = false;

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }

    for (final controller in _transports.values) {
      controller.dispose();
    }

    for (final controller in _holdingRates.values) {
      controller.dispose();
    }

    for (final controller in _discounts.values) {
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

  /// Final Amount Due for a booking. For a ticked booking this is the
  /// figure AFTER extra booking amount from the other ticked bookings has
  /// been applied (see [_allocation]) — the same netting the service
  /// re-runs before saving.
  double _finalAmountOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final alloc = _allocation(customer).bySale[entry.id];

    if (alloc != null) return alloc.toCollect;

    return entry.finalAmountAt(
      _deliveryDateOr(customer),
      transport: _transportOf(entry),
      discount: _discountOf(entry),
      holdingRate: _holdingRateOf(entry),
    );
  }

  /// The ticked bookings treated as ONE customer settlement: a booking
  /// whose booking amount is more than its bill pays part of another
  /// booking's due.
  WaitDeliveryAllocation _allocation(BookingDeliveryCustomer customer) {
    final bills = <WaitDeliveryBill>[];
    final date = _deliveryDateOr(customer);

    for (final entry in _ordered) {
      if (!_selected.contains(entry.id)) continue;

      final settlement = entry.settlementAt(
        date,
        transport: _transportOf(entry),
        discount: _discountOf(entry),
        holdingRate: _holdingRateOf(entry),
      );

      bills.add(
        WaitDeliveryBill(
          saleId: entry.id,
          payable: settlement.payable,
          advancePaid: entry.bookingAmount,
        ),
      );
    }

    return WaitDeliveryAllocator.allocate(bills);
  }

  List<WaitDeliveryTransfer> _transfersInto(
      BookingDeliveryCustomer customer, BookingDeliverySale entry) =>
      _allocation(customer).transfersInto(entry.id);

  List<WaitDeliveryTransfer> _transfersFrom(
      BookingDeliveryCustomer customer, BookingDeliverySale entry) =>
      _allocation(customer).transfersFrom(entry.id);

  double _totalTransferred(BookingDeliveryCustomer customer) {
    return Sale.roundMoney(
      _allocation(customer).transfers.fold<double>(
        0,
            (sum, t) => sum + t.amount,
      ),
    );
  }

  /// What the booking amount covered beyond this booking's final bill (0
  /// when it did not). Same maths as SalesService.completeBookingDelivery.
  ///
  /// For a ticked booking only the extra LEFT after the other bookings'
  /// dues were covered counts — that is the part that still needs the
  /// Add to advance / Return to customer choice.
  double _excessOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    final alloc = _allocation(customer).bySale[entry.id];

    if (alloc != null) return alloc.leftoverExcess;

    return entry.excessAt(
      _deliveryDateOr(customer),
      transport: _transportOf(entry),
      discount: _discountOf(entry),
      holdingRate: _holdingRateOf(entry),
    );
  }

  double _totalExcess(BookingDeliveryCustomer customer, List<BookingDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _excessOf(customer, entry)),
    );
  }

  TextEditingController _transportControllerFor(BookingDeliverySale entry) {
    return _transports.putIfAbsent(
      entry.id,
          () => TextEditingController(),
    );
  }

  /// The transportation charge typed for a booking (blank counts as 0).
  double _transportOf(BookingDeliverySale entry) {
    final text = _transportControllerFor(entry).text.trim();

    if (text.isEmpty) return 0;

    final number = double.tryParse(text) ?? 0;

    return number <= 0 ? 0 : Sale.roundMoney(number);
  }

  TextEditingController _holdingRateControllerFor(BookingDeliverySale entry) {
    return _holdingRates.putIfAbsent(
      entry.id,
          () => TextEditingController(
        text: entry.holdingChargePerDay > 0
            ? _plainMoney(entry.holdingChargePerDay)
            : '',
      ),
    );
  }

  /// The holding charge per day to use for this booking: what was typed,
  /// or the booked rate when the box is blank (so clearing it can never
  /// waive the charge by accident — type 0 to waive it on purpose).
  double _holdingRateOf(BookingDeliverySale entry) {
    final text = _holdingRateControllerFor(entry).text.trim();

    if (text.isEmpty) return entry.holdingChargePerDay;

    final number = double.tryParse(text) ?? 0;

    return number <= 0 ? 0 : Sale.roundMoney(number);
  }

  bool _holdingRateChanged(BookingDeliverySale entry) {
    return Sale.roundMoney(_holdingRateOf(entry)) !=
        Sale.roundMoney(entry.holdingChargePerDay);
  }

  TextEditingController _discountControllerFor(BookingDeliverySale entry) {
    return _discounts.putIfAbsent(
      entry.id,
          () => TextEditingController(),
    );
  }

  /// The extra discount typed for a booking (blank counts as 0), never more
  /// than the booking's goat amount.
  double _discountOf(BookingDeliverySale entry) {
    final text = _discountControllerFor(entry).text.trim();

    if (text.isEmpty) return 0;

    final number = double.tryParse(text) ?? 0;

    if (number <= 0) return 0;

    final value = Sale.roundMoney(number);
    final goatAmount = entry.sale.totalSaleAmount;

    return value > goatAmount ? goatAmount : value;
  }

  int _holdingDaysOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    return entry.holdingDaysAt(_deliveryDateOr(customer));
  }

  double _holdingChargesOf(BookingDeliveryCustomer customer, BookingDeliverySale entry) {
    return entry.holdingChargesAt(
      _deliveryDateOr(customer),
      ratePerDay: _holdingRateOf(entry),
    );
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
    _ordered = customer.sales;

    final ids = customer.sales.map((entry) => entry.id).toSet();

    for (final id in ids) {
      if (_seen.add(id)) {
        _selected.add(id);
      }
    }

    _selected.removeWhere((id) => !ids.contains(id));

    for (final entry in customer.sales) {
      final now = (
      goats: entry.goatCount,
      total: entry.sale.totalSaleAmount,
      paid: entry.bookingAmount,
      );

      final before = _signatures[entry.id];

      _signatures[entry.id] = now;

      // The booking was edited: let the amount received follow the new
      // final amount again instead of keeping a figure typed for the old
      // one.
      if (before != null && before != now) {
        _amountEdited.remove(entry.id);
      }
    }

    _syncAllAutoAmounts(customer);
  }

  /// Edit booking: pick how many (or which) goats go out now and what
  /// happens to the rest. The booking is trimmed to the goats being
  /// delivered; the person then delivers it as usual.
  Future<void> _openEditBooking(BookingDeliverySale entry) async {
    if (_delivering) return;

    final result = await showEditWaitBookingSheet(
      context,
      farmId: widget.farmId,
      sale: entry.sale,
      goats: entry.goats,
    );

    if (result == null || !mounted) return;

    setState(() {
      // The goats to deliver stay on this booking, so tick it. A kept
      // booking is marked as seen WITHOUT being ticked, otherwise it would
      // be selected for delivery automatically as a "new" booking.
      _selected.add(result.deliverSaleId);

      final kept = result.keptSaleId;

      if (kept != null) {
        _seen.add(kept);
        _selected.remove(kept);
      }
    });

    final deliver = _goats(result.deliverCount);
    final left = _goats(result.leftoverCount);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.keptSaleId != null
              ? 'Booking ${result.deliverSaleId} now has $deliver to '
              'deliver. $left kept on booking ${result.keptSaleId}.'
              : 'Booking ${result.deliverSaleId} now has $deliver to '
              'deliver. $left went back to stock.',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    return picked.fold<int>(0, (sum, entry) => sum + entry.goatCount);
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
    final excessAction = _excessAction;
    final excessById = <String, double>{
      for (final entry in picked) entry.id: _excessOf(customer, entry),
    };
    final transferred = _totalTransferred(customer);

    for (final entry in picked) {
      final transport = _transportOf(entry);
      final discount = _discountOf(entry);
      final holdingRate = _holdingRateOf(entry);
      // After the bookings were netted against each other.
      final due = _finalAmountOf(customer, entry);

      payments[entry.id] = BookingDeliveryPayment(
        transportCharges: transport,
        discount: discount,
        holdingChargePerDay: holdingRate,
        expectedRemaining: due,
        amountReceivedNow: due > 0 ? _receivedNowOf(customer, entry) : 0,
        onCredit: due > 0 && _onCredit,
        excessAction: excessAction,
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
      final extra = _extraDelivered(excessById, result);

      var base = left > 0
          ? '${_goats(delivered)} delivered — '
          '${_money.format(left)} added to outstanding balance.'
          : '${_goats(delivered)} delivered — paid in full.';

      if (transferred > 0) {
        base = '$base ${_money.format(transferred)} of extra booking '
            'amount was applied to another booking.';
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            extra > 0
                ? '$base ${_extraText(extra, excessAction)}'
                : base,
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

  /// Extra money on the bookings that WERE delivered.
  double _extraDelivered(
      Map<String, double> excessById,
      BookingDeliveryBatchResult result,
      ) {
    return Sale.roundMoney(
      result.delivered.fold<double>(
        0,
            (sum, outcome) => sum + (excessById[outcome.saleId] ?? 0),
      ),
    );
  }

  String _extraText(double extra, ExcessAction action) {
    return action == ExcessAction.carryToAdvance
        ? 'Extra ${_money.format(extra)} added to the customer\'s advance.'
        : 'Extra ${_money.format(extra)} to be returned to the customer '
        '(recorded as a refund).';
  }

  Future<void> _showFailures(
      List<BookingDeliverySale> picked,
      BookingDeliveryBatchResult result,
      ) async {
    final deliveredGoats = picked
        .where((entry) => result.delivered.any((o) => o.saleId == entry.id))
        .fold<int>(0, (sum, entry) => sum + entry.goatCount);

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
    final excess = _totalExcess(customer, picked);

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
                  if (_allocation(customer).hasTransfers) ...[
                    for (final transfer in _allocation(customer).transfers) ...[
                      _confirmTotalRow(
                        '${transfer.fromSaleId} extra settles part of '
                            '${transfer.toSaleId}',
                        transfer.amount,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      'No new money changes hands for this part — it was '
                          'already received as the extra booking amount.',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _confirmTotalRow('Goat value + holding charges total', due),
                  const SizedBox(height: 6),
                  _confirmTotalRow('Received now', receivedNow),
                  if (excess > 0) ...[
                    const SizedBox(height: 6),
                    _confirmTotalRow(
                      'Extra (booking amount over the bill)',
                      excess,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _excessAction == ExcessAction.carryToAdvance
                          ? 'The extra is added to the customer\'s advance '
                          'balance.'
                          : 'The extra is returned to the customer and '
                          'recorded as a Customer Refund.',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ],
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
                'Booking ${entry.id} · ${_goats(entry.goatCount)}',
                style: AppTheme.heading(size: 12.5),
              ),
              const SizedBox(height: 1),
              Text(
                '$days holding day${days == 1 ? '' : 's'} × '
                    '${_money.format(_holdingRateOf(entry))} − '
                    '${_money.format(entry.bookingAmount)} booking amount'
                    '${_discountOf(entry) > 0 ? ' − ${_money.format(_discountOf(entry))} discount' : ''}'
                    '${_transportOf(entry) > 0 ? ' + ${_money.format(_transportOf(entry))} transport' : ''}',
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
              for (final t in _transfersInto(customer, entry))
                Text(
                  'Covered by extra from ${t.fromSaleId}: '
                      '−${_money.format(t.amount)}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
              for (final t in _transfersFrom(customer, entry))
                Text(
                  'Extra ${_money.format(t.amount)} → applied to '
                      '${t.toSaleId}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
              if (_excessOf(customer, entry) > 0)
                Text(
                  'Extra: ${_money.format(_excessOf(customer, entry))}',
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

              // Checkout opened from "Select goats to complete": keep only
              // the bookings of the selected goats.
              final only = widget.onlySaleIds;

              if (customer != null && only != null) {
                final kept = customer.sales
                    .where((entry) => only.contains(entry.id))
                    .toList();

                customer = kept.isEmpty
                    ? null
                    : BookingDeliveryCustomer(
                  key: customer.key,
                  name: customer.name,
                  mobile: customer.mobile,
                  address: customer.address,
                  sales: kept,
                );
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
                  [
                    widget.onlySaleIds == null
                        ? 'Booking / Holding'
                        : 'Checkout · selected goats',
                    if (subtitle != null) subtitle,
                  ].join(' · '),
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
                color: color.withValues(alpha: 0.12),
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
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
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
              ? AppColors.darkGreen.withValues(alpha: 0.55)
              : AppColors.divider.withValues(alpha: 0.6),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Which lot these goats came from, with the booking ID.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
            child: LotOriginCard(
              farmId: widget.farmId,
              bookingId: entry.id,
              lotDocIds: LotOriginCard.lotsOf(entry.sale, entry.goats),
              note: entry.isLotSale &&
                  entry.sale.sourceLocation == Sale.sourceSupplier
                  ? 'At supplier'
                  : null,
            ),
          ),
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
                        '${_goats(entry.goatCount)} · Booked '
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
                SaleActionsMenu(
                  farmId: widget.farmId,
                  sale: entry.sale,
                  // The open-bookings stream refreshes this list by itself
                  // after an edit, a cancel or a delete.
                  onResult: (_) {
                    if (mounted) {
                      setState(() => _selected.remove(entry.id));
                    }
                  },
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

                // Edit the deal or cancel it while nothing is delivered.
                // Cancel puts the goats back in stock (or the lot) and
                // removes the sale; the open-deals stream refreshes this
                // list by itself.
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: OpenDealButtons(
                    farmId: widget.farmId,
                    sale: entry.sale,
                    onResult: (_) {
                      if (mounted) {
                        setState(() => _selected.remove(entry.id));
                      }
                    },
                  ),
                ),

                // Deliver only some of the goats, and keep or remove the rest.
                if (entry.goatCount > 1) _editBookingButton(entry),
                if (entry.isLotSale)
                  _lotRow(entry)
                else
                  for (final goat in entry.goats) _goatRow(goat),
                const SizedBox(height: 3),
                _holdingRateField(customer, entry, selected),
                const SizedBox(height: 10),
                _discountField(customer, entry, selected),
                const SizedBox(height: 10),
                _transportField(customer, entry, selected),
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

  /// Opens Edit booking — deliver one or any number of the booking's goats
  /// and keep or remove the rest.
  Widget _editBookingButton(BookingDeliverySale entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: _delivering ? null : () => _openEditBooking(entry),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.stockTeal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.stockTeal.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.edit_outlined,
                size: 16,
                color: AppColors.stockTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit booking',
                      style: AppTheme.heading(
                        size: 12,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    Text(
                      'Deliver some goats now · keep or remove the rest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 10),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.stockTeal,
              ),
            ],
          ),
        ),
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

  /// A booking made straight from a lot has no goat records, so it shows
  /// the lot and the quantity held instead of a list of goats.
  Widget _lotRow(BookingDeliverySale entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.stockTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.inventory_2_outlined,
                size: 19,
                color: AppColors.stockTeal,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.sale.lotDisplayId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 13.5),
                ),
                Text(
                  '${_goats(entry.goatCount)} held from this lot',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 10.5),
                ),
              ],
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
        color: AppColors.stockTeal.withValues(alpha: 0.12),
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

  InputDecoration _deliveryFieldDecoration({
    required String label,
    required String helper,
    required IconData icon,
    required bool selected,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: AppTheme.body(size: 10.5),
      helperText: helper,
      helperMaxLines: 2,
      helperStyle: AppTheme.body(size: 9.5),
      prefixText: '₹ ',
      prefixStyle: AppTheme.body(size: 12),
      prefixIcon: Icon(icon, size: 18, color: AppColors.textGrey),
      filled: true,
      fillColor: selected ? Colors.white : AppColors.paleGreen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border(AppColors.divider),
      enabledBorder: border(AppColors.divider),
      disabledBorder: border(AppColors.divider.withValues(alpha: 0.6)),
      focusedBorder: border(AppColors.darkGreen, 1.4),
    );
  }

  /// Holding charge per day for one booking, editable at delivery. Starts
  /// at the rate agreed at booking; type 0 to waive holding charges.
  Widget _holdingRateField(
      BookingDeliveryCustomer customer,
      BookingDeliverySale entry,
      bool selected,
      ) {
    return TextField(
      controller: _holdingRateControllerFor(entry),
      enabled: selected && !_delivering,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: (_) {
        setState(() {
          _syncAutoAmount(customer, entry);
        });
      },
      style: AppTheme.body(
        size: 12.5,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      decoration: _deliveryFieldDecoration(
        label: 'Holding Charge / Day',
        helper: _holdingRateChanged(entry)
            ? 'Changed from the booked '
            '${_money.format(entry.holdingChargePerDay)} / day. '
            'Type 0 to waive.'
            : 'Booked rate. Edit to change the holding charge, or 0 to '
            'waive it.',
        icon: Icons.hotel_outlined,
        selected: selected,
      ),
    );
  }

  /// Optional extra discount for one booking, given at delivery. Comes off
  /// the goat amount only — never holding charges or transport.
  Widget _discountField(
      BookingDeliveryCustomer customer,
      BookingDeliverySale entry,
      bool selected,
      ) {
    final typed = double.tryParse(_discountControllerFor(entry).text.trim()) ?? 0;
    final tooMuch = typed > entry.sale.totalSaleAmount;

    return TextField(
      controller: _discountControllerFor(entry),
      enabled: selected && !_delivering,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: (_) {
        setState(() {
          _syncAutoAmount(customer, entry);
        });
      },
      style: AppTheme.body(
        size: 12.5,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      decoration: _deliveryFieldDecoration(
        label: 'Discount (optional)',
        helper: tooMuch
            ? 'Capped at the goat amount '
            '(${_money.format(entry.sale.totalSaleAmount)}).'
            : 'Comes off the goat amount, not holding or transport.',
        icon: Icons.local_offer_outlined,
        selected: selected,
      ),
    );
  }

  /// Optional transportation charge for one booking, entered at delivery.
  /// It is added to the amount due and shown on the bill, but it is not
  /// farm revenue (it is passed on to the transport team).
  Widget _transportField(
      BookingDeliveryCustomer customer,
      BookingDeliverySale entry,
      bool selected,
      ) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return TextField(
      controller: _transportControllerFor(entry),
      enabled: selected && !_delivering,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: (_) {
        setState(() {
          _syncAutoAmount(customer, entry);
        });
      },
      style: AppTheme.body(
        size: 12.5,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Transportation Charge (optional)',
        labelStyle: AppTheme.body(size: 10.5),
        helperText: 'Added to the amount due — not farm revenue.',
        helperStyle: AppTheme.body(size: 9.5),
        prefixText: '₹ ',
        prefixStyle: AppTheme.body(size: 12),
        prefixIcon: const Icon(
          Icons.directions_car_outlined,
          size: 18,
          color: AppColors.textGrey,
        ),
        filled: true,
        fillColor: selected ? Colors.white : AppColors.paleGreen,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: border(AppColors.divider),
        enabledBorder: border(AppColors.divider),
        disabledBorder: border(AppColors.divider.withValues(alpha: 0.6)),
        focusedBorder: border(AppColors.darkGreen, 1.4),
      ),
    );
  }

  Widget _calcBox(BookingDeliveryCustomer customer, BookingDeliverySale entry, double due) {
    final days = _holdingDaysOf(customer, entry);
    final charges = _holdingChargesOf(customer, entry);
    final transport = _transportOf(entry);
    final excess = _excessOf(customer, entry);
    final deliveryDiscount = _discountOf(entry);

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
          if (entry.bookingDiscount > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Discount (already taken off)',
              _money.format(entry.bookingDiscount),
            ),
          ],
          if (deliveryDiscount > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Discount at Delivery',
              '− ${_money.format(deliveryDiscount)}',
            ),
          ],
          const SizedBox(height: 6),
          _calcRow(
            'Holding Charges ($days day${days == 1 ? '' : 's'} × '
                '${_money.format(_holdingRateOf(entry))})',
            _money.format(charges),
          ),
          if (transport > 0) ...[
            const SizedBox(height: 6),
            _calcRow('Transportation', '+ ${_money.format(transport)}'),
          ],
          const SizedBox(height: 6),
          _calcRow('Booking Amount Paid', '− ${_money.format(entry.bookingAmount)}'),
          for (final t in _transfersInto(customer, entry)) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Covered by extra from ${t.fromSaleId}',
              '− ${_money.format(t.amount)}',
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          _calcRow('Final Amount Due', _money.format(due), emphasized: true),
          for (final t in _transfersFrom(customer, entry)) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Extra applied to ${t.toSaleId}',
              _money.format(t.amount),
              emphasized: true,
            ),
          ],
          if (excess > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Extra (booking amount over the bill)',
              _money.format(excess),
              emphasized: true,
            ),
          ],
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
    final totalExcess = _totalExcess(customer, picked);

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
        child: totalExcess > 0
            ? ExcessActionPicker(
          excess: totalExcess,
          value: _excessAction,
          customerName: customer.name,
          paidLabel: 'booking amount',
          message: 'The booking amount is ${_money.format(totalExcess)} '
              'more than the final bill of the selected bookings, so '
              'there is nothing more to collect.',
          onChanged: _delivering
              ? null
              : (action) {
            setState(() {
              _excessAction = action;
            });
          },
        )
            : Row(
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
          if (totalExcess > 0) ...[
            const SizedBox(height: 14),
            ExcessActionPicker(
              excess: totalExcess,
              value: _excessAction,
              customerName: customer.name,
              paidLabel: 'booking amount',
              message: 'Some bookings were paid ${_money.format(totalExcess)} '
                  'more than their final bill.',
              onChanged: _delivering
                  ? null
                  : (action) {
                setState(() {
                  _excessAction = action;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _creditSwitch(BookingDeliveryCustomer customer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _onCredit ? AppColors.error.withValues(alpha: 0.06) : AppColors.paleGreen,
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
              selectedColor: AppColors.primaryGreen.withValues(alpha: 0.15),
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
    final excess = _totalExcess(customer, picked);
    final received = _totalReceivedNow(customer, picked);
    final all = picked.length == customer.sales.length;
    final canDeliver = picked.isNotEmpty && !_delivering;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -3)),
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
                        left > 0
                            ? 'Stays outstanding'
                            : (received <= 0 && excess > 0)
                            ? (_excessAction == ExcessAction.carryToAdvance
                            ? 'Extra added to advance'
                            : 'Extra to return')
                            : 'Total to collect',
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
                  _money.format(
                    left > 0 ? left : (received > 0 ? received : excess),
                  ),
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
                  disabledBackgroundColor: AppColors.darkGreen.withValues(alpha: 0.35),
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