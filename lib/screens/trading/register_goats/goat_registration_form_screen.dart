import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/image_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/photo_upload_circle.dart';
import 'registration_completed_screen.dart';

/// Single goat registration form.
///
/// The UI is intentionally compact and symmetrical:
/// - Equal-width Age / Weight fields, and Height / Length / Color below
///   them. Height and Length (cm) are optional; each is validated only
///   when filled in.
/// - Consistent label and field spacing.
/// - Age explanation is placed below the complete row instead of only
///   below the Age field.
/// - Actions are stacked so long button labels don't feel cramped.
/// - Goat age is saved in months and automatically increases over time.
class GoatRegistrationFormScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase purchase;

  const GoatRegistrationFormScreen({
    super.key,
    required this.farmId,
    required this.purchase,
  });

  @override
  State<GoatRegistrationFormScreen> createState() =>
      _GoatRegistrationFormScreenState();
}

class _GoatRegistrationFormScreenState
    extends State<GoatRegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _breedController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _colorController = TextEditingController();
  final _notesController = TextEditingController();

  String _healthStatus = Goat.healthStatusValues.first;
  String _gender = Goat.genderValues.first;

  Uint8List? _photoBytes;
  String? _photoContentType;

  bool _saving = false;

  late TradingPurchase _purchase;

  @override
  void initState() {
    super.initState();
    _purchase = widget.purchase;
  }

  @override
  void dispose() {
    _breedController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _lengthController.dispose();
    _colorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SNACKBAR
  // ===========================================================================

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
        isError ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ===========================================================================
  // PHOTO
  // ===========================================================================

  Future<void> _pickPhoto() async {
    try {
      final picked = await showImageSourceSheet(
        context,
        isGoatPhoto: true,
      );

      if (picked == null) return;

      setState(() {
        _photoBytes = picked.bytes;
        _photoContentType = picked.contentType;
      });
    } on ImageTooLargeException catch (e) {
      _showSnack(
        e.message,
        isError: true,
      );
    } catch (_) {
      _showSnack(
        'Could not add photo. Please try again.',
        isError: true,
      );
    }
  }

  // ===========================================================================
  // RESET
  // ===========================================================================

  void _clearFormForNextGoat() {
    _breedController.clear();
    _ageController.clear();
    _weightController.clear();
    _heightController.clear();
    _lengthController.clear();
    _colorController.clear();
    _notesController.clear();

    setState(() {
      _healthStatus = Goat.healthStatusValues.first;
      _gender = Goat.genderValues.first;
      _photoBytes = null;
      _photoContentType = null;
    });
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<TradingPurchase?> _saveGoat() async {
    if (!_formKey.currentState!.validate()) {
      return null;
    }

    final ageMonths =
        int.tryParse(_ageController.text.trim()) ?? 0;

    final weight =
        double.tryParse(_weightController.text.trim()) ?? 0;

    // Optional: blank means "not recorded" (0).
    final height =
        double.tryParse(_heightController.text.trim()) ?? 0;

    // Optional: blank means "not recorded" (0).
    final length =
        double.tryParse(_lengthController.text.trim()) ?? 0;

    setState(() {
      _saving = true;
    });

    try {
      await GoatService.instance.registerGoat(
        farmId: widget.farmId,
        purchase: _purchase,
        breed: _breedController.text,
        ageMonths: ageMonths,
        weight: weight,
        height: height,
        length: length,
        color: _colorController.text,
        healthStatus: _healthStatus,
        gender: _gender,
        notes: _notesController.text,
        photo: _photoBytes,
        photoContentType: _photoContentType,
      );

      final updated =
      await TradingService.instance.getPurchase(
        widget.farmId,
        _purchase.id,
      );

      return updated ?? _purchase;
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );

      return null;
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ===========================================================================
  // SAVE & NEXT
  // ===========================================================================

  Future<void> _saveAndNext() async {
    final updated = await _saveGoat();

    if (updated == null || !mounted) {
      return;
    }

    if (updated.pendingCount <= 0) {
      Navigator.of(context).pushReplacement(
        fastRoute(
          RegistrationCompletedScreen(
            farmId: widget.farmId,
            purchase: updated,
          ),
        ),
      );

      return;
    }

    setState(() {
      _purchase = updated;
    });

    _clearFormForNextGoat();

    _showSnack(
      'Goat registered — '
          '${updated.registeredCount}/${updated.totalGoats} done.',
    );
  }

  // ===========================================================================
  // SAVE & CONTINUE LATER
  // ===========================================================================

  Future<void> _saveAndContinueLater() async {
    final updated = await _saveGoat();

    if (updated == null || !mounted) {
      return;
    }

    _showSnack(
      'Saved. '
          '${updated.registeredCount}/${updated.totalGoats} '
          'registered so far.',
    );

    Navigator.of(context).pop();
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
        elevation: 0,
        foregroundColor: AppColors.textDark,
        centerTitle: false,
        title: Text(
          'Register Goat',
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -----------------------------------------------------------
                // PROGRESS
                // -----------------------------------------------------------

                _progressHeader(),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // PHOTO
                // -----------------------------------------------------------

                Center(
                  child: PhotoUploadCircle(
                    imageBytes: _photoBytes,
                    label: 'Goat Photo (Optional)',
                    onTap: _pickPhoto,
                    size: 88,
                  ),
                ),

                const SizedBox(height: 22),

                // -----------------------------------------------------------
                // BREED
                // -----------------------------------------------------------

                _label('Breed'),

                _textField(
                  _breedController,
                  hint: 'e.g. Sojat, Jamnapari',
                ),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // AGE + WEIGHT
                // -----------------------------------------------------------

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _fieldColumn(
                        label: 'Age (months)',
                        child: _textField(
                          _ageController,
                          hint: 'e.g. 9',
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return 'Required';
                            }

                            final months =
                            int.tryParse(value.trim());

                            if (months == null ||
                                months <= 0) {
                              return 'Enter whole months';
                            }

                            return null;
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: _fieldColumn(
                        label: 'Weight (kg)',
                        child: _textField(
                          _weightController,
                          hint: 'e.g. 22',
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // -----------------------------------------------------------
                // AGE INFORMATION
                // -----------------------------------------------------------

                const SizedBox(height: 7),

                Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: 14,
                      color: AppColors.textGrey,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Age will increase automatically as the goat grows.',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // GENDER
                // -----------------------------------------------------------
                //
                // Captured once, here, at registration — this is the only
                // place it's ever asked. The Sell Goat wizard later only
                // displays it (see Step3SelectedGoatDetails).

                _label('Gender'),

                _dropdown(
                  _gender,
                  Goat.genderValues,
                      (value) {
                    setState(() {
                      _gender = value;
                    });
                  },
                ),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // HEIGHT + LENGTH
                // -----------------------------------------------------------

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _fieldColumn(
                        label: 'Height (cm)',
                        child: _textField(
                          _heightController,
                          hint: 'e.g. 65',
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          optional: true,
                          validator: (value) {
                            final text = (value ?? '').trim();

                            // Optional — blank is fine.
                            if (text.isEmpty) return null;

                            final cm = double.tryParse(text);

                            if (cm == null || cm <= 0) {
                              return 'Enter valid height';
                            }

                            if (cm > Goat.maxHeightCm) {
                              return 'Max ${Goat.maxHeightCm.toStringAsFixed(0)} cm';
                            }

                            return null;
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: _fieldColumn(
                        label: 'Length (cm)',
                        child: _textField(
                          _lengthController,
                          hint: 'e.g. 70',
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          optional: true,
                          validator: (value) {
                            final text = (value ?? '').trim();

                            // Optional — blank is fine.
                            if (text.isEmpty) return null;

                            final cm = double.tryParse(text);

                            if (cm == null || cm <= 0) {
                              return 'Enter valid length';
                            }

                            if (cm > Goat.maxLengthCm) {
                              return 'Max ${Goat.maxLengthCm.toStringAsFixed(0)} cm';
                            }

                            return null;
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // COLOR
                // -----------------------------------------------------------

                _label('Color'),

                _textField(
                  _colorController,
                  hint: 'e.g. Brown & White',
                ),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // HEALTH
                // -----------------------------------------------------------

                _label('Health Status'),

                _dropdown(
                  _healthStatus,
                  Goat.healthStatusValues,
                      (value) {
                    setState(() {
                      _healthStatus = value;
                    });
                  },
                ),

                const SizedBox(height: 18),

                // -----------------------------------------------------------
                // NOTES
                // -----------------------------------------------------------

                _label('Notes'),

                _textField(
                  _notesController,
                  hint: 'Optional notes',
                  maxLines: 3,
                  optional: true,
                ),

                const SizedBox(height: 24),

                // -----------------------------------------------------------
                // ACTIONS
                // -----------------------------------------------------------

                _actionButtons(),

                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PROGRESS HEADER
  // ===========================================================================

  Widget _progressHeader() {
    final total = _purchase.totalGoats;
    final registered = _purchase.registeredCount;

    final percent = total > 0
        ? ((registered / total) * 100).round()
        : 0;

    final progress = total > 0
        ? (registered / total).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.tradingBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.tradingBlue.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color:
                  AppColors.tradingBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  GoatIcons.paw,
                  color: AppColors.tradingBlue,
                  size: 18,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      _purchase.id,
                      style: AppTheme.heading(
                        size: 12,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _purchase.sellerName,
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

              Text(
                '$percent%',
                style: AppTheme.heading(
                  size: 14,
                  color: AppColors.tradingBlue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor:
              AppColors.tradingBlue.withOpacity(0.12),
              valueColor:
              const AlwaysStoppedAnimation(
                AppColors.tradingBlue,
              ),
            ),
          ),

          const SizedBox(height: 6),

          Text(
            '$registered of $total goats registered',
            style: AppTheme.body(
              size: 10,
              color: AppColors.tradingBlue,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FIELD COLUMN
  // ===========================================================================

  Widget _fieldColumn({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        child,
      ],
    );
  }

  // ===========================================================================
  // LABEL
  // ===========================================================================

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 7,
      ),
      child: Text(
        text,
        style: AppTheme.heading(
          size: 13,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  // ===========================================================================
  // TEXT FIELD
  // ===========================================================================

  Widget _textField(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        bool optional = false,
        String? Function(String?)? validator,
      }) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(
        radius: 13,
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,

        validator: validator ??
                (value) {
              if (!optional &&
                  (value == null ||
                      value.trim().isEmpty)) {
                return 'Required';
              }

              return null;
            },

        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
          ),
          border: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),

        style: AppTheme.body(
          size: 13,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  // ===========================================================================
  // DROPDOWN
  // ===========================================================================

  Widget _dropdown(
      String value,
      List<String> options,
      ValueChanged<String> onChanged,
      ) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: AppTheme.card(
        radius: 13,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,

          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGrey,
          ),

          items: options
              .map(
                (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(
                option,
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.textDark,
                ),
              ),
            ),
          )
              .toList(),

          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // ACTION BUTTONS
  // ===========================================================================

  Widget _actionButtons() {
    return Column(
      children: [
        // Primary action
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed:
            _saving ? null : _saveAndNext,
            style: ElevatedButton.styleFrom(
              backgroundColor:
              AppColors.primaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
              AppColors.primaryGreen.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(13),
              ),
            ),
            child: _saving
                ? const SizedBox(
              height: 19,
              width: 19,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : Row(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                ),
                SizedBox(width: 7),
                Text(
                  'Save & Next',
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

        const SizedBox(height: 10),

        // Secondary action
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _saving
                ? null
                : _saveAndContinueLater,
            style: OutlinedButton.styleFrom(
              foregroundColor:
              AppColors.primaryGreen,
              disabledForegroundColor:
              AppColors.primaryGreen
                  .withOpacity(0.45),
              side: BorderSide(
                color: AppColors.primaryGreen
                    .withOpacity(0.7),
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(13),
              ),
            ),
            child: Row(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.bookmark_border_rounded,
                  size: 18,
                ),
                SizedBox(width: 7),
                Text(
                  'Save & Continue Later',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}