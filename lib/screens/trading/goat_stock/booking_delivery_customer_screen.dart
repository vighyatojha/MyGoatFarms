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
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/goat_service.dart';
import 'package:mygoatfarms/widgets/lot_origin_card.dart';
import 'package:mygoatfarms/widgets/edit_wait_booking_sheet.dart';
import 'package:mygoatfarms/widgets/sale_actions.dart';
import 'package:mygoatfarms/widgets/excess_action_picker.dart';
import 'package:mygoatfarms/screens/trading/purchase_goats/purchase_wizard_widgets.dart';
import 'package:mygoatfarms/screens/home/delivery_flow/delivery_section.dart';

/// Booking / Holding — one customer.
///
/// Flow: Booking & Holding (customers) -> customer profile -> Booking &
/// Holding -> select goats -> THIS SCREEN: a photo + age card for each
/// selected goat ([DeliveryGoatUpdatesCard]), then the bookings with
/// their calculation -> Complete Sale -> receipts (view / download /
/// share).
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

  /// Pickup weight per goat, keyed by goat ID (a lot booking has one
  /// total under `lot:<saleId>`). The goat value is the agreed amount x
  /// pickup weight / booked weight (WEIGHT-BASED PRICE).
  final Map<String, TextEditingController> _weights =
  <String, TextEditingController>{};

  /// Newest weight on record per goat (and `lot:<saleId>` totals), from
  /// the goats' profiles — what the pickup-weight fields start from.
  final Map<String, double> _latest = <String, double>{};

  /// Bookings whose latest weights were already asked for.
  final Set<String> _latestRequested = <String>{};

  /// Text each pickup-weight field started with: a field still showing it
  /// has not been typed in, so it may follow a newer weight.
  final Map<String, String> _weightInitial = <String, String>{};

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

  /// Photo + age per goat, saved when the sale is completed.
  final DeliveryGoatUpdates _goatUpdates = DeliveryGoatUpdates();

  bool _submitted = false;
  bool _delivering = false;

  @override
  void dispose() {
    for (final controller in _weights.values) {
      controller.dispose();
    }

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

    _goatUpdates.dispose();

    super.dispose();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _trim(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  // ---------------------------------------------------------------------------
  // PICKUP WEIGHT
  // ---------------------------------------------------------------------------

  /// Pickup-weight field of a registered goat, starting from its last
  /// recorded weight.
  TextEditingController _weightControllerFor(Goat goat) {
    return _weights.putIfAbsent(goat.id, () {
      final weight = _latest[goat.id] ?? goat.weight;
      final controller = TextEditingController(
        text: weight <= 0 ? '' : _trim(weight),
      );
      _weightInitial[goat.id] = controller.text;
      return controller;
    });
  }

  /// The goat's newest weight on record (profile weight history), or the
  /// weight recorded on the goat.
  double _lastWeightOf(Goat goat) => _latest[goat.id] ?? goat.weight;

  /// Asks once per booking for the newest recorded weights, then moves
  /// every pickup-weight field nobody has typed in to them.
  void _requestLatestWeights(BookingDeliverySale entry) {
    if (!_latestRequested.add(entry.id)) return;

    latestRecordedWeights(
      widget.farmId,
      SectionBooking(sale: entry.sale, goats: entry.goats),
    ).then((weights) {
      if (!mounted || weights.isEmpty) return;
      setState(() {
        weights.forEach((key, weight) {
          _latest[key] = weight;
          final controller = _weights[key];
          if (controller != null &&
              controller.text == _weightInitial[key]) {
            controller.text = weight <= 0 ? '' : _trim(weight);
            _weightInitial[key] = controller.text;
          }
        });
      });
    }).catchError((Object _) {
      // Keep the recorded weights; the person can still type them.
    });
  }

  /// One total pickup weight for a booking made from a lot (its goats are
  /// not weighed one by one), starting from the booked weight.
  TextEditingController _lotWeightControllerFor(BookingDeliverySale entry) {
    final key = 'lot:${entry.id}';
    return _weights.putIfAbsent(key, () {
      final weight = _latest[key] ?? entry.bookedWeight;
      final controller = TextEditingController(
        text: weight <= 0 ? '' : _trim(weight),
      );
      _weightInitial[key] = controller.text;
      return controller;
    });
  }

  double _weightOf(Goat goat) {
    return double.tryParse(_weightControllerFor(goat).text.trim()) ?? 0;
  }

  /// Total pickup weight of a booking (rounded so 34.5 + 12.3 leaves no
  /// float noise).
  double _pickupWeightOf(BookingDeliverySale entry) {
    final total = entry.isLotSale
        ? double.tryParse(_lotWeightControllerFor(entry).text.trim()) ?? 0
        : entry.goats.fold<double>(0, (t, goat) => t + _weightOf(goat));

    return (total * 1000).round() / 1000;
  }

  /// The pickup weight to price with, or null while it is not entered yet
  /// (the booked amount is shown until then).
  double? _pickupOrNull(BookingDeliverySale entry) {
    final weight = _pickupWeightOf(entry);
    return weight > 0 ? weight : null;
  }

  bool _missingWeight(BookingDeliverySale entry) => entry.isLotSale
      ? _pickupWeightOf(entry) <= 0
      : entry.goats.any((goat) => _weightOf(goat) <= 0);

  /// Goat value at the pickup weight, before any discount.
  double _goatValueOf(BookingDeliverySale entry) {
    final weight = _pickupOrNull(entry);
    return weight == null
        ? entry.sale.agreedGoatAmount
        : entry.saleValueAt(weight);
  }

  /// Goat amount after the booking discount, before the delivery discount.
  double _goatAmountOf(BookingDeliverySale entry) =>
      entry.sale.bookingGoatAmountAt(_pickupOrNull(entry));

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
      pickupWeight: _pickupOrNull(entry),
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
        pickupWeight: _pickupOrNull(entry),
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
      pickupWeight: _pickupOrNull(entry),
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
    final goatAmount = _goatAmountOf(entry);

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

        // A lot booking's total pickup weight follows its new booked
        // weight (goats were split off).
        final lot = _weights['lot:${entry.id}'];
        if (lot != null) {
          lot.text = entry.bookedWeight <= 0 ? '' : _trim(entry.bookedWeight);
          _weightInitial['lot:${entry.id}'] = lot.text;
        }

        // Goats were split off: ask again for the remaining goats' weights.
        _latest.remove('lot:${entry.id}');
        _latestRequested.remove(entry.id);
      }

      _requestLatestWeights(entry);
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

    final missingWeight = picked.any(_missingWeight);
    final invalidAmount =
    picked.any((entry) => !_amountValid(customer, entry));

    if (missingWeight || invalidAmount) {
      setState(() {
        _submitted = true;
      });

      _snack(
        missingWeight
            ? 'Enter a pickup weight for every selected goat.'
            : 'Check the amount received for every selected booking.',
        error: true,
      );

      return;
    }

    final pickedIds = <String>{for (final entry in picked) entry.id};
    final goatProblem = _goatUpdates.validate(pickedIds);

    if (goatProblem != null) {
      _snack(goatProblem, error: true);
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
        pickupWeight: _pickupWeightOf(entry),
        expectedRemaining: due,
        amountReceivedNow: due > 0 ? _receivedNowOf(customer, entry) : 0,
        onCredit: due > 0 && _onCredit,
        excessAction: excessAction,
      );
    }

    setState(() {
      _delivering = true;
    });

    // The photos and ages typed at the top are saved first. If that
    // fails, nothing is completed and the person can try again.
    try {
      await _goatUpdates.save(widget.farmId, pickedIds);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _delivering = false;
      });
      _snack(
        'Could not save the goat photos / ages: '
            '${FirestoreService.instance.describeError(e)}',
        error: true,
      );
      return;
    }

    if (!mounted) return;

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

    // Receipts of the bookings that were completed: view, download or
    // share them.
    final deliveredIds = [for (final o in result.delivered) o.saleId];
    if (deliveredIds.isNotEmpty && mounted) {
      await showDeliveryReceiptsSheet(
        context,
        farmId: widget.farmId,
        saleIds: deliveredIds,
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
                '${_trim(_pickupWeightOf(entry))} kg × '
                    '${_money.format(entry.ratePerKg)}/kg + '
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
          DeliveryGoatUpdatesCard(
            farmId: widget.farmId,
            bookings: [
              for (final entry in _picked(customer))
                SectionBooking(sale: entry.sale, goats: entry.goats),
            ],
            updates: _goatUpdates,
            color: DeliverySection.bookingHolding.color,
            enabled: !_delivering,
          ),
          const SizedBox(height: 2),
          _deliveryDateCard(customer),
          const SizedBox(height: 12),
          _selectorBar(customer),
          const SizedBox(height: 9),
          for (var i = 0; i < customer.sales.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _bookingCard(customer, customer.sales[i]),
          ],
          const SizedBox(height: 12),
          if (_picked(customer).isNotEmpty) ...[
            _totalsCard(customer, _picked(customer)),
            const SizedBox(height: 12),
          ],
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
          // 1. HEADER: tick + booking + booked date + live amount due.
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Booking ${entry.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.heading(size: 14),
                            ),
                          ),
                          if (entry.isFixedPrice) ...[
                            const SizedBox(width: 6),
                            _tag('Fixed price'),
                          ],
                        ],
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

                // 2. PRICE: locked rate per KG, the agreed amount and
                // weight it came from, holding since, booking amount.
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _infoChip(
                      Icons.lock_outline_rounded,
                      '${_money.format(entry.ratePerKg)}/kg locked',
                    ),
                    if (entry.isFixedPrice)
                      _infoChip(
                        Icons.sell_outlined,
                        '${_money.format(entry.sale.agreedGoatAmount)} '
                            'fixed for ${_trim(entry.bookedWeight)} kg',
                      )
                    else if (entry.bookedWeight > 0)
                      _infoChip(
                        Icons.scale_outlined,
                        'Booked ${_trim(entry.bookedWeight)} kg',
                      ),
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

                const SizedBox(height: 10),

                // 3. LOTS: every lot this booking's goats came from, with
                // supplier, purchase date and how many goats.
                LotOriginCard(
                  farmId: widget.farmId,
                  bookingId: entry.id,
                  lotDocIds: LotOriginCard.lotsOf(entry.sale, entry.goats),
                  goatsByLot:
                  LotOriginCard.goatsByLotOf(entry.sale, entry.goats),
                  showBookingHeader: false,
                  note: entry.isLotSale
                      ? (entry.sale.sourceLocation == Sale.sourceSupplier
                      ? 'At supplier'
                      : 'At farm')
                      : null,
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

                // 4. GOATS: lot, last recorded weight, pickup weight and
                // what each goat comes to at the locked rate.
                _sectionLabel('Goats · pickup weight'),
                if (entry.isLotSale)
                  _lotRow(customer, entry, selected)
                else
                  for (final goat in entry.goats)
                    _goatRow(customer, entry, goat, selected),
                const SizedBox(height: 3),

                // 5. CHARGES
                _holdingRateField(customer, entry, selected),
                const SizedBox(height: 10),
                _discountField(customer, entry, selected),
                const SizedBox(height: 10),
                _transportField(customer, entry, selected),
                const SizedBox(height: 12),
                // 6. CALCULATION
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

  Widget _goatRow(
      BookingDeliveryCustomer customer,
      BookingDeliverySale entry,
      Goat goat,
      bool selected,
      ) {
    final breed = goat.breed.trim().isEmpty ? 'Breed not specified' : goat.breed.trim();
    final weight = _weightOf(goat);

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
                  Row(
                    children: [
                      Flexible(
                        child: LotIdText(
                          farmId: widget.farmId,
                          lotDocId: goat.purchaseId,
                          style: AppTheme.body(
                            size: 10.5,
                            color: AppColors.info,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          [
                            if (_lastWeightOf(goat) > 0)
                              ' · Last ${_trim(_lastWeightOf(goat))} kg',
                            weight > 0
                                ? ' · ${_money.format(entry.saleValueAt(weight))}'
                                : ' · enter pickup wt',
                          ].join(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            size: 10.5,
                            color: AppColors.textDark,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _weightField(
            customer: customer,
            entry: entry,
            controller: _weightControllerFor(goat),
            selected: selected,
            label: 'Pickup wt',
            width: 108,
          ),
        ],
      ),
    );
  }

  /// A booking made straight from a lot has no goat records, so it shows
  /// the lot and the quantity held, with ONE total pickup weight.
  Widget _lotRow(
      BookingDeliveryCustomer customer,
      BookingDeliverySale entry,
      bool selected,
      ) {
    final pickup = _pickupWeightOf(entry);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
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
                  Text(
                    [
                      if (entry.bookedWeight > 0)
                        'Booked ${_trim(entry.bookedWeight)} kg',
                      if (pickup > 0)
                        _money.format(entry.saleValueAt(pickup)),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 10.5,
                      color: AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _weightField(
            customer: customer,
            entry: entry,
            controller: _lotWeightControllerFor(entry),
            selected: selected,
            label: 'Total pickup wt',
            width: 118,
          ),
        ],
      ),
    );
  }

  Widget _weightField({
    required BookingDeliveryCustomer customer,
    required BookingDeliverySale entry,
    required TextEditingController controller,
    required bool selected,
    required String label,
    required double width,
  }) {
    final invalid = _submitted &&
        selected &&
        (double.tryParse(controller.text.trim()) ?? 0) <= 0;

    OutlineInputBorder border(Color color, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: w),
        );

    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: selected && !_delivering,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        textAlign: TextAlign.right,
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
          labelText: label,
          labelStyle: AppTheme.body(size: 10.5),
          suffixText: 'kg',
          suffixStyle: AppTheme.body(size: 11),
          errorText: invalid ? 'Required' : null,
          errorStyle: const TextStyle(fontSize: 9.5),
          filled: true,
          fillColor: selected ? Colors.white : AppColors.paleGreen,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          border: border(AppColors.divider),
          enabledBorder: border(AppColors.divider),
          disabledBorder: border(AppColors.divider.withValues(alpha: 0.6)),
          focusedBorder: border(AppColors.darkGreen, 1.4),
          errorBorder: border(AppColors.error),
          focusedErrorBorder: border(AppColors.error, 1.4),
        ),
      ),
    );
  }

  /// Every ticked booking added up: weight booked vs weight now, goat
  /// value at the locked rates, discounts, holding, transport, what was
  /// paid and what is due.
  Widget _totalsCard(
      BookingDeliveryCustomer customer,
      List<BookingDeliverySale> picked,
      ) {
    double sum(double Function(BookingDeliverySale e) f) =>
        Sale.roundMoney(picked.fold<double>(0, (t, e) => t + f(e)));

    final booked = picked.fold<double>(0, (t, e) => t + e.bookedWeight);
    final pickup = picked.fold<double>(0, (t, e) => t + _pickupWeightOf(e));
    final goatValue = sum(_goatValueOf);
    final discount =
    sum((e) => Sale.roundMoney(e.bookingDiscount + _discountOf(e)));
    final holding = sum((e) => _holdingChargesOf(customer, e));
    final transport = sum(_transportOf);
    final paid = sum((e) => e.bookingAmount);
    final due = sum((e) => _finalAmountOf(customer, e));
    final extra = sum((e) => _excessOf(customer, e));
    final goats = _goatCountOf(picked);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.darkGreen.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total · ${_goats(goats)} · ${picked.length} '
                '${picked.length == 1 ? 'booking' : 'bookings'}',
            style: AppTheme.heading(size: 14),
          ),
          const SizedBox(height: 8),
          if (booked > 0) ...[
            _calcRow('Booked weight', '${_trim(booked)} kg'),
            const SizedBox(height: 6),
          ],
          _calcRow(
            'Pickup weight',
            '${_trim(pickup)} kg${_weightChange(booked, pickup)}',
          ),
          const SizedBox(height: 6),
          _calcRow('Goat value', _money.format(goatValue)),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            _calcRow('Discount', '− ${_money.format(discount)}'),
          ],
          if (holding > 0) ...[
            const SizedBox(height: 6),
            _calcRow('Holding charges', '+ ${_money.format(holding)}'),
          ],
          if (transport > 0) ...[
            const SizedBox(height: 6),
            _calcRow('Transportation', '+ ${_money.format(transport)}'),
          ],
          const SizedBox(height: 6),
          _calcRow('Booking amount paid', '− ${_money.format(paid)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          _calcRow('Total due', _money.format(due), emphasized: true),
          if (extra > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Extra (booking amount over the bill)',
              _money.format(extra),
              emphasized: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text.toUpperCase(),
        style: AppTheme.body(
          size: 9.5,
          color: AppColors.textGrey,
          weight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTheme.body(
          size: 9.5,
          color: AppColors.info,
          weight: FontWeight.w700,
        ),
      ),
    );
  }

  /// " (+10 kg)" / " (−5 kg)" against the booked weight; empty when the
  /// same or nothing was booked.
  String _weightChange(double booked, double pickup) {
    if (booked <= 0 || pickup <= 0) return '';
    final diff = (pickup - booked) * 1000;
    if (diff.round() == 0) return '';
    final kg = (diff.abs().round()) / 1000;
    return ' (${diff > 0 ? '+' : '−'}${_trim(kg)} kg)';
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
    final tooMuch = typed > _goatAmountOf(entry);

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
            '(${_money.format(_goatAmountOf(entry))}).'
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
          if (entry.bookedWeight > 0) ...[
            _calcRow('Booked weight', '${_trim(entry.bookedWeight)} kg'),
            const SizedBox(height: 6),
          ],
          _calcRow(
            'Pickup weight',
            _pickupOrNull(entry) == null
                ? 'Not entered'
                : '${_trim(_pickupWeightOf(entry))} kg'
                '${_weightChange(entry.bookedWeight, _pickupWeightOf(entry))}',
          ),
          const SizedBox(height: 6),
          _calcRow(
            entry.isFixedPrice
                ? 'Locked rate (${_money.format(entry.sale.agreedGoatAmount)}'
                ' ÷ ${_trim(entry.bookedWeight)} kg)'
                : 'Locked rate',
            '${_money.format(entry.ratePerKg)}/kg',
          ),
          const SizedBox(height: 6),
          _calcRow(
            _pickupOrNull(entry) == null
                ? 'Goat value (booked)'
                : 'Goat value (${_trim(_pickupWeightOf(entry))} kg × '
                '${_money.format(entry.ratePerKg)})',
            _money.format(_goatValueOf(entry)),
          ),
          if (entry.bookingDiscount > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Booking discount',
              '− ${_money.format(entry.bookingDiscount)}',
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
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  _delivering ? 'Completing…' : (all ? 'Complete Sale' : 'Complete Selected'),
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