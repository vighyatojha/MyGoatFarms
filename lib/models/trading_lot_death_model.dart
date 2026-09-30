import 'package:cloud_firestore/cloud_firestore.dart';

/// One "Record death" event for goats that died at the farm while still
/// part of a Purchase Lot (not yet transferred to Own / Customer Palai and
/// not sold). Stored in `tradingPurchases/{lotId}/deaths`.
///
/// [lossAmount] = [qty] x the lot's cost per surviving goat at the moment
/// of the event. It is informational: the same loss is already carried by
/// the remaining goats, because recording a death raises the lot's
/// mortality and therefore its cost per goat (see
/// TradingService.recordLotFarmDeath).
class LotDeath {
  static const List<String> reasons = [
    'Disease',
    'Injury',
    'Heat / stress',
    'Unknown',
    'Other',
  ];

  final String id;
  final DateTime date;
  final int qty;
  final String reason;
  final String note;
  final double costPerGoat;
  final double lossAmount;
  final DateTime? createdAt;
  final String? actorUid;
  final String? actorName;

  /// True once the event has been undone (see
  /// TradingService.undoLotFarmDeath). The doc is kept as an audit trail;
  /// a reversed event no longer counts as a loss.
  final bool reversed;
  final DateTime? reversedAt;
  final String? reversedByName;

  const LotDeath({
    required this.id,
    required this.date,
    required this.qty,
    required this.reason,
    this.note = '',
    required this.costPerGoat,
    required this.lossAmount,
    this.createdAt,
    this.actorUid,
    this.actorName,
    this.reversed = false,
    this.reversedAt,
    this.reversedByName,
  });

  factory LotDeath.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime? dateOrNull(String key) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return LotDeath(
      id: doc.id,
      date: dateOrNull('date') ?? DateTime.now(),
      qty: (data['qty'] as num?)?.toInt() ?? 0,
      reason: (data['reason'] ?? '').toString(),
      note: (data['note'] ?? '').toString(),
      costPerGoat: (data['costPerGoat'] as num?)?.toDouble() ?? 0,
      lossAmount: (data['lossAmount'] as num?)?.toDouble() ?? 0,
      createdAt: dateOrNull('createdAt'),
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
      reversed: data['reversed'] == true,
      reversedAt: dateOrNull('reversedAt'),
      reversedByName: data['reversedByName'] as String?,
    );
  }

  /// Does not write createdAt — the service adds a server timestamp.
  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'qty': qty,
    'reason': reason,
    'note': note.trim(),
    'costPerGoat': costPerGoat,
    'lossAmount': lossAmount,
    if (actorUid != null) 'actorUid': actorUid,
    if (actorName != null) 'actorName': actorName,
  };
}