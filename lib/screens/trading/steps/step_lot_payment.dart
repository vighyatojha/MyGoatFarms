import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 3 — Supplier Payment.
///
/// How much is being paid to the supplier RIGHT NOW. Anything from 0 up to
/// the full purchase amount is allowed:
///
///   0            -> lot is Unpaid
///   part         -> lot is Partial
///   full amount  -> lot is Paid
///
/// More payments can be added at any time from Lot Detail, so a lot never
/// has to be settled here. The status and the remaining balance are always
/// worked out from the amount typed — never entered by hand.
///
/// The amount field starts empty and must be filled in (0 is fine), so
/// "nothing paid" is always a deliberate choice rather than a forgotten
/// field.
class StepLotPayment extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PurchaseDraft draft;

  const StepLotPayment({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<StepLotPayment> createState() => _StepLotPaymentState();
}

class _StepLotPaymentState extends State<StepLotPayment> {
  late final TextEditingController _paidController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _paidController = TextEditingController(
      text: draft.paidNowEntered
          ? PurchaseCosting.formatNumber(draft.paidNow)
          : '',
    );

    _noteController = TextEditingController(text: draft.paymentNote);
  }

  @override
  void dispose() {
    _paidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onPaidChanged(String value) {
    final draft = widget.draft;
    final text = value.trim();

    setState(() {
      draft.paidNowEntered = text.isNotEmpty;
      draft.paidNow = double.tryParse(text) ?? 0;
    });
  }

  void _setAmount(double amount) {
    final draft = widget.draft;

    _paidController.text = PurchaseCosting.formatNumber(amount);
    _paidController.selection = TextSelection.collapsed(
      offset: _paidController.text.length,
    );

    setState(() {
      draft.paidNowEntered = true;
      draft.paidNow = amount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final total = draft.purchaseAmount;

    final Color statusColor;
    switch (draft.paymentStatus) {
      case 'Paid':
        statusColor = AppColors.success;
        break;
      case 'Partial':
        statusColor = const Color(0xFFB26A00);
        break;
      default:
        statusColor = AppColors.error;
    }

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardResultCard(
            icon: Icons.receipt_long_outlined,
            title: 'Amount payable to supplier',
            formula: 'Goat cost only — transport and other costs are not '
                'part of the supplier balance',
            value: wizardCurrency(total),
          ),

          const SizedBox(height: 14),

          WizardSectionCard(
            title: 'Paid Now',
            icon: Icons.payments_outlined,
            children: [
              wizardField(
                controller: _paidController,
                label: 'Amount Paid Now',
                hint: 'Enter 0 if nothing is paid yet',
                icon: Icons.currency_rupee_rounded,
                keyboardType: wizardDecimalKeyboard,
                inputFormatters: wizardDecimalFormatters(),
                textInputAction: TextInputAction.done,
                onChanged: _onPaidChanged,
                validator: (value) {
                  final text = value?.trim() ?? '';

                  if (text.isEmpty) {
                    return 'Enter the amount paid (0 if none)';
                  }

                  final number = double.tryParse(text);

                  if (number == null || number < 0) {
                    return 'Enter a valid amount';
                  }

                  if (number > total + 0.005) {
                    return 'Cannot be more than ${wizardCurrency(total)}';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QuickAmountChip(
                    label: 'Nothing yet',
                    onTap: () => _setAmount(0),
                  ),
                  _QuickAmountChip(
                    label: 'Half',
                    onTap: () => _setAmount(
                      PurchaseCosting.round2(total / 2),
                    ),
                  ),
                  _QuickAmountChip(
                    label: 'Full amount',
                    onTap: () => _setAmount(total),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text(
                'Payment Method',
                style: AppTheme.body(size: 11),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _MethodOption(
                      title: 'Cash',
                      icon: Icons.money_rounded,
                      selected: draft.paymentMethod == 'Cash',
                      onTap: () => setState(
                            () => draft.setPaymentMethod('Cash'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MethodOption(
                      title: 'Online',
                      icon: Icons.account_balance_wallet_outlined,
                      selected: draft.paymentMethod == 'Online',
                      onTap: () => setState(
                            () => draft.setPaymentMethod('Online'),
                      ),
                    ),
                  ),
                ],
              ),

              if (draft.paidNow <= 0 && draft.paidNowEntered) ...[
                const SizedBox(height: 10),
                Text(
                  'No payment is made now, so the method is not used. You '
                      'choose it when you add a payment later.',
                  style: AppTheme.body(size: 11),
                ),
              ],

              const SizedBox(height: 14),

              wizardField(
                controller: _noteController,
                label: 'Payment Note',
                hint: 'e.g. Advance to Ramesh',
                icon: Icons.notes_rounded,
                optional: true,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                onChanged: (value) {
                  draft.paymentNote = value;
                },
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ---------------------------------------------------------------
          // LIVE STATUS — derived, never typed
          // ---------------------------------------------------------------

          WizardSectionCard(
            title: 'Payment Status',
            icon: Icons.account_balance_wallet_outlined,
            children: [
              Row(
                children: [
                  Text(
                    'Status',
                    style: AppTheme.body(size: 13, color: AppColors.textGrey),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      draft.paidNowEntered ? draft.paymentStatus : '—',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: draft.paidNowEntered
                            ? statusColor
                            : AppColors.textGrey,
                      ),
                    ),
                  ),
                ],
              ),
              WizardComputedRow(
                label: 'Purchase Amount',
                value: wizardCurrency(total),
              ),
              WizardComputedRow(
                label: 'Paid Now',
                value: wizardCurrency(draft.paidNowEntered ? draft.paidNow : 0),
              ),
              const Divider(height: 18, color: AppColors.divider),
              WizardComputedRow(
                label: 'Remaining Balance',
                value: wizardCurrency(
                  draft.paidNowEntered ? draft.dueAfterPayment : total,
                ),
                emphasize: true,
              ),
            ],
          ),

          if (draft.paidNowEntered && draft.paymentStatus != 'Paid') ...[
            const SizedBox(height: 12),
            const WizardNote(
              'The remaining balance stays with the lot. You can add more '
                  'payments any time from Lot Detail — each one is recorded '
                  'separately.',
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// QUICK AMOUNT CHIP
// ============================================================================

class _QuickAmountChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickAmountChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: AppTheme.body(
          size: 12,
          color: AppColors.darkGreen,
          weight: FontWeight.w600,
        ),
      ),
      backgroundColor: AppColors.lightGreen,
      side: BorderSide(color: AppColors.primaryGreen.withValues(alpha: 0.25)),
      onPressed: onTap,
    );
  }
}

// ============================================================================
// METHOD OPTION (Cash / Online)
// ============================================================================

class _MethodOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodOption({
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
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
                size: 21,
                color: selected ? AppColors.darkGreen : AppColors.textGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 13,
                    color: selected
                        ? AppColors.darkGreen
                        : AppColors.textDark,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.primaryGreen,
                ),
            ],
          ),
        ),
      ),
    );
  }
}