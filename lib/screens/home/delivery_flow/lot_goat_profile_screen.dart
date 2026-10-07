import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/image_service.dart';
import '../../../services/sale_goat_details_service.dart';
import '../../../widgets/fast_route.dart';
import '../../../widgets/image_source_sheet.dart';
import '../../../widgets/lot_origin_card.dart';
import '../../palai/fullscreen_image_viewer.dart';

/// Profile of one goat of a LOT booking or lot sale ("Goat 1", "Goat 2" —
/// lot goats are not registered): its lot, photos, approximate age,
/// weight history and health records.
///
/// Opened from the Wait on Delivery / Booking & Holding goat list (can be
/// edited — at the farm or still at the supplier: add photos, update
/// weight / age, add health records; anything not added at the sale can be
/// added here) and from the customer's purchase history ([readOnly]).
///
/// Data: [SaleGoatDetailsService]. A goat with nothing saved yet opens
/// empty and is created by the first change.
class LotGoatProfileScreen extends StatefulWidget {
  final String farmId;
  final Sale sale;
  final int index;
  final bool readOnly;

  const LotGoatProfileScreen({
    super.key,
    required this.farmId,
    required this.sale,
    required this.index,
    this.readOnly = false,
  });

  @override
  State<LotGoatProfileScreen> createState() => _LotGoatProfileScreenState();
}

class _LotGoatProfileScreenState extends State<LotGoatProfileScreen> {
  static final DateFormat _date = DateFormat('d MMM yyyy');

  late final Stream<SaleGoatDetail> _goat = SaleGoatDetailsService.instance
      .goatStream(widget.farmId, widget.sale.id, widget.index);

  Stream<List<SaleGoatExtraPhoto>>? _photos;
  String _photosKey = '';

  bool _busy = false;

  SaleGoatDetailsService get _service => SaleGoatDetailsService.instance;
  Sale get _sale => widget.sale;
  bool get _atSupplier => _sale.sourceLocation == Sale.sourceSupplier;

