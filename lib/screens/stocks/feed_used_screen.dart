import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';

class FeedUsedScreen extends StatefulWidget {
  const FeedUsedScreen({super.key});

  @override
  State<FeedUsedScreen> createState() => _FeedUsedScreenState();
}

class _FeedUsedScreenState extends State<FeedUsedScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  StockItem? _selectedItem;
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String _usageUnit = 'Kg';

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
        backgroundColor: error ? AppColors.error : AppColors.primaryGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _save() async {
    final item = _selectedItem;
    final farmId = _farmId;

    if (item == null || farmId == null) {
      _message('Select a feed item first.', error: true);
      return;
    }

    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;

    if (quantity <= 0) {
      _message('Enter a valid quantity.', error: true);
      return;
    }

    final usageIsBag = _usageUnit.trim().toLowerCase() == 'bag';
    final availableInUsageUnit = item.isBagUnit && !item.needsBagWeight
        ? (usageIsBag ? item.quantity : item.totalKg)
        : item.quantity;

    if (quantity > availableInUsageUnit + 0.000001) {
      _message(
        'You only have ${item.isBagUnit && !item.needsBagWeight ? (usageIsBag ? '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} Bags' : '${item.totalKg.toStringAsFixed(item.totalKg % 1 == 0 ? 0 : 1)} KG') : item.quantityLabel} available.',
        error: true,
      );
      return;
    }

    if (item.isBagUnit && item.needsBagWeight) {
      _message('This feed needs a Weight per Bag before it can be used.', error: true);
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
        usageUnit: _usageUnit,
        notes: _notesController.text.trim(),
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.feedUsed,
          title: 'Feed Used Today',
          subtitle: '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} $_usageUnit'
              '${item.isBagUnit && !item.needsBagWeight && _usageUnit.toLowerCase() == 'bag' ? ' (${(quantity * item.weightPerBag!).toStringAsFixed(0)} KG)' : ''}'
              ' of ${item.name} used'
              '${_notesController.text.trim().isEmpty ? '' : ' — ${_notesController.text.trim()}'}',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Feed usage recorded');
    } on TimeoutException {
      _message('Connection is taking too long. Please try again.', error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmUsage(StockItem item, double quantity) async {
    final usedKg = item.isBagUnit && !item.needsBagWeight && _usageUnit.toLowerCase() == 'bag'
        ? quantity * item.weightPerBag!
        : quantity;
    final remainingKg = item.isBagUnit && !item.needsBagWeight
        ? (item.totalKg - usedKg).clamp(0, double.infinity)
        : (item.quantity - quantity).clamp(0, double.infinity);
    final remainingText = item.isBagUnit && !item.needsBagWeight
        ? '${(remainingKg / item.weightPerBag!).toStringAsFixed((remainingKg / item.weightPerBag!) % 1 == 0 ? 0 : 1)} Bags (${remainingKg.toStringAsFixed(remainingKg % 1 == 0 ? 0 : 1)} KG)'
        : '${remainingKg.toStringAsFixed(remainingKg % 1 == 0 ? 0 : 1)} ${item.unit}';

    return await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.lightGreen,
                  child: Icon(Icons.remove_circle_outline, color: AppColors.primaryGreen, size: 28),
                ),
                const SizedBox(height: 12),
                Text('Confirm feed usage', style: AppTheme.heading(size: 17)),
                const SizedBox(height: 5),
                Text(
                  '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} $_usageUnit will be deducted from ${item.name}.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 12),
                ),
                const SizedBox(height: 16),
                _summaryRow('Current stock', item.quantityLabel),
                _summaryRow(
                  'Used now',
                  '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} $_usageUnit'
                      '${item.isBagUnit && _usageUnit.toLowerCase() == 'bag' ? ' (${usedKg.toStringAsFixed(usedKg % 1 == 0 ? 0 : 1)} KG)' : ''}',
                ),
                _summaryRow('Remaining', remainingText, highlight: true),
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
                          backgroundColor: AppColors.primaryGreen,
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
              color: highlight ? AppColors.darkGreen : AppColors.textDark,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotLinkedState() {
    return FarmNotLinkedState(
      buttonColor: AppColors.primaryGreen,
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
        title: Text('Feed Used Today', style: AppTheme.heading(size: 18)),
      ),
      body: _loadingFarm
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : _farmId == null
          ? _buildNotLinkedState()
          : StreamBuilder<List<StockItem>>(
        stream: FirestoreService.instance.stockItemsStream(_farmId!, type: StockType.feed),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
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
              if (selected != null) _usageUnitSelector(selected),
              if (selected != null) const SizedBox(height: 14),
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
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, AppColors.darkGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: AppColors.darkGreen.withOpacity(.20), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: Colors.white.withOpacity(.18), shape: BoxShape.circle),
            child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record feed usage', style: AppTheme.heading(size: 17, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Choose stock, enter usage and review the remaining quantity.', style: AppTheme.body(size: 11, color: Colors.white70)),
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
          _sectionTitle(Icons.grass_rounded, 'Feed item'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selected?.id,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Choose feed item',
              prefixIcon: const Icon(Icons.inventory_2_outlined, color: AppColors.primaryGreen),
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
                      item.quantityLabel,
                      style: AppTheme.body(size: 11, color: low ? AppColors.error : AppColors.darkGreen, weight: FontWeight.w700),
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
                    _usageUnit = item.isBagUnit ? 'Kg' : item.unit;
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
    final available = item.isBagUnit && !item.needsBagWeight ? item.totalKg : item.quantity;
    final progress = available <= 0 ? 0.0 : (available / (available + 50)).clamp(0.0, 1.0);
    final low = item.isLowStock;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: low ? AppColors.error.withOpacity(.07) : AppColors.lightGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: low ? AppColors.error.withOpacity(.18) : AppColors.primaryGreen.withOpacity(.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, color: AppColors.primaryGreen, size: 21),
              const SizedBox(width: 9),
              Expanded(child: Text('Available stock', style: AppTheme.body(size: 12, weight: FontWeight.w600))),
              Text(
                item.quantityLabel,
                style: AppTheme.heading(size: 16, color: low ? AppColors.error : AppColors.darkGreen),
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
              valueColor: AlwaysStoppedAnimation<Color>(low ? AppColors.error : AppColors.primaryGreen),
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

  Widget _usageUnitSelector(StockItem item) {
    final units = item.isBagUnit ? const ['Kg', 'Bag'] : <String>[item.unit];
    return _card(
      title: 'Usage unit',
      icon: Icons.swap_horiz_rounded,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: units.map((unit) {
            final selected = _usageUnit.toLowerCase() == unit.toLowerCase();
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _usageUnit = unit;
                    _quantityController.clear();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: selected
                        ? [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 5)]
                        : null,
                  ),
                  child: Text(
                    unit,
                    textAlign: TextAlign.center,
                    style: AppTheme.body(
                      size: 12,
                      color: selected ? AppColors.darkGreen : AppColors.textGrey,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
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
          hintText: 'e.g. 15',
          suffixText: item?.isBagUnit == true ? _usageUnit : (item?.unit ?? 'unit'),
          prefixIcon: const Icon(Icons.scale_outlined, color: AppColors.primaryGreen),
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
      title: 'Notes',
      icon: Icons.notes_rounded,
      child: TextField(
        controller: _notesController,
        maxLines: 3,
        style: AppTheme.body(size: 13, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'Optional: morning feeding, shed A...',
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
          decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primaryGreen, size: 18),
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
        label: Text(_saving ? 'Saving...' : 'Record Feed Usage'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
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
            const CircleAvatar(
              radius: 42,
              backgroundColor: AppColors.lightGreen,
              child: Icon(Icons.inventory_2_outlined, color: AppColors.primaryGreen, size: 38),
            ),
            const SizedBox(height: 16),
            Text('No feed stock yet', style: AppTheme.heading(size: 17)),
            const SizedBox(height: 6),
            Text('Add feed stock first, then record daily usage.', textAlign: TextAlign.center, style: AppTheme.body(size: 12)),
          ],
        ),
      ),
    );
  }
}
