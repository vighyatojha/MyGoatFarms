import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_lot_death_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Bottom sheet to record goats of a lot that died at the farm.
///
/// Only goats at the farm that are not reserved for a booking can be
/// entered. Returns true when a death was saved.
Future<bool?> showRecordLotDeathSheet({
  required BuildContext context,
  required String farmId,
  required TradingPurchase lot,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecordLotDeathSheet(farmId: farmId, lot: lot),
  );
}

class _RecordLotDeathSheet extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const _RecordLotDeathSheet({required this.farmId, required this.lot});

  @override
  State<_RecordLotDeathSheet> createState() => _RecordLotDeathSheetState();
}

class _RecordLotDeathSheetState extends State<_RecordLotDeathSheet> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController(text: '1');
  final _noteController = TextEditingController();

  String _reason = LotDeath.reasons.first;
  DateTime _date = DateTime.now();
  bool _saving = false;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int get _qty => int.tryParse(_qtyController.text.trim()) ?? 0;

  double get _costPerGoat {
    final c = widget.lot.costing;
    return c.costPerSurvivingGoat > 0
        ? c.costPerSurvivingGoat
        : c.purchaseAmountPerGoat;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
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
      helpText: 'Date of death',
    );

    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      await TradingService.instance.recordLotFarmDeath(
        farmId: widget.farmId,
        lotDocId: widget.lot.id,
        qty: _qty,
        reason: _reason,
        date: _date,
        note: _noteController.text,
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
    final lot = widget.lot;
    final available = lot.farmAvailableQty;
    final loss = PurchaseCosting.round2(_costPerGoat * _qty);

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
                  Text('Record Death', style: AppTheme.heading(size: 18)),
                  const SizedBox(height: 2),
                  Text(
                    '${lot.lotId} • ${lot.sellerName}',
                    style: AppTheme.body(size: 12),
                  ),
                  const SizedBox(height: 14),
                  WizardComputedRow(
                    label: 'Goats at farm (not reserved)',
                    value: '$available',
                  ),
                  WizardComputedRow(
                    label: 'Cost per goat',
                    value: wizardCurrency(_costPerGoat),
                  ),
                  const SizedBox(height: 12),
                  wizardField(
                    controller: _qtyController,
                    label: 'Goats that died',
                    hint: '1',
                    icon: Icons.numbers_rounded,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final n = int.tryParse(value?.trim() ?? '');

                      if (n == null || n <= 0) {
                        return 'Enter at least 1';
                      }

                      if (n > available) {
                        return 'Only $available goats can be recorded';
                      }

                      return null;
                    },
                  ),
                  if (_qty > 0 && _qty <= available) ...[
                    const SizedBox(height: 10),
                    WizardComputedRow(
                      label: 'Loss at lot cost',
                      value: wizardCurrency(loss),
                      emphasize: true,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text('Reason', style: AppTheme.body(size: 11)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in LotDeath.reasons)
                        ChoiceChip(
                          label: Text(r),
                          selected: _reason == r,
                          onSelected: (_) => setState(() => _reason = r),
                          selectedColor: AppColors.lightGreen,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  WizardDateField(
                    label: 'Date of death *',
                    date: _date,
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 14),
                  wizardField(
                    controller: _noteController,
                    label: 'Note',
                    hint: 'e.g. Found in the morning',
                    icon: Icons.notes_rounded,
                    optional: true,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  ),
                  const SizedBox(height: 10),
                  const WizardNote(
                    'The loss stays with the goats that are left: the lot\'s '
                        'cost per goat goes up. Nothing is paid or received, so '
                        'no Finance entry is made.',
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                          : const Text('Record Death'),
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