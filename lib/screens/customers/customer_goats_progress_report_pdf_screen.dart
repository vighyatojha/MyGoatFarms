import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/monthly_bill_model.dart';
import '../../models/palai_models.dart';
import '../../models/report_models.dart';
import '../../services/customer_goats_progress_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/monthly_billing_service.dart';

/// Lets the owner generate ONE consolidated Progress Report covering all
/// (or a chosen subset of) the goats under a single Palai customer —
/// laid out like the reference "Monthly Report": a numbered card per
/// goat showing its previous photo next to a freshly captured photo,
/// weight & gain, and the latest health update.
///
/// This is the multi-goat sibling of GenerateReportScreen. It is a
/// direct evolution of CustomerGoatsReportScreen: same goat-selection
/// step, but instead of building a flat summary table it also collects
/// one camera photo per selected goat, then saves an individual
/// [GoatReport] for each goat (same Firestore path GenerateReportScreen
/// uses: `.../goats/{goatId}/reports/{reportId}`) so:
///   - the goat's "Report" badge / reportsCount stay accurate, and
///   - the NEXT time a progress report is generated for that goat, this
///     report's photo becomes the "previous" photo automatically.
///
/// "Previous" photo rule:
///   - 1st report ever for a goat -> the check-in ("Before Palai") photo.
///   - Every report after that   -> the photo saved with that goat's
///     most recently generated report.
class CustomerGoatsProgressReportScreen extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;

  const CustomerGoatsProgressReportScreen({
    super.key,
    required this.farmId,
    required this.customer,
  });

  @override
  State<CustomerGoatsProgressReportScreen> createState() =>
      _CustomerGoatsProgressReportScreenState();
}

/// What we know about a goat's *previous* state before this report is
/// generated — fetched once, right before the capture step, so the
/// capture step (and the final PDF) always has somewhere to pull a
/// "previous" photo/weight from even if the goat has no earlier report.
class _PreviousInfo {
  final Uint8List bytes;
  final String label;
  final DateTime date;
  final double? weight;
  final HealthRecordEntry? latestHealthRecord;

  const _PreviousInfo({
    required this.bytes,
    required this.label,
    required this.date,
    required this.weight,
    required this.latestHealthRecord,
  });
}

enum _Phase { selecting, capturing }

