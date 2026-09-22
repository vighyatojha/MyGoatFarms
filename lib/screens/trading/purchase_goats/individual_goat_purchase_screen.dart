import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/image_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/photo_upload_circle.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Individual Goat Purchase.
///
/// Lets the user buy ONE goat straight from the Goat Stock screen, without
/// going through the wholesale Purchase wizard + Register Goats flow.
///
/// No new models or collections are introduced. Saving does exactly what
/// the existing two-step flow does, back to back:
///
/// 1. [TradingService.savePurchase] with a single goat, receiving already
///    completed. This writes farms/{farmId}/tradingPurchases/{PUR-xxxx},
///    updates the Trading dashboard summary and creates the Finance
///    "Goat Purchase" expense (referenceType = tradingPurchase).
///
/// 2. [GoatService.registerGoat] against that purchase. This writes
///    farms/{farmId}/tradingGoats/{G-xxxx} with status Available.
///
/// If step 1 succeeds but step 2 fails, the purchase already exists and
/// would otherwise be duplicated by a plain retry. The saved purchase is
/// therefore remembered, the form is locked, and the retry only repeats
/// step 2. (Even if the user leaves instead, the purchase shows up under
/// Trading > Register Goats, like any other pending registration.)
///
/// Pops with the created [Goat] on success.
class IndividualGoatPurchaseScreen extends StatefulWidget {
  final String farmId;

  const IndividualGoatPurchaseScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<IndividualGoatPurchaseScreen> createState() =>
      _IndividualGoatPurchaseScreenState();
}

