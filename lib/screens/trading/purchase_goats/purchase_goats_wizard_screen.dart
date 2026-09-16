import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_draft.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../widgets/fast_route.dart';
import 'purchase_wizard_widgets.dart';
import 'purchase_success_screen.dart';
import '../steps/step1_seller_details.dart';
import '../steps/step2_purchase_details.dart';
import '../steps/step3_receiving_transport.dart';
import '../steps/step4_summary.dart';

/// Purchase Goat wizard.
///
/// Flow:
/// Step 1  -> Seller Details
/// Step 2  -> Purchase Details
///          -> Fill Receiving Details Now
///          -> Later
///
/// If receiving is done now:
/// Step 3  -> Receiving + Transport
/// Step 4  -> Summary
///          -> Save
///
/// If receiving is done later:
/// Step 4  -> Summary
///          -> Save
///          -> Pending Receiving appears on Trading Dashboard.
class PurchaseGoatsWizardScreen extends StatefulWidget {
  const PurchaseGoatsWizardScreen({
    super.key,
  });

  @override
  State<PurchaseGoatsWizardScreen> createState() =>
      _PurchaseGoatsWizardScreenState();
}

class _PurchaseGoatsWizardScreenState
    extends State<PurchaseGoatsWizardScreen> {
  final PageController _pageController = PageController();

  final GlobalKey<FormState> _sellerFormKey =
  GlobalKey<FormState>();

  final GlobalKey<FormState> _purchaseFormKey =
  GlobalKey<FormState>();

  final GlobalKey<FormState> _receivingFormKey =
  GlobalKey<FormState>();

  final GlobalKey<Step4SummaryState> _summaryKey =
  GlobalKey<Step4SummaryState>();

  final PurchaseDraft _draft = PurchaseDraft();

  int _currentStep = 0;

  bool _moving = false;

  static const List<String> _stepLabels = [
    'Seller',
    'Purchase',
    'Receiving',
    'Summary',
  ];

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
        return 'Seller Details';
      case 1:
        return 'Purchase Details';
      case 2:
        return 'Receiving Details';
      case 3:
        return 'Purchase Summary';
      default:
        return 'Purchase Goat';
    }
  }

  // ===========================================================================
  // NEXT
  // ===========================================================================

  Future<void> _next() async {
    if (_moving) return;

    FocusScope.of(context).unfocus();

    // -------------------------------------------------------------------------
    // STEP 1
    // -------------------------------------------------------------------------

    if (_currentStep == 0) {
      final valid =
          _sellerFormKey.currentState?.validate() ?? false;

      if (!valid) {
        return;
      }

      _sellerFormKey.currentState?.save();

      await _goToStep(1);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 2
    // -------------------------------------------------------------------------

    if (_currentStep == 1) {
      final valid =
          _purchaseFormKey.currentState?.validate() ?? false;

      if (!valid) {
        return;
      }

      _purchaseFormKey.currentState?.save();

      await _showReceivingChoice();
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 3
    // -------------------------------------------------------------------------

    if (_currentStep == 2) {
      final valid =
          _receivingFormKey.currentState?.validate() ?? false;

      if (!valid) {
        return;
      }

      _receivingFormKey.currentState?.save();

      _draft.markReceivingCompleted();

      await _goToStep(3);
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 4
    // -------------------------------------------------------------------------

    if (_currentStep == 3) {
      await _savePurchase();
    }
  }

  // ===========================================================================
  // RECEIVING CHOICE
  // ===========================================================================

  Future<void> _showReceivingChoice() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color:
                    AppColors.primaryGreen.withOpacity(0.10),
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
                  'Receiving Details',
                  style: AppTheme.heading(
                    size: 19,
                    color: AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  'Do you want to enter the goat receiving details now or complete them later?',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textGrey,
                  ),
                ),

                const SizedBox(height: 22),

                // ----------------------------------------------------------------
                // FILL NOW
                // ----------------------------------------------------------------

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop(true);
                    },
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      size: 22,
                    ),
                    label: const Text(
                      'Fill Receiving Details Now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ----------------------------------------------------------------
                // LATER
                // ----------------------------------------------------------------

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop(false);
                    },
                    icon: const Icon(
                      Icons.schedule_outlined,
                      size: 21,
                    ),
                    label: const Text(
                      'Later',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                      AppColors.primaryGreen,
                      side: BorderSide(
                        color: AppColors.primaryGreen
                            .withOpacity(0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    // -------------------------------------------------------------------------
    // RECEIVING NOW
    // -------------------------------------------------------------------------

    if (result) {
      _draft.receivingNow = true;
      _draft.receivingStatus = 'pending';

      await _goToStep(2);
      return;
    }

    // -------------------------------------------------------------------------
    // RECEIVING LATER
    // -------------------------------------------------------------------------

    _draft.markReceivingPending();

    await _goToStep(3);
  }

  // ===========================================================================
  // GO TO STEP
  // ===========================================================================

  Future<void> _goToStep(int step) async {
    if (_moving) return;

    if (step < 0 || step > 3) {
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
        duration: const Duration(
          milliseconds: 260,
        ),
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
    if (_moving) return;

    FocusScope.of(context).unfocus();

    if (_currentStep == 0) {
      final exit = await _confirmExit();

      if (!mounted || !exit) {
        return;
      }

      Navigator.of(context).pop();
      return;
    }

    // -------------------------------------------------------------------------
    // STEP 4
    // -------------------------------------------------------------------------

    if (_currentStep == 3) {
      if (_draft.isReceivingCompleted) {
        await _goToStep(2);
      } else {
        await _goToStep(1);
      }

      return;
    }

    // -------------------------------------------------------------------------
    // STEP 3
    // -------------------------------------------------------------------------

    if (_currentStep == 2) {
      await _goToStep(1);
      return;
    }

    await _goToStep(_currentStep - 1);
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _savePurchase() async {
    if (_summaryKey.currentState?.isSaving ?? false) {
      return;
    }

    await _summaryKey.currentState?.save();
  }

  // ===========================================================================
  // SAVED
  // ===========================================================================

  void _onSaved(TradingPurchase purchase) {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      fastRoute(
        PurchaseSuccessScreen(
          purchaseId: purchase.id,
          receivingPending:
          purchase.receivingStatus != 'completed',
        ),
      ),
    );
  }

  // ===========================================================================
  // PAGE CONTENT
  // ===========================================================================

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return Step1SellerDetails(
          formKey: _sellerFormKey,
          draft: _draft,
        );

      case 1:
        return Step2PurchaseDetails(
          formKey: _purchaseFormKey,
          draft: _draft,
        );

      case 2:
        return Step3ReceivingTransport(
          formKey: _receivingFormKey,
          draft: _draft,
        );

      case 3:
        return Step4Summary(
          key: _summaryKey,
          draft: _draft,
          onSaved: _onSaved,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // EXIT CONFIRMATION
  // ===========================================================================

  Future<bool> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Leave Purchase?',
          ),
          content: const Text(
            'Your entered purchase details will be lost if you leave now.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Stay',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Leave',
              ),
            ),
          ],
        );
      },
    );

    return shouldExit ?? false;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }

        if (_currentStep > 0) {
          await _back();
          return;
        }

        final exit = await _confirmExit();

        if (!mounted || !exit) {
          return;
        }

        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            onPressed: _moving ? null : _back,
            icon: const Icon(
              Icons.arrow_back_rounded,
            ),
            color: AppColors.textDark,
          ),
          title: Text(
            'Purchase Goat',
            style: AppTheme.heading(
              size: 19,
              color: AppColors.textDark,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ----------------------------------------------------------------
              // STEP INDICATOR
              // ----------------------------------------------------------------

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

              // ----------------------------------------------------------------
              // STEP TITLE
              // ----------------------------------------------------------------

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  4,
                  18,
                  10,
                ),
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
                      'Step ${_currentStep + 1} of 4',
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
                  physics:
                  const NeverScrollableScrollPhysics(),
                  itemCount: 4,
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

              // ----------------------------------------------------------------
              // BOTTOM ACTION BAR
              // ----------------------------------------------------------------

              Container(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  14,
                ),
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
                            onPressed:
                            _moving ? null : _back,
                            style:
                            OutlinedButton.styleFrom(
                              foregroundColor:
                              AppColors.primaryGreen,
                              side: BorderSide(
                                color: AppColors
                                    .primaryGreen
                                    .withOpacity(0.35),
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  15,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.w700,
                              ),
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
                          onPressed:
                          _moving ? null : _next,
                          style:
                          ElevatedButton.styleFrom(
                            backgroundColor:
                            AppColors.primaryGreen,
                            foregroundColor:
                            Colors.white,
                            elevation: 1,
                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(15),
                            ),
                          ),
                          child: _currentStep == 3
                              ? Row(
                            mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                            children: [
                              if (_summaryKey
                                  .currentState
                                  ?.isSaving ??
                                  false)
                                const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child:
                                  CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                    AlwaysStoppedAnimation<
                                        Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.save_rounded,
                                  size: 20,
                                ),
                              const SizedBox(
                                width: 8,
                              ),
                              const Text(
                                'Save Purchase',
                                style: TextStyle(
                                  fontWeight:
                                  FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                              : Row(
                            mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                            children: const [
                              Text(
                                'Next',
                                style: TextStyle(
                                  fontWeight:
                                  FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(width: 7),
                              Icon(
                                Icons
                                    .arrow_forward_rounded,
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
          ),
        ),
      ),
    );
  }
}