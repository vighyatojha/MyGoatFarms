import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 5 — payment for a Deliver Now sale straight from a lot.
///
/// Booking and Wait for Delivery are not offered here: the handover
/// restricts them to goats that have already arrived and been registered
/// individually (Palai needs per-goat tracking), so a lot sale is always
/// handed over today. See TRADING_LOT_REFACTOR_HANDOVER.md, Step 5.
class StepLotDelivery extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final SaleDraft draft;

  const StepLotDelivery({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<StepLotDelivery> createState() => _StepLotDeliveryState();
}

enum _PayMode { paid, partial, pending }

class _StepLotDeliveryState extends State<StepLotDelivery> {
  late final TextEditingController _transportController;
  late final TextEditingController _receivedController;
  late _PayMode _mode;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    // Restore the choice when coming back to this step: not on credit =
    // fully paid; on credit with nothing received = pending; otherwise
    // partial.
    _mode = !draft.onCredit
        ? _PayMode.paid
        : (draft.amountReceived <= 0 ? _PayMode.pending : _PayMode.partial);

    _transportController = TextEditingController(
      text: draft.transportCost == 0
          ? ''
          : SaleDraft.formatWeight(draft.transportCost),
    );

    _receivedController = TextEditingController(
      text: draft.amountReceived == 0
          ? ''
          : SaleDraft.formatWeight(draft.amountReceived),
    );
  }

  @override
  void dispose() {
    _transportController.dispose();
    _receivedController.dispose();
    super.dispose();
  }

  /// Applies a payment choice to the draft. Fully Paid and Pending fix
  /// the amount; Partial leaves it to the field. Anything short of the
  /// full amount is a credit sale.
  void _setMode(_PayMode mode) {
    final draft = widget.draft;
    final total = draft.customerTotalDeliverNow;

    setState(() {
      _mode = mode;

      switch (mode) {
        case _PayMode.paid:
          draft.onCredit = false;
          draft.amountReceived = total;
          break;
        case _PayMode.pending:
          draft.onCredit = true;
          draft.amountReceived = 0;
          break;
        case _PayMode.partial:
          draft.onCredit = true;
          draft.amountReceived = 0;
          _receivedController.text = '';
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final total = draft.customerTotalDeliverNow;

    // Transport can change the total while Fully Paid is selected.
    if (_mode == _PayMode.paid) {
      draft.onCredit = false;
      draft.amountReceived = total;
    }

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardSectionCard(
            title: 'Transport (optional)',
            icon: Icons.local_shipping_outlined,
            children: [
              wizardField(
                controller: _transportController,
                label: 'Transport Charge to Customer',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                optional: true,
                keyboardType: wizardDecimalKeyboard,
                inputFormatters: wizardDecimalFormatters(),
                onChanged: (v) {
                  draft.transportCost = double.tryParse(v.trim()) ?? 0;
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              const WizardNote(
                'Billed to the customer and passed on to the transport '
                    'team — it is not part of your revenue.',
              ),
            ],
          ),

          const SizedBox(height: 14),

          WizardResultCard(
            icon: Icons.receipt_long_outlined,
            title: 'Customer Total',
            formula: 'Goat Sale + Transport',
            value: wizardCurrency(total),
          ),

          const SizedBox(height: 14),

          WizardSectionCard(
            title: 'Payment',
            icon: Icons.payments_outlined,
            children: [
              Text('Payment Status', style: AppTheme.body(size: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in const {
                    _PayMode.paid: 'Fully Paid',
                    _PayMode.partial: 'Partial',
                    _PayMode.pending: 'Pending',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _mode == entry.key,
                      onSelected: (_) => _setMode(entry.key),
                      selectedColor: AppColors.lightGreen,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_mode == _PayMode.paid)
                WizardNote(
                  'Full amount ${wizardCurrency(total)} received now.',
                )
              else if (_mode == _PayMode.pending)
                const WizardNote(
                  'Nothing received now. The full amount is recorded as '
                      'owed by the customer.',
                  tone: WizardNoteTone.warning,
                )
              else
                wizardField(
                  controller: _receivedController,
                  label: 'Amount Received Now',
                  hint: '0.00',
                  icon: Icons.currency_rupee_rounded,
                  keyboardType: wizardDecimalKeyboard,
                  inputFormatters: wizardDecimalFormatters(),
                  onChanged: (v) {
                    draft.amountReceived = double.tryParse(v.trim()) ?? 0;
                    setState(() {});
                  },
                  validator: (value) {
                    final n = double.tryParse(value?.trim() ?? '');
                    if (n == null || n <= 0) {
                      return 'Enter the amount received (choose Pending if '
                          'nothing yet)';
                    }
                    if (n >= total - 0.005) {
                      return 'That is the full amount — choose Fully Paid';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 14),
              if (_mode != _PayMode.pending) ...[
                Text('Payment Method', style: AppTheme.body(size: 11)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in const ['Cash', 'UPI', 'Bank Transfer'])
                      ChoiceChip(
                        label: Text(m),
                        selected: draft.paymentMethod == m,
                        onSelected: (_) =>
                            setState(() => draft.paymentMethod = m),
                        selectedColor: AppColors.lightGreen,
                      ),
                  ],
                ),
              ],
            ],
          ),

          if (draft.remainingBalanceDeliverNow > 0) ...[
            const SizedBox(height: 14),
            WizardNote(
              'Remaining balance ${wizardCurrency(draft.remainingBalanceDeliverNow)} '
                  'will be recorded as owed by the customer.',
              tone: WizardNoteTone.warning,
            ),
          ],
        ],
      ),
    );
  }
}