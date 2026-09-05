import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';

// Medicine screens use a blue theme (AppColors.info) instead of the app's
// default green, matching the medicine card color on the Stock screen.
// There's no separate "dark blue" in AppColors, so this derives one at
// runtime for the hero gradient/shadow.
final Color _medicineBlueDark = Color.lerp(AppColors.info, Colors.black, 0.15)!;

class MedicineUsedScreen extends StatefulWidget {
  const MedicineUsedScreen({super.key});

  @override
  State<MedicineUsedScreen> createState() => _MedicineUsedScreenState();
}

class _MedicineUsedScreenState extends State<MedicineUsedScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  StockItem? _selectedItem;
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  void _loadFarm() {
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() {
        _farmId = id;
        _loadingFarm = false;
      });
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : AppColors.info,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _save() async {
    final item = _selectedItem;
    final farmId = _farmId;

    if (item == null || farmId == null) {
      _message('Select a medicine first.', error: true);
      return;
    }

    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;

    if (quantity <= 0) {
      _message('Enter a valid quantity.', error: true);
      return;
    }

    if (quantity > item.quantity) {
      _message('Only ${item.quantity.toStringAsFixed(0)} ${item.unit} is available.', error: true);
      return;
    }

    final confirmed = await _confirmUsage(item, quantity);
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);

    try {
      await FirestoreService.instance.useStock(
        farmId,
        itemId: item.id,
        itemName: item.name,
        quantity: quantity,
        unit: item.unit,
        notes: _notesController.text.trim(),
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.medicineUsed,
          title: 'Medicine Used',
          subtitle: '${quantity.toStringAsFixed(0)} ${item.unit} of ${item.name} used'
              '${_notesController.text.trim().isEmpty ? '' : ' — ${_notesController.text.trim()}'}',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Medicine usage recorded');
    } on TimeoutException {
      _message('Connection is taking too long. Please try again.', error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmUsage(StockItem item, double quantity) async {
    final remaining = item.quantity - quantity;

    return await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 18),
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.info.withOpacity(.10),
                  child: const Icon(Icons.medication_outlined, color: AppColors.info, size: 28),
                ),
                const SizedBox(height: 12),
                Text('Confirm medicine usage', style: AppTheme.heading(size: 17)),
                const SizedBox(height: 5),
                Text(
                  '${quantity.toStringAsFixed(0)} ${item.unit} will be deducted from ${item.name}.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 12),
                ),
                const SizedBox(height: 16),
                _summaryRow('Current stock', '${item.quantity.toStringAsFixed(0)} ${item.unit}'),
                _summaryRow('Used now', '${quantity.toStringAsFixed(0)} ${item.unit}'),
                _summaryRow('Remaining', '${remaining.toStringAsFixed(0)} ${item.unit}', highlight: true),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ) ??
        false;
  }

  Widget _summaryRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.body(size: 12))),
          Text(
            value,
            style: AppTheme.body(
              size: 12,
              color: highlight ? AppColors.info : AppColors.textDark,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotLinkedState() {
    return FarmNotLinkedState(
      buttonColor: AppColors.info,
      onRetry: () {
        setState(() => _loadingFarm = true);
        _loadFarm();
      },
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
        titleSpacing: 4,
        title: Text('Medicine Used', style: AppTheme.heading(size: 18)),
      ),
      body: _loadingFarm
          ? const Center(child: CircularProgressIndicator(color: AppColors.info))
          : _farmId == null
          ? _buildNotLinkedState()
          : StreamBuilder<List<StockItem>>(
        stream: FirestoreService.instance.stockItemsStream(_farmId!, type: StockType.medicine),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.info));
          }

          final items = snap.data ?? <StockItem>[];

          if (items.isEmpty) {
            return _emptyState();
          }

          StockItem? selected;
          for (final item in items) {
            if (item.id == _selectedItem?.id) {
              selected = item;
              break;
            }
          }

          if (selected != null && selected != _selectedItem) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedItem = selected);
            });
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _hero(),
              const SizedBox(height: 16),
              _stockSelector(items, selected),
              const SizedBox(height: 14),
              if (selected != null) _availableCard(selected),
              const SizedBox(height: 14),
              _quantityField(selected),
              const SizedBox(height: 14),
              _notesField(),
              const SizedBox(height: 20),
              _saveButton(),
            ],
          );
        },
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.info, _medicineBlueDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: _medicineBlueDark.withOpacity(.20), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: Colors.white.withOpacity(.18), shape: BoxShape.circle),
            child: const Icon(Icons.medication_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record medicine usage', style: AppTheme.heading(size: 17, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Track medicine given to goats and keep inventory accurate.', style: AppTheme.body(size: 11, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockSelector(List<StockItem> items, StockItem? selected) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.medication_outlined, 'Medicine'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selected?.id,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Choose medicine',
              prefixIcon: const Icon(Icons.inventory_2_outlined, color: AppColors.info),
              filled: true,
              fillColor: AppColors.paleGreen,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
            ),
            items: items.map((item) {
              final low = item.isLowStock;
              return DropdownMenuItem(
                value: item.id,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.name, style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w600)),
                    ),
                    Text(
                      '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                      style: AppTheme.body(size: 11, color: low ? AppColors.error : AppColors.info, weight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (id) {
              for (final item in items) {
                if (item.id == id) {
                  setState(() {
                    _selectedItem = item;
                    _quantityController.clear();
                  });
                  break;
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _availableCard(StockItem item) {
    final progress = item.quantity <= 0 ? 0.0 : (item.quantity / (item.quantity + 10)).clamp(0.0, 1.0);
    final low = item.isLowStock;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: low ? AppColors.error.withOpacity(.07) : AppColors.info.withOpacity(.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: low ? AppColors.error.withOpacity(.18) : AppColors.info.withOpacity(.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, color: AppColors.info, size: 21),
              const SizedBox(width: 9),
              Expanded(child: Text('Available stock', style: AppTheme.body(size: 12, weight: FontWeight.w600))),
              Text(
                '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                style: AppTheme.heading(size: 16, color: low ? AppColors.error : AppColors.info),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(low ? AppColors.error : AppColors.info),
            ),
          ),
          if (low) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                const SizedBox(width: 5),
                Text('Stock is already low', style: AppTheme.body(size: 11, color: AppColors.error, weight: FontWeight.w700)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _quantityField(StockItem? item) {
    return _card(
      title: 'Usage quantity',
      icon: Icons.remove_circle_outline_rounded,
      child: TextField(
        controller: _quantityController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: AppTheme.body(size: 14, color: AppColors.textDark, weight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'e.g. 2',
          suffixText: item?.unit ?? 'unit',
          prefixIcon: const Icon(Icons.numbers_rounded, color: AppColors.info),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: AppColors.divider)),
        ),
      ),
    );
  }

  Widget _notesField() {
    return _card(
      title: 'Usage note',
      icon: Icons.notes_rounded,
      child: TextField(
        controller: _notesController,
        maxLines: 3,
        style: AppTheme.body(size: 13, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'e.g. Given to Goat G-1004 for deworming',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: AppColors.divider)),
        ),
      ),
    );
  }

  Widget _card({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon, title),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: AppColors.info.withOpacity(.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.info, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title, style: AppTheme.heading(size: 14)),
      ],
    );
  }

  Widget _saveButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle_outline_rounded),
        label: Text(_saving ? 'Saving...' : 'Record Medicine Usage'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.info,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: AppColors.info.withOpacity(.10),
              child: const Icon(Icons.medication_outlined, color: AppColors.info, size: 38),
            ),
            const SizedBox(height: 16),
            Text('No medicine stock yet', style: AppTheme.heading(size: 17)),
            const SizedBox(height: 6),
            Text('Add medicine stock first, then record its usage.', textAlign: TextAlign.center, style: AppTheme.body(size: 12)),
          ],
        ),
      ),
    );
  }
}