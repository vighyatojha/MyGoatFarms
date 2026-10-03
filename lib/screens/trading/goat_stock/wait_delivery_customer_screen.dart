import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/goat_icons.dart';
import 'package:mygoatfarms/models/expense_categories.dart';
import 'package:mygoatfarms/models/goat_model.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/models/sale_settlement.dart';
import 'package:mygoatfarms/models/wait_delivery_group.dart';
import 'package:mygoatfarms/services/goat_service.dart';
import 'package:mygoatfarms/widgets/excess_action_picker.dart';
import 'package:mygoatfarms/widgets/fast_route.dart';
import 'package:mygoatfarms/widgets/sale_actions.dart';
import 'package:mygoatfarms/screens/palai/fullscreen_image_viewer.dart';
import 'package:mygoatfarms/services/wait_delivery_service.dart';
import 'package:mygoatfarms/widgets/edit_wait_booking_sheet.dart';
import 'package:mygoatfarms/screens/trading/own_palai/own_palai_goat_profile_screen.dart';

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
/// Flow: Goat Stock -> Wait on Delivery tab (customers) -> this screen
/// (that customer's goats, grouped by booking) -> Deliver All at Once.
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

  const WaitDeliveryCustomerScreen({
    super.key,
    required this.farmId,
    required this.customerKey,
    required this.customerName,
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
    return _weights.putIfAbsent(
      goat.id,
          () => TextEditingController(
        text: goat.weight <= 0 ? '' : _trim(goat.weight),
      ),
    );
  }

  /// Pickup-weight field for a booking made from a lot. Goats in a lot are
  /// not weighed one by one, so the whole booking has ONE total weight,
  /// starting from the weight recorded when it was booked. Kept in
  /// [_weights] (under a `lot:` key) so it is disposed with the rest.
  TextEditingController _lotWeightControllerFor(WaitDeliverySale entry) {
    return _weights.putIfAbsent(
      'lot:${entry.id}',
          () => TextEditingController(
        text: entry.bookedWeight <= 0 ? '' : _trim(entry.bookedWeight),
      ),
    );
  }

  double _weightOf(Goat goat) {
    return double.tryParse(_weightControllerFor(goat).text.trim()) ?? 0;
  }

  /// Total pickup weight of a booking, from its goats' fields. Rounded so
  /// adding decimals (34.5 + 12.3) never leaves float noise in the total.
  double _pickupWeightOf(WaitDeliverySale entry) {
    if (entry.isLotSale) {
      final typed = double.tryParse(
        _lotWeightControllerFor(entry).text.trim(),
      ) ??
          0;

      return (typed * 1000).round() / 1000;
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

  /// While Sell on Credit is off, a booking's amount field simply follows
  /// its full remaining amount as pickup weight changes, until the
  /// person types their own figure.
  void _syncAutoAmount(WaitDeliverySale entry) {
    if (_onCredit || _amountEdited.contains(entry.id)) return;

    final due = _remainingOf(entry);
    final text = due > 0 ? _plainMoney(due) : '';
    final controller = _amountControllerFor(entry);

    if (controller.text != text) {
      controller.text = text;
    }
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

      if (_selected.contains(entry.id)) {
        _syncAutoAmount(entry);
      }
    }
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
      final controller = _weights['lot:${entry.id}'];

      if (controller != null) {
        controller.text = entry.bookedWeight <= 0 ? '' : _trim(entry.bookedWeight);
      }
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

  /// Edit booking: pick how many (or which) goats go out now and what
  /// happens to the rest. The booking is trimmed to the goats being
  /// delivered; the person then delivers it as usual.
  Future<void> _openEditBooking(WaitDeliverySale entry) async {
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

    _snack(
      result.keptSaleId != null
          ? 'Booking ${result.deliverSaleId} now has $deliver to deliver. '
          '$left kept on booking ${result.keptSaleId}.'
          : 'Booking ${result.deliverSaleId} now has $deliver to deliver. '
          '$left went back to stock.',
    );
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

    final missingWeight = picked.any(
          (entry) => entry.isLotSale
          ? _pickupWeightOf(entry) <= 0
          : entry.goats.any((goat) => _weightOf(goat) <= 0),
    );

    final invalidAmount = picked.any((entry) => !_amountValid(entry));
    final invalidDiscount = picked.any((entry) => !_discountValid(entry));

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
                (entry.isFixedPrice
                    ? 'Fixed price'
                    : '${_trim(pickup)} kg × '
                    '${_money.format(entry.ratePerKg)}') +
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
                  subtitle == null
                      ? 'Wait on Delivery'
                      : 'Wait on Delivery · $subtitle',
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
    // A plain scroll view (not a lazy list) so every pickup-weight /
    // amount field stays mounted and keeps its value while scrolling.
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
      child: Column(
        children: [
          _summaryCard(customer),

          const SizedBox(height: 12),

          _selectorBar(customer),

          const SizedBox(height: 9),

          for (var i = 0; i < customer.sales.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _bookingCard(customer.sales[i]),
          ],

          const SizedBox(height: 12),

          _batchPaymentCard(_picked(customer)),
        ],
      ),
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
  // SELECTOR
  // ---------------------------------------------------------------------------

  Widget _selectorBar(WaitDeliveryCustomer customer) {
    final total = customer.sales.length;
    final count = _picked(customer).length;

    final bool? value = count == total
        ? true
        : count == 0
        ? false
        : null;

    void toggleAll() {
      if (_delivering) return;

      setState(() {
        if (count == total) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(customer.sales.map((entry) => entry.id));

          for (final entry in customer.sales) {
            _syncAutoAmount(entry);
          }
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
              Text(
                '$count of $total selected',
                style: AppTheme.body(size: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOOKING CARD
  // ---------------------------------------------------------------------------

  Widget _bookingCard(WaitDeliverySale entry) {
    final selected = _selected.contains(entry.id);
    final pickup = _pickupWeightOf(entry);
    final due = _remainingOf(entry);
    final excess = _excessOf(entry);

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
          // Header: tick + booking + live amount due.
          InkWell(
            onTap: _delivering
                ? null
                : () {
              setState(() {
                if (selected) {
                  _selected.remove(entry.id);
                } else {
                  _selected.add(entry.id);
                  _syncAutoAmount(entry);
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
                        _syncAutoAmount(entry);
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
                            _fixedPriceTag(),
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
                      _money.format(due <= 0 && excess > 0 ? excess : due),
                      style: AppTheme.heading(
                        size: 14,
                        color: selected
                            ? AppColors.darkGreen
                            : AppColors.textGrey,
                      ),
                    ),
                    Text(
                      due <= 0 && excess > 0 ? 'Extra' : 'Due',
                      style: AppTheme.body(size: 9.5),
                    ),
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
                    entry.isFixedPrice
                        ? _infoChip(
                      Icons.sell_outlined,
                      '${_money.format(entry.saleValueAt(pickup))} '
                          'fixed price',
                    )
                        : _infoChip(
                      Icons.sell_outlined,
                      '${_money.format(entry.ratePerKg)}/kg booked rate',
                    ),
                    _infoChip(
                      Icons.payments_outlined,
                      '${_money.format(entry.advancePaid)} advance',
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
                  _lotRow(entry, selected)
                else
                  for (final goat in entry.goats) _goatRow(goat, selected),

                const SizedBox(height: 3),

                _transportField(entry, selected),

                const SizedBox(height: 10),

                _discountField(entry, selected),

                const SizedBox(height: 12),

                _calcBox(entry, pickup, due),

                if (selected && due > 0) ...[
                  const SizedBox(height: 10),
                  _bookingAmountField(entry, due),
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
  Widget _editBookingButton(WaitDeliverySale entry) {
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

  /// A booking made straight from a lot: the lot and quantity, plus ONE
  /// total pickup-weight field for all of its goats.
  Widget _lotRow(WaitDeliverySale entry, bool selected) {
    final controller = _lotWeightControllerFor(entry);

    final invalid = _submitted &&
        selected &&
        (double.tryParse(controller.text.trim()) ?? 0) <= 0;

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

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
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 118,
            child: TextField(
              controller: controller,
              enabled: selected && !_delivering,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'),
                ),
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
                labelText: 'Total pickup wt',
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
                disabledBorder:
                border(AppColors.divider.withValues(alpha: 0.6)),
                focusedBorder: border(AppColors.darkGreen, 1.4),
                errorBorder: border(AppColors.error),
                focusedErrorBorder: border(AppColors.error, 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatRow(Goat goat, bool selected) {
    final controller = _weightControllerFor(goat);

    final invalid = _submitted &&
        selected &&
        (double.tryParse(controller.text.trim()) ?? 0) <= 0;

    final breed = goat.breed.trim().isEmpty
        ? 'Breed not specified'
        : goat.breed.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _goatAvatar(goat),

          const SizedBox(width: 9),

          Expanded(
            child: InkWell(
              onTap: _delivering ? null : () => _openProfile(goat),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
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
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Weight & health',
                          style: AppTheme.body(
                            size: 10.5,
                            color: AppColors.stockTeal,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: AppColors.stockTeal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          SizedBox(
            width: 108,
            child: TextField(
              controller: controller,
              enabled: selected && !_delivering,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'),
                ),
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
                labelText: 'Pickup wt',
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.divider.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.darkGreen,
                    width: 1.4,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.error,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tap the photo to view it full-screen (pinch to zoom). With no photo
  /// the paw logo is shown and is not tappable.
  Widget _goatAvatar(Goat goat) {
    final box = _goatAvatarBox(goat);
    final photo = goat.photo;
    if (photo == null || photo.isEmpty) return box;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        fastRoute(FullscreenImageViewer(imageBytes: photo, title: goat.id)),
      ),
      child: box,
    );
  }

  Widget _goatAvatarBox(Goat goat) {
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
        child: Icon(
          GoatIcons.paw,
          size: 19,
          color: AppColors.stockTeal,
        ),
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
            style: AppTheme.body(
              size: 10,
              color: AppColors.textDark,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _calcBox(WaitDeliverySale entry, double pickup, double due) {
    final transport = _transportOf(entry);
    final discount = _appliedDiscountOf(entry);
    final excess = _excessOf(entry);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _calcRow('Pickup weight', '${_trim(pickup)} kg'),
          const SizedBox(height: 6),
          _calcRow(
            entry.isFixedPrice
                ? 'Goat value (fixed price)'
                : '${_trim(pickup)} kg × ${_money.format(entry.ratePerKg)}',
            _money.format(entry.saleValueAt(pickup)),
          ),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Discount',
              '− ${_money.format(discount)}',
            ),
          ],
          if (transport > 0) ...[
            const SizedBox(height: 6),
            _calcRow(
              'Transportation',
              '+ ${_money.format(transport)}',
            ),
          ],
          const SizedBox(height: 6),
          _calcRow(
            'Advance paid',
            '− ${_money.format(entry.advancePaid)}',
          ),
          for (final t in _transfersInto(entry)) ...[
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
          _calcRow(
            'Final Amount Due',
            _money.format(due),
            emphasized: true,
          ),
          for (final t in _transfersFrom(entry)) ...[
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
              'Extra (advance over the bill)',
              _money.format(excess),
              emphasized: true,
            ),
          ],
        ],
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

  /// Optional transportation charge for one booking, entered at pickup.
  /// It is added to the amount due and shown on the bill, but it is not
  /// farm revenue (it is passed on to the transport team).
  Widget _transportField(WaitDeliverySale entry, bool selected) {
    return TextField(
      controller: _transportControllerFor(entry),
      enabled: selected && !_delivering,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(r'^\d*\.?\d{0,2}'),
        ),
      ],
      onChanged: (_) => setState(() {}),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.darkGreen,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  /// Optional discount for one booking, entered at pickup. It starts at
  /// the discount given when the goats were booked. Taken off the goat
  /// value only — never off transportation.
  Widget _discountField(WaitDeliverySale entry, bool selected) {
    final invalid = !_discountValid(entry);

    return TextField(
      controller: _discountControllerFor(entry),
      enabled: selected && !_delivering,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(r'^\d*\.?\d{0,2}'),
        ),
      ],
      onChanged: (_) => setState(() {}),
      style: AppTheme.body(
        size: 12.5,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Discount (optional)',
        labelStyle: AppTheme.body(size: 10.5),
        helperText: 'Off the goat value only. Starts at the booking '
            'discount.',
        helperStyle: AppTheme.body(size: 9.5),
        errorText: invalid ? 'More than the goat amount' : null,
        errorStyle: const TextStyle(fontSize: 9.5),
        prefixText: '₹ ',
        prefixStyle: AppTheme.body(size: 12),
        prefixIcon: const Icon(
          Icons.local_offer_outlined,
          size: 18,
          color: AppColors.textGrey,
        ),
        filled: true,
        fillColor: selected ? Colors.white : AppColors.paleGreen,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.darkGreen,
            width: 1.4,
          ),
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
    );
  }

  /// Per-booking "amount received now" field, shown once a booking with
  /// something due is selected.
  Widget _bookingAmountField(WaitDeliverySale entry, double due) {
    final controller = _amountControllerFor(entry);
    final invalid = _submitted && !_amountValid(entry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !_delivering,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _amountEdited.add(entry.id);
                  });
                },
                style: AppTheme.body(
                  size: 12.5,
                  color: AppColors.textDark,
                  weight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Amount Received Now',
                  labelStyle: AppTheme.body(size: 10.5),
                  prefixText: '₹ ',
                  prefixStyle: AppTheme.body(size: 12),
                  errorText: invalid
                      ? (_onCredit
                      ? 'More than the amount due'
                      : 'Must equal the full ${_money.format(due)}')
                      : null,
                  errorStyle: const TextStyle(fontSize: 9.5),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppColors.darkGreen,
                      width: 1.4,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.error),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 1.4,
                    ),
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
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  'Full',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
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
                      ? 'Whatever is not received now is added to each '
                      'customer\'s outstanding balance.'
                      : 'Off — the full amount due is received now on '
                      'every selected booking.',
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
                  for (final controller in _amounts.entries) {
                    if (!_amountEdited.contains(controller.key)) {
                      controller.value.text = '';
                    }
                  }
                } else {
                  // Off -> the full amount is expected on every booking.
                  _amountEdited.clear();
                  _amounts.forEach((id, controller) {
                    controller.text = '';
                  });
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
                    : const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(
                  _delivering
                      ? 'Delivering…'
                      : all
                      ? 'Deliver All at Once'
                      : 'Deliver Selected',
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