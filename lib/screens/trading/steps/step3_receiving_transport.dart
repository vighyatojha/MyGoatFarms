import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_draft.dart';
import '../purchase_goats/purchase_cost_card.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 3 — Receiving & Transport.
///
/// Only shown when the user chooses "Fill Receiving Details Now".
///
/// Fields:
/// - Date Received at Farm
/// - Total Weight After Arrival
/// - Mortality
/// - Remarks
/// - Transport Cost
/// - Loading Charges
/// - Unloading Charges
/// - Other Expenses
///
/// Everything is LIVE: each keystroke is pushed into the [PurchaseDraft] and
/// the cards below are rebuilt from [PurchaseCosting]. The bottom card shows
/// the purchase cost after transportation, mortality and arrival weight —
/// the same numbers the summary step shows and the service saves.
class Step3ReceivingTransport extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PurchaseDraft draft;

  const Step3ReceivingTransport({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<Step3ReceivingTransport> createState() =>
      _Step3ReceivingTransportState();
}

class _Step3ReceivingTransportState
    extends State<Step3ReceivingTransport> {
  late final TextEditingController _weightAfterController;
  late final TextEditingController _mortalityController;
  late final TextEditingController _remarksController;
  late final TextEditingController _transportController;
  late final TextEditingController _loadingController;
  late final TextEditingController _unloadingController;
  late final TextEditingController _otherController;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _moneyText(double value) =>
      value == 0 ? '' : PurchaseCosting.formatNumber(value);

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    // The farm cannot receive goats before they were bought. If the purchase
    // date was moved forward after this step was first filled in, pull the
    // received date up with it.
    if (_dateOnly(draft.dateReceivedAtFarm)
        .isBefore(_dateOnly(draft.purchaseDate))) {
      draft.dateReceivedAtFarm = _dateOnly(draft.purchaseDate);
    }

    _weightAfterController = TextEditingController(
      text: _moneyText(draft.totalWeightAfterArrival),
    );

    _mortalityController = TextEditingController(
      text: draft.mortality == 0 ? '' : draft.mortality.toString(),
    );

    _remarksController = TextEditingController(text: draft.remarks);

    _transportController =
        TextEditingController(text: _moneyText(draft.transportCost));

    _loadingController =
        TextEditingController(text: _moneyText(draft.loadingCharges));

    _unloadingController =
        TextEditingController(text: _moneyText(draft.unloadingCharges));

    _otherController =
        TextEditingController(text: _moneyText(draft.otherExpenses));
  }

  @override
  void dispose() {
    _weightAfterController.dispose();
    _mortalityController.dispose();
    _remarksController.dispose();
    _transportController.dispose();
    _loadingController.dispose();
    _unloadingController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _pickReceivedDate() async {
    final draft = widget.draft;

    final picked = await showWizardDatePicker(
      context: context,
      initialDate: draft.dateReceivedAtFarm,
      // Cannot be received before it was purchased, or in the future.
      firstDate: draft.purchaseDate,
      lastDate: DateTime.now(),
      helpText: 'Date received at farm',
    );

    if (picked == null || !mounted) return;

    setState(() {
      draft.dateReceivedAtFarm = picked;
    });
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  /// Pushes every field into the draft and rebuilds — this is what keeps
  /// all the calculated cards live.
  void _recalculate() {
    final draft = widget.draft;

    draft.totalWeightAfterArrival = _number(_weightAfterController);
    draft.mortality = int.tryParse(_mortalityController.text.trim()) ?? 0;
    draft.transportCost = _number(_transportController);
    draft.loadingCharges = _number(_loadingController);
    draft.unloadingCharges = _number(_unloadingController);
    draft.otherExpenses = _number(_otherController);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final costing = draft.costing;

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildReceivingSection(draft, costing),

          const SizedBox(height: 14),

          _buildTransportSection(),

          const SizedBox(height: 14),

          WizardResultCard(
            icon: Icons.receipt_long_outlined,
            title: 'Total Transportation Expenses',
            formula: 'Transport + loading + unloading + other',
            value: wizardCurrency(costing.totalExpenses),
          ),

          const SizedBox(height: 14),

          PurchaseCostCard(costing: costing),
        ],
      ),
    );
  }

  // ===========================================================================
  // RECEIVING
  // ===========================================================================

  Widget _buildReceivingSection(
      PurchaseDraft draft,
      PurchaseCosting costing,
      ) {
    return WizardSectionCard(
      title: 'Farm Receiving',
      icon: Icons.inventory_2_outlined,
      children: [
        WizardDateField(
          label: 'Date Received at Farm *',
          date: draft.dateReceivedAtFarm,
          onTap: _pickReceivedDate,
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _weightAfterController,
          label: 'Total Weight After Arrival',
          hint: '0.00',
          icon: Icons.scale_outlined,
          suffix: 'KG',
          helper:
          'Purchased: ${PurchaseCosting.formatNumber(draft.totalWeightAtPurchase)} kg',
          keyboardType: wizardDecimalKeyboard,
          inputFormatters: wizardDecimalFormatters(),
          onChanged: (_) => _recalculate(),
          validator: (value) {
            final number = double.tryParse(value?.trim() ?? '');

            if (number == null || number <= 0) {
              return 'Enter a valid weight';
            }

            if (number > draft.totalWeightAtPurchase) {
              return 'Cannot exceed the purchase weight '
                  '(${PurchaseCosting.formatNumber(draft.totalWeightAtPurchase)} kg)';
            }

            return null;
          },
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _mortalityController,
          label: 'Mortality',
          hint: 'Goats lost in transit (0 if none)',
          icon: Icons.report_gmailerrorred_outlined,
          suffix: 'goats',
          helper: 'Out of ${draft.totalGoats} purchased',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          optional: true,
          onChanged: (_) => _recalculate(),
          validator: (value) {
            final text = value?.trim() ?? '';

            if (text.isEmpty) return null;

            final number = int.tryParse(text);

            if (number == null || number < 0) {
              return 'Enter a valid number';
            }

            // At least one goat must have arrived: an arrival weight is
            // required, and there is nothing to register otherwise.
            if (number >= draft.totalGoats) {
              return 'Must be less than the ${draft.totalGoats} '
                  'goats purchased';
            }

            return null;
          },
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _remarksController,
          label: 'Remarks / Notes',
          hint: 'e.g. 1 goat weak on arrival',
          icon: Icons.edit_note_rounded,
          maxLines: 3,
          optional: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) {
            draft.remarks = value;
          },
        ),

        const SizedBox(height: 14),

        // ---------------------------------------------------------------
        // LIVE — weight loss + goats that arrived
        // ---------------------------------------------------------------

        Row(
          children: [
            Expanded(
              child: WizardStatTile(
                icon: Icons.trending_down_rounded,
                label: 'Weight loss',
                value: costing.hasArrival
                    ? '${PurchaseCosting.formatNumber(costing.weightLoss)} kg '
                    '(${PurchaseCosting.formatNumber(costing.weightLossPercent)}%)'
                    : '—',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WizardStatTile(
                icon: GoatIcons.paw,
                label: 'Goats arrived',
                value: costing.totalGoats > 0
                    ? '${costing.survivingGoats} of ${costing.totalGoats}'
                    : '—',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // TRANSPORT
  // ===========================================================================

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool last = false,
  }) {
    return wizardField(
      controller: controller,
      label: label,
      hint: '0.00',
      icon: icon,
      prefix: '₹ ',
      keyboardType: wizardDecimalKeyboard,
      inputFormatters: wizardDecimalFormatters(),
      optional: true,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onChanged: (_) => _recalculate(),
    );
  }

  Widget _buildTransportSection() {
    return WizardSectionCard(
      title: 'Transportation & Expenses',
      icon: Icons.local_shipping_outlined,
      children: [
        Text(
          'Add whatever applies. Every amount is optional.',
          style: AppTheme.body(size: 11),
        ),
        const SizedBox(height: 12),
        _moneyField(
          controller: _transportController,
          label: 'Transport Cost',
          icon: Icons.directions_car_outlined,
        ),
        const SizedBox(height: 14),
        _moneyField(
          controller: _loadingController,
          label: 'Loading Charges',
          icon: Icons.upload_outlined,
        ),
        const SizedBox(height: 14),
        _moneyField(
          controller: _unloadingController,
          label: 'Unloading Charges',
          icon: Icons.download_outlined,
        ),
        const SizedBox(height: 14),
        _moneyField(
          controller: _otherController,
          label: 'Other Expenses',
          icon: Icons.more_horiz_rounded,
          last: true,
        ),
      ],
    );
  }
}