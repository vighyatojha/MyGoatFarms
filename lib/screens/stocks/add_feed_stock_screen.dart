import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/stock_model.dart';
import '../../models/activity_model.dart';
import '../../services/firestore_service.dart';

class AddFeedStockScreen extends StatefulWidget {
  const AddFeedStockScreen({super.key});

  @override
  State<AddFeedStockScreen> createState() => _AddFeedStockScreenState();
}

class _AddFeedStockScreenState extends State<AddFeedStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _thresholdController = TextEditingController(text: '20');
  final _notesController = TextEditingController();

  bool _saving = false;
  String? _farmId;
  StockItem? _selectedFeed;
  String _unit = 'Kg';

  static const _units = ['Kg', 'Bag'];

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final farmId = await FirestoreService.instance.currentFarmId();
    if (!mounted) return;
    setState(() => _farmId = farmId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _thresholdController.dispose();
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
    if (!_formKey.currentState!.validate()) return;

    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;

    if (quantity <= 0) {
      _message('Enter a quantity greater than 0.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final farmId = await FirestoreService.instance.currentFarmId();

      if (farmId == null) {
        _message('Could not find your farm profile. Please log in again.', error: true);
        return;
      }

      final name = _nameController.text.trim();

      await FirestoreService.instance.addStock(
        farmId,
        itemName: name,
        type: StockType.feed,
        quantity: quantity,
        unit: _unit,
        lowStockThreshold: threshold,
        notes: _notesController.text.trim(),
      );

      await FirestoreService.instance.logActivity(
        farmId,
        ActivityLog(
          id: '',
          type: ActivityType.feedStockAdded,
          title: 'Feed Stock Added',
          subtitle: '${quantity.toStringAsFixed(0)} $_unit of $name added'
              '${_notesController.text.trim().isEmpty ? '' : ' — ${_notesController.text.trim()}'}',
          module: 'stock',
          timestamp: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Feed stock added successfully');
    } on TimeoutException {
      _message('Connection is taking too long. Please try again.', error: true);
    } catch (e) {
      _message(FirestoreService.instance.describeError(e), error: true);
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
        titleSpacing: 4,
        title: Text('Add Feed Stock', style: AppTheme.heading(size: 18)),
      ),
      bottomNavigationBar: _bottomAction(),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _hero(),
              const SizedBox(height: 16),
              _section(
                title: 'Feed details',
                icon: Icons.grass_rounded,
                children: [
                  _feedSelector(),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _field(
                          controller: _quantityController,
                          label: 'Quantity',
                          hint: '100',
                          icon: Icons.inventory_2_outlined,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _unitSelector(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Stock alert',
                icon: Icons.notifications_active_outlined,
                children: [
                  _field(
                    controller: _thresholdController,
                    label: 'Low-stock threshold',
                    hint: '20',
                    suffix: _unit,
                    icon: Icons.warning_amber_rounded,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will see a low-stock warning when the quantity reaches this level.',
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Notes',
                icon: Icons.notes_rounded,
                children: [
                  _field(
                    controller: _notesController,
                    label: 'Additional note',
                    hint: 'Supplier, quality, storage location...',
                    icon: Icons.edit_note_rounded,
                    maxLines: 3,
                    optional: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _tip(),
            ],
          ),
        ),
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
          BoxShadow(
            color: AppColors.darkGreen.withOpacity(.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.grass_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add feed to inventory',
                  style: AppTheme.heading(size: 17, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Record what arrived and set the alert level.',
                  style: AppTheme.body(size: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppTheme.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _feedSelector() {
    if (_farmId == null) {
      return _field(
        controller: _nameController,
        label: 'Feed name',
        hint: 'Loading existing feeds...',
        icon: Icons.eco_rounded,
        readOnly: true,
      );
    }

    return StreamBuilder<List<StockItem>>(
      stream: FirestoreService.instance.stockItemsStream(
        _farmId!,
        type: StockType.feed,
      ),
      builder: (context, snapshot) {
        final feeds = snapshot.data ?? <StockItem>[];

        // Keep the selected object synced with Firestore after a stock update.
        StockItem? selected;
        if (_selectedFeed != null) {
          for (final item in feeds) {
            if (item.id == _selectedFeed!.id) {
              selected = item;
              break;
            }
          }
        }

        if (selected != null && selected != _selectedFeed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedFeed = selected);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _saving ? null : () => _showFeedPicker(feeds),
              child: AbsorbPointer(
                child: _field(
                  controller: _nameController,
                  label: 'Feed name',
                  hint: feeds.isEmpty
                      ? 'Select or add a feed'
                      : 'Select an existing feed',
                  icon: Icons.eco_rounded,
                  readOnly: true,
                  suffixIcon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 9),
              _selectedFeedSummary(selected),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showFeedPicker(List<StockItem> feeds) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Select feed', style: AppTheme.heading(size: 17)),
                            const SizedBox(height: 2),
                            Text(
                              feeds.isEmpty
                                  ? 'No feed has been added yet.'
                                  : 'Choose an existing feed or create a new one.',
                              style: AppTheme.body(size: 11, color: AppColors.textGrey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (feeds.isNotEmpty)
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      itemCount: feeds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = feeds[index];
                        return _feedPickerTile(item, sheetContext);
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => Navigator.pop(sheetContext, 'new'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: AppColors.primaryGreen.withOpacity(.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.add_circle_rounded, color: AppColors.primaryGreen),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Add New Feed',
                              style: AppTheme.body(
                                size: 13,
                                color: AppColors.darkGreen,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.primaryGreen),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == 'new') {
      await _addNewFeedName();
    } else if (result is StockItem) {
      _selectExistingFeed(result);
    }
  }

  Widget _feedPickerTile(StockItem item, BuildContext sheetContext) {
    final selected = _selectedFeed?.id == item.id;
    final status = item.isLowStock ? 'Low stock' : 'Good stock';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(sheetContext, item),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? AppColors.lightGreen : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primaryGreen
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.grass_rounded, color: AppColors.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: AppTheme.heading(size: 13)),
                  const SizedBox(height: 3),
                  Text(
                    'Current stock: ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit}',
                    style: AppTheme.body(size: 11, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: item.isLowStock
                    ? AppColors.warning.withOpacity(.12)
                    : AppColors.lightGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: AppTheme.body(
                  size: 10,
                  color: item.isLowStock ? AppColors.warning : AppColors.darkGreen,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  void _selectExistingFeed(StockItem item) {
    setState(() {
      _selectedFeed = item;
      _nameController.text = item.name;
      _unit = item.unit;
      _thresholdController.text = item.lowStockThreshold.toStringAsFixed(
        item.lowStockThreshold % 1 == 0 ? 0 : 1,
      );
    });
  }

  Future<void> _addNewFeedName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Add new feed', style: AppTheme.heading(size: 17)),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Feed name',
              hintText: 'e.g. Maize, Bajra, Chana Chuni',
              prefixIcon: const Icon(Icons.eco_rounded, color: AppColors.primaryGreen),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(dialogContext, value);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    // Note: we intentionally do NOT call controller.dispose() here.
    // showDialog's Future completes as soon as Navigator.pop() is called,
    // but the dialog's exit transition is still playing for several more
    // frames, and the (still-focused) TextField above is still mounted
    // during that time. Disposing the controller immediately races with
    // that teardown and throws:
    //   "'_dependents.isEmpty': is not true" (framework.dart)
    // This controller is only ever used for this single dialog, so it's
    // safe to just let it be garbage-collected once it's dropped.

    if (!mounted || name == null || name.trim().isEmpty) return;

    setState(() {
      _selectedFeed = null;
      _nameController.text = name.trim();
      _unit = 'Kg';
      _thresholdController.text = '20';
    });
  }

  Widget _selectedFeedSummary(StockItem item) {
    final newQuantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    final projected = item.quantity + newQuantity;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(.16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppColors.primaryGreen, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current stock  ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit}',
                  style: AppTheme.body(size: 11, color: AppColors.textGrey),
                ),
                if (newQuantity > 0)
                  Text(
                    'After addition  ${projected.toStringAsFixed(projected % 1 == 0 ? 0 : 1)} ${item.unit}',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.darkGreen,
                      weight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 20),
        ],
      ),
    );
  }

  Widget _unitSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unit', style: AppTheme.body(size: 11, color: AppColors.textGrey, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: _units.map((unit) {
              final selected = _unit == unit;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _unit = unit),
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
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    bool optional = false,
    bool readOnly = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      readOnly: readOnly,
      onChanged: onChanged,
      validator: (value) {
        if (!optional && (value == null || value.trim().isEmpty)) return 'Required';
        return null;
      },
      style: AppTheme.body(size: 13, color: AppColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
        suffixText: suffix,
        suffixIcon: suffixIcon,
        labelStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        hintStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
        ),
      ),
    );
  }

  Widget _tip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.info.withOpacity(.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppColors.info, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tip: use the same unit you use when purchasing this feed so stock usage and alerts stay consistent.',
              style: AppTheme.body(size: 11, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: SizedBox(
        height: 54,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Icon(Icons.add_rounded),
          label: Text(_saving ? 'Saving...' : 'Add to Stock'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
    );
  }
}