import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// PALAI BILL
/// ============================================================================
///
/// Represents one billing period for a Customer Palai customer.
///
/// IMPORTANT:
///
/// A bill is NOT a payment.
///
/// Bill:
///     "How much does the customer owe for this billing period?"
///
/// Payment:
///     "How much did the customer actually pay?"
///
/// Keeping these two things separate gives us a reliable accounting structure.
///
/// Example:
///
/// January Bill
///     Palai Charges       ₹8,000
///     Extra Charges       ₹1,000
///     Discount              ₹500
///     ---------------------------
///     Total               ₹8,500
///
/// Payments:
///     01 Jan              ₹5,000
///     15 Jan              ₹2,000
///
/// Outstanding:           ₹1,500
///
/// The payment records will be handled separately by PalaiPayment.
///
/// ============================================================================

enum PalaiBillStatus {
  draft,
  issued,
  partiallyPaid,
  paid,
  overdue,
  cancelled,
}

class PalaiBill {
  // ==========================================================================
  // IDENTITY
  // ==========================================================================

  final String id;

  /// Customer who owns this bill.
  final String customerId;

  /// Optional reference to a specific goat.
  ///
  /// Usually monthly Customer Palai billing may contain multiple goats, so
  /// this can remain empty for customer-level bills.
  final String goatId;

  // ==========================================================================
  // BILLING PERIOD
  // ==========================================================================

  /// First day of the billing period.
  final DateTime billingStartDate;

  /// Last day of the billing period.
  final DateTime billingEndDate;

  /// Calendar year.
  final int year;

  /// Calendar month.
  ///
  /// 1 = January
  /// 12 = December
  final int month;

  // ==========================================================================
  // BILL INFORMATION
  // ==========================================================================

  /// Human-readable bill number.
  ///
  /// Example:
  /// PGF-2026-01-0001
  final String billNumber;

  /// Date on which the bill was generated.
  final DateTime billDate;

  /// Date by which payment is expected.
  final DateTime? dueDate;

  // ==========================================================================
  // CHARGES
  // ==========================================================================

  /// Main Palai/boarding charge.
  final double palaiAmount;

  /// Additional service charges.
  ///
  /// This can later cover things such as:
  ///
  /// - Medicine
  /// - Special treatment
  /// - Extra care
  /// - Other services
  final double additionalCharges;

  /// Manual miscellaneous charge.
  final double miscellaneousCharges;

  /// Discount applied to the bill.
  final double discount;

  // ==========================================================================
  // TOTALS
  // ==========================================================================

  /// Total amount before discount.
  final double subtotal;

  /// Final amount customer is required to pay.
  final double totalAmount;

  /// Amount already received against this bill.
  ///
  /// This is a cached summary.
  ///
  /// The source of truth for individual payments remains PalaiPayment.
  final double amountPaid;

  /// Remaining amount.
  final double pendingAmount;

  // ==========================================================================
  // STATUS
  // ==========================================================================

  final PalaiBillStatus status;

  // ==========================================================================
  // DESCRIPTION / NOTES
  // ==========================================================================

  final String description;

  final String notes;

  // ==========================================================================
  // AUDIT
  // ==========================================================================

