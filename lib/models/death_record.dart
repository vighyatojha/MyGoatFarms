
import 'package:cloud_firestore/cloud_firestore.dart';

/// A single "Goat Death & Settlement" record, stored at
/// `farms/{farmId}/deathRecords/{id}`.
///
/// One farm-wide collection covers all three cases (Customer Palai, Own
/// Palai, Available Stock) so the Home Screen's "Goat Death & Settlement"
/// history is a single query. [goatType] tells the UI which shape of
/// record it is — Customer Palai records carry settlement/customer
/// fields, Own Palai and Available Stock records carry [farmLossAmount]
/// instead.
///
/// The goat itself is never deleted — see [DeathSettlementService]. This
/// record is the permanent audit trail of the death/settlement event.
class DeathRecord {
  final String id;

  /// One of [typeCustomerPalai], [typeOwnPalai], [typeAvailableStock].
  final String goatType;

  final String goatId;

  /// Denormalized display label for the goat (tag/goat code for Customer
  /// Palai, breed + short id for farm goats) so history lists never need
  /// a second read.
  final String goatLabel;

  /// Only set for [typeCustomerPalai].
  final String? customerId;
  final String? customerName;

  final DateTime deathDate;
  final String reason;
  final String notes;

  // ---------------------------------------------------------------------
  // CUSTOMER PALAI SETTLEMENT
  // ---------------------------------------------------------------------

  /// 0 for Own Palai / Available Stock (no customer settlement).
  final double settlementAmount;

  /// [directionCredit] or [directionDebit]. Null when [settlementAmount]
  /// is 0.
  final String? settlementDirection;

  final double? customerPendingBefore;
  final double? customerPendingAfter;

  // ---------------------------------------------------------------------
  // FARM LOSS (OWN PALAI / AVAILABLE STOCK)
  // ---------------------------------------------------------------------

  /// 0 for Customer Palai (settlement covers the financial side there).
  final double farmLossAmount;

  final DateTime createdAt;

  final String? actorUid;
  final String? actorName;
  final String? actorRole;

  const DeathRecord({
    required this.id,
    required this.goatType,
    required this.goatId,
    required this.goatLabel,
    this.customerId,
    this.customerName,
    required this.deathDate,
    required this.reason,
    this.notes = '',
    this.settlementAmount = 0,
    this.settlementDirection,
    this.customerPendingBefore,
    this.customerPendingAfter,
    this.farmLossAmount = 0,
    required this.createdAt,
    this.actorUid,
    this.actorName,
    this.actorRole,
  });

  // ---------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------

  static const String typeCustomerPalai = 'customerPalai';
  static const String typeOwnPalai = 'ownPalai';
  static const String typeAvailableStock = 'availableStock';

  static const String directionCredit = 'credit';
  static const String directionDebit = 'debit';

  bool get isCustomerPalai => goatType == typeCustomerPalai;
  bool get isOwnPalai => goatType == typeOwnPalai;
  bool get isAvailableStock => goatType == typeAvailableStock;

  bool get hasSettlement => settlementAmount > 0;
  bool get isCreditSettlement => settlementDirection == directionCredit;
  bool get isDebitSettlement => settlementDirection == directionDebit;

  String get goatTypeLabel {
    switch (goatType) {
      case typeOwnPalai:
        return 'Own Palai';
      case typeAvailableStock:
        return 'Available Stock';
      case typeCustomerPalai:
      default:
        return 'Customer Palai';
    }
  }

  // ---------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------

  factory DeathRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    DateTime dateFrom(String key) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return DateTime.now();
    }

    double? doubleOrNull(String key) {
      final value = data[key];
      if (value is num) return value.toDouble();
      return null;
    }

    return DeathRecord(
      id: doc.id,
      goatType: (data['goatType'] ?? typeCustomerPalai).toString(),
      goatId: (data['goatId'] ?? '').toString(),
      goatLabel: (data['goatLabel'] ?? '').toString(),
      customerId: data['customerId'] as String?,
      customerName: data['customerName'] as String?,
      deathDate: dateFrom('deathDate'),
      reason: (data['reason'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      settlementAmount: (data['settlementAmount'] as num?)?.toDouble() ?? 0,
      settlementDirection: data['settlementDirection'] as String?,
      customerPendingBefore: doubleOrNull('customerPendingBefore'),
      customerPendingAfter: doubleOrNull('customerPendingAfter'),
      farmLossAmount: (data['farmLossAmount'] as num?)?.toDouble() ?? 0,
      createdAt: dateFrom('createdAt'),
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
    );
  }
}