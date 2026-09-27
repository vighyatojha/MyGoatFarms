import 'package:cloud_firestore/cloud_firestore.dart';

/// A single "Goat Death & Settlement" record, stored at
/// `farms/{farmId}/deathRecords/{id}`.
///
/// One farm-wide collection covers all three cases (Customer Palai, Own
/// Palai, Available Stock) so the Home Screen's "Goat Death & Settlement"
/// history is a single query. [goatType] tells the UI which shape of
/// record it is — Customer Palai records carry [goatPendingCharge] /
/// [customerAmountToPay] / customer fields, Own Palai and Available
/// Stock records carry only [farmLossAmount].
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
  //
  // The farm owner tells the system two numbers: what was pending for
  // this specific goat, and what the customer will actually be asked
  // to pay. Whatever gap is waived between the two becomes a farm
  // loss — see [farmLossAmount] below, which this case shares with
  // Own Palai / Available Stock.
  //
  //   goatPendingCharge = 5000, customerAmountToPay = 2000
  //     → farmLossAmount = 3000 (waived, recorded as a loss)
  //   goatPendingCharge = 5000, customerAmountToPay = 5000
  //     → farmLossAmount = 0 (paid in full, no loss)
  // ---------------------------------------------------------------------

  /// 0 for Own Palai / Available Stock. What was pending specifically
  /// for this one goat at the time of death (the farm owner enters
  /// this manually — the customer's combined `pendingAmount` covers
  /// every goat they have, not just this one).
  final double goatPendingCharge;

  /// 0 for Own Palai / Available Stock. What the customer is actually
  /// being asked to pay for this goat — may be less than
  /// [goatPendingCharge] (partial waiver), equal to it (paid in full,
  /// no loss), or more (an additional charge).
  final double customerAmountToPay;

  final double? customerPendingBefore;
  final double? customerPendingAfter;

  // ---------------------------------------------------------------------
  // FARM LOSS
  //
  // Shared by all three cases:
  // * Customer Palai — the amount waived (goatPendingCharge minus
  //   customerAmountToPay, floored at 0). 0 when the customer pays in
  //   full.
  // * Own Palai / Available Stock — the goat's recorded value (the
  //   farm owner enters this manually when recording the death; see
  //   RecordFarmGoatDeathScreen).
  //
  // Whenever this is > 0, DeathSettlementService also posts a "Goat
  // Death Loss" expense in Finance for the same amount — see
  // ExpenseModel.isUnpaidCredit for how it counts toward Net Income
  // despite being a non-cash loss.
  // ---------------------------------------------------------------------

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
    this.goatPendingCharge = 0,
    this.customerAmountToPay = 0,
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

  bool get isCustomerPalai => goatType == typeCustomerPalai;
  bool get isOwnPalai => goatType == typeOwnPalai;
  bool get isAvailableStock => goatType == typeAvailableStock;

  /// True when part (or all) of [goatPendingCharge] was waived —
  /// i.e. this record carries a farm loss.
  bool get hasFarmLoss => farmLossAmount > 0;

  /// True when the customer paid [goatPendingCharge] in full — no
  /// loss to the farm. Only meaningful when [isCustomerPalai].
  bool get paidInFull =>
      isCustomerPalai && goatPendingCharge > 0 && farmLossAmount <= 0;

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
      goatPendingCharge:
      (data['goatPendingCharge'] as num?)?.toDouble() ?? 0,
      customerAmountToPay:
      (data['customerAmountToPay'] as num?)?.toDouble() ?? 0,
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