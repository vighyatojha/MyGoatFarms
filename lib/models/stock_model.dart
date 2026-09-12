import 'package:cloud_firestore/cloud_firestore.dart';

enum StockType { feed, medicine }

/// A single stock item (a type of feed or medicine) tracked in quantity.
///
/// --- Bag vs KG ---------------------------------------------------------
/// When [unit] is "Bag", [quantity] is the number of *physical bags*
/// (never a KG figure — the two must never be swapped). [weightPerBag] is
/// how much a single bag weighs, captured once from the user when they
/// pick "Bag" as the unit. [totalKg] is the normalized weight in
/// kilograms and is the authoritative figure used for all calculations
/// (low-stock checks, deductions, merging purchases) — see
/// FirestoreService.addStock / useStock. This mirrors the "Proposed Stock
/// Logic" doc: bags stay bags for display, KG stays the calculation unit.
///
/// When [unit] is "Kg" (or any other non-bag unit, e.g. medicine's
/// "Bottle"/"Unit"), [quantity] and [totalKg] are the same number and
/// [weightPerBag] is null.
class StockItem {
  final String id;
  final String name;
  final StockType type;
  final double quantity; // number of bags when unit == "Bag"; otherwise same as totalKg
  final String unit; // "Kg", "Bag", "Bottle", "Unit" etc.
  final double? weightPerBag; // KG per bag — only set when unit == "Bag"
  final double totalKg; // normalized weight in KG; authoritative for weight-based units
  final double lowStockThreshold;
  final DateTime lastUpdated;

  StockItem({
    required this.id,
    required this.name,
    required this.type,
    required this.quantity,
    required this.unit,
    this.weightPerBag,
    required this.totalKg,
    required this.lowStockThreshold,
    required this.lastUpdated,
  });

  bool get isBagUnit => unit.trim().toLowerCase() == 'bag';
  bool get isKgUnit => unit.trim().toLowerCase() == 'kg';

  /// True when this item is tracked by weight (Kg or Bag), as opposed to
  /// count-based units like medicine's Bottle/Unit — [totalKg] is only
  /// meaningful for weight-based items.
  bool get isWeightBased => isBagUnit || isKgUnit;

  /// Whether a Bag-unit item is missing its bag weight — happens for
  /// records saved before this field existed. Screens should prompt for
  /// the weight rather than guessing, per the "Weight required" rule.
  bool get needsBagWeight => isBagUnit && (weightPerBag == null || weightPerBag! <= 0);

  /// Whole bags currently available, derived from [totalKg] so it never
  /// drifts out of sync with usage/purchases recorded in KG.
  int get wholeBags {
    if (!isBagUnit || needsBagWeight) return 0;
    return (totalKg / weightPerBag!).floor();
  }

  /// Leftover KG that doesn't make up a full bag (e.g. an opened bag).
  double get partialBagKg {
    if (!isBagUnit || needsBagWeight) return 0;
    final remainder = totalKg - (wholeBags * weightPerBag!);
    return remainder < 0.01 ? 0 : remainder;
  }

  /// Short line for list rows, e.g. "5 Bags", "8 Bags + 25 KG", "100 KG".
  String get quantityLabel {
    if (!isWeightBased) return '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} $unit';
    if (isKgUnit) return '${totalKg.toStringAsFixed(totalKg % 1 == 0 ? 0 : 1)} KG';
    if (needsBagWeight) return '${quantity.toStringAsFixed(0)} Bags (weight required)';
    final bags = wholeBags;
    final partial = partialBagKg;
    final total = totalKg.toStringAsFixed(totalKg % 1 == 0 ? 0 : 1);
    if (partial <= 0) {
      return '$bags ${bags == 1 ? 'Bag' : 'Bags'} ($total KG)';
    }
    return '$bags ${bags == 1 ? 'Bag' : 'Bags'} + ${partial.toStringAsFixed(partial % 1 == 0 ? 0 : 1)} KG ($total KG total)';
  }

  /// Longer summary for detail views, e.g. "5 Bags · 50 KG/Bag · 250 KG total".
  String get stockSummary {
    if (!isBagUnit) return quantityLabel;
    if (needsBagWeight) return '$quantityLabel — set the bag weight to see total KG';
    return '$quantityLabel · ${weightPerBag!.toStringAsFixed(weightPerBag! % 1 == 0 ? 0 : 1)} KG/Bag · ${totalKg.toStringAsFixed(totalKg % 1 == 0 ? 0 : 1)} KG total';
  }

  // Threshold is always entered (and compared) in the item's *current*
  // unit — bags for Bag stock, KG for Kg stock — same as [quantity], so
  // no unit conversion is needed here. (Bag-count `quantity` is itself
  // always kept in sync with the authoritative [totalKg], see below.)
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
    final unit = data['unit'] ?? 'kg';
    final quantity = (data['quantity'] ?? 0).toDouble();
    final weightPerBag = (data['weightPerBag'] as num?)?.toDouble();
    final isBag = unit.toString().trim().toLowerCase() == 'bag';

    // Self-heal records saved before `totalKg` existed: derive it from
    // quantity/unit/weightPerBag instead of defaulting to 0, so old data
    // doesn't suddenly look empty.
    final storedTotalKg = (data['totalKg'] as num?)?.toDouble();
    final totalKg = storedTotalKg ??
        (isBag ? (quantity * (weightPerBag ?? 0)) : quantity);

    return StockItem(
      id: doc.id,
      name: data['name'] ?? '',
      type: (data['type'] == 'medicine') ? StockType.medicine : StockType.feed,
      quantity: quantity,
      unit: unit,
      weightPerBag: (weightPerBag != null && weightPerBag > 0) ? weightPerBag : null,
      totalKg: totalKg,
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
      if (weightPerBag != null) 'weightPerBag': weightPerBag,
      'totalKg': totalKg,
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

  /// KG per bag at the time of this movement, and the resulting KG amount
  /// — only set for Bag-unit movements. Kept on the movement itself (not
  /// just derived from the current stock item) so history stays accurate
  /// even if the item's bag weight is changed later.
  final double? weightPerBag;
  final double? kgAmount;

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
    this.weightPerBag,
    this.kgAmount,
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
      weightPerBag: (data['weightPerBag'] as num?)?.toDouble(),
      kgAmount: (data['kgAmount'] as num?)?.toDouble(),
    );
  }

  /// "5 Bags (250 KG)" for bag movements, "100 KG" otherwise.
  String get quantityLabel {
    if (weightPerBag != null && weightPerBag! > 0) {
      final bagWord = quantity == 1 ? 'Bag' : 'Bags';
      final kg = kgAmount ?? (quantity * weightPerBag!);
      return '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} $bagWord (${kg.toStringAsFixed(kg % 1 == 0 ? 0 : 1)} KG)';
    }
    return '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} $unit';
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
      if (weightPerBag != null) 'weightPerBag': weightPerBag,
      if (kgAmount != null) 'kgAmount': kgAmount,
    };
  }
}