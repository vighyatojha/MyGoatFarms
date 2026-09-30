import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/lot_transfer_models.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/permission_gate.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../sale_receipt_screen.dart';
import '../steps/step2_customer_lookup.dart';
import '../steps/step4_sale_details.dart';
import '../steps/step5_delivery_options.dart';
import 'lot_transfer_goats_form.dart';

/// Transfer to Customer Palai — a customer buys goats out of a Purchase
/// Lot and keeps them boarded here.
///
/// Flow: Goats -> Customer -> Sale -> Palai -> Save.
///
///  1. Goats    — how many, and who they are (breed, age, color, health,
///                weight and gender per goat). Lot goats are anonymous, so
///                this is where each one gets an individual identity.
///  2. Customer — the same lookup the Sell Goat wizard uses.
///  3. Sale     — price per kg or a fixed price, using the goats' weights
///                from step 1.
///  4. Palai    — package, monthly charge, transfer date and the money
///                received now (Step5DeliveryOptions in Palai-only mode).
///
/// Saving creates the goats, the sale, the Palai customer and every
/// goat's Palai check-in in one transaction
/// (SalesService.saveLotTransferToCustomerPalai) and opens the receipt.
///
/// Only goats at the farm and not reserved for a customer can be
/// transferred; the lot is re-checked inside that transaction.
class TransferToCustomerPalaiWizardScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const TransferToCustomerPalaiWizardScreen({
    super.key,
    required this.farmId,
    required this.lot,
  });

  @override
  State<TransferToCustomerPalaiWizardScreen> createState() =>
      _TransferToCustomerPalaiWizardScreenState();
}

