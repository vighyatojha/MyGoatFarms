import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/partner_model.dart';
import '../services/firestore_service.dart';

/// Lets the farm owner choose what a pending partner can do, then calls
/// [FirestoreService.approvePartner]. This is the other half of
/// [FirestoreService.addPartner]/[AddPartnerSheet] (in add_partner_sheet.dart):
/// that flow creates the partner doc with `status: 'pending'` and
/// `PartnerPermissions.none()`; nothing previously called `approvePartner`
/// anywhere in the app, so a partner created that way had no way to ever
/// become usable. This sheet is that missing "other end."
///
/// Returns `true` via [Navigator.pop] if the partner was approved.
class PartnerApprovalSheet extends StatefulWidget {
  final String farmId;
  final PartnerModel partner;

  const PartnerApprovalSheet({
    super.key,
    required this.farmId,
    required this.partner,
  });

  @override
  State<PartnerApprovalSheet> createState() => _PartnerApprovalSheetState();
}

class _PermissionToggle {
  final String key;
  final String label;
  bool value;

  _PermissionToggle(this.key, this.label, {this.value = false});
}

class _PermissionGroup {
  final String title;
  final IconData icon;
  final List<_PermissionToggle> toggles;

  _PermissionGroup(this.title, this.icon, this.toggles);
}

class _PartnerApprovalSheetState extends State<PartnerApprovalSheet> {
  bool _saving = false;

  late final List<_PermissionGroup> _groups = [
    _PermissionGroup('Palai', Icons.storefront_outlined, [
      _PermissionToggle('palaiView', 'View'),
      _PermissionToggle('palaiCreate', 'Create'),
      _PermissionToggle('palaiUpdate', 'Update'),
      _PermissionToggle('palaiDelete', 'Delete'),
    ]),
    _PermissionGroup('Customers', Icons.people_outline, [
      _PermissionToggle('customersView', 'View'),
      _PermissionToggle('customersCreate', 'Create'),
      _PermissionToggle('customersUpdate', 'Update'),
      _PermissionToggle('customersDelete', 'Delete'),
    ]),
    _PermissionGroup('Stock', Icons.inventory_2_outlined, [
      _PermissionToggle('stockView', 'View'),
      _PermissionToggle('stockCreate', 'Create'),
      _PermissionToggle('stockUpdate', 'Update'),
      _PermissionToggle('stockDelete', 'Delete'),
    ]),
    _PermissionGroup('Finance', Icons.account_balance_wallet_outlined, [
      _PermissionToggle('financeView', 'View'),
      _PermissionToggle('financeExpenseCreate', 'Create expenses'),
      _PermissionToggle('financeExpenseEdit', 'Edit expenses'),
      _PermissionToggle('financeExpenseVoid', 'Void expenses'),
      _PermissionToggle('financeRevenueCreate', 'Create revenue'),
      _PermissionToggle('financeRevenueEdit', 'Edit revenue'),
      _PermissionToggle('financeRevenueVoid', 'Void revenue'),
      _PermissionToggle('financeLedgerView', 'View ledger'),
      _PermissionToggle('financeReportsView', 'View finance reports'),
    ]),
    _PermissionGroup('Trading', Icons.swap_horiz_outlined, [
      _PermissionToggle('tradingView', 'View'),
      _PermissionToggle('tradingPurchaseCreate', 'Create purchases'),
    ]),
    _PermissionGroup('General', Icons.tune_outlined, [
      _PermissionToggle('reportsView', 'View reports'),
      _PermissionToggle('profileView', 'View farm profile'),
    ]),
  ];

  bool _flag(String key) {
    for (final group in _groups) {
      for (final toggle in group.toggles) {
        if (toggle.key == key) return toggle.value;
      }
    }
    return false;
  }

  PartnerPermissions _buildPermissions() {
    return PartnerPermissions(
      palaiView: _flag('palaiView'),
      palaiCreate: _flag('palaiCreate'),
      palaiUpdate: _flag('palaiUpdate'),
      palaiDelete: _flag('palaiDelete'),
      customersView: _flag('customersView'),
      customersCreate: _flag('customersCreate'),
      customersUpdate: _flag('customersUpdate'),
      customersDelete: _flag('customersDelete'),
      stockView: _flag('stockView'),
      stockCreate: _flag('stockCreate'),
      stockUpdate: _flag('stockUpdate'),
      stockDelete: _flag('stockDelete'),
      reportsView: _flag('reportsView'),
      profileView: _flag('profileView'),
      financeView: _flag('financeView'),
      financeExpenseCreate: _flag('financeExpenseCreate'),
      financeExpenseEdit: _flag('financeExpenseEdit'),
      financeExpenseVoid: _flag('financeExpenseVoid'),
      financeRevenueCreate: _flag('financeRevenueCreate'),
      financeRevenueEdit: _flag('financeRevenueEdit'),
      financeRevenueVoid: _flag('financeRevenueVoid'),
      financeLedgerView: _flag('financeLedgerView'),
      financeReportsView: _flag('financeReportsView'),
      tradingView: _flag('tradingView'),
      tradingPurchaseCreate: _flag('tradingPurchaseCreate'),
    );
  }

  Future<void> _approve() async {
    if (_saving) return;

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;

    setState(() => _saving = true);

    try {
      await FirestoreService.instance.approvePartner(
        farmId: widget.farmId,
        partnerId: widget.partner.id,
        adminUid: adminUid,
        permissions: _buildPermissions(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.partner.name.trim().isEmpty ? 'Partner' : widget.partner.name.trim()} approved.',
          ),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FirestoreService.instance.describeError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.partner.name.trim().isEmpty
        ? 'this partner'
        : widget.partner.name.trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approve $name',
                      style: AppTheme.heading(size: 19),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose what this partner can view and change. '
                          'You can adjust this later from their profile.',
                      style: AppTheme.body(size: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  children: [
                    for (final group in _groups) _buildGroup(group),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Approve Partner',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroup(_PermissionGroup group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Icon(group.icon, size: 17, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  group.title,
                  style: AppTheme.heading(size: 13, color: AppColors.darkGreen),
                ),
              ],
            ),
          ),
          for (final toggle in group.toggles)
            SwitchListTile.adaptive(
              dense: true,
              activeColor: AppColors.primaryGreen,
              title: Text(
                toggle.label,
                style: AppTheme.body(size: 12),
              ),
              value: toggle.value,
              onChanged: (v) => setState(() => toggle.value = v),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}