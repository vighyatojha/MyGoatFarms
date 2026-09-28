import 'package:cloud_firestore/cloud_firestore.dart';

/// A single "Farm Loss" record, stored at
/// `farms/{farmId}/deathRecords/{id}`.
///
/// One farm-wide collection covers every kind of loss the farm can take:
///
/// * Customer Palai goat death — [typeCustomerPalai]
/// * Own Palai / Available Stock goat death — [typeOwnPalai] /
///   [typeAvailableStock]
/// * Any other manually-logged loss (fire, theft, disease, spoiled feed,
///   storm damage, etc.) — [typeManualLoss], distinguished further by
///   [category]
///
/// [goatType] tells the UI which shape of record it is — the goat-death
/// cases carry [goatPendingCharge] / [customerAmountToPay] / customer
/// fields; every case shares [farmLossAmount] as "the ₹ figure this
/// record cost the farm."
///
/// The collection is still named `deathRecords` for backward
/// compatibility with existing Firestore data and every screen that
/// already queries it — only the model and the UI treat it as the
/// broader "Losses" ledger now.
class DeathRecord {
  final String id;

  /// One of [typeCustomerPalai], [typeOwnPalai], [typeAvailableStock],
  /// [typeManualLoss].
  final String goatType;

  final String goatId;

  /// Denormalized display label for the goat (tag/goat code for Customer
  /// Palai, breed + short id for farm goats) so history lists never need
  /// a second read. For [typeManualLoss] this is unused — see [title]
  /// instead.
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
  // every other loss type.
  //
  //   goatPendingCharge = 5000, customerAmountToPay = 2000
  //     → farmLossAmount = 3000 (waived, recorded as a loss)
  //   goatPendingCharge = 5000, customerAmountToPay = 5000
  //     → farmLossAmount = 0 (paid in full, no loss)
  // ---------------------------------------------------------------------

  /// 0 outside Customer Palai. What was pending specifically for this
  /// one goat at the time of death (the farm owner enters this
  /// manually — the customer's combined `pendingAmount` covers every
  /// goat they have, not just this one).
  final double goatPendingCharge;

  /// 0 outside Customer Palai. What the customer is actually being
  /// asked to pay for this goat — may be less than [goatPendingCharge]
  /// (partial waiver), equal to it (paid in full, no loss), or more (an
  /// additional charge).
  final double customerAmountToPay;

  final double? customerPendingBefore;
  final double? customerPendingAfter;

  // ---------------------------------------------------------------------
  // MANUAL LOSS (typeManualLoss only)
  //
  // A free-form loss the farm owner logs directly — not tied to a
  // specific goat's death. [category] says what kind; [title] and
  // [description] are the owner's own words; [proofCount] counts optional
  // photos (receipt, damage photo, police complaint, vet report, etc.)
  // uploaded as supporting evidence — never required to save the
  // record. [isCashLoss] says whether real money left the farm (e.g.
  // repair costs after theft) as opposed to a pure value loss (e.g.
  // spoiled feed that was simply thrown away) — this decides which
  // FinancePaymentMethods gets posted alongside it.
  // ---------------------------------------------------------------------

  /// One of [categoryFire], [categoryTheft], [categoryDisease],
  /// [categoryFeedSpoilage], [categoryWeatherDamage], [categoryOther].
  /// Null outside [typeManualLoss].
  final String? category;

  /// Short owner-entered title for a manual loss (e.g. "Store room
  /// fire"). Empty outside [typeManualLoss].
  final String title;

  /// Longer free-text description for a manual loss. Doubles as
  /// [reason] for manual losses so existing UI that reads [reason]
  /// keeps working unchanged.
  final String description;

  /// How many optional proof photos (receipts, damage photos, reports)
  /// are attached. The photos themselves live in the
  /// `deathRecords/{id}/proofs` subcollection as Firestore `Blob`s —
  /// same no-Storage-bucket approach as the rest of the app (see
  /// ImageService) — so this record stays far below the 1 MiB
  /// document limit. 0 is normal; nothing requires a photo.
  final int proofCount;

