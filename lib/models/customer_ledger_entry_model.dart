import 'package:cloud_firestore/cloud_firestore.dart';

enum LedgerEntryKind {
  monthlyBill, // from `bills` (type: monthly) or `monthlyBills`
  manualOutstanding, // from `bills` (type: manualOutstanding)
  payment, // from `payments` (type: billPayment / standalone)
  outstandingAdded, // from `payments` (type: outstandingAdded) — display only, not cash
}

/// One row in a Customer Ledger — built directly from an existing bill,
/// monthly-bill, or payment document. This is a read-time view, never a
/// stored document: per spec §16, current balance always comes from the
/// customer's live `pendingAmount`/`advanceAmount`, and history always
/// comes from the snapshot fields already stored on these existing docs.
class CustomerLedgerEntry {
  final String id;
  final LedgerEntryKind kind;
  final DateTime date;
  final String title;
  final String subtitle;

  /// True for a charge/bill (increases what the customer owes), false
  /// for a payment/credit (reduces it).
  final bool isDebit;

  final double amount;

  /// Snapshot fields as stored on the source document — never
  /// recalculated here.
  final double? pendingBefore;
  final double? pendingAfter;
  final double? advanceBefore;
  final double? advanceAfter;

  final String? paymentMethod;
  final String? note;

  const CustomerLedgerEntry({
    required this.id,
    required this.kind,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.isDebit,
    required this.amount,
    this.pendingBefore,
    this.pendingAfter,
    this.advanceBefore,
    this.advanceAfter,
    this.paymentMethod,
    this.note,
  });

  /// Builds a ledger row from a `bills` document (both `monthly`
  /// check-out bills and `manualOutstanding` entries land here).
  factory CustomerLedgerEntry.fromBillDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final type = (data['type'] ?? '').toString();
    final isManualOutstanding = type == 'manualOutstanding';

    final newCharges = (data['newCharges'] ?? data['amount'] ?? 0).toDouble();
    final billNumber = (data['billNumber'] ?? '').toString();

    return CustomerLedgerEntry(
      id: doc.id,
      kind: isManualOutstanding
          ? LedgerEntryKind.manualOutstanding
          : LedgerEntryKind.monthlyBill,
      date: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      title: isManualOutstanding ? 'Manual Outstanding' : 'Monthly Bill',
      subtitle: billNumber.isEmpty ? '' : billNumber,
      isDebit: true,
      amount: newCharges,
      pendingBefore: (data['previousPending'] as num?)?.toDouble(),
      pendingAfter: (data['pendingAfter'] as num?)?.toDouble(),
      advanceBefore: (data['advanceBefore'] as num?)?.toDouble(),
      advanceAfter: (data['advanceAfter'] as num?)?.toDouble(),
      note: (data['note'] ?? '').toString(),
    );
  }

  /// Builds a ledger row from a `monthlyBills` document (the recurring
  /// customer monthly-billing flow — see MonthlyBillingService).
  factory CustomerLedgerEntry.fromMonthlyBillDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final billNumber = (data['billNumber'] ?? '').toString();

    return CustomerLedgerEntry(
      id: doc.id,
      kind: LedgerEntryKind.monthlyBill,
      date:
          (data['generatedAt'] as Timestamp?)?.toDate() ??
          (data['billingMonth'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      title: 'Monthly Bill',
      subtitle: billNumber.isEmpty ? '' : billNumber,
      isDebit: true,
      amount: (data['currentBillAmount'] ?? 0).toDouble(),
      pendingBefore: (data['previousOutstanding'] as num?)?.toDouble(),
      pendingAfter:
          null, // monthlyBills doesn't snapshot a farm-wide pendingAfter
      note: (data['notes'] ?? '').toString(),
    );
  }

  /// Builds a ledger row from a `payments` document. Branches on `type`
  /// because an `outstandingAdded` payment doc represents money now
  /// *owed*, not money received — it must never be shown or counted as
  /// a credit (see customer_profile_screen.dart's existing handling of
  /// the same field).
  factory CustomerLedgerEntry.fromPaymentDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final isOutstandingAdded = data['type'] == 'outstandingAdded';
    final paymentNumber = (data['paymentNumber'] ?? '').toString();

    if (isOutstandingAdded) {
      return CustomerLedgerEntry(
        id: doc.id,
        kind: LedgerEntryKind.outstandingAdded,
        date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        title: 'Outstanding Added',
        subtitle: paymentNumber,
        isDebit: true,
        amount: (data['pendingAdded'] ?? data['amount'] ?? 0).toDouble(),
        pendingBefore: (data['pendingBefore'] as num?)?.toDouble(),
        pendingAfter: (data['pendingAfter'] as num?)?.toDouble(),
        advanceBefore: (data['advanceBefore'] as num?)?.toDouble(),
        advanceAfter: (data['advanceAfter'] as num?)?.toDouble(),
        note: (data['note'] ?? '').toString(),
      );
    }

    return CustomerLedgerEntry(
      id: doc.id,
      kind: LedgerEntryKind.payment,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      title: 'Payment Received',
      subtitle: paymentNumber,
      isDebit: false,
      amount: (data['amountReceived'] ?? data['amount'] ?? 0).toDouble(),
      pendingBefore: (data['pendingBefore'] as num?)?.toDouble(),
      pendingAfter: (data['pendingAfter'] as num?)?.toDouble(),
      advanceBefore: (data['advanceBefore'] as num?)?.toDouble(),
      advanceAfter: (data['advanceAfter'] as num?)?.toDouble(),
      paymentMethod: data['paymentMethod'] as String?,
      note: (data['note'] ?? '').toString(),
    );
  }
}
