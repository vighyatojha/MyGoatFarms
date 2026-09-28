import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_draft.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../widgets/fast_route.dart';
import '../steps/step1_seller_details.dart';
import '../steps/step2_purchase_details.dart';
import '../steps/step3_receiving_transport.dart';
import '../steps/step_lot_payment.dart';
import '../steps/step4_summary.dart';
import 'purchase_success_screen.dart';
import 'purchase_wizard_widgets.dart';

/// Purchase Lot wizard.
///
/// A purchase is a LOT: goats stay anonymous inside it (no goat IDs are
/// created here).
///
/// Flow:
/// Step 1  -> Supplier Details (+ optional Expected Delivery Date)
/// Step 2  -> Lot Details
/// Step 3  -> Supplier Payment (paid now: 0 .. full)
///          -> popup: Goats received now / Still at supplier
///
/// Received now:
/// Step 4  -> Receiving + Transport (live cost after mortality/arrival)
/// Step 5  -> Summary -> Save
///
/// Still at supplier:
/// Step 4 is skipped (the progress bar drops to 4 steps so it never says
/// "Step 5 of 5" after only four screens) -> Summary -> Save
///          -> the lot starts At Supplier; it can be sold from, and
///             received later (in one go or in batches).
class PurchaseGoatsWizardScreen extends StatefulWidget {
  const PurchaseGoatsWizardScreen({super.key});

  @override
  State<PurchaseGoatsWizardScreen> createState() =>
      _PurchaseGoatsWizardScreenState();
}

