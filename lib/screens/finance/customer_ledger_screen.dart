import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import 'customer_ledger_detail_screen.dart';

class CustomerLedgerScreen extends StatefulWidget {
  const CustomerLedgerScreen({super.key});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final id = await FirestoreService.instance.currentFarmId();
    if (!mounted) return;
    setState(() {
      _farmId = id;
      _loadingFarm = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PalaiCustomer> _filter(List<PalaiCustomer> customers) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return customers;
    return customers.where((c) {
      return c.name.toLowerCase().contains(query) ||
          c.mobileNumber.toLowerCase().contains(query) ||
          c.id.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text('Customer Ledger', style: AppTheme.heading(size: 18)),
      ),
      body: SafeArea(
        child: _loadingFarm
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _farmId == null
                ? FarmNotLinkedState(
                    buttonColor: AppColors.primaryGreen,
                    onRetry: () {
                      setState(() => _loadingFarm = true);
                      _loadFarm();
                    },
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _search = v),
                          style: AppTheme.body(size: 13),
                          decoration: InputDecoration(
                            hintText: 'Search name or mobile number...',
                            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textGrey),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                              borderSide: BorderSide(color: AppColors.divider),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: StreamBuilder<List<PalaiCustomer>>(
                          stream: FirestoreService.instance.customersStream(_farmId!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(color: AppColors.primaryGreen),
                              );
                            }
                            final customers = _filter(snapshot.data!);
                            if (customers.isEmpty) {
                              return Center(
                                child: Text('No customers found.', style: AppTheme.body(size: 13)),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: customers.length,
                              itemBuilder: (context, index) => _customerCard(customers[index]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _customerCard(PalaiCustomer customer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            fastRoute(CustomerLedgerDetailScreen(customer: customer)),
          );
        },
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.lightGreen,
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: AppTheme.body(size: 15, color: AppColors.darkGreen, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w700),
                  ),
                  Text(customer.mobileNumber, style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Outstanding: ₹${customer.pendingAmount.toStringAsFixed(0)}',
                  style: AppTheme.body(
                    size: 11,
                    color: customer.pendingAmount > 0 ? AppColors.error : AppColors.textGrey,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Advance: ₹${customer.advanceAmount.toStringAsFixed(0)}',
                  style: AppTheme.body(
                    size: 11,
                    color: customer.advanceAmount > 0 ? AppColors.info : AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
