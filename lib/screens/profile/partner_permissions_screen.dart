import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';

class PartnerPermissionsScreen extends StatefulWidget {
  final String farmId;
  final String partnerId;

  const PartnerPermissionsScreen({
    super.key,
    required this.farmId,
    required this.partnerId,
  });

  @override
  State<PartnerPermissionsScreen> createState() =>
      _PartnerPermissionsScreenState();
}

class _PartnerPermissionsScreenState
    extends State<PartnerPermissionsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _palai = true;
  bool _customers = true;
  bool _stocks = false;
  bool _reports = false;

  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _permissionRef =>
      _db
          .collection('farms')
          .doc(widget.farmId)
          .collection('partners')
          .doc(widget.partnerId)
          .collection('settings')
          .doc('permissions');

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final snapshot = await _permissionRef.get();

      if (snapshot.exists) {
        final data = snapshot.data() ?? {};

        if (mounted) {
          setState(() {
            _palai = data['palai'] ?? true;
            _customers = data['customers'] ?? true;
            _stocks = data['stocks'] ?? false;
            _reports = data['reports'] ?? false;
          });
        }
      }
    } catch (_) {
      // Use defaults if permissions don't exist yet.
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _savePermissions() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      await _permissionRef.set({
        'palai': _palai,
        'customers': _customers,
        'stocks': _stocks,
        'reports': _reports,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Partner permissions saved.'),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save permissions: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
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

  Widget _permissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.card(radius: 16),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primaryGreen,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: AppColors.primaryGreen,
          ),
        ),
        title: Text(
          title,
          style: AppTheme.body(
            size: 14,
            color: AppColors.textDark,
            weight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTheme.body(size: 11),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          title: const Text('Partner Permissions'),
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Partner Permissions'),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure Access',
                style: AppTheme.heading(
                  size: 20,
                  color: AppColors.darkGreen,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Choose which areas of the farm application this partner can access.',
                style: AppTheme.body(size: 12),
              ),

              const SizedBox(height: 20),

              _permissionTile(
                title: 'Palai',
                subtitle: 'Manage goat boarding and Palai records',
                icon: Icons.pets_outlined,
                value: _palai,
                onChanged: (value) {
                  setState(() => _palai = value);
                },
              ),

              _permissionTile(
                title: 'Customers',
                subtitle: 'View and manage customer information',
                icon: Icons.people_outline,
                value: _customers,
                onChanged: (value) {
                  setState(() => _customers = value);
                },
              ),

              _permissionTile(
                title: 'Stocks',
                subtitle: 'View and manage farm stock',
                icon: Icons.inventory_2_outlined,
                value: _stocks,
                onChanged: (value) {
                  setState(() => _stocks = value);
                },
              ),

              _permissionTile(
                title: 'Reports',
                subtitle: 'View generated farm reports',
                icon: Icons.assessment_outlined,
                value: _reports,
                onChanged: (value) {
                  setState(() => _reports = value);
                },
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _savePermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                      : const Text(
                    'Save Permissions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}