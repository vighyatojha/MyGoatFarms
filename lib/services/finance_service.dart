import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity_model.dart';
import '../models/customer_ledger_entry_model.dart';
import '../models/expense_categories.dart';
import '../models/expense_model.dart';
import '../models/final_checkout_report_model.dart';
import '../models/finance_scope.dart';
import '../models/finance_summary_model.dart';
import '../models/trading_finance_summary.dart';
import '../models/sale_model.dart';
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

  CollectionReference<Map<String, dynamic>> _sales(String farmId) =>
      _farms().doc(farmId).collection('sales');

  CollectionReference<Map<String, dynamic>> _activities(String farmId) =>
      _farms().doc(farmId).collection('activities');

  CollectionReference<Map<String, dynamic>> _supplierLedger(String farmId) =>
      _farms().doc(farmId).collection('supplierLedger');

  /// True for any `transactions` doc that represents money coming IN.
  ///
  /// Every current writer sets `isIncome: true` — except
  /// [MonthlyBillingService.receiveMonthlyBillPayment], which (until
  /// fixed) only ever set a legacy `type: 'income'` field on the mirrored
  /// transaction. That meant a customer's Monthly Bill payment updated
  /// their balance and showed correctly in the Customer Ledger (which
  /// reads `payments`/`bills`/`monthlyBills` directly), but silently
  /// never counted as Revenue anywhere in the Finance module — Finance
  /// Overview's totals, its Cash/Online tracker, Recent Transactions, and
  /// the Revenue list all read `transactions` and checked `isIncome`
  /// alone. The write now sets both fields going forward; this read-side
  /// check also accepts the legacy `type: 'income'` shape so payments
  /// already sitting in Firestore from before that fix show up too,
  /// without needing a data migration.
  bool _isIncomeTransaction(Map<String, dynamic> data) =>
      data['isIncome'] == true || data['type'] == 'income';

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
    final activityRef = _activities(farmId).doc();

    final batch = _db.batch();

    // A "Buy on Credit" purchase (paymentMethod: Credit) has NOT been
    // paid for — it's a liability owed to the supplier, not cash out
    // the door. Finance is cash-based throughout (see class doc), so
    // this must not get a mirrored `transactions` doc: that doc is
    // exactly what Net Cash Flow, the Cash/Online tracker, and Home's
    // today's-net-income figure sum. The expense doc itself is still
    // written, so the purchase stays visible/auditable in the Expense
    // List — it's just excluded from every cash total (see
    // ExpenseModel.isUnpaidCredit and its use throughout this file).
    // The real cash outflow is recorded later, when the supplier is
    // actually paid — see FirestoreService.recordSupplierPayment.
    final isUnpaidCredit =
        expense.paymentMethod.trim().toLowerCase() == 'credit';
    final transactionRef = isUnpaidCredit ? null : _transactions(farmId).doc();

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
        ..addAll({if (transactionRef != null) 'transactionId': transactionRef.id}),
    );

    if (transactionRef != null) {
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
    }

    final activitySubtitle =
        '${expense.category} · ₹${expense.amount.toStringAsFixed(0)}'
        '${expense.supplierName != null && expense.supplierName!.trim().isNotEmpty ? ' · ${expense.supplierName}' : ''}';

    batch.set(activityRef, {
      'type': ActivityType.expenseAdded.name,
      'title': 'Expense Added',
      'subtitle': activitySubtitle,
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);

    // Surfaces this to the owner's Notification screen when a partner
    // added the expense — see FirestoreService.notifyPartnerActivity.
    unawaited(FirestoreService.instance.notifyPartnerActivity(
      farmId: farmId,
      type: ActivityType.expenseAdded,
      title: 'Expense Added',
      subtitle: activitySubtitle,
      module: 'finance',
      actor: actor,
    ));
  }

  /// Updates an expense in place. The mirrored `transactions` doc is
  /// updated to match so aggregation stays correct — this does not
  /// create a second transaction.
  ///
  /// A credit purchase has no mirrored transaction at all (see
  /// [addExpense]), so editing one that is still on credit does not
  /// invent one — and if the payment method changes away from Credit
  /// here (the person realizes it was actually paid), a transaction is
  /// created now so it starts counting as a cash expense. The reverse
  /// (changing a paid expense to Credit) voids the existing mirrored
  /// transaction so it stops counting.
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
    final isCreditNow = updated.paymentMethod.trim().toLowerCase() == 'credit';

    final batch = _db.batch();
    final expenseUpdateMap = Map<String, dynamic>.from(updated.toUpdateMap());

    if (transactionId.isNotEmpty) {
      if (isCreditNow) {
        // No longer a cash outflow — drop the mirrored transaction so
        // it stops counting toward Net Cash Flow / the Cash-Online
        // tracker, the same as it never being created in the first
        // place for a new credit purchase.
        batch.update(_transactions(farmId).doc(transactionId), {
          'status': 'voided',
        });
      } else {
        batch.update(_transactions(farmId).doc(transactionId), {
          'amount': updated.amount,
          'category': updated.category,
          'note': updated.title.trim(),
          'paymentMethod': updated.paymentMethod,
          'date': Timestamp.fromDate(updated.date),
          'status': 'active',
        });
      }
    } else if (!isCreditNow) {
      // Was Credit (so no mirrored transaction was ever created) and
      // is now actually paid — create it now, exactly like addExpense
      // would have if this payment method had been chosen originally.
      final newTransactionRef = _transactions(farmId).doc();
      batch.set(newTransactionRef, {
        'amount': updated.amount,
        'isIncome': false,
        'category': updated.category,
        'note': updated.title.trim(),
        'paymentMethod': updated.paymentMethod,
        'date': Timestamp.fromDate(updated.date),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'referenceType': 'expense',
        'referenceId': expenseRef.id,
      });
      expenseUpdateMap['transactionId'] = newTransactionRef.id;
    }

    batch.update(expenseRef, expenseUpdateMap);

    final actor = await FirestoreService.instance.getCurrentActor();
    final activityRef = _activities(farmId).doc();
    final activitySubtitle = '${updated.title} · ₹${updated.amount.toStringAsFixed(0)}';
    batch.set(activityRef, {
      'type': ActivityType.expenseAdded.name,
      'title': 'Expense Updated',
      'subtitle': activitySubtitle,
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);

    unawaited(FirestoreService.instance.notifyPartnerActivity(
      farmId: farmId,
      type: ActivityType.expenseAdded,
      title: 'Expense Updated',
      subtitle: activitySubtitle,
      module: 'finance',
      actor: actor,
    ));
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
    final activitySubtitle = '${expense.title} · ₹${expense.amount.toStringAsFixed(0)}';
    batch.set(activityRef, {
      'type': ActivityType.expenseVoided.name,
      'title': 'Expense Voided',
      'subtitle': activitySubtitle,
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);

    unawaited(FirestoreService.instance.notifyPartnerActivity(
      farmId: farmId,
      type: ActivityType.expenseVoided,
      title: 'Expense Voided',
      subtitle: activitySubtitle,
      module: 'finance',
      actor: actor,
    ));
  }

  /// Live expense list for a date range. Filtered to a single field
  /// (`date`) server-side — the same field it's ordered by — so no
  /// composite Firestore index is required. `status`/`category` are
  /// filtered client-side, which is fine at farm-app data volumes; if
  /// this ever needs to scale up, add a composite index on
  /// (status, date) and move that filter server-side.
  ///
  /// [scope] limits the list to one side of the Finance tab (Palai or
  /// Trading). Null keeps the old behaviour: every expense.
  Stream<List<ExpenseModel>> expensesStream(
      String farmId, {
        DateTime? start,
        DateTime? end,
        String? category,
        bool includeVoided = false,
        FinanceScope? scope,
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
      if (scope != null) {
        items = items
            .where(
              (e) => FinanceScopeRules.expenseBelongsTo(
            scope,
            referenceType: e.referenceType,
            category: e.category,
          ),
        )
            .toList();
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

    final activitySubtitle = '$category · ₹${amount.toStringAsFixed(0)}';
    batch.set(activityRef, {
      'type': ActivityType.revenueAdded.name,
      'title': 'Revenue Added',
      'subtitle': activitySubtitle,
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    });

    await batch.commit().timeout(_timeout);

    unawaited(FirestoreService.instance.notifyPartnerActivity(
      farmId: farmId,
      type: ActivityType.revenueAdded,
      title: 'Revenue Added',
      subtitle: activitySubtitle,
      module: 'finance',
      actor: actor,
    ));
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
    final activitySubtitle = '$category · ₹${amount.toStringAsFixed(0)}';
    await _activities(farmId).add({
      'type': ActivityType.revenueAdded.name,
      'title': 'Revenue Updated',
      'subtitle': activitySubtitle,
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    }).timeout(_timeout);

    unawaited(FirestoreService.instance.notifyPartnerActivity(
      farmId: farmId,
      type: ActivityType.revenueAdded,
      title: 'Revenue Updated',
      subtitle: activitySubtitle,
      module: 'finance',
      actor: actor,
    ));
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
    final activitySubtitle =
        '${transactionData['category'] ?? ''} · ₹${((transactionData['amount'] ?? 0) as num).toStringAsFixed(0)}';
    await _activities(farmId).add({
      'type': ActivityType.revenueVoided.name,
      'title': 'Revenue Voided',
      'subtitle': activitySubtitle,
      'module': 'finance',
      'timestamp': FieldValue.serverTimestamp(),
      if (actor != null) 'actorUid': actor.uid,
      if (actor != null) 'actorName': actor.name,
      if (actor != null) 'actorRole': actor.role,
    }).timeout(_timeout);

    unawaited(FirestoreService.instance.notifyPartnerActivity(
      farmId: farmId,
      type: ActivityType.revenueVoided,
      title: 'Revenue Voided',
      subtitle: activitySubtitle,
      module: 'finance',
      actor: actor,
    ));
  }

  /// Live revenue (income) list for a date range — reads the *existing*
  /// shared `transactions` collection, so customer payments generated by
  /// createMonthlyBill / receivePalaiPayment / MonthlyBillingService show
  /// up automatically alongside manual revenue, with zero duplication.
  ///
  /// [scope] limits the list to one side of the Finance tab (Palai or
  /// Trading). Null keeps the old behaviour: all revenue.
  Stream<List<FinanceTransactionRow>> revenueStream(
      String farmId, {
        DateTime? start,
        DateTime? end,
        String? category,
        FinanceScope? scope,
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
          .where((d) => _isIncomeTransaction(d.data()))
          .where((d) => d.data()['status'] != 'voided')
          .where(
            (d) =>
        scope == null ||
            FinanceScopeRules.revenueMapBelongsTo(scope, d.data()),
      )
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
  ///
  /// [scope] = [FinanceScope.palai] leaves Trading records out (goat
  /// sales, goat purchases, goat-sale credit) so the Palai side shows
  /// only Palai money. Null keeps the old all-in-one behaviour. The
  /// Trading side has its own method: [getTradingFinanceSummary].
  Future<FinanceSummary> getFinanceSummary(
      String farmId, {
        required DateTime start,
        required DateTime end,
        FinanceScope? scope,
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
    double cashReceived = 0;
    double onlineReceived = 0;
    final revenueByCategory = <String, double>{};

    for (final doc in transactionsSnap.docs) {
      final data = doc.data();
      if (!_isIncomeTransaction(data)) continue;
      if (data['status'] == 'voided') continue;
      if (scope != null && !FinanceScopeRules.revenueMapBelongsTo(scope, data)) {
        continue;
      }
      final amount = (data['amount'] ?? 0).toDouble();
      revenue += amount;
      final category = (data['category'] ?? 'Other').toString();
      revenueByCategory[category] = (revenueByCategory[category] ?? 0) + amount;

      final paymentMethod = (data['paymentMethod'] ?? '').toString();
      if (FinancePaymentMethods.isCash(paymentMethod)) {
        cashReceived += amount;
      } else if (FinancePaymentMethods.isOnline(paymentMethod)) {
        onlineReceived += amount;
      }
    }

    double expenses = 0;
    final expenseByCategory = <String, double>{};

    for (final doc in expensesSnap.docs) {
      final data = doc.data();
      if (data['status'] == 'voided') continue;
      // Not yet paid — a liability owed to the supplier, not cash out
      // the door. See ExpenseModel.isUnpaidCredit.
      if ((data['paymentMethod'] ?? '').toString().trim().toLowerCase() ==
          'credit') {
        continue;
      }
      if (scope != null && !FinanceScopeRules.expenseMapBelongsTo(scope, data)) {
        continue;
      }
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

    // Goat-sale balances customers still owe (Trading). A delivered sale
    // with money still owed carries a Partial / Pending paymentStatus, so
    // this reads only the unsettled ones. Collecting a balance
    // (SalesService.receiveBalancePayment) brings this figure down.
    //
    // Left out on the Palai side: that money belongs to Trading.
    if (scope != FinanceScope.palai) {
      final unpaidSalesSnap = await _sales(farmId)
          .where(
        'paymentStatus',
        whereIn: [
          Sale.paymentStatusPartial,
          Sale.paymentStatusPending,
        ],
      )
          .get()
          .timeout(_timeout);

      for (final doc in unpaidSalesSnap.docs) {
        final sale = Sale.fromDoc(doc);

        if (sale.canCollectBalance) {
          totalOutstanding += sale.billBalanceDue;
        }
      }
    }

    return FinanceSummary(
      revenue: revenue,
      expenses: expenses,
      totalOutstanding: totalOutstanding,
      totalAdvance: totalAdvance,
      revenueByCategory: revenueByCategory,
      expenseByCategory: expenseByCategory,
      cashReceived: cashReceived,
      onlineReceived: onlineReceived,
    );
  }

  /// Combined recent-transactions feed for the Overview screen — merges
  /// the last [limit] income rows and expense rows into one
  /// newest-first list.
  ///
  /// [scope] limits the feed to one side of the Finance tab. When a scope
  /// is given, more rows are fetched before filtering so the other side's
  /// records can't crowd the list out.
  Future<List<FinanceTransactionRow>> getRecentTransactions(
      String farmId, {
        int limit = 10,
        FinanceScope? scope,
      }) async {
    final fetchLimit = scope == null ? limit : limit * 6;

    final incomeSnap = await _transactions(farmId)
        .orderBy('date', descending: true)
        .limit(fetchLimit)
        .get()
        .timeout(_timeout);

    final expenseSnap = await _expenses(farmId)
        .orderBy('date', descending: true)
        .limit(fetchLimit)
        .get()
        .timeout(_timeout);

    final rows = <FinanceTransactionRow>[];

    for (final doc in incomeSnap.docs) {
      final data = doc.data();
      if (!_isIncomeTransaction(data)) continue;
      if (data['status'] == 'voided') continue;
      if (scope != null && !FinanceScopeRules.revenueMapBelongsTo(scope, data)) {
        continue;
      }
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
      // Not yet paid — excluded from the cash-movements feed, same as
      // every other cash-based Finance total. See ExpenseModel.
      // isUnpaidCredit.
      if (expense.isUnpaidCredit) continue;
      if (scope != null &&
          !FinanceScopeRules.expenseBelongsTo(
            scope,
            referenceType: expense.referenceType,
            category: expense.category,
          )) {
        continue;
      }
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
  // TRADING FINANCE SUMMARY
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _tradingPurchases(
      String farmId,
      ) =>
      _farms().doc(farmId).collection('tradingPurchases');

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Finance figures for the Trading side, for [start, end).
  ///
  /// Reads only Trading records (see [FinanceScopeRules]):
  ///   * `transactions`     income tagged as a goat sale
  ///   * `expenses`         Goat Purchase expenses
  ///   * `tradingPurchases` transport / loading / unloading / other costs
  ///                        of purchases made in the range (these are not
  ///                        written to `expenses`, so nothing is counted
  ///                        twice)
  ///   * `sales`            goat-sale balances still owed (current balance)
  Future<TradingFinanceSummary> getTradingFinanceSummary(
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

    final purchasesSnap = await _tradingPurchases(farmId)
        .where('purchaseDate', isGreaterThanOrEqualTo: startTs)
        .where('purchaseDate', isLessThan: endTs)
        .get()
        .timeout(_timeout);

    // ---- Sales revenue ------------------------------------------------
    double salesRevenue = 0;
    double cashReceived = 0;
    double onlineReceived = 0;
    final revenueByCategory = <String, double>{};
    final saleIds = <String>{};

    for (final doc in transactionsSnap.docs) {
      final data = doc.data();
      if (!_isIncomeTransaction(data)) continue;
      if (data['status'] == 'voided') continue;
      if (!FinanceScopeRules.revenueMapBelongsTo(FinanceScope.trading, data)) {
        continue;
      }

      final amount = _num(data['amount']);
      salesRevenue += amount;

      final category = (data['category'] ?? 'Other').toString();
      revenueByCategory[category] = (revenueByCategory[category] ?? 0) + amount;

      final saleId = (data['referenceId'] ?? '').toString();
      if (saleId.isNotEmpty) saleIds.add(saleId);

      final method = (data['paymentMethod'] ?? '').toString();
      if (FinancePaymentMethods.isCash(method)) {
        cashReceived += amount;
      } else if (FinancePaymentMethods.isOnline(method)) {
        onlineReceived += amount;
      }
    }

    // ---- Goat purchase spend -------------------------------------------
    double purchaseSpend = 0;
    double cashPaid = 0;
    double onlinePaid = 0;
    final expenseByCategory = <String, double>{};

    for (final doc in expensesSnap.docs) {
      final data = doc.data();
      if (data['status'] == 'voided') continue;
      // Not yet paid — see ExpenseModel.isUnpaidCredit.
      if ((data['paymentMethod'] ?? '').toString().trim().toLowerCase() ==
          'credit') {
        continue;
      }
      if (!FinanceScopeRules.expenseMapBelongsTo(FinanceScope.trading, data)) {
        continue;
      }

      final amount = _num(data['amount']);
      purchaseSpend += amount;

      final category = (data['category'] ?? 'Other').toString();
      expenseByCategory[category] = (expenseByCategory[category] ?? 0) + amount;

      final method = (data['paymentMethod'] ?? '').toString();
      if (FinancePaymentMethods.isCash(method)) {
        cashPaid += amount;
      } else if (FinancePaymentMethods.isOnline(method)) {
        onlinePaid += amount;
      }
    }

    // ---- Purchase extras (transport etc.) ------------------------------
    double otherPurchaseCosts = 0;
    int goatsPurchased = 0;

    for (final doc in purchasesSnap.docs) {
      final data = doc.data();
      otherPurchaseCosts += _num(data['totalTransportExpenses']);
      goatsPurchased += _num(data['totalGoats']).toInt();
    }

    if (otherPurchaseCosts > 0) {
      expenseByCategory['Transport & Other'] = otherPurchaseCosts;
    }

    // ---- Goat-sale credit (current balance, not a period total) --------
    double receivable = 0;
    int receivableCount = 0;

    final unpaidSalesSnap = await _sales(farmId)
        .where(
      'paymentStatus',
      whereIn: [
        Sale.paymentStatusPartial,
        Sale.paymentStatusPending,
      ],
    )
        .get()
        .timeout(_timeout);

    for (final doc in unpaidSalesSnap.docs) {
      final sale = Sale.fromDoc(doc);

      if (sale.canCollectBalance && sale.billBalanceDue > 0) {
        receivable += sale.billBalanceDue;
        receivableCount++;
      }
    }

    return TradingFinanceSummary(
      salesRevenue: salesRevenue,
      purchaseSpend: purchaseSpend,
      otherPurchaseCosts: otherPurchaseCosts,
      receivable: receivable,
      receivableCount: receivableCount,
      cashReceived: cashReceived,
      onlineReceived: onlineReceived,
      cashPaid: cashPaid,
      onlinePaid: onlinePaid,
      salesCount: saleIds.length,
      purchaseCount: purchasesSnap.docs.length,
      goatsPurchased: goatsPurchased,
      revenueByCategory: revenueByCategory,
      expenseByCategory: expenseByCategory,
    );
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
  // FINAL CHECKOUT — PAYMENT HISTORY
  //
  // Read-only aggregation over the customer's existing `payments` docs,
  // the same source [getCustomerLedger] already reads. The Final
  // Checkout Report's balance figures (pendingAmount/paidAmount/
  // advanceAfter) are NOT recomputed here — they're carried straight
  // through from the [MonthlyBillResult] that FirestoreService.
  // createMonthlyBill() already returned for this exact checkout, which
  // is itself the atomic write against pendingAmount/advanceAmount.
  // This method only builds the payment-history table shown alongside
  // that balance — it never sums payments a second time into the
  // balance itself (spec: don't double-count what the live customer
  // balance already incorporates).
  // ---------------------------------------------------------------------

  /// Every payment received from this customer, oldest first.
  Future<List<FinalPaymentHistoryRow>> getCustomerPaymentHistory({
    required String farmId,
    required String customerId,
  }) async {
    final paymentsSnap = await _payments(farmId)
        .where('customerId', isEqualTo: customerId)
        .get()
        .timeout(_timeout);

    final paymentHistory = <FinalPaymentHistoryRow>[];
    for (final doc in paymentsSnap.docs) {
      final data = doc.data();
      // "Outstanding Added" payment docs represent money now OWED, not
      // received — never show them as a payment (same rule the
      // Customer Ledger and Customer Profile already follow).
      if ((data['type'] ?? '').toString() == 'outstandingAdded') continue;

      final amount = ((data['amount'] ?? 0) as num).toDouble();
      paymentHistory.add(
        FinalPaymentHistoryRow(
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          paymentNumber: (data['paymentNumber'] ?? '').toString(),
          method: (data['paymentMethod'] ?? '').toString(),
          amount: amount,
          status: 'Paid',
        ),
      );
    }
    paymentHistory.sort((a, b) => a.date.compareTo(b.date));

    return paymentHistory;
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