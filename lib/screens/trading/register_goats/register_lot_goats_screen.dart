import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/lot_goat_registration_service.dart';
import 'sale_goats_form.dart';

/// Registers goats of a Purchase Lot one by one — photo, weight, breed,
/// age, color, health — so every goat that is sold or booked has its own
/// identity and profile.
///
/// Two uses:
///  * [RegisterLotGoatsScreen.forSale] — Sell from Lot (goats at the
///    farm): the goats are registered as Available and the screen pops
///    with the new goats; the Sell Goat wizard then sells them.
///  * [RegisterLotGoatsScreen.forBooking] — an existing lot Booking / Wait
///    for Delivery: its goats become registered Booked / Waiting goats on
///    the same booking. Goats booked at the supplier are marked as arrived
///    at the farm at the same time. Pops `true` when done.
///
/// Saving is one transaction (see [LotGoatRegistrationService]); the save
/// button is locked while it runs, so goats are never created twice.
class RegisterLotGoatsScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase? lot;
  final int quantity;
  final Sale? sale;

  const RegisterLotGoatsScreen.forSale({
    super.key,
    required this.farmId,
    required TradingPurchase this.lot,
    required this.quantity,
  }) : sale = null;

  RegisterLotGoatsScreen.forBooking({
    super.key,
    required this.farmId,
    required Sale this.sale,
  })  : lot = null,
        quantity = sale.lotQuantity;

  bool get isBooking => sale != null;

  @override
  State<RegisterLotGoatsScreen> createState() => _RegisterLotGoatsScreenState();
}

class _RegisterLotGoatsScreenState extends State<RegisterLotGoatsScreen> {
  final GlobalKey<SaleGoatsFormState> _formKey =
  GlobalKey<SaleGoatsFormState>();

  bool _saving = false;
  DateTime _arrivalDate = DateTime.now();

  /// Photos uploaded while the goats were at the supplier — used to start
  /// the goat cards. Loaded once.
  List<Uint8List>? _uploaded;

  bool get _atSupplier =>
      widget.isBooking &&
          widget.sale!.sourceLocation == Sale.sourceSupplier;

  @override
  void initState() {
    super.initState();
    if (widget.isBooking) {
      _loadUploadedPhotos();
    } else {
      _uploaded = const [];
    }
  }

  Future<void> _loadUploadedPhotos() async {
    try {
      final photos = await LotGoatRegistrationService.instance
          .photosStream(widget.farmId, widget.sale!.id)
          .first
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => _uploaded = [for (final p in photos) p.bytes]);
    } catch (_) {
      if (mounted) setState(() => _uploaded = const []);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
      ),
    );
  }

  String _errorText(Object e) {
    if (e is StateError) return e.message;
    if (e is ArgumentError) return '${e.message}';
    return FirestoreService.instance.describeError(e);
  }

  Future<void> _pickArrivalDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _arrivalDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _arrivalDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final max = LotGoatRegistrationService.maxGoatsPerCall;
    if (widget.quantity > max) {
      _snack(
        widget.isBooking
            ? 'This booking holds ${widget.quantity} goats. Use Edit on the '
            'booking to split it into bookings of up to $max goats, then '
            'register each one.'
            : 'Register at most $max goats at a time.',
        error: true,
      );
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final specs = form.buildSpecs();
    setState(() => _saving = true);

    try {
      if (widget.isBooking) {
        await LotGoatRegistrationService.instance.convertLotBooking(
          farmId: widget.farmId,
          saleId: widget.sale!.id,
          goats: specs,
          arrivalDate: _atSupplier ? _arrivalDate : null,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final goats = await LotGoatRegistrationService.instance.registerForSale(
          farmId: widget.farmId,
          lotDocId: widget.lot!.id,
          goats: specs,
        );
        if (!mounted) return;
        Navigator.of(context).pop<List<Goat>>(goats);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(_errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.quantity;
    final lotLabel = widget.isBooking
        ? widget.sale!.lotDisplayId
        : widget.lot!.lotId;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          elevation: 0,
          foregroundColor: AppColors.textDark,
          title: Text(
            count == 1 ? 'Register goat' : 'Register $count goats',
            style: AppTheme.heading(size: 17),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: const BoxDecoration(
              color: AppColors.paleGreen,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving || _uploaded == null ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
                    : Text(
                  widget.isBooking
                      ? 'Register & keep booking'
                      : 'Register & continue to sale',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: _uploaded == null
            ? const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        )
            : ListView(
          keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: [
            _intro(lotLabel),
            const SizedBox(height: 12),
            if (_atSupplier) ...[
              _arrivalCard(),
              const SizedBox(height: 12),
            ],
            SaleGoatsForm(
              key: _formKey,
              count: count,
              initialPhotos: _uploaded!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(String lotLabel) {
    final text = widget.isBooking
        ? 'Booking ${widget.sale!.id} for ${widget.sale!.customerName} holds '
        '${widget.quantity} goat${widget.quantity == 1 ? '' : 's'} from '
        '$lotLabel. Add each goat\'s photo and details — the booking, '
        'its price and the money already paid stay the same.'
        : 'Each goat sold from $lotLabel gets its own ID, photo and '
        'details, so the customer\'s goats can be recognised at '
        'delivery. After this, the sale continues as usual.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: AppTheme.body(size: 11.5, color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _arrivalCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 14),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arrived at the farm on',
                    style: AppTheme.body(size: 11)),
                Text(DateFormat('d MMM yyyy').format(_arrivalDate),
                    style: AppTheme.heading(size: 14)),
                Text(
                  'These goats were booked at the supplier. Saving marks '
                      'them as received at the farm; the weights below are '
                      'their arrival weights.',
                  style: AppTheme.body(size: 10.5),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _pickArrivalDate,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}