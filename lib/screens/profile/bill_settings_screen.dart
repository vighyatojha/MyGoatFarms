import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../services/firestore_service.dart';

/// Lets the farm owner customize what appears on the Palai check-out
/// bill: business name, tagline, address, phone, UPI payment info, a
/// thank-you footer note, and optional terms & conditions.
///
/// Reached from Profile > Bill Details > Edit Bill Details.
class BillSettingsScreen extends StatefulWidget {
  final String farmId;
  final BillSettings initialSettings;



  const BillSettingsScreen({
    super.key,
    required this.farmId,
    required this.initialSettings,
  });

  @override
  State<BillSettingsScreen> createState() => _BillSettingsScreenState();
}

class _BillSettingsScreenState extends State<BillSettingsScreen> {
  late final TextEditingController _businessNameController;
  late final TextEditingController _taglineController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _upiController;
  late final TextEditingController _footerController;
  late final TextEditingController _termsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _businessNameController = TextEditingController(text: s.businessName);
    _taglineController = TextEditingController(text: s.tagline);
    _addressController = TextEditingController(text: s.address);
    _phoneController = TextEditingController(text: s.phone);
    _upiController = TextEditingController(text: s.upiId);
    _footerController = TextEditingController(text: s.footerNote);
    _termsController = TextEditingController(text: s.terms);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _taglineController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _upiController.dispose();
    _footerController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final settings = BillSettings(
      businessName: _businessNameController.text.trim().isEmpty
          ? 'My Goat Farms'
          : _businessNameController.text.trim(),
      tagline: _taglineController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      upiId: _upiController.text.trim(),
      footerNote: _footerController.text.trim().isEmpty
          ? 'Thank you for trusting us with your goat.'
          : _footerController.text.trim(),
      terms: _termsController.text.trim(),
    );

    try {
      await FirestoreService.instance.updateBillSettings(widget.farmId, settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill details updated'), backgroundColor: AppColors.primaryGreen),
      );
      Navigator.of(context).pop(settings);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirestoreService.instance.describeError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
        title: Text('Bill Details', style: AppTheme.heading(size: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These details are printed on every Palai check-out bill (PDF) — the one shared or downloaded after a goat is checked out.',
              style: AppTheme.body(size: 12),
            ),
            const SizedBox(height: 22),
            _label('Business Name on Bill'),
            _field(_businessNameController, hint: 'e.g. My Goat Farms'),
            const SizedBox(height: 16),
            _label('Tagline (optional)'),
            _field(_taglineController, hint: 'e.g. Palai - Goat Boarding & Care'),
            const SizedBox(height: 16),
            _label('Address on Bill'),
            _field(_addressController, hint: 'Farm address shown on the bill', maxLines: 2),
            const SizedBox(height: 16),
            _label('Phone on Bill'),
            _field(_phoneController, hint: 'e.g. +91 90000 00000', keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            _label('UPI ID / Payment Info (optional)'),
            _field(_upiController, hint: 'e.g. mygoatfarms@upi'),
            const SizedBox(height: 16),
            _label('Thank-You Note'),
            _field(_footerController, hint: 'Shown at the bottom of the bill', maxLines: 2),
            const SizedBox(height: 16),
            _label('Terms & Conditions (optional)'),
            _field(_termsController, hint: 'Printed below the bill total, if filled in', maxLines: 4),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Bill Details', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTheme.heading(size: 13)),
      );

  Widget _field(
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.body(size: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
    );
  }
}
