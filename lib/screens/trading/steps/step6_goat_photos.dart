import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_draft.dart';
import '../../../services/image_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../palai/fullscreen_image_viewer.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 6 — Goat Photos. The last step of a Deliver Now, Booking / Holding
/// or Wait for Delivery sale, in both the Sell Goat and the Sell from Lot
/// wizards; the sale is saved when it is completed. (Transfer to Palai
/// saves on Step 5.)
///
/// For every goat sold: a photo, the approximate age (months) and the
/// weight — shown on the Wait on Delivery / Booking & Holding goat list
/// and kept in the customer's purchase history.
///
///  * Registered goats (Sell Goat): photo and age go onto the goat. The
///    weight is the selling weight from Goat Details (Step 3) and is only
///    shown here — the bill was worked out from it.
///  * Lot sale (Sell from Lot, goats at the farm or at the supplier): the
///    goats are not registered, so each one gets a card "Goat 1..N" with
///    photo, age and weight, saved with the sale. Weights start at the
///    average of the sale weight; the bill stays on the sale weight from
///    Sale Details.
///
/// Everything is kept in the [SaleDraft], so going Back and forward keeps
/// what was entered.
class Step6GoatPhotos extends StatefulWidget {
  final SaleDraft draft;

  const Step6GoatPhotos({super.key, required this.draft});

  @override
  State<Step6GoatPhotos> createState() => Step6GoatPhotosState();
}

