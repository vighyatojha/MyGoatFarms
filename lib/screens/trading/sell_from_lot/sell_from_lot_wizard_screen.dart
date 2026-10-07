import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sale_goat_details_service.dart';
import '../../../services/sales_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/farm_not_linked_state.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/permission_gate.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../lots/receive_lot_screen.dart';
import '../lots/transfer_to_customer_palai_wizard_screen.dart';
import '../sale_receipt_screen.dart';
import '../steps/step2_customer_lookup.dart';
import '../steps/step4_sale_details.dart';
import '../steps/step5_delivery_options.dart';
import '../steps/step6_goat_photos.dart';
import 'step_select_lot.dart';
import 'step_source_and_quantity.dart';

/// Sell From Lot — the lot-first counterpart of Sell Goat: no individual
/// goats are picked, a quantity is taken straight out of a Purchase Lot.
///
/// Flow (goats at the farm or at the supplier alike):
/// Select Lot -> Source & Quantity -> Customer -> Sale Details -> Delivery
/// -> Goat Photos (photo, approximate age and weight of each goat, saved
/// with the sale: shown on the Wait on Delivery / Booking & Holding goat
/// list and in the customer's purchase history) -> save.
///
/// Delivery is the same [Step5DeliveryOptions] the Sell Goat wizard uses,
/// told (through the draft) that this is a lot sale:
///  - every source gets Deliver Now, Booking / Holding and Wait for
///    Delivery (held goats are reserved in the lot — at the farm or at the
///    supplier — not sold, until the delivery is completed from the
///    Booking / Wait for Delivery lists);
///  - Transfer to Palai hands over to the lot's own Palai transfer
///    (goats must be registered one by one). Goats still at the supplier
///    are received at the farm first (Receive Lot). Transfer to Own Palai
///    is not a sale; it is in Lot details.
class SellFromLotWizardScreen extends StatefulWidget {
  /// When given (e.g. from the "Lot Created" screen) the wizard skips Select
  /// Lot and opens on Source & Quantity for this lot.
  final TradingPurchase? initialLot;

  const SellFromLotWizardScreen({super.key, this.initialLot});

  @override
  State<SellFromLotWizardScreen> createState() =>
      _SellFromLotWizardScreenState();
}

class _SellFromLotWizardScreenState extends State<SellFromLotWizardScreen> {
  static const int _lotPage = 0;
  static const int _sourcePage = 1;
  static const int _customerPage = 2;
  static const int _detailsPage = 3;
  static const int _paymentPage = 4;
  static const int _photosPage = 5;

  late final PageController _pageController = PageController(
    initialPage: widget.initialLot == null ? _lotPage : _sourcePage,
  );

  final GlobalKey<Step2CustomerLookupState> _customerKey =
  GlobalKey<Step2CustomerLookupState>();
  final GlobalKey<FormState> _sourceFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _detailsFormKey = GlobalKey<FormState>();
  final GlobalKey<Step5DeliveryOptionsState> _deliveryKey =
  GlobalKey<Step5DeliveryOptionsState>();
  final GlobalKey<Step6GoatPhotosState> _goatPhotosKey =
  GlobalKey<Step6GoatPhotosState>();

  final SaleDraft _draft = SaleDraft();

  String? _farmId;
  bool _loadingFarm = true;

  /// Snapshot of the lot as it was when picked, only for showing numbers
  /// on Step 2 — TradingService re-checks everything live at save time.
  TradingPurchase? _lot;

  late int _currentStep =
  widget.initialLot == null ? _lotPage : _sourcePage;
  bool _moving = false;
  bool _saving = false;

  /// Step 6 (Goat Photos): Deliver Now, Booking / Holding and Wait for
  /// Delivery.
  List<String> get _stepLabels => [
    'Lot',
    'Quantity',
    'Customer',
    'Sale',
    'Delivery',
    if (_draft.needsGoatPhotos) 'Photos',
  ];

  bool get _isLastStep => _currentStep == _stepLabels.length - 1;