class _IndividualGoatPurchaseScreenState
    extends State<IndividualGoatPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();

  // Goat
  final _breedController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _colorController = TextEditingController();
  final _notesController = TextEditingController();

  // Seller
  final _sellerNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _marketController = TextEditingController();

  // Price
  final _priceController = TextEditingController();

  String _healthStatus = Goat.healthStatusValues.first;
  String _gender = Goat.genderValues.first;
  DateTime _purchaseDate = DateTime.now();

  /// Trading payment methods are limited to Cash / Online.
  String _paymentMethod = 'Cash';

  Uint8List? _photoBytes;
  String? _photoContentType;

  bool _saving = false;

  /// Set once the purchase document exists. See the class comment.
  TradingPurchase? _savedPurchase;

  bool get _locked => _savedPurchase != null;

  @override
  void dispose() {
    _breedController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _lengthController.dispose();
    _colorController.dispose();
    _notesController.dispose();
    _sellerNameController.dispose();
    _mobileController.dispose();
    _marketController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  double get _weight =>
      double.tryParse(_weightController.text.trim()) ?? 0;

  /// Optional — 0 means "not recorded".
  double get _height =>
      double.tryParse(_heightController.text.trim()) ?? 0;

  double get _length =>
      double.tryParse(_lengthController.text.trim()) ?? 0;

  double get _pricePerKg =>
      double.tryParse(_priceController.text.trim()) ?? 0;

  double get _purchaseAmount => _weight * _pricePerKg;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
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
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack(
        'Could not add photo. Please try again.',
        isError: true,
      );
    }
  }

  // ===========================================================================
  // DATE
  // ===========================================================================

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primaryGreen,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _purchaseDate = picked;
    });
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    if (_saving) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _showSnack(
        'Please fix the highlighted fields.',
        isError: true,
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // Step 1 — purchase (skipped when a previous attempt already saved it).
      _savedPurchase ??= await TradingService.instance.savePurchase(
        farmId: widget.farmId,
        sellerName: _sellerNameController.text,
        mobile: _mobileController.text,
        market: _marketController.text,
        vehicleNumber: '',
        purchaseDate: _purchaseDate,
        totalGoats: 1,
        totalWeightAtPurchase: _weight,
        pricePerKg: _pricePerKg,
        paymentMethod: _paymentMethod,

        // The goat is bought and brought to the farm in one go, so
        // receiving is recorded as completed straight away.
        receivingStatus: 'completed',
        dateReceivedAtFarm: _purchaseDate,
        totalWeightAfterArrival: _weight,
        mortality: 0,
        remarks: 'Individual goat purchase',
      );

      final purchase = _savedPurchase!;

      // Step 2 — register the goat against that purchase.
      final goat = await GoatService.instance.registerGoat(
        farmId: widget.farmId,
        purchase: purchase,
        breed: _breedController.text,
        ageMonths: int.tryParse(_ageController.text.trim()) ?? 0,
        weight: _weight,
        height: _height,
        length: _length,
        color: _colorController.text,
        healthStatus: _healthStatus,
        gender: _gender,
        notes: _notesController.text,
        photo: _photoBytes,
        photoContentType: _photoContentType,
      );

      if (!mounted) return;

      Navigator.of(context).pop(goat);
    } catch (e) {
      final message = FirestoreService.instance.describeError(e);

      final saved = _savedPurchase;

      if (saved != null) {
        // Purchase exists, goat registration failed.
        if (mounted) {
          setState(() {});
        }

        _showSnack(
          'Purchase ${saved.id} was saved but the goat could not be '
              'added to stock. $message',
          isError: true,
        );
      } else {
        _showSnack(message, isError: true);
      }
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
        backgroundColor: AppColors.paleGreen,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Purchase Goat',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_locked) _retryBanner(),

                    // While a retry is pending, the form is read-only so
                    // the goat can't drift away from the saved purchase.
                    AbsorbPointer(
                      absorbing: _locked,
                      child: Opacity(
                        opacity: _locked ? 0.55 : 1,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              _goatCard(),
                              const SizedBox(height: 14),
                              _sellerCard(),
                              const SizedBox(height: 14),
                              _priceCard(),
                              const SizedBox(height: 14),
                              _infoNote(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _bottomBar(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // RETRY BANNER
  // ===========================================================================

  Widget _retryBanner() {
    final purchase = _savedPurchase!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Purchase ${purchase.id} is saved. Only adding the goat '
                  'to stock is left — tap Retry. Nothing will be '
                  'charged twice.',
              style: AppTheme.body(
                size: 12,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GOAT DETAILS
  // ===========================================================================

  Widget _goatCard() {
    return WizardSectionCard(
      title: 'Goat Details',
      icon: GoatIcons.paw,
      children: [
        Center(
          child: PhotoUploadCircle(
            imageBytes: _photoBytes,
            label: 'Goat Photo (Optional)',
            onTap: _pickPhoto,
            size: 88,
          ),
        ),

        const SizedBox(height: 16),

        wizardField(
          controller: _breedController,
          label: 'Breed',
          hint: 'e.g. Sojat, Jamnapari',
          icon: Icons.category_outlined,
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Enter breed';
            }
            return null;
          },
        ),

        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: wizardField(
                controller: _ageController,
                label: 'Age (months)',
                hint: 'e.g. 9',
                icon: Icons.calendar_month_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                validator: (value) {
                  final months = int.tryParse(
                    (value ?? '').trim(),
                  );

                  if (months == null || months <= 0) {
                    return 'Enter months';
                  }

                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: wizardField(
                controller: _weightController,
                label: 'Weight (kg)',
                hint: 'e.g. 22',
                icon: Icons.monitor_weight_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final number = double.tryParse(
                    (value ?? '').trim(),
                  );

                  if (number == null || number <= 0) {
                    return 'Enter weight';
                  }

                  return null;
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: wizardField(
                controller: _heightController,
                label: 'Height (cm)',
                hint: 'e.g. 65',
                icon: Icons.height,
                optional: true,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,1}'),
                  ),
                ],
                validator: (value) {
                  final text = (value ?? '').trim();

                  // Optional — blank is fine.
                  if (text.isEmpty) return null;

                  final cm = double.tryParse(text);

                  if (cm == null || cm <= 0) {
                    return 'Enter height';
                  }

                  if (cm > Goat.maxHeightCm) {
                    return 'Max ${Goat.maxHeightCm.toStringAsFixed(0)} cm';
                  }

                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: wizardField(
                controller: _lengthController,
                label: 'Length (cm)',
                hint: 'e.g. 70',
                icon: Icons.straighten_outlined,
                optional: true,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,1}'),
                  ),
                ],
                validator: (value) {
                  final text = (value ?? '').trim();

                  // Optional — blank is fine.
                  if (text.isEmpty) return null;

                  final cm = double.tryParse(text);

                  if (cm == null || cm <= 0) {
                    return 'Enter length';
                  }

                  if (cm > Goat.maxLengthCm) {
                    return 'Max ${Goat.maxLengthCm.toStringAsFixed(0)} cm';
                  }

                  return null;
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _colorController,
          label: 'Color',
          hint: 'e.g. Brown',
          icon: Icons.palette_outlined,
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Enter color';
            }
            return null;
          },
        ),

        const SizedBox(height: 14),

        _fieldLabel('Gender'),

        _dropdown(
          value: _gender,
          options: Goat.genderValues,
          onChanged: (value) {
            setState(() {
              _gender = value;
            });
          },
        ),

        const SizedBox(height: 14),

        _fieldLabel('Health Status'),

        _dropdown(
          value: _healthStatus,
          options: Goat.healthStatusValues,
          onChanged: (value) {
            setState(() {
              _healthStatus = value;
            });
          },
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _notesController,
          label: 'Notes',
          hint: 'Optional notes',
          icon: Icons.notes_rounded,
          maxLines: 2,
          optional: true,
        ),
      ],
    );
  }

  // ===========================================================================
  // SELLER
  // ===========================================================================

  Widget _sellerCard() {
    return WizardSectionCard(
      title: 'Seller Details',
      icon: Icons.person_outline_rounded,
      children: [
        wizardField(
          controller: _sellerNameController,
          label: 'Seller Name',
          hint: 'e.g. Ramesh Traders',
          icon: Icons.badge_outlined,
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Enter seller name';
            }
            return null;
          },
        ),

        const SizedBox(height: 14),

        // Same rule as the wholesale wizard's Step 1.
        wizardField(
          controller: _mobileController,
          label: 'Mobile Number',
          hint: '10-digit mobile number',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          validator: (value) {
            final v = (value ?? '').trim();

            if (v.isEmpty) {
              return 'Enter mobile number';
            }

            if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) {
              return 'Enter a valid 10-digit number';
            }

            return null;
          },
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _marketController,
          label: 'Market / Location',
          hint: 'Optional',
          icon: Icons.location_on_outlined,
          optional: true,
        ),

        const SizedBox(height: 14),

        WizardDateField(
          label: 'Purchase Date',
          date: _purchaseDate,
          onTap: _pickDate,
        ),
      ],
    );
  }

  // ===========================================================================
  // PRICE + PAYMENT
  // ===========================================================================

  Widget _priceCard() {
    // Once the purchase is saved, show what was actually saved.
    final saved = _savedPurchase;

    final weight = saved?.totalWeightAtPurchase ?? _weight;
    final pricePerKg = saved?.pricePerKg ?? _pricePerKg;
    final amount = saved?.purchaseAmount ?? _purchaseAmount;

    return WizardSectionCard(
      title: 'Price & Payment',
      icon: Icons.payments_outlined,
      children: [
        wizardField(
          controller: _priceController,
          label: 'Price per KG',
          hint: '0.00',
          icon: Icons.currency_rupee_rounded,
          suffix: '/ KG',
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          onChanged: (_) => setState(() {}),
          validator: (value) {
            final number = double.tryParse(
              (value ?? '').trim(),
            );

            if (number == null || number <= 0) {
              return 'Enter a valid price';
            }

            return null;
          },
        ),

        const SizedBox(height: 14),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              WizardComputedRow(
                label: 'Weight',
                value: '${_trimZero(weight)} kg',
              ),
              WizardComputedRow(
                label: 'Price per KG',
                value: _currency(pricePerKg),
              ),
              const Divider(height: 10),
              WizardComputedRow(
                label: 'Purchase Amount',
                value: _currency(amount),
                emphasize: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Paid to seller by',
          style: AppTheme.body(
            size: 11,
            color: AppColors.textGrey,
            weight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _paymentOption(
                title: 'Cash',
                icon: Icons.money_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _paymentOption(
                title: 'Online',
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paymentOption({
    required String title,
    required IconData icon,
  }) {
    final selected = _paymentMethod == title;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _paymentMethod = title;
          });
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? AppColors.primaryGreen
                  : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected
                    ? AppColors.darkGreen
                    : AppColors.textGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 13,
                    color: selected
                        ? AppColors.darkGreen
                        : AppColors.textDark,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.primaryGreen,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // INFO NOTE
  // ===========================================================================

  Widget _infoNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: AppColors.textGrey,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Saving creates a purchase record, adds the goat to stock '
                'as Available, and records the goat purchase as an '
                'expense in Finance.',
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // FIELD HELPERS
  // ===========================================================================

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTheme.body(
          size: 11,
          color: AppColors.textGrey,
          weight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
          onChanged: (selected) {
            if (selected != null) {
              onChanged(selected);
            }
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // BOTTOM BAR
  // ===========================================================================

  Widget _bottomBar() {
    final amount = _savedPurchase?.purchaseAmount ?? _purchaseAmount;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currency(amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 18,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                  AppColors.darkGreen.withOpacity(0.6),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
                    : Text(
                  _locked
                      ? 'Retry Adding Goat'
                      : 'Purchase & Add to Stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 14,
                    color: Colors.white,
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