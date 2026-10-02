import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:mygoatfarms/models/activity_model.dart';
import 'package:mygoatfarms/models/goat_model.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/models/trading_purchase_model.dart';
import 'package:mygoatfarms/services/firestore_service.dart';

/// What happens to the goats that are NOT being delivered now.
enum LeftoverGoatsAction {
  /// They stay waiting for delivery as a new booking (same customer, same
  /// rate / agreed price, a share of the advance).
  keepBooked,

  /// They are taken off the booking and go back to stock.
  returnToStock,
}

/// The money on both sides of a split, worked out in one place so the
/// Edit Booking sheet previews exactly what [WaitBookingSplitService]
/// saves.
class WaitBookingSplitFigures {
  /// Fraction of the booking that is being delivered now (0 - 1].
  final double share;

  // Goats delivered now (the booking keeps its ID).
  final double deliverGross;
  final double deliverDiscount;
  final double deliverTotal;
  final double deliverAdvance;
  final double deliverBookingWeight;
  final double deliverSellingWeight;
  final double? deliverFixedPrice;

  // Goats left over (a new booking when kept; ignored when returned).
  final double leftGross;
  final double leftDiscount;
  final double leftTotal;
  final double leftAdvance;
  final double leftBookingWeight;
  final double leftSellingWeight;
  final double? leftFixedPrice;

  const WaitBookingSplitFigures({
    required this.share,
    required this.deliverGross,
    required this.deliverDiscount,
    required this.deliverTotal,
    required this.deliverAdvance,
    required this.deliverBookingWeight,
    required this.deliverSellingWeight,
    required this.deliverFixedPrice,
    required this.leftGross,
    required this.leftDiscount,
    required this.leftTotal,
    required this.leftAdvance,
    required this.leftBookingWeight,
    required this.leftSellingWeight,
    required this.leftFixedPrice,
  });
}

/// What a split did, so the screen can tell the person and keep the new
/// booking from being ticked for delivery by accident.
class WaitBookingSplitResult {
  /// The booking that now holds only the goats to deliver (original ID).
  final String deliverSaleId;

  /// The new booking holding the leftover goats; null unless they were
  /// kept on a booking.
  final String? keptSaleId;

  final int deliverCount;
  final int leftoverCount;
  final LeftoverGoatsAction action;

  const WaitBookingSplitResult({
    required this.deliverSaleId,
    required this.keptSaleId,
    required this.deliverCount,
    required this.leftoverCount,
    required this.action,
  });
}

/// Edit Booking for a Wait for Delivery booking: choose how many (or which)
/// goats are delivered now, and what happens to the rest.
///
/// A booking is the unit SalesService delivers: one rate, one advance, one
/// pickup weight and one goat list. So partial delivery is done by
/// reshaping the booking BEFORE it is delivered, not by teaching the
/// delivery code about partial sales:
///
///  * the original booking keeps its ID and is trimmed to the goats being
///    delivered now (so the normal Deliver flow, bill, revenue and profit
///    all work on it unchanged);
///  * the leftover goats either move to a NEW Wait for Delivery booking
///    ([LeftoverGoatsAction.keepBooked]) or go back to stock
///    ([LeftoverGoatsAction.returnToStock]).
///
/// Money is split by the share of goats being delivered (by weight when
/// every goat has a weight, otherwise by count). A Wait for Delivery
/// advance is not in Finance until delivery (see SalesService), so moving
/// part of it to another booking needs no Finance entry to be rewritten.
///
/// Everything happens in ONE Firestore transaction, so a booking can never
/// be half split.
class WaitBookingSplitService {
  WaitBookingSplitService._();

  static final WaitBookingSplitService instance = WaitBookingSplitService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // REFERENCES
  // -----------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _farm(String farmId) =>
      _db.collection('farms').doc(farmId);

  DocumentReference<Map<String, dynamic>> _saleRef(
      String farmId,
      String saleId,
      ) =>
      _farm(farmId).collection('sales').doc(saleId);

  DocumentReference<Map<String, dynamic>> _goatRef(
      String farmId,
      String goatId,
      ) =>
      _farm(farmId).collection('tradingGoats').doc(goatId);

