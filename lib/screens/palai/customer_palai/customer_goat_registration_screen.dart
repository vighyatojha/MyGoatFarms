import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/activity_model.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/photo_upload_circle.dart';

class CustomerGoatRegistrationScreen extends StatefulWidget {
  final String customerId;

  const CustomerGoatRegistrationScreen({
    super.key,
    required this.customerId,
  });

  @override
  State<CustomerGoatRegistrationScreen> createState() =>
      _CustomerGoatRegistrationScreenState();
}

class _CustomerGoatRegistrationScreenState
    extends State<CustomerGoatRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _goatCodeController = TextEditingController();
  final _breedController = TextEditingController();
  final _colorController = TextEditingController();
  final _weightController = TextEditingController();
  final _pricingController = TextEditingController();
  final _notesController = TextEditingController();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  String _gender = 'Male';
  String _healthStatus = 'Healthy';
  String _monthlyPackage = 'Basic Palai';

  // Date the goat actually arrived at the farm.
  // This is different from checkInDate, which is the Palai registration/check-in time.
  DateTime? _farmArrivalDate;

  bool _saving = false;

  // ---------------------------------------------------------------------------
  // BEFORE PALAI PHOTO
  // ---------------------------------------------------------------------------

  Uint8List? _beforeImageBytes;
  String? _beforeImageContentType;

  static const List<String> _genders = [
    'Male',
    'Female',
  ];

  static const List<String> _healthOptions = [
    'Healthy',
    'Under Observation',
    'Sick',
  ];

  static const List<String> _packages = [
    'Basic Palai',
    'Standard Palai',
    'Special Palai',
  ];

  // ===========================================================================
  // PALAI PERMISSION CHECK
  // ===========================================================================
  //
  // Without this, the form lets ANY signed-in user fill everything out and
  // only finds out they're blocked when _saveGoat() runs — either with
  // "Unable to determine the current farm." (partner accounts, since
  // FirestoreService.currentFarmId() only resolves the FARM OWNER's uid)
  // or a Firestore `permission-denied` error if farmId does resolve but
  // the security rules still reject the write.
  //
  // This mirrors the permission a farm owner actually sets in Profile ->
  // Partners -> Partner Permissions (`palai` flag stored at
  // farms/{farmId}/partners/{partnerId}/settings/permissions) so the user
  // is warned BEFORE filling in the whole form, not after.
  //
  // Fail-open by design: if this check can't be resolved (offline, some
  // unforeseen account shape, etc.) the button stays enabled and the
  // existing try/catch in _saveGoat() remains the real fallback.

  bool _permissionChecked = false;
  bool _canRegister = true;
  String? _permissionMessage;

  @override
  void initState() {
    super.initState();
    _checkPalaiPermission();
  }

  Future<void> _checkPalaiPermission() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        return;
      }

      // Farm owners always have full access.
      final ownerFarm = await _firestore
          .collection('farms')
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get();

      if (ownerFarm.docs.isNotEmpty) {
        return;
      }

      // Otherwise, check whether this user is a partner/staff account.
      final partnerQuery = await _firestore
          .collectionGroup('partners')
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get();

      if (partnerQuery.docs.isEmpty) {
        // Not resolvable as owner or partner. This is the case that
        // currently produces "Unable to determine the current farm." —
        // surface that plainly instead of letting the user discover it
        // only after filling in the whole form.
        if (mounted) {
          setState(() {
            _permissionChecked = true;
            _canRegister = false;
            _permissionMessage =
            'Could not confirm which farm this account belongs to, so goats can\'t be registered right now. Please contact the farm owner.';
          });
        }
        return;
      }

      final partnerDoc = partnerQuery.docs.first;
      final partnerData = partnerDoc.data();

      if (partnerData['isActive'] == false) {
        if (mounted) {
          setState(() {
            _permissionChecked = true;
            _canRegister = false;
            _permissionMessage =
            'Your partner account has been deactivated by the farm owner.';
          });
        }
        return;
      }

      final permissionsSnapshot = await partnerDoc.reference
          .collection('settings')
          .doc('permissions')
          .get();

      // Matches the default used in the Partner Permissions screen: a
      // partner with no permissions document yet defaults to allowed.
      final hasPalaiAccess = permissionsSnapshot.exists
          ? (permissionsSnapshot.data()?['palai'] ?? true) == true
          : true;

      if (mounted) {
        setState(() {
          _permissionChecked = true;
          _canRegister = hasPalaiAccess;
          _permissionMessage = hasPalaiAccess
              ? null
              : 'You do not have Palai access on this account. Ask the farm owner to enable it from Profile > Partners > Partner Permissions.';
        });
      }

      // NOTE: since a partner's `currentFarmId()` currently resolves to
      // null even when they DO have Palai access (that helper only
      // matches the farm owner's uid), fixing that resolution in
      // FirestoreService is also required for a permitted partner to
      // actually complete registration. This check only prevents a
      // blocked user from filling in the form for nothing — it can't
      // grant access _saveGoat() itself can't resolve.
    } catch (_) {
      // Fail open client-side; the real gate is Firestore's rules /
      // _saveGoat()'s own error handling.
    }
  }

  @override
  void dispose() {
    _goatCodeController.dispose();
    _breedController.dispose();
    _colorController.dispose();
    _weightController.dispose();
    _pricingController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // BEFORE PALAI PHOTO
  // ===========================================================================

  Future<void> _pickBeforePhoto() async {
    try {
      final picked = await showImageSourceSheet(
        context,
        isGoatPhoto: true,
      );

      if (picked == null) {
        return;
      }

      setState(() {
        _beforeImageBytes = picked.bytes;
        _beforeImageContentType = picked.contentType;
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
  // SNACKBAR
  // ===========================================================================

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? AppColors.error
            : AppColors.primaryGreen,
      ),
    );
  }

  // ===========================================================================
  // SAVE / REGISTER + CHECK-IN
  // ===========================================================================

  Future<void> _saveGoat() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_saving) {
      return;
    }

    final weight = double.tryParse(
      _weightController.text.trim(),
    );

    if (weight == null || weight <= 0) {
      _showSnack(
        'Please enter a valid goat weight.',
        isError: true,
      );
      return;
    }

    final pricingText = _pricingController.text.trim();

    final pricing = pricingText.isEmpty
        ? 0.0
        : double.tryParse(pricingText);

    if (pricing == null || pricing < 0) {
      _showSnack(
        'Please enter a valid pricing amount.',
        isError: true,
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // ---------------------------------------------------------------
      // GET CURRENT FARM
      // ---------------------------------------------------------------

      final farmId =
      await FirestoreService.instance.currentFarmId();

      if (farmId == null || farmId.trim().isEmpty) {
        throw StateError(
          'Unable to determine the current farm.',
        );
      }

      // ---------------------------------------------------------------
      // GET CUSTOMER
      // ---------------------------------------------------------------

      final customer =
      await FirestoreService.instance.getCustomer(
        farmId,
        widget.customerId,
      );

      if (customer == null) {
        throw StateError(
          'Customer no longer exists.',
        );
      }

      // ---------------------------------------------------------------
      // CREATE UNIFIED PALAI GOAT
      // ---------------------------------------------------------------

      final now = DateTime.now();

      final goat = PalaiGoat(
        // FirestoreService.checkInGoat() generates
        // the actual Firestore document ID.
        id: '',

        customerId:
        widget.customerId,

        // Identity
        goatCode:
        _goatCodeController.text.trim(),

        breed:
        _breedController.text.trim(),

        gender:
        _gender,

        color:
        _colorController.text.trim(),

        // Weight
        weightAtCheckIn:
        weight,

        currentWeight:
        weight,

        // Health
        healthStatus:
        _healthStatus,

        // Check-in
        // Keep the existing Palai check-in behavior unchanged.
        checkInDate:
        now,

        // Actual date the goat arrived at the farm.
        farmArrivalDate:
        _farmArrivalDate,

        checkOutDate:
        null,

        status:
        'active',

        isCheckedOut:
        false,

        // Package / pricing
        monthlyPackage:
        _monthlyPackage,

        pricing:
        pricing,

        // Registration
        registrationDate:
        now,

        updatedAt:
        now,

        // Other
        notes:
        _notesController.text.trim(),

        imageUrl:
        null,

        // Before Palai photo
        beforeImage:
        _beforeImageBytes,

        beforeImageContentType:
        _beforeImageContentType,

        // Reports
        reportStatus:
        'Not Generated',

        lastReportType:
        null,

        lastReportDate:
        null,

        reportsCount:
        0,
      );

      // ---------------------------------------------------------------
      // SAVE USING THE SAME SERVICE AS OLD CHECK-IN
      // ---------------------------------------------------------------

      final goatId =
      await FirestoreService.instance.checkInGoat(
        farmId,
        widget.customerId,
        goat,
      );

      // ---------------------------------------------------------------
      // ACTIVITY LOG
      // ---------------------------------------------------------------

      try {
        await FirestoreService.instance.logActivity(
          farmId,
          ActivityLog(
            id: '',
            type: ActivityType.goatCheckIn,
            title: 'Goat Check-In',
            subtitle:
            '${goat.goatCode} · ${customer.name}',
            module: 'palai',
            timestamp: now,
          ),
        );
      } catch (_) {
        // Goat has already been saved.
        // Do not fail registration only because
        // activity logging failed.
      }

      if (!mounted) {
        return;
      }

      _showSnack(
        'Goat registered and checked in successfully.',
      );

      // The list will reload from Firestore.
      // goatId is intentionally not required here.
      Navigator.of(context).pop(goat);
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      _showSnack(
        _firebaseErrorMessage(e),
        isError: true,
      );
    } on StateError catch (e) {
      if (!mounted) {
        return;
      }

      _showSnack(
        e.message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showSnack(
        'Unable to register the goat. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor:
        AppColors.paleGreen,
        elevation: 0,
        foregroundColor:
        AppColors.textDark,
        title: Text(
          'Register Goat',
          style: AppTheme.heading(
            size: 17,
          ),
        ),
      ),

      body: Form(
        key: _formKey,

        child: ListView(
          padding:
          const EdgeInsets.fromLTRB(
            20,
            16,
            20,
            120,
          ),

          children: [
            if (_permissionChecked && !_canRegister) ...[
              _buildPermissionWarningBanner(),
              const SizedBox(height: 16),
            ],

            _buildIntroCard(),

            const SizedBox(height: 22),

            _buildPhotoSection(),

            const SizedBox(height: 24),

            _buildSectionTitle(
              'Goat Information',
            ),

            const SizedBox(height: 12),

            _buildGoatCodeField(),

            const SizedBox(height: 16),

            _buildBreedField(),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildGenderField(),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: _buildColorField(),
                ),
              ],
            ),

            const SizedBox(height: 28),

            _buildSectionTitle(
              'Check-In Information',
            ),

            const SizedBox(height: 12),

            _buildFarmArrivalDateField(),

            const SizedBox(height: 12),

            _buildWeightField(),

            const SizedBox(height: 16),

            _buildHealthField(),

            const SizedBox(height: 16),

            _buildPackageField(),

            const SizedBox(height: 16),

            _buildPricingField(),

            const SizedBox(height: 28),

            _buildSectionTitle(
              'Additional Information',
            ),

            const SizedBox(height: 12),

            _buildNotesField(),

            const SizedBox(height: 22),

            _buildInformationCard(),
          ],
        ),
      ),

      bottomNavigationBar:
      SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            16,
          ),

          child: SizedBox(
            height: 54,

            child: ElevatedButton.icon(
              onPressed:
              (_saving || (_permissionChecked && !_canRegister))
                  ? null
                  : _saveGoat,

              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor:
                Colors.white,
                disabledBackgroundColor:
                Colors.grey.shade400,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
              ),

              icon:
              _saving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                  Colors.white,
                ),
              )
                  : const Icon(
                Icons
                    .check_circle_outline,
              ),

              label: Text(
                _saving
                    ? 'Registering...'
                    : 'Register & Check-In Goat',
                style: const TextStyle(
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // INTRO
  // ===========================================================================

  Widget _buildIntroCard() {
    return Container(
      padding:
      const EdgeInsets.all(18),

      decoration:
      AppTheme.card(
        radius: 16,
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Container(
            width: 50,
            height: 50,

            decoration:
            BoxDecoration(
              shape:
              BoxShape.circle,
              color:
              AppColors.primaryGreen
                  .withOpacity(0.12),
            ),

            child: const Icon(
              Icons.pets_outlined,
              color:
              AppColors.primaryGreen,
              size: 27,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  'Register & Check-In Goat',
                  style:
                  AppTheme.heading(
                    size: 17,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Register this customer goat directly into the Palai boarding system. The goat will be checked in immediately and can then be managed from its profile.',
                  style:
                  AppTheme.body(
                    size: 13,
                    color:
                    AppColors.textGrey,
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
  // PHOTO
  // ===========================================================================

  Widget _buildPhotoSection() {
    return Column(
      children: [
        PhotoUploadCircle(
          imageBytes:
          _beforeImageBytes,
          label:
          'Before Palai Photo',
          onTap:
          _pickBeforePhoto,
        ),

        const SizedBox(height: 8),

        Text(
          'Optional photo taken before Palai care begins.',
          textAlign:
          TextAlign.center,
          style: AppTheme.body(
            size: 12,
            color:
            AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // GOAT CODE
  // ===========================================================================

  Widget _buildGoatCodeField() {
    return _textField(
      controller:
      _goatCodeController,
      label:
      'Goat Code / Tag Number',
      hint:
      'Example: G-1001',
      icon:
      Icons.qr_code_2_outlined,
      capitalization:
      TextCapitalization.characters,
      validator: (value) {
        if (value == null ||
            value.trim().isEmpty) {
          return 'Enter the goat code / tag number';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // BREED
  // ===========================================================================

  Widget _buildBreedField() {
    return _textField(
      controller:
      _breedController,
      label:
      'Breed',
      hint:
      'Example: Sirohi, Sojat, Jamnapari',
      icon:
      Icons.category_outlined,
      capitalization:
      TextCapitalization.words,
      validator: (value) {
        if (value == null ||
            value.trim().isEmpty) {
          return 'Enter the goat breed';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // GENDER
  // ===========================================================================

  Widget _buildGenderField() {
    return _dropdownField(
      label:
      'Gender',
      value:
      _gender,
      icon:
      Icons.wc_outlined,
      options:
      _genders,
      onChanged: (value) {
        setState(() {
          _gender = value;
        });
      },
    );
  }

  // ===========================================================================
  // COLOR
  // ===========================================================================

  Widget _buildColorField() {
    return _textField(
      controller:
      _colorController,
      label:
      'Color',
      hint:
      'e.g. Brown & White',
      icon:
      Icons.palette_outlined,
      capitalization:
      TextCapitalization.words,
      optional:
      true,
    );
  }

  // ===========================================================================
  // WEIGHT
  // ===========================================================================

  Widget _buildWeightField() {
    return _textField(
      controller:
      _weightController,
      label:
      'Weight at Check-In (kg)',
      hint:
      'Example: 35.5',
      icon:
      Icons.monitor_weight_outlined,
      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),
      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
          return 'Enter the goat weight';
        }

        final weight =
        double.tryParse(text);

        if (weight == null) {
          return 'Enter a valid weight';
        }

        if (weight <= 0) {
          return 'Weight must be greater than 0';
        }

        if (weight > 300) {
          return 'Please check the weight';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // HEALTH
  // ===========================================================================

  Widget _buildHealthField() {
    return _dropdownField(
      label:
      'Initial Health Status',
      value:
      _healthStatus,
      icon:
      Icons.health_and_safety_outlined,
      options:
      _healthOptions,
      onChanged: (value) {
        setState(() {
          _healthStatus = value;
        });
      },
    );
  }

  // ===========================================================================
  // PACKAGE
  // ===========================================================================

  Widget _buildPackageField() {
    return _dropdownField(
      label:
      'Monthly Package',
      value:
      _monthlyPackage,
      icon:
      Icons.inventory_2_outlined,
      options:
      _packages,
      onChanged: (value) {
        setState(() {
          _monthlyPackage = value;
        });
      },
    );
  }

  // ===========================================================================
  // PRICING
  // ===========================================================================

  Widget _buildPricingField() {
    return _textField(
      controller:
      _pricingController,
      label:
      'Pricing (₹)',
      hint:
      'Example: 1500',
      icon:
      Icons.currency_rupee,
      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),
      optional:
      true,
      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
          return null;
        }

        final amount =
        double.tryParse(text);

        if (amount == null) {
          return 'Enter a valid price';
        }

        if (amount < 0) {
          return 'Price cannot be negative';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  Widget _buildNotesField() {
    return _textField(
      controller:
      _notesController,
      label:
      'Notes',
      hint:
      'Optional notes about this goat...',
      icon:
      Icons.notes_outlined,
      maxLines:
      4,
      optional:
      true,
      capitalization:
      TextCapitalization.sentences,
    );
  }

  // ===========================================================================
  // INFORMATION CARD
  // ===========================================================================

  Widget _buildPermissionWarningBanner() {
    return Container(
      padding:
      const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.error.withOpacity(0.4),
        ),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.lock_outline,
            color: AppColors.error,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              _permissionMessage ??
                  'You do not have permission to register goats on this account.',
              style:
              AppTheme.body(
                size: 12,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationCard() {
    return Container(
      padding:
      const EdgeInsets.all(16),

      decoration:
      AppTheme.card(
        radius: 14,
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.info_outline,
            color:
            AppColors.primaryGreen,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              'After registration, the goat will be considered checked in. From the goat profile you can manage weight, health, vaccination, hoof cutting, hair trimming, medicine, monthly photos, reports and checkout.',
              style:
              AppTheme.body(
                size: 12,
                color:
                AppColors.textGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TEXT FIELD
  // ===========================================================================

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool optional = false,
    TextCapitalization capitalization =
        TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller:
      controller,

      keyboardType:
      keyboardType,

      maxLines:
      maxLines,

      textCapitalization:
      capitalization,

      textInputAction:
      maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,

      validator:
      validator ??
          (optional
              ? null
              : (value) {
            if (value == null ||
                value.trim().isEmpty) {
              return 'Required';
            }

            return null;
          }),

      decoration:
      InputDecoration(
        labelText:
        label,
        hintText:
        hint,
        prefixIcon:
        icon == null
            ? null
            : Icon(icon),
        border:
        const OutlineInputBorder(),
      ),
    );
  }

  // ===========================================================================
  // DROPDOWN
  // ===========================================================================

  Widget _dropdownField({
    required String label,
    required String value,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return InputDecorator(
      decoration:
      InputDecoration(
        labelText:
        label,
        prefixIcon:
        Icon(icon),
        border:
        const OutlineInputBorder(),
      ),

      child:
      DropdownButtonHideUnderline(
        child:
        DropdownButton<String>(
          value:
          value,
          isExpanded:
          true,

          items:
          options.map(
                (option) {
              return DropdownMenuItem<String>(
                value:
                option,
                child:
                Text(option),
              );
            },
          ).toList(),

          onChanged:
              (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION TITLE
  // ===========================================================================

  Widget _buildSectionTitle(
      String title,
      ) {
    return Text(
      title,
      style:
      AppTheme.heading(
        size: 18,
      ),
    );
  }

  Widget _buildFarmArrivalDateField() {
    final date = _farmArrivalDate;

    final dateText = date == null
        ? 'Select date'
        : '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';

    return FormField<DateTime>(
      validator: (_) {
        if (_farmArrivalDate == null) {
          return 'Please select the date the goat came into the farm';
        }
        return null;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                await _selectFarmArrivalDate();
                field.didChange(_farmArrivalDate);
              },
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date Goat Came Into Farm',
                  hintText: 'Select arrival date',
                  prefixIcon: const Icon(
                    Icons.calendar_month_outlined,
                  ),
                  border: const OutlineInputBorder(),
                  errorText: field.errorText,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateText,
                        style: TextStyle(
                          color: date == null
                              ? AppColors.textGrey
                              : AppColors.textDark,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectFarmArrivalDate() async {
    final now = DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _farmArrivalDate ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Select Goat Arrival Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );

    if (selectedDate == null) {
      return;
    }

    setState(() {
      _farmArrivalDate = selectedDate;
    });
  }

  // ===========================================================================
  // FIREBASE ERROR
  // ===========================================================================

  String _firebaseErrorMessage(
      FirebaseException error,
      ) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to register this goat.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      case 'unavailable':
        return 'Firebase is temporarily unavailable. Please try again.';

      default:
        return 'Unable to register the goat. Please try again.';
    }
  }
}