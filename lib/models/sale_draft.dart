import 'dart:typed_data';

import '../models/goat_model.dart';
import '../services/sales_service.dart';
import 'expense_categories.dart';
import 'sale_model.dart';
import 'sale_settlement.dart';

/// Shared in-memory state for the Sell Goat wizard.
///
/// One SaleDraft instance is created when the wizard opens and is passed
/// through all wizard steps. Nothing is written to Firestore until the
/// sale is saved (Step 5's branch-specific save action).
class SaleDraft {
  // ---------------------------------------------------------------------------
  // NUMBER HELPERS
  // ---------------------------------------------------------------------------

  static double round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;

    final nudge = value >= 0 ? 1e-9 : -1e-9;

    return ((value + nudge) * 100).roundToDouble() / 100;
  }

  static double _nonNegative(double value) {
    final rounded = round2(value);

    return rounded <= 0 ? 0.0 : rounded;
  }

  static String formatWeight(double value) {
    final fixed = round2(value).toStringAsFixed(2);

    if (!fixed.contains('.')) return fixed;

    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  // ---------------------------------------------------------------------------
  // STEP 1 — SELECT GOAT(S)
  // ---------------------------------------------------------------------------

  List<Goat> selectedGoats = [];

  List<String> get goatIds =>
      selectedGoats.map((g) => g.id).toList();

  bool get isMultiGoat => saleGoatCount > 1;

  // ---------------------------------------------------------------------------
  // LOT SALE
  // ---------------------------------------------------------------------------

  String lotDocId = '';

  String lotDisplayId = '';

  int lotQuantity = 0;

  String sourceLocation = '';

  double lotSellingWeight = 0;

  bool get isLotSale => lotDocId.isNotEmpty;

  int get saleGoatCount => isLotSale ? lotQuantity : selectedGoats.length;

  // ---------------------------------------------------------------------------
  // STEP 2 — CUSTOMER MOBILE LOOKUP
  // ---------------------------------------------------------------------------

  String mobile = '';
  String customerName = '';
  String address = '';

  CustomerMatchSource? customerSource;

  String customerId = '';

  bool get isExistingCustomer => customerSource != null;

  bool get isExistingPalaiCustomer =>
      customerSource == CustomerMatchSource.palai;

  void applyMatch(CustomerMatch match) {
    customerSource = match.source;
    customerId = match.id;
    customerName = match.name;
    mobile = match.mobile;
    address = match.address;
  }

  void clearCustomerMatch() {
    customerSource = null;
    customerId = '';
  }

  // ---------------------------------------------------------------------------
  // STEP 3 — SELECTED GOAT DETAILS
  // ---------------------------------------------------------------------------

  final Map<String, double> _sellingWeights = {};

  double weightFor(Goat goat) => _sellingWeights[goat.id] ?? goat.weight;

  void setWeight(Goat goat, double weight) {
    _sellingWeights[goat.id] = weight;
  }

  String genderFor(Goat goat) => goat.gender;

  // Photo and approximate age, entered on Step 6 (Goat Photos — Deliver
  // Now, Booking / Holding, Wait for Delivery) so every goat sold has a
  // photo and an age on its booking and in the customer's purchase
  // history. Only CHANGED values are kept here; they are saved onto the
  // goat right before the sale is saved (see SellGoatWizardScreen).

  final Map<String, Uint8List> _newPhotos = {};
  final Map<String, String> _newPhotoTypes = {};
  final Map<String, int> _ageMonths = {};

  Uint8List? photoFor(Goat goat) => _newPhotos[goat.id] ?? goat.photo;

  bool hasPhoto(Goat goat) {
    final photo = photoFor(goat);
    return photo != null && photo.isNotEmpty;
  }

  void setPhoto(Goat goat, Uint8List bytes, String contentType) {
    _newPhotos[goat.id] = bytes;
    _newPhotoTypes[goat.id] = contentType;
  }

  int ageMonthsFor(Goat goat) => _ageMonths[goat.id] ?? goat.currentAgeMonths;

  void setAgeMonths(Goat goat, int months) {
    if (months == goat.currentAgeMonths) {
      _ageMonths.remove(goat.id);
    } else {
      _ageMonths[goat.id] = months;
    }
  }

  /// Photos picked on the Goat details step: goat id -> (bytes, content type).
  Map<String, (Uint8List, String)> get changedPhotos => {
    for (final e in _newPhotos.entries)
      e.key: (e.value, _newPhotoTypes[e.key] ?? 'image/jpeg'),
  };

  /// Ages changed on the Goat details step: goat id -> months.
  Map<String, int> get changedAges => Map.unmodifiable(_ageMonths);

  // ---------------------------------------------------------------------------
  // STEP 6 — GOAT PHOTOS (lot sale)
  // ---------------------------------------------------------------------------
  //
  // A lot sale has no registered goats, so the photo, approximate age and
  // weight of each goat handed over are kept here, one entry per goat, and
  // saved with the sale (SaleGoatDetailsService).

  final List<LotGoatDetail> lotGoatDetails = [];

  /// Makes [lotGoatDetails] hold exactly [lotQuantity] entries. New entries
  /// start with the average weight of the sale; entries already filled in
  /// are kept.
  void ensureLotGoatDetails() {
    final qty = lotQuantity < 0 ? 0 : lotQuantity;
    if (lotGoatDetails.length > qty) {
      lotGoatDetails.removeRange(qty, lotGoatDetails.length);
    }
    final average = qty > 0 ? round2(lotSellingWeight / qty) : 0.0;
    while (lotGoatDetails.length < qty) {
      lotGoatDetails.add(LotGoatDetail(weight: average));
    }
  }

  double get lotGoatDetailsWeight => round2(
    lotGoatDetails.fold(0.0, (sum, g) => sum + g.weight),
  );

  double get totalSellingWeight => isLotSale
      ? round2(lotSellingWeight)
      : round2(
    selectedGoats.fold(
      0.0,
          (sum, g) => sum + weightFor(g),
    ),
  );

  double get totalRecordedWeight => round2(
    selectedGoats.fold(
      0.0,
          (sum, g) => sum + g.weight,
    ),
  );

  // ---------------------------------------------------------------------------
  // STEP 4 — SALE DETAILS
  // ---------------------------------------------------------------------------

  String pricingMode = Sale.pricingModePerKg;

  bool get isFixedPrice => pricingMode == Sale.pricingModeFixed;

  double sellingPricePerKg = 0;

  double fixedSalePrice = 0;

  double get grossSaleAmount => isFixedPrice
      ? round2(fixedSalePrice)
      : round2(totalSellingWeight * sellingPricePerKg);

  /// Discount entered in Step 4 (Sale Details).
  double discount = 0;

  /// Extra discount given at delivery, entered in Step 5 on the
  /// Deliver Now branch only. It stacks on top of [discount] and, like
  /// it, comes off the goat amount only (never transport).
  double deliveryDiscount = 0;

  /// The Step 4 discount alone, capped at the goat amount. Step 4 uses
  /// this so it never shows a Step 5 delivery discount.
  double get saleDiscountApplied => SaleSettlement.fromAmount(
    goatAmount: grossSaleAmount,
    discount: discount,
  ).appliedDiscount;

  /// The delivery discount actually applied: only on Deliver Now, and
  /// never more than what is left of the goat amount after the Step 4
  /// discount.
  double get appliedDeliveryDiscount {
    if (!isDeliverNow || deliveryDiscount <= 0) return 0;

    final remaining = round2(grossSaleAmount - saleDiscountApplied);

    return remaining <= 0
        ? 0
        : round2(deliveryDiscount > remaining ? remaining : deliveryDiscount);
  }

  /// Goat amount after the Step 4 discount only (what Step 4 shows).
  double get saleAmountAfterSaleDiscount =>
      round2(grossSaleAmount - saleDiscountApplied);

  /// Total discount saved on the sale (Step 4 + delivery discount).
  double get appliedDiscount =>
      round2(saleDiscountApplied + appliedDeliveryDiscount);

  double get totalSaleAmount =>
      round2(grossSaleAmount - appliedDiscount);

  double get effectivePricePerKg {
    if (!isFixedPrice) return sellingPricePerKg;

    final weight = totalSellingWeight;

    return weight > 0 ? round2(fixedSalePrice / weight) : 0.0;
  }

  // ---------------------------------------------------------------------------
  // STEP 5 — DELIVERY OPTIONS
  // ---------------------------------------------------------------------------

  String deliveryType = '';

  bool get isDeliverNow =>
      deliveryType == Sale.deliveryTypeDeliverNow;

  bool get isBooking =>
      deliveryType == Sale.deliveryTypeBooking;

  bool get isWaitForDelivery =>
      deliveryType == Sale.deliveryTypeWaitForDelivery;

  bool get isPalaiTransfer =>
      deliveryType == Sale.deliveryTypePalai;

  /// Step 6 (Goat Photos — photo, approximate age and weight of each goat)
  /// is part of Deliver Now, Booking / Holding and Wait for Delivery.
  /// Transfer to Palai saves on Step 5.
  bool get needsGoatPhotos => isDeliverNow || isBooking || isWaitForDelivery;

  String paymentMethod = FinancePaymentMethods.cash;

  bool onCredit = false;

  // ---------------------------------------------------------------------------
  // EXCESS PAYMENT ACTION
  // ---------------------------------------------------------------------------
  //
  // Used when the customer has paid MORE than the final bill.
  //
  // Exactly one action must be selected:
  //
  //   carryToAdvance    -> put the extra money into customer advance
  //   refundToCustomer  -> return the extra money to the customer
  //
  // This remains null until the user explicitly chooses one.
  // The delivery/payment screen must require a selection whenever
  // extraReceived > 0.

  ExcessAction? excessAction;

  /// Clears the previous excess choice.
  ///
  /// This should be called whenever the received amount changes back to
  /// the normal/non-excess state or when changing sale branches.
  void clearExcessAction() {
    excessAction = null;
  }

  /// True when the user has selected either "Add to Advance" or
  /// "Return to Customer".
  bool get hasExcessActionSelected =>
      excessAction != null;

  // --- Branch A: Deliver Now -----------------------------------------------

  double transportCost = 0;

  double amountReceived = 0;

  double get customerTotalDeliverNow =>
      round2(totalSaleAmount + transportCost);

  double get remainingBalanceDeliverNow =>
      _nonNegative(customerTotalDeliverNow - amountReceived);

  double get extraReceivedDeliverNow =>
      _nonNegative(amountReceived - customerTotalDeliverNow);

  String get paymentStatusDeliverNow {
    final received = round2(amountReceived);

    if (received <= 0) return Sale.paymentStatusPending;
    if (received >= customerTotalDeliverNow) {
      return Sale.paymentStatusPaid;
    }

    return Sale.paymentStatusPartial;
  }

  // --- Branch B: Booking / Holding ----------------------------------------

  double bookingAmount = 0;

  double holdingChargePerDay = 0;

  double get remainingBalanceBooking =>
      _nonNegative(totalSaleAmount - bookingAmount);

  // --- Branch C: Wait for Delivery ----------------------------------------

  double get bookingPricePerKg => effectivePricePerKg;

  double get bookingWeightTotal => totalSellingWeight;

  double bookingAdvanceAmount = 0;

  double get customerTotalWaitForDelivery =>
      round2(totalSaleAmount);

  double get remainingAdvanceBalanceWaitForDelivery =>
      _nonNegative(
        customerTotalWaitForDelivery - bookingAdvanceAmount,
      );

  // --- Branch D: Transfer to Palai ----------------------------------------

  static const List<String> palaiPackages = [
    'Basic Palai',
    'Standard Palai',
    'Special Palai',
  ];

  DateTime? transferDate;

  String palaiPackage = '';

  double monthlyPalaiCharge = 0;

  double palaiAmountReceived = 0;

  double get customerTotalPalai =>
      round2(totalSaleAmount);

  double get remainingBalancePalai =>
      _nonNegative(
        customerTotalPalai - palaiAmountReceived,
      );

  double get extraReceivedPalai =>
      _nonNegative(
        palaiAmountReceived - customerTotalPalai,
      );

  String get paymentStatusPalai {
    final received = round2(palaiAmountReceived);

    if (received <= 0) return Sale.paymentStatusPending;

    if (received >= customerTotalPalai) {
      return Sale.paymentStatusPaid;
    }

    return Sale.paymentStatusPartial;
  }
}

/// Photo, approximate age and weight of one goat handed over on a Deliver
/// Now lot sale (Step 6).
class LotGoatDetail {
  Uint8List? photo;
  String photoContentType;
  int ageMonths;
  double weight;

  LotGoatDetail({
    this.photo,
    this.photoContentType = 'image/jpeg',
    this.ageMonths = 0,
    this.weight = 0,
  });

  bool get hasPhoto => photo != null && photo!.isNotEmpty;
}