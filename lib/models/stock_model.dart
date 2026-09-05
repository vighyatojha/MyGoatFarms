import 'package:cloud_firestore/cloud_firestore.dart';

enum StockType { feed, medicine }

/// A single stock item (a type of feed or medicine) tracked in quantity.
class StockItem {
  final String id;
  final String name;
  final StockType type;
  final double quantity; // kg for feed, units for medicine
  final String unit; // "kg", "bottle", "pack" etc.
  final double lowStockThreshold;
  final DateTime lastUpdated;

  StockItem({
    required this.id,
    required this.name,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.lowStockThreshold,
    required this.lastUpdated,
  });

  bool get isLowStock => quantity <= lowStockThreshold;

  // Firestore streams rebuild a brand-new StockItem instance on every
  // snapshot, even when nothing meaningful changed. Without this override,
  // Dart compares instances by identity, so a StockItem held onto from an
  // older snapshot (e.g. a dropdown's selected value) stops matching any
  // entry in a newer list even though it represents the same document —
  // which breaks widgets like DropdownButton that match `value` against
  // `items` using `==`.
  @override
  bool operator ==(Object other) => other is StockItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  factory StockItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return StockItem(
      id: doc.id,
      name: data['name'] ?? '',
      type: (data['type'] == 'medicine') ? StockType.medicine : StockType.feed,
      quantity: (data['quantity'] ?? 0).toDouble(),
      unit: data['unit'] ?? 'kg',
      lowStockThreshold: (data['lowStockThreshold'] ?? 0).toDouble(),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type == StockType.medicine ? 'medicine' : 'feed',
      'quantity': quantity,
      'unit': unit,
      'lowStockThreshold': lowStockThreshold,
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }
}

/// A logged stock movement — either stock added (purchase) or stock used.
class StockMovement {
  final String id;
  final String stockItemId;
  final String itemName;
  final double quantity;
  final String unit;
  final bool isAddition; // true = added to stock, false = used/consumed
  final DateTime date;
  final String notes;

  /// Who performed this movement — set by [FirestoreService.getCurrentActor]
  /// at write time, the same way [ActivityLog] attaches its actor fields.
  /// Nullable so older stock movements written before this field existed
  /// still parse and render fine (they just show no "By ..." line).
  final String? actorUid;
  final String? actorName;
  final String? actorRole; // 'owner' or 'partner'

  StockMovement({
    required this.id,
    required this.stockItemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.isAddition,
    required this.date,
    required this.notes,
    this.actorUid,
    this.actorName,
    this.actorRole,
  });

  /// "OWNER" / "PARTNER" badge text for the recent-activity list, or null
  /// when there's no actor on this doc (older movements).
  String? get actorRoleLabel {
    final role = actorRole;
    if (role == null || role.isEmpty) return null;
    return role.toUpperCase();
  }

  factory StockMovement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return StockMovement(
      id: doc.id,
      stockItemId: data['stockItemId'] ?? '',
      itemName: data['itemName'] ?? '',
      quantity: (data['quantity'] ?? 0).toDouble(),
      unit: data['unit'] ?? 'kg',
      isAddition: data['isAddition'] ?? true,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'] ?? '',
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stockItemId': stockItemId,
      'itemName': itemName,
      'quantity': quantity,
      'unit': unit,
      'isAddition': isAddition,
      'date': Timestamp.fromDate(date),
      'notes': notes,
      if (actorUid != null) 'actorUid': actorUid,
      if (actorName != null) 'actorName': actorName,
      if (actorRole != null) 'actorRole': actorRole,
    };
  }
}