import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking_delivery_group.dart';
import '../models/customer_account.dart';
import '../models/customer_credit.dart';
import '../models/customer_model.dart';
import '../models/customer_sales_history.dart';
import '../models/goat_model.dart';
import '../models/palai_models.dart';
import '../models/sale_model.dart';
import '../models/wait_delivery_group.dart';
import 'booking_delivery_service.dart';
import 'firestore_service.dart';
import 'goat_service.dart';
import 'sales_service.dart';
import 'wait_delivery_service.dart';

/// Read-only. Combines the streams the existing screens already use into
/// one [CustomerAccountBook]. It never writes anything: payments,
/// deliveries and refunds stay in their existing screens and services.
class CustomerAccountService {
  CustomerAccountService._();

  static final CustomerAccountService instance = CustomerAccountService._();

  /// The list and the account screen both use this, so they can never show
  /// different numbers for the same customer.
  Stream<CustomerAccountBook> bookStream(String farmId) {
    final sources = <Stream<Object?>>[
      FirestoreService.instance.customersStream(farmId),
      SalesService.instance.creditCustomersStream(farmId),
      SalesService.instance.customersStream(farmId),
      WaitDeliveryService.instance.openSalesStream(farmId),
      BookingDeliveryService.instance.openSalesStream(farmId),
      GoatService.instance.goatsStream(farmId),
      FirestoreService.instance.allActiveGoatsStream(farmId),
    ];

    return _combine<CustomerAccountBook>(
      sources,
          (v) => _build(
        palai: v[0] as List<PalaiCustomer>,
        credits: v[1] as List<CustomerCredit>,
        trading: v[2] as List<Customer>,
        waitSales: v[3] as List<Sale>,
        bookingSales: v[4] as List<Sale>,
        goats: v[5] as List<Goat>,
        palaiGoats: v[6] as List<PalaiGoat>,
      ),
    );
  }

  /// The [CustomerAccount.key] of the person who owns the delivery group
  /// [groupKey], read once from [bookStream] so the match is exactly the
  /// one the Customers hub makes. Null when no open booking has that key
  /// any more (e.g. it was just delivered).
  Future<String?> personKeyForDeliveryGroup(
      String farmId,
      String groupKey,
      ) async {
    final book = await bookStream(farmId)
        .first
        .timeout(const Duration(seconds: 30));
    return book.byDeliveryKey(groupKey)?.key;
  }

  /// Every sale of the farm plus every trading goat: what a customer's
  /// purchase history is built from (same full read the Total Sold
  /// screen uses). Read-only.
  Stream<List<Sale>> allSalesStream(String farmId) {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('sales')
        .snapshots()
        .map((snap) => snap.docs.map(Sale.fromDoc).toList());
  }

  /// One person's account and goat purchase history, live. The account
  /// comes from [bookStream], so the person is matched exactly as on the
  /// list. [personKey] is [CustomerAccount.key].
  Stream<CustomerProfileData> profileStream(
      String farmId,
      String personKey,
      ) {
    final sources = <Stream<Object?>>[
      bookStream(farmId),
      allSalesStream(farmId),
      GoatService.instance.goatsStream(farmId),
    ];
    return _combine<CustomerProfileData>(sources, (values) {
      final book = values[0] as CustomerAccountBook;
      final account = book.byId(personKey);
      return CustomerProfileData(
        account: account,
        history: account == null
            ? null
            : CustomerSalesHistory.build(
          account: account,
          sales: values[1] as List<Sale>,
          goats: values[2] as List<Goat>,
        ),
      );
    });
  }

  /// Emits [combine] of the latest value of every source once all have
  /// produced one, and again whenever any of them changes.
  Stream<T> _combine<T>(
      List<Stream<Object?>> sources,
      T Function(List<Object?> values) combine,
      ) {
    final latest = List<Object?>.filled(sources.length, null);
    final ready = List<bool>.filled(sources.length, false);
    final subs = <StreamSubscription<Object?>>[];
    late final StreamController<T> controller;

    void emit() {
      if (ready.contains(false) || controller.isClosed) return;
      try {
        controller.add(combine(latest));
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subs.add(
            sources[i].listen(
                  (value) {
                latest[i] = value;
                ready[i] = true;
                emit();
              },
              onError: controller.addError,
            ),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  CustomerAccountBook _build({
    required List<PalaiCustomer> palai,
    required List<CustomerCredit> credits,
    required List<Customer> trading,
    required List<Sale> waitSales,
    required List<Sale> bookingSales,
    required List<Goat> goats,
    required List<PalaiGoat> palaiGoats,
  }) {
    final today = DateTime.now();

    final waitGroups = WaitDeliveryCustomer.group(sales: waitSales, goats: goats)
        .map(
          (c) => DeliveryGroupSummary(
        key: c.key,
        name: c.name,
        mobile: c.mobile,
        address: c.address,
        goatCount: c.goatCount,
        bookingCount: c.sales.length,
        estimate: c.estimatedRemaining,
      ),
    )
        .toList();

    final bookingGroups =
    BookingDeliveryCustomer.group(sales: bookingSales, goats: goats)
        .map(
          (c) => DeliveryGroupSummary(
        key: c.key,
        name: c.name,
        goatCount: c.goatCount,
        bookingCount: c.sales.length,
        estimate: Sale.roundMoney(
          c.sales.fold<double>(
            0,
                (sum, e) => sum + e.finalAmountAt(today),
          ),
        ),
        mobile: c.mobile,
        address: c.address,
      ),
    )
        .toList();

    final active = <String, int>{};
    for (final g in palaiGoats) {
      if (g.isCheckedOut) continue;
      active[g.customerId] = (active[g.customerId] ?? 0) + 1;
    }

    return CustomerAccountBook.build(
      palaiCustomers: palai,
      credits: credits,
      tradingCustomers: trading,
      waitGroups: waitGroups,
      bookingGroups: bookingGroups,
      activePalaiGoats: active,
    );
  }
}

/// What the account and purchase history screens show for one customer.
class CustomerProfileData {
  /// Null when the customer no longer exists.
  final CustomerAccount? account;
  final CustomerSalesHistory? history;

  const CustomerProfileData({required this.account, required this.history});
}