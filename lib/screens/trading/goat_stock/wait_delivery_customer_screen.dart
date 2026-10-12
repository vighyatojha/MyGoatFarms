import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/expense_categories.dart';
import 'package:mygoatfarms/models/goat_model.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/models/sale_settlement.dart';
import 'package:mygoatfarms/models/wait_delivery_group.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/goat_service.dart';
import 'package:mygoatfarms/services/sale_goat_details_service.dart';
import 'package:mygoatfarms/widgets/lot_origin_card.dart';
import 'package:mygoatfarms/widgets/excess_action_picker.dart';
import 'package:mygoatfarms/widgets/fast_route.dart';
import 'package:mygoatfarms/widgets/sale_actions.dart';
import 'package:mygoatfarms/services/wait_delivery_service.dart';
import 'package:mygoatfarms/screens/trading/own_palai/own_palai_goat_profile_screen.dart';
import 'package:mygoatfarms/screens/home/delivery_flow/delivery_section.dart';
import 'package:mygoatfarms/screens/home/delivery_flow/lot_goat_profile_screen.dart';

/// The figures of a booking that other fields on this screen are filled in
/// from (see [_WaitDeliveryCustomerScreenState._syncBookingFields]).
typedef _BookingSignature = ({
int goats,
double weight,
double discount,
double advance,
double fixed,
});

/// Wait on Delivery — one customer.
///
/// Flow: Wait on Delivery (customers) -> customer profile -> Wait on
/// Delivery -> select goats -> THIS SCREEN: ONE card for the whole sale —
/// every selected goat (photo, lot and supplier, booking, locked rate,
/// pickup weight, value), the bookings, one transport, one discount, one
/// calculation and one "received now" -> Complete Sale -> receipts (view
/// / download / share).
///
/// Every booking is still saved as its own sale: the shared fields are
/// split onto the bookings (see [_WaitDeliveryCustomerScreenState
/// ._applySharedFields]).
///
/// A booking (Sale) has one rate — or one agreed [Sale.isFixedPrice]
/// price — one advance and one pickup weight, so all of its goats are
/// delivered together; that is what the booking selector below chooses
/// between. Every goat still has its own pickup-weight field (pre-filled
/// with the weight recorded at booking); a booking's pickup weight is the
/// total of its goats' fields.
///
///   Goat value  = pickup weight x booking rate           (per KG)
///               = the agreed price, whatever the weight   (fixed price)
///   Remaining   = Goat value + transportation - advance paid
///
/// Transportation is an optional charge typed per booking at pickup. It
/// is collected on top of the goat value and shows on the bill, but it is
/// passed on to the transport team, so it is never farm revenue.
///
/// which is the same formula SalesService.completeWaitForDeliveryPickup
/// saves, so the amount shown here is the amount that gets stored.
///
/// PAYMENT & CREDIT — same rule as the single-goat Complete Delivery
/// screen: once a booking's final amount is known, either it is received
/// in full right now, or Sell on Credit is on and whatever is left
/// becomes the customer's outstanding balance. One Sell on Credit switch
/// and one payment method apply to every booking delivered in this
/// batch; each booking still gets its own "amount received now" field
/// (pre-filled with its full remaining amount, editable, and only
/// required to match exactly while credit is off). The rules are
/// enforced again by SalesService per booking, so this screen and the
/// saved sale can never disagree.
class WaitDeliveryCustomerScreen extends StatefulWidget {
  final String farmId;

  /// [WaitDeliveryCustomer.key] of the customer to show.
  final String customerKey;

  /// Only used for the header while loading, or once nothing is left.
  final String customerName;

  /// When set, ONLY these bookings (sale IDs) are shown and delivered —
  /// used by the dashboard's Complete → Select goats flow
  /// (CompleteGoatsSelectorScreen), which passes the bookings of the goats
  /// that were ticked. Everything else on this screen (pickup weights,
  /// advance, remaining balance, discount, transport, credit, excess
  /// handling and saving) works exactly as before. Null = every open
  /// booking of the customer, the original behaviour.
  final Set<String>? onlySaleIds;

  const WaitDeliveryCustomerScreen({
    super.key,
    required this.farmId,
    required this.customerKey,
    required this.customerName,
    this.onlySaleIds,
  });

  @override
  State<WaitDeliveryCustomerScreen> createState() =>
      _WaitDeliveryCustomerScreenState();
}

