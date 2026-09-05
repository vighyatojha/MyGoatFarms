import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../models/report_models.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/report_pdf_service.dart';
import '../../widgets/fast_route.dart';
import 'report_ready_screen.dart';

/// Generates a report for one Palai goat, covering everything recorded
/// from its check-in (registration) date through today.
///
/// A short, four-step wizard keeps this easy to follow on a phone:
///  1. Report Type   — Progress Report (built) or Final Report (coming
///     soon — picking it just shows a toast and stays on this step).
///  2. Report Period  — read-only summary of the date range and what
///     will go into the report, pulled live from this goat's health
///     records.
///  3. Report Photos  — camera-only photo capture (no gallery), stored
///     against the report itself so the PDF always shows exactly what
///     was captured for it.
///  4. Preview & Generate — final check, then builds the PDF, saves the
///     report + updates the goat's report status, and opens the
///     Share/Save screen.
class GenerateReportScreen extends StatefulWidget {
  final PalaiGoat goat;
  const GenerateReportScreen({super.key, required this.goat});

  @override
  State<GenerateReportScreen> createState() => _GenerateReportScreenState();
}

class _GenerateReportScreenState extends State<GenerateReportScreen> {
  static const int _maxPhotos = 3;
  static const List<String> _stepTitles = ['Report Type', 'Report Period', 'Report Photos', 'Preview & Generate'];

  int _step = 0;
  String? _farmId;

  GoatReportType? _selectedType;

  bool _loadingHistory = false;
  List<HealthRecordEntry> _historyAscending = [];
  bool _historyLoaded = false;

  final List<PickedImage> _photos = [];
  bool _capturingPhoto = false;

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  // -------------------------------------------------------------------
  // Step 1 — Report Type
  // -------------------------------------------------------------------

