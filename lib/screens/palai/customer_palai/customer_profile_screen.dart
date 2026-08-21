import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'customer_settings_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  final String customerId;

  const CustomerProfileScreen({
    super.key,
    required this.customerId,
  });

  @override
  State<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState
    extends State<CustomerProfileScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _customer;

  @override
  void initState() {
    super.initState();
    _loadCustomer();
  }

  // ===========================================================================
  // LOAD CUSTOMER
  // ===========================================================================

  Future<void> _loadCustomer() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final doc = await _firestore
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .get();

      if (!mounted) {
        return;
      }

      if (!doc.exists) {
        setState(() {
          _loading = false;
          _error = 'Customer not found.';
        });
        return;
      }

      setState(() {
        _customer = doc.data();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'Unable to load customer.';
      });
    }
  }

  // ===========================================================================
  // EDIT CUSTOMER
  // ===========================================================================

  Future<void> _editCustomer() async {
    if (_customer == null) {
      return;
    }

    final nameController = TextEditingController(
      text: _customer?['name']?.toString() ?? '',
    );

    final mobileController = TextEditingController(
      text:
      _customer?['mobileNumber']?.toString() ?? '',
    );

    final addressController = TextEditingController(
      text: _customer?['address']?.toString() ?? '',
    );

    final priceController = TextEditingController(
      text: _customer?['price']?.toString() ?? '',
    );

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return AlertDialog(
              title: const Text(
                'Edit Customer',
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        textCapitalization:
                        TextCapitalization.words,
                        decoration:
                        const InputDecoration(
                          labelText: 'Customer Name',
                          prefixIcon: Icon(
                            Icons.person_outline,
                          ),
                          border:
                          OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'Enter customer name';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                        mobileController,
                        keyboardType:
                        TextInputType.phone,
                        maxLength: 10,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Mobile Number',
                          prefixIcon: Icon(
                            Icons.phone_outlined,
                          ),
                          border:
                          OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return null;
                          }

                          if (!RegExp(
                            r'^[0-9]{10}$',
                          ).hasMatch(
                            value.trim(),
                          )) {
                            return 'Enter a valid 10-digit number';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                        addressController,
                        maxLines: 3,
                        textCapitalization:
                        TextCapitalization.sentences,
                        decoration:
                        const InputDecoration(
                          labelText: 'Address',
                          prefixIcon: Icon(
                            Icons
                                .location_on_outlined,
                          ),
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                        priceController,
                        keyboardType:
                        const TextInputType
                            .numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Monthly Price',
                          prefixIcon: Icon(
                            Icons.currency_rupee,
                          ),
                          border:
                          OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'Enter monthly price';
                          }

                          final price =
                          double.tryParse(
                            value.trim(),
                          );

                          if (price == null ||
                              price < 0) {
                            return 'Enter a valid price';
                          }

                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                    Navigator.of(
                      dialogContext,
                    ).pop(false);
                  },
                  child:
                  const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                    if (!formKey
                        .currentState!
                        .validate()) {
                      return;
                    }

                    setDialogState(() {
                      saving = true;
                    });

                    try {
                      final price =
                          double.tryParse(
                            priceController
                                .text
                                .trim(),
                          ) ??
                              0.0;

                      await _firestore
                          .collection(
                        'palaiCustomers',
                      )
                          .doc(
                        widget.customerId,
                      )
                          .update({
                        'name':
                        nameController
                            .text
                            .trim(),
                        'mobileNumber':
                        mobileController
                            .text
                            .trim(),
                        'address':
                        addressController
                            .text
                            .trim(),
                        'price': price,
                        'updatedAt':
                        Timestamp.now(),
                      });

                      if (!dialogContext
                          .mounted) {
                        return;
                      }

                      Navigator.of(
                        dialogContext,
                      ).pop(true);
                    } catch (e) {
                      setDialogState(() {
                        saving = false;
                      });

                      if (!dialogContext
                          .mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Unable to update customer.',
                          ),
                        ),
                      );
                    }
                  },
                  child: saving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    mobileController.dispose();
    addressController.dispose();
    priceController.dispose();

    if (result == true) {
      await _loadCustomer();
    }
  }

  // ===========================================================================
  // CUSTOMER SETTINGS
  // ===========================================================================

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerSettingsScreen(
              customerId: widget.customerId,
            ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadCustomer();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Customer Profile',
        ),
        actions: [
          if (!_loading &&
              _customer != null)
            IconButton(
              tooltip: 'Edit customer',
              onPressed:
              _editCustomer,
              icon: const Icon(
                Icons.edit_outlined,
              ),
            ),
          if (!_loading &&
              _customer != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value ==
                    'settings') {
                  _openSettings();
                }
              },
              itemBuilder:
                  (context) => [
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    contentPadding:
                    EdgeInsets.zero,
                    leading: Icon(
                      Icons
                          .settings_outlined,
                    ),
                    title: Text(
                      'Customer Settings',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child:
        CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    if (_customer == null) {
      return const Center(
        child: Text(
          'Customer information unavailable.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCustomer,
      child: ListView(
        padding:
        const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32,
        ),
        children: [
          _buildCustomerHeader(),

          const SizedBox(
            height: 20,
          ),

          _buildQuickSummary(),

          const SizedBox(
            height: 24,
          ),

          _buildSectionTitle(
            'Customer Information',
          ),

          const SizedBox(
            height: 12,
          ),

          _buildInformationCard(),

          const SizedBox(
            height: 24,
          ),

          _buildSectionTitle(
            'Palai Management',
          ),

          const SizedBox(
            height: 12,
          ),

          _buildManagementGrid(),

          const SizedBox(
            height: 24,
          ),

          _buildSectionTitle(
            'Customer Settings',
          ),

          const SizedBox(
            height: 12,
          ),

          _buildSettingsPreview(),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildCustomerHeader() {
    final name =
    _customer?['name']
        ?.toString()
        .trim()
        .isNotEmpty ==
        true
        ? _customer!['name']
        .toString()
        : 'Customer';

    final package =
        _customer?['package']
            ?.toString() ??
            'Palai';

    final active =
        _customer?['active'] == true;

    return Container(
      padding:
      const EdgeInsets.all(20),
      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(20),
        color: Theme.of(context)
            .colorScheme
            .primaryContainer,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            child: Text(
              _initials(name),
              style: const TextStyle(
                fontSize: 20,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  package,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium,
                ),
                const SizedBox(
                  height: 8,
                ),
                Row(
                  children: [
                    Icon(
                      active
                          ? Icons.check_circle
                          : Icons
                          .cancel_outlined,
                      size: 16,
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    Text(
                      active
                          ? 'Active Customer'
                          : 'Inactive Customer',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // QUICK SUMMARY
  // ===========================================================================

  Widget _buildQuickSummary() {
    final price =
    _asDouble(
      _customer?['price'],
    );

    final pending =
    _asDouble(
      _customer?['pendingAmount'],
    );

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            icon:
            Icons.currency_rupee,
            title:
            'Monthly Price',
            value:
            '₹${_formatAmount(price)}',
          ),
        ),
        const SizedBox(
          width: 12,
        ),
        Expanded(
          child: _buildSummaryCard(
            icon:
            Icons
                .account_balance_wallet_outlined,
            title:
            'Pending',
            value:
            '₹${_formatAmount(pending)}',
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 24,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
            const SizedBox(
              height: 3,
            ),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // INFORMATION
  // ===========================================================================

  Widget _buildInformationCard() {
    final mobile =
        _customer?['mobileNumber']
            ?.toString() ??
            '';

    final address =
        _customer?['address']
            ?.toString() ??
            '';

    final package =
        _customer?['package']
            ?.toString() ??
            '';

    final joiningDate =
    _asDate(
      _customer?['joiningDate'],
    );

    return Card(
      child: Column(
        children: [
          _buildInfoRow(
            icon:
            Icons.phone_outlined,
            label:
            'Mobile Number',
            value: mobile.isEmpty
                ? 'Not provided'
                : mobile,
          ),
          const Divider(
            height: 1,
          ),
          _buildInfoRow(
            icon:
            Icons
                .location_on_outlined,
            label:
            'Address',
            value: address.isEmpty
                ? 'Not provided'
                : address,
          ),
          const Divider(
            height: 1,
          ),
          _buildInfoRow(
            icon:
            Icons
                .inventory_2_outlined,
            label:
            'Palai Package',
            value:
            package.isEmpty
                ? 'Not provided'
                : package,
          ),
          const Divider(
            height: 1,
          ),
          _buildInfoRow(
            icon:
            Icons
                .calendar_today_outlined,
            label:
            'Joining Date',
            value:
            joiningDate == null
                ? 'Not provided'
                : _formatDate(
              joiningDate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding:
      const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 22,
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
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w500,
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
  // MANAGEMENT GRID
  // ===========================================================================

  Widget _buildManagementGrid() {
    final items = [
      _ManagementItem(
        icon:
        Icons.pets_outlined,
        title: 'Goats',
        subtitle:
        'Register and manage goats',
        onTap: () {
          _showComingSoon(
            'Goat management',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.receipt_long_outlined,
        title: 'Billing',
        subtitle:
        'Monthly bills and payments',
        onTap: () {
          _showComingSoon(
            'Billing',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.medical_services_outlined,
        title: 'Health',
        subtitle:
        'Health and medicine records',
        onTap: () {
          _showComingSoon(
            'Health records',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.vaccines_outlined,
        title: 'Vaccination',
        subtitle:
        'Schedule and history',
        onTap: () {
          _showComingSoon(
            'Vaccination',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.content_cut_outlined,
        title: 'Hoof & Hair',
        subtitle:
        'Care records and reminders',
        onTap: () {
          _showComingSoon(
            'Hoof and hair management',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.photo_library_outlined,
        title: 'Photos',
        subtitle:
        'Monthly goat photos',
        onTap: () {
          _showComingSoon(
            'Monthly photos',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.assessment_outlined,
        title: 'Reports',
        subtitle:
        'Monthly customer reports',
        onTap: () {
          _showComingSoon(
            'Reports',
          );
        },
      ),
      _ManagementItem(
        icon:
        Icons.settings_outlined,
        title: 'Settings',
        subtitle:
        'Reminder preferences',
        onTap: _openSettings,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics:
      const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder:
          (context, index) {
        final item =
        items[index];

        return InkWell(
          onTap: item.onTap,
          borderRadius:
          BorderRadius.circular(
            16,
          ),
          child: Card(
            child: Padding(
              padding:
              const EdgeInsets.all(
                14,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    child: Icon(
                      item.icon,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.title,
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow:
                    TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // SETTINGS PREVIEW
  // ===========================================================================

  Widget _buildSettingsPreview() {
    final settings =
    Map<String, dynamic>.from(
      (_customer?['settings']
      as Map?) ??
          {},
    );

    final vaccination =
        (settings[
        'vaccinationReminderDays']
        as num?)
            ?.toInt() ??
            30;

    final hoof =
        (settings[
        'hoofCuttingReminderDays']
        as num?)
            ?.toInt() ??
            30;

    final hair =
        (settings[
        'hairTrimmingReminderDays']
        as num?)
            ?.toInt() ??
            30;

    return Card(
      child: Column(
        children: [
          _buildSettingRow(
            icon:
            Icons.vaccines_outlined,
            title:
            'Vaccination',
            value:
            'Every $vaccination days',
          ),
          const Divider(
            height: 1,
          ),
          _buildSettingRow(
            icon:
            Icons.content_cut_outlined,
            title:
            'Hoof Cutting',
            value:
            'Every $hoof days',
          ),
          const Divider(
            height: 1,
          ),
          _buildSettingRow(
            icon:
            Icons.content_cut_outlined,
            title:
            'Hair Trimming',
            value:
            'Every $hair days',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading:
      Icon(icon),
      title:
      Text(title),
      trailing:
      Text(
        value,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(
          fontWeight:
          FontWeight.w600,
        ),
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .error_outline,
              size: 48,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              _error ??
                  'Something went wrong.',
              textAlign:
              TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),
            const SizedBox(
              height: 16,
            ),
            FilledButton.icon(
              onPressed:
              _loadCustomer,
              icon: const Icon(
                Icons.refresh,
              ),
              label:
              const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // COMING SOON
  // ===========================================================================

  void _showComingSoon(
      String feature,
      ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '$feature will be connected next.',
        ),
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _initials(
      String name,
      ) {
    final parts =
    name.trim().split(
      RegExp(r'\s+'),
    );

    if (parts.isEmpty) {
      return 'C';
    }

    if (parts.length == 1) {
      return parts.first
          .substring(
        0,
        parts.first.length > 2
            ? 2
            : parts.first.length,
      )
          .toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'
        .toUpperCase();
  }

  double _asDouble(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0.0;
  }

  DateTime? _asDate(
      dynamic value,
      ) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  String _formatAmount(
      double amount,
      ) {
    if (amount == amount.roundToDouble()) {
      return amount
          .toInt()
          .toString();
    }

    return amount
        .toStringAsFixed(2);
  }

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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

// ==============================================================================
// MANAGEMENT ITEM
// ==============================================================================

class _ManagementItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManagementItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}