import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_goat.dart';

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

  final _nameController = TextEditingController();
  final _tagNumberController = TextEditingController();
  final _breedController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime? _dateOfBirth;
  String _gender = 'Male';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _tagNumberController.dispose();
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

      final double? weight =
      weightText.isEmpty
          ? null
          : double.tryParse(weightText);

      final goat = PalaiGoat(
        id: goatReference.id,
        customerId: widget.customerId,
        name: _nameController.text.trim(),
        tagNumber:
        _tagNumberController.text.trim(),
        breed: _breedController.text.trim(),
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        currentWeight: weight,
        status: 'active',
        imageUrl: null,
        notes: _notesController.text.trim(),
        registrationDate: now,
        updatedAt: now,
      );

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
    } catch (_) {
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
  // DATE PICKER
  // ===========================================================================

  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      initialDate:
      _dateOfBirth ?? now,
      firstDate: DateTime(
        2000,
        1,
        1,
      ),
      lastDate: now,
      helpText: 'Select date of birth',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );

    if (selectedDate == null) {
      return;
    }

    setState(() {
      _dateOfBirth = selectedDate;
    });
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
              'Basic Information',
            ),

            const SizedBox(height: 12),

            _buildNameField(),

            const SizedBox(height: 14),

            _buildTagField(),

            const SizedBox(height: 14),

            _buildBreedField(),

            const SizedBox(height: 14),

            _buildGenderField(),

            const SizedBox(height: 28),

            _buildSectionTitle(
              'Birth & Weight',
            ),

            const SizedBox(height: 12),

            _buildDateOfBirthField(),

            const SizedBox(height: 14),

            _buildWeightField(),

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
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              child: const Icon(
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
                    'Add the basic details of the goat. You can add health, vaccination, weight and other records later from the goat profile.',
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
  // NAME
  // ===========================================================================

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      textCapitalization:
      TextCapitalization.words,
      textInputAction:
      TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Goat Name',
        hintText: 'Example: Raja',
        prefixIcon: Icon(
          Icons.pets_outlined,
        ),
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
          return 'Enter the goat name';
        }

        if (text.length < 2) {
          return 'Goat name is too short';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // TAG
  // ===========================================================================

  Widget _buildTagField() {
    return TextFormField(
      controller: _tagNumberController,
      textCapitalization:
      TextCapitalization.characters,
      textInputAction:
      TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Tag / ID Number',
        hintText: 'Example: G-102',
        prefixIcon: Icon(
          Icons.qr_code_2_outlined,
        ),
        border: OutlineInputBorder(),
        helperText:
        'Use the number written on the goat tag.',
      ),
      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
          return 'Enter the goat tag / ID number';
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
      controller: _breedController,
      textCapitalization:
      TextCapitalization.words,
      textInputAction:
      TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Breed',
        hintText: 'Example: Sirohi',
        prefixIcon: Icon(
          Icons.category_outlined,
        ),
        border: OutlineInputBorder(),
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
      decoration: const InputDecoration(
        labelText: 'Gender',
        prefixIcon: Icon(
          Icons.wc_outlined,
        ),
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _gender,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'Male',
              child: Text('Male'),
            ),
            DropdownMenuItem(
              value: 'Female',
              child: Text('Female'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _gender = value;
            });
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // DATE OF BIRTH
  // ===========================================================================

  Widget _buildDateOfBirthField() {
    return InkWell(
      onTap: _selectDateOfBirth,
      borderRadius:
      BorderRadius.circular(4),
      child: InputDecorator(
        decoration:
        const InputDecoration(
          labelText: 'Date of Birth',
          hintText:
          'Select if known',
          prefixIcon: Icon(
            Icons
                .calendar_today_outlined,
          ),
          border:
          OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _dateOfBirth == null
                    ? 'Not entered'
                    : _formatDate(
                  _dateOfBirth!,
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(
                  color:
                  _dateOfBirth ==
                      null
                      ? Theme.of(
                    context,
                  )
                      .colorScheme
                      .onSurfaceVariant
                      : null,
                ),
              ),
            ),
            if (_dateOfBirth != null)
              IconButton(
                tooltip:
                'Clear date',
                onPressed: () {
                  setState(() {
                    _dateOfBirth =
                    null;
                  });
                },
                icon: const Icon(
                  Icons.clear,
                ),
              )
            else
              const Icon(
                Icons
                    .calendar_month_outlined,
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // WEIGHT
  // ===========================================================================

  Widget _buildWeightField() {
    return TextFormField(
      controller: _weightController,
      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),
      textInputAction:
      TextInputAction.next,
      decoration: const InputDecoration(
        labelText:
        'Current Weight (kg)',
        hintText: 'Example: 32.5',
        prefixIcon: Icon(
          Icons.monitor_weight_outlined,
        ),
        suffixText: 'kg',
        border: OutlineInputBorder(),
        helperText:
        'Optional. You can record detailed weight history later.',
      ),
      validator: (value) {
        final text =
            value?.trim() ?? '';

        if (text.isEmpty) {
          return null;
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
  // NOTES
  // ===========================================================================

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      textCapitalization:
      TextCapitalization.sentences,
      minLines: 3,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Notes',
        hintText:
        'Add any useful information about this goat...',
        prefixIcon: Padding(
          padding: EdgeInsets.only(
            bottom: 45,
          ),
          child: Icon(
            Icons.notes_outlined,
          ),
        ),
        border: OutlineInputBorder(),
      ),
    );
  }

  // ===========================================================================
  // INFORMATION CARD
  // ===========================================================================

  Widget _buildInformationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                'After registration, this goat will appear under the customer. From its profile you will be able to manage weight, health, vaccination, hoof cutting, hair trimming, medicines, photos and other records.',
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
  // HELPERS
  // ===========================================================================

  String _formatDate(
      DateTime date,
      ) {
    final day =
    date.day.toString().padLeft(
      2,
      '0',
    );

    final month =
    date.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${date.year}';
  }

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