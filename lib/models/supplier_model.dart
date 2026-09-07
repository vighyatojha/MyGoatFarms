import 'package:cloud_firestore/cloud_firestore.dart';

/// A supplier/vendor the farm buys feed, medicine, or other stock from.
///
/// Mirrors [PalaiCustomer]'s balance shape, but from the opposite side of
/// the ledger:
///  - [pendingAmount]  = what the farm currently OWES this supplier
///                       (unpaid credit purchases).
///  - [advanceAmount]  = what the farm has PAID this supplier in excess
///                       of what it owed (an advance against future
///                       purchases).
class SupplierModel {
  final String id;
  final String name;
  final String mobileNumber;
  final String address;

  /// Amount the farm currently owes this supplier.
  final double pendingAmount;

  /// Amount the farm has paid this supplier in advance.
  final double advanceAmount;

  final DateTime createdAt;

  SupplierModel({
    required this.id,
    required this.name,
    this.mobileNumber = '',
    this.address = '',
    this.pendingAmount = 0,
    this.advanceAmount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory SupplierModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return SupplierModel(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      mobileNumber: (data['mobileNumber'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      pendingAmount: (data['pendingAmount'] as num?)?.toDouble() ?? 0,
      advanceAmount: (data['advanceAmount'] as num?)?.toDouble() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Returns a copy of this supplier with updated balances — used to keep
  /// a detail screen's local state in sync right after a credit purchase
  /// or payment is recorded, without waiting for a fresh stream/read.
  SupplierModel copyWith({
    double? pendingAmount,
    double? advanceAmount,
  }) {
    return SupplierModel(
      id: id,
      name: name,
      mobileNumber: mobileNumber,
      address: address,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) => other is SupplierModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}