  final String createdBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const PalaiBill({
    required this.id,
    required this.customerId,
    this.goatId = '',
    required this.billingStartDate,
    required this.billingEndDate,
    required this.year,
    required this.month,
    required this.billNumber,
    required this.billDate,
    this.dueDate,
    this.palaiAmount = 0,
    this.additionalCharges = 0,
    this.miscellaneousCharges = 0,
    this.discount = 0,
    required this.subtotal,
    required this.totalAmount,
    this.amountPaid = 0,
    this.pendingAmount = 0,
    this.status = PalaiBillStatus.draft,
    this.description = '',
    this.notes = '',
    this.createdBy = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // CREATE NEW BILL
  // ==========================================================================

  factory PalaiBill.create({
    required String id,
    required String customerId,
    String goatId = '',
    required DateTime billingStartDate,
    required DateTime billingEndDate,
    required String billNumber,
    required DateTime billDate,
    DateTime? dueDate,
    double palaiAmount = 0,
    double additionalCharges = 0,
    double miscellaneousCharges = 0,
    double discount = 0,
    double amountPaid = 0,
    PalaiBillStatus status = PalaiBillStatus.draft,
    String description = '',
    String notes = '',
    String createdBy = '',
  }) {
    final now = DateTime.now();

    final subtotal =
        palaiAmount +
            additionalCharges +
            miscellaneousCharges;

    final totalAmount =
    _safeAmount(subtotal - discount);

    final safePaid =
    _safeAmount(amountPaid);

    final pendingAmount =
    _safeAmount(totalAmount - safePaid);

    return PalaiBill(
      id: id,
      customerId: customerId,
      goatId: goatId,
      billingStartDate: billingStartDate,
      billingEndDate: billingEndDate,
      year: billingStartDate.year,
      month: billingStartDate.month,
      billNumber: billNumber,
      billDate: billDate,
      dueDate: dueDate,
      palaiAmount: _safeAmount(palaiAmount),
      additionalCharges:
      _safeAmount(additionalCharges),
      miscellaneousCharges:
      _safeAmount(miscellaneousCharges),
      discount: _safeAmount(discount),
      subtotal: subtotal,
      totalAmount: totalAmount,
      amountPaid: safePaid,
      pendingAmount: pendingAmount,
      status: status,
      description: description,
      notes: notes,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  PalaiBill copyWith({
    String? id,
    String? customerId,
    String? goatId,
    DateTime? billingStartDate,
    DateTime? billingEndDate,
    int? year,
    int? month,
    String? billNumber,
    DateTime? billDate,
    DateTime? dueDate,
    bool clearDueDate = false,
    double? palaiAmount,
    double? additionalCharges,
    double? miscellaneousCharges,
    double? discount,
    double? subtotal,
    double? totalAmount,
    double? amountPaid,
    double? pendingAmount,
    PalaiBillStatus? status,
    String? description,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PalaiBill(
      id: id ?? this.id,
      customerId:
      customerId ?? this.customerId,
      goatId: goatId ?? this.goatId,
      billingStartDate:
      billingStartDate ??
          this.billingStartDate,
      billingEndDate:
      billingEndDate ??
          this.billingEndDate,
      year: year ?? this.year,
      month: month ?? this.month,
      billNumber:
      billNumber ?? this.billNumber,
      billDate:
      billDate ?? this.billDate,

      dueDate:
      clearDueDate
          ? null
          : (dueDate ?? this.dueDate),

      palaiAmount:
      palaiAmount ?? this.palaiAmount,

      additionalCharges:
      additionalCharges ??
          this.additionalCharges,

      miscellaneousCharges:
      miscellaneousCharges ??
          this.miscellaneousCharges,

      discount:
      discount ?? this.discount,

      subtotal:
      subtotal ?? this.subtotal,

      totalAmount:
      totalAmount ?? this.totalAmount,

      amountPaid:
      amountPaid ?? this.amountPaid,

      pendingAmount:
      pendingAmount ?? this.pendingAmount,

      status:
      status ?? this.status,

      description:
      description ?? this.description,

      notes:
      notes ?? this.notes,

      createdBy:
      createdBy ?? this.createdBy,

      createdAt:
      createdAt ?? this.createdAt,

      updatedAt:
      updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory PalaiBill.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data =
        doc.data() ?? <String, dynamic>{};

    final startDate = _dateValue(
      data['billingStartDate'] ??
          data['startDate'],
    );

    final subtotal = _doubleValue(
      data['subtotal'],
      fallback:
      _doubleValue(
        data['palaiAmount'],
      ) +
          _doubleValue(
            data['additionalCharges'],
          ) +
          _doubleValue(
            data['miscellaneousCharges'],
          ),
    );

    final totalAmount = _doubleValue(
      data['totalAmount'],
      fallback:
      _safeAmount(
        subtotal -
            _doubleValue(
              data['discount'],
            ),
      ),
    );

    final amountPaid =
    _doubleValue(
      data['amountPaid'],
    );

    final pendingAmount =
    _doubleValue(
      data['pendingAmount'],
      fallback:
      _safeAmount(
        totalAmount -
            amountPaid,
      ),
    );

    return PalaiBill(
      id: doc.id,

      customerId:
      _stringValue(
        data['customerId'],
      ),

      goatId:
      _stringValue(
        data['goatId'],
      ),

      billingStartDate:
      startDate,

      billingEndDate:
      _dateValue(
        data['billingEndDate'] ??
            data['endDate'] ??
            startDate,
      ),

      year:
      _intValue(
        data['year'],
        fallback:
        startDate.year,
      ),

      month:
      _intValue(
        data['month'],
        fallback:
        startDate.month,
      ),

      billNumber:
      _stringValue(
        data['billNumber'],
      ),

      billDate:
      _dateValue(
        data['billDate'],
        fallback:
        startDate,
      ),

      dueDate:
      _nullableDateValue(
        data['dueDate'],
      ),

      palaiAmount:
      _doubleValue(
        data['palaiAmount'],
      ),

      additionalCharges:
      _doubleValue(
        data['additionalCharges'],
      ),

      miscellaneousCharges:
      _doubleValue(
        data['miscellaneousCharges'],
      ),

      discount:
      _doubleValue(
        data['discount'],
      ),

      subtotal:
      subtotal,

      totalAmount:
      totalAmount,

      amountPaid:
      amountPaid,

      pendingAmount:
      pendingAmount,

      status:
      _statusValue(
        data['status'],
      ),

      description:
      _stringValue(
        data['description'],
      ),

      notes:
      _stringValue(
        data['notes'],
      ),

      createdBy:
      _stringValue(
        data['createdBy'],
      ),

      createdAt:
      _dateValue(
        data['createdAt'],
      ),

      updatedAt:
      _dateValue(
        data['updatedAt'],
      ),
    );
  }

  // ==========================================================================
  // MODEL -> FIRESTORE
  // ==========================================================================

  Map<String, dynamic> toMap({
    bool useServerTimestamps = false,
  }) {
    return {
      'customerId': customerId,

      'goatId': goatId,

      'billingStartDate':
      Timestamp.fromDate(
        billingStartDate,
      ),

      'billingEndDate':
      Timestamp.fromDate(
        billingEndDate,
      ),

      'year': year,

      'month': month,

      'billNumber': billNumber,

      'billDate':
      Timestamp.fromDate(
        billDate,
      ),

      'dueDate':
      dueDate == null
          ? null
          : Timestamp.fromDate(
        dueDate!,
      ),

      'palaiAmount':
      palaiAmount,

      'additionalCharges':
      additionalCharges,

      'miscellaneousCharges':
      miscellaneousCharges,

      'discount':
      discount,

      'subtotal':
      subtotal,

      'totalAmount':
      totalAmount,

      'amountPaid':
      amountPaid,

      'pendingAmount':
      pendingAmount,

      'status':
      status.name,

      'description':
      description,

      'notes':
      notes,

      'createdBy':
      createdBy,

      if (useServerTimestamps)
        'createdAt':
        FieldValue.serverTimestamp()
      else
        'createdAt':
        Timestamp.fromDate(
          createdAt,
        ),

      if (useServerTimestamps)
        'updatedAt':
        FieldValue.serverTimestamp()
      else
        'updatedAt':
        Timestamp.fromDate(
          updatedAt,
        ),
    };
  }

  // ==========================================================================
  // PAYMENT SUMMARY
  // ==========================================================================

  /// Returns a new bill after applying a payment.
  ///
  /// The actual payment should be stored separately in PalaiPayment.
  ///
  /// This method only updates the bill's cached payment summary.
  PalaiBill applyPayment(
      double paymentAmount,
      ) {
    if (paymentAmount <= 0) {
      return this;
    }

    final newAmountPaid =
    _safeAmount(
      amountPaid +
          paymentAmount,
    );

    final cappedPaid =
    newAmountPaid > totalAmount
        ? totalAmount
        : newAmountPaid;

    final newPending =
    _safeAmount(
      totalAmount -
          cappedPaid,
    );

    final newStatus =
    newPending <= 0
        ? PalaiBillStatus.paid
        : PalaiBillStatus.partiallyPaid;

    return copyWith(
      amountPaid: cappedPaid,
      pendingAmount: newPending,
      status: newStatus,
      updatedAt: DateTime.now(),
    );
  }

  // ==========================================================================
  // RECALCULATE TOTAL
  // ==========================================================================

  PalaiBill recalculate() {
    final newSubtotal =
        palaiAmount +
            additionalCharges +
            miscellaneousCharges;

    final newTotal =
    _safeAmount(
      newSubtotal -
          discount,
    );

    final newPaid =
    amountPaid > newTotal
        ? newTotal
        : amountPaid;

    final newPending =
    _safeAmount(
      newTotal -
          newPaid,
    );

    PalaiBillStatus newStatus;

    if (newPending <= 0) {
      newStatus =
          PalaiBillStatus.paid;
    } else if (newPaid > 0) {
      newStatus =
          PalaiBillStatus.partiallyPaid;
    } else {
      newStatus =
          PalaiBillStatus.issued;
    }

    return copyWith(
      subtotal: newSubtotal,
      totalAmount: newTotal,
      amountPaid: newPaid,
      pendingAmount: newPending,
      status: newStatus,
      updatedAt: DateTime.now(),
    );
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (customerId.trim().isEmpty) {
      return 'Customer ID is required.';
    }

    if (billNumber.trim().isEmpty) {
      return 'Bill number is required.';
    }

    if (billingEndDate.isBefore(
      billingStartDate,
    )) {
      return 'Billing end date cannot be before start date.';
    }

    if (palaiAmount < 0) {
      return 'Palai amount cannot be negative.';
    }

    if (additionalCharges < 0) {
      return 'Additional charges cannot be negative.';
    }

    if (miscellaneousCharges < 0) {
      return 'Miscellaneous charges cannot be negative.';
    }

    if (discount < 0) {
      return 'Discount cannot be negative.';
    }

    if (discount > subtotal) {
      return 'Discount cannot exceed subtotal.';
    }

    if (amountPaid < 0) {
      return 'Paid amount cannot be negative.';
    }

    if (amountPaid > totalAmount) {
      return 'Paid amount cannot exceed total amount.';
    }

    return null;
  }

  // ==========================================================================
  // STATUS HELPERS
  // ==========================================================================

  bool get isDraft {
    return status == PalaiBillStatus.draft;
  }

  bool get isIssued {
    return status == PalaiBillStatus.issued;
  }

  bool get isPartiallyPaid {
    return status ==
        PalaiBillStatus.partiallyPaid;
  }

  bool get isPaid {
    return status == PalaiBillStatus.paid;
  }

  bool get isOverdue {
    return status ==
        PalaiBillStatus.overdue;
  }

  bool get isCancelled {
    return status ==
        PalaiBillStatus.cancelled;
  }

  bool get hasPendingAmount {
    return pendingAmount > 0;
  }

  bool get hasPayment {
    return amountPaid > 0;
  }

  // ==========================================================================
  // MONTH HELPERS
  // ==========================================================================

  String get monthKey {
    return '$year-${month.toString().padLeft(2, '0')}';
  }

  String get monthLabel {
    const months = [
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

    if (month < 1 || month > 12) {
      return '$year';
    }

    return '${months[month - 1]} $year';
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

  String get statusLabel {
    switch (status) {
      case PalaiBillStatus.draft:
        return 'Draft';

      case PalaiBillStatus.issued:
        return 'Issued';

      case PalaiBillStatus.partiallyPaid:
        return 'Partially Paid';

      case PalaiBillStatus.paid:
        return 'Paid';

      case PalaiBillStatus.overdue:
        return 'Overdue';

      case PalaiBillStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isDue {
    if (dueDate == null ||
        isPaid ||
        isCancelled) {
      return false;
    }

    final today = DateTime.now();

    final dueDay = DateTime(
      dueDate!.year,
      dueDate!.month,
      dueDate!.day,
    );

    final currentDay = DateTime(
      today.year,
      today.month,
      today.day,
    );

    return currentDay.isAfter(
      dueDay,
    );
  }

  // ==========================================================================
  // FIRESTORE HELPERS
  // ==========================================================================

  static String _stringValue(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final result =
    value.toString();

    if (result.trim().isEmpty) {
      return fallback;
    }

    return result;
  }

  static int _intValue(
      dynamic value, {
        required int fallback,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  static double _doubleValue(
      dynamic value, {
        double fallback = 0,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  static DateTime _dateValue(
      dynamic value, {
        DateTime? fallback,
      }) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(
        value,
      ) ??
          fallback ??
          DateTime.now();
    }

    return fallback ??
        DateTime.now();
  }

  static DateTime? _nullableDateValue(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(
        value,
      );
    }

    return null;
  }

  static PalaiBillStatus _statusValue(
      dynamic value,
      ) {
    if (value == null) {
      return PalaiBillStatus.draft;
    }

    switch (value.toString()) {
      case 'draft':
        return PalaiBillStatus.draft;

      case 'issued':
        return PalaiBillStatus.issued;

      case 'partiallyPaid':
        return PalaiBillStatus.partiallyPaid;

      case 'paid':
        return PalaiBillStatus.paid;

      case 'overdue':
        return PalaiBillStatus.overdue;

      case 'cancelled':
        return PalaiBillStatus.cancelled;

      default:
        return PalaiBillStatus.draft;
    }
  }

  static double _safeAmount(
      double value,
      ) {
    if (value.isNaN ||
        value.isInfinite ||
        value < 0) {
      return 0;
    }

    return double.parse(
      value.toStringAsFixed(2),
    );
  }

  // ==========================================================================
  // DEBUG
  // ==========================================================================

  @override
  String toString() {
    return 'PalaiBill('
        'id: $id, '
        'customerId: $customerId, '
        'billNumber: $billNumber, '
        'month: $monthKey, '
        'totalAmount: $totalAmount, '
        'amountPaid: $amountPaid, '
        'pendingAmount: $pendingAmount, '
        'status: ${status.name}'
        ')';
  }
}