import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../services/firestore_service.dart';
import '../../../services/sales_service.dart';
import '../../../widgets/farm_not_linked_state.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';
import '../steps/step1_select_goats.dart';
import '../steps/step2_customer_lookup.dart';
import '../steps/step3_selected_goat_details.dart';
import '../steps/step4_sale_details.dart';
import '../steps/step5_delivery_options.dart';


/// Sell Goat wizard (Phase 4: Feature 7 + 8).
///
/// Flow (per the Phase 4 plan):
/// Step 1 -> Select Goat(s)             [Task 2.1]
/// Step 2 -> Customer Mobile Lookup     [Task 2.2]
/// Step 3 -> Selected Goat Details      [Task 2.3]
/// Step 4 -> Sale Details               [Task 2.4]
/// Step 5 -> Delivery Options (branch)  [Section 3 — all four branches]
///
/// Each branch's "Complete Delivery" follow-up action (Booking and
/// Wait for Delivery only) is out of scope for this phase — see the
/// plan's Pair 7 note.
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
  // STEP TITLE
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

  bool get _isLastStep => _currentStep == _stepLabels.length - 1;

  // ===========================================================================
  // NEXT / SAVE
  // ===========================================================================

  Future<void> _next() async {
    if (_moving || _saving) return;

    FocusScope.of(context).unfocus();

    // -------------------------------------------------------------------------
    // STEP 1 — SELECT GOAT(S)
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
    // STEP 2 — CUSTOMER LOOKUP
    // -------------------------------------------------------------------------

    if (_currentStep == 1) {
      final valid = _customerKey.currentState?.validate() ?? false;
      if (!valid) return;

      await _goToStep(2);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 3 — SELECTED GOAT DETAILS
    // -------------------------------------------------------------------------

    if (_currentStep == 2) {
      final valid = _goatDetailsKey.currentState?.validate() ?? false;
      if (!valid) return;

      await _goToStep(3);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 4 — SALE DETAILS
    // -------------------------------------------------------------------------

    if (_currentStep == 3) {
      final valid = _saleDetailsFormKey.currentState?.validate() ?? false;
      if (!valid) return;

      await _goToStep(4);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 5 — DELIVERY OPTIONS -> SAVE
    // -------------------------------------------------------------------------

    if (_currentStep == 4) {
      final valid = _deliveryKey.currentState?.validate() ?? false;
      if (!valid) return;

      await _saveSale();
      return;
    }
  }

  Future<void> _saveSale() async {
    final farmId = _farmId;
    if (farmId == null) return;

    setState(() {
      _saving = true;
    });

    try {
      final String saleId;

      if (_draft.isDeliverNow) {
        saleId = await SalesService.instance.saveDeliverNow(
          farmId: farmId,
          draft: _draft,
        );
      } else if (_draft.isBooking) {
        saleId = await SalesService.instance.saveBooking(
          farmId: farmId,
          draft: _draft,
        );
      } else if (_draft.isWaitForDelivery) {
        saleId = await SalesService.instance.saveWaitForDelivery(
          farmId: farmId,
          draft: _draft,
        );
      } else if (_draft.isPalaiTransfer) {
        saleId = await SalesService.instance.saveTransferToPalai(
          farmId: farmId,
          draft: _draft,
        );
      } else {
        _showMessage('Choose a delivery option to continue.');
        setState(() {
          _saving = false;
        });
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pop(saleId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _draft.isPalaiTransfer
                ? 'Sale $saleId saved — goat transferred to Palai.'
                : _draft.isBooking
                ? 'Sale $saleId saved — goat booked.'
                : _draft.isWaitForDelivery
                ? 'Sale $saleId saved — goat marked wait for delivery.'
                : 'Sale $saleId saved.',
          ),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showMessage('Could not save the sale: ${e.toString()}');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ===========================================================================
  // GO TO STEP
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
      final exit = await _confirmExit();

      if (!mounted || !exit) return;

      Navigator.of(context).pop();
      return;
    }

    await _goToStep(_currentStep - 1);
  }

  // ===========================================================================
  // EXIT CONFIRMATION
  // ===========================================================================

  Future<bool> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Leave Sale?'),
          content: const Text(
            'Your entered sale details will be lost if you leave now.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );

    return shouldExit ?? false;
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
        if (didPop) return;

        if (_currentStep > 0) {
          await _back();
          return;
        }

        final exit = await _confirmExit();

        if (!mounted || !exit) return;

        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            onPressed: (_moving || _saving) ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textDark,
          ),
          title: Text(
            'Sell Goat',
            style: AppTheme.heading(size: 19, color: AppColors.textDark),
          ),
        ),
        body: SafeArea(
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
      ),
    );
  }

  Widget _buildWizardBody() {
    return Column(
      children: [
        // ----------------------------------------------------------------
        // STEP INDICATOR
        // ----------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: WizardStepIndicator(
            currentStep: _currentStep,
            labels: _stepLabels,
          ),
        ),

        // ----------------------------------------------------------------
        // STEP TITLE
        // ----------------------------------------------------------------

        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _stepTitle,
                  style: AppTheme.heading(
                    size: 17,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                'Step ${_currentStep + 1} of ${_stepLabels.length}',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textGrey,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // ----------------------------------------------------------------
        // PAGE VIEW
        // ----------------------------------------------------------------

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
            itemBuilder: (context, index) => _buildPage(index),
          ),
        ),

        // ----------------------------------------------------------------
        // BOTTOM ACTION BAR
        // ----------------------------------------------------------------

        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
          child: Row(
            children: [
              if (_currentStep > 0) ...[
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: (_moving || _saving) ? null : _back,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryGreen,
                        side: BorderSide(
                          color: AppColors.primaryGreen.withOpacity(0.35),
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
                    onPressed: (_moving || _saving) ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLastStep ? 'Save Sale' : 'Next',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Icon(
                          _isLastStep
                              ? Icons.check_circle_outline_rounded
                              : Icons.arrow_forward_rounded,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}