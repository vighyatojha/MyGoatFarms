import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Receive Lot — records a batch of the lot's goats arriving at the farm.
///
/// A lot can arrive in several batches. Each batch is checked live against
/// the goats still at the supplier; goats already sold from the supplier
/// are never received. Pops with true when a batch was saved.
///
/// The lot passed in is only a snapshot for the live numbers on screen —
/// TradingService.receiveLotBatch re-checks everything inside its
/// transaction, so a stale screen can never over-receive.
class ReceiveLotScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const ReceiveLotScreen({
    super.key,
    required this.farmId,
    required this.lot,
  });

  @override
  State<ReceiveLotScreen> createState() => _ReceiveLotScreenState();
}

class _ReceiveLotScreenState extends State<ReceiveLotScreen> {
  final _formKey = GlobalKey<FormState>();

  final _arrivedController = TextEditingController();
  final _diedController = TextEditingController();
  final _weightController = TextEditingController();
  final _noteController = TextEditingController();
  final _transportController = TextEditingController();
  final _loadingController = TextEditingController();
  final _unloadingController = TextEditingController();
  final _otherController = TextEditingController();

  DateTime _date = DateTime.now();
  bool _saving = false;

  /// Same sanity range the purchase step uses (kg per goat).
  static const double _minKgPerGoat = 3;
  static const double _maxKgPerGoat = 120;

  TradingPurchase get _lot => widget.lot;

  int get _arrived => int.tryParse(_arrivedController.text.trim()) ?? 0;
  int get _died => int.tryParse(_diedController.text.trim()) ?? 0;
  double get _weight => double.tryParse(_weightController.text.trim()) ?? 0;