  void _selectType(GoatReportType type) {
    if (type == GoatReportType.final_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Final Report is coming soon! Use Progress Report for now.'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }
    setState(() => _selectedType = type);
    _goToStep(1);
  }

  // -------------------------------------------------------------------
  // Step 2 — Report Period (auto: check-in date -> today)
  // -------------------------------------------------------------------

  Future<void> _loadHistory() async {
    if (_historyLoaded || _loadingHistory) return;
    if (_farmId == null) {
      // Previously silently no-op'd, leaving the person stuck on this
      // step with no feedback if farm resolution had failed. Give them
      // something actionable instead of an indefinite blank state.
      _showSnack("Couldn't load your farm. Please go back and try again.", isError: true);
      return;
    }
    setState(() => _loadingHistory = true);
    try {
      final descending = await FirestoreService.instance
          .healthRecordsStream(_farmId!, widget.goat.customerId, widget.goat.id)
          .first;
      final ascending = descending.reversed.toList();
      if (!mounted) return;
      setState(() {
        _historyAscending = ascending;
        _historyLoaded = true;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      _showSnack("Couldn't load this goat's health history. Please try again.", isError: true);
    }
  }

  // Start weight is always the weight recorded at check-in — that's the
  // actual start of the report period (checkInDate). It must NOT shift to
  // whatever weight was logged in the first health record, otherwise a
  // goat with only one health record ends up with its just-entered weight
  // showing as "Start Weight" instead of "Current Weight".
  double? get _startWeight => widget.goat.weightAtCheckIn;

  // Current/end weight is the most recently logged health record weight;
  // if no health records exist yet, fall back to the goat's current/at
  // check-in weight so the report still has a value to show.
  double? get _endWeight =>
      _historyAscending.isNotEmpty ? _historyAscending.last.weight : (widget.goat.currentWeight ?? widget.goat.weightAtCheckIn);

  // -------------------------------------------------------------------
  // Step 3 — Report Photos (camera only)
  // -------------------------------------------------------------------

  Future<void> _capturePhoto() async {
    if (_photos.length >= _maxPhotos) {
      _showSnack('You can add up to $_maxPhotos photos per report.');
      return;
    }
    setState(() => _capturingPhoto = true);
    try {
      final picked = await ImageService.instance.pickFromCamera(
        maxStoredBytes: 200 * 1024,
        maxDimension: 480,
      );
      if (picked != null && mounted) {
        setState(() => _photos.add(picked));
      }
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Could not capture photo. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _capturingPhoto = false);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  // -------------------------------------------------------------------
  // Step 4 — Generate
  // -------------------------------------------------------------------

  /// Assembles every photo the report should show, in chronological
  /// order, each tagged with a label so the PDF can caption them:
  ///   1. The "Before Palai" photo taken at check-in.
  ///   2. The photo attached to the most recent health record that has
  ///      one (not necessarily the very latest record — if the latest
  ///      entry has no photo, we fall back to the last one that does).
  ///   3. Whatever photo(s) were just captured for this report.
  ///
  /// Previously only #3 was ever included, which is why the PDF looked
  /// like it was "missing" the check-in and health-update photos — they
  /// were never being attached to the report at all.
  List<ReportImage> _buildReportImages() {
    final images = <ReportImage>[];

    final beforeBytes = widget.goat.beforeImage;
    if (beforeBytes != null && beforeBytes.isNotEmpty) {
      images.add(ReportImage(
        bytes: beforeBytes,
        contentType: widget.goat.beforeImageContentType ?? 'image/jpeg',
        label: 'Check-In Photo',
      ));
    }

    for (final entry in _historyAscending.reversed) {
      final img = entry.image;
      if (img != null && img.isNotEmpty) {
        images.add(ReportImage(
          bytes: img,
          contentType: entry.imageContentType,
          label: 'Health Update Photo',
        ));
        break;
      }
    }

    for (int i = 0; i < _photos.length; i++) {
      images.add(ReportImage(
        bytes: _photos[i].bytes,
        contentType: _photos[i].contentType,
        label: _photos.length > 1 ? 'Report Day Photo ${i + 1}' : 'Report Day Photo',
      ));
    }

    return images;
  }

  Future<void> _generate() async {
    if (_farmId == null || _selectedType == null) return;
    setState(() => _generating = true);
    try {
      final customer = await FirestoreService.instance.getCustomer(_farmId!, widget.goat.customerId);
      final farm = await FirestoreService.instance.getFarmById(_farmId!);
      if (customer == null) {
        _showSnack("Couldn't find this goat's customer. Please try again.", isError: true);
        setState(() => _generating = false);
        return;
      }

      final report = GoatReport(
        id: '',
        type: _selectedType!,
        fromDate: widget.goat.checkInDate,
        toDate: DateTime.now(),
        generatedAt: DateTime.now(),
        startWeight: _startWeight,
        endWeight: _endWeight,
        healthStatus: widget.goat.healthStatus,
        images: _buildReportImages(),
      );

      final billSettings = farm?.billSettings ?? const BillSettings();

      final bytes = await ReportPdfService.instance.buildBytes(
        goat: widget.goat,
        customer: customer,
        report: report,
        historyAscending: _historyAscending,
        billSettings: billSettings,
      );

      await FirestoreService.instance.saveGoatReport(_farmId!, widget.goat.customerId, widget.goat.id, report);

      if (!mounted) return;
      setState(() => _generating = false);
      Navigator.of(context).pushReplacement(fastRoute(ReportReadyScreen(goat: widget.goat, pdfBytes: bytes)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showSnack('Could not generate the report. Please try again.', isError: true);
    }
  }

  // -------------------------------------------------------------------
  // Step navigation
  // -------------------------------------------------------------------

  void _goToStep(int step) {
    setState(() => _step = step);
    if (step == 1) _loadHistory();
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      _goToStep(_step - 1);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text('Generate Report · ${widget.goat.goatCode}', style: AppTheme.heading(size: 15)),
      ),
      body: Column(
        children: [
          _stepProgress(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Padding(
                key: ValueKey(_step),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(child: _stepBody()),
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _stepProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 0; i < _stepTitles.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step ? AppColors.primaryGreen : AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i != _stepTitles.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text('Step ${_step + 1} of ${_stepTitles.length} · ${_stepTitles[_step]}', style: AppTheme.body(size: 12, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _typeStep();
      case 1:
        return _periodStep();
      case 2:
        return _photosStep();
      default:
        return _previewStep();
    }
  }

  Widget? _primaryAction() {
    switch (_step) {
      case 0:
        return null; // selecting a type card advances automatically
      case 1:
        return _historyLoaded
            ? _actionButton('Continue', () => _goToStep(2))
            : null;
      case 2:
        return _actionButton('Continue', () => _goToStep(3));
      default:
        return _actionButton(
          _generating ? 'Generating…' : 'Generate Report',
          _generating ? null : _generate,
          loading: _generating,
        );
    }
  }

  Widget _bottomBar() {
    final action = _primaryAction();
    if (action == null) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: action,
    );
  }

  Widget _actionButton(String label, VoidCallback? onPressed, {bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Step 1 UI — Report Type
  // -------------------------------------------------------------------

  Widget _typeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What kind of report?', style: AppTheme.heading(size: 16)),
        const SizedBox(height: 4),
        Text('Choose what this report should cover.', style: AppTheme.body(size: 12)),
        const SizedBox(height: 16),
        _typeCard(
          icon: Icons.trending_up,
          title: 'Progress Report',
          subtitle: 'Everything recorded from check-in to today — weight trend, health update and photos.',
          badge: null,
          onTap: () => _selectType(GoatReportType.progress),
        ),
        const SizedBox(height: 12),
        _typeCard(
          icon: Icons.fact_check_outlined,
          title: 'Final Report',
          subtitle: 'A complete check-out summary for this goat.',
          badge: 'Coming soon',
          onTap: () => _selectType(GoatReportType.final_),
        ),
      ],
    );
  }

  Widget _typeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: AppTheme.card(radius: 16),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
                child: Icon(icon, color: AppColors.primaryGreen, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: AppTheme.heading(size: 14)),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                            child: Text(badge, style: AppTheme.body(size: 10, color: AppColors.warning, weight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTheme.body(size: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textGrey),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Step 2 UI — Report Period
  // -------------------------------------------------------------------

  Widget _periodStep() {
    if (_loadingHistory || !_historyLoaded) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }
    final start = _startWeight;
    final end = _endWeight;
    final gain = (start != null && end != null) ? end - start : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Report period', style: AppTheme.heading(size: 16)),
        const SizedBox(height: 4),
        Text('Automatically covers from check-in to today.', style: AppTheme.body(size: 12)),
        const SizedBox(height: 16),
        Container(
          decoration: AppTheme.card(radius: 16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('From', _fmt(widget.goat.checkInDate)),
              const Divider(height: 20),
              _summaryRow('To (today)', _fmt(DateTime.now())),
              const Divider(height: 20),
              _summaryRow('Health records in period', '${_historyAscending.length}'),
              const Divider(height: 20),
              _summaryRow('Current health status', widget.goat.healthStatus),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: AppTheme.card(radius: 16),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: _statBlock('Start Weight', start != null ? '${start.toStringAsFixed(1)} kg' : '—')),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(child: _statBlock('Current Weight', end != null ? '${end.toStringAsFixed(1)} kg' : '—')),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(
                child: _statBlock(
                  'Gain',
                  gain != null ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : '—',
                  color: gain == null ? AppColors.textDark : (gain >= 0 ? AppColors.success : AppColors.error),
                ),
              ),
            ],
          ),
        ),
        if (_historyAscending.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'No health records logged yet for this goat, so weight trend won\'t appear in the report. You can still generate it.',
            style: AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.body(size: 12)),
        Text(value, style: AppTheme.body(size: 12, color: AppColors.textDark, weight: FontWeight.w700)),
      ],
    );
  }

  Widget _statBlock(String label, String value, {Color color = AppColors.textDark}) {
    return Column(
      children: [
        Text(value, style: AppTheme.heading(size: 15, color: color)),
        const SizedBox(height: 3),
        Text(label, style: AppTheme.body(size: 10), textAlign: TextAlign.center),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Step 3 UI — Report Photos (camera only)
  // -------------------------------------------------------------------

  Widget _photosStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Report photos', style: AppTheme.heading(size: 16)),
        const SizedBox(height: 4),
        Text('Take up to $_maxPhotos photos with the camera to include in this report. Optional.', style: AppTheme.body(size: 12)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (int i = 0; i < _photos.length; i++) _photoThumb(i),
            if (_photos.length < _maxPhotos) _addPhotoTile(),
          ],
        ),
      ],
    );
  }

  Widget _photoThumb(int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(_photos[index].bytes, width: 100, height: 100, fit: BoxFit.cover),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addPhotoTile() {
    return GestureDetector(
      onTap: _capturingPhoto ? null : _capturePhoto,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryGreen.withOpacity(0.4), width: 1.5),
        ),
        child: _capturingPhoto
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen))
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, color: AppColors.primaryGreen, size: 26),
            const SizedBox(height: 6),
            Text('Take Photo', style: AppTheme.body(size: 10, color: AppColors.primaryGreen, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Step 4 UI — Preview & Generate
  // -------------------------------------------------------------------

  Widget _previewStep() {
    final gain = (_startWeight != null && _endWeight != null) ? _endWeight! - _startWeight! : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ready to generate', style: AppTheme.heading(size: 16)),
        const SizedBox(height: 4),
        Text('Review the details below, then generate the PDF.', style: AppTheme.body(size: 12)),
        const SizedBox(height: 16),
        Container(
          decoration: AppTheme.card(radius: 16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('Report type', _selectedType?.label ?? '—'),
              const Divider(height: 20),
              _summaryRow('Goat', '${widget.goat.goatCode} · ${widget.goat.breed}'),
              const Divider(height: 20),
              _summaryRow('Period', '${_fmt(widget.goat.checkInDate)}  →  ${_fmt(DateTime.now())}'),
              const Divider(height: 20),
              _summaryRow('Weight gain', gain != null ? '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} kg' : '—'),
              const Divider(height: 20),
              _summaryRow('Photos attached', '${_photos.length}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'The report will be saved to this goat\'s history, and the goat list will show it as reported.',
          style: AppTheme.body(size: 11, color: AppColors.textGrey),
        ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}