import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../../services/monthly_statement_engine.dart';
import '../../../utils/billing_ledger.dart';

/// Billing awareness for the Customer Palai goat screens.
///
/// Bills are statements for months that are already over, so a change to
/// a goat (registered with a past arrival date, price or arrival edited,
/// goat deleted) does NOT change bills that already exist. Before this,
/// the screens said nothing and the bills silently stayed wrong — e.g. a
/// deleted goat's Palai stayed on the bill, a newly added goat's
/// September days were never charged.
///
/// These helpers tell the owner exactly when that happens and what to do
/// (Sync bills rebuilds the latest bill; older months use an adjustment).

/// The last day already covered by the customer's bills, or null.
Future<DateTime?> customerBilledThrough({
  required String farmId,
  required String customerId,
}) async {
  try {
    final key = await MonthlyStatementEngine.instance.lastBilledPeriod(
      farmId: farmId,
      customerId: customerId,
    );
    if (key == null || parsePeriodKey(key) == null) return null;
    return periodEnd(key);
  } catch (_) {
    return null; // never block the screen over a notice
  }
}

/// After registering / editing a goat: if the change reaches into months
/// that are already billed, says so and how to fix the bills.
Future<void> showBilledMonthsNotice(
    BuildContext context, {
      required String farmId,
      required String customerId,
      required DateTime affectedFrom,
      required String what,
    }) async {
  final billedThrough =
  await customerBilledThrough(farmId: farmId, customerId: customerId);
  if (billedThrough == null || !context.mounted) return;

  final from = palaiDateOnlyLocal(affectedFrom);
  if (from.isAfter(billedThrough)) return; // only future months affected

  final lastMonth = DateFormat('MMMM yyyy').format(billedThrough);
  final fromText = DateFormat('d MMM yyyy').format(from);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Bills already made', style: AppTheme.heading(size: 17)),
          ),
        ],
      ),
      content: Text(
        'This $what affects $fromText onwards, but bills up to $lastMonth '
            'are already made and do not change by themselves.\n\n'
            '• Press Sync bills on the Customers screen to rebuild the '
            '$lastMonth bill with it.\n'
            '• For months before $lastMonth, add an adjustment in Monthly '
            'Bills.\n\n'
            'Later months are billed correctly on their own.',
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Extra warning lines for the Delete goat dialog (empty when none).
///
/// * The goat is on the latest bill → its Palai stays there.
/// * The goat still has days not yet billed → deleting means they are
///   never charged (Checkout charges them; delete does not).
Future<List<String>> deleteGoatBillingWarnings({
  required String farmId,
  required PalaiGoat goat,
}) async {
  final warnings = <String>[];
  final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  try {
    final engine = MonthlyStatementEngine.instance;
    final latest = await engine.latestBill(
      farmId: farmId,
      customerId: goat.customerId,
    );
    if (latest != null) {
      for (final line in latest.goatBreakdown) {
        if (line.goatId == goat.id && line.palaiAmount > 0) {
          warnings.add(
            'It is on the ${DateFormat('MMMM yyyy').format(latest.billingMonth)} '
                'bill (${money.format(line.palaiAmount)}). That bill will not '
                'change by itself: press Sync bills afterwards to rebuild it.',
          );
          break;
        }
      }
    }

    if (!goat.isCheckedOut) {
      final lastBilled = await engine.lastBilledPeriod(
        farmId: farmId,
        customerId: goat.customerId,
      );
      final unbilled = engine.unbilledChargeFor(
        goat: goat,
        lastBilledKey: lastBilled,
        upTo: DateTime.now(),
      );
      if (unbilled.amount > 0 && unbilled.fromDate != null) {
        warnings.add(
          '${unbilled.totalDays} day(s) since '
              '${DateFormat('d MMM').format(unbilled.fromDate!)} are not billed yet '
              '(${money.format(unbilled.amount)}). Deleting means they are never '
              'charged. If the goat has left the farm, use Checkout instead.',
        );
      }
    }
  } catch (_) {
    // A notice must never stop the owner from deleting.
  }
  return warnings;
}

DateTime palaiDateOnlyLocal(DateTime d) => DateTime(d.year, d.month, d.day);