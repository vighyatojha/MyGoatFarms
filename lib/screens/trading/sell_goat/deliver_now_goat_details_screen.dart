import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_draft.dart';
import '../../../services/image_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../palai/fullscreen_image_viewer.dart';

/// Sell Goat → Delivery → DELIVER NOW → THIS STEP → sale saved.
///
/// Only for Deliver Now: the customer takes the goats today, so each goat's
/// photo, approximate age and weight are recorded for the customer's
/// purchase history before the sale is finished.
///
///  * Photo — required (camera / gallery).
///  * Approx. age — required, in months (pre-filled from the goat).
///  * Weight — the selling weight from Goat Details (Step 3). Shown here,
///    not edited: the bill on the Delivery step was worked out from it, so
///    changing it now would change amounts already entered.
///
/// Everything is kept in the [SaleDraft]; the wizard saves it onto the
/// goats right before it saves the sale. Finish Sale pops `true`; Back pops
/// nothing and returns to Delivery with nothing saved.
class DeliverNowGoatDetailsScreen extends StatefulWidget {
  final SaleDraft draft;

  const DeliverNowGoatDetailsScreen({super.key, required this.draft});

  @override
  State<DeliverNowGoatDetailsScreen> createState() =>
      _DeliverNowGoatDetailsScreenState();
}

class _DeliverNowGoatDetailsScreenState
    extends State<DeliverNowGoatDetailsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ages = {};

  bool _submitted = false;
  String? _pickingFor;

  SaleDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    for (final goat in _draft.selectedGoats) {
      final age = _draft.ageMonthsFor(goat);
      _ages[goat.id] = TextEditingController(text: age > 0 ? '$age' : '');
    }
  }

  @override
  void dispose() {
    for (final c in _ages.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _pickPhoto(Goat goat) async {
    if (_pickingFor != null) return;
    setState(() => _pickingFor = goat.id);
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null || !mounted) return;
      setState(() => _draft.setPhoto(goat, picked.bytes, picked.contentType));
    } on ImageTooLargeException {
      if (mounted) _snack('That photo is too large. Choose another.');
    } catch (_) {
      if (mounted) _snack('Could not add the photo. Try again.');
    } finally {
      if (mounted) setState(() => _pickingFor = null);
    }
  }

  void _finish() {
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);

    final fieldsOk = _formKey.currentState?.validate() ?? false;

    for (final goat in _draft.selectedGoats) {
      if (!_draft.hasPhoto(goat)) {
        _snack('Add a photo of ${goat.id}.');
        return;
      }
    }
    if (!fieldsOk) return;

    for (final goat in _draft.selectedGoats) {
      final months = int.tryParse(_ages[goat.id]!.text.trim()) ?? 0;
      _draft.setAgeMonths(goat, months);
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final goats = _draft.selectedGoats;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Goat details', style: AppTheme.heading(size: 17)),
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
            child: ElevatedButton.icon(
              onPressed: _pickingFor != null ? null : _finish,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text(
                'Finish Sale',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'The customer is taking delivery now. Add a photo and the '
                    'approximate age of each goat — they are kept in the '
                    'customer\'s purchase history with the weight.',
                style: AppTheme.body(size: 11.5, color: AppColors.textDark),
              ),
            ),
            const SizedBox(height: 12),
            for (final goat in goats) ...[
              _goatCard(goat),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _goatCard(Goat goat) {
    final photo = _draft.photoFor(goat);
    final missing = _submitted && photo == null;
    final weight = _draft.weightFor(goat);

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
            onTap: () => _pickPhoto(goat),
            onLongPress: photo == null
                ? null
                : () => Navigator.of(context).push(
              fastRoute(
                FullscreenImageViewer(imageBytes: photo, title: goat.id),
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
              child: _pickingFor == goat.id
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
                  Icon(Icons.add_a_photo_outlined,
                      color: missing
                          ? AppColors.error
                          : AppColors.primaryGreen),
                  const SizedBox(height: 4),
                  Text('Photo',
                      style: AppTheme.body(
                        size: 10.5,
                        color: missing
                            ? AppColors.error
                            : AppColors.darkGreen,
                      )),
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
                      child: Text(goat.id, style: AppTheme.heading(size: 14)),
                    ),
                    if (photo != null)
                      GestureDetector(
                        onTap: () => _pickPhoto(goat),
                        child: Text('Change photo',
                            style: AppTheme.body(
                              size: 11,
                              color: AppColors.darkGreen,
                              weight: FontWeight.w600,
                            )),
                      ),
                  ],
                ),
                if (goat.breed.trim().isNotEmpty)
                  Text(goat.breed.trim(), style: AppTheme.body(size: 11)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ages[goat.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTheme.body(size: 13, color: AppColors.textDark),
                  decoration: _decoration('Approx. age (months)'),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return n == null || n <= 0 ? 'Enter the age' : null;
                  },
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: _decoration('Weight'),
                  child: Text(
                    '${SaleDraft.formatWeight(weight)} kg  ·  from Goat Details',
                    style: AppTheme.body(size: 13, color: AppColors.textDark),
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