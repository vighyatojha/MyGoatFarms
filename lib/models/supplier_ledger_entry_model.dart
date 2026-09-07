import 'package:cloud_firestore/cloud_firestore.dart';

enum SupplierLedgerEntryKind {
  creditPurchase, // stock bought on credit — increases what we owe
  payment, // payment made to the supplier — reduces what we owe
}

/// One row in a Supplier Ledger — built directly from a `supplierLedger`
/// document. Mirrors [CustomerLedgerEntry], but for the supplier side:
/// a credit purchase is a debit (we owe more), a payment is a credit
/// (we owe less).
class SupplierLedgerEntry {
  final String id;
  final SupplierLedgerEntryKind kind;
  final DateTime date;
  final String title;
  final String subtitle;

  /// True when this entry increases what the farm owes the supplier
  /// (a credit purchase), false when it reduces it (a payment made).
  final bool isDebit;

  final double amount;

  final double? pendingBefore;
  final double? pendingAfter;
  final double? advanceBefore;
  final double? advanceAfter;

  final String? paymentMethod;
  final String? note;
  final String? stockMovementId;

  const SupplierLedgerEntry({
    required this.id,
    required this.kind,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.isDebit,
    required this.amount,
    this.pendingBefore,
    this.pendingAfter,
    this.advanceBefore,
    this.advanceAfter,
    this.paymentMethod,
    this.note,
    this.stockMovementId,
  });

  factory SupplierLedgerEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};
    final type = (data['type'] ?? '').toString();
    final isCreditPurchase = type == 'creditPurchase';

    final itemName = (data['itemName'] ?? '').toString();

    return SupplierLedgerEntry(
      id: doc.id,
      kind: isCreditPurchase
          ? SupplierLedgerEntryKind.creditPurchase
          : SupplierLedgerEntryKind.payment,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      title: isCreditPurchase ? 'Stock Purchased on Credit' : 'Payment Made',
      subtitle: isCreditPurchase ? itemName : (data['paymentMethod'] ?? '').toString(),
      isDebit: isCreditPurchase,
      amount: (data['amount'] ?? 0).toDouble(),
      pendingBefore: (data['pendingBefore'] as num?)?.toDouble(),
      pendingAfter: (data['pendingAfter'] as num?)?.toDouble(),
      advanceBefore: (data['advanceBefore'] as num?)?.toDouble(),
      advanceAfter: (data['advanceAfter'] as num?)?.toDouble(),
      paymentMethod: data['paymentMethod'] as String?,
      note: (data['note'] ?? '').toString(),
      stockMovementId: data['stockMovementId'] as String?,
    );
  }
}