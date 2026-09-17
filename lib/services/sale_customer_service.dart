import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/palai_customer.dart';
import '../models/sale_customer.dart';

/// Handles the Sale module's own buyer records.
///
/// Collection layout:
///
/// farms/{farmId}/customers_own_palai/{customerId}
///
/// IMPORTANT — WHY THIS IS NOT `palaiCustomers`:
/// `farms/{farmId}/palaiCustomers` models a boarding customer (package,
/// joining date, pending/advance balance feeding the Palai billing
/// dashboard). A Sale buyer is a different kind of record — someone who
/// buys goats, with no package or boarding relationship. Keeping them
/// separate means a one-off "Deliver Now" sale never has to invent fake
/// package/joining-date values, and never pollutes the Palai pending-
/// payments dashboard total.
///
/// DYNAMIC CUSTOMER SOURCE:
/// The Sale customer picker (a later task) offers two paths, both landing
/// here:
/// 1. "Create new customer" -> [addCustomer] with a fresh [SaleCustomer].
/// 2. "Use existing Palai customer" -> [getOrCreateFromPalaiCustomer],
///    which links to (and reuses, if already linked) a Sale customer
///    record seeded from that Palai customer's identity fields.
class SaleCustomerService {
  SaleCustomerService._();

  static final SaleCustomerService instance = SaleCustomerService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // -----------------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() {
    return _db.collection('farms');
  }

  CollectionReference<Map<String, dynamic>> _customers(String farmId) {
    return _farms().doc(farmId).collection('customers_own_palai');
  }

  // -----------------------------------------------------------------------
  // READ
  // -----------------------------------------------------------------------

  /// Live list of every Sale customer, most recently updated first.
  Stream<List<SaleCustomer>> customersStream(String farmId) {
    return _customers(farmId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(SaleCustomer.fromDoc).toList());
  }

  /// Fetches a single Sale customer once — used to prefill an edit form.
  Future<SaleCustomer?> getCustomer(String farmId, String customerId) async {
    final doc =
    await _customers(farmId).doc(customerId).get().timeout(_timeout);
    if (!doc.exists) return null;
    return SaleCustomer.fromDoc(doc);
  }

  /// Live stream of a single Sale customer — used wherever a screen needs
  /// the customer's current running totals without going stale.
  Stream<SaleCustomer?> customerStream(String farmId, String customerId) {
    return _customers(farmId).doc(customerId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SaleCustomer.fromDoc(doc);
    });
  }

  /// Simple client-side name/mobile search over the live customer list.
  /// The Sale customer list is expected to stay small enough (farm-scale)
  /// that a Firestore full-text index isn't warranted yet.
  Stream<List<SaleCustomer>> searchCustomers(String farmId, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return customersStream(farmId);
    }

    return customersStream(farmId).map((customers) {
      return customers.where((customer) {
        return customer.name.toLowerCase().contains(normalized) ||
            customer.mobileNumber.contains(normalized);
      }).toList();
    });
  }

  // -----------------------------------------------------------------------
  // CREATE / UPDATE — manual path
  // -----------------------------------------------------------------------

  /// Creates a brand-new Sale customer (the "Create new customer" path).
  /// Returns the new document id.
  Future<String> addCustomer(String farmId, SaleCustomer customer) async {
    final error = customer.validate();
    if (error != null) {
      throw ArgumentError(error);
    }

    final ref = await _customers(farmId)
        .add(customer.toMap(useServerTimestamps: true))
        .timeout(_timeout);
    return ref.id;
  }

  Future<void> updateCustomer(String farmId, SaleCustomer customer) async {
    final error = customer.validate();
    if (error != null) {
      throw ArgumentError(error);
    }

    await _customers(farmId)
        .doc(customer.id)
        .set(
      customer.toMap(useServerTimestamps: true),
      SetOptions(merge: true),
    )
        .timeout(_timeout);
  }

  // -----------------------------------------------------------------------
  // CREATE — dynamic "use existing Palai customer" path
  // -----------------------------------------------------------------------

  /// Finds the Sale customer already linked to [palaiCustomer], if the
  /// person has picked this same Palai customer before, so repeat sales to
  /// the same person don't create duplicate Sale customer records.
  Future<SaleCustomer?> findLinkedToPalaiCustomer(
      String farmId,
      String palaiCustomerId,
      ) async {
    final snapshot = await _customers(farmId)
        .where('linkedPalaiCustomerId', isEqualTo: palaiCustomerId)
        .limit(1)
        .get()
        .timeout(_timeout);

    if (snapshot.docs.isEmpty) return null;
    return SaleCustomer.fromDoc(snapshot.docs.first);
  }

  /// The "Use existing Palai customer" path.
  ///
  /// If [palaiCustomer] has already been linked to a Sale customer, that
  /// existing record is reused as-is (no duplicate created). Otherwise a
  /// new Sale customer is seeded from the Palai customer's identity
  /// fields and linked via [SaleCustomer.linkedPalaiCustomerId].
  ///
  /// This never writes back into `palaiCustomers` — the link is one-way,
  /// from the Sale customer record toward the Palai customer it was
  /// sourced from.
  Future<SaleCustomer> getOrCreateFromPalaiCustomer(
      String farmId,
      PalaiCustomer palaiCustomer,
      ) async {
    final existing = await findLinkedToPalaiCustomer(
      farmId,
      palaiCustomer.id,
    );
    if (existing != null) {
      return existing;
    }

    final docRef = _customers(farmId).doc();
    final seeded = SaleCustomer.fromPalaiCustomerFields(
      id: docRef.id,
      palaiCustomerId: palaiCustomer.id,
      name: palaiCustomer.name,
      mobileNumber: palaiCustomer.mobileNumber,
      alternateMobileNumber: palaiCustomer.alternateMobileNumber,
      address: palaiCustomer.address,
    );

    await docRef
        .set(seeded.toMap(useServerTimestamps: true))
        .timeout(_timeout);

    return seeded;
  }

  // -----------------------------------------------------------------------
  // SALE TOTALS
  // -----------------------------------------------------------------------

  /// Increments a Sale customer's running totals after a sale completes.
  /// Called by the Sale wizard once a sale is finalized (a later task) —
  /// kept here since it's a simple, self-contained write against this
  /// collection.
  Future<void> recordCompletedSale(
      String farmId,
      String customerId, {
        required int goatsCount,
        required double amount,
      }) async {
    await _customers(farmId).doc(customerId).update({
      'totalPurchases': FieldValue.increment(1),
      'totalGoatsPurchased': FieldValue.increment(goatsCount),
      'totalSpent': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }
}