  @override
  void initState() {
    super.initState();

    final lot = widget.initialLot;

    if (lot != null) {
      _lot = lot;
      _draft.lotDocId = lot.id;
      _draft.lotDisplayId = lot.lotId;
      _draft.sourceLocation =
      lot.farmAvailableQty > 0 ? Sale.sourceFarm : Sale.sourceSupplier;
    }

    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final id = await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    setState(() {
      _farmId = id == null || id.trim().isEmpty ? null : id.trim();
      _loadingFarm = false;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _stepTitle {
    switch (_currentStep) {
      case _lotPage:
        return 'Select Lot';
      case _sourcePage:
        return 'Source & Quantity';
      case _customerPage:
        return 'Customer Details';
      case _detailsPage:
        return 'Sale Details';
      case _paymentPage:
        return 'Delivery Options';
      case _photosPage:
        return 'Goat Photos';
      default:
        return 'Sell From Lot';
    }
  }

  Future<void> _selectLot(TradingPurchase lot) async {
    setState(() => _lot = lot);
    await _goToStep(_sourcePage);
  }

  Future<void> _next() async {
    if (_moving || _saving) return;

    FocusScope.of(context).unfocus();

    switch (_currentStep) {
      case _lotPage:
      // Advancing here happens via the lot tile's onTap (_selectLot),
      // not this button — Select Lot has no Next of its own.
        return;

      case _sourcePage:
        if (!(_sourceFormKey.currentState?.validate() ?? false)) return;
        await _goToStep(_customerPage);
        return;

      case _customerPage:
        if (!(_customerKey.currentState?.validate() ?? false)) return;
        await _goToStep(_detailsPage);
        return;

      case _detailsPage:
        if (!(_detailsFormKey.currentState?.validate() ?? false)) return;
        await _goToStep(_paymentPage);
        return;

      case _paymentPage:
        if (!(_deliveryKey.currentState?.validate() ?? false)) return;
        // Step 6 records each goat's photo, age and weight before the
        // sale is saved.
        if (_draft.needsGoatPhotos) {
          await _goToStep(_photosPage);
          return;
        }
        await _save();
        return;

      case _photosPage:
        if (!(_goatPhotosKey.currentState?.validate() ?? false)) return;
        await _save();
        return;
    }
  }

  /// Sale Summary shown before the sale is saved (PDF §13): lot, customer,
  /// goats, weight, rate, total, received and pending. Returns true when the
  /// owner taps Confirm Lot Sale.
  Future<bool> _confirmSummary() async {
    final d = _draft;

    final received = d.isDeliverNow
        ? d.amountReceived
        : d.isBooking
        ? d.bookingAmount
        : d.bookingAdvanceAmount;

    final pending = d.isDeliverNow
        ? d.remainingBalanceDeliverNow
        : SaleDraft.round2(
      (d.totalSaleAmount - received) < 0 ? 0 : d.totalSaleAmount - received,
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text('Sale Summary', style: AppTheme.heading(size: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WizardComputedRow(label: 'Lot ID', value: d.lotDisplayId),
              WizardComputedRow(
                label: 'Customer',
                value: d.customerName.trim(),
              ),
              WizardComputedRow(
                label: 'Number of Goats',
                value: '${d.lotQuantity}',
              ),
              WizardComputedRow(
                label: 'Weight',
                value: '${SaleDraft.formatWeight(d.totalSellingWeight)} KG',
              ),
              WizardComputedRow(
                label: 'Pricing',
                value: d.isFixedPrice ? 'Fixed Price' : 'By KG',
              ),
              if (d.isFixedPrice)
                WizardComputedRow(
                  label: 'Fixed Price (≈ / KG)',
                  value: wizardCurrency(d.effectivePricePerKg),
                )
              else
                WizardComputedRow(
                  label: 'Selling Price / KG',
                  value: wizardCurrency(d.effectivePricePerKg),
                ),
              const Divider(height: 18, color: AppColors.divider),
              WizardComputedRow(
                label: 'Total Sale',
                value: wizardCurrency(d.totalSaleAmount),
                emphasize: true,
              ),
              if (d.isDeliverNow && d.transportCost > 0)
                WizardComputedRow(
                  label: 'Transport (billed to customer)',
                  value: wizardCurrency(d.transportCost),
                ),
              WizardComputedRow(
                label: 'Received',
                value: wizardCurrency(received),
              ),
              WizardComputedRow(
                label: 'Pending',
                value: wizardCurrency(pending),
              ),
              if (d.isBooking || d.isWaitForDelivery) ...[
                const SizedBox(height: 8),
                Text(
                  'These goats are reserved in ${d.lotDisplayId} until the '
                      'delivery is completed.',
                  style: AppTheme.body(size: 11),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Confirm Lot Sale',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    return result == true;
  }

  /// Palai / Own Palai transfers register goats one by one, so they need
  /// the goats at the farm. When this sale is from the supplier, offer to
  /// receive them first (Receive Lot) and return the refreshed lot, or
  /// null when the person backed out.
  Future<TradingPurchase?> _lotAtFarmForTransfer(String target) async {
    final lot = _lot;
    final farmId = _farmId;

    if (lot == null || farmId == null) return null;

    final fromSupplier = _draft.sourceLocation == Sale.sourceSupplier;

    if (!fromSupplier && lot.farmAvailableQty > 0) return lot;

    if (lot.supplierAvailableQty <= 0) {
      wizardSnack(
        context,
        'No goats of ${lot.lotId} are free to receive at the farm.',
        error: true,
      );
      return null;
    }

    final ok = await showWizardConfirm(
      context: context,
      title: 'Receive goats first?',
      message: 'These goats are still at the supplier. $target registers '
          'each goat at the farm, so receive them first. After receiving '
          'you will go straight to the transfer.',
      confirmLabel: 'Receive Lot',
    );

    if (!ok || !mounted) return null;

    final received = await Navigator.of(context).push<bool>(
      fastRoute(ReceiveLotScreen(farmId: farmId, lot: lot)),
    );

    if (received != true || !mounted) return null;

    final fresh =
    await TradingService.instance.lotStream(farmId, lot.id).first;

    if (!mounted || fresh == null) return null;

    setState(() {
      _lot = fresh;
      _draft.sourceLocation = Sale.sourceFarm;
    });

    return fresh.farmAvailableQty > 0 ? fresh : null;
  }

  /// Transfer to Palai for goats at the farm. A lot's goats are anonymous,
  /// so a Palai transfer needs each goat registered — that is the lot's own
  /// Palai transfer wizard, which this hands over to.
  Future<void> _openPalaiTransfer() async {
    final farmId = _farmId;
    if (farmId == null) return;

    final lot = await _lotAtFarmForTransfer('Transfer to Palai');
    if (lot == null || !mounted) return;

    Navigator.of(context).pushReplacement(
      fastRoute(
        TransferToCustomerPalaiWizardScreen(farmId: farmId, lot: lot),
      ),
    );
  }

  /// Saves the sale. Called once the last step is valid (Delivery, or
  /// Goat Photos for Deliver Now).
  Future<void> _save() async {
    if (!await _confirmSummary()) return;
    if (!mounted) return;

    setState(() => _saving = true);

    try {
      final String saleId;

      if (_draft.isDeliverNow) {
        saleId = await SalesService.instance.saveLotDeliverNow(
          farmId: _farmId!,
          draft: _draft,
        );
        await _saveGoatPhotos(saleId);
      } else if (_draft.isBooking) {
        saleId = await SalesService.instance.saveBooking(
          farmId: _farmId!,
          draft: _draft,
        );
        await _saveGoatPhotos(saleId);
      } else if (_draft.isWaitForDelivery) {
        saleId = await SalesService.instance.saveWaitForDelivery(
          farmId: _farmId!,
          draft: _draft,
        );
        await _saveGoatPhotos(saleId);
      } else {
        // Palai is not offered for a lot sale, and Step 5 refuses to
        // validate without a choice — this is only a backstop.
        setState(() => _saving = false);
        wizardSnack(
          context,
          'Choose a delivery option to continue.',
          error: true,
        );
        return;
      }

      // The sale is saved. If the customer is an existing Palai customer
      // and the address was edited, carry it over to their Palai record
      // (best effort, never throws).
      unawaited(
        SalesService.instance.syncPalaiCustomerAddress(_farmId!, _draft),
      );

      if (!mounted) return;

      // Booking / Wait for Delivery: the goats are only reserved, so there
      // is no receipt yet — it is generated when the delivery is
      // completed (same as the individual-goat flow).
      if (_draft.isBooking || _draft.isWaitForDelivery) {
        final messenger = ScaffoldMessenger.of(context);

        Navigator.of(context).pop();

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.darkGreen,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              duration: const Duration(seconds: 5),
              content: Text(
                'Sale $saleId saved. ${_draft.lotQuantity} goats are '
                    'reserved in ${_draft.lotDisplayId}. The receipt will '
                    'be generated when the delivery is completed.',
                style: AppTheme.body(
                  size: 12,
                  color: Colors.white,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          );

        return;
      }

      Navigator.of(context).pushReplacement(
        fastRoute(SaleReceiptScreen(farmId: _farmId!, saleId: saleId)),
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

  /// Saves the Step 6 photos / ages / weights with the (already saved)
  /// sale. On a failure the person can retry; skipping keeps the sale
  /// without them.
  Future<void> _saveGoatPhotos(String saleId) async {
    while (true) {
      try {
        await SaleGoatDetailsService.instance.saveForSale(
          farmId: _farmId!,
          saleId: saleId,
          lotDisplayId: _draft.lotDisplayId,
          goats: _draft.lotGoatDetails,
        );
        return;
      } catch (e) {
        if (!mounted) return;
        final retry = await showWizardConfirm(
          context: context,
          title: 'Goat photos not saved',
          message: 'Sale $saleId is saved, but the goat photos could not be '
              'saved (${FirestoreService.instance.describeError(e)}). '
              'Check the internet connection and try again.',
          confirmLabel: 'Try again',
          cancelLabel: 'Skip',
        );
        if (!retry || !mounted) return;
      }
    }
  }

  Future<void> _goToStep(int step) async {
    if (_moving) return;
    if (step < _lotPage || step >= _stepLabels.length) return;

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

    if (_currentStep == _lotPage) {
      Navigator.of(context).pop();
      return;
    }

    if (_currentStep == _sourcePage) {
      setState(() => _lot = null);
      await _goToStep(_lotPage);
      return;
    }

    await _goToStep(_currentStep - 1);
  }

  Widget _buildPage(int index) {
    final lot = _lot;

    switch (index) {
      case _lotPage:
        return StepSelectLot(
          farmId: _farmId!,
          draft: _draft,
          onSelected: () {
            // The stream row only carries the fields StepSelectLot reads;
            // fetch a full snapshot for the quantity step's numbers.
            TradingService.instance
                .lotStream(_farmId!, _draft.lotDocId)
                .first
                .then((fresh) {
              if (!mounted || fresh == null) return;
              _selectLot(fresh);
            });
          },
        );

      case _sourcePage:
        if (lot == null) return const SizedBox.shrink();
        return StepSourceAndQuantity(
          formKey: _sourceFormKey,
          draft: _draft,
          lot: lot,
        );

      case _customerPage:
        return Step2CustomerLookup(
          key: _customerKey,
          farmId: _farmId!,
          draft: _draft,
        );

      case _detailsPage:
        return Step4SaleDetails(
          formKey: _detailsFormKey,
          draft: _draft,
        );

      case _paymentPage:
        return Step5DeliveryOptions(
          key: _deliveryKey,
          draft: _draft,
          onTransferToPalai: _openPalaiTransfer,
          // Shows / hides Step 6 and switches Next <-> Confirm Lot Sale.
          onDeliveryTypeChanged: (_) {
            if (mounted) setState(() {});
          },
        );

      case _photosPage:
        return Step6GoatPhotos(
          key: _goatPhotosKey,
          draft: _draft,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: PartnerPermissionKeys.tradingSell,
      child: _body(),
    );
  }

  Widget _body() {
    if (_loadingFarm) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_farmId == null) {
      return Scaffold(body: FarmNotLinkedState(onRetry: _loadFarm));
    }

    return PopScope(
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
              _currentStep == _lotPage
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
            ),
            color: AppColors.textDark,
          ),
          title: Text('Sell From Lot', style: AppTheme.heading(size: 19)),
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
        bottomNavigationBar: _currentStep == _lotPage ? null : _buildBottomBar(),
      ),
    );
  }

  Widget _buildBottomBar() {
    final busy = _moving || _saving;
    final isPayment = _currentStep >= _paymentPage && _isLastStep;

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
                        color: AppColors.primaryGreen.withValues(alpha: busy ? 0.15 : 0.35),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700)),
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
                      disabledBackgroundColor: AppColors.primaryGreen.withValues(alpha: 0.55),
                      disabledForegroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: isPayment
                        ? (_saving
                        ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('Confirm Lot Sale', style: TextStyle(fontWeight: FontWeight.w700)))
                        : const Text('Next', style: TextStyle(fontWeight: FontWeight.w700)),
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