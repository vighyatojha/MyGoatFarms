import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_models.dart';

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
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  String _gender = 'Male';
  String _color = '';

  bool _saving = false;

  @override
  void dispose() {
    _goatCodeController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SAVE GOAT
  // ===========================================================================

  Future<void> _saveGoat() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final goatReference = _firestore
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .collection('goats')
          .doc();

      final now = DateTime.now();

      final weightText =
      _weightController.text.trim();

      final parsedWeight =
      double.tryParse(weightText);

      if (parsedWeight == null ||
          parsedWeight <= 0) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enter a valid goat weight.',
            ),
          ),
        );

        return;
      }

      // -----------------------------------------------------------------------
      // CREATE THE UNIFIED PALAI GOAT MODEL
      // -----------------------------------------------------------------------

      final goat = PalaiGoat(
        id: goatReference.id,
        customerId: widget.customerId,

        goatCode:
        _goatCodeController.text.trim(),

        breed:
        _breedController.text.trim(),

        gender:
        _gender,

        color:
        _color.trim(),

        // At registration/check-in the entered weight
        // becomes the initial boarding weight.
        weightAtCheckIn:
        parsedWeight,

        currentWeight:
        parsedWeight,

        healthStatus:
        'Healthy',

        // New goat is being registered into Palai,
        // therefore check-in happens now.
        checkInDate:
        now,

        // It has not been checked out yet.
        checkOutDate:
        null,

        // These can be changed later according
        // to the customer's Palai package.
        monthlyPackage:
        '',

        pricing:
        0,

        notes:
        _notesController.text.trim(),

        isCheckedOut:
        false,

        // No image at registration.
        beforeImage:
        null,

        beforeImageContentType:
        null,

        afterImage:
        null,

        afterImageContentType:
        null,

        // Report starts with no generated report.
        reportStatus:
        'Not Generated',

        lastReportType:
        null,

        lastReportDate:
        null,

        reportsCount:
        0,
      );

      // -----------------------------------------------------------------------
      // SAVE TO FIRESTORE
      // -----------------------------------------------------------------------

      await goatReference.set(
        goat.toMap(),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Goat registered successfully.',
          ),
        ),
      );

      // Return the SAME PalaiGoat type from palai_models.dart.
      Navigator.of(context).pop(goat);
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _firebaseErrorMessage(e),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to register the goat. Please try again.',
          ),
        ),
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
      appBar: AppBar(
        title: const Text(
          'Register Goat',
        ),
      ),

      body: Form(
        key: _formKey,

        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            120,
          ),

          children: [
            _buildIntroCard(),

            const SizedBox(height: 24),

            _buildSectionTitle(
              'Goat Information',
            ),

            const SizedBox(height: 12),

            _buildGoatCodeField(),

            const SizedBox(height: 14),

            _buildBreedField(),

            const SizedBox(height: 14),

            _buildGenderField(),

            const SizedBox(height: 14),

            _buildColorField(),

            const SizedBox(height: 28),

            _buildSectionTitle(
              'Check-In Information',
            ),

            const SizedBox(height: 12),

            _buildWeightField(),

            const SizedBox(height: 14),

            _buildHealthInformation(),

            const SizedBox(height: 28),

            _buildSectionTitle(
              'Additional Information',
            ),

            const SizedBox(height: 12),

            _buildNotesField(),

            const SizedBox(height: 24),

            _buildInformationCard(),
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            10,
            16,
            16,
          ),

          child: SizedBox(
            height: 54,

            child: FilledButton.icon(
              onPressed:
              _saving
                  ? null
                  : _saveGoat,

              icon:
              _saving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
                  : const Icon(
                Icons.save_outlined,
              ),

              label: Text(
                _saving
                    ? 'Saving...'
                    : 'Register Goat',
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
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(18),

        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [
            const CircleAvatar(
              radius: 25,

              child: Icon(
                Icons.pets_outlined,
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
                    'Register a Customer Goat',

                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Register the goat directly into the Palai boarding system. The goat will be checked in immediately and can then be managed from its profile.',

                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // GOAT CODE
  // ===========================================================================

  Widget _buildGoatCodeField() {
    return TextFormField(
      controller:
      _goatCodeController,

      textCapitalization:
      TextCapitalization.characters,

      textInputAction:
      TextInputAction.next,

      decoration:
      const InputDecoration(
        labelText:
        'Goat Code / Tag Number',

        hintText:
        'Example: G-102',

        prefixIcon:
        Icon(
          Icons.qr_code_2_outlined,
        ),

        border:
        OutlineInputBorder(),

        helperText:
        'Use the unique number written on the goat tag.',
      ),

      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
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
    return TextFormField(
      controller:
      _breedController,

      textCapitalization:
      TextCapitalization.words,

      textInputAction:
      TextInputAction.next,

      decoration:
      const InputDecoration(
        labelText:
        'Breed',

        hintText:
        'Example: Sirohi',

        prefixIcon:
        Icon(
          Icons.category_outlined,
        ),

        border:
        OutlineInputBorder(),
      ),

      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
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
    return InputDecorator(
      decoration:
      const InputDecoration(
        labelText:
        'Gender',

        prefixIcon:
        Icon(
          Icons.wc_outlined,
        ),

        border:
        OutlineInputBorder(),
      ),

      child:
      DropdownButtonHideUnderline(
        child:
        DropdownButton<String>(
          value:
          _gender,

          isExpanded:
          true,

          items: const [
            DropdownMenuItem(
              value: 'Male',
              child:
              Text('Male'),
            ),

            DropdownMenuItem(
              value: 'Female',
              child:
              Text('Female'),
            ),
          ],

          onChanged:
              (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _gender =
                  value;
            });
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // COLOR
  // ===========================================================================

  Widget _buildColorField() {
    return TextFormField(
      onChanged: (value) {
        _color = value;
      },

      textCapitalization:
      TextCapitalization.words,

      textInputAction:
      TextInputAction.next,

      decoration:
      const InputDecoration(
        labelText:
        'Color',

        hintText:
        'Example: White / Black & White',

        prefixIcon:
        Icon(
          Icons.palette_outlined,
        ),

        border:
        OutlineInputBorder(),

        helperText:
        'Optional.',
      ),
    );
  }

  // ===========================================================================
  // WEIGHT
  // ===========================================================================

  Widget _buildWeightField() {
    return TextFormField(
      controller:
      _weightController,

      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),

      textInputAction:
      TextInputAction.next,

      decoration:
      const InputDecoration(
        labelText:
        'Weight at Check-In (kg)',

        hintText:
        'Example: 32.5',

        prefixIcon:
        Icon(
          Icons.monitor_weight_outlined,
        ),

        suffixText:
        'kg',

        border:
        OutlineInputBorder(),

        helperText:
        'This becomes the goat\'s initial Palai weight.',
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

  Widget _buildHealthInformation() {
    return InputDecorator(
      decoration:
      const InputDecoration(
        labelText:
        'Initial Health Status',

        prefixIcon:
        Icon(
          Icons
              .health_and_safety_outlined,
        ),

        border:
        OutlineInputBorder(),
      ),

      child:
      const Padding(
        padding:
        EdgeInsets.symmetric(
          vertical: 4,
        ),

        child: Text(
          'Healthy',
        ),
      ),
    );
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  Widget _buildNotesField() {
    return TextFormField(
      controller:
      _notesController,

      textCapitalization:
      TextCapitalization.sentences,

      minLines:
      3,

      maxLines:
      5,

      decoration:
      const InputDecoration(
        labelText:
        'Notes',

        hintText:
        'Add any useful information about this goat...',

        prefixIcon:
        Padding(
          padding:
          EdgeInsets.only(
            bottom: 45,
          ),

          child:
          Icon(
            Icons.notes_outlined,
          ),
        ),

        border:
        OutlineInputBorder(),
      ),
    );
  }

  // ===========================================================================
  // INFORMATION CARD
  // ===========================================================================

  Widget _buildInformationCard() {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),

        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [
            const Icon(
              Icons.info_outline,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Text(
                'After registration, the goat will be considered checked in. From the goat profile you can manage weight, health, vaccination, hoof cutting, hair trimming, medicine, monthly photos, reports and checkout.',

                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ),
          ],
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

      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(
        fontWeight:
        FontWeight.w700,
      ),
    );
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
        return 'Service is temporarily unavailable. Please try again.';

      default:
        return 'Unable to register the goat. Please try again.';
    }
  }
}