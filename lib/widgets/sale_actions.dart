import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/sale_model.dart';
import 'package:mygoatfarms/services/sale_adjustment_service.dart';

/// What a sale action did, so the screen knows whether to reload or leave.
enum SaleActionResult { none, edited, cancelled, deleted }

/// Edit / Cancel Deal / Delete menu for one sale.
///
/// Drop it into an AppBar or a card header. [onResult] runs after a
/// successful action; for [SaleActionResult.cancelled] and
/// [SaleActionResult.deleted] the sale no longer exists, so a screen that
/// shows only that sale should close itself.
class SaleActionsMenu extends StatelessWidget {
  final String farmId;
  final Sale sale;
  final ValueChanged<SaleActionResult> onResult;
  final Color? iconColor;

  const SaleActionsMenu({
    super.key,
    required this.farmId,
    required this.sale,
    required this.onResult,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final service = SaleAdjustmentService.instance;
    final canCancel = service.canCancel(sale);

    return PopupMenuButton<String>(
      tooltip: 'Sale options',
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: (value) async {
        final result = await switch (value) {
          'edit' => showEditSaleSheet(context, farmId: farmId, sale: sale),
          'cancel' => showCancelDealDialog(context, farmId: farmId, sale: sale),
          _ => showDeleteSaleDialog(context, farmId: farmId, sale: sale),
        };

        if (result != SaleActionResult.none) onResult(result);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit sale'),
          ),
        ),
        if (canCancel)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cancel_outlined),
              title: Text('Cancel deal'),
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text(
              'Delete sale',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ),
      ],
    );
  }
}

/// Visible "Edit" and "Cancel Deal" buttons for a deal that has not been
/// delivered yet (Booking / Holding or Wait for Delivery).
///
/// Shows nothing for a sale that is already delivered, so it is safe to
/// drop under any sale row. [onResult] runs after a successful action;
/// after [SaleActionResult.cancelled] the sale no longer exists.
class OpenDealButtons extends StatelessWidget {
  final String farmId;
  final Sale sale;
  final ValueChanged<SaleActionResult>? onResult;

  const OpenDealButtons({
    super.key,
    required this.farmId,
    required this.sale,
    this.onResult,
  });

  @override
  Widget build(BuildContext context) {
    if (!SaleAdjustmentService.instance.canCancel(sale)) {
      return const SizedBox.shrink();
    }

    Future<void> run(
        Future<SaleActionResult> Function() action,
        ) async {
      final result = await action();
      if (result != SaleActionResult.none) onResult?.call(result);
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => run(
                  () => showEditSaleSheet(context, farmId: farmId, sale: sale),
            ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: const BorderSide(color: AppColors.primaryGreen),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => run(
                  () => showCancelDealDialog(
                context,
                farmId: farmId,
                sale: sale,
              ),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Cancel Deal'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _clean(Object e) =>
    e.toString().replaceFirst(RegExp(r'^\w*(Error|Exception): '), '');

void _snack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : null,
    ),
  );
}

// ===========================================================================
// CANCEL DEAL
// ===========================================================================

Future<SaleActionResult> showCancelDealDialog(
    BuildContext context, {
      required String farmId,
      required Sale sale,
    }) async {
  final service = SaleAdjustmentService.instance;

  if (!service.canCancel(sale)) {
    _snack(
      context,
      'Only a booking or wait-for-delivery that is not delivered yet can '
          'be cancelled.',
      error: true,
    );
    return SaleActionResult.none;
  }

  final reason = TextEditingController();
  var decision = AdvanceDecision.refund;

  final advance = sale.isBooking
      ? (sale.bookingAmount ?? 0)
      : (sale.bookingAdvanceAmount ?? 0);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Cancel this deal?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sale.id} · ${sale.customerName}\n'
                    'The goat(s) go back to stock and the booking is '
                    'removed from the delivery list.',
              ),
              if (advance > 0) ...[
                const SizedBox(height: 14),
                Text(
                  'Advance received: ₹${advance.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                RadioListTile<AdvanceDecision>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: AdvanceDecision.refund,
                  groupValue: decision,
                  title: const Text('Refund to customer'),
                  subtitle: const Text(
                    'Its Sold Goat Revenue in Finance is voided.',
                  ),
                  onChanged: (v) => setLocal(() => decision = v!),
                ),
                RadioListTile<AdvanceDecision>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: AdvanceDecision.keep,
                  groupValue: decision,
                  title: const Text('Keep the advance'),
                  subtitle: const Text(
                    'Stays as income; the customer forfeits it.',
                  ),
                  onChanged: (v) => setLocal(() => decision = v!),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep deal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel deal',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    ),
  );

