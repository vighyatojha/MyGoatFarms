import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/billing_ledger.dart';
import '../utils/palai_proration.dart';

/// One goat's line in the goat-wise Palai breakdown of a [MonthlyBill].
///
/// This is a snapshot taken at the moment the bill was generated — the
/// amount is whatever the owner typed for that goat that month (it may
/// differ from the goat's registered [PalaiGoat.pricing] if the owner
/// overrode it), so it should never be recalculated later from the
/// goat's current price.
class GoatBillingLine {
  final String goatId;

  /// Display label for the goat (name, or its code/tag if unnamed).
  final String label;

  /// The Palai amount entered for this goat for this specific bill.
  final double palaiAmount;

  /// Pro-rating snapshot. All three are null for full-month lines and
  /// for bills saved before pro-rating existed, or when the owner typed
  /// their own amount instead of the calculated one.
  ///
  /// palaiAmount = monthlyRate ÷ daysInMonth × billableDays
  final int? billableDays;
  final int? daysInMonth;
  final double? monthlyRate;

  /// Statement bills only: the exact days charged for this goat in the
  /// month (both inclusive). Null on older bills.
  final DateTime? fromDate;
  final DateTime? toDate;

  const GoatBillingLine({
    required this.goatId,
    required this.label,
    required this.palaiAmount,
    this.billableDays,
    this.daysInMonth,
    this.monthlyRate,
    this.fromDate,
    this.toDate,
  });

  /// Line for a statement bill, built from the engine's calculated charge.
  /// Always carries the day count, so the bill/PDF can show
  /// "20 of 30 days" for partial months.
  factory GoatBillingLine.fromCharge(GoatChargeLine charge) {
    return GoatBillingLine(
      goatId: charge.goatId,
      label: charge.label,
      palaiAmount: charge.amount,
      billableDays: charge.days,
      daysInMonth: charge.daysInMonth,
      monthlyRate: charge.monthlyRate,
      fromDate: charge.fromDate,
      toDate: charge.toDate,
    );
  }

  /// Builds a line from the amount the owner ended up with.
  ///
  /// The day-count is only attached when [amount] still equals the
  /// calculated pro-rated amount. If the owner overrode the amount by
  /// hand, the line is saved as a plain amount so a bill/PDF never claims
  /// "20 of 30 days" for a number that was not calculated that way.
  factory GoatBillingLine.forGoat({
    required String goatId,
    required String label,
    required double amount,
    required PalaiProration proration,
  }) {
    final matches = (amount - proration.amount).abs() < 0.01;
    return GoatBillingLine(
      goatId: goatId,
      label: label,
      palaiAmount: amount,
      billableDays: matches && proration.isPartialMonth
          ? proration.billableDays
          : null,
      daysInMonth: matches && proration.isPartialMonth
          ? proration.daysInMonth
          : null,
      monthlyRate:
      matches && proration.isPartialMonth ? proration.monthlyCharge : null,
    );
  }

  /// True when this goat was billed for only part of the month.
  bool get isPartialMonth =>
      billableDays != null &&
          daysInMonth != null &&
          billableDays! < daysInMonth!;

  /// Label for bills/PDFs, e.g. "Bruno (20 of 30 days)".
  String get displayLabel =>
      isPartialMonth ? '$label ($billableDays of $daysInMonth days)' : label;

