import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../palai/add_customer_screen.dart';
import 'customer_profile_screen.dart';

/// Customer management screen for the MyGoatFarms application.
///
/// Features:
/// - Customer list
/// - Search by name / mobile
/// - Total customer count
/// - Total pending amount
/// - Total advance amount
/// - Customer profile
/// - Edit customer
/// - Delete customer
/// - Prevent deletion when active goats exist
class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState
    extends State<CustomerManagementScreen> {
  String? _farmId;

  final TextEditingController _searchController =
  TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();

    _loadFarm();

    _searchController.addListener(() {
      final value =
      _searchController.text.trim().toLowerCase();

      if (_query == value) return;

      setState(() {
        _query = value;
      });
    });
  }

  Future<void> _loadFarm() async {
    try {
      final id =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId = id;
      });
    } catch (e) {
      debugPrint('Customer screen farm error: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PalaiCustomer> _filterCustomers(
      List<PalaiCustomer> customers,
      ) {
    if (_query.isEmpty) {
      return customers;
    }

    return customers.where((customer) {
      final name =
      customer.name.toLowerCase();

      final mobile =
      customer.mobileNumber.toLowerCase();

      return name.contains(_query) ||
          mobile.contains(_query);
    }).toList();
  }

  Future<void> _openAddCustomer() async {
    await Navigator.of(context).push(
      fastRoute(
        const AddCustomerScreen(),
      ),
    );
  }

  Future<void> _openProfile(
      PalaiCustomer customer,
      ) async {
    final farmId = _farmId;

    if (farmId == null) return;

    await Navigator.of(context).push(
      fastRoute(
        CustomerProfileScreen(
          customer: customer,
          farmId: farmId,
        ),
      ),
    );
  }

  Future<void> _openEdit(
      PalaiCustomer customer,
      ) async {
    await Navigator.of(context).push(
      fastRoute(
        AddCustomerScreen(
          customer: customer,
        ),
      ),
    );
  }

  Future<void> _deleteCustomer(
      PalaiCustomer customer,
      ) async {
    final farmId = _farmId;

    if (farmId == null) return;

    try {
      final hasActiveGoats =
      await FirestoreService.instance
          .customerHasActiveGoats(
        farmId,
        customer.id,
      );

      if (!mounted) return;

      if (hasActiveGoats) {
        await _showActiveGoatsDialog(customer);
        return;
      }

      final confirmed =
      await _showDeleteConfirmation(customer);

      if (confirmed != true) return;

      if (!mounted) return;

      _showLoadingSnackBar(
        'Deleting ${customer.name}...',
      );

      await FirestoreService.instance
          .deleteCustomer(
        farmId,
        customer.id,
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.customerDeleted,
          title: 'Customer Deleted',
          subtitle:
          '${customer.name} removed from Palai',
          module: 'palai',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
          Text('${customer.name} deleted successfully'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    } on TimeoutException {
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This is taking too long. Check your internet connection.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirestoreService.instance.describeError(e),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showActiveGoatsDialog(
      PalaiCustomer customer,
      ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Cannot Delete Customer',
            style: AppTheme.heading(size: 17),
          ),
          content: Text(
            '${customer.name} still has goats checked into Palai.\n\n'
                'Please check out all of the customer\'s goats before deleting this customer.',
            style: AppTheme.body(size: 13),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                'OK',
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.darkGreen,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showDeleteConfirmation(
      PalaiCustomer customer,
      ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Delete Customer?',
            style: AppTheme.heading(size: 17),
          ),
          content: Text(
            'Are you sure you want to delete ${customer.name}?\n\n'
                'This will permanently remove the customer and their Palai history.',
            style: AppTheme.body(size: 13),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(
                'Cancel',
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.textGrey,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                'Delete',
                style: AppTheme.body(
                  size: 13,
                  color: AppColors.error,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showLoadingSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.darkGreen,
        duration: const Duration(seconds: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        )
            : StreamBuilder<List<PalaiCustomer>>(
          stream: FirestoreService.instance
              .customersStream(_farmId!),
          builder: (
              context,
              snapshot,
              ) {
            if (snapshot.hasError) {
              return _buildErrorState(
                snapshot.error.toString(),
              );
            }

            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              );
            }

            final allCustomers =
                snapshot.data ?? [];

            final customers =
            _filterCustomers(
              allCustomers,
            );

            return CustomScrollView(
              physics:
              const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      4,
                    ),
                    child: _buildSummary(
                      allCustomers,
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      8,
                    ),
                    child: _buildSearch(),
                  ),
                ),

                if (customers.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child:
                    _buildEmptyState(
                      allCustomers.isEmpty,
                    ),
                  )
                else
                  SliverPadding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      28,
                    ),
                    sliver:
                    SliverList.separated(
                      itemCount:
                      customers.length,
                      separatorBuilder:
                          (_, __) =>
                      const SizedBox(
                        height: 10,
                      ),
                      itemBuilder:
                          (context, index) {
                        final customer =
                        customers[index];

                        return _CustomerCard(
                          customer:
                          customer,
                          onTap: () =>
                              _openProfile(
                                customer,
                              ),
                          onEdit: () =>
                              _openEdit(
                                customer,
                              ),
                          onDelete: () =>
                              _deleteCustomer(
                                customer,
                              ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        14,
        16,
        6,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_alt_outlined,
              color: AppColors.primaryGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Customers',
                  style: AppTheme.heading(
                    size: 20,
                  ),
                ),
                Text(
                  'Manage your Palai customers',
                  style: AppTheme.body(
                    size: 11,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _openAddCustomer,
            style: ElevatedButton.styleFrom(
              backgroundColor:
              AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
              const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              shape:
              RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add,
                  size: 18,
                ),
                SizedBox(width: 4),
                Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
      List<PalaiCustomer> customers,
      ) {
    double pending = 0;
    double advance = 0;

    for (final customer in customers) {
      pending += customer.pendingAmount;
      advance += customer.advanceAmount;
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon:
                Icons.people_outline,
                title: 'Customers',
                value:
                '${customers.length}',
                color:
                AppColors.info,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryCard(
                icon:
                Icons.pending_actions_outlined,
                title: 'Pending',
                value:
                _rupees(pending),
                color: pending > 0
                    ? AppColors.error
                    : AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon:
                Icons.account_balance_wallet_outlined,
                title: 'Advance',
                value:
                _rupees(advance),
                color:
                AppColors.darkGreen,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return Container(
      decoration:
      AppTheme.card(radius: 14),
      child: TextField(
        controller:
        _searchController,
        textInputAction:
        TextInputAction.search,
        decoration:
        InputDecoration(
          hintText:
          'Search customer or mobile',
          hintStyle:
          AppTheme.body(size: 12),
          prefixIcon:
          const Icon(
            Icons.search,
            color:
            AppColors.textGrey,
            size: 20,
          ),
          suffixIcon:
          _query.isEmpty
              ? null
              : IconButton(
            onPressed: () {
              _searchController
                  .clear();
            },
            icon:
            const Icon(
              Icons.close,
              color:
              AppColors.textGrey,
              size: 18,
            ),
          ),
          border:
          InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
        ),
        style: AppTheme.body(
          size: 13,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      bool noCustomers,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration:
              const BoxDecoration(
                color:
                AppColors.lightGreen,
                shape: BoxShape.circle,
              ),
              child:
              const Icon(
                Icons.people_outline,
                color:
                AppColors.primaryGreen,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              noCustomers
                  ? 'No customers yet'
                  : 'No customers found',
              style: AppTheme.heading(
                size: 17,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              noCustomers
                  ? 'Add your first Palai customer to start managing their goats and payments.'
                  : 'Try searching with a different name or mobile number.',
              textAlign:
              TextAlign.center,
              style: AppTheme.body(
                size: 12,
              ),
            ),
            if (noCustomers) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed:
                _openAddCustomer,
                icon:
                const Icon(Icons.add),
                label:
                const Text(
                  'Add Customer',
                ),
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,
                  foregroundColor:
                  Colors.white,
                  elevation: 0,
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
      String error,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 44,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load customers',
              style: AppTheme.heading(
                size: 17,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              error,
              textAlign:
              TextAlign.center,
              maxLines: 5,
              overflow:
              TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 11,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loadFarm,
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor:
                Colors.white,
              ),
              child:
              const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  static String _rupees(double value) {
    return '₹${value.toStringAsFixed(0)}';
  }
}

// ============================================================================
// SUMMARY CARD
// ============================================================================

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.all(13),
      decoration:
      AppTheme.card(radius: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration:
            BoxDecoration(
              color:
              color.withOpacity(0.12),
              shape:
              BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
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
                  title,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  AppTheme.body(
                    size: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  AppTheme.heading(
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CUSTOMER CARD
// ============================================================================

class _CustomerCard extends StatelessWidget {
  final PalaiCustomer customer;

  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerCard({
    required this.customer,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasPending =
        customer.pendingAmount > 0;

    final bool hasAdvance =
        customer.advanceAmount > 0;

    final String initial =
    customer.name.isNotEmpty
        ? customer.name[0]
        .toUpperCase()
        : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(16),
        child: Container(
          padding:
          const EdgeInsets.all(14),
          decoration:
          AppTheme.card(radius: 16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration:
                    const BoxDecoration(
                      color:
                      AppColors.lightGreen,
                      shape:
                      BoxShape.circle,
                    ),
                    alignment:
                    Alignment.center,
                    child: Text(
                      initial,
                      style:
                      AppTheme.heading(
                        size: 18,
                        color:
                        AppColors.darkGreen,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style:
                          AppTheme.heading(
                            size: 14,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Row(
                          children: [
                            const Icon(
                              Icons.phone_outlined,
                              size: 13,
                              color:
                              AppColors.textGrey,
                            ),
                            const SizedBox(
                              width: 4,
                            ),
                            Expanded(
                              child: Text(
                                customer
                                    .mobileNumber,
                                maxLines: 1,
                                overflow:
                                TextOverflow
                                    .ellipsis,
                                style:
                                AppTheme.body(
                                  size: 11,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        Row(
                          children: [
                            const Icon(
                              Icons
                                  .calendar_today_outlined,
                              size: 12,
                              color:
                              AppColors.textGrey,
                            ),
                            const SizedBox(
                              width: 4,
                            ),
                            Text(
                              'Joined ${DateFormat('dd MMM yyyy').format(customer.joiningDate)}',
                              style:
                              AppTheme.body(
                                size: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  PopupMenuButton<String>(
                    padding:
                    EdgeInsets.zero,
                    icon:
                    const Icon(
                      Icons.more_vert,
                      color:
                      AppColors.textGrey,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          onTap();
                          break;

                        case 'edit':
                          onEdit();
                          break;

                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder:
                        (context) => const [
                      PopupMenuItem(
                        value: 'view',
                        child:
                        Text('View Profile'),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child:
                        Text('Edit Customer'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child:
                        Text('Delete Customer'),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child:
                    _MoneyBadge(
                      icon: Icons
                          .pending_actions_outlined,
                      label: 'Pending',
                      value:
                      _rupees(
                        customer
                            .pendingAmount,
                      ),
                      color: hasPending
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                    _MoneyBadge(
                      icon: Icons
                          .account_balance_wallet_outlined,
                      label: 'Advance',
                      value:
                      _rupees(
                        customer
                            .advanceAmount,
                      ),
                      color: hasAdvance
                          ? AppColors.darkGreen
                          : AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _rupees(double value) {
    return '₹${value.toStringAsFixed(0)}';
  }
}

// ============================================================================
// MONEY BADGE
// ============================================================================

class _MoneyBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MoneyBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 8,
      ),
      decoration:
      BoxDecoration(
        color:
        color.withOpacity(0.08),
        borderRadius:
        BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                  AppTheme.body(
                    size: 9,
                  ),
                ),
                Text(
                  value,
                  style:
                  AppTheme.body(
                    size: 11,
                    color: color,
                    weight:
                    FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}