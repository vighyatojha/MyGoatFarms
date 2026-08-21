import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'add_customer_screen.dart';
import 'customer_profile_screen.dart';

/// ============================================================================
/// CUSTOMER PALAI - CUSTOMER LIST
/// ============================================================================
///
/// This is the NEW Customer Palai entry screen.
///
/// Responsibilities:
/// - Show Customer Palai customers
/// - Search customers
/// - Add a customer
/// - Open customer profile
/// - Show basic customer information
///
/// This screen intentionally does NOT handle:
/// - Goat management
/// - Billing
/// - Payments
/// - Reminders
/// - Health records
/// - Vaccinations
///
/// Those features will be handled by their own screens/services.
///
/// ============================================================================

class CustomerPalaiListScreen extends StatefulWidget {
  const CustomerPalaiListScreen({
    super.key,
  });

  @override
  State<CustomerPalaiListScreen> createState() =>
      _CustomerPalaiListScreenState();
}

class _CustomerPalaiListScreenState
    extends State<CustomerPalaiListScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final TextEditingController _searchController =
  TextEditingController();

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _onSearchChanged,
    );
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _searchQuery =
          _searchController.text.trim().toLowerCase();
    });
  }

  // ==========================================================================
  // FIRESTORE QUERY
  // ==========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _customerStream() {
    return _firestore
        .collection('palaiCustomers')
        .orderBy(
      'name',
      descending: false,
    )
        .snapshots();
  }

  // ==========================================================================
  // SEARCH
  // ==========================================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _filterCustomers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      customers,
      ) {
    if (_searchQuery.isEmpty) {
      return customers;
    }

    return customers.where((customer) {
      final data = customer.data();

      final name =
      (data['name'] ?? '')
          .toString()
          .toLowerCase();

      final mobile =
      (data['mobileNumber'] ??
          data['mobile'] ??
          '')
          .toString()
          .toLowerCase();

      final address =
      (data['address'] ?? '')
          .toString()
          .toLowerCase();

      return name.contains(_searchQuery) ||
          mobile.contains(_searchQuery) ||
          address.contains(_searchQuery);
    }).toList();
  }

  // ==========================================================================
  // ADD CUSTOMER
  // ==========================================================================

  Future<void> _showAddCustomerDialog() async {
    final nameController =
    TextEditingController();

    final mobileController =
    TextEditingController();

    final addressController =
    TextEditingController();

    final packageController =
    TextEditingController(
      text: 'Basic Palai',
    );

    final formKey =
    GlobalKey<FormState>();

    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            Future<void> saveCustomer() async {
              if (!formKey.currentState!
                  .validate()) {
                return;
              }

              setDialogState(() {
                saving = true;
              });

              try {
                final customerRef =
                _firestore
                    .collection(
                  'palaiCustomers',
                )
                    .doc();

                final now =
                Timestamp.now();

                await customerRef.set({
                  'name':
                  nameController.text.trim(),

                  'mobileNumber':
                  mobileController.text.trim(),

                  'address':
                  addressController.text.trim(),

                  'package':
                  packageController.text.trim(),

                  'joiningDate':
                  now,

                  'pendingAmount':
                  0.0,

                  'price':
                  0.0,

                  'createdAt':
                  now,

                  'updatedAt':
                  now,

                  'active':
                  true,
                });

                if (!context.mounted) {
                  return;
                }

                Navigator.of(
                  context,
                ).pop();

                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Customer added successfully.',
                    ),
                  ),
                );
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });

                if (!context.mounted) {
                  return;
                }

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Unable to add customer: $e',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text(
                'Add Customer',
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      _buildDialogField(
                        controller:
                        nameController,
                        label:
                        'Customer Name',
                        hint:
                        'Enter customer name',
                        icon:
                        Icons.person_outline,
                        validator:
                            (value) {
                          if (value == null ||
                              value
                                  .trim()
                                  .isEmpty) {
                            return 'Enter customer name';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      _buildDialogField(
                        controller:
                        mobileController,
                        label:
                        'Mobile Number',
                        hint:
                        'Enter mobile number',
                        icon:
                        Icons.phone_outlined,
                        keyboardType:
                        TextInputType.phone,
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      _buildDialogField(
                        controller:
                        addressController,
                        label:
                        'Address',
                        hint:
                        'Enter address',
                        icon:
                        Icons.location_on_outlined,
                        maxLines: 2,
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      _buildDialogField(
                        controller:
                        packageController,
                        label:
                        'Palai Package',
                        hint:
                        'Example: Basic Palai',
                        icon:
                        Icons.inventory_2_outlined,
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
                      context,
                    ).pop();
                  },
                  child: const Text(
                    'Cancel',
                  ),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : saveCustomer,
                  child: saving
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Save Customer',
                  ),
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
    packageController.dispose();
  }

  // ==========================================================================
  // CUSTOMER PROFILE
  // ==========================================================================

  void _openCustomerProfile(
      QueryDocumentSnapshot<Map<String, dynamic>>
      customer,
      ) {
    final customerId = customer.id;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerProfileScreen(
              customerId: customerId,
            ),
      ),
    );
  }

  // ==========================================================================
  // UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Customer Palai',
        ),
      ),
      floatingActionButton:
      FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
              const AddCustomerScreen(),
            ),
          );
        },
        icon: const Icon(
          Icons.person_add_alt_1,
        ),
        label: const Text(
          'Add Customer',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            _buildSearchBar(),

            Expanded(
              child: StreamBuilder<
                  QuerySnapshot<
                      Map<String, dynamic>>>(
                stream:
                _customerStream(),
                builder: (
                    context,
                    snapshot,
                    ) {
                  if (snapshot
                      .hasError) {
                    return _buildErrorState(
                      snapshot.error
                          .toString(),
                    );
                  }

                  if (snapshot
                      .connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child:
                      CircularProgressIndicator(),
                    );
                  }

                  final documents =
                      snapshot.data?.docs ??
                          [];

                  final customers =
                  _filterCustomers(
                    documents,
                  );

                  if (documents
                      .isEmpty) {
                    return _buildEmptyState(
                      isSearchResult:
                      false,
                    );
                  }

                  if (customers
                      .isEmpty) {
                    return _buildEmptyState(
                      isSearchResult:
                      true,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh:
                    _refreshCustomers,
                    child: ListView.separated(
                      padding:
                      const EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        100,
                      ),
                      itemCount:
                      customers.length,
                      separatorBuilder:
                          (_, __) =>
                      const SizedBox(
                        height: 10,
                      ),
                      itemBuilder: (
                          context,
                          index,
                          ) {
                        final customer =
                        customers[index];

                        return _buildCustomerCard(
                          customer,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // HEADER
  // ==========================================================================

  Widget _buildHeader() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Customers',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  'Manage goats, health, billing and records.',
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

  // ==========================================================================
  // SEARCH BAR
  // ==========================================================================

  Widget _buildSearchBar() {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      child: TextField(
        controller:
        _searchController,
        textInputAction:
        TextInputAction.search,
        decoration:
        InputDecoration(
          hintText:
          'Search customer...',
          prefixIcon:
          const Icon(
            Icons.search,
          ),
          suffixIcon:
          _searchQuery.isEmpty
              ? null
              : IconButton(
            onPressed: () {
              _searchController
                  .clear();
            },
            icon:
            const Icon(
              Icons.clear,
            ),
          ),
          border:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(
              14,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // CUSTOMER CARD
  // ==========================================================================

  Widget _buildCustomerCard(
      QueryDocumentSnapshot<
          Map<String, dynamic>>
      customer,
      ) {
    final data =
    customer.data();

    final name =
    _stringValue(
      data['name'],
      fallback: 'Unnamed Customer',
    );

    final mobile =
    _stringValue(
      data['mobileNumber'] ??
          data['mobile'],
    );

    final address =
    _stringValue(
      data['address'],
    );

    final package =
    _stringValue(
      data['package'],
      fallback: 'Palai',
    );

    final pendingAmount =
    _doubleValue(
      data['pendingAmount'],
    );

    final active =
        data['active'] != false;

    final initial =
    name.trim().isEmpty
        ? '?'
        : name
        .trim()
        .substring(0, 1)
        .toUpperCase();

    return Card(
      elevation: 0,
      clipBehavior:
      Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _openCustomerProfile(
              customer,
            ),
        child: Padding(
          padding:
          const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              _buildAvatar(
                initial,
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style:
                            const TextStyle(
                              fontSize: 17,
                              fontWeight:
                              FontWeight
                                  .w700,
                            ),
                          ),
                        ),

                        if (!active)
                          _buildStatusChip(
                            'Inactive',
                          ),
                      ],
                    ),

                    if (mobile
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 6,
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons
                                .phone_outlined,
                            size: 16,
                          ),
                          const SizedBox(
                            width: 6,
                          ),
                          Expanded(
                            child: Text(
                              mobile,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (address
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 5,
                      ),
                      Row(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          const Icon(
                            Icons
                                .location_on_outlined,
                            size: 16,
                          ),
                          const SizedBox(
                            width: 6,
                          ),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 2,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(
                      height: 12,
                    ),

                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildInfoChip(
                          icon:
                          Icons
                              .inventory_2_outlined,
                          label:
                          package,
                        ),

                        if (pendingAmount >
                            0)
                          _buildPendingChip(
                            pendingAmount,
                          )
                        else
                          _buildInfoChip(
                            icon:
                            Icons
                                .check_circle_outline,
                            label:
                            'No pending',
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              const Icon(
                Icons
                    .arrow_forward_ios,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // AVATAR
  // ==========================================================================

  Widget _buildAvatar(
      String initial,
      ) {
    return CircleAvatar(
      radius: 28,
      child: Text(
        initial,
        style:
        const TextStyle(
          fontSize: 21,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }

  // ==========================================================================
  // CHIPS
  // ==========================================================================

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration:
      BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius:
        BorderRadius.circular(
          8,
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            label,
            style:
            const TextStyle(
              fontSize: 12,
              fontWeight:
              FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingChip(
      double amount,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration:
      BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .errorContainer,
        borderRadius:
        BorderRadius.circular(
          8,
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            Icons
                .account_balance_wallet_outlined,
            size: 15,
            color: Theme.of(context)
                .colorScheme
                .onErrorContainer,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            'Pending ₹${amount.toStringAsFixed(0)}',
            style:
            TextStyle(
              fontSize: 12,
              fontWeight:
              FontWeight.w700,
              color: Theme.of(context)
                  .colorScheme
                  .onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
      String label,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration:
      BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius:
        BorderRadius.circular(
          8,
        ),
      ),
      child: Text(
        label,
        style:
        const TextStyle(
          fontSize: 11,
          fontWeight:
          FontWeight.w600,
        ),
      ),
    );
  }

  // ==========================================================================
  // EMPTY STATES
  // ==========================================================================

  Widget _buildEmptyState({
    required bool isSearchResult,
  }) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(
          32,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              isSearchResult
                  ? Icons.search_off
                  : Icons.people_outline,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .outline,
            ),

            const SizedBox(
              height: 16,
            ),

            Text(
              isSearchResult
                  ? 'No customer found'
                  : 'No customers yet',
              textAlign:
              TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              isSearchResult
                  ? 'Try another name or mobile number.'
                  : 'Add your first Customer Palai customer to get started.',
              textAlign:
              TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),

            if (!isSearchResult) ...[
              const SizedBox(
                height: 20,
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                      const AddCustomerScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons
                      .person_add_alt_1,
                ),
                label: const Text(
                  'Add Customer',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // ERROR
  // ==========================================================================

  Widget _buildErrorState(
      String error,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              Icons
                  .error_outline,
              size: 60,
              color: Theme.of(context)
                  .colorScheme
                  .error,
            ),
            const SizedBox(
              height: 16,
            ),
            const Text(
              'Unable to load customers',
              style:
              TextStyle(
                fontSize: 18,
                fontWeight:
                FontWeight.w700,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              error,
              textAlign:
              TextAlign.center,
              style:
              Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
            const SizedBox(
              height: 20,
            ),
            FilledButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // REFRESH
  // ==========================================================================

  Future<void> _refreshCustomers() async {
    // Firestore snapshots automatically refresh the UI.
    //
    // We keep this small delay so RefreshIndicator has a visible interaction
    // when the user pulls down.
    await Future<void>.delayed(
      const Duration(
        milliseconds: 400,
      ),
    );
  }

  // ==========================================================================
  // FORM FIELD
  // ==========================================================================

  Widget _buildDialogField({
    required TextEditingController
    controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType:
      keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration:
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon:
        Icon(icon),
        border:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // VALUE HELPERS
  // ==========================================================================

  String _stringValue(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final result =
    value.toString().trim();

    if (result.isEmpty) {
      return fallback;
    }

    return result;
  }

  double _doubleValue(
      dynamic value, {
        double fallback = 0,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        fallback;
  }
}

// ============================================================================
// TEMPORARY PROFILE SCREEN
// ============================================================================
//
// This is deliberately temporary.
//
// We need the Customer List to be testable immediately without waiting for
// the complete Customer Profile implementation.
//
// Later this screen will be replaced with:
//
// Customer Profile
//      ├── Customer Details
//      ├── Settings
//      ├── Goat List
//      ├── Billing
//      ├── Payments
//      ├── Reports
//      └── Reminders
//
// ============================================================================

class _TemporaryCustomerProfileScreen
    extends StatelessWidget {
  final String customerId;

  final Map<String, dynamic>
  customerData;

  const _TemporaryCustomerProfileScreen({
    required this.customerId,
    required this.customerData,
  });

  @override
  Widget build(BuildContext context) {
    final name =
    customerData['name']
        ?.toString()
        .trim()
        .isNotEmpty ==
        true
        ? customerData['name']
        .toString()
        : 'Customer';

    final mobile =
        customerData['mobileNumber']
            ?.toString() ??
            '';

    final address =
        customerData['address']
            ?.toString() ??
            '';

    final package =
        customerData['package']
            ?.toString() ??
            '';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: ListView(
        padding:
        const EdgeInsets.all(
          16,
        ),
        children: [
          Card(
            child: Padding(
              padding:
              const EdgeInsets.all(
                20,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  if (mobile
                      .isNotEmpty)
                    _detailRow(
                      context,
                      Icons
                          .phone_outlined,
                      'Mobile',
                      mobile,
                    ),

                  if (address
                      .isNotEmpty)
                    _detailRow(
                      context,
                      Icons
                          .location_on_outlined,
                      'Address',
                      address,
                    ),

                  if (package
                      .isNotEmpty)
                    _detailRow(
                      context,
                      Icons
                          .inventory_2_outlined,
                      'Package',
                      package,
                    ),

                  _detailRow(
                    context,
                    Icons
                        .fingerprint,
                    'Customer ID',
                    customerId,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          _featurePlaceholder(
            context,
            icon:
            Icons.pets_outlined,
            title:
            'Goats',
            subtitle:
            'Goat registration and management will be added next.',
          ),

          _featurePlaceholder(
            context,
            icon:
            Icons.settings_outlined,
            title:
            'Customer Settings',
            subtitle:
            'Vaccination, hoof and hair reminder settings will be added here.',
          ),

          _featurePlaceholder(
            context,
            icon:
            Icons.receipt_long_outlined,
            title:
            'Billing & Payments',
            subtitle:
            'Monthly billing and payment history will be connected later.',
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
      BuildContext context,
      IconData icon,
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context)
                .colorScheme
                .primary,
          ),
          const SizedBox(
            width: 10,
          ),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style:
              const TextStyle(
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _featurePlaceholder(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
      }) {
    return Card(
      margin:
      const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          title,
          style:
          const TextStyle(
            fontWeight:
            FontWeight.w600,
          ),
        ),
        subtitle:
        Padding(
          padding:
          const EdgeInsets.only(
            top: 4,
          ),
          child: Text(
            subtitle,
          ),
        ),
        trailing:
        const Icon(
          Icons
              .arrow_forward_ios,
          size: 16,
        ),
      ),
    );
  }
}