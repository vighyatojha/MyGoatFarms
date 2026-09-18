import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../palai/fullscreen_image_viewer.dart';
import 'complete_booking_delivery_screen.dart';

class GoatStockDetailScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const GoatStockDetailScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<GoatStockDetailScreen> createState() =>
      _GoatStockDetailScreenState();
}

class _GoatStockDetailScreenState
    extends State<GoatStockDetailScreen> {
  bool _loadingPurchase = false;

  Color _statusColor(String status) {
    switch (status) {
      case Goat.statusAvailable:
        return AppColors.success;

      case Goat.statusBooked:
        return AppColors.warning;

      case Goat.statusWaitOnDelivery:
        return AppColors.warning;

      case Goat.statusSold:
        return AppColors.error;

      case Goat.statusInCustomerPalai:
        return AppColors.info;

      case Goat.statusOwnPalai:
        return AppColors.tradingBlue;

      default:
        return AppColors.textGrey;
    }
  }

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor:
        isError
            ? AppColors.error
            : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ===========================================================================
  // COMPLETE DELIVERY
  // ===========================================================================

  Future<void> _openCompleteBookingDelivery() async {
    final completed = await Navigator.of(context).push<bool>(
      fastRoute(
        CompleteBookingDeliveryScreen(
          farmId: widget.farmId,
          goat: widget.goat,
        ),
      ),
    );

    // The Goat instance this screen was built with is a static snapshot
    // (not a stream), so once the delivery is completed we pop back to
    // the goat list, which streams live and will already show the goat
    // as Sold — rather than showing a stale "Booked" status here.
    if (completed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ===========================================================================
  // PURCHASE
  // ===========================================================================

  Future<void> _openPurchase() async {
    final purchaseId = widget.goat.purchaseId;

    if (purchaseId.trim().isEmpty) {
      _showSnack(
        'No linked purchase found for this goat.',
        isError: true,
      );
      return;
    }

    setState(() {
      _loadingPurchase = true;
    });

    try {
      final purchase =
      await TradingService.instance.getPurchase(
        widget.farmId,
        purchaseId,
      );

      if (!mounted) return;

      if (purchase == null) {
        _showSnack(
          'That purchase record could not be found.',
          isError: true,
        );
        return;
      }

      _showPurchaseSheet(purchase);
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingPurchase = false;
        });
      }
    }
  }

  void _showPurchaseSheet(
      TradingPurchase purchase,
      ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            28,
          ),
          decoration: const BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius:
                      BorderRadius.circular(4),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.tradingBlue
                            .withOpacity(0.10),
                        borderRadius:
                        BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color:
                        AppColors.tradingBlue,
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
                            'Purchase Details',
                            style: AppTheme.heading(
                              size: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            purchase.id,
                            style: AppTheme.body(
                              size: 10,
                              color:
                              AppColors.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color:
                    AppColors.paleGreen,
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _sheetRow(
                        'Seller',
                        purchase.sellerName,
                      ),
                      _sheetRow(
                        'Mobile',
                        purchase.mobile,
                      ),
                      _sheetRow(
                        'Market',
                        purchase.market,
                      ),
                      _sheetRow(
                        'Purchase Date',
                        DateFormat(
                          'dd MMM yyyy',
                        ).format(
                          purchase.purchaseDate,
                        ),
                      ),
                      _sheetRow(
                        'Total Goats',
                        '${purchase.totalGoats}',
                      ),
                      _sheetRow(
                        'Registered',
                        '${purchase.registeredCount}/${purchase.totalGoats}',
                        isLast: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetRow(
      String label,
      String value, {
        bool isLast = false,
      }) {
    return Padding(
      padding: EdgeInsets.only(
        top: 5,
        bottom: isLast ? 0 : 5,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;
    final statusColor =
    _statusColor(goat.currentStatus);

    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 20,
        title: Text(
          'Goat Details',
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
            28,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              // ---------------------------------------------------------------
              // PHOTO + ID
              // ---------------------------------------------------------------

              _profileHeader(
                goat,
                statusColor,
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // AGE + WEIGHT
              // ---------------------------------------------------------------

              Row(
                children: [
                  Expanded(
                    child: _highlightCard(
                      icon:
                      Icons.calendar_month_outlined,
                      label: 'Age',
                      value: goat.age,
                      color:
                      AppColors.tradingBlue,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _highlightCard(
                      icon:
                      Icons.monitor_weight_outlined,
                      label: 'Weight',
                      value:
                      '${goat.weight.toStringAsFixed(1)} kg',
                      color:
                      AppColors.stockTeal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // GOAT INFORMATION
              // ---------------------------------------------------------------

              _sectionCard(
                title: 'Goat Information',
                icon: Icons.pets_outlined,
                children: [
                  _infoRow(
                    'Breed',
                    goat.breed,
                  ),
                  _infoRow(
                    'Color',
                    goat.color,
                  ),
                  _infoRow(
                    'Health Status',
                    goat.healthStatus,
                  ),
                  if (goat.notes.trim().isNotEmpty)
                    _notesRow(goat.notes),
                ],
              ),

              const SizedBox(height: 14),

              // ---------------------------------------------------------------
              // PURCHASE / ORIGIN
              // ---------------------------------------------------------------

              _sectionCard(
                title: 'Purchase & Origin',
                icon:
                Icons.receipt_long_outlined,
                children: [
                  _infoRow(
                    'Purchase Date',
                    DateFormat(
                      'dd MMM yyyy',
                    ).format(
                      goat.purchaseDate,
                    ),
                  ),

                  _purchaseIdRow(),
                ],
              ),

              // ---------------------------------------------------------------
              // SALE INFORMATION / COMPLETE DELIVERY
              //
              // Booked goats get a "Complete Delivery" action here per
              // the Phase 5 plan's Task 1.1 ("wherever Booked goats are
              // visible"). Wait for Delivery's equivalent action lands
              // in the next Phase 5 task.
              // ---------------------------------------------------------------

              if (goat.currentStatus == Goat.statusBooked) ...[
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Sale Information',
                  icon: Icons.receipt_long_outlined,
                  children: [
                    _infoRow(
                      'Sale ID',
                      goat.saleId ?? '—',
                    ),
                    _infoRow(
                      'Status',
                      'Booked — awaiting pickup',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _openCompleteBookingDelivery,
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 19,
                    ),
                    label: const Text(
                      'Complete Delivery',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PROFILE HEADER
  // ===========================================================================

  Widget _profileHeader(
      Goat goat,
      Color statusColor,
      ) {
    final hasPhoto = goat.photo != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
        radius: 16,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: hasPhoto
                ? () {
              Navigator.of(context).push(
                fastRoute(
                  FullscreenImageViewer(
                    imageBytes: goat.photo!,
                    title: goat.id,
                  ),
                ),
              );
            }
                : null,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.stockTeal
                    .withOpacity(0.10),
                borderRadius:
                BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.stockTeal
                      .withOpacity(0.18),
                ),
                image: hasPhoto
                    ? DecorationImage(
                  image: MemoryImage(
                    goat.photo!,
                  ),
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: hasPhoto
                  ? null
                  : const Icon(
                Icons.pets_outlined,
                color:
                AppColors.stockTeal,
                size: 32,
              ),
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  goat.id,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 17,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  goat.breed.isEmpty
                      ? 'Breed not specified'
                      : goat.breed,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 11,
                    color:
                    AppColors.textGrey,
                  ),
                ),

                const SizedBox(height: 9),

                Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor
                        .withOpacity(0.10),
                    borderRadius:
                    BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    goat.currentStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight:
                      FontWeight.w700,
                    ),
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
  // HIGHLIGHT CARD
  // ===========================================================================

  Widget _highlightCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.14),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius:
              BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 17,
              color: color,
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(
                    size: 9,
                    color:
                    AppColors.textGrey,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 13,
                    color:
                    AppColors.textDark,
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
  // SECTION CARD
  // ===========================================================================

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
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
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen
                      .withOpacity(0.09),
                  borderRadius:
                  BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color:
                  AppColors.primaryGreen,
                  size: 16,
                ),
              ),

              const SizedBox(width: 9),

              Text(
                title,
                style: AppTheme.heading(
                  size: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 11),

          Container(
            height: 1,
            color: AppColors.divider,
          ),

          const SizedBox(height: 2),

          ...children,
        ],
      ),
    );
  }

  // ===========================================================================
  // INFO ROW
  // ===========================================================================

  Widget _infoRow(
      String label,
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),

          Expanded(
            child: Text(
              value.trim().isEmpty
                  ? '—'
                  : value,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  Widget _notesRow(String notes) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 3,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          ),

          const SizedBox(height: 5),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.paleGreen,
              borderRadius:
              BorderRadius.circular(10),
            ),
            child: Text(
              notes,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PURCHASE ID
  // ===========================================================================

  Widget _purchaseIdRow() {
    final purchaseId =
        widget.goat.purchaseId;

    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 3,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              'Purchase ID',
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
              ),
            ),
          ),

          Expanded(
            child: purchaseId.trim().isEmpty
                ? Text(
              '—',
              style: AppTheme.body(
                size: 11,
                color:
                AppColors.textDark,
              ),
            )
                : GestureDetector(
              onTap: _openPurchase,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      purchaseId,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        fontSize: 11,
                        fontWeight:
                        FontWeight.w700,
                        color: AppColors
                            .tradingBlue,
                        decoration:
                        TextDecoration
                            .underline,
                      ),
                    ),
                  ),

                  const SizedBox(width: 5),

                  if (_loadingPurchase)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  else
                    const Icon(
                      Icons
                          .chevron_right_rounded,
                      size: 17,
                      color: AppColors
                          .tradingBlue,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}