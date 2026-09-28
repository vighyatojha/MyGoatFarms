import 'package:cloud_firestore/cloud_firestore.dart';

/// One payment made to the supplier against a purchase lot.
///
/// Stored at:
/// farms/{farmId}/tradingPurchases/{lotDocId}/payments/{paymentId}
///
/// Payments are append-only — a later payment never overwrites an earlier
/// one. The lot's `paidAmount` is the sum of these documents, kept in sync
/// by TradingService in the same transaction that writes the payment, so
/// paid / due / status are always derived from real records.
class LotPayment {
  final String id;
  final double amount;
  final DateTime date;

  /// 'Cash' or 'Online' (same limit as the purchase itself).
  final String method;
  final String note;

  /// True for the single payment synthesized when an old goat-first
  /// purchase (which was always paid in full at purchase time) is
  /// converted into a lot. No Finance entry is created for it — the
  /// original purchase expense already exists.
  final bool isLegacy;

  /// Id of the Finance expense posted for this payment, so the two can
  /// be traced to each other. Null for legacy payments.
  final String? expenseId;

  final DateTime? createdAt;
  final String? actorUid;
  final String? actorName;

  const LotPayment({
    required this.id,
    required this.amount,
    required this.date,
    required this.method,
    this.note = '',
    this.isLegacy = false,
    this.expenseId,
    this.createdAt,
    this.actorUid,
    this.actorName,
  });

  factory LotPayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime? dateOrNull(String key) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return LotPayment(
      id: doc.id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      date: dateOrNull('date') ?? DateTime.now(),
      method: (data['method'] ?? 'Cash').toString(),
      note: (data['note'] ?? '').toString(),
      isLegacy: data['isLegacy'] == true,
      expenseId: data['expenseId'] as String?,
      createdAt: dateOrNull('createdAt'),
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
    );
  }

  /// Does not write createdAt — the service adds a server timestamp.
  Map<String, dynamic> toMap() => {
    'amount': amount,
    'date': Timestamp.fromDate(date),
    'method': method,
    'note': note.trim(),
    'isLegacy': isLegacy,
    if (expenseId != null) 'expenseId': expenseId,
    if (actorUid != null) 'actorUid': actorUid,
    if (actorName != null) 'actorName': actorName,
  };
}