  /// Extra photos are filed by the goat's key; the stream is kept while
  /// the key stays the same.
  Stream<List<SaleGoatExtraPhoto>> _photosFor(SaleGoatDetail goat) {
    final key = goat.exists && goat.goatKey.isNotEmpty
        ? goat.goatKey
        : SaleGoatDetailsService.docId(_sale.id, widget.index);
    if (_photos == null || key != _photosKey) {
      _photosKey = key;
      _photos = _service.extraPhotosStream(widget.farmId, key);
    }
    return _photos!;
  }

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _snack(done);
    } on ImageTooLargeException {
      if (mounted) _snack('That photo is too large. Choose another.', error: true);
    } catch (e) {
      if (mounted) {
        _snack(FirestoreService.instance.describeError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({Uint8List bytes, String type})?> _pick() async {
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null) return null;
      return (bytes: picked.bytes, type: picked.contentType);
    } on ImageTooLargeException {
      if (mounted) _snack('That photo is too large. Choose another.', error: true);
      return null;
    }
  }

  Future<void> _changeMainPhoto() async {
    final picked = await _pick();
    if (picked == null || !mounted) return;
    await _run(
          () => _service.setPhoto(
        farmId: widget.farmId,
        saleId: _sale.id,
        index: widget.index,
        lotDisplayId: _sale.lotDisplayId,
        bytes: picked.bytes,
        contentType: picked.type,
      ),
      'Photo saved.',
    );
  }

  Future<void> _addPhoto(SaleGoatDetail goat) async {
    // No main photo yet: the first photo becomes the main photo.
    if (!goat.hasPhoto) return _changeMainPhoto();

    final picked = await _pick();
    if (picked == null || !mounted) return;
    await _run(
          () => _service.addExtraPhoto(
        farmId: widget.farmId,
        saleId: _sale.id,
        index: widget.index,
        lotDisplayId: _sale.lotDisplayId,
        goatKey: goat.exists ? goat.goatKey : '',
        bytes: picked.bytes,
        contentType: picked.type,
      ),
      'Photo added.',
    );
  }

  Future<void> _deletePhoto(SaleGoatExtraPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
          () => _service.deleteExtraPhoto(widget.farmId, photo.id),
      'Photo removed.',
    );
  }

  Future<void> _updateWeight(SaleGoatDetail goat) async {
    final result = await showDialog<({double weight, DateTime date})>(
      context: context,
      builder: (_) => _WeightDialog(initial: goat.weight),
    );
    if (result == null || !mounted) return;
    await _run(
          () => _service.updateWeight(
        farmId: widget.farmId,
        saleId: _sale.id,
        index: widget.index,
        lotDisplayId: _sale.lotDisplayId,
        weight: result.weight,
        date: result.date,
      ),
      'Weight saved.',
    );
  }

  Future<void> _updateAge(SaleGoatDetail goat) async {
    final months = await showDialog<int>(
      context: context,
      builder: (_) => _AgeDialog(initial: goat.ageMonths),
    );
    if (months == null || !mounted) return;
    await _run(
          () => _service.setAgeMonths(
        farmId: widget.farmId,
        saleId: _sale.id,
        index: widget.index,
        lotDisplayId: _sale.lotDisplayId,
        months: months,
      ),
      'Age saved.',
    );
  }

  Future<void> _addHealth(SaleGoatDetail goat) async {
    final result = await showDialog<({String status, String note, DateTime date})>(
      context: context,
      builder: (_) => _HealthDialog(
        initial: goat.healthStatus.isEmpty
            ? Goat.healthStatusValues.first
            : goat.healthStatus,
      ),
    );
    if (result == null || !mounted) return;
    await _run(
          () => _service.addHealthRecord(
        farmId: widget.farmId,
        saleId: _sale.id,
        index: widget.index,
        lotDisplayId: _sale.lotDisplayId,
        status: result.status,
        note: result.note,
        date: result.date,
      ),
      'Health record saved.',
    );
  }

  void _view(Uint8List bytes, String title) {
    Navigator.of(context).push(
      fastRoute(FullscreenImageViewer(imageBytes: bytes, title: title)),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(
          'Goat ${widget.index} · ${_sale.id}',
          style: AppTheme.heading(size: 17),
        ),
        bottom: _busy
            ? const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.primaryGreen,
          ),
        )
            : null,
      ),
      body: StreamBuilder<SaleGoatDetail>(
        stream: _goat,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load this goat. '
                      '${FirestoreService.instance.describeError(snap.error!)}',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 12, color: AppColors.error),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }
          final goat = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            children: [
              _header(goat),
              const SizedBox(height: 12),
              LotOriginCard(
                farmId: widget.farmId,
                bookingId: _sale.id,
                lotDocIds: LotOriginCard.lotsOf(_sale, const <Goat>[]),
                note: _atSupplier ? 'At supplier' : 'At farm',
              ),
              const SizedBox(height: 12),
              _detailsCard(goat),
              const SizedBox(height: 12),
              _photosCard(goat),
              const SizedBox(height: 12),
              _weightCard(goat),
              const SizedBox(height: 12),
              _healthCard(goat),
            ],
          );
        },
      ),
    );
  }

  String get _stage {
    if (_sale.isDelivered) return 'Delivered';
    if (_sale.isWaitForDelivery) return 'Wait on Delivery';
    if (_sale.isBooking) return 'Booking & Holding';
    return _sale.deliveryType;
  }

  Widget _header(SaleGoatDetail goat) {
    final photo = goat.photo;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 18),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: photo == null
                    ? (widget.readOnly ? null : _changeMainPhoto)
                    : () => _view(photo, goat.label),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: photo != null
                      ? Image.memory(photo, width: 92, height: 92, fit: BoxFit.cover)
                      : Container(
                    width: 92,
                    height: 92,
                    color: AppColors.primaryGreen.withValues(alpha: 0.10),
                    child: Icon(
                      widget.readOnly
                          ? GoatIcons.paw
                          : Icons.add_a_photo_outlined,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              ),
              if (!widget.readOnly && photo != null)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Material(
                    color: AppColors.primaryGreen,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy ? null : _changeMainPhoto,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.photo_camera_outlined,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goat.label, style: AppTheme.heading(size: 18)),
                const SizedBox(height: 2),
                Text(
                  '${_sale.customerName} · ${_sale.lotDisplayId}',
                  style: AppTheme.body(size: 11.5),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _pill(_stage, AppColors.info),
                    _pill(_atSupplier ? 'At supplier' : 'At farm',
                        _atSupplier ? AppColors.warning : AppColors.success),
                    if (goat.healthStatus.isNotEmpty)
                      _pill(goat.healthStatus, AppColors.darkGreen),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(SaleGoatDetail goat) {
    return _Section(
      title: 'Details',
      children: [
        _row(
          'Approx. age',
          goat.ageMonths > 0 ? '${goat.ageMonths} months' : 'Not added',
          action: widget.readOnly ? null : () => _updateAge(goat),
          actionLabel: goat.ageMonths > 0 ? 'Edit' : 'Add',
        ),
        _row(
          'Weight',
          goat.weight > 0 ? '${goat.weight.toStringAsFixed(1)} kg' : 'Not added',
          action: widget.readOnly ? null : () => _updateWeight(goat),
          actionLabel: 'Update',
        ),
        _row(
          'Health',
          goat.healthStatus.isEmpty ? 'Not recorded' : goat.healthStatus,
          action: widget.readOnly ? null : () => _addHealth(goat),
          actionLabel: 'Add record',
        ),
        _row('Lot', _sale.lotDisplayId),
        _row('Booking', _sale.id),
      ],
    );
  }

  Widget _photosCard(SaleGoatDetail goat) {
    return StreamBuilder<List<SaleGoatExtraPhoto>>(
      stream: _photosFor(goat),
      builder: (context, snap) {
        final extra = snap.data ?? const <SaleGoatExtraPhoto>[];
        final tiles = <Widget>[
          if (goat.photo != null)
            _photoTile(goat.photo!, 'Main', () => _view(goat.photo!, goat.label)),
          for (final p in extra)
            _photoTile(
              p.bytes,
              p.date == null ? '' : _date.format(p.date!),
                  () => _view(p.bytes, goat.label),
              onLongPress: widget.readOnly ? null : () => _deletePhoto(p),
            ),
        ];

        return _Section(
          title: 'Photos',
          trailing: widget.readOnly
              ? null
              : TextButton.icon(
            onPressed: _busy ? null : () => _addPhoto(goat),
            icon: const Icon(Icons.add_a_photo_outlined, size: 16),
            label: Text(goat.hasPhoto ? 'Add photo' : 'Upload photo'),
          ),
          children: [
            if (tiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No photos yet.', style: AppTheme.body(size: 11.5)),
              )
            else ...[
              GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: tiles,
              ),
              if (!widget.readOnly && extra.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Long-press an added photo to remove it.',
                      style: AppTheme.body(size: 10.5)),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _weightCard(SaleGoatDetail goat) {
    return _Section(
      title: 'Weight history',
      trailing: widget.readOnly
          ? null
          : TextButton.icon(
        onPressed: _busy ? null : () => _updateWeight(goat),
        icon: const Icon(Icons.monitor_weight_outlined, size: 16),
        label: const Text('Update weight'),
      ),
      children: [
        if (goat.weightHistory.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              goat.weight > 0
                  ? '${goat.weight.toStringAsFixed(1)} kg (at the sale)'
                  : 'No weight recorded yet.',
              style: AppTheme.body(size: 11.5),
            ),
          )
        else
          for (final w in goat.weightHistory)
            _row(
              w.date == null ? '—' : _date.format(w.date!),
              '${w.weight.toStringAsFixed(1)} kg',
            ),
      ],
    );
  }

  Widget _healthCard(SaleGoatDetail goat) {
    return _Section(
      title: 'Health records',
      trailing: widget.readOnly
          ? null
          : TextButton.icon(
        onPressed: _busy ? null : () => _addHealth(goat),
        icon: const Icon(Icons.medical_services_outlined, size: 16),
        label: const Text('Add record'),
      ),
      children: [
        if (goat.healthRecords.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No health records yet.',
                style: AppTheme.body(size: 11.5)),
          )
        else
          for (final h in goat.healthRecords)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.circle, size: 8, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${h.status}${h.date == null ? '' : ' · ${_date.format(h.date!)}'}',
                          style: AppTheme.heading(size: 12.5),
                        ),
                        if (h.note.isNotEmpty)
                          Text(h.note, style: AppTheme.body(size: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  // ===========================================================================
  // SMALL PIECES
  // ===========================================================================

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTheme.body(size: 10.5, color: AppColors.textDark, weight: FontWeight.w600),
      ),
    );
  }

  Widget _row(String label, String value, {VoidCallback? action, String? actionLabel}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTheme.body(size: 11.5)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.body(size: 12.5, color: AppColors.textDark, weight: FontWeight.w600),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: _busy ? null : action,
              child: Text(
                actionLabel ?? 'Edit',
                style: AppTheme.body(size: 11.5, color: AppColors.darkGreen, weight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoTile(Uint8List bytes, String caption, VoidCallback onTap,
      {VoidCallback? onLongPress}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
          if (caption.isNotEmpty)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(caption,
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _Section({required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTheme.heading(size: 14))),
              if (trailing != null) trailing!,
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

// =============================================================================
// DIALOGS
// =============================================================================

InputDecoration _decoration(String label) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    border: border(AppColors.divider),
    enabledBorder: border(AppColors.divider),
    focusedBorder: border(AppColors.primaryGreen, 1.5),
    errorBorder: border(AppColors.error),
    focusedErrorBorder: border(AppColors.error, 1.5),
  );
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.now(),
  );
}

class _WeightDialog extends StatefulWidget {
  final double initial;
  const _WeightDialog({required this.initial});

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial > 0 ? widget.initial.toStringAsFixed(1) : '',
  );
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final w = double.tryParse(_c.text.trim()) ?? 0;
    if (w <= 0) {
      setState(() => _error = 'Enter the weight');
      return;
    }
    Navigator.of(context).pop((weight: w, date: _date));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update weight'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: _decoration('Weight (kg)').copyWith(errorText: _error),
          ),
          const SizedBox(height: 10),
          _DateRow(
            date: _date,
            onPick: () async {
              final d = await _pickDate(context, _date);
              if (d != null) setState(() => _date = d);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _AgeDialog extends StatefulWidget {
  final int initial;
  const _AgeDialog({required this.initial});

  @override
  State<_AgeDialog> createState() => _AgeDialogState();
}

class _AgeDialogState extends State<_AgeDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial > 0 ? '${widget.initial}' : '',
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final m = int.tryParse(_c.text.trim()) ?? 0;
    if (m <= 0) {
      setState(() => _error = 'Enter the age');
      return;
    }
    Navigator.of(context).pop(m);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approx. age'),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _decoration('Age (months)').copyWith(errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _HealthDialog extends StatefulWidget {
  final String initial;
  const _HealthDialog({required this.initial});

  @override
  State<_HealthDialog> createState() => _HealthDialogState();
}

class _HealthDialogState extends State<_HealthDialog> {
  late String _status = Goat.healthStatusValues.contains(widget.initial)
      ? widget.initial
      : Goat.healthStatusValues.first;
  final TextEditingController _note = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Health record'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InputDecorator(
            decoration: _decoration('Health status'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _status,
                isDense: true,
                isExpanded: true,
                items: [
                  for (final s in Goat.healthStatusValues)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Note (medicine, vaccine, treatment…)'),
          ),
          const SizedBox(height: 10),
          _DateRow(
            date: _date,
            onPick: () async {
              final d = await _pickDate(context, _date);
              if (d != null) setState(() => _date = d);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop((status: _status, note: _note.text, date: _date)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPick;
  const _DateRow({required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _decoration('Date'),
        child: Row(
          children: [
            Expanded(child: Text(DateFormat('d MMM yyyy').format(date))),
            const Icon(Icons.calendar_today_outlined, size: 16),
          ],
        ),
      ),
    );
  }
}