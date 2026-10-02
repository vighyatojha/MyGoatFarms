import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mygoatfarms/app_theme.dart';
import 'package:mygoatfarms/models/stock_model.dart';
import 'package:mygoatfarms/services/firestore_service.dart';
import 'package:mygoatfarms/services/image_service.dart';
import 'package:mygoatfarms/services/stock_edit_service.dart';

/// Opens the Edit sheet for a medicine or feed item. Returns true when the
/// item was saved.
Future<bool> showEditStockItemSheet(
    BuildContext context, {
      required String farmId,
      required StockItem item,
    }) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditStockItemSheet(farmId: farmId, item: item),
  );

  return saved == true;
}

class _EditStockItemSheet extends StatefulWidget {
  final String farmId;
  final StockItem item;

  const _EditStockItemSheet({required this.farmId, required this.item});

  @override
  State<_EditStockItemSheet> createState() => _EditStockItemSheetState();
}

class _EditStockItemSheetState extends State<_EditStockItemSheet> {
  static String _num(double v) =>
      v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  late final TextEditingController _name =
  TextEditingController(text: widget.item.name);
  late final TextEditingController _threshold =
  TextEditingController(text: _num(widget.item.lowStockThreshold));
  late final TextEditingController _quantity =
  TextEditingController(text: _num(widget.item.quantity));
  late final TextEditingController _description =
  TextEditingController(text: widget.item.description ?? '');
  final TextEditingController _correctionNote = TextEditingController();

  Uint8List? _newPhoto;
  String? _newPhotoType;
  bool _removePhoto = false;
  bool _pickingPhoto = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _quantity.dispose();
    _description.dispose();
    _correctionNote.dispose();
    super.dispose();
  }

  Uint8List? get _shownPhoto {
    if (_removePhoto) return null;
    if (_newPhoto != null) return _newPhoto;
    return widget.item.hasPhoto ? widget.item.photo : null;
  }

  bool get _quantityChanged {
    final q = double.tryParse(_quantity.text.trim());
    return q != null && (q - widget.item.quantity).abs() > 0.000001;
  }

  Future<void> _pick({required bool camera}) async {
    if (_pickingPhoto) return;

    setState(() => _pickingPhoto = true);

    try {
      final picked = camera
          ? await ImageService.instance.pickFromCamera()
          : await ImageService.instance.pickFromGallery();

      if (picked == null || !mounted) return;

      setState(() {
        _newPhoto = picked.bytes;
        _newPhotoType = picked.contentType;
        _removePhoto = false;
      });
    } on ImageTooLargeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load that photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _photoOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(camera: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(camera: true);
              },
            ),
            if (_shownPhoto != null)
              ListTile(
                leading:
                const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _newPhoto = null;
                    _newPhotoType = null;
                    _removePhoto = true;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    final name = _name.text.trim();
    final threshold = double.tryParse(_threshold.text.trim());
    final quantity = double.tryParse(_quantity.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }

    if (threshold == null || threshold < 0) {
      setState(() => _error = 'Enter a valid low stock threshold.');
      return;
    }

    if (quantity == null || quantity < 0) {
      setState(() => _error = 'Enter a valid quantity.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await StockEditService.instance.editItem(
        farmId: widget.farmId,
        item: widget.item,
        name: name,
        lowStockThreshold: threshold,
        description: _description.text,
        newQuantity: _quantityChanged ? quantity : null,
        newPhoto: _newPhoto,
        newPhotoContentType: _newPhotoType,
        removePhoto: _removePhoto,
        correctionNote: _correctionNote.text,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'This is taking too long. Check your connection and retry.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ArgumentError
            ? e.message.toString()
            : e is StateError
            ? e.message
            : FirestoreService.instance.describeError(e);
      });
    }
  }

  InputDecoration _field(String label, {String? suffix, String? helper}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      helperText: helper,
      filled: true,
      fillColor: AppColors.paleGreen,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final isMedicine = widget.item.type == StockType.medicine;
    final photo = _shownPhoto;
    final unit = widget.item.unit;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + inset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isMedicine ? 'Edit medicine' : 'Edit feed',
                style: AppTheme.heading(size: 18),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickingPhoto ? null : _photoOptions,
                    child: Container(
                      width: 64,
                      height: 64,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.paleGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _pickingPhoto
                          ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                          : photo != null
                          ? Image.memory(photo, fit: BoxFit.cover)
                          : Icon(
                        isMedicine
                            ? Icons.medication_rounded
                            : Icons.grass_rounded,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickingPhoto ? null : _photoOptions,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(
                        photo == null ? 'Add photo' : 'Change photo',
                      ),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _field(isMedicine ? 'Medicine name' : 'Feed name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _quantity,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: _field(
                  'Quantity in stock',
                  suffix: unit,
                  helper: 'Change this only to correct a wrong count. '
                      'It is saved in Recent Activity.',
                ),
              ),
              if (_quantityChanged) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _correctionNote,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  decoration: _field('Reason for correction (optional)'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _threshold,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: _field('Low stock threshold', suffix: unit),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: _field(
                  isMedicine
                      ? 'Description / dosage notes'
                      : 'Description',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.error,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.info,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}