  /// True when this loss involved real cash leaving the farm (repair,
  /// replacement purchase, etc.) rather than just lost value. Only
  /// meaningful for [typeManualLoss] — goat-death losses are always a
  /// non-cash value loss, same as before.
  final bool isCashLoss;

  // ---------------------------------------------------------------------
  // FARM LOSS
  //
  // Shared by every case — "how many rupees did this cost the farm":
  // * Customer Palai — the amount waived (goatPendingCharge minus
  //   customerAmountToPay, floored at 0). 0 when the customer pays in
  //   full.
  // * Own Palai / Available Stock — the goat's recorded value (entered
  //   manually when recording the death; see RecordFarmGoatDeathScreen).
  // * Manual loss — the amount the farm owner enters directly (see
  //   RecordFarmLossScreen).
  //
  // Whenever this is > 0, DeathSettlementService also posts a Finance
  // expense for the same amount — see ExpenseModel.isUnpaidCredit for
  // how a non-cash loss still counts toward Net Income.
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
    this.category,
    this.title = '',
    this.description = '',
    this.proofCount = 0,
    this.isCashLoss = false,
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
  static const String typeManualLoss = 'manualLoss';

  static const String categoryFire = 'fire';
  static const String categoryTheft = 'theft';
  static const String categoryDisease = 'disease';
  static const String categoryFeedSpoilage = 'feedSpoilage';
  static const String categoryWeatherDamage = 'weatherDamage';
  static const String categoryOther = 'other';

  static const List<String> manualLossCategories = [
    categoryFire,
    categoryTheft,
    categoryDisease,
    categoryFeedSpoilage,
    categoryWeatherDamage,
    categoryOther,
  ];

  bool get isCustomerPalai => goatType == typeCustomerPalai;
  bool get isOwnPalai => goatType == typeOwnPalai;
  bool get isAvailableStock => goatType == typeAvailableStock;
  bool get isManualLoss => goatType == typeManualLoss;

  /// True when part (or all) of [goatPendingCharge] was waived —
  /// i.e. this record carries a farm loss.
  bool get hasFarmLoss => farmLossAmount > 0;

  /// True when the customer paid [goatPendingCharge] in full — no
  /// loss to the farm. Only meaningful when [isCustomerPalai].
  bool get paidInFull =>
      isCustomerPalai && goatPendingCharge > 0 && farmLossAmount <= 0;

  /// True when at least one proof photo has been attached.
  bool get hasProof => proofCount > 0;

  /// Display label for whatever this record represents — the goat-type
  /// label for goat deaths, the loss category label for manual losses.
  /// Kept as `goatTypeLabel` so every existing call site (e.g.
  /// DeathHistoryScreen's chips) keeps working unchanged.
  String get goatTypeLabel {
    switch (goatType) {
      case typeOwnPalai:
        return 'Own Palai';
      case typeAvailableStock:
        return 'Available Stock';
      case typeManualLoss:
        return categoryLabelFor(category);
      case typeCustomerPalai:
      default:
        return 'Customer Palai';
    }
  }

  /// The label to show for a manual-loss card's title line — falls back
  /// to the category label if the owner left the title blank.
  String get displayTitle => title.trim().isNotEmpty
      ? title.trim()
      : categoryLabelFor(category);

  static String categoryLabelFor(String? category) {
    switch (category) {
      case categoryFire:
        return 'Fire';
      case categoryTheft:
        return 'Theft';
      case categoryDisease:
        return 'Disease';
      case categoryFeedSpoilage:
        return 'Feed Spoilage';
      case categoryWeatherDamage:
        return 'Weather Damage';
      case categoryOther:
        return 'Other';
      default:
        return 'Loss';
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
      category: data['category'] as String?,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      proofCount: (data['proofCount'] as num?)?.toInt() ?? 0,
      isCashLoss: data['isCashLoss'] == true,
      farmLossAmount: (data['farmLossAmount'] as num?)?.toDouble() ?? 0,
      createdAt: dateFrom('createdAt'),
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
    );
  }
}