  factory GoatBillingLine.fromMap(Map<String, dynamic> map) {
    DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : null;
    return GoatBillingLine(
      goatId: map['goatId']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      palaiAmount: (map['palaiAmount'] as num?)?.toDouble() ?? 0,
      billableDays: (map['billableDays'] as num?)?.toInt(),
      daysInMonth: (map['daysInMonth'] as num?)?.toInt(),
      monthlyRate: (map['monthlyRate'] as num?)?.toDouble(),
      fromDate: date(map['fromDate']),
      toDate: date(map['toDate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'goatId': goatId,
      'label': label,
      'palaiAmount': palaiAmount,
      if (billableDays != null) 'billableDays': billableDays,
      if (daysInMonth != null) 'daysInMonth': daysInMonth,
      if (monthlyRate != null) 'monthlyRate': monthlyRate,
      if (fromDate != null) 'fromDate': Timestamp.fromDate(fromDate!),
      if (toDate != null) 'toDate': Timestamp.fromDate(toDate!),
    };
  }
}

/// Payment status of a monthly customer bill.
///
/// The UI may show:
/// - Unpaid
/// - Partially Paid
/// - Paid
///
/// The database stores the lowercase values defined here.
enum MonthlyBillStatus {
  unpaid,
  partial,
  paid,
}

/// A monthly bill generated for a Palai customer.
///
/// IMPORTANT:
/// This is different from the Final Bill generated during goat checkout.
///
/// Monthly Bill:
///   Customer-level recurring billing.
///
/// Final Bill:
///   Final financial settlement when a goat/goats are checked out.
///
/// A monthly bill is a snapshot. Once generated, the amounts used to
/// calculate that bill should not silently change because the customer's
/// current outstanding balance changes later.
class MonthlyBill {
  final String id;

  final String customerId;
  final String customerName;

  /// Human-readable bill number.
  ///
  /// Example:
  /// MB-2026-08-0001
  final String billNumber;

  /// First day of the billing month.
  ///
  /// Example:
  /// 2026-08-01
  final DateTime billingMonth;

  /// Last day of the billing month.
  final DateTime periodEnd;

  /// Number of active/boarded goats used when the bill was generated.
  final int goatCount;

  /// Monthly Palai charges before other adjustments.
  final double palaiCharges;

  /// Additional charges included in this monthly bill.
  final double otherCharges;

  /// Discount applied to this monthly bill.
  final double discount;

  /// Amount already outstanding before this bill was generated.
  ///
  /// This is a snapshot and should never be recalculated later.
  final double previousOutstanding;

  /// Net amount generated by this month's bill.
  ///
  /// Formula:
  ///
  /// palaiCharges + otherCharges - discount
  final double currentBillAmount;

  /// Amount of the customer's existing advance balance that was used to
  /// offset this bill, if any.
  ///
  /// This is a snapshot taken when the bill was generated and should never
  /// be recalculated later.
  final double advanceApplied;

  /// Total amount due after adding this bill to the previous outstanding
  /// and subtracting any advance that was applied.
  ///
  /// Formula:
  ///
  /// previousOutstanding + currentBillAmount - advanceApplied
  final double totalDue;

  /// Amount paid against THIS monthly bill.
  ///
  /// This may be less than [currentBillAmount] if the customer makes a
  /// partial payment.
  final double amountPaid;

  /// Amount still outstanding from this bill.
  final double remainingAmount;

  final MonthlyBillStatus status;

  final DateTime generatedAt;

  /// Set when the bill becomes completely paid.
  final DateTime? paidAt;

  /// Optional notes attached to this bill.
  final String notes;

  /// Optional snapshot of the farm name shown on the PDF.
  final String farmName;

  /// Optional snapshot of the farm address shown on the PDF.
  final String farmAddress;

  /// Optional snapshot of the farm phone shown on the PDF.
  final String farmPhone;

  /// Optional snapshot of the farm email shown on the PDF.
  final String farmEmail;

  /// Goat-wise Palai breakdown for this bill (one line per goat included
  /// in the current-month calculation). Empty for older bills generated
  /// before this breakdown existed, or for bills that don't have a
  /// goat-wise split (e.g. a purely manual outstanding entry).
  ///
  /// This is a snapshot — like every other amount on a MonthlyBill, it
  /// should never be recalculated from a goat's current price.
  final List<GoatBillingLine> goatBreakdown;

  // ================================================================
  // STATEMENT BILLING (billingModel == 'statementV2')
  //
  // A statement bill shows the CUSTOMER-FACING totals in the fields
  // above: totalDue == totalPayable, amountPaid / remainingAmount /
  // status track payments received against this statement while it is
  // the latest one.
  //
  // The own* fields below track only THIS MONTH's charge, which is what
  // oldest-first payments clear. Older bills (no billingModel) used
  // amountPaid / remainingAmount for the month's own charge, so the
  // effective* getters fall back to those.
  // ================================================================

  /// 'statementV2' for bills made by the statement engine, '' otherwise.
  final String billingModel;

  /// previousOutstanding + currentBillAmount − advanceApplied.
  final double totalPayable;

  final double? ownCharges;
  final double? ownPaid;
  final double? ownRemaining;
  final String? ownStatus;

  /// Previous Outstanding split by month, oldest first.
  final List<BreakdownLine> previousBreakdown;

  /// Part of previousOutstanding not tied to a monthly bill.
  final double earlierBalance;

  /// Which months the advance applied on this statement paid off.
  final List<BreakdownLine> advanceAllocations;

  /// True once a later statement exists. A locked bill is history.
  final bool locked;

  /// The unpaid statement balance was carried into a later statement.
  final bool carriedForward;
  final String? carriedForwardToBillId;

  final bool isVoid;

  const MonthlyBill({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.billNumber,
    required this.billingMonth,
    required this.periodEnd,
    required this.goatCount,
    required this.palaiCharges,
    required this.otherCharges,
    required this.discount,
    required this.previousOutstanding,
    required this.currentBillAmount,
    this.advanceApplied = 0,
    required this.totalDue,
    required this.amountPaid,
    required this.remainingAmount,
    required this.status,
    required this.generatedAt,
    this.paidAt,
    this.notes = '',
    this.farmName = '',
    this.farmAddress = '',
    this.farmPhone = '',
    this.farmEmail = '',
    this.goatBreakdown = const [],
    this.billingModel = '',
    double? totalPayable,
    this.ownCharges,
    this.ownPaid,
    this.ownRemaining,
    this.ownStatus,
    this.previousBreakdown = const [],
    this.earlierBalance = 0,
    this.advanceAllocations = const [],
    this.locked = false,
    this.carriedForward = false,
    this.carriedForwardToBillId,
    this.isVoid = false,
  }) : totalPayable = totalPayable ?? totalDue;

  static const String statementModel = 'statementV2';

  bool get isStatement => billingModel == statementModel;

  /// This month's own charge.
  double get effectiveOwnCharges => ownCharges ?? currentBillAmount;

  /// Paid against this month's own charge.
  double get effectiveOwnPaid => ownPaid ?? amountPaid;

  /// Still unpaid from this month's own charge.
  double get effectiveOwnRemaining => ownRemaining ?? remainingAmount;

  /// Status of this month's own charge: 'paid' / 'partial' / 'unpaid'.
  String get effectiveOwnStatus =>
      ownStatus ??
          paymentStatusFor(
            paid: effectiveOwnPaid,
            remaining: effectiveOwnRemaining,
          );

  // ================================================================
  // STATUS HELPERS
  // ================================================================

  static MonthlyBillStatus statusFromString(String? value) {
    switch (value) {
      case 'paid':
        return MonthlyBillStatus.paid;

      case 'partial':
      case 'partiallyPaid':
      case 'partially_paid':
        return MonthlyBillStatus.partial;

      case 'unpaid':
      default:
        return MonthlyBillStatus.unpaid;
    }
  }

  static String statusToString(MonthlyBillStatus status) {
    switch (status) {
      case MonthlyBillStatus.paid:
        return 'paid';

      case MonthlyBillStatus.partial:
        return 'partial';

      case MonthlyBillStatus.unpaid:
        return 'unpaid';
    }
  }

  String get statusLabel {
    switch (status) {
      case MonthlyBillStatus.paid:
        return 'PAID';

      case MonthlyBillStatus.partial:
        return 'PARTIALLY PAID';

      case MonthlyBillStatus.unpaid:
        return 'UNPAID';
    }
  }

  bool get isPaid => status == MonthlyBillStatus.paid;

  bool get isPartiallyPaid => status == MonthlyBillStatus.partial;

  bool get isUnpaid => status == MonthlyBillStatus.unpaid;

  // ================================================================
  // MONTH HELPERS
  // ================================================================

  int get month => billingMonth.month;

  int get year => billingMonth.year;

  String get monthYear {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[billingMonth.month - 1]} ${billingMonth.year}';
  }

  /// Stable identifier used to prevent duplicate bills for the same
  /// customer/month/year.
  String get billingPeriodKey {
    final monthString = billingMonth.month.toString().padLeft(2, '0');

    return '${billingMonth.year}-$monthString';
  }

  /// Customer + billing period is the logical unique key.
  String get uniqueBillKey => '$customerId-$billingPeriodKey';

  // ================================================================
  // FIRESTORE
  // ================================================================

  factory MonthlyBill.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    final billingMonthValue = data['billingMonth'];
    final periodEndValue = data['periodEnd'];
    final generatedAtValue = data['generatedAt'];
    final paidAtValue = data['paidAt'];

    DateTime parseDate(
        dynamic value, {
          required DateTime fallback,
        }) {
      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return fallback;
    }

    return MonthlyBill(
      id: doc.id,

      customerId:
      data['customerId']?.toString() ?? '',

      customerName:
      data['customerName']?.toString() ?? '',

      billNumber:
      data['billNumber']?.toString() ?? doc.id,

      billingMonth: parseDate(
        billingMonthValue,
        fallback: DateTime.now(),
      ),

      periodEnd: parseDate(
        periodEndValue,
        fallback: DateTime.now(),
      ),

      goatCount:
      (data['goatCount'] as num?)?.toInt() ?? 0,

      palaiCharges:
      (data['palaiCharges'] as num?)?.toDouble() ?? 0,

      otherCharges:
      (data['otherCharges'] as num?)?.toDouble() ?? 0,

      discount:
      (data['discount'] as num?)?.toDouble() ?? 0,

      previousOutstanding:
      (data['previousOutstanding'] as num?)?.toDouble() ?? 0,

      currentBillAmount:
      (data['currentBillAmount'] as num?)?.toDouble() ?? 0,

      advanceApplied:
      (data['advanceApplied'] as num?)?.toDouble() ?? 0,

      totalDue:
      (data['totalDue'] as num?)?.toDouble() ?? 0,

      amountPaid:
      (data['amountPaid'] as num?)?.toDouble() ?? 0,

      remainingAmount:
      (data['remainingAmount'] as num?)?.toDouble() ?? 0,

      status: statusFromString(
        data['status']?.toString(),
      ),

      generatedAt: parseDate(
        generatedAtValue,
        fallback: DateTime.now(),
      ),

      paidAt: paidAtValue == null
          ? null
          : parseDate(
        paidAtValue,
        fallback: DateTime.now(),
      ),

      notes:
      data['notes']?.toString() ?? '',

      farmName:
      data['farmName']?.toString() ?? '',

      farmAddress:
      data['farmAddress']?.toString() ?? '',

      farmPhone:
      data['farmPhone']?.toString() ?? '',

      farmEmail:
      data['farmEmail']?.toString() ?? '',

      goatBreakdown: (data['goatBreakdown'] as List<dynamic>?)
          ?.map((e) => GoatBillingLine.fromMap(
        Map<String, dynamic>.from(e as Map),
      ))
          .toList() ??
          const [],

      billingModel:
      data['billingModel']?.toString() ?? '',

      totalPayable:
      (data['totalPayable'] as num?)?.toDouble(),

      ownCharges:
      (data['ownCharges'] as num?)?.toDouble(),

      ownPaid:
      (data['ownPaid'] as num?)?.toDouble(),

      ownRemaining:
      (data['ownRemaining'] as num?)?.toDouble(),

      ownStatus:
      data['ownStatus']?.toString(),

      previousBreakdown: _lines(data['previousBreakdown']),

      earlierBalance:
      (data['earlierBalance'] as num?)?.toDouble() ?? 0,

      advanceAllocations: _lines(data['advanceAllocations']),

      locked: data['locked'] == true,

      carriedForward: data['carriedForward'] == true,

      carriedForwardToBillId:
      data['carriedForwardToBillId']?.toString(),

      isVoid: data['isVoid'] == true ||
          data['status']?.toString() == 'void',
    );
  }

