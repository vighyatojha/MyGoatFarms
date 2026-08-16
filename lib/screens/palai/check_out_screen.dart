import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/image_source_sheet.dart';
import 'checkout_success_screen.dart';
import 'fullscreen_image_viewer.dart';

/// Check-out page for one specific goat (opened by tapping it in the
/// Palai goat list). Shows the "Before Palai" photo taken at check-in and
/// lets the owner add an "After Palai" photo; both can be tapped to view
/// full-screen. After filling in the final details, "Confirm Check-Out"
/// records the check-out and moves to the success screen.
class CheckOutGoatScreen extends StatefulWidget {
  final PalaiGoat goat;
  const CheckOutGoatScreen({super.key, required this.goat});

  @override
  State<CheckOutGoatScreen> createState() => _CheckOutGoatScreenState();
}

class _CheckOutGoatScreenState extends State<CheckOutGoatScreen> {
  String? _farmId;
  final _finalWeightController = TextEditingController();
  final _totalChargesController = TextEditingController();
  String _healthStatus = 'Healthy';
  String _deliveryStatus = 'Picked up by Owner';
  bool _saving = false;

  // "After Palai" photo, taken/picked at check-out time.
  Uint8List? _afterImageBytes;
  String? _afterImageContentType;

  // What gets printed on the bill (business name, address, UPI, terms,
  // etc.) — customized from Profile > Bill Details. Loaded once so the
  // Checked-Out success/details screens can build the same PDF without
  // each one having to fetch the farm document again.
  BillSettings _billSettings = const BillSettings();

  static const List<String> _healthOptions = ['Healthy', 'Under Observation', 'Sick'];
  static const List<String> _deliveryOptions = ['Picked up by Owner', 'Delivered to Owner', 'Pending Delivery'];

  @override
  void initState() {
    super.initState();
    _finalWeightController.text = (widget.goat.currentWeight ?? widget.goat.weightAtCheckIn).toString();
    FirestoreService.instance.currentFarmId().then((id) async {
      if (!mounted) return;
      setState(() => _farmId = id);
      if (id == null) return;
      final farm = await FirestoreService.instance.getFarmById(id);
      if (mounted && farm != null) setState(() => _billSettings = farm.billSettings);
    });
  }

  @override
  void dispose() {
    _finalWeightController.dispose();
    _totalChargesController.dispose();
    super.dispose();
  }

  Future<void> _pickAfterPhoto() async {
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return; // user cancelled
      setState(() {
        _afterImageBytes = picked.bytes;
        _afterImageContentType = picked.contentType;
      });
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Could not add photo. Please try again.', isError: true);
    }
  }

  void _openFullscreen(Uint8List bytes, String title) {
    Navigator.of(context).push(fastRoute(FullscreenImageViewer(imageBytes: bytes, title: title)));
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.darkGreen),
    );
  }

  Future<void> _save() async {
    if (_farmId == null) return;
    setState(() => _saving = true);

    final finalWeight = double.tryParse(_finalWeightController.text.trim()) ?? widget.goat.weightAtCheckIn;
    final totalCharges = double.tryParse(_totalChargesController.text.trim()) ?? 0;

    await FirestoreService.instance.checkOutGoat(
      _farmId!,
      widget.goat.customerId,
      widget.goat.id,
      finalWeight: finalWeight,
      healthStatus: _healthStatus,
      afterImage: _afterImageBytes,
      afterImageContentType: _afterImageContentType,
    );

    await FirestoreService.instance.logActivity(
      _farmId!,
      ActivityLog(
        id: '',
        type: ActivityType.goatCheckOut,
        title: 'Goat Check-Out',
        subtitle: '${widget.goat.goatCode} · $_deliveryStatus',
        module: 'palai',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.of(context).pushReplacement(fastRoute(CheckoutSuccessScreen(
      goat: widget.goat,
      finalWeight: finalWeight,
      healthStatus: _healthStatus,
      deliveryStatus: _deliveryStatus,
      totalCharges: totalCharges,
      beforeImage: widget.goat.beforeImage,
      afterImage: _afterImageBytes,
      billSettings: _billSettings,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final goat = widget.goat;
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Check-Out · ${goat.goatCode}', style: AppTheme.heading(size: 16)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Palai Photos'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _photoTile(
                          label: 'Before Palai',
                          bytes: goat.beforeImage,
                          onTap: goat.beforeImage != null
                              ? () => _openFullscreen(goat.beforeImage!, 'Before Palai · ${goat.goatCode}')
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _photoTile(
                          label: 'After Palai',
                          bytes: _afterImageBytes,
                          onTap: _afterImageBytes != null
                              ? () => _openFullscreen(_afterImageBytes!, 'After Palai · ${goat.goatCode}')
                              : null,
                          onAdd: _pickAfterPhoto,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _label('Final Weight (kg)'),
                  _textField(_finalWeightController, hint: 'e.g. 40', keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  _label('Health Status'),
                  _dropdown(_healthStatus, _healthOptions, (v) => setState(() => _healthStatus = v)),
                  const SizedBox(height: 16),
                  _label('Total Charges (₹)'),
                  _textField(_totalChargesController, hint: 'e.g. 4500', keyboardType: TextInputType.number, optional: true),
                  const SizedBox(height: 16),
                  _label('Delivery Status'),
                  _dropdown(_deliveryStatus, _deliveryOptions, (v) => setState(() => _deliveryStatus = v)),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm Check-Out', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// A single Before/After photo box. Tapping a filled photo opens it
  /// full-screen ([onTap]); tapping an empty "After Palai" box (or its
  /// "+ Add Photo" label, [onAdd]) opens the camera/gallery picker.
  Widget _photoTile({
    required String label,
    Uint8List? bytes,
    VoidCallback? onTap,
    VoidCallback? onAdd,
  }) {
    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(label, style: AppTheme.body(size: 12, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: bytes != null ? onTap : onAdd,
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: bytes != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(bytes, fit: BoxFit.cover))
                  : Icon(onAdd != null ? Icons.add_a_photo_outlined : Icons.pets, color: AppColors.primaryGreen, size: 30),
            ),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: onAdd,
              child: Text(
                bytes == null ? '+ Add Photo' : 'Change Photo',
                style: AppTheme.body(size: 11, color: AppColors.primaryGreen, weight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTheme.heading(size: 13)),
      );

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: AppTheme.body(size: 13, color: AppColors.textDark)))).toList(),
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    bool optional = false,
  }) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
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
