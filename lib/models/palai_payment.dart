import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// PALAI PAYMENT
/// ============================================================================
///
/// Represents ONE payment made by a customer against a Palai bill.
///
/// IMPORTANT:
///
/// A payment is an individual financial transaction.
///
/// Example:
///
/// Bill: ₹10,000
///
/// Payment #1 -> ₹4,000
/// Payment #2 -> ₹3,000
/// Payment #3 -> ₹3,000
///
/// Total Paid -> ₹10,000
/// Pending    -> ₹0
///
/// We keep every payment as a separate historical record.
///
/// This makes it possible to build:
///
/// - Payment History
/// - Monthly Payment History
/// - Customer Payment History
/// - Pending Payment Calculation
/// - Payment Receipts
/// - Reports
/// - Payment Reminders
///
/// ============================================================================

enum PalaiPaymentMethod {
  cash,
  upi,
  bankTransfer,
  cheque,
  card,
  other,
}

enum PalaiPaymentStatus {
  completed,
  pending,
  cancelled,
  refunded,
}

class PalaiPayment {
  // ==========================================================================
  // IDENTITY
  // ==========================================================================

  final String id;

  /// Customer who made the payment.
  final String customerId;

  /// Bill against which the payment was made.
  final String billId;

  /// Optional goat reference.
  ///
  /// Normally payment belongs to the customer/bill rather than an individual
  /// goat, but this allows us to support goat-specific charges later.
  final String goatId;

  // ==========================================================================
  // PAYMENT INFORMATION
  // ==========================================================================

  final double amount;

  final DateTime paymentDate;

  final PalaiPaymentMethod paymentMethod;

  final PalaiPaymentStatus status;

  // ==========================================================================
  // TRANSACTION INFORMATION
  // ==========================================================================

  /// UPI transaction ID / bank reference / cheque number etc.
  final String transactionReference;

  /// Optional receipt number.
  final String receiptNumber;

  // ==========================================================================
  // NOTES
  // ==========================================================================

  final String notes;

  /// Person who recorded the payment.
  final String recordedBy;

  // ==========================================================================
  // AUDIT
  // ==========================================================================

  final DateTime createdAt;

