import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({
    super.key,
  });

  @override
  State<AddCustomerScreen> createState() =>
      _AddCustomerScreenState();
}

class _AddCustomerScreenState
    extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController =
  TextEditingController();

  final _mobileController =
  TextEditingController();

  final _addressController =
  TextEditingController();

  final _priceController =
  TextEditingController();

  final _customPackageController =
  TextEditingController();

  DateTime _joiningDate =
  DateTime.now();

  String _selectedPackage =
      'Basic Palai';

  bool _saving = false;

  final List<String> _packages = [
    'Basic Palai',
    'Special Palai',
    'Custom',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _priceController.dispose();
    _customPackageController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // DATE
  // ===========================================================================

  Future<void> _selectJoiningDate() async {
    final selected =
    await showDatePicker(
      context: context,
      initialDate: _joiningDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText:
      'Select joining date',
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _joiningDate = selected;
    });
  }

  // ===========================================================================
  // SAVE CUSTOMER
  // ===========================================================================

  Future<void> _saveCustomer() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final firestore =
          FirebaseFirestore.instance;

      final customerRef = firestore
          .collection('palaiCustomers')
          .doc();

      final now =
      Timestamp.now();

      final package =
      _selectedPackage == 'Custom'
          ? _customPackageController
          .text
          .trim()
          : _selectedPackage;

      final price =
          double.tryParse(
            _priceController.text
                .trim(),
          ) ??
              0.0;

      await customerRef.set({
        'id': customerRef.id,

        'name':
        _nameController.text.trim(),

        'mobileNumber':
        _mobileController.text.trim(),

        'address':
        _addressController.text.trim(),

        'package':
        package,

        'joiningDate':
        Timestamp.fromDate(
          _joiningDate,
        ),

        'price':
        price,

        'pendingAmount':
        0.0,

        'createdAt':
        now,

        'updatedAt':
        now,

        'active':
        true,
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Customer added successfully.',
          ),
        ),
      );

      Navigator.of(context).pop(
        customerRef.id,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Unable to save customer: $e',
          ),
        ),
      );
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
          'Add Customer',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding:
                  const EdgeInsets.fromLTRB(
                    16,
                    20,
                    16,
                    24,
                  ),
                  children: [
                    _buildIntro(),

                    const SizedBox(
                      height: 24,
                    ),

                    _buildSectionTitle(
                      'Customer Details',
                      'Basic information about the customer.',
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    _buildTextField(
                      controller:
                      _nameController,
                      label:
                      'Customer Name',
                      hint:
                      'Enter customer name',
                      icon:
                      Icons.person_outline,
                      requiredField:
                      true,
                      textCapitalization:
                      TextCapitalization.words,
                      validator:
                      _validateName,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    _buildTextField(
                      controller:
                      _mobileController,
                      label:
                      'Mobile Number',
                      hint:
                      'Enter mobile number',
                      icon:
                      Icons.phone_outlined,
                      keyboardType:
                      TextInputType.phone,
                      maxLength: 10,
                      validator:
                      _validateMobile,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    _buildTextField(
                      controller:
                      _addressController,
                      label:
                      'Address',
                      hint:
                      'Enter customer address',
                      icon:
                      Icons
                          .location_on_outlined,
                      maxLines: 3,
                      textCapitalization:
                      TextCapitalization.sentences,
                    ),

                    const SizedBox(
                      height: 28,
                    ),

                    _buildSectionTitle(
                      'Palai Details',
                      'Set the customer\'s Palai package and pricing.',
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    _buildPackageSelector(),

                    if (_selectedPackage ==
                        'Custom') ...[
                      const SizedBox(
                        height: 16,
                      ),
                      _buildTextField(
                        controller:
                        _customPackageController,
                        label:
                        'Custom Package Name',
                        hint:
                        'Enter package name',
                        icon:
                        Icons
                            .edit_outlined,
                        requiredField:
                        true,
                        textCapitalization:
                        TextCapitalization.words,
                        validator:
                            (value) {
                          if (_selectedPackage !=
                              'Custom') {
                            return null;
                          }

                          if (value ==
                              null ||
                              value
                                  .trim()
                                  .isEmpty) {
                            return 'Enter package name';
                          }

                          return null;
                        },
                      ),
                    ],

                    const SizedBox(
                      height: 16,
                    ),

                    _buildTextField(
                      controller:
                      _priceController,
                      label:
                      'Monthly Price',
                      hint:
                      'Enter monthly Palai price',
                      icon:
                      Icons
                          .currency_rupee,
                      keyboardType:
                      const TextInputType
                          .numberWithOptions(
                        decimal: true,
                      ),
                      requiredField:
                      true,
                      prefixText:
                      '₹ ',
                      validator:
                      _validatePrice,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    _buildDateField(),

                    const SizedBox(
                      height: 28,
                    ),

                    _buildInformationCard(),
                  ],
                ),
              ),

              _buildBottomButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // INTRO
  // ===========================================================================

  Widget _buildIntro() {
    return Container(
      padding:
      const EdgeInsets.all(18),
      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(16),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            child: const Icon(
              Icons.person_add_alt_1,
            ),
          ),
          const SizedBox(
            width: 14,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'New Customer Palai',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  'Enter the customer details below. You can add goats and other records after creating the customer.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION TITLE
  // ===========================================================================

  Widget _buildSectionTitle(
      String title,
      String subtitle,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight:
            FontWeight.w700,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall,
        ),
      ],
    );
  }

  // ===========================================================================
  // TEXT FIELD
  // ===========================================================================

  Widget _buildTextField({
    required TextEditingController
    controller,
    required String label,
    required String hint,
    required IconData icon,
    bool requiredField = false,
    TextInputType? keyboardType,
    TextCapitalization
    textCapitalization =
        TextCapitalization.none,
    int maxLines = 1,
    int? maxLength,
    String? prefixText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType:
      keyboardType,
      textCapitalization:
      textCapitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      decoration:
      InputDecoration(
        labelText:
        requiredField
            ? '$label *'
            : label,
        hintText: hint,
        prefixIcon:
        Icon(icon),
        prefixText:
        prefixText,
        border:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
          borderSide:
          BorderSide(
            color: Theme.of(context)
                .colorScheme
                .primary,
            width: 2,
          ),
        ),
        counterText:
        maxLength != null
            ? null
            : '',
      ),
    );
  }

  // ===========================================================================
  // PACKAGE SELECTOR
  // ===========================================================================

  Widget _buildPackageSelector() {
    return DropdownButtonFormField<String>(
      initialValue:
      _selectedPackage,
      decoration:
      InputDecoration(
        labelText:
        'Palai Package *',
        prefixIcon:
        const Icon(
          Icons
              .inventory_2_outlined,
        ),
        border:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
      ),
      items:
      _packages.map(
            (package) {
          return DropdownMenuItem<
              String>(
            value: package,
            child: Text(
              package,
            ),
          );
        },
      ).toList(),
      onChanged: _saving
          ? null
          : (value) {
        if (value == null) {
          return;
        }

        setState(() {
          _selectedPackage =
              value;
        });
      },
      validator: (value) {
        if (value == null ||
            value.isEmpty) {
          return 'Select a Palai package';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // DATE
  // ===========================================================================

  Widget _buildDateField() {
    return InkWell(
      onTap: _saving
          ? null
          : _selectJoiningDate,
      borderRadius:
      BorderRadius.circular(
        12,
      ),
      child: InputDecorator(
        decoration:
        InputDecoration(
          labelText:
          'Joining Date *',
          prefixIcon:
          const Icon(
            Icons
                .calendar_today_outlined,
          ),
          border:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(
              12,
            ),
          ),
          enabledBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(
              12,
            ),
          ),
        ),
        child: Text(
          _formatDate(
            _joiningDate,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // INFORMATION CARD
  // ===========================================================================

  Widget _buildInformationCard() {
    return Container(
      padding:
      const EdgeInsets.all(16),
      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons
                .info_outline,
            color: Theme.of(context)
                .colorScheme
                .primary,
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Text(
              'After saving, this customer will become available in Customer Palai. You can then register their goats and manage their complete Palai records.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BOTTOM BUTTON
  // ===========================================================================

  Widget _buildBottomButton() {
    return Material(
      elevation: 8,
      color: Theme.of(context)
          .scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed:
              _saving
                  ? null
                  : _saveCustomer,
              icon: _saving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
                  : const Icon(
                Icons
                    .person_add_alt_1,
              ),
              label: Text(
                _saving
                    ? 'Saving Customer...'
                    : 'Save Customer',
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // VALIDATION
  // ===========================================================================

  String? _validateName(
      String? value,
      ) {
    if (value == null ||
        value.trim().isEmpty) {
      return 'Enter customer name';
    }

    if (value.trim().length < 2) {
      return 'Enter a valid customer name';
    }

    return null;
  }

  String? _validateMobile(
      String? value,
      ) {
    if (value == null ||
        value.trim().isEmpty) {
      return null;
    }

    final mobile =
    value.trim();

    if (!RegExp(
      r'^[0-9]{10}$',
    ).hasMatch(mobile)) {
      return 'Enter a valid 10-digit mobile number';
    }

    return null;
  }

  String? _validatePrice(
      String? value,
      ) {
    if (value == null ||
        value.trim().isEmpty) {
      return 'Enter monthly price';
    }

    final price =
    double.tryParse(
      value.trim(),
    );

    if (price == null) {
      return 'Enter a valid amount';
    }

    if (price < 0) {
      return 'Price cannot be negative';
    }

    return null;
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
}