import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';
import '../services/monthly_statement_engine.dart';
import '../utils/billing_ledger.dart';

/// The Generate Bills button's whole flow:
///
///   1. Confirmation: "Generate September 2026 bills for 27 customers?"
///   2. Progress pop-up that cannot be dismissed, one customer at a time.
///   3. Done pop-up with the summary and a Retry failed button.
///
/// Every customer is its own all-or-nothing transaction inside
/// [MonthlyStatementEngine.runAll], so one failure never stops the
/// others, and pressing the button again is always safe.
///
/// Returns the run summary, or null when the owner cancelled or nothing
/// needed billing.
Future<BillingRunSummary?> runGenerateBillsFlow(
    BuildContext context, {
      required String farmId,
    }) async {
  final engine = MonthlyStatementEngine.instance;
  final target = engine.targetPeriodKey();
  final monthLabel = periodLabel(target);

  // -------------------------------------------------------------------------
  // 1. PLAN + CONFIRM
  // -------------------------------------------------------------------------
  List<CustomerBillingPlan> plans;
  try {
    plans = await _withLoading(
      context,
      'Checking customers…',
          () => engine.planRun(farmId: farmId, targetKey: target),
    );
  } catch (e) {
    if (context.mounted) {
      await _showMessage(
        context,
        title: 'Could not check customers',
        message: FirestoreService.instance.describeError(e),
      );
    }
    return null;
  }

  if (!context.mounted) return null;

  if (plans.isEmpty) {
    await _showMessage(
      context,
      title: 'No customers yet',
      message: 'Add a Palai customer before generating bills.',
    );
    return null;
  }

  final toBill = plans.where((p) => p.periods.isNotEmpty).toList();
  if (toBill.isEmpty) {
    await _showMessage(
      context,
      title: '$monthLabel is already billed',
      message: 'Every customer already has a bill for $monthLabel. '
          'Nothing new to generate.',
    );
    return null;
  }

  final catchUp = toBill.where((p) => p.isCatchUp).length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Generate $monthLabel bills?',
        style: AppTheme.heading(size: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${toBill.length} of ${plans.length} customer'
                '${plans.length == 1 ? '' : 's'} will be billed for '
                '$monthLabel. Customers already billed are skipped.',
            style: AppTheme.body(size: 13, color: AppColors.textDark),
          ),
          if (catchUp > 0) ...[
            const SizedBox(height: 10),
            _Note(
              icon: Icons.history,
              color: AppColors.warning,
              text: '$catchUp customer${catchUp == 1 ? ' has' : 's have'} '
                  'missed months. Those months are billed first, in order.',
            ),
          ],
          const SizedBox(height: 10),
          _Note(
            icon: Icons.info_outline,
            color: AppColors.info,
            text: 'Keep the app open until it finishes. If it is closed, '
                'press Generate Bills again to continue.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Generate bills'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return null;

  // -------------------------------------------------------------------------
  // 2. RUN (+ retry loop)
  // -------------------------------------------------------------------------
  List<String>? onlyCustomerIds;
  BillingRunSummary? lastSummary;

  while (context.mounted) {
    final summary = await _runWithProgress(
      context,
      farmId: farmId,
      target: target,
      onlyCustomerIds: onlyCustomerIds,
    );
    lastSummary = summary;
    if (!context.mounted) break;

    final retry = await _showDone(context, summary);
    if (retry != true || summary.failedCustomerIds.isEmpty) break;
    onlyCustomerIds = summary.failedCustomerIds;
  }

  return lastSummary;
}

// ===========================================================================
// PROGRESS
// ===========================================================================

Future<BillingRunSummary> _runWithProgress(
    BuildContext context, {
      required String farmId,
      required String target,
      List<String>? onlyCustomerIds,
    }) async {
  final progress = ValueNotifier<BillingRunProgress?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(
        progress: progress,
        monthLabel: periodLabel(target),
      ),
    ),
  );

  BillingRunSummary summary;
  try {
    summary = await MonthlyStatementEngine.instance.runAll(
      farmId: farmId,
      targetKey: target,
      onlyCustomerIds: onlyCustomerIds,
      onProgress: (p) => progress.value = p,
    );
  } catch (e) {
    // planRun itself failed (e.g. offline). Report it as a run with no
    // results so the Done pop-up still explains what happened.
    summary = BillingRunSummary(
      targetPeriodKey: target,
      results: const [],
      error: FirestoreService.instance.describeError(e),
    );
  } finally {
    navigator.pop();
    // Dispose only after the dialog's closing animation has finished;
    // its ValueListenableBuilder is still listening until then.
    Future<void>.delayed(
      const Duration(milliseconds: 600),
      progress.dispose,
    );
  }

  return summary;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({
    required this.progress,
    required this.monthLabel,
  });

  final ValueNotifier<BillingRunProgress?> progress;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Generating $monthLabel bills',
        style: AppTheme.heading(size: 17),
      ),
      content: ValueListenableBuilder<BillingRunProgress?>(
        valueListenable: progress,
        builder: (context, p, _) {
          final fraction = p == null || p.total == 0
              ? null
              : (p.index - 1) / p.total;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  color: AppColors.primaryGreen,
                  backgroundColor: AppColors.lightGreen,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                p == null
                    ? 'Getting ready…'
                    : 'Generating ${p.index} of ${p.total}',
                style: AppTheme.heading(size: 14),
              ),
              const SizedBox(height: 2),
              Text(
                p == null
                    ? ' '
                    : p.periodKey == null
                    ? p.customerName
                    : '${p.customerName} · ${periodLabel(p.periodKey!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// DONE
// ===========================================================================

/// Returns true when the owner pressed Retry failed.
Future<bool?> _showDone(BuildContext context, BillingRunSummary summary) {
  final monthLabel = periodLabel(summary.targetPeriodKey);
  final failures = summary.failures;
  final hasFailures = failures.isNotEmpty || summary.error != null;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(
            hasFailures ? Icons.error_outline : Icons.check_circle,
            color: hasFailures ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasFailures ? 'Finished with problems' : 'Done',
              style: AppTheme.heading(size: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.error != null)
              Text(
                'The run could not start: ${summary.error}',
                style: AppTheme.body(size: 13, color: AppColors.error),
              )
            else ...[
              Text(
                '$monthLabel billing',
                style: AppTheme.body(size: 12),
              ),
              const SizedBox(height: 10),
              _CountRow(
                label: 'Bills generated',
                value: summary.billsGenerated,
                color: AppColors.success,
              ),
              _CountRow(
                label: 'Already billed',
                value: summary.alreadyBilledCustomers,
                color: AppColors.textGrey,
              ),
              _CountRow(
                label: 'Nothing to bill',
                value: summary.nothingToBillCustomers,
                color: AppColors.textGrey,
              ),
              _CountRow(
                label: 'Failed',
                value: summary.failedCustomers,
                color: AppColors.error,
              ),
              if (summary.billsGenerated > summary.generatedCustomers) ...[
                const SizedBox(height: 6),
                Text(
                  'Includes missed months for some customers.',
                  style: AppTheme.body(size: 11),
                ),
              ],
              if (failures.isNotEmpty) ...[
                const Divider(height: 22),
                for (final failure in failures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          failure.customerName,
                          style: AppTheme.heading(size: 13),
                        ),
                        Text(
                          _failureReason(failure),
                          style: AppTheme.body(size: 11.5),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Nothing was written for a failed customer. '
                      'Retry failed tries just those again.',
                  style: AppTheme.body(size: 11),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (failures.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retry failed'),
          ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

String _failureReason(CustomerRunResult result) {
  for (final outcome in result.outcomes) {
    if (outcome.kind == StatementOutcomeKind.failed) {
      final month = periodLabel(outcome.periodKey);
      return outcome.message.isEmpty ? '$month failed.' : '$month: ${outcome.message}';
    }
  }
  return 'Failed.';
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(size: 13, color: AppColors.textDark),
            ),
          ),
          Text(
            '$value',
            style: AppTheme.heading(
              size: 15,
              color: value == 0 ? AppColors.textGrey : color,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// SMALL HELPERS
// ===========================================================================

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(size: 11.5, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

Future<T> _withLoading<T>(
    BuildContext context,
    String message,
    Future<T> Function() task,
    ) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: AppTheme.body(size: 13, color: AppColors.textDark),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

Future<void> _showMessage(
    BuildContext context, {
      required String title,
      required String message,
    }) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: AppTheme.heading(size: 17)),
      content: Text(
        message,
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ===========================================================================
// SYNC BILLS
// ===========================================================================

/// The Sync bills button's flow, for after bills were already generated:
///
///   1. Analyse every customer (nothing is written).
///   2. Review: bills to generate (new customers / months), bills to
///      rebuild (goats added, deleted or changed since the bill), and
///      anything that needs the owner (with what to do).
///   3. Apply: one customer at a time, then a Done summary.
Future<void> runSyncBillsFlow(
    BuildContext context, {
      required String farmId,
    }) async {
  final engine = MonthlyStatementEngine.instance;

  List<BillSyncItem> items;
  try {
    items = await _withLoading(
      context,
      'Checking every customer\u2019s bill against their goats\u2026',
          () => engine.analyseSync(farmId: farmId),
    );
  } catch (e) {
    if (context.mounted) {
      await _showMessage(
        context,
        title: 'Could not check bills',
        message: FirestoreService.instance.describeError(e),
      );
    }
    return;
  }
  if (!context.mounted) return;

  if (items.isEmpty) {
    await _showMessage(
      context,
      title: 'Everything is up to date',
      message: 'Every customer is billed for '
          '${periodLabel(engine.targetPeriodKey())}, and every bill matches '
          'the goats on the farm.',
    );
    return;
  }

  final automatic = items.where((i) => i.isAutomatic).toList();
  final apply = await showDialog<bool>(
    context: context,
    builder: (_) => _SyncReviewDialog(items: items),
  );
  if (apply != true || automatic.isEmpty || !context.mounted) return;

  // ------------------------------------------------------------- apply
  final progress = ValueNotifier<String>('Getting ready\u2026');
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Syncing bills', style: AppTheme.heading(size: 17)),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, text, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(
                minHeight: 6,
                color: AppColors.primaryGreen,
                backgroundColor: AppColors.lightGreen,
              ),
              const SizedBox(height: 14),
              Text(text, style: AppTheme.body(size: 13, color: AppColors.textDark)),
            ],
          ),
        ),
      ),
    ),
  );

  List<BillSyncResult> results;
  try {
    results = await engine.applySync(
      farmId: farmId,
      items: items,
      onProgress: (index, total, name) =>
      progress.value = 'Customer $index of $total \u00b7 $name',
    );
  } catch (e) {
    results = [
      BillSyncResult(
        customerName: 'Sync',
        ok: false,
        message: FirestoreService.instance.describeError(e),
      ),
    ];
  } finally {
    navigator.pop();
    Future<void>.delayed(const Duration(milliseconds: 600), progress.dispose);
  }

  if (!context.mounted) return;
  final failed = results.where((r) => !r.ok).toList();
  final attention = items.length - automatic.length;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(
            failed.isEmpty ? Icons.check_circle : Icons.error_outline,
            color: failed.isEmpty ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              failed.isEmpty ? 'Done' : 'Finished with problems',
              style: AppTheme.heading(size: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in results)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.customerName, style: AppTheme.heading(size: 13)),
                    Text(
                      r.message,
                      style: AppTheme.body(
                        size: 11.5,
                        color: r.ok ? AppColors.textDark : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            if (attention > 0) ...[
              const Divider(height: 18),
              Text(
                '$attention customer${attention == 1 ? '' : 's'} still need '
                    'your attention (see the review list). Press Sync bills '
                    'again any time to re-check.',
                style: AppTheme.body(size: 11.5),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _SyncReviewDialog extends StatelessWidget {
  const _SyncReviewDialog({required this.items});

  final List<BillSyncItem> items;

  @override
  Widget build(BuildContext context) {
    final generate =
    items.where((i) => i.kind == BillSyncKind.generate).toList();
    final rebuild = items.where((i) => i.kind == BillSyncKind.rebuild).toList();
    final attention =
    items.where((i) => i.kind == BillSyncKind.attention).toList();
    final automaticCount = generate.length + rebuild.length;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Sync bills', style: AppTheme.heading(size: 18)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (generate.isNotEmpty)
              _section(
                'New bills to generate (${generate.length})',
                AppColors.success,
                generate,
                showAmounts: false,
              ),
            if (rebuild.isNotEmpty)
              _section(
                'Bills to rebuild (${rebuild.length})',
                AppColors.info,
                rebuild,
                showAmounts: true,
                intro: 'Deleted and generated again from the goats on the '
                    'farm now. Payments for older months are not touched.',
              ),
            if (attention.isNotEmpty)
              _section(
                'Needs your attention (${attention.length})',
                AppColors.warning,
                attention,
                showAmounts: true,
                intro: 'Not changed automatically.',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(automaticCount == 0 ? 'Close' : 'Cancel'),
        ),
        if (automaticCount > 0)
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('Apply $automaticCount'),
          ),
      ],
    );
  }

  Widget _section(
      String title,
      Color color,
      List<BillSyncItem> list, {
        required bool showAmounts,
        String? intro,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.heading(size: 13.5, color: color)),
          if (intro != null) ...[
            const SizedBox(height: 2),
            Text(intro, style: AppTheme.body(size: 11)),
          ],
          const SizedBox(height: 6),
          for (final item in list)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showAmounts
                        ? '${item.customerName} \u00b7 ${periodLabel(item.periodKey)}'
                        : item.customerName,
                    style: AppTheme.heading(size: 12.5),
                  ),
                  if (showAmounts &&
                      (item.oldAmount - item.newAmount).abs() > 0.5)
                    Text(
                      'Palai \u20b9${item.oldAmount.toStringAsFixed(0)} \u2192 '
                          '\u20b9${item.newAmount.toStringAsFixed(0)}',
                      style: AppTheme.body(size: 11.5, color: AppColors.textDark),
                    ),
                  for (final change in item.changes)
                    Text('\u2022 $change', style: AppTheme.body(size: 11)),
                  if (item.note != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.note!,
                      style: AppTheme.body(size: 11, color: AppColors.textDark),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}