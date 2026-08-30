import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/monthly_bill_model.dart' show MonthlyBill, GoatBillingLine;
import '../../models/palai_models.dart';
import '../../models/report_models.dart';
import '../../services/customer_goats_progress_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/monthly_billing_service.dart';
import '../../widgets/fast_route.dart';
import 'monthly_bill_generate_screen.dart';

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
  // CURRENT-MONTH CALCULATION
  //
  //   Current Month Palai (per goat, editable)
  //         +
  //   Current Outstanding (customer's current balance — zero if none)
  //         −
  //   Current Advance (customer's current advance — zero if none)
  //         =
  //   Current Amount Due
  //
  // IMPORTANT: this is a current-period calculation only. Historical
  // payments and old bills are NEVER summed/subtracted again here —
  // Current Outstanding and Current Advance are read fresh from the
  // customer's live profile and nothing else feeds into them.
  // ------------------------------------------------------------------

  /// One editable "Monthly Palai Amount" controller per selected goat.
  /// Seeded from that goat's registered [PalaiGoat.pricing] as a
  /// starting point, but the owner can freely change it — this is the
  /// custom, per-goat, current-month Palai amount, not a fixed default.
  final Map<String, TextEditingController> _palaiControllers = {};

  /// The customer's CURRENT outstanding balance, re-fetched fresh (not
  /// from `widget.customer`, which may be stale) the moment we enter the
  /// capture step. This is the customer's real current balance — never
  /// a sum of old bills, old payments, or previous months.
  double _currentOutstanding = 0;

  /// The customer's CURRENT advance balance (credit), re-fetched fresh at
  /// the same time as [_currentOutstanding]. Applied against the total
  /// before the remainder becomes the customer's new outstanding amount.
  double _currentAdvanceAvailable = 0;

  /// If a monthly bill for the current month already exists for this
  /// customer, it's loaded here so we don't create a duplicate — we
  /// just reuse its numbers in the report instead.
  MonthlyBill? _existingMonthlyBill;

  bool _loadingBilling = false;
  String? _billingLoadError;

  /// Current Outstanding and Current Advance — the two customer-level
  /// numbers the owner can edit for a fresh bill. Prefilled from the
  /// customer's live balance as a starting point (zero when there is
  /// none) but fully customizable; whatever is typed here is exactly
  /// what gets saved, alongside the goat-wise Palai amounts. There is no
  /// "amount paid" field here — this entry only records what is owed,
  /// never a payment.
  final TextEditingController _outstandingController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController();

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
    for (final controller in _palaiControllers.values) {
      controller.dispose();
    }
    _outstandingController.dispose();
    _advanceController.dispose();
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
        _currentOutstanding = freshCustomer?.pendingAmount ?? widget.customer.pendingAmount;
        _currentAdvanceAvailable = freshCustomer?.advanceAmount ?? widget.customer.advanceAmount;
        _existingMonthlyBill = existingBill;
        _loadingBilling = false;

        if (existingBill == null) {
          // Current Outstanding and Current Advance are prefilled ONLY
          // from the customer's live current balance — zero if there is
          // none. This month's goat-wise Palai amount is a completely
          // separate line item (see _palaiControllers) and must NEVER be
          // folded into Current Outstanding here. That mixing is exactly
          // the old bug: it made the outstanding figure look like it
          // already contained this month's charges, so the final total
          // silently double-counted them.
          _outstandingController.text = _currentOutstanding.toStringAsFixed(2);
          _advanceController.text = _currentAdvanceAvailable.toStringAsFixed(2);
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

  /// Sends the owner to the goat-wise Monthly Billing screen to finish
  /// or fix this month's bill, then refreshes this screen's billing
  /// info when they come back — so if they fixed a ₹0-Palai bill there,
  /// this screen (and the eventual PDF) picks up the corrected numbers
  /// immediately instead of still showing the stale snapshot.
  ///
  /// - If a bill already exists for this month with ₹0 Current Month
  ///   Palai, this opens it in EDIT mode (same bill document gets
  ///   corrected in place).
  /// - Otherwise it opens in CREATE mode for this month.
  ///
  /// Either way `cameFromProgressReport: true` is passed so that screen
  /// shows "Done" instead of "Generate Monthly Bill" — the owner is
  /// being sent there to finish something, not to start a fresh,
  /// independent billing flow.
  Future<void> _openMonthlyBillingToFix() async {
    final now = DateTime.now();
    final existing = _existingMonthlyBill;
    final needsFix = existing != null && existing.palaiCharges <= 0;

    await Navigator.of(context).push(
      fastRoute(
        MonthlyBillGenerateScreen(
          farmId: widget.farmId,
          customerId: widget.customer.id,
          customerName: widget.customer.name,
          goatCount: _selectedGoats.length,
          editBillId: needsFix ? existing.id : null,
          cameFromProgressReport: true,
        ),
      ),
    );

    if (!mounted) return;
    await _loadBillingInfo();
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
      for (final controller in _palaiControllers.values) {
        controller.dispose();
      }
      _palaiControllers.clear();

      _existingMonthlyBill = null;
      _billingLoadError = null;
      _currentOutstanding = 0;
      _currentAdvanceAvailable = 0;
      _outstandingController.clear();
      _advanceController.clear();
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

  /// Controller for a given goat's "Monthly Palai Amount" — the custom,
  /// editable, current-month Palai amount for that goat. Seeded from the
  /// goat's registered [PalaiGoat.pricing] the first time it's built, as
  /// a starting point only; the owner can freely change it to whatever
  /// this month's real amount is (e.g. GP-11 → ₹2,800). Changing one
  /// goat's amount never affects any other goat's amount or total.
  TextEditingController _palaiControllerFor(PalaiGoat goat) {
    return _palaiControllers.putIfAbsent(
      goat.id,
          () => TextEditingController(text: goat.pricing.toStringAsFixed(2)),
    );
  }

  double _enteredPalai(PalaiGoat goat) {
    final controller = _palaiControllers[goat.id];
    if (controller == null) return goat.pricing;
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  /// Sum of each *selected* goat's current-month Palai amount, exactly
  /// as typed in that goat's own "Monthly Palai Amount" field. This is
  /// the ONLY thing that feeds "Current Month Palai" — it is a
  /// completely separate line from Current Outstanding and Current
  /// Advance below, and is never combined with them before display.
  double get _palaiChargesTotal =>
      _selectedGoats.fold<double>(0, (sum, g) => sum + _enteredPalai(g));

  /// Goat-wise breakdown, saved with the bill as a permanent snapshot —
  /// so the bill always shows exactly what each goat's Palai amount was
  /// that month, even if the goat's registered price changes later.
  List<GoatBillingLine> get _goatBreakdown => _selectedGoats.map((g) {
    final label = g.name.trim().isNotEmpty
        ? g.name
        : (g.goatCode.trim().isNotEmpty ? g.goatCode : g.tagNumber);
    return GoatBillingLine(
      goatId: g.id,
      label: label,
      palaiAmount: _enteredPalai(g),
    );
  }).toList();

  /// Current Outstanding and Current Advance, exactly as typed by the
  /// owner. Nothing else feeds into them — no reconstruction from old
  /// bills or payment history. Defaults to zero when the field is empty
  /// or the customer simply has no current outstanding/advance.
  double get _enteredOutstanding =>
      double.tryParse(_outstandingController.text.trim()) ?? 0;

  double get _enteredAdvance =>
      double.tryParse(_advanceController.text.trim()) ?? 0;

  /// Current Month Palai + Current Outstanding − Current Advance,
  /// floored at zero — this is exactly what gets written as the
  /// customer's new outstanding balance.
  double get _currentAmountDue =>
      (_palaiChargesTotal + _enteredOutstanding - _enteredAdvance)
          .clamp(0, double.infinity)
          .toDouble();

  /// True once billing is ready to include in the report: either an
  /// existing bill for this month was found (nothing more to enter), or
  /// every selected goat has a valid Palai amount entered.
  bool get _billingReady {
    if (_loadingBilling) return false;
    if (_existingMonthlyBill != null) return true;
    if (_selectedGoats.isEmpty) return false;
    return _selectedGoats.every((g) {
      final controller = _palaiControllers[g.id];
      if (controller == null) return false;
      final value = double.tryParse(controller.text.trim());
      return value != null && value >= 0;
    });
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
      _showSnack('Enter the Monthly Palai Amount for every goat before generating the report.');
      return;
    }

    setState(() => _generating = true);

    try {
      final farm = await FirestoreService.instance.getFarmById(widget.farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();
      final now = DateTime.now();

      // ------------------------------------------------------------
      // BILLING — reuse this month's bill if one already exists,
      // otherwise create it now from three separate numbers:
      //   - this month's goat-wise Palai total (_palaiChargesTotal)
      //   - Current Outstanding (the customer's real current balance)
      //   - Current Advance (the customer's real current advance)
      // These are never merged before being saved — see
      // createCurrentMonthMonthlyBill for the current-month-only rule.
      // ------------------------------------------------------------
      MonthlyBill monthlyBill;
      if (_existingMonthlyBill != null) {
        monthlyBill = _existingMonthlyBill!;
      } else {
        try {
          monthlyBill = await MonthlyBillingService.instance.createCurrentMonthMonthlyBill(
            farmId: widget.farmId,
            customerId: widget.customer.id,
            year: now.year,
            month: now.month,
            palaiCharges: _palaiChargesTotal,
            currentOutstanding: _enteredOutstanding,
            currentAdvance: _enteredAdvance,
            goatBreakdown: _goatBreakdown,
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

        // Only goats still boarded under this customer belong in a
        // Progress Report — a goat that has already been checked out is
        // no longer under Palai care, so it's excluded here (same rule
        // used by the checkout and billing screens).
        final goats = (snapshot.data ?? [])
            .where((g) => !g.isCheckedOut)
            .toList();
        _lastLoadedGoats = goats;

        if (_selectedIds.isEmpty && goats.isNotEmpty) {
          _selectedIds.addAll(goats.map((g) => g.id));
        }

        if (goats.isEmpty) {
          final hadAnyGoats = (snapshot.data ?? []).isNotEmpty;
          return _buildEmptyState(
            allCheckedOut: hadAnyGoats,
          );
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

  Widget _buildEmptyState({bool allCheckedOut = false}) {
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
            Text(allCheckedOut ? 'No active goats' : 'No goats found', style: AppTheme.heading(size: 15)),
            const SizedBox(height: 6),
            Text(
              allCheckedOut
                  ? 'All of this customer\'s goats have already been checked out of Palai.'
                  : 'This customer has no goats under Palai yet.',
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
              if (existing == null)
                IconButton(
                  tooltip: 'Re-fetch live Outstanding & Advance',
                  icon: _loadingBilling
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.refresh, size: 18, color: AppColors.textMuted),
                  onPressed: _loadingBilling ? null : _loadBillingInfo,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            existing != null
                ? 'A bill for $monthLabel was already generated for this customer. Its saved amounts are shown below exactly as recorded — generating this report again will NOT create a duplicate bill or change these numbers.'
                : 'Set each goat\'s Monthly Palai Amount below, then Current Outstanding and Current Advance. Nothing here is combined for you — you always see exactly what each figure is.',
            style: AppTheme.body(size: 11, color: AppColors.textMuted),
          ),
          if (existing == null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current Month Calculation Only — previous monthly payments and historical transactions are not included in this calculation.',
                      style: AppTheme.body(size: 10.5, color: AppColors.textDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              if (existing != null) ...[
                // ------------------------------------------------------
                // EXISTING BILL — every number below comes from THAT
                // bill's own saved snapshot (taken the moment it was
                // generated). We deliberately do NOT mix in the
                // customer's current/live outstanding here — the
                // customer's live pendingAmount already reflects this
                // bill (it was written into their profile when this
                // bill was created), so showing it again next to this
                // bill's numbers would double up and look
                // contradictory. There is no "amount paid" on bills
                // created this way, so none is shown.
                // ------------------------------------------------------
                if (existing.goatBreakdown.isNotEmpty) ...[
                  for (final line in existing.goatBreakdown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _billingRow(line.label, _currency(line.palaiAmount)),
                    ),
                  const Divider(height: 14),
                ],
                _billingRow('Current Month Palai', _currency(existing.palaiCharges)),
                const SizedBox(height: 4),
                _billingRow('Current Outstanding', _currency(existing.previousOutstanding)),
                const SizedBox(height: 4),
                _billingRow('Current Advance', '- ${_currency(existing.advanceApplied)}'),
                const Divider(height: 20),
                _billingRow('Current Amount Due', _currency(existing.totalDue), bold: true),
                if (existing.palaiCharges <= 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This month\'s bill shows ₹0 Current Month Palai. Fix it in Monthly Billing before sharing this report.',
                                style: AppTheme.body(size: 10.5, color: AppColors.textDark),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openMonthlyBillingToFix,
                            icon: const Icon(Icons.build_outlined, size: 16),
                            label: const Text('Fix in Monthly Billing'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              side: const BorderSide(color: AppColors.warning),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                // ------------------------------------------------------
                // NEW BILL — nothing has been saved to Firestore yet.
                // Each goat's Monthly Palai Amount, Current Outstanding,
                // and Current Advance are the editable numbers. They are
                // shown and summed SEPARATELY — never pre-combined —
                // right up until the moment the report is generated.
                // ------------------------------------------------------
                _buildGoatWisePalaiEntry(),
                const SizedBox(height: 14),
                _billingRow('Current Month Palai', _currency(_palaiChargesTotal), bold: true),
                const SizedBox(height: 14),
                _billingField(
                  controller: _outstandingController,
                  label: 'Current Outstanding',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                const SizedBox(height: 10),
                _billingField(
                  controller: _advanceController,
                  label: 'Current Advance',
                  icon: Icons.savings_outlined,
                ),
                const Divider(height: 24),
                _billingRow(
                  'Current Amount Due',
                  _currency(_currentAmountDue),
                  bold: true,
                ),
                const SizedBox(height: 4),
                Text(
                  'This will be saved to the customer\'s profile the moment you generate this report.',
                  style: AppTheme.body(size: 10, color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: _openMonthlyBillingToFix,
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Fill in Monthly Billing instead'),
                  ),
                ),
              ],
            ],
        ],
      ),
    );
  }

  /// Editable, per-goat "Monthly Palai Amount" entry. Each goat gets its
  /// own card clearly labelled with its ID and reference Palai Price
  /// (e.g. "GP-11 — Palai Price: ₹2,800"), plus its own editable amount
  /// textbox. Changing one goat's amount only ever affects that goat's
  /// row and the overall total — never another goat's amount.
  Widget _buildGoatWisePalaiEntry() {
    if (_selectedGoats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Monthly Palai Amount (per goat)', style: AppTheme.body(size: 11, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        for (final goat in _selectedGoats) ...[
          _goatPalaiCard(goat),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _goatPalaiCard(PalaiGoat goat) {
    final goatId = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);
    final label = goat.name.trim().isNotEmpty ? goat.name : goatId;
    final controller = _palaiControllerFor(goat);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "GP-11 — Palai Price: ₹2,800"
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label, style: AppTheme.heading(size: 13)),
                TextSpan(
                  text: '  •  Palai Price: ${_currency(goat.pricing)}',
                  style: AppTheme.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: AppTheme.heading(size: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Monthly Palai Amount',
              labelStyle: AppTheme.body(size: 11, color: AppColors.textMuted),
              prefixText: '₹ ',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
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