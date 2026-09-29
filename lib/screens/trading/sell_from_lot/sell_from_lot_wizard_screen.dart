import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/farm_not_linked_state.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/permission_gate.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../sale_receipt_screen.dart';
import '../steps/step2_customer_lookup.dart';
import '../steps/step4_sale_details.dart';
import '../steps/step5_delivery_options.dart';
import 'step_select_lot.dart';
import 'step_source_and_quantity.dart';

/// Sell From Lot — the lot-first counterpart of Sell Goat: no individual
/// goats are picked, a quantity is taken straight out of a Purchase Lot.
///
/// Flow: Select Lot -> Source & Quantity -> Customer -> Sale Details ->
/// Delivery -> Save. The last step is the same [Step5DeliveryOptions] the
/// Sell Goat wizard uses, told (through the draft) that this is a lot
/// sale:
///  - goats still at the supplier: Deliver Now only;
///  - goats at the farm: Deliver Now, Booking / Holding or Wait for
///    Delivery (held goats are reserved in the lot, not sold, until the
///    delivery is completed from the Booking / Wait for Delivery lists);
///  - Transfer to Palai is not offered — that is the lot's own transfer
///    action.
class SellFromLotWizardScreen extends StatefulWidget {
  const SellFromLotWizardScreen({super.key});

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

  final PageController _pageController = PageController();

  final GlobalKey<Step2CustomerLookupState> _customerKey =
  GlobalKey<Step2CustomerLookupState>();
  final GlobalKey<FormState> _sourceFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _detailsFormKey = GlobalKey<FormState>();
  final GlobalKey<Step5DeliveryOptionsState> _deliveryKey =
  GlobalKey<Step5DeliveryOptionsState>();

  final SaleDraft _draft = SaleDraft();

  String? _farmId;
  bool _loadingFarm = true;

  /// Snapshot of the lot as it was when picked, only for showing numbers
  /// on Step 2 — TradingService re-checks everything live at save time.
  TradingPurchase? _lot;

  int _currentStep = _lotPage;
  bool _moving = false;
  bool _saving = false;

  static const Map<int, String> _stepLabels = {
    _lotPage: 'Lot',
    _sourcePage: 'Quantity',
    _customerPage: 'Customer',
    _detailsPage: 'Sale',
    _paymentPage: 'Delivery',
  };

  @override
  void initState() {
    super.initState();
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
        await _save();
        return;
    }
  }

  Future<void> _save() async {
    if (!(_deliveryKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final String saleId;

      if (_draft.isDeliverNow) {
        saleId = await SalesService.instance.saveLotDeliverNow(
          farmId: _farmId!,
          draft: _draft,
        );
      } else if (_draft.isBooking) {
        saleId = await SalesService.instance.saveBooking(
          farmId: _farmId!,
          draft: _draft,
        );
      } else if (_draft.isWaitForDelivery) {
        saleId = await SalesService.instance.saveWaitForDelivery(
          farmId: _farmId!,
          draft: _draft,
        );
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

  Future<void> _goToStep(int step) async {
    if (_moving) return;
    if (step < _lotPage || step > _paymentPage) return;

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
        );

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      // Selling from a lot isn't creating a purchase, but no dedicated
      // Trading "sell" permission exists yet — tradingPurchaseCreate is
      // reused here for the same reason lot_detail_screen.dart reuses it
      // for Receive Lot / Add Payment. See TRADING_LOT_REFACTOR_HANDOVER
      // v2 for the note that this should probably become its own key.
      permission: PartnerPermissionKeys.tradingPurchaseCreate,
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
                  labels: _stepLabels.values.toList(),
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
                  itemCount: 5,
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
    final isPayment = _currentStep == _paymentPage;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                        color: AppColors.primaryGreen.withOpacity(busy ? 0.15 : 0.35),
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
                      disabledBackgroundColor: AppColors.primaryGreen.withOpacity(0.55),
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
                        : const Text('Save Sale', style: TextStyle(fontWeight: FontWeight.w700)))
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