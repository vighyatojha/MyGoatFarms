import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Records medicine used (e.g. given to a goat), deducting it from the
/// matching medicine stock item. Mirrors [FeedUsedScreen] for medicine.
class MedicineUsedScreen extends StatefulWidget {
  const MedicineUsedScreen({super.key});

  @override
  State<MedicineUsedScreen> createState() => _MedicineUsedScreenState();
}

class _MedicineUsedScreenState extends State<MedicineUsedScreen> {
  String? _farmId;
  StockItem? _selectedItem;
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedItem == null || _farmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a medicine'), backgroundColor: AppColors.error),
      );
      return;
    }
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);

    await FirestoreService.instance.useStock(
      _farmId!,
      itemId: _selectedItem!.id,
      itemName: _selectedItem!.name,
      quantity: quantity,
      unit: _selectedItem!.unit,
      notes: _notesController.text.trim(),
    );

    await FirestoreService.instance.logActivity(
      _farmId!,
      ActivityLog(
        id: '',
        type: ActivityType.medicineUsed,
        title: 'Medicine Used',
        subtitle: '${quantity.toStringAsFixed(0)} ${_selectedItem!.unit} of ${_selectedItem!.name} used'
            '${_notesController.text.trim().isEmpty ? '' : ' — ${_notesController.text.trim()}'}',
        module: 'stock',
        timestamp: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medicine usage recorded'), backgroundColor: AppColors.primaryGreen),
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
        title: Text('Medicine Used', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Select Medicine'),
                  StreamBuilder<List<StockItem>>(
                    stream: FirestoreService.instance.stockItemsStream(_farmId!, type: StockType.medicine),
                    builder: (context, snap) {
                      final items = snap.data ?? [];
                      if (snap.hasData && items.isEmpty) {
                        return Text('No medicine stock yet — add some first.', style: AppTheme.body(size: 12));
                      }
                      // If the previously selected item was deleted or its
                      // reference is now stale, drop the selection instead
                      // of pointing the dropdown at a value it can't find.
                      final selected = items.any((i) => i.id == _selectedItem?.id) ? _selectedItem : null;
                      return Container(
                        decoration: AppTheme.card(radius: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<StockItem>(
                            value: selected,
                            isExpanded: true,
                            hint: Text('Choose medicine', style: AppTheme.body(size: 13)),
                            items: items
                                .map((i) => DropdownMenuItem(
                                    value: i,
                                    child: Text('${i.name} (${i.quantity.toStringAsFixed(0)} ${i.unit} left)',
                                        style: AppTheme.body(size: 13, color: AppColors.textDark))))
                                .toList(),
                            onChanged: (v) => setState(() => _selectedItem = v),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _label('Quantity Used (${_selectedItem?.unit ?? 'unit'})'),
                  _field(_quantityController, hint: 'e.g. 2', keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  _label('Notes'),
                  _field(_notesController, hint: 'e.g. Given to Goat G-1004 for deworming', maxLines: 2, optional: true),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.breedingPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Record Usage', style: TextStyle(fontWeight: FontWeight.w600)),
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
    bool optional = false,
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
