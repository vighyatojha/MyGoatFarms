import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity_model.dart';
import '../models/customer_ledger_entry_model.dart';
import '../models/expense_model.dart';
import '../models/finance_summary_model.dart';
import '../models/supplier_ledger_entry_model.dart';
import 'firestore_service.dart';

/// Handles the new farm-wide Finance module: expenses, manual revenue,
/// finance summaries, and the customer ledger view.
///
/// This is a separate service file rather than more additions to the
/// already very large `firestore_service.dart`, following the same
/// precedent [MonthlyBillingService] already set for the recurring
/// monthly-billing flow. It deliberately does NOT touch, wrap, or
/// duplicate anything `FirestoreService` already owns:
///
/// - Existing bills / monthlyBills / payments / customer balance writes
///   are untouched — this service only ever *reads* them for the ledger.
/// - Actor resolution (`getCurrentActor`) is reused from
///   [FirestoreService.instance] so Finance activity entries carry the
///   same actorUid/actorName/actorRole shape as every other module's.
///   Activity docs themselves are written directly here (same field
///   shape `ActivityLog.toMap()` produces) rather than through
///   `FirestoreService.logActivity`, because that helper always issues
///   its own standalone `.add()` — it can't join the same `WriteBatch`
///   as the expense/transaction write, and batching all three together
///   is what keeps an expense and its mirrored transaction from ever
///   being created out of sync with each other.
/// - Existing income transactions (written by createMonthlyBill /
///   receivePalaiPayment / MonthlyBillingService) are read here, never
///   rewritten — this service only *adds* new transaction docs for
///   expenses and manual revenue, using the same `transactions` shape.
class FinanceService {
  FinanceService._();

  static final FinanceService instance = FinanceService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------
  // COLLECTIONS
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _farms() =>
      _db.collection('farms');

  CollectionReference<Map<String, dynamic>> _expenses(String farmId) =>
      _farms().doc(farmId).collection('expenses');

  CollectionReference<Map<String, dynamic>> _transactions(String farmId) =>
      _farms().doc(farmId).collection('transactions');

  CollectionReference<Map<String, dynamic>> _bills(String farmId) =>
      _farms().doc(farmId).collection('bills');

  CollectionReference<Map<String, dynamic>> _monthlyBills(String farmId) =>
      _farms().doc(farmId).collection('monthlyBills');

  CollectionReference<Map<String, dynamic>> _payments(String farmId) =>
      _farms().doc(farmId).collection('payments');

  CollectionReference<Map<String, dynamic>> _customers(String farmId) =>
      _farms().doc(farmId).collection('palaiCustomers');

  CollectionReference<Map<String, dynamic>> _activities(String farmId) =>
      _farms().doc(farmId).collection('activities');

  CollectionReference<Map<String, dynamic>> _supplierLedger(String farmId) =>
      _farms().doc(farmId).collection('supplierLedger');

  // ---------------------------------------------------------------------
  // EXPENSES
  // ---------------------------------------------------------------------