  static List<BreakdownLine> _lines(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => BreakdownLine.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,

      'billNumber': billNumber,

      'billingMonth':
      Timestamp.fromDate(billingMonth),

      'periodEnd':
      Timestamp.fromDate(periodEnd),

      'billingPeriodKey':
      billingPeriodKey,

      'goatCount': goatCount,

      'palaiCharges': palaiCharges,
      'otherCharges': otherCharges,
      'discount': discount,

      'previousOutstanding':
      previousOutstanding,

      'currentBillAmount':
      currentBillAmount,

      'advanceApplied':
      advanceApplied,

      'totalDue':
      totalDue,

      'amountPaid':
      amountPaid,

      'remainingAmount':
      remainingAmount,

      'status':
      statusToString(status),

      'generatedAt':
      Timestamp.fromDate(generatedAt),

      'paidAt': paidAt == null
          ? null
          : Timestamp.fromDate(paidAt!),

      'notes': notes,

      // ------------------------------------------------------------
      // Farm snapshot for historical PDFs.
      // ------------------------------------------------------------

      'farmName': farmName,
      'farmAddress': farmAddress,
      'farmPhone': farmPhone,
      'farmEmail': farmEmail,

      'goatBreakdown': goatBreakdown.map((g) => g.toMap()).toList(),

      if (billingModel.isNotEmpty) 'billingModel': billingModel,
      if (isStatement) 'totalPayable': totalPayable,
      if (ownCharges != null) 'ownCharges': ownCharges,
      if (ownPaid != null) 'ownPaid': ownPaid,
      if (ownRemaining != null) 'ownRemaining': ownRemaining,
      if (ownStatus != null) 'ownStatus': ownStatus,
      if (isStatement)
        'previousBreakdown':
        previousBreakdown.map((l) => l.toMap()).toList(),
      if (isStatement) 'earlierBalance': earlierBalance,
      if (isStatement)
        'advanceAllocations':
        advanceAllocations.map((l) => l.toMap()).toList(),
      if (isStatement) 'locked': locked,
    };
  }

  // ================================================================
  // COPY
  // ================================================================

  MonthlyBill copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? billNumber,
    DateTime? billingMonth,
    DateTime? periodEnd,
    int? goatCount,
    double? palaiCharges,
    double? otherCharges,
    double? discount,
    double? previousOutstanding,
    double? currentBillAmount,
    double? advanceApplied,
    double? totalDue,
    double? amountPaid,
    double? remainingAmount,
    MonthlyBillStatus? status,
    DateTime? generatedAt,
    DateTime? paidAt,
    String? notes,
    String? farmName,
    String? farmAddress,
    String? farmPhone,
    String? farmEmail,
    List<GoatBillingLine>? goatBreakdown,
  }) {
    return MonthlyBill(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      billNumber: billNumber ?? this.billNumber,
      billingMonth: billingMonth ?? this.billingMonth,
      periodEnd: periodEnd ?? this.periodEnd,
      goatCount: goatCount ?? this.goatCount,
      palaiCharges: palaiCharges ?? this.palaiCharges,
      otherCharges: otherCharges ?? this.otherCharges,
      discount: discount ?? this.discount,
      previousOutstanding:
      previousOutstanding ?? this.previousOutstanding,
      currentBillAmount:
      currentBillAmount ?? this.currentBillAmount,
      advanceApplied: advanceApplied ?? this.advanceApplied,
      totalDue: totalDue ?? this.totalDue,
      amountPaid: amountPaid ?? this.amountPaid,
      remainingAmount:
      remainingAmount ?? this.remainingAmount,
      status: status ?? this.status,
      generatedAt: generatedAt ?? this.generatedAt,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
      farmName: farmName ?? this.farmName,
      farmAddress: farmAddress ?? this.farmAddress,
      farmPhone: farmPhone ?? this.farmPhone,
      farmEmail: farmEmail ?? this.farmEmail,
      goatBreakdown: goatBreakdown ?? this.goatBreakdown,
      billingModel: billingModel,
      totalPayable: (totalDue != null && !isStatement)
          ? totalDue
          : this.totalPayable,
      ownCharges: ownCharges,
      ownPaid: ownPaid,
      ownRemaining: ownRemaining,
      ownStatus: ownStatus,
      previousBreakdown: previousBreakdown,
      earlierBalance: earlierBalance,
      advanceAllocations: advanceAllocations,
      locked: locked,
      carriedForward: carriedForward,
      carriedForwardToBillId: carriedForwardToBillId,
      isVoid: isVoid,
    );
  }

  @override
  String toString() {
    return 'MonthlyBill('
        'id: $id, '
        'customer: $customerName, '
        'period: $monthYear, '
        'amount: $currentBillAmount, '
        'paid: $amountPaid, '
        'remaining: $remainingAmount, '
        'status: ${statusToString(status)}'
        ')';
  }
}