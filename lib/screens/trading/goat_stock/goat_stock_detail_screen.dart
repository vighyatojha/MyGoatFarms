import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../palai/fullscreen_image_viewer.dart';
import '../sale_receipt_screen.dart';
import 'complete_booking_delivery_screen.dart';
import 'complete_wait_for_delivery_screen.dart';

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
        isError ? AppColors.error : AppColors.primaryGreen,
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

    if (completed == true && mounted) {
      _replaceWithSaleReceipt();
    }
  }

  Future<void> _openCompleteWaitForDelivery() async {
    final completed = await Navigator.of(context).push<bool>(
      fastRoute(
        CompleteWaitForDeliveryScreen(
          farmId: widget.farmId,
          goat: widget.goat,
        ),
      ),
    );

    if (completed == true && mounted) {
      _replaceWithSaleReceipt();
    }
  }

  // ===========================================================================
  // SALE RECEIPT
  // ===========================================================================

  bool _hasSale(Goat goat) =>
      (goat.saleId ?? '').trim().isNotEmpty;

  bool _awaitingPickup(Goat goat) =>
      goat.currentStatus == Goat.statusBooked ||
          goat.currentStatus == Goat.statusWaitOnDelivery;

  String _saleStatusLabel(Goat goat) {
    if (goat.currentStatus == Goat.statusBooked) {
      return 'Booked — awaiting pickup';
    }

    if (goat.currentStatus == Goat.statusWaitOnDelivery) {
      return 'Wait for Delivery — awaiting pickup';
    }

    return goat.currentStatus;
  }

  void _openSaleReceipt() {
    final saleId = (widget.goat.saleId ?? '').trim();

    if (saleId.isEmpty) return;

    Navigator.of(context).push(
      fastRoute(
        SaleReceiptScreen(
          farmId: widget.farmId,
          saleId: saleId,
        ),
      ),
    );
  }

  void _replaceWithSaleReceipt() {
    final saleId = (widget.goat.saleId ?? '').trim();

    if (saleId.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushReplacement(
      fastRoute(
        SaleReceiptScreen(
          farmId: widget.farmId,
          saleId: saleId,
        ),
      ),
    );
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
      final purchase = await TradingService.instance.getPurchase(
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

  void _showPurchaseSheet(TradingPurchase purchase) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            24,
          ),
          decoration: const BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _iconBox(
                      Icons.receipt_long_outlined,
                      AppColors.tradingBlue,
                      size: 40,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Purchase Details',
                            style: AppTheme.heading(size: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            purchase.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _sheetRow('Seller', purchase.sellerName),
                      _sheetRow('Mobile', purchase.mobile),
                      _sheetRow('Market', purchase.market),
                      _sheetRow(
                        'Purchase Date',
                        DateFormat('dd MMM yyyy')
                            .format(purchase.purchaseDate),
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
                        Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
    final statusColor = _statusColor(goat.currentStatus);

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 20,
        toolbarHeight: 54,
        title: Text(
          'Goat Details',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _profileHeader(
                goat,
                statusColor,
              ),

              const SizedBox(height: 12),

              // -----------------------------------------------------------------
              // QUICK STATS
              // -----------------------------------------------------------------

              Row(
                children: [
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.calendar_month_outlined,
                      label: 'AGE',
                      value: goat.age,
                      color: AppColors.tradingBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.monitor_weight_outlined,
                      label: 'WEIGHT',
                      value:
                      '${goat.weight.toStringAsFixed(1)} kg',
                      color: AppColors.stockTeal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // -----------------------------------------------------------------
              // GOAT INFORMATION
              // -----------------------------------------------------------------

              _sectionCard(
                title: 'Goat Information',
                icon: GoatIcons.paw,
                children: [
                  _infoRow('Breed', goat.breed),
                  _infoRow('Color', goat.color),
                  _infoRow(
                    'Health Status',
                    goat.healthStatus,
                  ),
                  if (goat.notes.trim().isNotEmpty)
                    _notesRow(goat.notes),
                ],
              ),

              const SizedBox(height: 12),

              // -----------------------------------------------------------------
              // PURCHASE / ORIGIN
              // -----------------------------------------------------------------

              _sectionCard(
                title: 'Purchase & Origin',
                icon: Icons.receipt_long_outlined,
                children: [
                  _infoRow(
                    'Purchase Date',
                    DateFormat('dd MMM yyyy')
                        .format(goat.purchaseDate),
                  ),
                  _purchaseIdRow(),
                ],
              ),

              // -----------------------------------------------------------------
              // SALE
              // -----------------------------------------------------------------

              if (_hasSale(goat)) ...[
                const SizedBox(height: 12),

                _saleSection(
                  goat,
                  statusColor,
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
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 16),
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
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.stockTeal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color:
                  AppColors.stockTeal.withOpacity(0.14),
                ),
                image: hasPhoto
                    ? DecorationImage(
                  image: MemoryImage(goat.photo!),
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: hasPhoto
                  ? null
                  : const Icon(
                GoatIcons.paw,
                color: AppColors.stockTeal,
                size: 29,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goat.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  goat.breed.isEmpty
                      ? 'Breed not specified'
                      : goat.breed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        goat.currentStatus,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
  // QUICK STAT CARD
  // ===========================================================================

  Widget _highlightCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.065),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: color.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(
                    size: 8,
                    color: AppColors.textGrey,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
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
      padding: const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        11,
      ),
      decoration: AppTheme.card(radius: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(
                icon,
                AppColors.primaryGreen,
                size: 30,
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: AppTheme.heading(size: 13),
              ),
            ],
          ),
          const SizedBox(height: 9),
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
  // SALE SECTION
  // ===========================================================================

  Widget _saleSection(
      Goat goat,
      Color statusColor,
      ) {
    final awaitingPickup = _awaitingPickup(goat);

    // A Booking or Wait for Delivery sale has no receipt until its
    // delivery is completed — the holding charges / final weight and
    // amount aren't known before that.
    final receiptPending = awaitingPickup;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        14,
      ),
      decoration: AppTheme.card(radius: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(
                Icons.sell_outlined,
                AppColors.primaryGreen,
                size: 30,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Sale Information',
                  style: AppTheme.heading(size: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  goat.currentStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Container(
            height: 1,
            color: AppColors.divider,
          ),

          const SizedBox(height: 3),

          _infoRow(
            'Sale ID',
            goat.saleId!.trim(),
          ),

          _infoRow(
            'Status',
            _saleStatusLabel(goat),
          ),

          const SizedBox(height: 5),

          // -------------------------------------------------------------------
          // COMPLETE DELIVERY
          // -------------------------------------------------------------------

          if (awaitingPickup) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed:
                goat.currentStatus == Goat.statusBooked
                    ? _openCompleteBookingDelivery
                    : _openCompleteWaitForDelivery,
                icon: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                ),
                label: const Text(
                  'Complete Delivery',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // -------------------------------------------------------------------
          // RECEIPT
          // -------------------------------------------------------------------

          if (receiptPending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withOpacity(0.30),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The sale receipt is generated when the delivery '
                          'is completed.',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _openSaleReceipt,
                icon: const Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                ),
                label: const Text(
                  'View Sale Receipt',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: BorderSide(
                    color: AppColors.primaryGreen.withOpacity(0.65),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ICON BOX
  // ===========================================================================

  Widget _iconBox(
      IconData icon,
      Color color, {
        double size = 34,
      }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        icon,
        color: color,
        size: size <= 30 ? 15 : 18,
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
        vertical: 6.5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: AppTheme.body(
                size: 9.5,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: AppTheme.body(
                size: 10.5,
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
        top: 6,
        bottom: 3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: AppTheme.body(
              size: 9.5,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.paleGreen,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              notes,
              style: AppTheme.body(
                size: 10.5,
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
    final purchaseId = widget.goat.purchaseId;

    return Padding(
      padding: const EdgeInsets.only(
        top: 6,
        bottom: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              'Purchase ID',
              style: AppTheme.body(
                size: 9.5,
                color: AppColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: purchaseId.trim().isEmpty
                ? Text(
              '—',
              style: AppTheme.body(
                size: 10.5,
                color: AppColors.textDark,
              ),
            )
                : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openPurchase,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          purchaseId,
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color:
                            AppColors.tradingBlue,
                            decoration:
                            TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_loadingPurchase)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 1.8,
                          ),
                        )
                      else
                        const Icon(
                          Icons
                              .arrow_forward_ios_rounded,
                          size: 11,
                          color:
                          AppColors.tradingBlue,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}