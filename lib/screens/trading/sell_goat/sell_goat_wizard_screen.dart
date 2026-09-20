import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../../../widgets/farm_not_linked_state.dart';
import '../sale_receipt_screen.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../steps/step1_select_goats.dart';
import '../steps/step2_customer_lookup.dart';
import '../steps/step3_selected_goat_details.dart';
import '../steps/step4_sale_details.dart';
import '../steps/step5_delivery_options.dart';

/// Sell Goat wizard.
///
/// Flow:
/// Step 1 -> Select Goat(s)
/// Step 2 -> Customer
/// Step 3 -> Goat Details
/// Step 4 -> Sale Details
/// Step 5 -> Delivery
///
/// After a successful save, the user is taken to the Sale Receipt screen
/// instead of immediately being returned to the Trading dashboard.
///
/// The exceptions are Booking / Holding and Wait for Delivery: their
/// receipts are generated when the delivery is completed (the holding
/// charges / pickup weight aren't known before that), so saving them just
/// keeps the record and returns to the previous screen.
class SellGoatWizardScreen extends StatefulWidget {
  const SellGoatWizardScreen({super.key});

  @override
  State<SellGoatWizardScreen> createState() =>
      _SellGoatWizardScreenState();
}

class _SellGoatWizardScreenState extends State<SellGoatWizardScreen> {
  final PageController _pageController = PageController();

  final GlobalKey<Step2CustomerLookupState> _customerKey =
  GlobalKey<Step2CustomerLookupState>();

  final GlobalKey<Step3SelectedGoatDetailsState> _goatDetailsKey =
  GlobalKey<Step3SelectedGoatDetailsState>();

  final GlobalKey<FormState> _saleDetailsFormKey =
  GlobalKey<FormState>();

  final GlobalKey<Step5DeliveryOptionsState> _deliveryKey =
  GlobalKey<Step5DeliveryOptionsState>();

  final SaleDraft _draft = SaleDraft();

  String? _farmId;
  bool _loadingFarm = true;

  int _currentStep = 0;
  bool _moving = false;
  bool _saving = false;

  static const List<String> _stepLabels = [
    'Goats',
    'Customer',
    'Details',
    'Sale',
    'Delivery',
  ];

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    if (mounted) {
      setState(() {
        _loadingFarm = true;
      });
    }

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

