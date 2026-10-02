import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:mygoatfarms/models/activity_model.dart';
import 'package:mygoatfarms/models/expense_categories.dart';
import 'package:mygoatfarms/models/goat_model.dart';
import 'package:mygoatfarms/models/sale_draft.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/models/trading_purchase_model.dart';
import 'package:mygoatfarms/services/firestore_service.dart';

/// What happens to the advance / booking money when a deal is cancelled.
enum AdvanceDecision {
  /// The money is handed back to the customer. The Sold Goat Revenue that
  /// was recorded for it is voided, so Finance no longer counts it.
  refund,

  /// The farm keeps the money (the customer walked away). It stays as
  /// Sold Goat Revenue in Finance.
  keep,
}

/// Cancel Deal, Delete Sale and Edit Sale for the Trading module.
///
/// Every operation runs in ONE Firestore transaction, so a sale can never
/// be half reversed (goat back in stock but the revenue still counted, or
/// the other way round).
///
/// A cancelled or deleted sale is removed from `farms/{id}/sales` and a
/// copy is kept in `farms/{id}/archivedSales/{saleId}` with who did it,
/// when and why. Removing it from `sales` means every list, report and
/// credit screen stops showing it without any of them needing a change.
///
/// Collections touched: sales, archivedSales, tradingGoats,
/// tradingPurchases (lot counters), tradingSummary/dashboard, transactions
/// (Finance, voided not deleted), customers, activities.
class SaleAdjustmentService {
  SaleAdjustmentService._();

  static final SaleAdjustmentService instance = SaleAdjustmentService._();

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

  DocumentReference<Map<String, dynamic>> _archiveRef(
      String farmId,
      String saleId,
      ) =>
      _farm(farmId).collection('archivedSales').doc(saleId);

  DocumentReference<Map<String, dynamic>> _goatRef(
      String farmId,
      String goatId,
      ) =>
      _farm(farmId).collection('tradingGoats').doc(goatId);

  DocumentReference<Map<String, dynamic>> _purchaseRef(
      String farmId,
      String purchaseId,
      ) =>
      _farm(farmId).collection('tradingPurchases').doc(purchaseId);

  DocumentReference<Map<String, dynamic>> _summaryRef(String farmId) =>
      _farm(farmId).collection('tradingSummary').doc('dashboard');

  DocumentReference<Map<String, dynamic>> _txRef(
      String farmId,
      String docId,
      ) =>
      _farm(farmId).collection('transactions').doc(docId);

  DocumentReference<Map<String, dynamic>> _customerRef(
      String farmId,
      String customerId,
      ) =>
      _farm(farmId).collection('customers').doc(customerId);

  /// Same ids SalesService writes Sold Goat Revenue under.
  String _revenueId(String saleId, String key) => 'sale_${saleId}_$key';

  // -----------------------------------------------------------------------
  // WHAT IS ALLOWED
  // -----------------------------------------------------------------------

  /// True for a Booking / Wait for Delivery that has not been delivered.
  bool isOpenDeal(Sale sale) {
    return (sale.isBooking &&
        sale.status == Sale.statusBooked) ||
        (sale.isWaitForDelivery &&
            sale.status == Sale.statusWaitForDelivery);
  }

  /// True for a sale whose goats have already been handed over.
  bool isDelivered(Sale sale) {
    return sale.status == Sale.statusSold ||
        sale.status == Sale.statusDeliveryCompleted ||
        sale.status == Sale.statusPickupCompleted;
  }

  /// Cancel Deal only exists for a deal that is still open.
  bool canCancel(Sale sale) => isOpenDeal(sale);