  final DateTime updatedAt;

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const PalaiPayment({
    required this.id,
    required this.customerId,
    required this.billId,
    this.goatId = '',
    required this.amount,
    required this.paymentDate,
    this.paymentMethod = PalaiPaymentMethod.cash,
    this.status = PalaiPaymentStatus.completed,
    this.transactionReference = '',
    this.receiptNumber = '',
    this.notes = '',
    this.recordedBy = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // CREATE PAYMENT
  // ==========================================================================

  factory PalaiPayment.create({
    required String id,
    required String customerId,
    required String billId,
    String goatId = '',
    required double amount,
    required DateTime paymentDate,
    PalaiPaymentMethod paymentMethod =
        PalaiPaymentMethod.cash,
    String transactionReference = '',
    String receiptNumber = '',
    String notes = '',
    String recordedBy = '',
    PalaiPaymentStatus status =
        PalaiPaymentStatus.completed,
  }) {
    final now = DateTime.now();

    return PalaiPayment(
      id: id,
      customerId: customerId,
      billId: billId,
      goatId: goatId,
      amount: _safeAmount(amount),
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      status: status,
      transactionReference:
      transactionReference,
      receiptNumber: receiptNumber,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  PalaiPayment copyWith({
    String? id,
    String? customerId,
    String? billId,
    String? goatId,
    double? amount,
    DateTime? paymentDate,
    PalaiPaymentMethod? paymentMethod,
    PalaiPaymentStatus? status,
    String? transactionReference,
    String? receiptNumber,
    String? notes,
    String? recordedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PalaiPayment(
      id: id ?? this.id,
      customerId:
      customerId ?? this.customerId,
      billId:
      billId ?? this.billId,
      goatId:
      goatId ?? this.goatId,
      amount:
      amount ?? this.amount,
      paymentDate:
      paymentDate ?? this.paymentDate,
      paymentMethod:
      paymentMethod ?? this.paymentMethod,
      status:
      status ?? this.status,
      transactionReference:
      transactionReference ??
          this.transactionReference,
      receiptNumber:
      receiptNumber ??
          this.receiptNumber,
      notes:
      notes ?? this.notes,
      recordedBy:
      recordedBy ?? this.recordedBy,
      createdAt:
      createdAt ?? this.createdAt,
      updatedAt:
      updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory PalaiPayment.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data =
        doc.data() ?? <String, dynamic>{};

    return PalaiPayment(
      id: doc.id,

      customerId:
      _stringValue(
        data['customerId'],
      ),

      billId:
      _stringValue(
        data['billId'],
      ),

      goatId:
      _stringValue(
        data['goatId'],
      ),

      amount:
      _doubleValue(
        data['amount'],
      ),

      paymentDate:
      _dateValue(
        data['paymentDate'] ??
            data['date'],
      ),

      paymentMethod:
      _paymentMethodValue(
        data['paymentMethod'] ??
            data['method'],
      ),

      status:
      _statusValue(
        data['status'],
      ),

      transactionReference:
      _stringValue(
        data['transactionReference'] ??
            data['transactionId'],
      ),

      receiptNumber:
      _stringValue(
        data['receiptNumber'],
      ),

      notes:
      _stringValue(
        data['notes'],
      ),

      recordedBy:
      _stringValue(
        data['recordedBy'],
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

      'billId': billId,

      'goatId': goatId,

      'amount': amount,

      'paymentDate':
      Timestamp.fromDate(
        paymentDate,
      ),

      'paymentMethod':
      paymentMethod.name,

      'status':
      status.name,

      'transactionReference':
      transactionReference,

      'receiptNumber':
      receiptNumber,

      'notes':
      notes,

      'recordedBy':
      recordedBy,

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
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (customerId.trim().isEmpty) {
      return 'Customer ID is required.';
    }

    if (billId.trim().isEmpty) {
      return 'Bill ID is required.';
    }

    if (amount <= 0) {
      return 'Payment amount must be greater than zero.';
    }

    if (paymentMethod !=
        PalaiPaymentMethod.cash &&
        transactionReference.trim().isEmpty &&
        paymentMethod !=
            PalaiPaymentMethod.other) {
      return 'Transaction reference is required for this payment method.';
    }

    return null;
  }

  // ==========================================================================
  // STATUS HELPERS
  // ==========================================================================

  bool get isCompleted {
    return status ==
        PalaiPaymentStatus.completed;
  }

  bool get isPending {
    return status ==
        PalaiPaymentStatus.pending;
  }

  bool get isCancelled {
    return status ==
        PalaiPaymentStatus.cancelled;
  }

  bool get isRefunded {
    return status ==
        PalaiPaymentStatus.refunded;
  }

  // ==========================================================================
  // PAYMENT METHOD HELPERS
  // ==========================================================================

  bool get isCash {
    return paymentMethod ==
        PalaiPaymentMethod.cash;
  }

  bool get isUpi {
    return paymentMethod ==
        PalaiPaymentMethod.upi;
  }

  bool get isBankTransfer {
    return paymentMethod ==
        PalaiPaymentMethod.bankTransfer;
  }

  bool get isCheque {
    return paymentMethod ==
        PalaiPaymentMethod.cheque;
  }

  bool get isCard {
    return paymentMethod ==
        PalaiPaymentMethod.card;
  }

  String get paymentMethodLabel {
    switch (paymentMethod) {
      case PalaiPaymentMethod.cash:
        return 'Cash';

      case PalaiPaymentMethod.upi:
        return 'UPI';

      case PalaiPaymentMethod.bankTransfer:
        return 'Bank Transfer';

      case PalaiPaymentMethod.cheque:
        return 'Cheque';

      case PalaiPaymentMethod.card:
        return 'Card';

      case PalaiPaymentMethod.other:
        return 'Other';
    }
  }

  String get statusLabel {
    switch (status) {
      case PalaiPaymentStatus.completed:
        return 'Completed';

      case PalaiPaymentStatus.pending:
        return 'Pending';

      case PalaiPaymentStatus.cancelled:
        return 'Cancelled';

      case PalaiPaymentStatus.refunded:
        return 'Refunded';
    }
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

  bool get hasTransactionReference {
    return transactionReference
        .trim()
        .isNotEmpty;
  }

  bool get hasReceiptNumber {
    return receiptNumber
        .trim()
        .isNotEmpty;
  }

  bool get hasNotes {
    return notes.trim().isNotEmpty;
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

  static PalaiPaymentMethod
  _paymentMethodValue(
      dynamic value,
      ) {
    if (value == null) {
      return PalaiPaymentMethod.cash;
    }

    switch (value.toString()) {
      case 'cash':
        return PalaiPaymentMethod.cash;

      case 'upi':
        return PalaiPaymentMethod.upi;

      case 'bankTransfer':
        return PalaiPaymentMethod.bankTransfer;

      case 'cheque':
        return PalaiPaymentMethod.cheque;

      case 'card':
        return PalaiPaymentMethod.card;

      case 'other':
        return PalaiPaymentMethod.other;

      default:
        return PalaiPaymentMethod.cash;
    }
  }

  static PalaiPaymentStatus
  _statusValue(
      dynamic value,
      ) {
    if (value == null) {
      return PalaiPaymentStatus.completed;
    }

    switch (value.toString()) {
      case 'completed':
        return PalaiPaymentStatus.completed;

      case 'pending':
        return PalaiPaymentStatus.pending;

      case 'cancelled':
        return PalaiPaymentStatus.cancelled;

      case 'refunded':
        return PalaiPaymentStatus.refunded;

      default:
        return PalaiPaymentStatus.completed;
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
    return 'PalaiPayment('
        'id: $id, '
        'customerId: $customerId, '
        'billId: $billId, '
        'amount: $amount, '
        'method: ${paymentMethod.name}, '
        'status: ${status.name}'
        ')';
  }
}