class _PurchaseGoatsWizardScreenState
    extends State<PurchaseGoatsWizardScreen> {
  static const int _sellerPage = 0;
  static const int _purchasePage = 1;
  static const int _paymentPage = 2;
  static const int _receivingPage = 3;
  static const int _summaryPage = 4;

  final PageController _pageController = PageController();

  final GlobalKey<FormState> _sellerFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _purchaseFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _paymentFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _receivingFormKey = GlobalKey<FormState>();
  final GlobalKey<Step4SummaryState> _summaryKey =
  GlobalKey<Step4SummaryState>();

  final PurchaseDraft _draft = PurchaseDraft();

  /// Drives the bottom bar's spinner / disabled state while saving.
  final ValueNotifier<bool> _saving = ValueNotifier<bool>(false);

  int _currentStep = _sellerPage;

  bool _moving = false;

  /// True when "receive later" was chosen — Step 3 is then skipped.
  bool _receivingSkipped = false;

  static const Map<int, String> _stepLabels = {
    _sellerPage: 'Supplier',
    _purchasePage: 'Lot',
    _paymentPage: 'Payment',
    _receivingPage: 'Receiving',
    _summaryPage: 'Summary',
  };

  @override
  void dispose() {
    _pageController.dispose();
    _saving.dispose();
    super.dispose();
  }

  // ===========================================================================
  // STEP FLOW
  // ===========================================================================

  /// The pages the person will actually visit.
  List<int> get _flow => _receivingSkipped
      ? const [_sellerPage, _purchasePage, _paymentPage, _summaryPage]
      : const [
    _sellerPage,
    _purchasePage,
    _paymentPage,
    _receivingPage,
    _summaryPage,
  ];

  int get _flowPosition {
    final index = _flow.indexOf(_currentStep);

    return index < 0 ? 0 : index;
  }

  String get _stepTitle {
    switch (_currentStep) {
      case _sellerPage:
        return 'Supplier Details';
      case _purchasePage:
        return 'Lot Details';
      case _paymentPage:
        return 'Supplier Payment';
      case _receivingPage:
        return 'Receiving & Transport';
      case _summaryPage:
        return 'Lot Summary';
      default:
        return 'Purchase Lot';
    }
  }

  // ===========================================================================
  // NEXT
  // ===========================================================================

  Future<void> _next() async {
    if (_moving || _saving.value) return;

    FocusScope.of(context).unfocus();

    switch (_currentStep) {
      case _sellerPage:
        if (!(_sellerFormKey.currentState?.validate() ?? false)) return;

        await _goToStep(_purchasePage);
        return;

      case _purchasePage:
        if (!(_purchaseFormKey.currentState?.validate() ?? false)) return;

        await _goToStep(_paymentPage);
        return;

      case _paymentPage:
        if (!(_paymentFormKey.currentState?.validate() ?? false)) return;

        await _showReceivingChoice();
        return;

      case _receivingPage:
        if (!(_receivingFormKey.currentState?.validate() ?? false)) return;

        _draft.markReceivingCompleted();

        await _goToStep(_summaryPage);
        return;

      case _summaryPage:
        await _summaryKey.currentState?.save();
        return;
    }
  }

  // ===========================================================================
  // RECEIVING CHOICE POPUP
  // ===========================================================================

  Future<void> _showReceivingChoice() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.primaryGreen,
                  size: 27,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Have the goats reached the farm?',
                textAlign: TextAlign.center,
                style: AppTheme.heading(size: 19),
              ),
              const SizedBox(height: 6),
              Text(
                'If they are still with the supplier, the lot starts '
                    'At Supplier and you can sell from it or receive it '
                    'later.',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 12),
              ),
              const SizedBox(height: 20),
              _ChoiceTile(
                icon: Icons.edit_note_rounded,
                title: 'Goats have arrived — enter details',
                subtitle:
                'Arrival weight, mortality and transport costs. '
                    'The whole lot is marked At Farm.',
                highlighted: true,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: 10),
              _ChoiceTile(
                icon: Icons.schedule_outlined,
                title: 'Still at supplier',
                subtitle:
                'Saves the lot as At Supplier. Receive it later from '
                    'Lot Detail, all at once or in batches.',
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(
                  'Keep editing',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // Dismissed without choosing: stay on the Payment step, change nothing.
    if (!mounted || result == null) return;

    if (result) {
      _receivingSkipped = false;
      _draft.receivingNow = true;
      _draft.receivingStatus = 'pending';

      await _goToStep(_receivingPage);
      return;
    }

    _receivingSkipped = true;
    _draft.markReceivingPending();

    await _goToStep(_summaryPage);
  }

  // ===========================================================================
  // GO TO STEP
  // ===========================================================================

  Future<void> _goToStep(int step) async {
    if (_moving) return;

    if (step < _sellerPage || step > _summaryPage) return;

    if (!_pageController.hasClients) {
      setState(() {
        _currentStep = step;
      });
      return;
    }

    final distance = (step - _currentStep).abs();

    setState(() {
      _moving = true;
      _currentStep = step;
    });

    try {
      if (distance > 1) {
        // Skipping the Receiving page: jump, don't slide through it.
        _pageController.jumpToPage(step);
      } else {
        await _pageController.animateToPage(
          step,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
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
    if (_moving || _saving.value) return;

    FocusScope.of(context).unfocus();

    if (_currentStep == _sellerPage) {
      await _leave();
      return;
    }

    if (_currentStep == _summaryPage) {
      await _goToStep(_receivingSkipped ? _paymentPage : _receivingPage);
      return;
    }

    await _goToStep(_currentStep - 1);
  }

  // ===========================================================================
  // EXIT
  // ===========================================================================

  /// Leaves the wizard. Only asks for confirmation when there is actually
  /// something typed that would be lost.
  Future<void> _leave() async {
    if (_draft.hasAnyData) {
      final discard = await showWizardConfirm(
        context: context,
        title: 'Discard this lot?',
        message:
        'Nothing has been saved yet. If you leave now, everything '
            'you entered will be lost.',
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
  // SAVED
  // ===========================================================================

  void _onSaved(TradingPurchase lot) {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      fastRoute(
        PurchaseSuccessScreen(lot: lot),
      ),
    );
  }

  // ===========================================================================
  // PAGES
  // ===========================================================================

  Widget _buildPage(int index) {
    switch (index) {
      case _sellerPage:
        return Step1SellerDetails(
          formKey: _sellerFormKey,
          draft: _draft,
        );

      case _purchasePage:
        return Step2PurchaseDetails(
          formKey: _purchaseFormKey,
          draft: _draft,
        );

      case _paymentPage:
        return StepLotPayment(
          formKey: _paymentFormKey,
          draft: _draft,
        );

      case _receivingPage:
        return Step3ReceivingTransport(
          formKey: _receivingFormKey,
          draft: _draft,
        );

      case _summaryPage:
        return Step4Summary(
          key: _summaryKey,
          draft: _draft,
          savingNotifier: _saving,
          onSaved: _onSaved,
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
        if (didPop || _saving.value) return;

        await _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          leading: ValueListenableBuilder<bool>(
            valueListenable: _saving,
            builder: (context, saving, _) {
              return IconButton(
                onPressed: (_moving || saving) ? null : _back,
                icon: Icon(
                  _currentStep == _sellerPage
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                ),
                color: AppColors.textDark,
                tooltip: _currentStep == _sellerPage ? 'Close' : 'Back',
              );
            },
          ),
          title: Text(
            'Purchase Lot',
            style: AppTheme.heading(size: 19),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ----------------------------------------------------------
              // PROGRESS (one "Step x of y" only — the title row below no
              // longer repeats it)
              // ----------------------------------------------------------

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: WizardStepIndicator(
                  currentStep: _flowPosition,
                  labels: _flow.map((s) => _stepLabels[s]!).toList(),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _stepTitle,
                    style: AppTheme.heading(size: 17),
                  ),
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

        // A real bottomNavigationBar (rather than a widget inside the body)
        // so floating snackbars sit ABOVE it instead of covering the
        // Back / Next buttons.
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  // ===========================================================================
  // BOTTOM BAR
  // ===========================================================================

  Widget _buildBottomBar() {
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
          child: ValueListenableBuilder<bool>(
            valueListenable: _saving,
            builder: (context, saving, _) {
              final busy = _moving || saving;
              final isSummary = _currentStep == _summaryPage;

              return Row(
                children: [
                  if (_currentStep > _sellerPage) ...[
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
                        child: isSummary
                            ? _saveLabel(saving)
                            : _nextLabel(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _saveLabel(bool saving) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (saving)
          const SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        else
          const Icon(Icons.save_rounded, size: 20),
        const SizedBox(width: 8),
        Text(
          saving ? 'Saving…' : 'Save Lot',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _nextLabel() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Next',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        SizedBox(width: 7),
        Icon(Icons.arrow_forward_rounded, size: 20),
      ],
    );
  }
}

// ============================================================================
// CHOICE TILE (receiving popup)
// ============================================================================

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: highlighted ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted
                  ? AppColors.primaryGreen
                  : AppColors.divider,
              width: highlighted ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.darkGreen, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.heading(
                        size: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.body(size: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}