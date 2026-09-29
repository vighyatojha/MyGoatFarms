import 'goat_model.dart';
import 'trading_purchase_model.dart';

/// One goat being pulled out of a Purchase Lot into an individual goat
/// record (Step 6 — transfers to Own Palai / Customer Palai).
///
/// Goats stay anonymous inside a lot. This is the moment they get an
/// identity, so it carries the same details Goat Registration collects.
class LotTransferGoat {
  final String breed;
  final int ageMonths;
  final double weight;
  final String color;
  final String healthStatus;

  /// One of [Goat.genderValues], or '' to let the transfer pick the
  /// gender from what is left of the lot's Male / Female split.
  final String gender;

  /// Centimetres. 0 = not recorded.
  final double height;
  final double length;
  final String notes;

  const LotTransferGoat({
    required this.breed,
    required this.ageMonths,
    required this.weight,
    required this.color,
    required this.healthStatus,
    this.gender = '',
    this.height = 0,
    this.length = 0,
    this.notes = '',
  });

  /// Returns the first problem with this goat's details, or null.
  /// Mirrors the checks GoatService.registerGoat() makes for one goat.
  String? validate() {
    if (breed.trim().isEmpty) return 'Breed is required.';
    if (ageMonths <= 0) return 'Age must be greater than zero months.';
    if (weight <= 0) return 'Weight must be greater than zero.';
    if (color.trim().isEmpty) return 'Color is required.';

    if (height < 0 || height > Goat.maxHeightCm) {
      return 'Height must be between 0 and '
          '${Goat.maxHeightCm.toStringAsFixed(0)} cm.';
    }

    if (length < 0 || length > Goat.maxLengthCm) {
      return 'Length must be between 0 and '
          '${Goat.maxLengthCm.toStringAsFixed(0)} cm.';
    }

    if (gender.isNotEmpty && !Goat.genderValues.contains(gender)) {
      return 'Gender must be one of ${Goat.genderValues}.';
    }

    return null;
  }
}

/// Result of [LotTransferPlanner.assignGenders].
class LotGenderPlan {
  /// Final gender for each goat, in the same order as the input. May be
  /// '' when the lot has no Male / Female split recorded.
  final List<String> genders;

  final int maleRegisteredAfter;
  final int femaleRegisteredAfter;

  const LotGenderPlan({
    required this.genders,
    required this.maleRegisteredAfter,
    required this.femaleRegisteredAfter,
  });
}

/// Pure helpers for lot transfers — no Firestore, so they can be unit
/// tested on their own.
class LotTransferPlanner {
  LotTransferPlanner._();

  /// Hard cap on goats per transfer: each goat is one document write in
  /// a single Firestore transaction, and a commit allows 500 writes.
  static const int maxGoatsPerTransfer = 200;

  /// Decides each goat's gender and the lot's new maleRegistered /
  /// femaleRegistered counters.
  ///
  /// Goats with an explicit gender keep it. The rest ("auto") are filled
  /// from whatever is left of the lot's split (maleGoats / femaleGoats
  /// minus what is already registered, minus the explicit picks made in
  /// this same transfer), keeping pace with the overall ratio — the same
  /// rule GoatService uses when it registers goats one at a time.
  ///
  /// When the lot has no split (0 / 0), auto goats get '' and the
  /// counters are left alone.
  static LotGenderPlan assignGenders(
      TradingPurchase lot,
      List<String> requested,
      ) {
    final male = Goat.genderValues[0];
    final female = Goat.genderValues[1];

    final hasSplit = lot.maleGoats > 0 || lot.femaleGoats > 0;

    var maleUsed = lot.maleRegistered;
    var femaleUsed = lot.femaleRegistered;

    if (!hasSplit) {
      return LotGenderPlan(
        genders: List<String>.from(requested),
        maleRegisteredAfter: maleUsed,
        femaleRegisteredAfter: femaleUsed,
      );
    }

    // Explicit picks use up quota first, so the auto goats are drawn
    // from what is genuinely left.
    for (final g in requested) {
      if (g == male) maleUsed++;
      if (g == female) femaleUsed++;
    }

    final result = <String>[];

    for (final g in requested) {
      if (g.isNotEmpty) {
        result.add(g);
        continue;
      }

      final remainingMale = lot.maleGoats - maleUsed;
      final remainingFemale = lot.femaleGoats - femaleUsed;

      String pick;

      if (remainingMale <= 0 && remainingFemale <= 0) {
        // Split is exhausted (e.g. explicit picks used it all up).
        pick = '';
      } else if (remainingMale <= 0) {
        pick = female;
      } else if (remainingFemale <= 0) {
        pick = male;
      } else {
        final maleShare = remainingMale / lot.maleGoats;
        final femaleShare = remainingFemale / lot.femaleGoats;
        pick = maleShare >= femaleShare ? male : female;
      }

      if (pick == male) maleUsed++;
      if (pick == female) femaleUsed++;

      result.add(pick);
    }

    return LotGenderPlan(
      genders: result,
      maleRegisteredAfter: maleUsed,
      femaleRegisteredAfter: femaleUsed,
    );
  }

  /// Why [count] goats cannot be transferred out of [lot] right now, or
  /// null when they can. Transfers only ever draw on goats that are
  /// physically at the farm and not reserved for a customer.
  static String? blockReason(TradingPurchase lot, int count) {
    if (!lot.isLot) {
      return '${lot.lotId} is an older purchase that has not been '
          'converted to a lot yet, so goats cannot be transferred from it.';
    }

    if (count <= 0) return 'Enter how many goats to transfer.';

    if (lot.farmAvailableQty <= 0) {
      return 'No goats are free at the farm in ${lot.lotId}. Goats still '
          'at the supplier must be received first, and reserved goats '
          'cannot be transferred.';
    }

    if (count > lot.farmAvailableQty) {
      return 'Only ${lot.farmAvailableQty} goat'
          '${lot.farmAvailableQty == 1 ? '' : 's'} '
          'in ${lot.lotId} ${lot.farmAvailableQty == 1 ? 'is' : 'are'} '
          'free at the farm.';
    }

    return null;
  }
}

/// What a lot transfer worked out during the transaction's READ phase,
/// so the WRITE phase (which may run after other reads in a larger
/// transaction, e.g. a Customer Palai sale) needs no further reads.
class LotTransferPrep {
  /// The lot as read inside the transaction (never a stale screen copy).
  final TradingPurchase lot;

  /// Goat ids reserved for this transfer, in input order (G-0041, ...).
  final List<String> goatIds;

  /// Value of the goat counter before this transfer. The write phase
  /// stores `counterLastValue + goatIds.length`.
  final int counterLastValue;

  final LotGenderPlan genderPlan;

  const LotTransferPrep({
    required this.lot,
    required this.goatIds,
    required this.counterLastValue,
    required this.genderPlan,
  });
}