import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../widgets/fast_route.dart';
import '../goat_stock/goat_stock_list_screen.dart';
import '../own_palai/move_to_own_palai_screen.dart';

/// Registration completed screen.
///
/// Shown when all goats belonging to a purchase have been registered.
///
/// UX goals:
/// - Compact success confirmation.
/// - Clear purchase summary.
/// - Symmetrical statistics.
/// - One clear primary action.
/// - Secondary actions kept visually lighter.
/// - Uses the app's default AppTheme/AppColors.
class RegistrationCompletedScreen extends StatelessWidget {
  final String farmId;
  final TradingPurchase purchase;

  const RegistrationCompletedScreen({
    super.key,
    required this.farmId,
    required this.purchase,
  });

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  void _viewGoatStock(BuildContext context) {
    Navigator.of(context).push(
      fastRoute(
        const GoatStockListScreen(),
      ),
    );
  }

  void _moveToOwnPalai(BuildContext context) {
    Navigator.of(context).push(
      fastRoute(
        MoveToOwnPalaiScreen(
          farmId: farmId,
        ),
      ),
    );
  }

  void _sellGoat(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Sell Goat will be available in the next Trading phase.',
        ),
        backgroundColor: AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _backToTrading(BuildContext context) {
    Navigator.of(context).popUntil(
          (route) => route.isFirst,
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Registration Completed',
          style: AppTheme.heading(
            size: 17,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------------------
              // SUCCESS HEADER
              // ----------------------------------------------------------------

              _successHeader(),

              const SizedBox(height: 18),

              // ----------------------------------------------------------------
              // PURCHASE SUMMARY
              // ----------------------------------------------------------------

              _purchaseSummary(),

              const SizedBox(height: 18),

              // ----------------------------------------------------------------
              // PRIMARY ACTION
              // ----------------------------------------------------------------

              _primaryAction(
                icon: Icons.inventory_2_outlined,
                title: 'View Goat Stock',
                subtitle:
                'View all registered goats',
                onTap: () =>
                    _viewGoatStock(context),
              ),

              const SizedBox(height: 12),

              // ----------------------------------------------------------------
              // SECONDARY ACTIONS
              // ----------------------------------------------------------------

              Row(
                children: [
                  Expanded(
                    child: _actionCard(
                      icon:
                      Icons.holiday_village_outlined,
                      title: 'Own Palai',
                      subtitle:
                      'Move goat',
                      iconColor:
                      AppColors.tradingBlue,
                      backgroundColor:
                      AppColors.tradingBlue
                          .withOpacity(0.07),
                      onTap: () =>
                          _moveToOwnPalai(context),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _actionCard(
                      icon: Icons.sell_outlined,
                      title: 'Sell Goat',
                      subtitle:
                      'Start selling',
                      iconColor:
                      AppColors.warning,
                      backgroundColor:
                      AppColors.warning
                          .withOpacity(0.08),
                      onTap: () =>
                          _sellGoat(context),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ----------------------------------------------------------------
              // BACK TO TRADING
              // ----------------------------------------------------------------

              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () =>
                      _backToTrading(context),
                  style: TextButton.styleFrom(
                    foregroundColor:
                    AppColors.textGrey,
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(13),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons
                            .arrow_back_rounded,
                        size: 17,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Back to Trading',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SUCCESS HEADER
  // ===========================================================================

  Widget _successHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color:
              AppColors.success.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 28,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Registration Completed',
                  style: AppTheme.heading(
                    size: 15,
                    color: AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  'All ${purchase.totalGoats} goats have been '
                      'successfully added to Goat Stock.',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PURCHASE SUMMARY
  // ===========================================================================

  Widget _purchaseSummary() {
    final formattedPurchaseDate =
    DateFormat('dd MMM yyyy').format(
      purchase.purchaseDate,
    );

    final registrationDate =
    DateFormat('dd MMM yyyy').format(
      DateTime.now(),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: AppTheme.card(
        radius: 15,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          // ---------------------------------------------------------------
          // PURCHASE ID
          // ---------------------------------------------------------------

          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                  AppColors.primaryGreen
                      .withOpacity(0.10),
                  borderRadius:
                  BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color:
                  AppColors.primaryGreen,
                  size: 19,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Purchase',
                      style: AppTheme.body(
                        size: 9,
                        color:
                        AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      purchase.id,
                      style: AppTheme.heading(
                        size: 14,
                        color:
                        AppColors
                            .primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                  AppColors.success
                      .withOpacity(0.10),
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: Text(
                  'Completed',
                  style: AppTheme.body(
                    size: 9,
                    color:
                    AppColors.success,
                    weight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            height: 1,
            color: AppColors.divider,
          ),

          const SizedBox(height: 14),

          // ---------------------------------------------------------------
          // STATS
          // ---------------------------------------------------------------

          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  icon:
                  Icons.calendar_today_outlined,
                  label: 'Purchase Date',
                  value:
                  formattedPurchaseDate,
                ),
              ),

              _verticalDivider(),

              Expanded(
                child: _summaryStat(
                  icon:
                  Icons.event_available_outlined,
                  label: 'Registered On',
                  value:
                  registrationDate,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  icon:
                  GoatIcons.paw,
                  label: 'Total Goats',
                  value:
                  '${purchase.totalGoats}',
                ),
              ),

              _verticalDivider(),

              Expanded(
                child: _summaryStat(
                  icon:
                  Icons.check_circle_outline,
                  label: 'Registered',
                  value:
                  '${purchase.registeredCount}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUMMARY STAT
  // ===========================================================================

  Widget _summaryStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color:
            AppColors.primaryGreen
                .withOpacity(0.08),
            borderRadius:
            BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 15,
            color:
            AppColors.primaryGreen,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow:
                TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 9,
                  color:
                  AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                value,
                maxLines: 1,
                overflow:
                TextOverflow.ellipsis,
                style: AppTheme.heading(
                  size: 11,
                  color:
                  AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // VERTICAL DIVIDER
  // ===========================================================================

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      color: AppColors.divider,
    );
  }

  // ===========================================================================
  // PRIMARY ACTION
  // ===========================================================================

  Widget _primaryAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 66,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
          AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding:
          const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(14),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white
                    .withOpacity(0.15),
                borderRadius:
                BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: Colors.white,
              ),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Column(
                mainAxisAlignment:
                MainAxisAlignment.center,
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                    const TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style:
                    TextStyle(
                      fontSize: 10,
                      color: Colors.white
                          .withOpacity(0.78),
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons
                  .arrow_forward_rounded,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECONDARY ACTION CARD
  // ===========================================================================

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(14),
        child: Container(
          height: 96,
          padding:
          const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius:
            BorderRadius.circular(14),
            border: Border.all(
              color:
              iconColor.withOpacity(0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                  iconColor.withOpacity(
                    0.12,
                  ),
                  borderRadius:
                  BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: iconColor,
                ),
              ),

              const Spacer(),

              Text(
                title,
                style: AppTheme.heading(
                  size: 11,
                  color:
                  AppColors.textDark,
                ),
              ),

              const SizedBox(height: 1),

              Text(
                subtitle,
                style: AppTheme.body(
                  size: 9,
                  color:
                  AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}