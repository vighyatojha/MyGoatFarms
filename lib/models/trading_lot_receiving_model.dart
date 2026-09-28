import 'package:cloud_firestore/cloud_firestore.dart';

/// One receiving event for a purchase lot — a batch of the lot's goats
/// arriving at the farm.
///
/// Stored at:
/// farms/{farmId}/tradingPurchases/{lotDocId}/receivings/{receivingId}
///
/// A lot can be received in several events (e.g. 80 goats on Monday, the
/// other 20 on Friday). Purchase weight/quantity on the lot itself never
/// changes; these events record what actually arrived, so "purchased vs
/// received" stays visible.
class LotReceiving {
  final String id;
  final DateTime date;

  /// Goats in this batch that arrived alive.
  final int arrivedQty;

  /// Goats in this batch that died in transit.
  final int diedQty;

  /// Total weight (kg) of the [arrivedQty] goats on arrival.
  final double arrivalWeight;

  final String note;

  /// True for the event synthesized when an old purchase that had
  /// already been received is converted into a lot.
  final bool isLegacy;

  final DateTime? createdAt;
  final String? actorUid;
  final String? actorName;

  const LotReceiving({
    required this.id,
    required this.date,
    required this.arrivedQty,
    this.diedQty = 0,
    required this.arrivalWeight,
    this.note = '',
    this.isLegacy = false,
    this.createdAt,
    this.actorUid,
    this.actorName,
  });

  /// Goats this event accounts for, alive or dead.
  int get totalQty => arrivedQty + diedQty;

  factory LotReceiving.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime? dateOrNull(String key) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return LotReceiving(
      id: doc.id,
      date: dateOrNull('date') ?? DateTime.now(),
      arrivedQty: (data['arrivedQty'] as num?)?.toInt() ?? 0,
      diedQty: (data['diedQty'] as num?)?.toInt() ?? 0,
      arrivalWeight: (data['arrivalWeight'] as num?)?.toDouble() ?? 0,
      note: (data['note'] ?? '').toString(),
      isLegacy: data['isLegacy'] == true,
      createdAt: dateOrNull('createdAt'),
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
    );
  }

  /// Does not write createdAt — the service adds a server timestamp.
  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'arrivedQty': arrivedQty,
    'diedQty': diedQty,
    'arrivalWeight': arrivalWeight,
    'note': note.trim(),
    'isLegacy': isLegacy,
    if (actorUid != null) 'actorUid': actorUid,
    if (actorName != null) 'actorName': actorName,
  };
}