  // ===========================================================================
  // STEP INFORMATION
  // ===========================================================================

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Select Goat(s)';
      case 1:
        return 'Customer Details';
      case 2:
        return 'Selected Goat Details';
      case 3:
        return 'Sale Details';
      case 4:
        return 'Delivery Options';
      default:
        return 'Sell Goat';
    }
  }

  bool get _isLastStep =>
      _currentStep == _stepLabels.length - 1;

  // ===========================================================================
  // NEXT
  // ===========================================================================

  Future<void> _next() async {
    if (_moving || _saving) return;

    FocusScope.of(context).unfocus();

    // -------------------------------------------------------------------------
    // STEP 1
    // -------------------------------------------------------------------------

    if (_currentStep == 0) {
      if (_draft.selectedGoats.isEmpty) {
        _showMessage('Select at least one goat to continue.');
        return;
      }

      await _goToStep(1);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 2
    // -------------------------------------------------------------------------

    if (_currentStep == 1) {
      final valid =
          _customerKey.currentState?.validate() ?? false;

      if (!valid) return;

      await _goToStep(2);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 3
    // -------------------------------------------------------------------------

    if (_currentStep == 2) {
      final valid =
          _goatDetailsKey.currentState?.validate() ?? false;

      if (!valid) return;

      await _goToStep(3);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 4
    // -------------------------------------------------------------------------

    if (_currentStep == 3) {
      final valid =
          _saleDetailsFormKey.currentState?.validate() ?? false;

      if (!valid) return;

      await _goToStep(4);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 5
    // -------------------------------------------------------------------------

    if (_currentStep == 4) {
      final valid =
          _deliveryKey.currentState?.validate() ?? false;

      if (!valid) return;

      await _saveSale();
    }
  }

  // ===========================================================================
  // SAVE SALE
  // ===========================================================================

  Future<void> _saveSale() async {
    final farmId = _farmId;

    if (farmId == null || farmId.isEmpty) {
      _showMessage('Farm could not be found.');
      return;
    }

    if (_draft.deliveryType.trim().isEmpty) {
      _showMessage('Choose a delivery option to continue.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      late final String saleId;

      // -----------------------------------------------------------------------
      // DELIVER NOW
      // -----------------------------------------------------------------------

      if (_draft.isDeliverNow) {
        saleId = await SalesService.instance.saveDeliverNow(
          farmId: farmId,
          draft: _draft,
        );
      }

      // -----------------------------------------------------------------------
      // BOOKING / HOLD
      // -----------------------------------------------------------------------

      else if (_draft.isBooking) {
        saleId = await SalesService.instance.saveBooking(
          farmId: farmId,
          draft: _draft,
        );
      }

      // -----------------------------------------------------------------------
      // WAIT FOR DELIVERY
      // -----------------------------------------------------------------------

      else if (_draft.isWaitForDelivery) {
        saleId = await SalesService.instance.saveWaitForDelivery(
          farmId: farmId,
          draft: _draft,
        );
      }

      // -----------------------------------------------------------------------
      // TRANSFER TO PALAI
      // -----------------------------------------------------------------------

      else if (_draft.isPalaiTransfer) {
        saleId = await SalesService.instance.saveTransferToPalai(
          farmId: farmId,
          draft: _draft,
        );
      }

      else {
        _showMessage(
          'Choose a delivery option to continue.',
        );

        if (mounted) {
          setState(() {
            _saving = false;
          });
        }

        return;
      }

      if (!mounted) return;

      // -----------------------------------------------------------------------
      // BOOKING / WAIT FOR DELIVERY — keep the record, no receipt yet.
      //
      // The receipt is generated when the delivery is completed (goat stock
      // > Complete Delivery), when the holding charges / final weight and
      // the final amount are known.
      // -----------------------------------------------------------------------

      if (_draft.isWaitForDelivery || _draft.isBooking) {
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
                'Sale $saleId saved. The receipt will be generated when '
                    'the delivery is completed.',
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

      // -----------------------------------------------------------------------
      // OPEN RECEIPT
      // -----------------------------------------------------------------------

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SaleReceiptScreen(
            farmId: farmId,
            saleId: saleId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showMessage(
        _friendlySaveError(e),
      );
    }
  }

  String _friendlySaveError(Object error) {
    final raw = error.toString().trim();

    if (raw.isEmpty) {
      return 'Could not save the sale.';
    }

    if (raw.startsWith('Bad state: ')) {
      return raw.substring('Bad state: '.length);
    }

    if (raw.startsWith('StateError: ')) {
      return raw.substring('StateError: '.length);
    }

    return 'Could not save the sale.\n$raw';
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(String message) {
    if (!mounted) return;

    // Every message here is a blocker (validation or a failed save).
    wizardSnack(context, message, error: true);
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  Future<void> _goToStep(int step) async {
    if (_moving) return;

    if (step < 0 || step >= _stepLabels.length) {
      return;
    }

    if (!_pageController.hasClients) {
      setState(() {
        _currentStep = step;
      });
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
      if (mounted) {
        setState(() {
          _moving = false;
        });
      }
    }
  }

  // ===========================================================================
  // BACK
  // ===========================================================================

  Future<void> _back() async {
    if (_moving || _saving) return;

    FocusScope.of(context).unfocus();

    if (_currentStep == 0) {
      await _leave();
      return;
    }

    await _goToStep(_currentStep - 1);
  }

  // ===========================================================================
  // EXIT CONFIRMATION
  // ===========================================================================

  /// Leaves the wizard. Only asks for confirmation when there is actually
  /// something selected or typed that would be lost.
  Future<void> _leave() async {
    final hasData = _draft.selectedGoats.isNotEmpty ||
        _draft.mobile.trim().isNotEmpty ||
        _draft.customerName.trim().isNotEmpty;

    if (hasData) {
      final discard = await showWizardConfirm(
        context: context,
        title: 'Discard this sale?',
        message:
        'Nothing has been saved yet. If you leave now, the goats you '
            'selected and everything you entered will be lost.',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep editing',
        destructive: true,
        icon: Icons.delete_outline_rounded,
      );

      if (!mounted || !discard) return;
    }

    Navigator.of(context).pop();
  }

  // ===========================================================================
  // PAGE CONTENT
  // ===========================================================================

  Widget _buildPage(int index) {
    final farmId = _farmId;

    if (farmId == null) {
      return const SizedBox.shrink();
    }

    switch (index) {
      case 0:
        return Step1SelectGoats(
          farmId: farmId,
          draft: _draft,
        );

      case 1:
        return Step2CustomerLookup(
          key: _customerKey,
          farmId: farmId,
          draft: _draft,
        );

      case 2:
        return Step3SelectedGoatDetails(
          key: _goatDetailsKey,
          draft: _draft,
        );

      case 3:
        return Step4SaleDetails(
          formKey: _saleDetailsFormKey,
          draft: _draft,
        );

      case 4:
        return Step5DeliveryOptions(
          key: _deliveryKey,
          draft: _draft,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving) return;

        // _back() walks back a step, or (on step 1) asks before leaving.
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
              _currentStep == 0
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
            ),
            tooltip: _currentStep == 0 ? 'Close' : 'Back',
            color: AppColors.textDark,
          ),
          title: Text(
            'Sell Goat',
            style: AppTheme.heading(
              size: 19,
              color: AppColors.textDark,
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: _loadingFarm
              ? const Center(
            child: CircularProgressIndicator(
              color: AppColors.primaryGreen,
            ),
          )
              : _farmId == null
              ? FarmNotLinkedState(
            buttonColor: AppColors.primaryGreen,
            onRetry: _loadFarm,
          )
              : _buildWizardBody(),
        ),

        // A real bottomNavigationBar (not a widget inside the body) so
        // floating snackbars sit ABOVE it instead of covering Back / Next.
        bottomNavigationBar: (_loadingFarm || _farmId == null)
            ? null
            : _buildBottomBar(),
      ),
    );
  }

  Widget _buildWizardBody() {
    return Column(
      children: [
        // ---------------------------------------------------------------------
        // STEP INDICATOR
        // ---------------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            4,
            16,
            8,
          ),
          child: WizardStepIndicator(
            currentStep: _currentStep,
            labels: _stepLabels,
          ),
        ),

        // ---------------------------------------------------------------------
        // STEP TITLE (the indicator above already says "Step x of y")
        // ---------------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _stepTitle,
              style: AppTheme.heading(
                size: 17,
                color: AppColors.textDark,
              ),
            ),
          ),
        ),

        // ---------------------------------------------------------------------
        // PAGE
        // ---------------------------------------------------------------------

        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stepLabels.length,
            onPageChanged: (index) {
              if (!mounted) return;

              setState(() {
                _currentStep = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildPage(index);
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BOTTOM BAR
  // ===========================================================================

  Widget _buildBottomBar() {
    final busy = _moving || _saving;

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
              if (_currentStep > 0) ...[
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
                              .withOpacity(busy ? 0.15 : 0.35),
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
              ],
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
                      AppColors.primaryGreen.withOpacity(0.55),
                      disabledForegroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_saving) ...[
                          const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _saving
                              ? 'Saving…'
                              : (_isLastStep ? 'Complete Sale' : 'Next'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (!_saving) ...[
                          const SizedBox(width: 7),
                          Icon(
                            _isLastStep
                                ? Icons.check_circle_outline_rounded
                                : Icons.arrow_forward_rounded,
                            size: 20,
                          ),
                        ],
                      ],
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