class _WaitDeliveryCustomerScreenState
    extends State<WaitDeliveryCustomerScreen> {
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Goat>> _goatsStream =
  GoatService.instance.goatsStream(widget.farmId);

  late final Stream<List<Sale>> _salesStream =
  WaitDeliveryService.instance.openSalesStream(widget.farmId);

  /// Booking (sale) IDs picked for delivery.
  final Set<String> _selected = <String>{};

  /// Booking IDs already seen, so each booking is pre-selected exactly
  /// once (a booking the person un-ticks must not be re-ticked by the
  /// next stream update).
  final Set<String> _seen = <String>{};

  /// Pickup weight per goat, keyed by goat ID.
  final Map<String, TextEditingController> _weights =
  <String, TextEditingController>{};

  /// Amount received now per booking, keyed by sale ID.
  final Map<String, TextEditingController> _amounts =
  <String, TextEditingController>{};

  /// Optional transportation charge per booking, keyed by sale ID.
  /// Collected from the customer on top of the goat value; passed on to
  /// the transport team, so it is not farm revenue.
  final Map<String, TextEditingController> _transports =
  <String, TextEditingController>{};

  /// Bookings whose amount field the person has typed in themselves.
  /// Until then it follows the remaining amount as the pickup weight
  /// changes, same as the single-goat screen.
  final Set<String> _amountEdited = <String>{};

  /// Sell on Credit for this batch. Whatever is left after the amount
  /// received goes onto each customer's outstanding balance instead of
  /// blocking the delivery.
  bool _onCredit = false;

  /// How the money received now is being paid, for every booking in
  /// this batch.
  String _method = FinancePaymentMethods.cash;

  /// Discount on the goat value per booking, keyed by sale ID. Starts at
  /// the discount given at booking and can be changed at pickup. Never
  /// taken off transportation.
  final Map<String, TextEditingController> _discounts =
  <String, TextEditingController>{};

  /// What to do with any advance that turns out to be MORE than a
  /// booking's final bill. One choice for the whole batch; only used when
  /// there is an extra.
  ExcessAction _excessAction = ExcessAction.carryToAdvance;

  /// What each booking looked like the last time it was drawn, so the
  /// fields that depend on it (total pickup weight, discount, amount
  /// received) can be reset when the booking is edited — here after Edit
  /// booking, or from another device.
  final Map<String, _BookingSignature> _signatures =
  <String, _BookingSignature>{};

  /// The customer's bookings in the order they are shown. Dues are
  /// covered in this order when the ticked bookings are netted against
  /// each other.
  List<WaitDeliverySale> _ordered = const <WaitDeliverySale>[];

  /// New photo per goat, saved (with the weights) when the sale is
  /// completed.
  final DeliveryGoatUpdates _goatUpdates = DeliveryGoatUpdates();

  // ONE CARD: the whole sale has ONE transport, ONE discount and ONE
  // "received now" field. They are split onto the bookings behind the
  // scenes (see [_applySharedFields]), because every booking is still
  // saved as its own sale (receipt, finance, lot profit).
  final TextEditingController _sharedTransport = TextEditingController();
  final TextEditingController _sharedDiscount = TextEditingController();
  final TextEditingController _sharedReceived = TextEditingController();

  /// False while the discount still shows the bookings' own discounts.
  bool _discountTouched = false;

  /// False while "received now" follows the total due by itself.
  bool _receivedTouched = false;

  /// One live stream per lot booking's goats ("Goat 1..N").
  final Map<String, Stream<List<SaleGoatDetail>>> _lotGoatStreams = {};

  /// Newest weight on record per goat (and `lot:<saleId>` totals), from
  /// the goats' profiles — what the pickup-weight fields start from.
  final Map<String, double> _latest = <String, double>{};

  /// Bookings whose latest weights were already asked for.
  final Set<String> _latestRequested = <String>{};

  /// Text each pickup-weight field started with: a field still showing it
  /// has not been typed in, so it may follow a newer weight.
  final Map<String, String> _weightInitial = <String, String>{};

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

    for (final controller in _discounts.values) {
      controller.dispose();
    }

    _goatUpdates.dispose();
    _sharedTransport.dispose();
    _sharedDiscount.dispose();
    _sharedReceived.dispose();

    super.dispose();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _trim(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  /// A money value as plain text for an input field: 14760, or 14760.50.
  String _plainMoney(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

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
  void _requestLatestWeights(WaitDeliverySale entry) {
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

  /// Pickup weight of "Goat [index]" of a lot booking. Starts from the
  /// goat's saved weight, or an even share of the booked weight.
  TextEditingController _lotGoatWeightControllerFor(
      WaitDeliverySale entry,
      int index,
      ) {
    final key = 'lot:${entry.id}:$index';
    return _weights.putIfAbsent(key, () {
      final share = entry.goatCount <= 0
          ? 0.0
          : (entry.bookedWeight / entry.goatCount * 100).round() / 100;
      final weight = _latest[key] ?? share;
      final controller = TextEditingController(
        text: weight <= 0 ? '' : _trim(weight),
      );
      _weightInitial[key] = controller.text;
      return controller;
    });
  }

  double _lotGoatWeightOf(WaitDeliverySale entry, int index) {
    return double.tryParse(
      _lotGoatWeightControllerFor(entry, index).text.trim(),
    ) ??
        0;
  }

  /// True when a selected goat of [entry] has no pickup weight yet.
  bool _missingWeight(WaitDeliverySale entry) {
    if (entry.isLotSale) {
      for (var i = 1; i <= entry.goatCount; i++) {
        if (_lotGoatWeightOf(entry, i) <= 0) return true;
      }
      return false;
    }
    return entry.goats.any((goat) => _weightOf(goat) <= 0);
  }

  double _weightOf(Goat goat) {
    return double.tryParse(_weightControllerFor(goat).text.trim()) ?? 0;
  }

  /// Total pickup weight of a booking, from its goats' fields. Rounded so
  /// adding decimals (34.5 + 12.3) never leaves float noise in the total.
  double _pickupWeightOf(WaitDeliverySale entry) {
    if (entry.isLotSale) {
      var total = 0.0;
      for (var i = 1; i <= entry.goatCount; i++) {
        total += _lotGoatWeightOf(entry, i);
      }
      return (total * 1000).round() / 1000;
    }

    final sum = entry.goats.fold<double>(
      0,
          (total, goat) => total + _weightOf(goat),
    );

    return (sum * 1000).round() / 1000;
  }

  TextEditingController _transportControllerFor(WaitDeliverySale entry) {
    return _transports.putIfAbsent(
      entry.id,
          () => TextEditingController(),
    );
  }

  /// The transportation charge typed for a booking (blank counts as 0).
  double _transportOf(WaitDeliverySale entry) {
    final text = _transportControllerFor(entry).text.trim();

    if (text.isEmpty) return 0;

    final number = double.tryParse(text) ?? 0;

    return number <= 0 ? 0 : Sale.roundMoney(number);
  }

  TextEditingController _discountControllerFor(WaitDeliverySale entry) {
    return _discounts.putIfAbsent(
      entry.id,
          () => TextEditingController(
        text: entry.bookingDiscount > 0
            ? _plainMoney(entry.bookingDiscount)
            : '',
      ),
    );
  }

  /// The discount typed for a booking (blank counts as 0).
  double _discountOf(WaitDeliverySale entry) {
    final text = _discountControllerFor(entry).text.trim();

    if (text.isEmpty) return 0;

    final number = double.tryParse(text) ?? 0;

    return number <= 0 ? 0 : Sale.roundMoney(number);
  }

  /// A discount can never be more than the goat amount.
  bool _discountValid(WaitDeliverySale entry) {
    final typed = _discountOf(entry);

    if (typed <= 0) return true;

    final goatValue = entry.saleValueAt(_pickupWeightOf(entry));

    // No weight yet -> nothing to compare against.
    if (goatValue <= 0) return true;

    return typed <= goatValue;
  }

  /// The pickup settlement for a booking, worked out by [SaleSettlement]
  /// so the screen shows exactly what SalesService saves.
  SaleSettlement _settlementOf(WaitDeliverySale entry) {
    return entry.settlementAt(
      _pickupWeightOf(entry),
      transport: _transportOf(entry),
      discount: _discountOf(entry),
      excessAction: _excessAction,
    );
  }

  /// Discount actually applied (never more than the goat value).
  double _appliedDiscountOf(WaitDeliverySale entry) {
    if (_pickupWeightOf(entry) <= 0) return 0;

    return _settlementOf(entry).appliedDiscount;
  }

  /// Final Amount Due for a booking: goat value (pickup weight x booking
  /// rate, or the fixed price) - discount + transportation - advance.
  /// Same figure the service saves.
  ///
  /// For a ticked booking this is the figure AFTER extra advance from the
  /// other ticked bookings has been applied (see [_allocation]).
  double _remainingOf(WaitDeliverySale entry) {
    final alloc = _allocation().bySale[entry.id];

    if (alloc != null) return alloc.toCollect;

    return entry.remainingAt(
      _pickupWeightOf(entry),
      transport: _transportOf(entry),
      discount: _discountOf(entry),
    );
  }

  /// The ticked bookings treated as ONE customer settlement: a booking
  /// whose advance is more than its bill pays part of another booking's
  /// due. The same function the service re-runs before saving, so what is
  /// shown here is what gets saved. A booking with no pickup weight yet
  /// is left out until one is entered.
  WaitDeliveryAllocation _allocation() {
    final bills = <WaitDeliveryBill>[];

    for (final entry in _ordered) {
      if (!_selected.contains(entry.id)) continue;

      final weight = _pickupWeightOf(entry);

      if (weight <= 0) continue;

      final settlement = entry.settlementAt(
        weight,
        transport: _transportOf(entry),
        discount: _discountOf(entry),
      );

      bills.add(
        WaitDeliveryBill(
          saleId: entry.id,
          payable: settlement.payable,
          advancePaid: entry.advancePaid,
        ),
      );
    }

    return WaitDeliveryAllocator.allocate(bills);
  }

  /// Extra advance of other ticked bookings that pays this booking's due.
  List<WaitDeliveryTransfer> _transfersInto(WaitDeliverySale entry) =>
      _allocation().transfersInto(entry.id);

  /// Extra advance of this booking that pays other bookings' dues.
  List<WaitDeliveryTransfer> _transfersFrom(WaitDeliverySale entry) =>
      _allocation().transfersFrom(entry.id);

  double _totalTransferred() {
    return Sale.roundMoney(
      _allocation().transfers.fold<double>(
        0,
            (sum, t) => sum + t.amount,
      ),
    );
  }

  /// What the advance covered beyond the booking's final bill (0 when it
  /// did not). Example: 85 kg x 620 = 52,700 against a 60,000 advance ->
  /// 7,300. Nothing until a pickup weight has been entered.
  ///
  /// For a ticked booking only the extra LEFT after the other bookings'
  /// dues were covered counts here — that is the part that still needs the
  /// Add to advance / Return to customer choice.
  double _excessOf(WaitDeliverySale entry) {
    if (_pickupWeightOf(entry) <= 0) return 0;

    final alloc = _allocation().bySale[entry.id];

    if (alloc != null) return alloc.leftoverExcess;

    return entry.excessAt(
      _pickupWeightOf(entry),
      transport: _transportOf(entry),
      discount: _discountOf(entry),
    );
  }

  double _totalExcess(List<WaitDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _excessOf(entry)),
    );
  }

  TextEditingController _amountControllerFor(WaitDeliverySale entry) {
    return _amounts.putIfAbsent(
      entry.id,
          () => TextEditingController(),
    );
  }

  double _typedAmount(WaitDeliverySale entry) {
    final text = _amountControllerFor(entry).text.trim();

    if (text.isEmpty) return 0;

    return Sale.roundMoney(double.tryParse(text) ?? 0);
  }

  /// What is being received now for this booking. Nothing is asked for
  /// when the advance already covers the whole amount.
  double _receivedNowOf(WaitDeliverySale entry) {
    final due = _remainingOf(entry);

    return due > 0 ? _typedAmount(entry) : 0;
  }

  double _leftAfterReceiptOf(WaitDeliverySale entry) {
    final left = Sale.roundMoney(
      _remainingOf(entry) - _receivedNowOf(entry),
    );

    return left <= 0 ? 0 : left;
  }

  /// Amounts received now come from the one "Received now" field (see
  /// [_applySharedFields]); nothing to do per booking.
  void _syncAutoAmount(WaitDeliverySale entry) {}

  // ---------------------------------------------------------------------------
  // ONE CARD — shared Transport / Discount / Received now
  // ---------------------------------------------------------------------------

  double _numberIn(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim()) ?? 0;
    return value <= 0 ? 0 : Sale.roundMoney(value);
  }

  /// Splits [total] in proportion to [weights], to the paisa. The rounding
  /// remainder goes on the last share, so the shares always add up to
  /// [total]. Equal shares when every weight is 0.
  static List<double> _split(double total, List<double> weights) {
    if (weights.isEmpty) return const <double>[];
    final sum = weights.fold<double>(0, (a, b) => a + b);
    final out = <double>[];
    var given = 0.0;
    for (var i = 0; i < weights.length; i++) {
      if (i == weights.length - 1) {
        out.add(Sale.roundMoney(total - given));
        break;
      }
      final share = sum <= 0
          ? Sale.roundMoney(total / weights.length)
          : Sale.roundMoney(total * weights[i] / sum);
      out.add(share);
      given = Sale.roundMoney(given + share);
    }
    return out;
  }

  /// Puts the shared fields onto the selected bookings:
  ///
  ///  * Transport — split by number of goats.
  ///  * Discount  — each booking's own booking discount until the field is
  ///    changed; after that the typed total is split by goat value.
  ///  * Received now — follows the total due while Sell on Credit is off
  ///    (until typed in); it pays the OLDEST booking first, then the next.
  ///
  /// Every booking then works exactly as before (settlement, extra
  /// advance moved between bookings, credit), so what is saved is what is
  /// shown.
  void _applySharedFields(WaitDeliveryCustomer customer) {
    final picked = _picked(customer);
    if (picked.isEmpty) return;

    String plain(double v) => v > 0 ? _plainMoney(v) : '';

    if (!_discountTouched) {
      final own = Sale.roundMoney(
        picked.fold<double>(0, (t, e) => t + e.bookingDiscount),
      );
      if (_sharedDiscount.text != plain(own)) {
        _sharedDiscount.text = plain(own);
      }
    }

    final transports = _split(
      _numberIn(_sharedTransport),
      [for (final e in picked) e.goatCount.toDouble()],
    );
    final discounts = _discountTouched
        ? _split(
      _numberIn(_sharedDiscount),
      [for (final e in picked) e.saleValueAt(_pickupWeightOf(e))],
    )
        : [for (final e in picked) e.bookingDiscount];

    for (var i = 0; i < picked.length; i++) {
      final transport = _transportControllerFor(picked[i]);
      if (transport.text != plain(transports[i])) {
        transport.text = plain(transports[i]);
      }
      final discount = _discountControllerFor(picked[i]);
      if (discount.text != plain(discounts[i])) {
        discount.text = plain(discounts[i]);
      }
    }

    final totalDue = _totalRemaining(picked);

    if (!_onCredit && !_receivedTouched &&
        _sharedReceived.text != plain(totalDue)) {
      _sharedReceived.text = plain(totalDue);
    }

    // Oldest booking first.
    final oldestFirst = [...picked]
      ..sort((a, b) => a.bookedAt.compareTo(b.bookedAt));
    var left = _numberIn(_sharedReceived);

    for (final entry in oldestFirst) {
      final due = _remainingOf(entry);
      final take = Sale.roundMoney(due <= 0 ? 0 : (left < due ? left : due));
      left = Sale.roundMoney(left - take);
      final controller = _amountControllerFor(entry);
      if (controller.text != plain(take)) controller.text = plain(take);
      _amountEdited.add(entry.id);
    }
  }

  /// The one "Received now" figure is valid: never more than the total
  /// due, and the full total while Sell on Credit is off.
  bool _receivedValid(List<WaitDeliverySale> picked) {
    final due = _totalRemaining(picked);
    if (due <= 0) return true;
    final received = _numberIn(_sharedReceived);
    if (received > due + 0.004) return false;
    if (!_onCredit && received < due - 0.004) return false;
    return true;
  }

  /// The one discount is never more than the goat value of the sale.
  bool _sharedDiscountValid(List<WaitDeliverySale> picked) {
    if (!_discountTouched) return true;
    final value = picked.fold<double>(
      0,
          (t, e) => t + e.saleValueAt(_pickupWeightOf(e)),
    );
    return value <= 0 || _numberIn(_sharedDiscount) <= value + 0.004;
  }

  /// Every selected goat with the weight typed here, to save on Complete.
  List<DeliveryGoatWeight> _goatWeights(List<WaitDeliverySale> picked) {
    return [
      for (final e in picked)
        if (e.isLotSale)
          for (var i = 1; i <= e.goatCount; i++)
            DeliveryGoatWeight.lot(
              saleId: e.id,
              index: i,
              lotDisplayId: e.sale.lotDisplayId,
              weight: _lotGoatWeightOf(e, i),
              lastWeight: _latest['lot:${e.id}:$i'] ?? 0,
            )
        else
          for (final g in e.goats)
            DeliveryGoatWeight.registered(
              goatId: g.id,
              saleId: e.id,
              weight: _weightOf(g),
              lastWeight: _lastWeightOf(g),
            ),
    ];
  }

  /// Ticks new bookings, drops bookings that are no longer waiting, and
  /// keeps every selected booking's amount field following its remaining
  /// amount while Sell on Credit is off.
  void _syncSelection(WaitDeliveryCustomer customer) {
    _ordered = customer.sales;

    final ids = customer.sales.map((entry) => entry.id).toSet();

    for (final id in ids) {
      if (_seen.add(id)) {
        _selected.add(id);
      }
    }

    _selected.removeWhere((id) => !ids.contains(id));

    for (final entry in customer.sales) {
      _syncBookingFields(entry);
      _requestLatestWeights(entry);

      if (_selected.contains(entry.id)) {
        _syncAutoAmount(entry);
      }
    }

    _applySharedFields(customer);
  }

  /// Resets the fields that were filled in from a booking's figures when
  /// those figures change (the booking was edited). Nothing happens the
  /// first time a booking is seen, so typed values are never wiped by a
  /// normal rebuild.
  void _syncBookingFields(WaitDeliverySale entry) {
    final now = (
    goats: entry.goatCount,
    weight: entry.bookedWeight,
    discount: entry.bookingDiscount,
    advance: entry.advancePaid,
    fixed: entry.sale.fixedSalePrice ?? 0.0,
    );

    final before = _signatures[entry.id];

    _signatures[entry.id] = now;

    if (before == null || before == now) return;

    // A lot booking has ONE total pickup weight for all its goats; with a
    // different number of goats the old total no longer makes sense.
    if (entry.isLotSale &&
        (before.goats != now.goats || before.weight != now.weight)) {
      // Goats were split off: start again from an even share of the new
      // booked weight and ask again for the remaining goats' weights.
      final share = entry.goatCount <= 0
          ? 0.0
          : (entry.bookedWeight / entry.goatCount * 100).round() / 100;
      for (var i = 1; i <= entry.goatCount; i++) {
        final key = 'lot:${entry.id}:$i';
        _latest.remove(key);
        final controller = _weights[key];
        if (controller != null) {
          controller.text = share <= 0 ? '' : _trim(share);
          _weightInitial[key] = controller.text;
        }
      }
      _latestRequested.remove(entry.id);
    }

    if (before.discount != now.discount) {
      final controller = _discounts[entry.id];

      if (controller != null) {
        controller.text = entry.bookingDiscount > 0
            ? _plainMoney(entry.bookingDiscount)
            : '';
      }
    }

    // Let the amount received follow the new remaining amount again.
    _amountEdited.remove(entry.id);
  }

  List<WaitDeliverySale> _picked(WaitDeliveryCustomer customer) {
    return customer.sales
        .where((entry) => _selected.contains(entry.id))
        .toList();
  }

  double _totalRemaining(List<WaitDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _remainingOf(entry)),
    );
  }

  double _totalReceivedNow(List<WaitDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(0, (sum, entry) => sum + _receivedNowOf(entry)),
    );
  }

  double _totalLeftAfterReceipt(List<WaitDeliverySale> picked) {
    return Sale.roundMoney(
      picked.fold<double>(
        0,
            (sum, entry) => sum + _leftAfterReceiptOf(entry),
      ),
    );
  }

  int _goatCountOf(List<WaitDeliverySale> picked) {
    return picked.fold<int>(0, (sum, entry) => sum + entry.goatCount);
  }

  String _goats(int count) => count == 1 ? '1 goat' : '$count goats';

  /// True while every selected booking's typed amount is a valid entry
  /// (within range, and equal to the full remaining amount when credit
  /// is off). Mirrors the single-goat screen's per-field validator.
  bool _amountValid(WaitDeliverySale entry) {
    final due = _remainingOf(entry);

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
  // DELIVER
  // ===========================================================================

  Future<void> _deliver(WaitDeliveryCustomer customer) async {
    if (_delivering) return;

    final picked = _picked(customer);

    if (picked.isEmpty) return;

    final missingWeight = picked.any(_missingWeight);

    final invalidAmount = !_receivedValid(picked) ||
        picked.any((entry) => !_amountValid(entry));
    final invalidDiscount = !_sharedDiscountValid(picked) ||
        picked.any((entry) => !_discountValid(entry));

    if (missingWeight || invalidDiscount || invalidAmount) {
      setState(() {
        _submitted = true;
      });

      _snack(
        missingWeight
            ? 'Enter a pickup weight for every selected goat.'
            : invalidDiscount
            ? 'A discount is more than the goat amount.'
            : 'Check the amount received for every selected booking.',
        error: true,
      );

      return;
    }

    final confirmed = await _confirmSheet(customer, picked);

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final payments = <String, WaitDeliveryPayment>{};
    final excessAction = _excessAction;
    final excessById = <String, double>{
      for (final entry in picked) entry.id: _excessOf(entry),
    };
    final transferred = _totalTransferred();

    for (final entry in picked) {
      final weight = _pickupWeightOf(entry);
      final due = _remainingOf(entry);

      payments[entry.id] = WaitDeliveryPayment(
        pickupWeight: weight,
        transportCharges: _transportOf(entry),
        expectedRemaining: due,
        amountReceivedNow: due > 0 ? _receivedNowOf(entry) : 0,
        onCredit: due > 0 && _onCredit,
        discount: _discountOf(entry),
        excessAction: excessAction,
      );
    }

    setState(() {
      _delivering = true;
    });

    // The new photos and weights are saved onto the goats first. If that
    // fails, nothing is completed and the person can try again.
    final goatWeights = _goatWeights(picked);
    try {
      await _goatUpdates.save(widget.farmId, goatWeights);

      // Saved: a second try must not save the same weights again.
      for (final g in goatWeights) {
        if (g.weight <= 0) continue;
        _latest[g.isLot ? 'lot:${g.saleId}:${g.index}' : g.goatId] = g.weight;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _delivering = false;
      });
      _snack(
        'Could not save the goat photos / weights: '
            '${FirestoreService.instance.describeError(e)}',
        error: true,
      );
      return;
    }

    if (!mounted) return;

    final result = await WaitDeliveryService.instance.deliverSales(
      farmId: widget.farmId,
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
        base = '$base ${_money.format(transferred)} of extra advance was '
            'applied to another booking.';
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
      WaitDeliveryBatchResult result,
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
      List<WaitDeliverySale> picked,
      WaitDeliveryBatchResult result,
      ) async {
    final deliveredGoats = picked
        .where(
          (entry) => result.delivered.any((o) => o.saleId == entry.id),
    )
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
                  'Bookings that failed are still waiting for delivery — '
                      'you can try them again.',
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
      WaitDeliveryCustomer customer,
      List<WaitDeliverySale> picked,
      ) {
    final due = _totalRemaining(picked);
    final receivedNow = _totalReceivedNow(picked);
    final left = _totalLeftAfterReceipt(picked);
    final goatCount = _goatCountOf(picked);
    final excess = _totalExcess(picked);

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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

                  Text(
                    'Confirm delivery',
                    style: AppTheme.heading(size: 16),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    '${customer.name} · ${_goats(goatCount)} will be '
                        'marked as Sold.',
                    style: AppTheme.body(size: 11),
                  ),

                  const SizedBox(height: 14),

                  for (final entry in picked) ...[
                    _confirmRow(entry),
                    const SizedBox(height: 10),
                  ],

                  const Divider(height: 1, color: AppColors.divider),

                  const SizedBox(height: 10),

                  if (_allocation().hasTransfers) ...[
                    for (final transfer in _allocation().transfers) ...[
                      _confirmTotalRow(
                        '${transfer.fromSaleId} extra settles part of '
                            '${transfer.toSaleId}',
                        transfer.amount,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      'No new money changes hands for this part — it was '
                          'already received as the extra advance.',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  _confirmTotalRow('Goat value + advance total', due),
                  const SizedBox(height: 6),
                  _confirmTotalRow('Received now', receivedNow),

                  if (excess > 0) ...[
                    const SizedBox(height: 6),
                    _confirmTotalRow(
                      'Extra (advance over the bill)',
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
                          left > 0
                              ? 'Outstanding (On Credit)'
                              : 'Remaining',
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
                            onPressed: () {
                              Navigator.of(sheetContext).pop(false);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textDark,
                              side: const BorderSide(
                                color: AppColors.divider,
                              ),
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
                            onPressed: () {
                              Navigator.of(sheetContext).pop(true);
                            },
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

  Widget _confirmRow(WaitDeliverySale entry) {
    final pickup = _pickupWeightOf(entry);
    final transport = _transportOf(entry);
    final due = _remainingOf(entry);
    final receivedNow = due > 0 ? _receivedNowOf(entry) : 0.0;
    final discount = _appliedDiscountOf(entry);
    final excess = _excessOf(entry);

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
                '${_trim(pickup)} kg × '
                    '${_money.format(entry.ratePerKg)}/kg' +
                    (transport > 0
                        ? ' + ${_money.format(transport)} transport'
                        : '') +
                    (discount > 0
                        ? ' − ${_money.format(discount)} discount'
                        : '') +
                    ' − ${_money.format(entry.advancePaid)} advance',
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
              for (final t in _transfersInto(entry))
                Text(
                  'Covered by extra from ${t.fromSaleId}: '
                      '−${_money.format(t.amount)}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
              for (final t in _transfersFrom(entry))
                Text(
                  'Extra ${_money.format(t.amount)} → applied to '
                      '${t.toSaleId}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
              if (excess > 0)
                Text(
                  'Extra: ${_money.format(excess)}',
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
          style: AppTheme.heading(
            size: 13,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _confirmTotalRow(String label, double value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTheme.body(size: 11)),
        ),
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

              final customers = WaitDeliveryCustomer.group(
                sales: saleSnap.data!,
                goats: goatSnap.data!,
              );

              WaitDeliveryCustomer? customer;

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
                    : WaitDeliveryCustomer(
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
                    title: 'No goats waiting',
                    subtitle:
                    'Every goat for this customer has been delivered.',
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
                        ? 'Wait on Delivery'
                        : 'Checkout · selected goats',
                    if (subtitle != null) subtitle,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10.5,
                    color: AppColors.textGrey,
                  ),
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BODY
  // ===========================================================================

  Widget _body(WaitDeliveryCustomer customer) {
    final picked = _picked(customer);

    // A plain scroll view (not a lazy list) so every pickup-weight /
    // amount field stays mounted and keeps its value while scrolling.
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
      child: Column(
        children: [
          _summaryCard(customer),

          const SizedBox(height: 12),

          _saleCard(customer, picked),

          const SizedBox(height: 12),

          _batchPaymentCard(picked),
        ],
      ),
    );
  }

  // ===========================================================================
  // ONE CARD — every selected goat, every booking, one calculation
  // ===========================================================================

  Widget _saleCard(
      WaitDeliveryCustomer customer,
      List<WaitDeliverySale> picked,
      ) {
    final goats = _goatCountOf(picked);
    final anyDue = picked.any((entry) => _remainingOf(entry) > 0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.darkGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${customer.name} · ${_goats(goats)} · ${picked.length} '
                '${picked.length == 1 ? 'booking' : 'bookings'}',
            style: AppTheme.heading(size: 15),
          ),
          Text(
            'Wait on Delivery · one bill for every selected goat',
            style: AppTheme.body(size: 10.5),
          ),

          const SizedBox(height: 14),

          // 1. GOATS — photo, lot (supplier), booking, rate, weight, value.
          _sectionLabel('Goats · photo & pickup weight'),
          for (final entry in picked)
            if (entry.isLotSale)
              _lotGoatLines(entry)
            else
              for (final goat in entry.goats) _goatLine(entry, goat),

          const Divider(height: 22, color: AppColors.divider),

          // 2. BOOKINGS — lot, supplier, locked rate, advance, ⋮ menu.
          _sectionLabel('Bookings'),
          for (final entry in picked) _bookingLine(entry),

          const Divider(height: 22, color: AppColors.divider),

          // 3. CHARGES — one transport and one discount for the sale.
          _sectionLabel('Charges'),
          _sharedMoneyField(
            controller: _sharedTransport,
            label: 'Transportation (optional)',
            icon: Icons.local_shipping_outlined,
            helper: 'Added to the bill, shared by the goats — not farm '
                'revenue.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _sharedMoneyField(
            controller: _sharedDiscount,
            label: 'Discount',
            icon: Icons.local_offer_outlined,
            helper: _sharedDiscountValid(picked)
                ? 'Off the goat value only. Starts at the booking '
                'discounts; shared by goat value.'
                : null,
            error: _sharedDiscountValid(picked)
                ? null
                : 'More than the goat value of this sale.',
            onChanged: (_) => setState(() => _discountTouched = true),
          ),

          const Divider(height: 22, color: AppColors.divider),

          // 4. CALCULATION
          _sectionLabel('Calculation'),
          _calculation(picked),

          if (anyDue) ...[
            const SizedBox(height: 12),
            _receivedField(picked),
          ],
        ],
      ),
    );
  }

  Widget _goatLine(WaitDeliverySale entry, Goat goat) {
    final weight = _weightOf(goat);
    final last = _lastWeightOf(goat);
    final breed = goat.breed.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeliveryGoatPhoto(
            updates: _goatUpdates,
            photoKey: 'g:${goat.id}',
            currentPhoto: goat.photo,
            color: AppColors.stockTeal,
            enabled: !_delivering,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: _delivering ? null : () => _openProfile(goat),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    breed.isEmpty ? goat.id : '${goat.id} · $breed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(size: 13),
                  ),
                  LotIdText(
                    farmId: widget.farmId,
                    lotDocId: goat.purchaseId,
                    style: AppTheme.body(
                      size: 10.5,
                      color: AppColors.info,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Booking ${entry.id} · '
                        '${_money.format(entry.ratePerKg)}/kg',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5),
                  ),
                  Text(
                    last > 0 ? 'Last ${_trim(last)} kg' : 'No weight on record',
                    style: AppTheme.body(size: 10),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _weightAndValue(
            controller: _weightControllerFor(goat),
            weight: weight,
            value: weight > 0 ? entry.saleValueAt(weight) : null,
          ),
        ],
      ),
    );
  }

  /// "Goat 1..N" of a lot booking, each with its own photo and weight.
  Widget _lotGoatLines(WaitDeliverySale entry) {
    return StreamBuilder<List<SaleGoatDetail>>(
      stream: _lotGoatStreams.putIfAbsent(
        entry.id,
            () => SaleGoatDetailsService.instance
            .streamForSale(widget.farmId, entry.id),
      ),
      builder: (context, snap) {
        final goats = SaleGoatDetailsService.withPlaceholders(
          snap.data ?? const <SaleGoatDetail>[],
          entry.goatCount,
        ).where((g) => g.index <= entry.goatCount);

        return Column(
          children: [
            for (final g in goats) _lotGoatLine(entry, g),
          ],
        );
      },
    );
  }

  Widget _lotGoatLine(WaitDeliverySale entry, SaleGoatDetail goat) {
    final weight = _lotGoatWeightOf(entry, goat.index);
    final last = _latest['lot:${entry.id}:${goat.index}'] ?? goat.weight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeliveryGoatPhoto(
            updates: _goatUpdates,
            photoKey: 'l:${entry.id}:${goat.index}',
            currentPhoto: goat.hasPhoto ? goat.photo : null,
            color: AppColors.stockTeal,
            enabled: !_delivering,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: _delivering
                  ? null
                  : () => Navigator.of(context).push(
                fastRoute(
                  LotGoatProfileScreen(
                    farmId: widget.farmId,
                    sale: entry.sale,
                    index: goat.index,
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goat.label, style: AppTheme.heading(size: 13)),
                  LotIdText(
                    farmId: widget.farmId,
                    lotDocId: entry.sale.lotDocId,
                    style: AppTheme.body(
                      size: 10.5,
                      color: AppColors.info,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Booking ${entry.id} · '
                        '${_money.format(entry.ratePerKg)}/kg',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10.5),
                  ),
                  Text(
                    last > 0 ? 'Last ${_trim(last)} kg' : 'No weight on record',
                    style: AppTheme.body(size: 10),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _weightAndValue(
            controller: _lotGoatWeightControllerFor(entry, goat.index),
            weight: weight,
            value: weight > 0 ? entry.saleValueAt(weight) : null,
          ),
        ],
      ),
    );
  }

  /// Pickup-weight field with the goat's value under it.
  Widget _weightAndValue({
    required TextEditingController controller,
    required double weight,
    required double? value,
  }) {
    final invalid = _submitted && weight <= 0;

    OutlineInputBorder border(Color color, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: w),
        );

    return SizedBox(
      width: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: controller,
            enabled: !_delivering,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            textAlign: TextAlign.right,
            onChanged: (_) => setState(() {}),
            style: AppTheme.body(
              size: 12.5,
              color: AppColors.textDark,
              weight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Weight',
              labelStyle: AppTheme.body(size: 10.5),
              suffixText: 'kg',
              suffixStyle: AppTheme.body(size: 11),
              errorText: invalid ? 'Required' : null,
              errorStyle: const TextStyle(fontSize: 9.5),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: border(_fieldBorderColor),
              enabledBorder: border(_fieldBorderColor),
              disabledBorder: border(AppColors.divider),
              focusedBorder: border(AppColors.darkGreen, 1.4),
              errorBorder: border(AppColors.error),
              focusedErrorBorder: border(AppColors.error, 1.4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value == null ? '—' : _money.format(value),
            style: AppTheme.heading(size: 12.5, color: AppColors.darkGreen),
          ),
        ],
      ),
    );
  }

  /// One booking of the sale: its lots (with supplier), locked rate,
  /// advance, and the Edit / Cancel deal / Delete menu.
  Widget _bookingLine(WaitDeliverySale entry) {
    final atSupplier = entry.isLotSale &&
        entry.sale.sourceLocation == Sale.sourceSupplier;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Booking ${entry.id}',
                        style: AppTheme.heading(size: 13),
                      ),
                    ),
                    if (entry.isFixedPrice) ...[
                      const SizedBox(width: 6),
                      _fixedPriceTag(),
                    ],
                  ],
                ),
                Text(
                  '${_goats(entry.goatCount)} · Booked '
                      '${_dateFormat.format(entry.bookedAt)}',
                  style: AppTheme.body(size: 10.5),
                ),
                const SizedBox(height: 6),
                LotOriginCard(
                  farmId: widget.farmId,
                  bookingId: entry.id,
                  lotDocIds: LotOriginCard.lotsOf(entry.sale, entry.goats),
                  goatsByLot:
                  LotOriginCard.goatsByLotOf(entry.sale, entry.goats),
                  showBookingHeader: false,
                  note: entry.isLotSale
                      ? (atSupplier ? 'At supplier' : 'At farm')
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  entry.isFixedPrice
                      ? '${_money.format(entry.sale.agreedGoatAmount)} fixed '
                      'for ${_trim(entry.bookedWeight)} kg = '
                      '${_money.format(entry.ratePerKg)}/kg locked'
                      : '${_money.format(entry.ratePerKg)}/kg locked · '
                      'booked ${_trim(entry.bookedWeight)} kg',
                  style: AppTheme.body(
                    size: 10.5,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Advance ${_money.format(entry.advancePaid)}'
                      '${entry.bookingDiscount > 0 ? ' · booking discount '
                      '${_money.format(entry.bookingDiscount)}' : ''}',
                  style: AppTheme.body(size: 10.5),
                ),
              ],
            ),
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
    );
  }

  Widget _sharedMoneyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
    String? helper,
    String? error,
  }) {
    return TextField(
      controller: controller,
      enabled: !_delivering,
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
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: AppTheme.body(size: 11),
        prefixIcon: Icon(icon, size: 18),
        prefixText: '₹ ',
        helperText: helper,
        helperMaxLines: 2,
        helperStyle: AppTheme.body(size: 10),
        errorText: error,
        filled: true,
        fillColor: Colors.white,
        border: _fieldBorder(_fieldBorderColor),
        enabledBorder: _fieldBorder(_fieldBorderColor),
        disabledBorder: _fieldBorder(AppColors.divider),
        focusedBorder: _fieldBorder(AppColors.darkGreen, 1.5),
        errorBorder: _fieldBorder(AppColors.error),
        focusedErrorBorder: _fieldBorder(AppColors.error, 1.5),
      ),
    );
  }

  /// Visible outline for every input on this screen (the app theme draws
  /// fields without one).
  static const Color _fieldBorderColor = Color(0xFF9EB3A6);

  OutlineInputBorder _fieldBorder(Color color, [double width = 1.1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// The whole sale worked out: each booking's goats at its own locked
  /// rate, then the shared charges and every advance.
  Widget _calculation(List<WaitDeliverySale> picked) {
    double sum(double Function(WaitDeliverySale e) f) =>
        Sale.roundMoney(picked.fold<double>(0, (t, e) => t + f(e)));

    final booked = picked.fold<double>(0, (t, e) => t + e.bookedWeight);
    final pickup = picked.fold<double>(0, (t, e) => t + _pickupWeightOf(e));
    final goatValue = sum((e) => e.saleValueAt(_pickupWeightOf(e)));
    final discount = sum(_appliedDiscountOf);
    final transport = sum(_transportOf);
    final advance = sum((e) => e.advancePaid);
    final due = _totalRemaining(picked);
    final extra = _totalExcess(picked);
    final received = _totalReceivedNow(picked);
    final onCredit = _totalLeftAfterReceipt(picked);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          if (booked > 0) ...[
            _calcRow('Booked weight', '${_trim(booked)} kg'),
            const SizedBox(height: 6),
          ],
          _calcRow(
            'Pickup weight',
            '${_trim(pickup)} kg${_weightChange(booked, pickup)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          for (final e in picked) ...[
            _calcRow(
              '${e.id} · ${_trim(_pickupWeightOf(e))} kg × '
                  '${_money.format(e.ratePerKg)}',
              _money.format(e.saleValueAt(_pickupWeightOf(e))),
            ),
            const SizedBox(height: 6),
          ],
          _calcRow('Goat value', _money.format(goatValue), emphasized: true),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            _calcRow('Discount', '− ${_money.format(discount)}'),
          ],
          if (transport > 0) ...[
            const SizedBox(height: 6),
            _calcRow('Transportation', '+ ${_money.format(transport)}'),
          ],
          const SizedBox(height: 6),
          _calcRow(
            'Advance paid (${picked.length} '
                '${picked.length == 1 ? 'booking' : 'bookings'})',
            '− ${_money.format(advance)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          _calcRow('Total due', _money.format(due), emphasized: true),
          if (extra > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Extra (advance over the bill)',
              _money.format(extra),
              emphasized: true,
            ),
          ],
          if (due > 0 && (received > 0 || _onCredit)) ...[
            const SizedBox(height: 6),
            _calcRow('Received now', '− ${_money.format(received)}'),
            if (onCredit > 0) ...[
              const SizedBox(height: 6),
              _calcRow(
                'Goes on credit',
                _money.format(onCredit),
                emphasized: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _receivedField(List<WaitDeliverySale> picked) {
    final due = _totalRemaining(picked);
    final received = _numberIn(_sharedReceived);
    final invalid = _submitted && !_receivedValid(picked);

    return _sharedMoneyField(
      controller: _sharedReceived,
      label: 'Amount received now',
      icon: Icons.payments_outlined,
      helper: invalid
          ? null
          : _onCredit
          ? 'Pays the oldest booking first; the rest goes on credit.'
          : 'The full amount due (${_money.format(due)}). Turn on Sell '
          'on Credit to take less.',
      error: !invalid
          ? null
          : received > due
          ? 'More than the total due (${_money.format(due)}).'
          : 'Enter the full amount due, or turn on Sell on Credit.',
      onChanged: (_) => setState(() => _receivedTouched = true),
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  Widget _summaryCard(WaitDeliveryCustomer customer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _summaryStat(
                '${customer.goatCount}',
                'Goats waiting',
              ),
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
                _money.format(customer.advanceTotal),
                'Advance paid',
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
          child: Text(
            value,
            style: AppTheme.heading(size: 17),
          ),
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
  // CARD PIECES
  // ---------------------------------------------------------------------------

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

  /// " (+10 kg)" / " (−5 kg)" against the booked weight; empty when the
  /// same or nothing was booked.
  String _weightChange(double booked, double pickup) {
    if (booked <= 0 || pickup <= 0) return '';
    final diff = (pickup - booked) * 1000;
    if (diff.round() == 0) return '';
    final kg = (diff.abs().round()) / 1000;
    return ' (${diff > 0 ? '+' : '−'}${_trim(kg)} kg)';
  }

  Widget _fixedPriceTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tradingBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Fixed price',
        style: TextStyle(
          color: AppColors.tradingBlue,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// A waiting goat is still on the farm, so it has the same profile as an
  /// Own Palai goat — weight, photos and health records — plus a Complete
  /// Delivery button.
  void _openProfile(Goat goat) {
    Navigator.of(context).push(
      fastRoute(
        OwnPalaiGoatProfileScreen(
          farmId: widget.farmId,
          goat: goat,
        ),
      ),
    );
  }

  Widget _calcRow(
      String label,
      String value, {
        bool emphasized = false,
      }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: emphasized
                ? AppTheme.heading(size: 12.5)
                : AppTheme.body(size: 10.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: emphasized
              ? AppTheme.heading(size: 14, color: AppColors.darkGreen)
              : AppTheme.body(
            size: 11,
            color: AppColors.textDark,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BATCH PAYMENT — Sell on Credit + payment method, applies to every
  // selected booking.
  // ---------------------------------------------------------------------------

  Widget _batchPaymentCard(List<WaitDeliverySale> picked) {
    final anyDue = picked.any((entry) => _remainingOf(entry) > 0);
    final totalExcess = _totalExcess(picked);
    final buyer = picked.isEmpty ? '' : picked.first.sale.customerName;

    if (picked.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 16),
        child: Text(
          'Select at least one booking to deliver.',
          style: AppTheme.body(size: 11.5),
        ),
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
          customerName: buyer,
          paidLabel: 'advance',
          message: 'The advance is ${_money.format(totalExcess)} more '
              'than the final bill of the selected bookings, so there '
              'is nothing more to collect.',
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
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: AppColors.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The advance already covers every selected booking — '
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
          Text(
            'Payment (applies to selected bookings)',
            style: AppTheme.heading(size: 12.5),
          ),

          const SizedBox(height: 10),

          _creditSwitch(),

          if (_totalReceivedNow(picked) > 0) ...[
            const SizedBox(height: 12),
            _paymentMethodPicker(),
          ],

          if (totalExcess > 0) ...[
            const SizedBox(height: 14),
            ExcessActionPicker(
              excess: totalExcess,
              value: _excessAction,
              customerName: buyer,
              paidLabel: 'advance',
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

  Widget _creditSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _onCredit
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
                  _onCredit
                      ? 'Whatever is not received now is added to the '
                      'customer\'s outstanding balance.'
                      : 'Off — the full amount due is received now.',
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
            onChanged: _delivering
                ? null
                : (value) {
              setState(() {
                _onCredit = value;

                if (value) {
                  // Nothing is assumed paid until the person says so.
                  if (!_receivedTouched) _sharedReceived.text = '';
                } else {
                  // Off -> the full amount due is received now.
                  _receivedTouched = false;
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
          children: WaitDeliveryService.instance.paymentMethods.map((
              method,
              ) {
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
              side: BorderSide(
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
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

  Widget _bottomBar(WaitDeliveryCustomer customer) {
    final picked = _picked(customer);
    final goatCount = _goatCountOf(picked);
    final left = _totalLeftAfterReceipt(picked);
    final excess = _totalExcess(picked);
    final received = _totalReceivedNow(picked);
    final all = picked.length == customer.sales.length;
    final canDeliver = picked.isNotEmpty && !_delivering;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: AppColors.divider),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
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
                            : '${_goats(goatCount)} · '
                            '${picked.length} '
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  _delivering
                      ? 'Completing…'
                      : all
                      ? 'Complete Sale'
                      : 'Complete Selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 13.5,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                  AppColors.darkGreen.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}