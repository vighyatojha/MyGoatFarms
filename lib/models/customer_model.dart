import 'package:cloud_firestore/cloud_firestore.dart';

/// A Trading-module customer (goat buyer).
///
/// Stored at:
/// farms/{farmId}/customers/{customerId}
///
/// This is deliberately separate from `PalaiCustomer`
/// (farms/{farmId}/palaiCustomers/{customerId}), which represents an
/// ongoing Palai boarding relationship (package, joining date, monthly
/// billing). A Sale customer may never become a Palai customer at all
/// (Deliver Now / Booking / Wait for Delivery), so forcing Palai-only
/// fields onto every buyer here would be wrong, and would pollute the
/// Palai dashboard's pending-payments total.
///
/// When a sale's delivery branch is "Transfer to Palai"
/// (Section 3, Task 3.4), a `PalaiCustomer` record is created/linked
/// separately — see SalesService.
///
/// See also: `CustomerMatch` in sales_service.dart, which merges this
/// collection with `palaiCustomers` for name/mobile lookup so a person
/// who is already a Palai customer is recognised while looking up a
/// buyer for a sale, instead of being registered twice.
class Customer {
  final String id;

  final String name;
  final String mobile;
  final String address;
  final String notes;

  /// Running count of sales this customer has been part of. Incremented
  /// by SalesService whenever a sale is saved against this customer, so
  /// Step 2's lookup (Task 2.2) can show purchase history at a glance.
  final int totalPurchases;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Customer({
    required this.id,
    required this.name,
    required this.mobile,
    this.address = '',
    this.notes = '',
    this.totalPurchases = 0,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------

  factory Customer.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    DateTime? dateFrom(String key) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return null;
    }

    int intFrom(String key) {
      final value = data[key];

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return Customer(
      id: doc.id,

      name:
      (data['name'] ?? '').toString(),

      mobile:
      (data['mobile'] ?? '').toString(),

      address:
      (data['address'] ?? '').toString(),

      notes:
      (data['notes'] ?? '').toString(),

      totalPurchases:
      intFrom('totalPurchases'),

      createdAt:
      dateFrom('createdAt'),

      updatedAt:
      dateFrom('updatedAt'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'mobile': mobile.trim(),
      'address': address.trim(),
      'notes': notes.trim(),
      'totalPurchases': totalPurchases,
    };
  }

  Customer copyWith({
    String? name,
    String? mobile,
    String? address,
    String? notes,
    int? totalPurchases,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Customer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}