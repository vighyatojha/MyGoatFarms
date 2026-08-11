import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Records a goat check-out: final weight, health status, total/pending
/// charges and delivery status — per the Palai spec.
class CheckOutGoatScreen extends StatefulWidget {
  const CheckOutGoatScreen({super.key});

  @override
  State<CheckOutGoatScreen> createState() => _CheckOutGoatScreenState();
}

class _CheckOutGoatScreenState extends State<CheckOutGoatScreen> {
  String? _farmId;
  PalaiGoat? _selectedGoat;
  final _finalWeightController = TextEditingController();
  final _totalChargesController = TextEditingController();
  String _healthStatus = 'Healthy';
  String _deliveryStatus = 'Picked up by Owner';
  bool _saving = false;

  static const List<String> _healthOptions = ['Healthy', 'Under Observation', 'Sick'];
  static const List<String> _deliveryOptions = ['Picked up by Owner', 'Delivered to Owner', 'Pending Delivery'];

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  void dispose() {
    _finalWeightController.dispose();
    _totalChargesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedGoat == null || _farmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a goat to check out'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _saving = true);

    final finalWeight = double.tryParse(_finalWeightController.text.trim()) ?? _selectedGoat!.weightAtCheckIn;

    await FirestoreService.instance.checkOutGoat(
      _farmId!,
      _selectedGoat!.customerId,
      _selectedGoat!.id,
      finalWeight: finalWeight,
      healthStatus: _healthStatus,
    );

    await FirestoreService.instance.logActivity(
      _farmId!,
      ActivityLog(
        id: '',
        type: ActivityType.goatCheckOut,
        title: 'Goat Check-Out',
        subtitle: '${_selectedGoat!.goatCode} · $_deliveryStatus',
        module: 'palai',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Goat checked out successfully'), backgroundColor: AppColors.primaryGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Goat Check-Out', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Select Goat'),
                  StreamBuilder<List<PalaiGoat>>(
                    stream: FirestoreService.instance.allActiveGoatsStream(_farmId!),
                    builder: (context, snap) {
                      final goats = snap.data ?? [];
                      if (snap.hasData && goats.isEmpty) {
                        return Text('No active goats to check out.', style: AppTheme.body(size: 12));
                      }
                      return Container(
                        decoration: AppTheme.card(radius: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PalaiGoat>(
                            value: _selectedGoat,
                            isExpanded: true,
                            hint: Text('Choose a goat', style: AppTheme.body(size: 13)),
                            items: goats
                                .map((g) => DropdownMenuItem(value: g, child: Text('${g.goatCode} · ${g.breed}', style: AppTheme.body(size: 13, color: AppColors.textDark))))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _selectedGoat = v;
                              _finalWeightController.text = (v?.currentWeight ?? v?.weightAtCheckIn ?? 0).toString();
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
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