  /// Why [sale] cannot be deleted, or null when it can.
  String? deleteBlockReason(Sale sale) {
    if (isOpenDeal(sale)) return null;

    if (sale.isPalaiTransfer ||
        sale.status == Sale.statusTransferredToPalai) {
      return 'A sale transferred to Customer Palai cannot be deleted here '
          'because the goat now lives in the Palai module.';
    }

    if (!isDelivered(sale)) {
      return 'This sale cannot be deleted in its current state.';
    }

    if (sale.billExcessAdjusted > 0) {
      return 'This sale moved extra money to the customer\'s advance or '
          'refunded it. Reverse that first, then delete the sale.';
    }

    if (sale.payments.any((p) => p.isPalaiSettlement && !p.voided)) {
      return 'A payment on this sale was received through Customer Palai. '
          'Void that payment from Customer Palai first.';
    }

    return null;
  }

  // -----------------------------------------------------------------------
  // SHARED HELPERS
  // -----------------------------------------------------------------------

  double _round2(num value) => SaleDraft.round2(value.toDouble());

  Future<Sale> _readSale(
      Transaction transaction,
      String farmId,
      String saleId,
      ) async {
    final snap = await transaction.get(_saleRef(farmId, saleId));

    if (!snap.exists) {
      throw StateError('This sale could not be found. It may already have '
          'been deleted or cancelled.');
    }

    return Sale.fromDoc(snap);
  }

  /// The money the customer paid up front on an open deal.
  double _advanceOf(Sale sale) {
    return sale.isBooking
        ? (sale.bookingAmount ?? 0)
        : (sale.bookingAdvanceAmount ?? 0);
  }

  /// Number of goats a sale covers.
  int _goatCount(Sale sale) =>
      sale.isLotSale ? sale.lotQuantity : sale.goatIds.length;

  void _writeActivity({
    required Transaction transaction,
    required String farmId,
    required ({String uid, String name, String role})? actor,
    required String title,
    required String subtitle,
  }) {
    transaction.set(_farm(farmId).collection('activities').doc(), {
      'type': ActivityType.revenueVoided.name,
      'title': title,
      'subtitle': subtitle,
      'module': 'trading',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });
  }

  void _archive({
    required Transaction transaction,
    required String farmId,
    required DocumentSnapshot<Map<String, dynamic>> saleSnap,
    required String archiveType,
    required String reason,
    required ({String uid, String name, String role})? actor,
    Map<String, dynamic> extra = const {},
  }) {
    transaction.set(_archiveRef(farmId, saleSnap.id), {
      ...?saleSnap.data(),
      'archiveType': archiveType,
      'archivedAt': FieldValue.serverTimestamp(),
      if (reason.trim().isNotEmpty) 'archiveReason': reason.trim(),
      if (actor != null) 'archivedByUid': actor.uid,
      if (actor != null) 'archivedByName': actor.name,
      ...extra,
    });

    transaction.delete(saleSnap.reference);
  }