  DocumentReference<Map<String, dynamic>> _lotRef(
      String farmId,
      String lotId,
      ) =>
      _farm(farmId).collection('tradingPurchases').doc(lotId);

  DocumentReference<Map<String, dynamic>> _summaryRef(String farmId) =>
      _farm(farmId).collection('tradingSummary').doc('dashboard');

  // Same counter SalesService numbers every sale from.
  DocumentReference<Map<String, dynamic>> _counterRef(String farmId) =>
      _farm(farmId).collection('tradingCounters').doc('saleCounter');

  DocumentReference<Map<String, dynamic>> _customerRef(
      String farmId,
      String customerId,
      ) =>
      _farm(farmId).collection('customers').doc(customerId);

  // -----------------------------------------------------------------------
  // MONEY — shared with the Edit Booking sheet
  // -----------------------------------------------------------------------

  static double _r2(num value) => Sale.roundMoney(value.toDouble());

  static double _r3(num value) => (value.toDouble() * 1000).round() / 1000;

  /// Fraction of the booking being delivered now.
  ///
  /// Individual goats are split by their recorded weights when every goat
  /// has one, otherwise by count. A lot booking has no per-goat weights,
  /// so it is always by count (pass no weights).
  static double shareOf({
    required int deliverCount,
    required int totalCount,
    List<double>? deliverWeights,
    List<double>? leftoverWeights,
  }) {
    if (totalCount <= 0) return 1;

    if (deliverWeights != null &&
        leftoverWeights != null &&
        deliverWeights.isNotEmpty &&
        leftoverWeights.isNotEmpty &&
        deliverWeights.every((w) => w > 0) &&
        leftoverWeights.every((w) => w > 0)) {
      final deliver = deliverWeights.fold<double>(0, (a, b) => a + b);
      final left = leftoverWeights.fold<double>(0, (a, b) => a + b);

      if (deliver + left > 0) return deliver / (deliver + left);
    }

    return deliverCount / totalCount;
  }

  /// The split of [sale]'s money.
  ///
  /// [deliverAdvance] and [deliverFixedPrice] are optional overrides for
  /// the delivered side (null = proportional to [share]). The advance
  /// override only applies when the leftover goats are kept on a booking;
  /// when they are returned to stock the whole advance stays with the goats
  /// being delivered.
  static WaitBookingSplitFigures figures({
    required Sale sale,
    required double share,
    required LeftoverGoatsAction action,
    double? deliverAdvance,
    double? deliverFixedPrice,
  }) {
    final s = math.min(math.max(share, 0.0), 1.0);
    final keep = action == LeftoverGoatsAction.keepBooked && s < 1;

    final discount = sale.appliedDiscount;
    final advance = sale.bookingAdvanceAmount ?? 0;

    // ---- goat value ---------------------------------------------------
    double dGross;
    double lGross;
    double? dFixed;
    double? lFixed;

    if (sale.isFixedPrice) {
      final total = _r2(sale.fixedSalePrice ?? (sale.totalSaleAmount + discount));
      final d = _r2(
        math.min(math.max(deliverFixedPrice ?? total * s, 0.0), total),
      );

      dFixed = d;
      lFixed = _r2(total - d);
      dGross = d;
      lGross = lFixed;
    } else {
      final total = _r2(sale.totalSaleAmount + discount);

      dGross = _r2(total * s);
      lGross = _r2(total - dGross);
    }

    // ---- discount (off the goat value, split by share) ----------------
    final dDisc = math.min(_r2(discount * s), dGross);
    final lDisc = math.min(math.max(_r2(discount - dDisc), 0.0), lGross);

    // ---- advance ------------------------------------------------------
    double dAdv;
    double lAdv;

    if (keep) {
      dAdv = _r2(
        math.min(math.max(deliverAdvance ?? advance * s, 0.0), advance),
      );
      lAdv = _r2(advance - dAdv);
    } else {
      dAdv = _r2(advance);
      lAdv = 0;
    }

    // ---- weights recorded at booking ----------------------------------
    final bookingWeight = sale.bookingWeight ?? 0;
    final dBookingW = _r3(bookingWeight * s);
    final lBookingW = _r3(bookingWeight - dBookingW);

    final dSellingW = _r3(sale.sellingWeight * s);
    final lSellingW = _r3(sale.sellingWeight - dSellingW);

    return WaitBookingSplitFigures(
      share: s,
      deliverGross: dGross,
      deliverDiscount: dDisc,
      deliverTotal: _r2(dGross - dDisc),
      deliverAdvance: dAdv,
      deliverBookingWeight: dBookingW,
      deliverSellingWeight: dSellingW,
      deliverFixedPrice: dFixed,
      leftGross: lGross,
      leftDiscount: lDisc,
      leftTotal: _r2(lGross - lDisc),
      leftAdvance: lAdv,
      leftBookingWeight: lBookingW,
      leftSellingWeight: lSellingW,
      leftFixedPrice: lFixed,
    );
  }

