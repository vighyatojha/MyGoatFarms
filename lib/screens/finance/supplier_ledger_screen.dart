import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/supplier_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/farm_not_linked_state.dart';
import 'supplier_ledger_detail_screen.dart';

/// Lists every supplier the farm has recorded, each with their current
/// pending (owed by the farm) / advance (paid in excess) balance.
///
/// Mirrors [CustomerLedgerScreen] in layout and behaviour, but for money
/// flowing the other way: here "Outstanding" means what the FARM owes
/// the supplier, not what a customer owes the farm.
class SupplierLedgerScreen extends StatefulWidget {
  const SupplierLedgerScreen({super.key});

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
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

  List<SupplierModel> _filter(List<SupplierModel> suppliers) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return suppliers;
    return suppliers.where((s) {
      return s.name.toLowerCase().contains(query) ||
          s.mobileNumber.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addSupplier() async {
    final farmId = _farmId;
    if (farmId == null) return;

    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: _AddSupplierSheet(
            farmId: farmId,
            nameController: nameController,
            mobileController: mobileController,
            addressController: addressController,
          ),
        );
      },
    );

    // Controllers are only used for this single sheet — safe to dispose
    // after the sheet's exit transition (see the note on the identical
    // pattern in add_feed_stock_screen.dart's _promptNewFeedName).
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier added'),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    }
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
        title: Text('Supplier Ledger', style: AppTheme.heading(size: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'Add Supplier',
            onPressed: _loadingFarm || _farmId == null ? null : _addSupplier,
          ),
        ],
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
                  hintText: 'Search supplier name or mobile...',
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
              child: StreamBuilder<List<SupplierModel>>(
                stream: FirestoreService.instance.suppliersStream(_farmId!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryGreen),
                    );
                  }
                  final suppliers = _filter(snapshot.data!);
                  if (suppliers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_shipping_outlined, color: AppColors.textGrey, size: 30),
                          const SizedBox(height: 9),
                          Text(
                            snapshot.data!.isEmpty ? 'No suppliers added yet.' : 'No suppliers found.',
                            style: AppTheme.body(size: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: suppliers.length,
                    itemBuilder: (context, index) => _supplierCard(suppliers[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplierCard(SupplierModel supplier) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            fastRoute(SupplierLedgerDetailScreen(supplier: supplier)),
          );
        },
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.lightGreen,
              child: Text(
                supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                style: AppTheme.body(size: 15, color: AppColors.darkGreen, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier.name,
                    style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w700),
                  ),
                  if (supplier.mobileNumber.isNotEmpty)
                    Text(supplier.mobileNumber, style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'You owe: ₹${supplier.pendingAmount.toStringAsFixed(0)}',
                  style: AppTheme.body(
                    size: 11,
                    color: supplier.pendingAmount > 0 ? AppColors.error : AppColors.textGrey,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Advance: ₹${supplier.advanceAmount.toStringAsFixed(0)}',
                  style: AppTheme.body(
                    size: 11,
                    color: supplier.advanceAmount > 0 ? AppColors.info : AppColors.textGrey,
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

class _AddSupplierSheet extends StatefulWidget {
  final String farmId;
  final TextEditingController nameController;
  final TextEditingController mobileController;
  final TextEditingController addressController;

  const _AddSupplierSheet({
    required this.farmId,
    required this.nameController,
    required this.mobileController,
    required this.addressController,
  });

  @override
  State<_AddSupplierSheet> createState() => _AddSupplierSheetState();
}

class _AddSupplierSheetState extends State<_AddSupplierSheet> {
  bool _saving = false;

  Future<void> _save() async {
    final name = widget.nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier name is required.'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await FirestoreService.instance.addSupplier(
        widget.farmId,
        name: name,
        mobileNumber: widget.mobileController.text.trim(),
        address: widget.addressController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Text('Add Supplier', style: AppTheme.heading(size: 17)),
          const SizedBox(height: 16),
          TextField(
            controller: widget.nameController,
            style: AppTheme.body(size: 13, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Supplier / Vendor name',
              prefixIcon: const Icon(Icons.storefront_outlined, color: AppColors.primaryGreen),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.mobileController,
            keyboardType: TextInputType.phone,
            style: AppTheme.body(size: 13, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Mobile number (optional)',
              prefixIcon: const Icon(Icons.call_outlined, color: AppColors.primaryGreen),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.addressController,
            style: AppTheme.body(size: 13, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: 'Address (optional)',
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.primaryGreen),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Save Supplier'),
            ),
          ),
        ],
      ),
    );
  }
}