  /// Lowers the customer's purchase count by one, when the customer is a
  /// Sale-flow buyer (Palai customers live elsewhere and are not touched).
  void _dropCustomerPurchase({
    required Transaction transaction,
    required String farmId,
    required String customerId,
    required DocumentSnapshot<Map<String, dynamic>>? customerSnap,
  }) {
    if (customerId.isEmpty || customerSnap == null || !customerSnap.exists) {
      return;
    }

    final current =
        (customerSnap.data()?['totalPurchases'] as num?)?.toInt() ?? 0;

    transaction.update(customerSnap.reference, {
      'totalPurchases': current > 0 ? current - 1 : 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _readCustomer(
      Transaction transaction,
      String farmId,
      String customerId,
      ) async {
    if (customerId.trim().isEmpty) return null;

    return transaction.get(_customerRef(farmId, customerId));
  }

  /// Reads every Sold Goat Revenue entry a sale can have, so they can be
  /// voided: the first receipt, one per balance payment, and a kept advance.
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _readRevenueDocs(
      Transaction transaction,
      String farmId,
      Sale sale,
      ) async {
    final keys = <String>[
      'initial',
      for (var i = 1; i <= sale.payments.length + 1; i++) 'pay$i',
      'forfeit',
    ];

    final docs = <DocumentSnapshot<Map<String, dynamic>>>[];

    for (final key in keys) {
      docs.add(
        await transaction.get(_txRef(farmId, _revenueId(sale.id, key))),
      );
    }

    return docs;
  }

  void _voidRevenueDocs(
      Transaction transaction,
      List<DocumentSnapshot<Map<String, dynamic>>> docs,
      String why,
      ) {
    for (final doc in docs) {
      if (!doc.exists) continue;
      if (doc.data()?['status'] == 'voided') continue;

      transaction.update(doc.reference, {
        'status': 'voided',
        'voidedAt': FieldValue.serverTimestamp(),
        'voidReason': why,
      });
    }
  }

  // -----------------------------------------------------------------------
  // CANCEL DEAL
  // -----------------------------------------------------------------------

  /// Cancels an open Booking / Wait for Delivery.
  ///
  /// * the goats go back to Available (or the lot's reserved goats are
  ///   released),
  /// * the Booking / Wait on Delivery count on the dashboard comes down,
  /// * the advance is refunded (revenue voided) or kept (revenue stays, and
  ///   for a Wait for Delivery advance it is recorded now), as chosen,
  /// * the sale is archived, never silently lost.
  Future<void> cancelDeal({
    required String farmId,
    required String saleId,
    required AdvanceDecision advance,
    String reason = '',
  }) async {
    final actor = await FirestoreService.instance.getCurrentActor();

    String customerName = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------- READS ----------------------------
      final saleSnap = await transaction.get(_saleRef(farmId, saleId));

      if (!saleSnap.exists) {
        throw StateError('This sale could not be found. It may already '
            'have been cancelled or deleted.');
      }

      final sale = Sale.fromDoc(saleSnap);

      if (!isOpenDeal(sale)) {
        throw StateError(
          'Only a booking or wait-for-delivery that has not been '
              'delivered can be cancelled.',
        );
      }

      customerName = sale.customerName;

      final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final goatId in sale.goatIds) {
        goatSnaps.add(await transaction.get(_goatRef(farmId, goatId)));
      }

      final revenueDocs = await _readRevenueDocs(transaction, farmId, sale);
      final customerSnap =
      await _readCustomer(transaction, farmId, sale.customerId);

      // ---------------------------- WRITES ---------------------------
      _releaseOpenDeal(
        transaction: transaction,
        farmId: farmId,
        sale: sale,
        goatSnaps: goatSnaps,
      );

      final advanceAmount = _round2(_advanceOf(sale));

      if (advance == AdvanceDecision.refund) {
        _voidRevenueDocs(
          transaction,
          revenueDocs,
          'Deal cancelled, advance refunded',
        );
      } else if (sale.isWaitForDelivery && advanceAmount > 0) {
        // A Wait for Delivery advance was never written to Finance (the
        // final goat value was unknown). Kept money is real income now.
        transaction.set(_txRef(farmId, _revenueId(saleId, 'forfeit')), {
          'amount': advanceAmount,
          'isIncome': true,
          'category': RevenueCategories.soldGoatRevenue,
          if (sale.customerName.trim().isNotEmpty)
            'customerName': sale.customerName.trim(),
          'note': 'Advance kept after cancelled deal, Sale $saleId',
          'paymentMethod': (sale.paymentMethod ?? '').trim().isEmpty
              ? 'Other'
              : sale.paymentMethod!.trim(),
          'date': Timestamp.fromDate(DateTime.now()),
          'status': 'active',
          'referenceType': 'tradingSale',
          'referenceId': saleId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _dropCustomerPurchase(
        transaction: transaction,
        farmId: farmId,
        customerId: sale.customerId,
        customerSnap: customerSnap,
      );

      _archive(
        transaction: transaction,
        farmId: farmId,
        saleSnap: saleSnap,
        archiveType: 'cancelled',
        reason: reason,
        actor: actor,
        extra: {
          'advanceDecision': advance.name,
          'advanceAmount': advanceAmount,
        },
      );

      _writeActivity(
        transaction: transaction,
        farmId: farmId,
        actor: actor,
        title: 'Deal Cancelled',
        subtitle: 'Sale $saleId · ${sale.customerName} · '
            '${_goatCount(sale)} goat(s) back in stock · '
            '${advance == AdvanceDecision.refund ? 'advance refunded' : 'advance kept'}',
      );
    }).timeout(_timeout * 2);

    unawaited(
      FirestoreService.instance.notifyPartnerActivity(
        farmId: farmId,
        type: ActivityType.revenueVoided,
        title: 'Deal Cancelled',
        subtitle: 'Sale $saleId · $customerName',
        module: 'trading',
        actor: actor,
      ),
    );
  }

  /// Puts the goats of an open (undelivered) deal back and lowers the
  /// dashboard counter. Shared by cancel and delete.
  void _releaseOpenDeal({
    required Transaction transaction,
    required String farmId,
    required Sale sale,
    required List<DocumentSnapshot<Map<String, dynamic>>> goatSnaps,
  }) {
    final heldStatus = sale.isBooking
        ? Goat.statusBooked
        : Goat.statusWaitOnDelivery;

    var released = 0;

    for (final snap in goatSnaps) {
      if (!snap.exists) continue;

      final goat = Goat.fromDoc(snap);

      if (goat.currentStatus != heldStatus || goat.saleId != sale.id) {
        continue;
      }

      transaction.update(snap.reference, {
        'currentStatus': Goat.statusAvailable,
        'saleId': FieldValue.delete(),
        'waitOnDeliveryAt': FieldValue.delete(),
      });

      released++;
    }

    if (sale.isLotSale) {
      transaction.update(_purchaseRef(farmId, sale.lotDocId), {
        'reservedFarmQty': FieldValue.increment(-sale.lotQuantity),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      released = sale.lotQuantity;
    }

    transaction.set(
      _summaryRef(farmId),
      {
        (sale.isBooking ? 'booking' : 'waitOnDelivery'):
        FieldValue.increment(-released),
      },
      SetOptions(merge: true),
    );
  }

  // -----------------------------------------------------------------------
  // DELETE SALE
  // -----------------------------------------------------------------------

  /// Deletes a sale and undoes everything it did.
  ///
  /// * An open deal is released exactly like [cancelDeal], with the advance
  ///   refunded (its revenue voided).
  /// * A delivered sale puts its goats back in stock, takes them out of
  ///   Total Sold, removes the profit it added to the dashboard, and voids
  ///   every Sold Goat Revenue entry it created. Money already collected
  ///   is therefore no longer counted in Finance.
  ///
  /// See [deleteBlockReason] for the sales that cannot be deleted.
  Future<void> deleteSale({
    required String farmId,
    required String saleId,
    String reason = '',
  }) async {
    final actor = await FirestoreService.instance.getCurrentActor();

    String customerName = '';

    await _db.runTransaction((transaction) async {
      // ---------------------------- READS ----------------------------
      final saleSnap = await transaction.get(_saleRef(farmId, saleId));

      if (!saleSnap.exists) {
        throw StateError('This sale could not be found. It may already '
            'have been deleted.');
      }

      final sale = Sale.fromDoc(saleSnap);
      final blocked = deleteBlockReason(sale);

      if (blocked != null) throw StateError(blocked);

      customerName = sale.customerName;

      final goatSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final goatId in sale.goatIds) {
        goatSnaps.add(await transaction.get(_goatRef(farmId, goatId)));
      }

      final revenueDocs = await _readRevenueDocs(transaction, farmId, sale);
      final customerSnap =
      await _readCustomer(transaction, farmId, sale.customerId);

      // Cost of the goats, needed to take the profit back off exactly.
      var costOfGoods = 0.0;

      if (isDelivered(sale)) {
        if (sale.isLotSale) {
          costOfGoods =
              _round2((sale.costPerGoatSnapshot ?? 0) * sale.lotQuantity);
        } else {
          final purchaseIds = goatSnaps
              .where((s) => s.exists)
              .map((s) => Goat.fromDoc(s).purchaseId)
              .toList();

          final perPurchase = <String, double>{};

          for (final id in purchaseIds.where((e) => e.trim().isNotEmpty).toSet()) {
            final snap = await transaction.get(_purchaseRef(farmId, id));

            if (snap.exists) {
              perPurchase[id] =
                  TradingPurchase.fromDoc(snap).costPerSurvivingGoat;
            }
          }

          costOfGoods = _round2(
            purchaseIds.fold<double>(
              0,
                  (sum, id) => sum + (perPurchase[id] ?? 0),
            ),
          );
        }
      }

      // ---------------------------- WRITES ---------------------------
      if (isOpenDeal(sale)) {
        _releaseOpenDeal(
          transaction: transaction,
          farmId: farmId,
          sale: sale,
          goatSnaps: goatSnaps,
        );
      } else {
        _reverseDelivered(
          transaction: transaction,
          farmId: farmId,
          sale: sale,
          goatSnaps: goatSnaps,
          costOfGoods: costOfGoods,
        );
      }

      _voidRevenueDocs(
        transaction,
        revenueDocs,
        'Sale deleted',
      );

      _dropCustomerPurchase(
        transaction: transaction,
        farmId: farmId,
        customerId: sale.customerId,
        customerSnap: customerSnap,
      );

      _archive(
        transaction: transaction,
        farmId: farmId,
        saleSnap: saleSnap,
        archiveType: 'deleted',
        reason: reason,
        actor: actor,
      );

      _writeActivity(
        transaction: transaction,
        farmId: farmId,
        actor: actor,
        title: 'Sale Deleted',
        subtitle: 'Sale $saleId · ${sale.customerName} · '
            '${_goatCount(sale)} goat(s) back in stock',
      );
    }).timeout(_timeout * 2);

    unawaited(
      FirestoreService.instance.notifyPartnerActivity(
        farmId: farmId,
        type: ActivityType.revenueVoided,
        title: 'Sale Deleted',
        subtitle: 'Sale $saleId · $customerName',
        module: 'trading',
        actor: actor,
      ),
    );
  }

  /// Undoes a delivered sale's effect on goats, the lot and the dashboard.
  /// The profit taken off is the same figure the sale added: goat sale
  /// (after discount) plus holding charges, minus the goats' cost.
  void _reverseDelivered({
    required Transaction transaction,
    required String farmId,
    required Sale sale,
    required List<DocumentSnapshot<Map<String, dynamic>>> goatSnaps,
    required double costOfGoods,
  }) {
    final profit = _round2(sale.billRevenueTotal - costOfGoods);

    var goats = 0;

    if (sale.isLotSale) {
      final fromSupplier = sale.sourceLocation == Sale.sourceSupplier;

      transaction.update(_purchaseRef(farmId, sale.lotDocId), {
        if (fromSupplier)
          'soldFromSupplierQty': FieldValue.increment(-sale.lotQuantity)
        else
          ...{
            'soldFromFarmQty': FieldValue.increment(-sale.lotQuantity),
            'pendingCount': FieldValue.increment(sale.lotQuantity),
          },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      goats = sale.lotQuantity;

      transaction.set(
        _summaryRef(farmId),
        {
          if (!fromSupplier) ...{
            'totalStock': FieldValue.increment(goats),
            'pendingRegistrations': FieldValue.increment(goats),
          },
          'totalSold': FieldValue.increment(-goats),
          'totalProfit': FieldValue.increment(-profit),
        },
        SetOptions(merge: true),
      );

      return;
    }

    for (final snap in goatSnaps) {
      if (!snap.exists) continue;

      final goat = Goat.fromDoc(snap);

      if (goat.currentStatus != Goat.statusSold || goat.saleId != sale.id) {
        continue;
      }

      transaction.update(snap.reference, {
        'currentStatus': Goat.statusAvailable,
        'saleId': FieldValue.delete(),
      });

      goats++;
    }

    transaction.set(
      _summaryRef(farmId),
      {
        'totalStock': FieldValue.increment(goats),
        'totalSold': FieldValue.increment(-goats),
        'totalProfit': FieldValue.increment(-profit),
      },
      SetOptions(merge: true),
    );
  }

  // -----------------------------------------------------------------------
  // EDIT SALE
  // -----------------------------------------------------------------------

  /// Edits a sale.
  ///
  /// Always editable: customer name, mobile and address (also updated on
  /// the sale's Finance entries so reports show the corrected name).
  ///
  /// Editable only while the deal is open:
  ///  * [discount]  - comes off the goat amount; the goat amount on the
  ///    sale moves with it, and a Booking's booking-date revenue is lowered
  ///    if the discounted sale is worth less than the money received,
  ///  * [holdingChargePerDay] - Booking only; the rate used when the
  ///    delivery is completed.
  ///
  /// A delivered sale's money is not edited here: its payments are
  /// corrected by voiding a payment, or by deleting the sale.
  Future<void> editSale({
    required String farmId,
    required String saleId,
    required String customerName,
    required String mobile,
    required String address,
    double? discount,
    double? holdingChargePerDay,
  }) async {
    final name = customerName.trim();

    if (name.isEmpty) {
      throw StateError('Customer name cannot be empty.');
    }

    final actor = await FirestoreService.instance.getCurrentActor();

    await _db.runTransaction((transaction) async {
      // ---------------------------- READS ----------------------------
      final sale = await _readSale(transaction, farmId, saleId);
      final open = isOpenDeal(sale);

      final revenueDocs = await _readRevenueDocs(transaction, farmId, sale);

      // ---------------------------- WRITES ---------------------------
      final update = <String, dynamic>{
        'customerName': name,
        'mobile': mobile.trim(),
        'address': address.trim(),
      };

      if (open && discount != null) {
        final newDiscount = _round2(discount < 0 ? 0 : discount);
        final goatBefore = _round2(sale.totalSaleAmount + sale.appliedDiscount);

        if (newDiscount > goatBefore) {
          throw StateError(
            'The discount cannot be more than the goat amount '
                '(₹${goatBefore.toStringAsFixed(2)}).',
          );
        }

        final newTotal = _round2(goatBefore - newDiscount);

        update['discount'] = newDiscount;
        update['totalSaleAmount'] = newTotal;

        // A Booking's money was recorded as revenue on the booking day,
        // capped at the goat value then. Keep it within the new value.
        if (sale.isBooking) {
          final initial = revenueDocs.first;

          if (initial.exists && initial.data()?['status'] != 'voided') {
            final allowed = _round2(
              Sale.revenueFromPaid(
                paid: sale.bookingAmount ?? 0,
                revenueTotal: newTotal,
              ),
            );

            final recorded =
            _round2((initial.data()?['amount'] as num?) ?? 0);

            if (allowed != recorded) {
              if (allowed <= 0) {
                transaction.update(initial.reference, {
                  'status': 'voided',
                  'voidedAt': FieldValue.serverTimestamp(),
                  'voidReason': 'Sale edited: discount',
                });
              } else {
                transaction.update(initial.reference, {
                  'amount': allowed,
                  'note': 'Sold Goat Revenue — Sale $saleId '
                      '(adjusted for an edited discount)',
                });
              }
            }
          }
        }
      }

      if (open && sale.isBooking && holdingChargePerDay != null) {
        update['holdingChargePerDay'] =
            _round2(holdingChargePerDay < 0 ? 0 : holdingChargePerDay);
      }

      transaction.update(_saleRef(farmId, saleId), update);

      for (final doc in revenueDocs) {
        if (!doc.exists) continue;

        transaction.update(doc.reference, {'customerName': name});
      }

      _writeActivity(
        transaction: transaction,
        farmId: farmId,
        actor: actor,
        title: 'Sale Edited',
        subtitle: 'Sale $saleId · $name',
      );
    }).timeout(_timeout * 2);
  }
}