  /// Creates an expense and its paired income-ledger entry
  /// (`transactions` doc with `isIncome: false`) atomically, so every
  /// screen that already sums `transactions` for cash flow picks up
  /// expenses automatically without a second query.
  Future<void> addExpense(String farmId, ExpenseModel expense) async {
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    if (expense.title.trim().isEmpty) {
      throw ArgumentError('Expense title is required.');
    }
    if (expense.paymentMethod.trim().isEmpty) {
      throw ArgumentError('Please select a payment method.');
    }

    final actor = await FirestoreService.instance.getCurrentActor();

    final expenseRef = _expenses(farmId).doc();
    final transactionRef = _transactions(farmId).doc();
    final activityRef = _activities(farmId).doc();

    final batch = _db.batch();

    batch.set(
      expenseRef,
      expense
          .toCreateMap(
        createdBy: actor?.uid ?? '',
        createdByName: actor?.name ?? 'Unknown',
        createdByRole: actor?.role ?? '',
      )
      // The mirrored transaction id is stored on the expense so a
      // later edit/void can find and update it without a query.
        ..addAll({'transactionId': transactionRef.id}),
    );

    batch.set(transactionRef, {
      'amount': expense.amount,
      'isIncome': false,
      'category': expense.category,
      'note': expense.title.trim(),
      'paymentMethod': expense.paymentMethod,
      'date': Timestamp.fromDate(expense.date),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'referenceType': 'expense',
      'referenceId': expenseRef.id,
    });

    batch.set(activityRef, {
      'type': ActivityType.expenseAdded.name,
      'title': 'Expense Added',
      'subtitle':
      '${expense.category} · ₹${expense.amount.toStringAsFixed(0)}'
          '${expense.supplierName != null && expense.supplierName!.trim().isNotEmpty ? ' · ${expense.supplierName}' : ''}',
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);
  }

  /// Updates an expense in place. The mirrored `transactions` doc is
  /// updated to match so aggregation stays correct — this does not
  /// create a second transaction.
  Future<void> updateExpense(
      String farmId,
      String expenseId,
      ExpenseModel updated,
      ) async {
    if (updated.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }

    final expenseRef = _expenses(farmId).doc(expenseId);
    final snap = await expenseRef.get().timeout(_timeout);
    if (!snap.exists) {
      throw StateError('This expense no longer exists.');
    }

    final transactionId = (snap.data()?['transactionId'] ?? '').toString();

    final batch = _db.batch();
    batch.update(expenseRef, updated.toUpdateMap());

    if (transactionId.isNotEmpty) {
      batch.update(_transactions(farmId).doc(transactionId), {
        'amount': updated.amount,
        'category': updated.category,
        'note': updated.title.trim(),
        'paymentMethod': updated.paymentMethod,
        'date': Timestamp.fromDate(updated.date),
      });
    }

    final actor = await FirestoreService.instance.getCurrentActor();
    final activityRef = _activities(farmId).doc();
    batch.set(activityRef, {
      'type': ActivityType.expenseAdded.name,
      'title': 'Expense Updated',
      'subtitle':
      '${updated.title} · ₹${updated.amount.toStringAsFixed(0)}',
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);
  }

  /// Soft-deletes (voids) an expense rather than removing it — per spec
  /// §29/§38, financial records stay auditable. A voided expense and
  /// its mirrored transaction are both excluded from every calculation.
  Future<void> voidExpense(
      String farmId,
      ExpenseModel expense, {
        String? transactionId,
      }) async {
    final expenseRef = _expenses(farmId).doc(expense.id);
    final snap = await expenseRef.get().timeout(_timeout);
    final resolvedTransactionId =
        transactionId ?? (snap.data()?['transactionId'] ?? '').toString();

    final batch = _db.batch();
    batch.update(expenseRef, {
      'status': 'voided',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (resolvedTransactionId.isNotEmpty) {
      batch.update(_transactions(farmId).doc(resolvedTransactionId), {
        'status': 'voided',
      });
    }

    final actor = await FirestoreService.instance.getCurrentActor();
    final activityRef = _activities(farmId).doc();
    batch.set(activityRef, {
      'type': ActivityType.expenseVoided.name,
      'title': 'Expense Voided',
      'subtitle': '${expense.title} · ₹${expense.amount.toStringAsFixed(0)}',
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);
  }

  /// Live expense list for a date range. Filtered to a single field
  /// (`date`) server-side — the same field it's ordered by — so no
  /// composite Firestore index is required. `status`/`category` are
  /// filtered client-side, which is fine at farm-app data volumes; if
  /// this ever needs to scale up, add a composite index on
  /// (status, date) and move that filter server-side.
  Stream<List<ExpenseModel>> expensesStream(
      String farmId, {
        DateTime? start,
        DateTime? end,
        String? category,
        bool includeVoided = false,
      }) {
    Query<Map<String, dynamic>> q = _expenses(
      farmId,
    ).orderBy('date', descending: true);

    if (start != null) {
      q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }
    if (end != null) {
      q = q.where('date', isLessThan: Timestamp.fromDate(end));
    }

    return q.snapshots().map((snap) {
      var items = snap.docs.map(ExpenseModel.fromDoc).toList();
      if (!includeVoided) {
        items = items.where((e) => !e.isVoided).toList();
      }
      if (category != null && category.isNotEmpty) {
        items = items.where((e) => e.category == category).toList();
      }
      return items;
    });
  }

  // ---------------------------------------------------------------------
  // MANUAL REVENUE
  //
  // Manual revenue is NOT a new collection — it's a `transactions` doc
  // with isIncome:true and referenceType:'manualRevenue'. Customer
  // payments (the other source of income) already write to this same
  // collection via the existing billing flow, so this keeps "one
  // real-world event = one financial transaction" (spec Rule 5) without
  // a second income-shaped collection to keep in sync.
  // ---------------------------------------------------------------------

  Future<void> addManualRevenue(
      String farmId, {
        required String category,
        required double amount,
        required String paymentMethod,
        required DateTime date,
        String description = '',
      }) async {
    if (amount <= 0) {
      throw ArgumentError('Revenue amount must be greater than zero.');
    }
    if (paymentMethod.trim().isEmpty) {
      throw ArgumentError('Please select a payment method.');
    }

    final actor = await FirestoreService.instance.getCurrentActor();
    final transactionRef = _transactions(farmId).doc();
    final activityRef = _activities(farmId).doc();

    final batch = _db.batch();

    batch.set(transactionRef, {
      'amount': amount,
      'isIncome': true,
      'category': category,
      'note': description.trim().isNotEmpty
          ? description.trim()
          : category,
      'paymentMethod': paymentMethod,
      'date': Timestamp.fromDate(date),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'referenceType': 'manualRevenue',
      if (actor != null) 'createdBy': actor.uid,
      if (actor != null) 'createdByName': actor.name,
      if (actor != null) 'createdByRole': actor.role,
    });

    batch.set(activityRef, {
      'type': ActivityType.revenueAdded.name,
      'title': 'Revenue Added',
      'subtitle': '$category · ₹${amount.toStringAsFixed(0)}',
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);
  }

  Future<void> updateManualRevenue(
      String farmId,
      String transactionId, {
        required String category,
        required double amount,
        required String paymentMethod,
        required DateTime date,
        String description = '',
      }) async {
    if (amount <= 0) {
      throw ArgumentError('Revenue amount must be greater than zero.');
    }

    await _transactions(farmId).doc(transactionId).update({
      'amount': amount,
      'category': category,
      'note': description.trim().isNotEmpty ? description.trim() : category,
      'paymentMethod': paymentMethod,
      'date': Timestamp.fromDate(date),
    }).timeout(_timeout);

    final actor = await FirestoreService.instance.getCurrentActor();
    await _activities(farmId).add({
      'type': ActivityType.revenueAdded.name,
      'title': 'Revenue Updated',
      'subtitle': '$category · ₹${amount.toStringAsFixed(0)}',
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    }).timeout(_timeout);
  }

  /// Voids a manual-revenue transaction. Customer-payment-derived
  /// transactions must NEVER be voided this way — corrections to those
  /// belong in the existing payment/bill correction flow (spec §29), so
  /// this only accepts a transaction whose `referenceType` is already
  /// `manualRevenue`, and the UI must never offer void on anything else.
  Future<void> voidManualRevenue(
      String farmId,
      String transactionId,
      Map<String, dynamic> transactionData,
      ) async {
    if (transactionData['referenceType'] != 'manualRevenue') {
      throw StateError(
        'Only manually added revenue can be voided here.',
      );
    }

    await _transactions(farmId).doc(transactionId).update({
      'status': 'voided',
    }).timeout(_timeout);

    final actor = await FirestoreService.instance.getCurrentActor();
    await _activities(farmId).add({
      'type': ActivityType.revenueVoided.name,
      'title': 'Revenue Voided',
      'subtitle':
      '${transactionData['category'] ?? ''} · ₹${((transactionData['amount'] ?? 0) as num).toStringAsFixed(0)}',
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    }).timeout(_timeout);
  }

  /// Live revenue (income) list for a date range — reads the *existing*
  /// shared `transactions` collection, so customer payments generated by
  /// createMonthlyBill / receivePalaiPayment / MonthlyBillingService show
  /// up automatically alongside manual revenue, with zero duplication.
  Stream<List<FinanceTransactionRow>> revenueStream(
      String farmId, {
        DateTime? start,
        DateTime? end,
        String? category,
      }) {
    Query<Map<String, dynamic>> q = _transactions(
      farmId,
    ).orderBy('date', descending: true);

    if (start != null) {
      q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }
    if (end != null) {
      q = q.where('date', isLessThan: Timestamp.fromDate(end));
    }

    return q.snapshots().map((snap) {
      var rows = snap.docs
          .where((d) => d.data()['isIncome'] == true)
          .where((d) => d.data()['status'] != 'voided')
          .map(
            (d) => FinanceTransactionRow(
          id: d.id,
          isIncome: true,
          category: (d.data()['category'] ?? '').toString(),
          title: (d.data()['customerName'] ?? d.data()['category'] ?? '')
              .toString(),
          amount: (d.data()['amount'] ?? 0).toDouble(),
          date: (d.data()['date'] as Timestamp?)?.toDate() ??
              DateTime.now(),
          customerName: d.data()['customerName'] as String?,
          paymentMethod: (d.data()['paymentMethod'] ?? '').toString(),
          note: d.data()['note'] as String?,
          sourceCollection: 'transactions',
        ),
      )
          .toList();

      if (category != null && category.isNotEmpty) {
        rows = rows.where((r) => r.category == category).toList();
      }
      return rows;
    });
  }

  // ---------------------------------------------------------------------
  // FINANCE SUMMARY (Overview / Reports)
  // ---------------------------------------------------------------------

  /// One-shot summary for [start, end) — not a live stream, mirroring
  /// how the existing Monthly Report screen already computes its
  /// numbers on demand rather than subscribing. Screens re-fetch this
  /// on pull-to-refresh and after returning from add/edit screens,
  /// exactly like [StockScreen] already does for its own data.
  Future<FinanceSummary> getFinanceSummary(
      String farmId, {
        required DateTime start,
        required DateTime end,
      }) async {
    final startTs = Timestamp.fromDate(start);
    final endTs = Timestamp.fromDate(end);

    final transactionsSnap = await _transactions(farmId)
        .where('date', isGreaterThanOrEqualTo: startTs)
        .where('date', isLessThan: endTs)
        .get()
        .timeout(_timeout);

    final expensesSnap = await _expenses(farmId)
        .where('date', isGreaterThanOrEqualTo: startTs)
        .where('date', isLessThan: endTs)
        .get()
        .timeout(_timeout);

    double revenue = 0;
    final revenueByCategory = <String, double>{};

    for (final doc in transactionsSnap.docs) {
      final data = doc.data();
      if (data['isIncome'] != true) continue;
      if (data['status'] == 'voided') continue;
      final amount = (data['amount'] ?? 0).toDouble();
      revenue += amount;
      final category = (data['category'] ?? 'Other').toString();
      revenueByCategory[category] = (revenueByCategory[category] ?? 0) + amount;
    }

    double expenses = 0;
    final expenseByCategory = <String, double>{};

    for (final doc in expensesSnap.docs) {
      final data = doc.data();
      if (data['status'] == 'voided') continue;
      final amount = (data['amount'] ?? 0).toDouble();
      expenses += amount;
      final category = (data['category'] ?? 'Other').toString();
      expenseByCategory[category] = (expenseByCategory[category] ?? 0) + amount;
    }

    // Current-balance figures — never period totals (spec §22).
    final customersSnap = await _customers(farmId).get().timeout(_timeout);
    double totalOutstanding = 0;
    double totalAdvance = 0;
    for (final doc in customersSnap.docs) {
      final data = doc.data();
      totalOutstanding += ((data['pendingAmount'] ?? 0) as num).toDouble();
      totalAdvance += ((data['advanceAmount'] ?? 0) as num).toDouble();
    }

    return FinanceSummary(
      revenue: revenue,
      expenses: expenses,
      totalOutstanding: totalOutstanding,
      totalAdvance: totalAdvance,
      revenueByCategory: revenueByCategory,
      expenseByCategory: expenseByCategory,
    );
  }

  /// Combined recent-transactions feed for the Overview screen — merges
  /// the last [limit] income rows and expense rows into one
  /// newest-first list.
  Future<List<FinanceTransactionRow>> getRecentTransactions(
      String farmId, {
        int limit = 10,
      }) async {
    final incomeSnap = await _transactions(farmId)
        .orderBy('date', descending: true)
        .limit(limit)
        .get()
        .timeout(_timeout);

    final expenseSnap = await _expenses(farmId)
        .orderBy('date', descending: true)
        .limit(limit)
        .get()
        .timeout(_timeout);

    final rows = <FinanceTransactionRow>[];

    for (final doc in incomeSnap.docs) {
      final data = doc.data();
      if (data['isIncome'] != true) continue;
      if (data['status'] == 'voided') continue;
      rows.add(
        FinanceTransactionRow(
          id: doc.id,
          isIncome: true,
          category: (data['category'] ?? '').toString(),
          title: (data['customerName'] ?? data['category'] ?? '').toString(),
          amount: (data['amount'] ?? 0).toDouble(),
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          customerName: data['customerName'] as String?,
          paymentMethod: (data['paymentMethod'] ?? '').toString(),
          note: data['note'] as String?,
          sourceCollection: 'transactions',
        ),
      );
    }

    for (final doc in expenseSnap.docs) {
      final expense = ExpenseModel.fromDoc(doc);
      if (expense.isVoided) continue;
      rows.add(
        FinanceTransactionRow(
          id: doc.id,
          isIncome: false,
          category: expense.category,
          title: expense.title,
          amount: expense.amount,
          date: expense.date,
          paymentMethod: expense.paymentMethod,
          note: expense.note,
          sourceCollection: 'expenses',
        ),
      );
    }

    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows.take(limit).toList();
  }

  // ---------------------------------------------------------------------
  // CUSTOMER LEDGER
  //
  // Read-only aggregation over existing bills / monthlyBills / payments.
  // No new collection, no recomputation of the customer's current
  // balance — that always comes from palaiCustomers directly (spec §16).
  // ---------------------------------------------------------------------

  Future<List<CustomerLedgerEntry>> getCustomerLedger(
      String farmId,
      String customerId,
      ) async {
    final results = await Future.wait([
      _bills(farmId).where('customerId', isEqualTo: customerId).get().timeout(_timeout),
      _monthlyBills(farmId).where('customerId', isEqualTo: customerId).get().timeout(_timeout),
      _payments(farmId).where('customerId', isEqualTo: customerId).get().timeout(_timeout),
    ]);

    final billsSnap = results[0];
    final monthlyBillsSnap = results[1];
    final paymentsSnap = results[2];

    final entries = <CustomerLedgerEntry>[
      ...billsSnap.docs.map(CustomerLedgerEntry.fromBillDoc),
      ...monthlyBillsSnap.docs.map(CustomerLedgerEntry.fromMonthlyBillDoc),
      ...paymentsSnap.docs.map(CustomerLedgerEntry.fromPaymentDoc),
    ];

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  // ---------------------------------------------------------------------
  // SUPPLIER LEDGER
  // ---------------------------------------------------------------------

  /// Full history for a single supplier — every credit purchase and
  /// payment recorded against them, newest first. Mirrors
  /// [getCustomerLedger], but reads a single `supplierLedger` collection
  /// since suppliers don't have separate bills/monthlyBills documents.
  Future<List<SupplierLedgerEntry>> getSupplierLedger(
      String farmId,
      String supplierId,
      ) async {
    final snap = await _supplierLedger(farmId)
        .where('supplierId', isEqualTo: supplierId)
        .get()
        .timeout(_timeout);

    final entries = snap.docs.map(SupplierLedgerEntry.fromDoc).toList();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }
}