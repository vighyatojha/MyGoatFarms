import 'dart:async';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/activity_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../palai/add_customer_screen.dart';

/// Customer management: the "Customers" bottom-nav tab.
///
/// Lists every Palai customer with search, and lets the user Create,
/// Read, Update and Delete customer records:
///  - Create: the "+" button opens [AddCustomerScreen] in add mode.
///  - Read: this list, plus a summary of total customers & total pending.
///  - Update: tapping a card, or "Edit" in its menu, opens the same form
///    pre-filled for that customer.
///  - Delete: "Delete" in the card's menu, with a confirmation dialog
///    (blocked if the customer still has goats checked into Palai).
class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  String? _farmId;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PalaiCustomer> _filtered(List<PalaiCustomer> customers) {
    if (_query.isEmpty) return customers;
    return customers
        .where((c) => c.name.toLowerCase().contains(_query) || c.mobileNumber.toLowerCase().contains(_query))
        .toList();
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(fastRoute(const AddCustomerScreen()));
  }

  Future<void> _openEdit(PalaiCustomer customer) async {
    await Navigator.of(context).push(fastRoute(AddCustomerScreen(customer: customer)));
  }

  Future<void> _confirmDelete(PalaiCustomer customer) async {
    final farmId = _farmId;
    if (farmId == null) return;

    final hasActiveGoats = await FirestoreService.instance.customerHasActiveGoats(farmId, customer.id);
    if (!mounted) return;
    if (hasActiveGoats) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Cannot delete ${customer.name}', style: AppTheme.heading(size: 16)),
          content: Text(
            'This customer still has goats checked into Palai. Check out all of their goats before deleting the customer.',
            style: AppTheme.body(size: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w600)),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${customer.name}?', style: AppTheme.heading(size: 16)),
        content: Text(
          'This permanently removes the customer and their Palai history. This cannot be undone.',
          style: AppTheme.body(size: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: AppTheme.body(size: 13, color: AppColors.textGrey))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: AppTheme.body(size: 13, color: AppColors.error, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirestoreService.instance.deleteCustomer(farmId, customer.id);
      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.customerDeleted,
          title: 'Customer Deleted',
          subtitle: '${customer.name} removed from Palai',
          module: 'palai',
          timestamp: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${customer.name} deleted'), backgroundColor: AppColors.darkGreen),
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is taking too long. Check your connection and try again.'), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: _farmId == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: FadeInDown(duration: const Duration(milliseconds: 180), child: _buildHeader()),
                  ),
                  Expanded(
                    child: StreamBuilder<List<PalaiCustomer>>(
                      stream: FirestoreService.instance.customersStream(_farmId!),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                        }
                        final all = snap.data!;
                        final customers = _filtered(all);
                        return CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                                child: FadeInUp(
                                  delay: const Duration(milliseconds: 40),
                                  duration: const Duration(milliseconds: 200),
                                  child: _buildSummary(all),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                                child: _buildSearch(),
                              ),
                            ),
                            if (customers.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      all.isEmpty ? 'No customers yet. Tap "Add Customer" to create one.' : 'No customers match "${_searchController.text}".',
                                      textAlign: TextAlign.center,
                                      style: AppTheme.body(size: 13),
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                sliver: SliverList.separated(
                                  itemCount: customers.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final customer = customers[i];
                                    return FadeInUp(
                                      delay: Duration(milliseconds: 20 * i.clamp(0, 8).toInt()),
                                      duration: const Duration(milliseconds: 200),
                                      child: _CustomerCard(
                                        customer: customer,
                                        onTap: () => _openEdit(customer),
                                        onEdit: () => _openEdit(customer),
                                        onDelete: () => _confirmDelete(customer),
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
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
          child: const Icon(Icons.people, color: AppColors.primaryGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customers', style: AppTheme.heading(size: 17)),
              Text('Manage Palai customers', style: AppTheme.body(size: 12)),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _openAdd,
          icon: const Icon(Icons.person_add_alt, size: 16),
          label: const Text('Add Customer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(List<PalaiCustomer> customers) {
    final totalPending = customers.fold<double>(0, (t, c) => t + c.pendingAmount);
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: Icons.people_outline,
            label: 'Total Customers',
            value: '${customers.length}',
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            icon: Icons.credit_card_outlined,
            label: 'Total Pending',
            value: '₹${totalPending.toStringAsFixed(0)}',
            color: totalPending > 0 ? AppColors.error : AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(value, style: AppTheme.heading(size: 18)),
          Text(label, style: AppTheme.body(size: 11)),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by name or mobile number',
          hintStyle: AppTheme.body(size: 12),
          prefixIcon: const Icon(Icons.search, color: AppColors.textGrey, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textGrey, size: 18),
                  onPressed: () => _searchController.clear(),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
    );
  }
}

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
    final hasPending = customer.pendingAmount > 0;
    final initial = customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: AppTheme.card(radius: 14),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(initial, style: AppTheme.heading(size: 17, color: AppColors.darkGreen)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: AppTheme.heading(size: 14)),
                    const SizedBox(height: 3),
                    Text(customer.mobileNumber, style: AppTheme.body(size: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(8)),
                          child: Text(customer.package, style: AppTheme.body(size: 10, color: AppColors.darkGreen, weight: FontWeight.w600)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (hasPending ? AppColors.error : AppColors.success).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            hasPending ? 'Pending ₹${customer.pendingAmount.toStringAsFixed(0)}' : 'No dues',
                            style: AppTheme.body(size: 10, color: hasPending ? AppColors.error : AppColors.success, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Joined ${DateFormat('dd MMM yyyy').format(customer.joiningDate)}', style: AppTheme.body(size: 10)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textGrey),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
