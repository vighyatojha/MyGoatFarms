import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../palai/fullscreen_image_viewer.dart';

/// Task 3.2 — Goat detail view.
///
/// Shows a goat's full record: Photo, Goat ID, Breed, Age, Weight,
/// Purchase Date, Purchase ID, Current Status, per the phase 2 plan.
/// Color, Health Status and Notes are also shown — they're already on
/// the record from registration and there's no reason to hide them here.
///
/// Purchase ID is tappable, per the plan's traceability note: it opens
/// a summary sheet of the originating `tradingPurchases` doc (fetched
/// via TradingService — there's no dedicated purchase-detail screen in
/// the app yet, so a bottom sheet keeps this self-contained rather than
/// blocking Task 3.2 on building one).
class GoatStockDetailScreen extends StatefulWidget {
  final String farmId;
  final Goat goat;

  const GoatStockDetailScreen({
    super.key,
    required this.farmId,
    required this.goat,
  });

  @override
  State<GoatStockDetailScreen> createState() => _GoatStockDetailScreenState();
}

class _GoatStockDetailScreenState extends State<GoatStockDetailScreen> {
  bool _loadingPurchase = false;

  Color _statusColor(String status) {
    switch (status) {
      case Goat.statusAvailable:
        return AppColors.success;
      case Goat.statusBooked:
        return AppColors.warning;
      case Goat.statusSold:
        return AppColors.error;
      case Goat.statusInCustomerPalai:
        return AppColors.info;
      default:
        return AppColors.textGrey;
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primaryGreen,
      ),
    );
  }

  Future<void> _openPurchase() async {
    final purchaseId = widget.goat.purchaseId;

    if (purchaseId.trim().isEmpty) {
      _showSnack('No linked purchase found for this goat.', isError: true);
      return;
    }

    setState(() => _loadingPurchase = true);

    try {
      final purchase = await TradingService.instance.getPurchase(
        widget.farmId,
        purchaseId,
      );

      if (!mounted) return;

      if (purchase == null) {
        _showSnack('That purchase record could not be found.', isError: true);
        return;
      }

      _showPurchaseSheet(purchase);
    } catch (e) {
      _showSnack(FirestoreService.instance.describeError(e), isError: true);
    } finally {
      if (mounted) setState(() => _loadingPurchase = false);
    }
  }

  void _showPurchaseSheet(TradingPurchase purchase) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: const BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
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
                  const Icon(Icons.shopping_cart_outlined, color: AppColors.tradingBlue),
                  const SizedBox(width: 10),
                  Text(purchase.id, style: AppTheme.heading(size: 17)),
                ],
              ),
              const SizedBox(height: 16),
              _sheetRow('Seller', purchase.sellerName),
              _sheetRow('Mobile', purchase.mobile),
              _sheetRow('Market', purchase.market),
              _sheetRow(
                'Purchase Date',
                DateFormat('dd MMM yyyy').format(purchase.purchaseDate),
              ),
              _sheetRow('Total Goats', '${purchase.totalGoats}'),
              _sheetRow(
                'Registered',
                '${purchase.registeredCount}/${purchase.totalGoats}',
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTheme.body(size: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

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
        title: Text(goat.id, style: AppTheme.heading(size: 17)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _photo(goat)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    goat.currentStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _sectionCard(
                title: 'Goat Details',
                icon: Icons.pets_outlined,
                children: [
                  _detailRow('Goat ID', goat.id),
                  _detailRow('Breed', goat.breed),
                  _detailRow('Age', goat.age),
                  _detailRow('Weight', '${goat.weight.toStringAsFixed(1)} kg'),
                  _detailRow('Color', goat.color),
                  _detailRow('Health Status', goat.healthStatus),
                  if (goat.notes.trim().isNotEmpty)
                    _detailRow('Notes', goat.notes, isLast: true),
                ],
              ),

              const SizedBox(height: 16),

              _sectionCard(
                title: 'Origin',
                icon: Icons.receipt_long_outlined,
                children: [
                  _detailRow(
                    'Purchase Date',
                    DateFormat('dd MMM yyyy').format(goat.purchaseDate),
                  ),
                  _linkRow(
                    'Purchase ID',
                    goat.purchaseId.isEmpty ? '—' : goat.purchaseId,
                    onTap: goat.purchaseId.isEmpty ? null : _openPurchase,
                    loading: _loadingPurchase,
                    isLast: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo(Goat goat) {
    final hasPhoto = goat.photo != null;

    return GestureDetector(
      onTap: hasPhoto
          ? () => Navigator.of(context).push(
        fastRoute(
          FullscreenImageViewer(imageBytes: goat.photo!, title: goat.id),
        ),
      )
          : null,
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.stockTeal.withOpacity(0.14),
          image: hasPhoto
              ? DecorationImage(image: MemoryImage(goat.photo!), fit: BoxFit.cover)
              : null,
          border: Border.all(color: AppColors.stockTeal.withOpacity(0.3), width: 2),
        ),
        child: !hasPhoto
            ? const Icon(Icons.pets, color: AppColors.stockTeal, size: 48)
            : null,
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.stockTeal, size: 18),
              const SizedBox(width: 8),
              Text(title, style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: isLast ? 0 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTheme.body(size: 12)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(
      String label,
      String value, {
        VoidCallback? onTap,
        bool loading = false,
        bool isLast = false,
      }) {
    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: isLast ? 0 : 0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTheme.body(size: 12)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: onTap != null ? AppColors.tradingBlue : AppColors.textDark,
                        decoration: onTap != null ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    loading
                        ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.chevron_right, size: 16, color: AppColors.tradingBlue),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}