class _TransferToCustomerPalaiWizardScreenState
    extends State<TransferToCustomerPalaiWizardScreen> {
  static const int _goatsPage = 0;
  static const int _customerPage = 1;
  static const int _salePage = 2;
  static const int _palaiPage = 3;

  static const List<String> _stepLabels = [
    'Goats',
    'Customer',
    'Sale',
    'Palai',
  ];

  final PageController _pageController = PageController();

  final GlobalKey<LotTransferGoatsFormState> _goatsKey =
  GlobalKey<LotTransferGoatsFormState>();
  final GlobalKey<Step2CustomerLookupState> _customerKey =
  GlobalKey<Step2CustomerLookupState>();
  final GlobalKey<FormState> _saleFormKey = GlobalKey<FormState>();
  final GlobalKey<Step5DeliveryOptionsState> _palaiKey =
  GlobalKey<Step5DeliveryOptionsState>();

  /// Pricing, customer and Palai fields live here, exactly as in the
  /// Sell Goat wizard. Its selectedGoats are stand-ins for the goats
  /// about to be created (see [_applyGoatsToDraft]).
  final SaleDraft _draft = SaleDraft();

  /// The goats entered on step 1. Kept here (not in the form) because the
  /// page is disposed when the wizard moves on.
  List<LotTransferGoat> _goats = const [];

  int _quantityTyped = 0;
  int _currentStep = _goatsPage;
  bool _moving = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft.deliveryType = Sale.deliveryTypePalai;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _stepTitle {
    switch (_currentStep) {
      case _goatsPage:
        return 'Goats to Transfer';
      case _customerPage:
        return 'Customer Details';
      case _salePage:
        return 'Sale Details';
      case _palaiPage:
        return 'Palai Details';
      default:
        return 'Transfer to Customer Palai';
    }
  }

  // ---------------------------------------------------------------------
  // DRAFT
  // ---------------------------------------------------------------------

  /// Puts stand-in goats (ids NEW-1, NEW-2 ...) into the draft so that
  /// the pricing steps see the right goat count and total weight. They
  /// are never saved: the real goats, with real ids, are created inside
  /// the save transaction from [_goats].
  void _applyGoatsToDraft(List<LotTransferGoat> goats) {
    final now = DateTime.now();

    _draft.selectedGoats = [
      for (var i = 0; i < goats.length; i++)
        Goat(
          id: 'NEW-${i + 1}',
          breed: goats[i].breed,
          ageMonthsAtRecord: goats[i].ageMonths,
          ageRecordedAt: now,
          weight: goats[i].weight,
          color: goats[i].color,
          healthStatus: goats[i].healthStatus,
          notes: '',
          purchaseId: widget.lot.id,
          purchaseDate: widget.lot.purchaseDate,
          currentStatus: Goat.statusAvailable,
          gender: goats[i].gender,
        ),
    ];

    _draft.deliveryType = Sale.deliveryTypePalai;
  }

  // ---------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------

  Future<void> _next() async {
    if (_moving || _saving) return;

    FocusScope.of(context).unfocus();

    switch (_currentStep) {
      case _goatsPage:
        final form = _goatsKey.currentState;

        if (form == null || !form.validate()) {
          wizardSnack(context, 'Fix the highlighted fields to continue.',
              error: true);
          return;
        }

        final goats = form.buildGoats();

        final blocked =
        LotTransferPlanner.blockReason(widget.lot, goats.length);

        if (blocked != null) {
          wizardSnack(context, blocked, error: true);
          return;
        }

        _goats = goats;
        _applyGoatsToDraft(goats);

        await _goToStep(_customerPage);
        return;

      case _customerPage:
        if (!(_customerKey.currentState?.validate() ?? false)) return;
        await _goToStep(_salePage);
        return;

      case _salePage:
        if (!(_saleFormKey.currentState?.validate() ?? false)) return;
        await _goToStep(_palaiPage);
        return;

      case _palaiPage:
        await _save();
        return;
    }
  }

  Future<void> _goToStep(int step) async {
    if (_moving) return;
    if (step < _goatsPage || step > _palaiPage) return;

    if (!_pageController.hasClients) {
      setState(() => _currentStep = step);
      return;
    }

    setState(() {
      _moving = true;
      _currentStep = step;
    });

    try {
      await _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  Future<void> _back() async {
    if (_moving || _saving) return;

    FocusScope.of(context).unfocus();

    if (_currentStep == _goatsPage) {
      Navigator.of(context).pop();
      return;
    }

    await _goToStep(_currentStep - 1);
  }

  // ---------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------

  Future<void> _save() async {
    if (!(_palaiKey.currentState?.validate() ?? false)) return;

    final n = _goats.length;

    final confirmed = await showWizardConfirm(
      context: context,
      title: 'Transfer $n goat${n == 1 ? '' : 's'} to Palai?',
      message: '$n goat${n == 1 ? '' : 's'} from ${widget.lot.lotId} will '
          'get their own goat record${n == 1 ? '' : 's'} and be checked in '
          'to ${_draft.customerName.trim()}\'s Palai. This cannot be '
          'undone.',
      confirmLabel: 'Transfer',
      icon: Icons.holiday_village_outlined,
    );

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);

    try {
      final saleId =
      await SalesService.instance.saveLotTransferToCustomerPalai(
        farmId: widget.farmId,
        lotDocId: widget.lot.id,
        goats: _goats,
        draft: _draft,
      );

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        fastRoute(
          SaleReceiptScreen(farmId: widget.farmId, saleId: saleId),
        ),
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

  // ---------------------------------------------------------------------
  // PAGES
  // ---------------------------------------------------------------------

  Widget _buildPage(int index) {
    switch (index) {
      case _goatsPage:
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            WizardNote(
              'Goats from ${widget.lot.lotId} get their own goat records '
                  'when this transfer is saved. Only goats already at the '
                  'farm, and not reserved for a customer, can be '
                  'transferred.',
            ),
            const SizedBox(height: 14),
            LotTransferGoatsForm(
              key: _goatsKey,
              lot: widget.lot,
              maxQuantity: widget.lot.farmAvailableQty,
              initialGoats: _goats.isEmpty ? null : _goats,
              onQuantityChanged: (n) => setState(() => _quantityTyped = n),
            ),
            if (_quantityTyped > 0) ...[
              const SizedBox(height: 14),
              WizardStatTile(
                icon: Icons.currency_rupee_rounded,
                label: 'Lot cost carried by these goats',
                value: wizardCurrency(
                  PurchaseCosting.round2(
                    widget.lot.lotCostPerGoat * _quantityTyped,
                  ),
                ),
              ),
            ],
          ],
        );

      case _customerPage:
        return Step2CustomerLookup(
          key: _customerKey,
          farmId: widget.farmId,
          draft: _draft,
        );

      case _salePage:
        return Step4SaleDetails(
          formKey: _saleFormKey,
          draft: _draft,
        );

      case _palaiPage:
        return Step5DeliveryOptions(
          key: _palaiKey,
          draft: _draft,
          palaiOnly: true,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      // Same key the other lot actions use — no dedicated Trading
      // transfer permission exists yet.
      permission: PartnerPermissionKeys.tradingPurchaseCreate,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || _saving) return;
          await _back();
        },
        child: Scaffold(
          backgroundColor: AppColors.paleGreen,
          appBar: AppBar(
            backgroundColor: AppColors.paleGreen,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            leading: IconButton(
              onPressed: (_moving || _saving) ? null : _back,
              icon: Icon(
                _currentStep == _goatsPage
                    ? Icons.close_rounded
                    : Icons.arrow_back_rounded,
              ),
              color: AppColors.textDark,
            ),
            title: Text(
              'Transfer to Customer Palai',
              style: AppTheme.heading(size: 19),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: WizardStepIndicator(
                    currentStep: _currentStep,
                    labels: _stepLabels,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_stepTitle, style: AppTheme.heading(size: 17)),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _stepLabels.length,
                    itemBuilder: (context, index) => _buildPage(index),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomBar(),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final busy = _moving || _saving;
    final isLast = _currentStep == _palaiPage;

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
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: busy ? null : _back,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: BorderSide(
                        color: AppColors.primaryGreen
                            .withValues(alpha: busy ? 0.15 : 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: busy ? null : _next,
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
                    child: isLast
                        ? (_saving
                        ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Transfer to Palai',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ))
                        : const Text(
                      'Next',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}