  final reasonText = reason.text;
  reason.dispose();

  if (ok != true) return SaleActionResult.none;

  try {
    await service.cancelDeal(
      farmId: farmId,
      saleId: sale.id,
      advance: decision,
      reason: reasonText,
    );

    _snack(context, 'Deal cancelled. Goats are back in stock.');
    return SaleActionResult.cancelled;
  } catch (e) {
    _snack(context, _clean(e), error: true);
    return SaleActionResult.none;
  }
}

// ===========================================================================
// DELETE SALE
// ===========================================================================

Future<SaleActionResult> showDeleteSaleDialog(
    BuildContext context, {
      required String farmId,
      required Sale sale,
    }) async {
  final service = SaleAdjustmentService.instance;
  final blocked = service.deleteBlockReason(sale);

  if (blocked != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot delete this sale'),
        content: Text(blocked),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return SaleActionResult.none;
  }

  final reason = TextEditingController();
  final open = service.isOpenDeal(sale);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this sale?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sale.id} · ${sale.customerName}\n\n'
                  '• The goat(s) go back to stock.\n'
                  '${open ? '' : '• Total Sold and profit on the dashboard are reduced.\n'}'
                  '• Every Sold Goat Revenue entry for this sale is voided in '
                  'Finance, including money already collected.\n'
                  '• A copy is kept in the archive.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Delete sale',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    ),
  );

  final reasonText = reason.text;
  reason.dispose();

  if (ok != true) return SaleActionResult.none;

  try {
    await service.deleteSale(
      farmId: farmId,
      saleId: sale.id,
      reason: reasonText,
    );

    _snack(context, 'Sale deleted.');
    return SaleActionResult.deleted;
  } catch (e) {
    _snack(context, _clean(e), error: true);
    return SaleActionResult.none;
  }
}

// ===========================================================================
// EDIT SALE
// ===========================================================================

Future<SaleActionResult> showEditSaleSheet(
    BuildContext context, {
      required String farmId,
      required Sale sale,
    }) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditSaleSheet(farmId: farmId, sale: sale),
  );

  return result == true ? SaleActionResult.edited : SaleActionResult.none;
}

class _EditSaleSheet extends StatefulWidget {
  final String farmId;
  final Sale sale;

  const _EditSaleSheet({required this.farmId, required this.sale});

  @override
  State<_EditSaleSheet> createState() => _EditSaleSheetState();
}

class _EditSaleSheetState extends State<_EditSaleSheet> {
  late final TextEditingController _name =
  TextEditingController(text: widget.sale.customerName);
  late final TextEditingController _mobile =
  TextEditingController(text: widget.sale.mobile);
  late final TextEditingController _address =
  TextEditingController(text: widget.sale.address);
  late final TextEditingController _discount = TextEditingController(
    text: widget.sale.appliedDiscount > 0
        ? widget.sale.appliedDiscount.toStringAsFixed(0)
        : '',
  );
  late final TextEditingController _holding = TextEditingController(
    text: (widget.sale.holdingChargePerDay ?? 0) > 0
        ? widget.sale.holdingChargePerDay!.toStringAsFixed(0)
        : '',
  );

  bool _saving = false;

  bool get _open => SaleAdjustmentService.instance.isOpenDeal(widget.sale);

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _address.dispose();
    _discount.dispose();
    _holding.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      await SaleAdjustmentService.instance.editSale(
        farmId: widget.farmId,
        saleId: widget.sale.id,
        customerName: _name.text,
        mobile: _mobile.text,
        address: _address.text,
        discount: _open ? double.tryParse(_discount.text.trim()) ?? 0 : null,
        holdingChargePerDay: _open && widget.sale.isBooking
            ? double.tryParse(_holding.text.trim()) ?? 0
            : null,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
      _snack(context, 'Sale updated.');
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);
      _snack(context, _clean(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + inset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit sale ${widget.sale.id}',
              style: AppTheme.heading(size: 18),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Customer name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            if (_open) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _discount,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Discount (₹, off the goat amount)',
                ),
              ),
              if (widget.sale.isBooking) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _holding,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Holding charge / day (₹)',
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'Amounts on a delivered sale are not edited here. To correct '
                    'a payment, void it from the receipt, or delete the sale.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}