class Step6GoatPhotosState extends State<Step6GoatPhotos> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final List<TextEditingController> _ages = [];
  final List<TextEditingController> _weights = [];

  bool _submitted = false;
  int? _pickingFor;

  SaleDraft get _draft => widget.draft;
  bool get _isLot => _draft.isLotSale;

  int get _count =>
      _isLot ? _draft.lotGoatDetails.length : _draft.selectedGoats.length;

  @override
  void initState() {
    super.initState();

    if (_isLot) {
      _draft.ensureLotGoatDetails();
      for (final g in _draft.lotGoatDetails) {
        _ages.add(TextEditingController(
          text: g.ageMonths > 0 ? '${g.ageMonths}' : '',
        ));
        _weights.add(TextEditingController(
          text: g.weight > 0 ? SaleDraft.formatWeight(g.weight) : '',
        ));
      }
    } else {
      for (final goat in _draft.selectedGoats) {
        final age = _draft.ageMonthsFor(goat);
        _ages.add(TextEditingController(text: age > 0 ? '$age' : ''));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [..._ages, ..._weights]) {
      c.dispose();
    }
    super.dispose();
  }

  // ===========================================================================
  // DATA
  // ===========================================================================

  Uint8List? _photoAt(int i) => _isLot
      ? _draft.lotGoatDetails[i].photo
      : _draft.photoFor(_draft.selectedGoats[i]);

  bool _hasPhotoAt(int i) {
    final p = _photoAt(i);
    return p != null && p.isNotEmpty;
  }

  String _labelAt(int i) =>
      _isLot ? 'Goat ${i + 1}' : _draft.selectedGoats[i].id;

  void _setAge(int i, String text) {
    final months = int.tryParse(text.trim()) ?? 0;
    if (_isLot) {
      _draft.lotGoatDetails[i].ageMonths = months;
    } else if (months > 0) {
      _draft.setAgeMonths(_draft.selectedGoats[i], months);
    }
  }

  void _setWeight(int i, String text) {
    _draft.lotGoatDetails[i].weight =
        SaleDraft.round2(double.tryParse(text.trim()) ?? 0);
    setState(() {}); // running total
  }

  Future<void> _pickPhoto(int i) async {
    if (_pickingFor != null) return;
    setState(() => _pickingFor = i);
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null || !mounted) return;
      setState(() {
        if (_isLot) {
          _draft.lotGoatDetails[i]
            ..photo = picked.bytes
            ..photoContentType = picked.contentType;
        } else {
          _draft.setPhoto(
            _draft.selectedGoats[i],
            picked.bytes,
            picked.contentType,
          );
        }
      });
    } on ImageTooLargeException {
      if (mounted) {
        wizardSnack(context, 'That photo is too large. Choose another.',
            error: true);
      }
    } catch (_) {
      if (mounted) {
        wizardSnack(context, 'Could not add the photo. Try again.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _pickingFor = null);
    }
  }

  /// True when every goat has a photo, an age and (lot) a weight.
  bool validate() {
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);

    for (var i = 0; i < _count; i++) {
      if (!_hasPhotoAt(i)) {
        wizardSnack(context, 'Add a photo of ${_labelAt(i)}.', error: true);
        return false;
      }
    }

    if (!(_formKey.currentState?.validate() ?? false)) return false;

    // The list builds lazily, so cards scrolled out of view are not
    // checked by the Form — check every goat's values directly too.
    for (var i = 0; i < _count; i++) {
      if ((int.tryParse(_ages[i].text.trim()) ?? 0) <= 0) {
        wizardSnack(context, 'Enter the age of ${_labelAt(i)}.', error: true);
        return false;
      }
      if (_isLot && (double.tryParse(_weights[i].text.trim()) ?? 0) <= 0) {
        wizardSnack(context, 'Enter the weight of ${_labelAt(i)}.',
            error: true);
        return false;
      }
    }

    for (var i = 0; i < _count; i++) {
      _setAge(i, _ages[i].text);
      if (_isLot) _setWeight(i, _weights[i].text);
    }
    return true;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _intro(),
          const SizedBox(height: 12),
          for (var i = 0; i < _count; i++) ...[
            _goatCard(i),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _intro() {
    final lotTotal = _isLot
        ? '\nWeights entered: '
        '${SaleDraft.formatWeight(_draft.lotGoatDetailsWeight)} kg · '
        'sale weight ${SaleDraft.formatWeight(_draft.totalSellingWeight)} kg '
        '(the bill uses the sale weight).'
        : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${_draft.isDeliverNow ? 'The customer is taking the goats now.' : 'These goats are being held for the customer.'} '
            'Add a photo, the approximate age and the weight of each goat — '
            '${_draft.isDeliverNow ? '' : 'they are shown on the booking and '}'
            'kept in the customer\'s purchase history.$lotTotal',
        style: AppTheme.body(size: 11.5, color: AppColors.textDark),
      ),
    );
  }

  Widget _goatCard(int i) {
    final photo = _photoAt(i);
    final missing = _submitted && !_hasPhotoAt(i);
    final Goat? goat = _isLot ? null : _draft.selectedGoats[i];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 16).copyWith(
        border: Border.all(
          color: missing ? AppColors.error : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _pickPhoto(i),
            onLongPress: photo == null
                ? null
                : () => Navigator.of(context).push(
              fastRoute(
                FullscreenImageViewer(
                  imageBytes: photo,
                  title: _labelAt(i),
                ),
              ),
            ),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: missing ? AppColors.error : AppColors.divider,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _pickingFor == i
                  ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : photo != null
                  ? Image.memory(photo, fit: BoxFit.cover)
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: missing
                        ? AppColors.error
                        : AppColors.primaryGreen,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Photo',
                    style: AppTheme.body(
                      size: 10.5,
                      color: missing
                          ? AppColors.error
                          : AppColors.darkGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_labelAt(i),
                          style: AppTheme.heading(size: 14)),
                    ),
                    if (photo != null)
                      GestureDetector(
                        onTap: () => _pickPhoto(i),
                        child: Text(
                          'Change photo',
                          style: AppTheme.body(
                            size: 11,
                            color: AppColors.darkGreen,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (goat != null && goat.breed.trim().isNotEmpty)
                  Text(goat.breed.trim(), style: AppTheme.body(size: 11)),
                if (_isLot && _draft.lotDisplayId.isNotEmpty)
                  Text(_draft.lotDisplayId, style: AppTheme.body(size: 11)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ages[i],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTheme.body(size: 13, color: AppColors.textDark),
                  decoration: _decoration('Approx. age (months)'),
                  onChanged: (v) => _setAge(i, v),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return n == null || n <= 0 ? 'Enter the age' : null;
                  },
                ),
                const SizedBox(height: 8),
                if (_isLot)
                  TextFormField(
                    controller: _weights[i],
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    style: AppTheme.body(size: 13, color: AppColors.textDark),
                    decoration: _decoration('Weight (kg)'),
                    onChanged: (v) => _setWeight(i, v),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      return n == null || n <= 0 ? 'Enter the weight' : null;
                    },
                  )
                else
                  InputDecorator(
                    decoration: _decoration('Weight'),
                    child: Text(
                      '${SaleDraft.formatWeight(_draft.weightFor(goat!))} kg'
                          '  ·  from Goat Details',
                      style:
                      AppTheme.body(size: 13, color: AppColors.textDark),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: _border(AppColors.divider),
    enabledBorder: _border(AppColors.divider),
    focusedBorder: _border(AppColors.primaryGreen, 1.5),
    errorBorder: _border(AppColors.error),
    focusedErrorBorder: _border(AppColors.error, 1.5),
  );
}