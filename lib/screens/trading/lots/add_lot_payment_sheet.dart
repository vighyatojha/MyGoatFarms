import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/partner_access_service.dart';
import '../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Bottom sheet for paying the supplier of a lot.
///
/// The amount can be anything from a few rupees up to the balance due.
/// Payments are append-only — each one is its own record — so the sheet
/// never edits an earlier payment.
///
/// Returns true when a payment was saved.
Future<bool?> showAddLotPaymentSheet({
  required BuildContext context,
  required String farmId,
  required TradingPurchase lot,
}) async {
  // Backstop for entry points that don't gate the button themselves
  // (e.g. the Lot Saved screen).
  if (!PartnerAccessService.instance
      .allows(PartnerPermissionKeys.tradingSupplierPayment)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You don\u2019t have permission to pay suppliers.'),
      ),
    );
    return null;
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddLotPaymentSheet(farmId: farmId, lot: lot),
  );
}

class _AddLotPaymentSheet extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const _AddLotPaymentSheet({required this.farmId, required this.lot});

  @override
  State<_AddLotPaymentSheet> createState() => _AddLotPaymentSheetState();
}

class _AddLotPaymentSheetState extends State<_AddLotPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _method = 'Cash';
  DateTime _date = DateTime.now();
  bool _saving = false;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _setAmount(double value) {
    _amountController.text = PurchaseCosting.formatNumber(value);
    _amountController.selection = TextSelection.collapsed(
      offset: _amountController.text.length,
    );
    setState(() {});
  }

  Future<void> _pickDate() async {
    final purchaseDay = DateTime(
      widget.lot.purchaseDate.year,
      widget.lot.purchaseDate.month,
      widget.lot.purchaseDate.day,
    );

    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _date,
      firstDate: purchaseDay,
      lastDate: _today,
      helpText: 'Payment date',
    );

    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      await TradingService.instance.addSupplierPayment(
        farmId: widget.farmId,
        lotDocId: widget.lot.id,
        amount: _amount,
        method: _method,
        date: _date,
        note: _noteController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      _fail(e.message?.toString() ?? 'Please check the payment.');
    } catch (e) {
      _fail(FirestoreService.instance.describeError(e));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;
    final due = lot.dueAmount;
    final after = PurchaseCosting.round2(due - _amount);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Add Supplier Payment', style: AppTheme.heading(size: 18)),
                  const SizedBox(height: 2),
                  Text(
                    '${lot.lotId} • ${lot.sellerName}',
                    style: AppTheme.body(size: 12),
                  ),
                  const SizedBox(height: 14),

                  WizardComputedRow(
                    label: 'Purchase Amount',
                    value: wizardCurrency(lot.purchaseAmount),
                  ),
                  WizardComputedRow(
                    label: 'Already Paid',
                    value: wizardCurrency(lot.paidAmount),
                  ),
                  WizardComputedRow(
                    label: 'Balance Due',
                    value: wizardCurrency(due),
                    emphasize: true,
                  ),

                  const SizedBox(height: 12),

                  wizardField(
                    controller: _amountController,
                    label: 'Amount',
                    hint: '0.00',
                    icon: Icons.currency_rupee_rounded,
                    keyboardType: wizardDecimalKeyboard,
                    inputFormatters: wizardDecimalFormatters(),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final number = double.tryParse(value?.trim() ?? '');

                      if (number == null || number <= 0) {
                        return 'Enter an amount greater than 0';
                      }

                      if (number > due + 0.005) {
                        return 'Cannot be more than ${wizardCurrency(due)}';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Half of balance'),
                        backgroundColor: AppColors.lightGreen,
                        onPressed: () =>
                            _setAmount(PurchaseCosting.round2(due / 2)),
                      ),
                      ActionChip(
                        label: const Text('Full balance'),
                        backgroundColor: AppColors.lightGreen,
                        onPressed: () => _setAmount(due),
                      ),
                    ],
                  ),

                  if (_amount > 0 && _amount <= due + 0.005) ...[
                    const SizedBox(height: 10),
                    WizardComputedRow(
                      label: 'Balance after this payment',
                      value: wizardCurrency(after < 0 ? 0 : after),
                    ),
                  ],

                  const SizedBox(height: 14),
                  Text('Payment Method', style: AppTheme.body(size: 11)),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: _MethodChoice(
                          title: 'Cash',
                          icon: Icons.money_rounded,
                          selected: _method == 'Cash',
                          onTap: () => setState(() => _method = 'Cash'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MethodChoice(
                          title: 'Online',
                          icon: Icons.account_balance_wallet_outlined,
                          selected: _method == 'Online',
                          onTap: () => setState(() => _method = 'Online'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  WizardDateField(
                    label: 'Payment Date *',
                    date: _date,
                    onTap: _pickDate,
                  ),

                  const SizedBox(height: 14),

                  wizardField(
                    controller: _noteController,
                    label: 'Note',
                    hint: 'e.g. Second instalment',
                    icon: Icons.notes_rounded,
                    optional: true,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Save Payment',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodChoice extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChoice({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.darkGreen : AppColors.textGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 13,
                    color: selected ? AppColors.darkGreen : AppColors.textDark,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.primaryGreen,
                ),
            ],
          ),
        ),
      ),
    );
  }
}