  // -----------------------------------------------------------------------
  // SPLIT
  // -----------------------------------------------------------------------

  /// Trims booking [saleId] to the goats being delivered now.
  ///
  /// Individual-goat booking: pass [deliverGoatIds] (the goats to deliver).
  /// Lot booking: pass [deliverQuantity] (how many of the held goats to
  /// deliver). At least one goat must be delivered and at least one must be
  /// left over; otherwise there is nothing to edit.
  ///
  /// Throws a [StateError] with a message fit to show to the person.
  Future<WaitBookingSplitResult> splitBooking({
    required String farmId,
    required String saleId,
    Set<String>? deliverGoatIds,
    int? deliverQuantity,
    required LeftoverGoatsAction leftover,
    double? deliverAdvance,
    double? deliverFixedPrice,
  }) async {
    final actor = await FirestoreService.instance.getCurrentActor();

    // Not `late final`: Firestore may re-run the closure on contention.
    String? keptSaleId;
    int deliverCount = 0;
    int leftoverCount = 0;
    String customerName = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------------------------------------------
      // 1. READS — every read before the first write.
      // ---------------------------------------------------------------

      final saleRef = _saleRef(farmId, saleId);
      final saleSnap = await transaction.get(saleRef);

      if (!saleSnap.exists) {
        throw StateError(
          'This booking could not be found. It may already have been '
              'delivered or cancelled.',
        );
      }

      final sale = Sale.fromDoc(saleSnap);

      if (!sale.isWaitForDelivery ||
          sale.status != Sale.statusWaitForDelivery) {
        throw StateError(
          'Only a booking that is still waiting for delivery can be '
              'edited.',
        );
      }

      if (sale.payments.isNotEmpty) {
        throw StateError(
          'This booking already has payments recorded, so its goats '
              'cannot be split. Deliver it as it is.',
        );
      }

      customerName = sale.customerName;

      // Goats that really are still held by this booking.
      final goatSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final members = <String, Goat>{};

      if (!sale.isLotSale) {
        for (final goatId in sale.goatIds) {
          final snap = await transaction.get(_goatRef(farmId, goatId));

          goatSnaps[goatId] = snap;

          if (!snap.exists) continue;

          final goat = Goat.fromDoc(snap);

          if (goat.currentStatus == Goat.statusWaitOnDelivery &&
              goat.saleId == saleId) {
            members[goatId] = goat;
          }
        }
      }

      final totalCount = sale.isLotSale ? sale.lotQuantity : members.length;

      // ---- which goats go out now --------------------------------------
      final deliverIds = <String>{};
      final leftoverIds = <String>[];

      if (sale.isLotSale) {
        final quantity = deliverQuantity ?? 0;

        if (quantity < 1) {
          throw StateError('Choose at least one goat to deliver now.');
        }

        if (quantity >= sale.lotQuantity) {
          throw StateError(
            'All ${sale.lotQuantity} goats are already being delivered — '
                'there is nothing to change.',
          );
        }

        deliverCount = quantity;
        leftoverCount = sale.lotQuantity - quantity;
      } else {
        final wanted = deliverGoatIds ?? const <String>{};

        for (final id in wanted) {
          if (!members.containsKey(id)) {
            throw StateError(
              'Goat $id is no longer waiting on this booking. Close this '
                  'screen and try again.',
            );
          }

          deliverIds.add(id);
        }

        if (deliverIds.isEmpty) {
          throw StateError('Choose at least one goat to deliver now.');
        }

        for (final id in members.keys) {
          if (!deliverIds.contains(id)) leftoverIds.add(id);
        }

        if (leftoverIds.isEmpty) {
          throw StateError(
            'All goats are already being delivered — there is nothing to '
                'change.',
          );
        }

        deliverCount = deliverIds.length;
        leftoverCount = leftoverIds.length;
      }

      final keep = leftover == LeftoverGoatsAction.keepBooked;

      // ---- lot (only needed to hand reserved goats back) ---------------
      DocumentReference<Map<String, dynamic>>? lotRef;

      if (sale.isLotSale && !keep) {
        lotRef = _lotRef(farmId, sale.lotDocId);

        final lotSnap = await transaction.get(lotRef);

        if (!lotSnap.exists) {
          throw StateError('Lot ${sale.lotDocId} no longer exists.');
        }

        final lot = TradingPurchase.fromDoc(lotSnap);

        if (lot.reservedFarmQty < sale.lotQuantity) {
          throw StateError(
            'Lot ${sale.lotDocId} has only ${lot.reservedFarmQty} goats '
                'reserved but this booking holds ${sale.lotQuantity}. '
                'Please check the lot first.',
          );
        }
      }

      // ---- new booking number + customer (only when kept) --------------
      int? nextNumber;
      DocumentSnapshot<Map<String, dynamic>>? customerSnap;

      if (keep) {
        final counterSnap = await transaction.get(_counterRef(farmId));

        nextNumber =
            ((counterSnap.data()?['lastValue'] as num?)?.toInt() ?? 0) + 1;

        if (sale.customerId.trim().isNotEmpty) {
          customerSnap = await transaction.get(
            _customerRef(farmId, sale.customerId.trim()),
          );
        }
      }

      // ---------------------------------------------------------------
      // 2. Money.
      // ---------------------------------------------------------------

      final share = sale.isLotSale
          ? shareOf(deliverCount: deliverCount, totalCount: totalCount)
          : shareOf(
        deliverCount: deliverCount,
        totalCount: totalCount,
        deliverWeights: [
          for (final id in deliverIds) members[id]!.weight,
        ],
        leftoverWeights: [
          for (final id in leftoverIds) members[id]!.weight,
        ],
      );

      final money = figures(
        sale: sale,
        share: share,
        action: leftover,
        deliverAdvance: deliverAdvance,
        deliverFixedPrice: deliverFixedPrice,
      );

      final rawSale = Map<String, dynamic>.from(saleSnap.data() ?? {});

      // ---------------------------------------------------------------
      // 3. WRITES — the booking being delivered keeps its ID.
      // ---------------------------------------------------------------

      final newSaleId = keep
          ? 'S-${nextNumber.toString().padLeft(4, '0')}'
          : null;

      Map<String, dynamic> moneyFields({
        required double total,
        required double discount,
        required double advance,
        required double bookingWeight,
        required double sellingWeight,
        required double? fixedPrice,
      }) {
        return {
          'totalSaleAmount': total,
          'discount': discount > 0 ? discount : FieldValue.delete(),
          'bookingAdvanceAmount': advance,
          'bookingWeight': bookingWeight,
          'sellingWeight': sellingWeight,
          if (fixedPrice != null) 'fixedSalePrice': fixedPrice,
          if (fixedPrice != null && sellingWeight > 0)
            'sellingPricePerKg': _r2(fixedPrice / sellingWeight),
        };
      }

      final parentGoatIds = sale.goatIds
          .where((id) => !leftoverIds.contains(id))
          .toList();

      transaction.update(saleRef, {
        ...moneyFields(
          total: money.deliverTotal,
          discount: money.deliverDiscount,
          advance: money.deliverAdvance,
          bookingWeight: money.deliverBookingWeight,
          sellingWeight: money.deliverSellingWeight,
          fixedPrice: money.deliverFixedPrice,
        ),
        if (sale.isLotSale)
          'lotQuantity': deliverCount
        else
          'goatIds': parentGoatIds,
        if (newSaleId != null) 'splitChildSaleId': newSaleId,
        if (!keep) 'splitReturnedCount': leftoverCount,
        'splitAt': FieldValue.serverTimestamp(),
      });

      if (keep) {
        // The new booking is a copy of the original (customer, rate,
        // booking date, payment method, lot cost snapshot ...) with only
        // the leftover goats and their share of the money.
        final child = Map<String, dynamic>.from(rawSale)
          ..remove('splitChildSaleId')
          ..remove('splitReturnedCount')
          ..remove('discount')
          ..addAll({
            ...moneyFields(
              total: money.leftTotal,
              discount: money.leftDiscount,
              advance: money.leftAdvance,
              bookingWeight: money.leftBookingWeight,
              sellingWeight: money.leftSellingWeight,
              fixedPrice: money.leftFixedPrice,
            ),
            if (sale.isLotSale)
              'lotQuantity': leftoverCount
            else
              'goatIds': leftoverIds,
            'splitFromSaleId': saleId,
            'splitAt': FieldValue.serverTimestamp(),
          });

        // `discount` was removed above and moneyFields put a delete marker
        // there when there is none — a delete marker is not valid in a
        // plain set, so drop it.
        if (child['discount'] is FieldValue) child.remove('discount');

        transaction.set(_saleRef(farmId, newSaleId!), child);

        transaction.set(
          _counterRef(farmId),
          {'lastValue': nextNumber},
          SetOptions(merge: true),
        );

        if (customerSnap != null && customerSnap.exists) {
          // One more sale for this customer, same as any new booking.
          transaction.update(customerSnap.reference, {
            'totalPurchases': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // ---- the leftover goats -----------------------------------------
      for (final id in leftoverIds) {
        if (keep) {
          // Still waiting for delivery — just under the new booking.
          transaction.update(goatSnaps[id]!.reference, {
            'saleId': newSaleId,
          });
        } else {
          transaction.update(goatSnaps[id]!.reference, {
            'currentStatus': Goat.statusAvailable,
            'saleId': FieldValue.delete(),
            'waitOnDeliveryAt': FieldValue.delete(),
          });
        }
      }

      if (!keep) {
        if (sale.isLotSale) {
          transaction.update(lotRef!, {
            'reservedFarmQty': FieldValue.increment(-leftoverCount),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Kept goats just change booking, so the Wait on Delivery count
        // only comes down when goats actually leave the booking list.
        transaction.set(
          _summaryRef(farmId),
          {'waitOnDelivery': FieldValue.increment(-leftoverCount)},
          SetOptions(merge: true),
        );
      }

      // ---- activity ----------------------------------------------------
      transaction.set(_farm(farmId).collection('activities').doc(), {
        'type': ActivityType.revenueVoided.name,
        'title': 'Booking Edited',
        'subtitle': 'Sale $saleId · ${sale.customerName} · '
            '$deliverCount to deliver · '
            '${keep ? '$leftoverCount kept as $newSaleId' : '$leftoverCount back in stock'}',
        'module': 'trading',
        'timestamp': FieldValue.serverTimestamp(),
        if (actor != null) 'actorUid': actor.uid,
        if (actor != null) 'actorName': actor.name,
        if (actor != null) 'actorRole': actor.role,
      });

      keptSaleId = newSaleId;
    }).timeout(_timeout * 2);

    unawaited(
      FirestoreService.instance.notifyPartnerActivity(
        farmId: farmId,
        type: ActivityType.revenueVoided,
        title: 'Booking Edited',
        subtitle: 'Sale $saleId · $customerName',
        module: 'trading',
        actor: actor,
      ),
    );

    return WaitBookingSplitResult(
      deliverSaleId: saleId,
      keptSaleId: keptSaleId,
      deliverCount: deliverCount,
      leftoverCount: leftoverCount,
      action: leftover,
    );
  }
}