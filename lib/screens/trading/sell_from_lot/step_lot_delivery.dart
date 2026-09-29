import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _StepLotDeliveryState extends State<StepLotDelivery> {
  late final TextEditingController _transportController;
  late final TextEditingController _receivedController;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

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

  void _setReceived(double amount) {
    widget.draft.amountReceived = amount;
    _receivedController.text = SaleDraft.formatWeight(amount);
    _receivedController.selection = TextSelection.collapsed(
      offset: _receivedController.text.length,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final total = draft.customerTotalDeliverNow;

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
              wizardField(
                controller: _receivedController,
                label: 'Amount Received',
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
                  if (n == null || n < 0) return 'Enter a valid amount';

                  if (!draft.onCredit && n < total - 0.005) {
                    return 'Turn on "Sell on Credit" to accept less than '
                        '${wizardCurrency(total)}';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Nothing yet'),
                    backgroundColor: AppColors.lightGreen,
                    onPressed: () => _setReceived(0),
                  ),
                  ActionChip(
                    label: const Text('Full amount'),
                    backgroundColor: AppColors.lightGreen,
                    onPressed: () => _setReceived(total),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: draft.onCredit,
                onChanged: (v) => setState(() => draft.onCredit = v),
                activeColor: AppColors.primaryGreen,
                title: const Text(
                  'Sell on Credit',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: const Text(
                  'Accept less than the full amount now',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
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
                      onSelected: (_) => setState(() => draft.paymentMethod = m),
                      selectedColor: AppColors.lightGreen,
                    ),
                ],
              ),
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