class _CustomerGoatsProgressReportScreenState
    extends State<CustomerGoatsProgressReportScreen> {
  Stream<List<PalaiGoat>>? _goatsStream;

  final Set<String> _selectedIds = {};
  List<PalaiGoat> _lastLoadedGoats = [];

  _Phase _phase = _Phase.selecting;

  bool _loadingPrevious = false;
  final Map<String, _PreviousInfo> _previousByGoatId = {};

  final Map<String, PickedImage> _capturedByGoatId = {};
  String? _capturingGoatId;

  /// One weight-entry controller per goat, created lazily as each goat's
  /// capture tile is built, and reused across rebuilds so the owner's
  /// typing isn't lost mid-flow.
  final Map<String, TextEditingController> _weightControllers = {};

  // ------------------------------------------------------------------
  // BILLING (this month's Palai amount + old pending amount)
  // ------------------------------------------------------------------

  /// The customer's pending/outstanding amount *before* this month's
  /// bill, re-fetched fresh (not from `widget.customer`, which may be
  /// stale) the moment we enter the capture step.
  double _previousOutstanding = 0;

  /// If a monthly bill for the current month already exists for this
  /// customer, it's loaded here so we don't create a duplicate — we
  /// just reuse its numbers in the report instead.
  MonthlyBill? _existingMonthlyBill;

  bool _loadingBilling = false;
  String? _billingLoadError;

  final TextEditingController _palaiChargesController = TextEditingController();
  final TextEditingController _otherChargesController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _goatsStream = FirestoreService.instance.goatsForCustomerStream(
      widget.farmId,
      widget.customer.id,
    );
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    _palaiChargesController.dispose();
    _otherChargesController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  // ================================================================
  // SELECTION (Phase 1)
  // ================================================================

  void _toggleSelectAll(List<PalaiGoat> goats) {
    setState(() {
      if (_selectedIds.length == goats.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(goats.map((g) => g.id));
      }
    });
  }

  void _toggleGoat(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  List<PalaiGoat> get _selectedGoats =>
      _lastLoadedGoats.where((g) => _selectedIds.contains(g.id)).toList();

  Future<void> _continueToCapture() async {
    if (_selectedGoats.isEmpty) {
      _showSnack('Select at least one goat to include in the report.');
      return;
    }

    setState(() {
      _phase = _Phase.capturing;
      _loadingPrevious = true;
    });

    try {
      final results = await Future.wait(_selectedGoats.map(_fetchPrevious));
      await _loadBillingInfo();
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _selectedGoats.length; i++) {
          _previousByGoatId[_selectedGoats[i].id] = results[i];
        }
        _loadingPrevious = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.selecting;
        _loadingPrevious = false;
      });
      _showSnack('Could not load previous report data: $e', isError: true);
    }
  }

  /// Loads the customer's current pending/outstanding amount, and checks
  /// whether a monthly bill already exists for the current month so we
  /// don't accidentally create a duplicate one.
  Future<void> _loadBillingInfo() async {
    setState(() {
      _loadingBilling = true;
      _billingLoadError = null;
    });

    try {
      final freshCustomer = await FirestoreService.instance.getCustomer(
        widget.farmId,
        widget.customer.id,
      );

      final now = DateTime.now();
      final billId = _monthlyBillId(widget.customer.id, now.year, now.month);

      final existingBill = await MonthlyBillingService.instance.getMonthlyBill(
        farmId: widget.farmId,
        billId: billId,
      );

      if (!mounted) return;

      setState(() {
        _previousOutstanding = freshCustomer?.pendingAmount ?? widget.customer.pendingAmount;
        _existingMonthlyBill = existingBill;
        _loadingBilling = false;

        if (existingBill != null) {
          _palaiChargesController.text = existingBill.palaiCharges.toStringAsFixed(2);
          _otherChargesController.text = existingBill.otherCharges.toStringAsFixed(2);
          _discountController.text = existingBill.discount.toStringAsFixed(2);
        } else {
          final suggested = freshCustomer?.price ?? widget.customer.price;
          _palaiChargesController.text = suggested > 0 ? suggested.toStringAsFixed(2) : '';
          _otherChargesController.text = '0';
          _discountController.text = '0';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBilling = false;
        _billingLoadError = 'Could not load billing info: $e';
      });
    }
  }

  /// Mirrors MonthlyBillingService's private document-ID format so we can
  /// look up "does this month already have a bill" without needing a new
  /// public method on the service.
  String _monthlyBillId(String customerId, int year, int month) {
    final periodKey = '$year-${month.toString().padLeft(2, '0')}';
    return 'monthly_${customerId}_$periodKey';
  }

  Future<_PreviousInfo> _fetchPrevious(PalaiGoat goat) async {
    final latestReport = await FirestoreService.instance.getLatestGoatReport(
      widget.farmId,
      widget.customer.id,
      goat.id,
    );
    final latestHealth = await FirestoreService.instance.getLatestHealthRecord(
      widget.farmId,
      widget.customer.id,
      goat.id,
    );

    if (latestReport != null && latestReport.images.isNotEmpty) {
      return _PreviousInfo(
        bytes: latestReport.images.first.bytes,
        label: 'From Previous Report',
        date: latestReport.generatedAt,
        weight: latestReport.endWeight ?? goat.weightAtCheckIn,
        latestHealthRecord: latestHealth,
      );
    }

    return _PreviousInfo(
      bytes: goat.beforeImage ?? Uint8List(0),
      label: 'Check-In Photo',
      date: goat.checkInDate,
      weight: goat.weightAtCheckIn,
      latestHealthRecord: latestHealth,
    );
  }

  void _backToSelecting() {
    setState(() {
      _phase = _Phase.selecting;
      _previousByGoatId.clear();
      _capturedByGoatId.clear();
      for (final controller in _weightControllers.values) {
        controller.dispose();
      }
      _weightControllers.clear();

      _existingMonthlyBill = null;
      _billingLoadError = null;
      _palaiChargesController.clear();
      _otherChargesController.clear();
      _discountController.clear();
    });
  }

  // ================================================================
  // CAPTURE (Phase 2)
  // ================================================================

  Future<void> _capturePhoto(String goatId) async {
    setState(() => _capturingGoatId = goatId);
    try {
      final picked = await ImageService.instance.pickFromCamera(
        maxStoredBytes: 200 * 1024,
        maxDimension: 480,
      );
      if (picked != null && mounted) {
        setState(() => _capturedByGoatId[goatId] = picked);
      }
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Could not capture photo. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _capturingGoatId = null);
    }
  }

  bool get _allPhotosCaptured =>
      _selectedGoats.every((g) => _capturedByGoatId.containsKey(g.id));

  /// Controller for a given goat's "new weight" field. Created once,
  /// pre-filled with the previous known weight (if any) as a starting
  /// point so the owner only has to adjust it rather than type from
  /// scratch — but they can still clear it and leave it blank.
  TextEditingController _weightControllerFor(String goatId) {
    return _weightControllers.putIfAbsent(goatId, () {
      final previous = _previousByGoatId[goatId];
      final initial = previous?.weight;
      return TextEditingController(
        text: initial != null ? initial.toStringAsFixed(1) : '',
      );
    });
  }

  double? _enteredWeight(String goatId) {
    final controller = _weightControllers[goatId];
    if (controller == null) return null;
    return double.tryParse(controller.text.trim());
  }

  bool get _allWeightsEntered => _selectedGoats.every((g) {
    final weight = _enteredWeight(g.id);
    return weight != null && weight > 0;
  });

  double? get _enteredPalaiCharges =>
      double.tryParse(_palaiChargesController.text.trim());

  double get _enteredOtherCharges =>
      double.tryParse(_otherChargesController.text.trim()) ?? 0;

  double get _enteredDiscount =>
      double.tryParse(_discountController.text.trim()) ?? 0;

  /// True once billing is ready to include in the report: either an
  /// existing bill for this month was found (nothing more to enter), or
  /// the owner has typed a valid Palai amount for a fresh bill.
  bool get _billingReady {
    if (_loadingBilling) return false;
    if (_existingMonthlyBill != null) return true;
    final palai = _enteredPalaiCharges;
    return palai != null && palai > 0;
  }

  bool get _readyToGenerate =>
      _allPhotosCaptured && _allWeightsEntered && _billingReady;

  // ================================================================
  // GENERATE
  // ================================================================

  Future<void> _generate({required bool share}) async {
    if (!_allPhotosCaptured) {
      _showSnack('Take a photo for every goat before generating the report.');
      return;
    }

    if (!_allWeightsEntered) {
      _showSnack('Enter the current weight for every goat before generating the report.');
      return;
    }

    if (!_billingReady) {
      _showSnack('Enter this month\'s Palai amount before generating the report.');
      return;
    }

    setState(() => _generating = true);

    try {
      final farm = await FirestoreService.instance.getFarmById(widget.farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();
      final now = DateTime.now();

      // ------------------------------------------------------------
      // BILLING — reuse this month's bill if one already exists,
      // otherwise create it now. Creating it also folds in the
      // customer's old pending amount and writes the new outstanding
      // total straight to the customer profile.
      // ------------------------------------------------------------
      MonthlyBill monthlyBill;
      if (_existingMonthlyBill != null) {
        monthlyBill = _existingMonthlyBill!;
      } else {
        try {
          monthlyBill = await MonthlyBillingService.instance.createMonthlyBill(
            farmId: widget.farmId,
            customerId: widget.customer.id,
            year: now.year,
            month: now.month,
            palaiCharges: _enteredPalaiCharges!,
            otherCharges: _enteredOtherCharges,
            discount: _enteredDiscount,
            goatCount: _selectedGoats.length,
            notes: 'Auto-generated with Progress Report.',
          );
        } on StateError {
          // Someone else generated this month's bill in the meantime —
          // fall back to reading it instead of failing the whole report.
          final billId = _monthlyBillId(widget.customer.id, now.year, now.month);
          final existing = await MonthlyBillingService.instance.getMonthlyBill(
            farmId: widget.farmId,
            billId: billId,
          );
          if (existing == null) rethrow;
          monthlyBill = existing;
        }
      }

      final entries = <GoatProgressEntry>[];

      for (final goat in _selectedGoats) {
        final previous = _previousByGoatId[goat.id]!;
        final captured = _capturedByGoatId[goat.id]!;
        final currentWeight = _enteredWeight(goat.id)!;

        entries.add(GoatProgressEntry(
          goat: goat,
          previousImageBytes: previous.bytes,
          previousLabel: previous.label,
          previousDate: previous.date,
          previousWeight: previous.weight,
          currentImageBytes: captured.bytes,
          currentDate: now,
          currentWeight: currentWeight,
          latestHealthRecord: previous.latestHealthRecord,
        ));

        // Save this goat's own report under its existing report history —
        // same path/pattern as GenerateReportScreen — so reportStatus /
        // reportsCount stay accurate and the next progress report finds
        // this photo as its "previous" photo.
        final report = GoatReport(
          id: '',
          type: GoatReportType.progress,
          fromDate: previous.date,
          toDate: now,
          generatedAt: now,
          startWeight: previous.weight,
          endWeight: currentWeight,
          healthStatus: previous.latestHealthRecord?.healthStatus.isNotEmpty == true
              ? previous.latestHealthRecord!.healthStatus
              : goat.healthStatus,
          images: [
            ReportImage(
              bytes: captured.bytes,
              contentType: captured.contentType,
              label: 'Report Day Photo',
            ),
          ],
        );

        await FirestoreService.instance.saveGoatReport(
          widget.farmId,
          widget.customer.id,
          goat.id,
          report,
        );

        // Record the freshly-entered weight as a health record too, so it
        // becomes the goat's new "current weight" everywhere in the app
        // (goat list, health history, and the next progress report's
        // "previous weight").
        await FirestoreService.instance.addHealthRecord(
          widget.farmId,
          widget.customer.id,
          goat.id,
          HealthRecordEntry(
            id: '',
            weight: currentWeight,
            vaccination: '',
            deworming: '',
            hoofCutting: '',
            medicineGiven: '',
            healthStatus: previous.latestHealthRecord?.healthStatus.isNotEmpty == true
                ? previous.latestHealthRecord!.healthStatus
                : goat.healthStatus,
            doctorNotes: 'Recorded during Progress Report generation.',
            recordedAt: now,
          ),
        );
      }

      if (share) {
        await CustomerGoatsProgressReportPdfService.instance.share(
          customer: widget.customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
        );
      } else {
        await CustomerGoatsProgressReportPdfService.instance.preview(
          customer: widget.customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not generate report: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ================================================================
  // HELPERS
  // ================================================================

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: _phase == _Phase.capturing
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _generating ? null : _backToSelecting)
            : null,
        title: Text('Progress Report', style: AppTheme.heading(size: 17)),
      ),
      body: _phase == _Phase.selecting ? _buildSelectingPhase() : _buildCapturingPhase(),
    );
  }

  // -------------------------------------------------------------------
  // Phase 1 UI — select goats (same shape as CustomerGoatsReportScreen)
  // -------------------------------------------------------------------

  Widget _buildSelectingPhase() {
    return StreamBuilder<List<PalaiGoat>>(
      stream: _goatsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
        }

        final goats = snapshot.data ?? [];
        _lastLoadedGoats = goats;

        if (_selectedIds.isEmpty && goats.isNotEmpty) {
          _selectedIds.addAll(goats.map((g) => g.id));
        }

        if (goats.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          children: [
            _buildHeaderCard(goats),
            Expanded(child: _buildGoatsSelectionList(goats)),
            _buildSelectionBottomBar(),
          ],
        );
      },
    );
  }

  Widget _buildHeaderCard(List<PalaiGoat> goats) {
    final allSelected = _selectedIds.length == goats.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.customer.name, style: AppTheme.heading(size: 15)),
                  const SizedBox(height: 3),
                  Text(
                    '${_selectedIds.length} of ${goats.length} goats selected',
                    style: AppTheme.body(size: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _toggleSelectAll(goats),
              child: Text(allSelected ? 'Deselect All' : 'Select All'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoatsSelectionList(List<PalaiGoat> goats) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: goats.length,
      itemBuilder: (context, index) {
        final goat = goats[index];
        final selected = _selectedIds.contains(goat.id);
        final goatId = goat.goatCode.trim().isNotEmpty
            ? goat.goatCode
            : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: AppTheme.card(radius: 14),
          child: CheckboxListTile(
            value: selected,
            onChanged: (_) => _toggleGoat(goat.id),
            activeColor: AppColors.primaryGreen,
            controlAffinity: ListTileControlAffinity.leading,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    goat.name.trim().isNotEmpty ? goat.name : goatId,
                    style: AppTheme.heading(size: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ID: $goatId',
                    style: AppTheme.body(size: 10, color: AppColors.primaryGreen),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${goat.breed.isNotEmpty ? goat.breed : 'Breed unknown'} • '
                  '${goat.healthStatus.isNotEmpty ? goat.healthStatus : 'No health status'}',
              style: AppTheme.body(size: 11, color: AppColors.textMuted),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectionBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loadingPrevious ? null : _continueToCapture,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Continue to Photos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.primaryGreen.withOpacity(0.10), shape: BoxShape.circle),
              child: const Icon(Icons.pets_outlined, size: 35, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 14),
            Text('No goats found', style: AppTheme.heading(size: 15)),
            const SizedBox(height: 6),
            Text(
              'This customer has no goats under Palai yet.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Phase 2 UI — capture one photo per selected goat
  // -------------------------------------------------------------------

  Widget _buildCapturingPhase() {
    if (_loadingPrevious) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }

    final goats = _selectedGoats;
    final capturedCount = _capturedByGoatId.length;
    final weighedCount = goats.where((g) {
      final w = _enteredWeight(g.id);
      return w != null && w > 0;
    }).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(radius: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Take a photo & weight for each goat', style: AppTheme.heading(size: 14)),
                      const SizedBox(height: 3),
                      Text(
                        '$capturedCount of ${goats.length} photos • $weighedCount of ${goats.length} weights'
                            '${_billingReady ? ' • billing ready' : ' • billing pending'}',
                        style: AppTheme.body(size: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _readyToGenerate ? Icons.check_circle : Icons.camera_alt_outlined,
                  color: AppColors.primaryGreen,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: goats.length + 1,
            itemBuilder: (context, index) {
              if (index == goats.length) {
                return _buildBillingCard();
              }
              return _captureTile(goats[index]);
            },
          ),
        ),
        _buildCaptureBottomBar(),
      ],
    );
  }

  Widget _captureTile(PalaiGoat goat) {
    final captured = _capturedByGoatId[goat.id];
    final capturing = _capturingGoatId == goat.id;
    final previous = _previousByGoatId[goat.id];
    final goatId = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);
    final weightController = _weightControllerFor(goat.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (previous != null && previous.bytes.isNotEmpty)
                    ? Image.memory(previous.bytes, width: 52, height: 52, fit: BoxFit.cover)
                    : Container(
                  width: 52,
                  height: 52,
                  color: AppColors.lightGreen,
                  child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            goat.name.trim().isNotEmpty ? goat.name : goatId,
                            style: AppTheme.heading(size: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'ID: $goatId',
                            style: AppTheme.body(size: 9, color: AppColors.primaryGreen),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previous != null ? 'Previous: ${previous.label}' : '',
                      style: AppTheme.body(size: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: capturing ? null : () => _capturePhoto(goat.id),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: captured != null ? AppColors.primaryGreen : AppColors.primaryGreen.withOpacity(0.4),
                      width: captured != null ? 2 : 1.5,
                    ),
                  ),
                  child: capturing
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen))
                      : captured != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(10.5),
                    child: Image.memory(captured.bytes, fit: BoxFit.cover),
                  )
                      : const Icon(Icons.camera_alt, color: AppColors.primaryGreen, size: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last weight',
                      style: AppTheme.body(size: 10, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previous?.weight != null
                          ? '${previous!.weight!.toStringAsFixed(1)} kg'
                          : 'Not recorded',
                      style: AppTheme.heading(size: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: AppTheme.heading(size: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'New weight (kg)',
                    labelStyle: AppTheme.body(size: 11, color: AppColors.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.monitor_weight_outlined, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _currency(double value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  // ------------------------------------------------------------------
  // BILLING CARD — old pending amount + this month's Palai amount
  // ------------------------------------------------------------------

  Widget _buildBillingCard() {
    final existing = _existingMonthlyBill;
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.primaryGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Monthly Billing — $monthLabel', style: AppTheme.heading(size: 14)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            existing != null
                ? 'A bill for this month already exists — its amount will be used in the report.'
                : 'This will create this month\'s bill and add it to the customer\'s pending amount.',
            style: AppTheme.body(size: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),

          if (_loadingBilling)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
              ),
            )
          else if (_billingLoadError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_billingLoadError!, style: AppTheme.body(size: 11, color: AppColors.error)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadBillingInfo,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            )
          else ...[
              _billingRow('Old Pending Amount', _currency(_previousOutstanding)),
              const SizedBox(height: 10),
              if (existing != null) ...[
                _billingRow('This Month\'s Palai Charges', _currency(existing.palaiCharges)),
                if (existing.otherCharges > 0) _billingRow('Other Charges', _currency(existing.otherCharges)),
                if (existing.discount > 0) _billingRow('Discount', '- ${_currency(existing.discount)}'),
                const Divider(height: 20),
                _billingRow('Total Outstanding', _currency(existing.totalDue - existing.amountPaid), bold: true),
              ] else ...[
                _billingField(
                  controller: _palaiChargesController,
                  label: 'This Month\'s Palai Amount',
                  icon: Icons.home_work_outlined,
                ),
                const SizedBox(height: 10),
                _billingField(
                  controller: _otherChargesController,
                  label: 'Other Charges (optional)',
                  icon: Icons.add_card_outlined,
                ),
                const SizedBox(height: 10),
                _billingField(
                  controller: _discountController,
                  label: 'Discount (optional)',
                  icon: Icons.discount_outlined,
                ),
                const Divider(height: 24),
                _billingRow(
                  'Total Outstanding (after this bill)',
                  _currency(
                    _previousOutstanding +
                        (_enteredPalaiCharges ?? 0) +
                        _enteredOtherCharges -
                        _enteredDiscount,
                  ),
                  bold: true,
                ),
              ],
            ],
        ],
      ),
    );
  }

  Widget _billingRow(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold ? AppTheme.heading(size: 13) : AppTheme.body(size: 12, color: AppColors.textMuted),
          ),
        ),
        Text(
          value,
          style: bold
              ? AppTheme.heading(size: 14).copyWith(color: AppColors.primaryGreen)
              : AppTheme.body(size: 12),
        ),
      ],
    );
  }

  Widget _billingField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        prefixText: '₹ ',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _buildCaptureBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_generating || !_readyToGenerate) ? null : () => _generate(share: false),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.primaryGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_generating || !_readyToGenerate) ? null : () => _generate(share: true),
                icon: _generating
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.share_outlined),
                label: Text(_generating ? 'Generating...' : 'Share Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}