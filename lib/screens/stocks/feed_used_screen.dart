import 'dart:async';

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

/// Records feed consumed today, deducting it from the matching stock item.
class FeedUsedScreen extends StatefulWidget {
  const FeedUsedScreen({super.key});

  @override
  State<FeedUsedScreen> createState() => _FeedUsedScreenState();
}

class _FeedUsedScreenState extends State<FeedUsedScreen> {
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
        const SnackBar(content: Text('Please select a feed item'), backgroundColor: AppColors.error),
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

    try {
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
          type: ActivityType.feedUsed,
          title: 'Feed Used Today',
          subtitle: '${quantity.toStringAsFixed(0)} ${_selectedItem!.unit} of ${_selectedItem!.name} used'
              '${_notesController.text.trim().isEmpty ? '' : ' — ${_notesController.text.trim()}'}',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feed usage recorded'), backgroundColor: AppColors.primaryGreen),
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
        title: Text('Feed Used Today', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Select Feed Item'),
            StreamBuilder<List<StockItem>>(
              stream: FirestoreService.instance.stockItemsStream(_farmId!, type: StockType.feed),
              builder: (context, snap) {
                final items = snap.data ?? [];
                if (snap.hasData && items.isEmpty) {
                  return Text('No feed stock yet — add some first.', style: AppTheme.body(size: 12));
                }
                // Re-resolve the selection against the CURRENT items list
                // rather than reusing the old StockItem instance — each
                // stream snapshot rebuilds fresh objects, so pointing the
                // dropdown's value at a stale instance (even one with a
                // matching id) trips DropdownButton's "exactly one item
                // with this value" assertion. If the item was deleted,
                // drop the selection instead of pointing at a value that
                // can't be found.
                StockItem? selected;
                for (final i in items) {
                  if (i.id == _selectedItem?.id) {
                    selected = i;
                    break;
                  }
                }
                return Container(
                  decoration: AppTheme.card(radius: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<StockItem>(
                      value: selected,
                      isExpanded: true,
                      hint: Text('Choose feed item', style: AppTheme.body(size: 13)),
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
            _label('Quantity Used (${_selectedItem?.unit ?? 'kg'})'),
            _field(_quantityController, hint: 'e.g. 15', keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _label('Notes'),
            _field(_notesController, hint: 'Optional', maxLines: 2, optional: true),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
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