  double _money(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _arrivedController.dispose();
    _diedController.dispose();
    _weightController.dispose();
    _noteController.dispose();
    _transportController.dispose();
    _loadingController.dispose();
    _unloadingController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  void _receiveAllRemaining() {
    _arrivedController.text = '${_lot.supplierQty}';
    _diedController.text = '0';
    setState(() {});
  }

  Future<void> _pickDate() async {
    final purchaseDay = DateTime(
      _lot.purchaseDate.year,
      _lot.purchaseDate.month,
      _lot.purchaseDate.day,
    );

    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _date,
      firstDate: purchaseDay,
      lastDate: _today,
      helpText: 'Date received',
    );

    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  String? _validateCounts() {
    if (_arrived + _died <= 0) return 'Enter at least one goat';

    if (_arrived + _died > _lot.supplierQty) {
      return 'Only ${_lot.supplierQty} goats are still at the supplier';
    }

    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final lastBatch = _arrived + _died == _lot.supplierQty;

    final ok = await showWizardConfirm(
      context: context,
      title: 'Receive this batch?',
      message: '$_arrived arrived alive'
          '${_died > 0 ? ', $_died died in transit' : ''}.'
          '${lastBatch ? '\n\nThis is the last batch — the lot will be marked fully received.' : ''}'
          '\n\nReceiving cannot be edited afterwards.',
      confirmLabel: 'Receive',
      icon: Icons.inventory_2_outlined,
    );

    if (!ok || !mounted) return;

    setState(() => _saving = true);

    try {
      await TradingService.instance.receiveLotBatch(
        farmId: widget.farmId,
        lotDocId: _lot.id,
        arrivedQty: _arrived,
        diedQty: _died,
        arrivalWeight: _arrived > 0 ? _weight : 0,
        date: _date,
        note: _noteController.text,
        transportCost: _money(_transportController),
        loadingCharges: _money(_loadingController),
        unloadingCharges: _money(_unloadingController),
        otherExpenses: _money(_otherController),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      _fail(e.message?.toString() ?? 'Please check the details.');
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
    final lot = _lot;
    final avg = _arrived > 0 && _weight > 0 ? _weight / _arrived : 0.0;
    final looksOff =
        avg > 0 && (avg < _minKgPerGoat || avg > _maxKgPerGoat);

    final remainingAfter = lot.supplierQty - _arrived - _died;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(title: Text('Receive ${lot.lotId}')),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            WizardSectionCard(
              title: 'Still at supplier',
              icon: Icons.local_shipping_outlined,
              children: [
                WizardComputedRow(
                  label: 'Goats in lot',
                  value: '${lot.totalGoats}',
                ),
                WizardComputedRow(
                  label: 'Already received / died',
                  value: '${lot.receivedTotalQty}',
                ),
                if (lot.soldFromSupplierQty > 0)
                  WizardComputedRow(
                    label: 'Sold from supplier',
                    value: '${lot.soldFromSupplierQty}',
                  ),
                const Divider(height: 18, color: AppColors.divider),
                WizardComputedRow(
                  label: 'Available to receive',
                  value: '${lot.supplierQty}',
                  emphasize: true,
                ),
              ],
            ),

            const SizedBox(height: 14),

            WizardSectionCard(
              title: 'This Batch',
              icon: Icons.inventory_2_outlined,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: wizardField(
                        controller: _arrivedController,
                        label: 'Arrived Alive',
                        hint: '0',
                        icon: Icons.check_circle_outline_rounded,
                        suffix: 'goats',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (_) => _validateCounts(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: wizardField(
                        controller: _diedController,
                        label: 'Died in Transit',
                        hint: '0',
                        icon: Icons.heart_broken_outlined,
                        suffix: 'goats',
                        optional: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (_) => _validateCounts(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    label: Text('Receive all ${lot.supplierQty} remaining'),
                    backgroundColor: AppColors.lightGreen,
                    onPressed: _receiveAllRemaining,
                  ),
                ),

                const SizedBox(height: 14),

                wizardField(
                  controller: _weightController,
                  label: 'Total Weight on Arrival',
                  hint: '0.00',
                  icon: Icons.scale_outlined,
                  suffix: 'KG',
                  helper: 'Weight of the goats that arrived alive',
                  keyboardType: wizardDecimalKeyboard,
                  inputFormatters: wizardDecimalFormatters(),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    // No live goats in this batch -> no weight to enter.
                    if (_arrived == 0) return null;

                    final n = double.tryParse(value?.trim() ?? '');
                    if (n == null || n <= 0) return 'Enter a valid weight';
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                WizardDateField(
                  label: 'Date Received *',
                  date: _date,
                  onTap: _pickDate,
                ),

                const SizedBox(height: 14),

                wizardField(
                  controller: _noteController,
                  label: 'Note',
                  hint: 'e.g. Second truck',
                  icon: Icons.notes_rounded,
                  optional: true,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                ),
              ],
            ),

            const SizedBox(height: 14),

            WizardSectionCard(
              title: 'Transport & Other Costs (optional)',
              icon: Icons.local_shipping_outlined,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _costField(_transportController, 'Transport')),
                    const SizedBox(width: 12),
                    Expanded(child: _costField(_loadingController, 'Loading')),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _costField(_unloadingController, 'Unloading')),
                    const SizedBox(width: 12),
                    Expanded(child: _costField(_otherController, 'Other')),
                  ],
                ),
                const SizedBox(height: 10),
                const WizardNote(
                  'These are added to any costs already on the lot. '
                      'They are not part of the supplier balance.',
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (avg > 0)
              WizardStatTile(
                icon: Icons.monitor_weight_outlined,
                label: 'Avg weight / goat on arrival',
                value: '${PurchaseCosting.formatNumber(avg)} kg',
              ),

            if (looksOff) ...[
              const SizedBox(height: 10),
              WizardNote(
                'That works out to ${PurchaseCosting.formatNumber(avg)} kg per '
                    'goat. Please double-check the count and weight.',
                tone: WizardNoteTone.warning,
              ),
            ],

            if (_arrived + _died > 0 && remainingAfter >= 0) ...[
              const SizedBox(height: 10),
              WizardNote(
                remainingAfter == 0
                    ? 'This receives every goat left at the supplier.'
                    : '$remainingAfter goats will still be at the supplier '
                    'after this batch.',
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.inventory_2_outlined),
                label: const Text(
                  'Save Receiving',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _costField(TextEditingController controller, String label) {
    return wizardField(
      controller: controller,
      label: label,
      hint: '0.00',
      icon: Icons.currency_rupee_rounded,
      optional: true,
      keyboardType: wizardDecimalKeyboard,
      inputFormatters: wizardDecimalFormatters(),
    );
  }
}