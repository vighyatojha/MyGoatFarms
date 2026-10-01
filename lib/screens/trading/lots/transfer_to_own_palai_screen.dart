import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/lot_transfer_models.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/health_reminder_scheduler.dart';
import '../../../widgets/permission_gate.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import 'lot_transfer_goats_form.dart';

/// Transfer to Own Palai — moves goats out of a Purchase Lot into the
/// farm's own Palai.
///
/// This is where the goats stop being anonymous: each one becomes an
/// individual record (G-0041 ...) created directly with status Own Palai
/// (no stop in Available first), because Own Palai needs per-goat health,
/// weight and reminders.
///
/// Only goats physically at the farm and not reserved for a customer can
/// be transferred. Everything is re-checked against the live lot inside
/// the save transaction, so a stale screen cannot over-transfer.
///
/// Pops with the list of new goat ids on success, null otherwise.
class TransferToOwnPalaiScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const TransferToOwnPalaiScreen({
    super.key,
    required this.farmId,
    required this.lot,
  });

  @override
  State<TransferToOwnPalaiScreen> createState() =>
      _TransferToOwnPalaiScreenState();
}

class _TransferToOwnPalaiScreenState extends State<TransferToOwnPalaiScreen> {
  final GlobalKey<LotTransferGoatsFormState> _formKey =
  GlobalKey<LotTransferGoatsFormState>();

  int _quantity = 0;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;

    FocusScope.of(context).unfocus();

    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      wizardSnack(context, 'Fix the highlighted fields to continue.',
          error: true);
      return;
    }

    final goats = form.buildGoats();

    final blocked = LotTransferPlanner.blockReason(widget.lot, goats.length);

    if (blocked != null) {
      wizardSnack(context, blocked, error: true);
      return;
    }

    final n = goats.length;

    final confirmed = await showWizardConfirm(
      context: context,
      title: 'Transfer $n goat${n == 1 ? '' : 's'}?',
      message: '$n goat${n == 1 ? '' : 's'} from ${widget.lot.lotId} will '
          'get their own goat record${n == 1 ? '' : 's'} and move to Own '
          'Palai. They leave the lot and cannot be put back.',
      confirmLabel: 'Transfer',
      icon: Icons.home_work_outlined,
    );

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);

    try {
      final created = await GoatService.instance.transferLotToOwnPalai(
        farmId: widget.farmId,
        lotDocId: widget.lot.id,
        goats: goats,
      );

      // Arm each goat's vaccination / hoof / hair reminders straight away,
      // as moving a goat to Own Palai does. Not awaited: the transfer
      // itself has already succeeded and this never throws.
      for (final goat in created) {
        unawaited(
          HealthReminderScheduler.instance.syncOwnPalaiFarmReminders(
            widget.farmId,
            goatId: goat.id,
            force: true,
          ),
        );
      }

      if (!mounted) return;

      await _showDone(created);

      if (!mounted) return;

      Navigator.of(context).pop<List<String>>(
        created.map((g) => g.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      wizardSnack(
        context,
        e is StateError || e is ArgumentError
            ? e.toString().replaceFirst(RegExp(r'^(State|Argument)Error: '), '')
            : FirestoreService.instance.describeError(e),
        error: true,
      );
    }
  }

  Future<void> _showDone(List<Goat> created) {
    final ids = created.map((g) => g.id).toList();

    final range = ids.length == 1
        ? ids.first
        : '${ids.first} to ${ids.last}';

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text('Transferred', style: AppTheme.heading(size: 18)),
          content: Text(
            '${ids.length} goat${ids.length == 1 ? '' : 's'} moved from '
                '${widget.lot.lotId} to Own Palai.\n\nNew goat '
                '${ids.length == 1 ? 'id' : 'ids'}: $range',
            style: AppTheme.body(size: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;

    return PermissionGate(
      permission: PartnerPermissionKeys.tradingManageStock,
      child: PopScope(
        canPop: !_saving,
        child: Scaffold(
          backgroundColor: AppColors.paleGreen,
          appBar: AppBar(
            backgroundColor: AppColors.paleGreen,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            foregroundColor: AppColors.textDark,
            title: Text(
              'Transfer to Own Palai',
              style: AppTheme.heading(size: 19),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: ListView(
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                WizardNote(
                  'Goats from ${lot.lotId} get their own goat records and '
                      'move straight to Own Palai. Only goats already at the '
                      'farm, and not reserved for a customer, can be '
                      'transferred.',
                ),
                const SizedBox(height: 14),
                LotTransferGoatsForm(
                  key: _formKey,
                  lot: lot,
                  maxQuantity: lot.farmAvailableQty,
                  onQuantityChanged: (n) => setState(() => _quantity = n),
                ),
                if (_quantity > 0) ...[
                  const SizedBox(height: 14),
                  WizardStatTile(
                    icon: Icons.currency_rupee_rounded,
                    label: 'Lot cost carried by these goats',
                    value: wizardCurrency(
                      PurchaseCosting.round2(lot.lotCostPerGoat * _quantity),
                    ),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: _bottomBar(),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final label = _quantity > 0
        ? 'Transfer $_quantity goat${_quantity == 1 ? '' : 's'}'
        : 'Transfer';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                AppColors.primaryGreen.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}