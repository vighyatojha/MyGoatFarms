import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../goat_icons.dart';
import '../../models/bill_settings_model.dart';
import '../../models/monthly_bill_model.dart' show MonthlyBill, GoatBillingLine;
import '../../models/palai_models.dart';
import '../../models/report_models.dart';
import '../../services/customer_goats_progress_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/monthly_billing_service.dart';
import '../../utils/palai_proration.dart';
import '../../widgets/fast_route.dart';
import 'monthly_bill_generate_screen.dart';

/// Consolidated Progress Report for all active goats belonging to one
/// Palai customer.
///
/// Important billing rule:
/// - All active goats are part of the current-month bill.
/// - If the current-month bill already exists but was created before a
///   newly-added active goat was registered, the missing goat is added to
///   that SAME bill document.
/// - Existing goat amounts already saved on the bill are preserved.
/// - A newly missing goat uses its current Palai pricing as its bill line.
/// - No duplicate monthly bill is created.
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

class _PreviousInfo {
  final Uint8List bytes;
  final String label;
  final DateTime date;
  final double? weight;
  final HealthRecordEntry? latestHealthRecord;
  final DateTime? latestVaccinationDate;
  final DateTime? latestHoofCuttingDate;
  final DateTime? latestHairTrimmingDate;
  final List<GoatWeightPoint> weightChain;

  const _PreviousInfo({
    required this.bytes,
    required this.label,
    required this.date,
    required this.weight,
    required this.latestHealthRecord,
    required this.weightChain,
    this.latestVaccinationDate,
    this.latestHoofCuttingDate,
    this.latestHairTrimmingDate,
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

  final Map<String, TextEditingController> _weightControllers = {};
  final Map<String, TextEditingController> _palaiControllers = {};

  final TextEditingController _outstandingController =
  TextEditingController();
  final TextEditingController _advanceController =
  TextEditingController();

  double _currentOutstanding = 0;
  double _currentAdvanceAvailable = 0;

  MonthlyBill? _existingMonthlyBill;

  bool _loadingBilling = false;
  String? _billingLoadError;
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

  // =====================================================================
  // SELECTION
  // =====================================================================

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

  List<PalaiGoat> get _selectedGoats => _lastLoadedGoats
      .where((g) => _selectedIds.contains(g.id))
      .toList();

  // =====================================================================
  // BILLING
  // =====================================================================

  String _monthlyBillId(String customerId, int year, int month) {
    final periodKey = '$year-${month.toString().padLeft(2, '0')}';
    return 'monthly_${customerId}_$periodKey';
  }

  String _goatLabel(PalaiGoat goat) {
    return goat.name.trim().isNotEmpty
        ? goat.name.trim()
        : (goat.goatCode.trim().isNotEmpty
        ? goat.goatCode.trim()
        : (goat.tagNumber.trim().isNotEmpty
        ? goat.tagNumber.trim()
        : goat.id));
  }

  /// FIX:
  /// The old Progress Report screen treated an already-generated monthly
  /// bill as permanently final even when a new active goat had been added
  /// to Palai afterwards.
  ///
  /// Example:
  ///   bill has 3 goatBreakdown lines
  ///   active Palai goats = 4
  ///
  /// The fourth goat must be added to the existing current-month bill.
  ///
  /// Existing lines are never changed. Only active goats whose goatId is
  /// missing from the saved breakdown are appended, using their current
  /// Palai pricing.
  Future<MonthlyBill> _syncMissingActiveGoatsIntoBill({
    required MonthlyBill bill,
    required List<PalaiGoat> activeGoats,
  }) async {
    final missingGoats = activeGoats.where((goat) {
      return !bill.goatBreakdown.any(
            (line) => line.goatId == goat.id,
      );
    }).toList();

    if (missingGoats.isEmpty) {
      return bill;
    }

    final updatedBreakdown = <GoatBillingLine>[
      ...bill.goatBreakdown,
    ];

    double addedPalai = 0;

    for (final goat in missingGoats) {
      // A goat that joined part-way through the bill's month is charged
      // only for the days it is here: monthly price ÷ days in month ×
      // days remaining (joining day included).
      final proration = PalaiProrationCalculator.calculate(
        monthlyCharge: goat.pricing < 0 ? 0.0 : goat.pricing.toDouble(),
        joiningDate: goat.checkInDate,
        year: bill.year,
        month: bill.month,
      );
      final double amount = proration.amount;

      updatedBreakdown.add(
        GoatBillingLine.forGoat(
          goatId: goat.id,
          label: _goatLabel(goat),
          amount: amount,
          proration: proration,
        ),
      );

      addedPalai += amount;
    }

    final updatedBill =
    await MonthlyBillingService.instance.updateCurrentMonthMonthlyBill(
      farmId: widget.farmId,
      customerId: widget.customer.id,
      billId: bill.id,

      // Preserve everything already billed and only add the missing
      // active goats' Palai charges.
      palaiCharges: bill.palaiCharges + addedPalai,

      // Preserve the original billing snapshot. Do NOT use the live
      // pendingAmount here because this bill already affected it.
      currentOutstanding: bill.previousOutstanding,

      // Passing the bill's own previous advance contribution lets the
      // service restore/re-apply the same advance without draining it
      // twice.
      currentAdvance: bill.advanceApplied,

      goatBreakdown: updatedBreakdown,
      goatCount: updatedBreakdown.length,
      notes: bill.notes,
    );

    return updatedBill;
  }

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
      final billId = _monthlyBillId(
        widget.customer.id,
        now.year,
        now.month,
      );

      MonthlyBill? existingBill =
      await MonthlyBillingService.instance.getMonthlyBill(
        farmId: widget.farmId,
        billId: billId,
      );

      // IMPORTANT:
      // Always compare the existing current-month bill against the
      // currently active Palai goats. This is what fixes the exact case
      // shown in the screenshot: 4 active goats but only 3 saved bill
      // lines.
      if (existingBill != null) {
        existingBill = await _syncMissingActiveGoatsIntoBill(
          bill: existingBill,
          activeGoats: _lastLoadedGoats,
        );
      }

      if (!mounted) return;

      setState(() {
        _currentOutstanding =
            freshCustomer?.pendingAmount ?? widget.customer.pendingAmount;
        _currentAdvanceAvailable =
            freshCustomer?.advanceAmount ?? widget.customer.advanceAmount;

        _existingMonthlyBill = existingBill;
        _loadingBilling = false;

        if (existingBill == null) {
          _outstandingController.text =
              _currentOutstanding.toStringAsFixed(2);
          _advanceController.text =
              _currentAdvanceAvailable.toStringAsFixed(2);
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

  Future<void> _openMonthlyBillingToFix() async {
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

  // =====================================================================
  // PREVIOUS GOAT DATA
  // =====================================================================

  Future<_PreviousInfo> _fetchPrevious(PalaiGoat goat) async {
    final results = await Future.wait([
      FirestoreService.instance.getLatestGoatReport(
        widget.farmId,
        widget.customer.id,
        goat.id,
      ),
      FirestoreService.instance.getLatestHealthRecord(
        widget.farmId,
        widget.customer.id,
        goat.id,
      ),
      FirestoreService.instance.getLatestVaccinationDate(
        widget.farmId,
        widget.customer.id,
        goat.id,
      ),
      FirestoreService.instance.getLatestHoofCuttingDate(
        widget.farmId,
        widget.customer.id,
        goat.id,
      ),
      FirestoreService.instance.getLatestHairTrimmingDate(
        widget.farmId,
        widget.customer.id,
        goat.id,
      ),
      FirestoreService.instance
          .goatReportsStream(
        widget.farmId,
        widget.customer.id,
        goat.id,
      )
          .first,
    ]);

    final latestReport = results[0] as GoatReport?;
    final latestHealth = results[1] as HealthRecordEntry?;
    final latestVaccinationDate = results[2] as DateTime?;
    final latestHoofCuttingDate = results[3] as DateTime?;
    final latestHairTrimmingDate = results[4] as DateTime?;
    final allReports = results[5] as List<GoatReport>;

    final weightChain = _buildWeightChain(goat, allReports);

    if (latestReport != null && latestReport.images.isNotEmpty) {
      return _PreviousInfo(
        bytes: latestReport.images.first.bytes,
        label: 'From Previous Report',
        date: latestReport.generatedAt,
        weight: latestReport.endWeight ?? goat.weightAtCheckIn,
        latestHealthRecord: latestHealth,
        weightChain: weightChain,
        latestVaccinationDate: latestVaccinationDate,
        latestHoofCuttingDate: latestHoofCuttingDate,
        latestHairTrimmingDate: latestHairTrimmingDate,
      );
    }

    return _PreviousInfo(
      bytes: goat.beforeImage ?? Uint8List(0),
      label: 'Check-In Photo',
      date: goat.checkInDate,
      weight: goat.weightAtCheckIn,
      latestHealthRecord: latestHealth,
      weightChain: weightChain,
      latestVaccinationDate: latestVaccinationDate,
      latestHoofCuttingDate: latestHoofCuttingDate,
      latestHairTrimmingDate: latestHairTrimmingDate,
    );
  }

  List<GoatWeightPoint> _buildWeightChain(
      PalaiGoat goat,
      List<GoatReport> reports,
      ) {
    final points = <GoatWeightPoint>[
      GoatWeightPoint(
        date: goat.farmArrivalDate ?? goat.checkInDate,
        weight: goat.weightAtCheckIn,
        source: 'Arrival',
      ),
      for (final report in reports)
        if (report.endWeight != null)
          GoatWeightPoint(
            date: report.generatedAt,
            weight: report.endWeight!,
            source: report.notes.isNotEmpty ? report.notes : 'Report',
          ),
    ];

    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

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
      final results = await Future.wait(
        _selectedGoats.map(_fetchPrevious),
      );

      // Billing is loaded only after _lastLoadedGoats has been populated
      // from the same active-goat stream, so the bill comparison sees all
      // current Palai goats.
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

      _showSnack(
        'Could not load previous report data: $e',
        isError: true,
      );
    }
  }

  // =====================================================================
  // CAPTURE / WEIGHT
  // =====================================================================

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
      _showSnack(
        'Could not capture photo. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _capturingGoatId = null);
      }
    }
  }

  TextEditingController _weightControllerFor(String goatId) {
    return _weightControllers.putIfAbsent(goatId, () {
      final previous = _previousByGoatId[goatId]?.weight;

      return TextEditingController(
        text: previous != null ? previous.toStringAsFixed(1) : '',
      );
    });
  }

  double? _enteredWeight(String goatId) {
    final controller = _weightControllers[goatId];
    if (controller == null) return null;

    return double.tryParse(controller.text.trim());
  }

  bool get _allPhotosCaptured => _selectedGoats.every(
        (goat) => _capturedByGoatId.containsKey(goat.id),
  );

  bool get _allWeightsEntered => _selectedGoats.every((goat) {
    final weight = _enteredWeight(goat.id);
    return weight != null && weight > 0;
  });

  TextEditingController _palaiControllerFor(PalaiGoat goat) {
    return _palaiControllers.putIfAbsent(
      goat.id,
          () => TextEditingController(
        text: _prorationFor(goat).amount.toStringAsFixed(2),
      ),
    );
  }

  /// Pro-rated Palai charge for [goat] in the current billing month:
  /// monthly price ÷ days in month × days the goat has been at the farm.
  PalaiProration _prorationFor(PalaiGoat goat) {
    final now = DateTime.now();
    return PalaiProrationCalculator.calculate(
      monthlyCharge: goat.pricing,
      joiningDate: goat.checkInDate,
      year: now.year,
      month: now.month,
    );
  }

  /// e.g. "Joined 11 Apr 2026 • 20 of 30 days • ₹3,000 ÷ 30 × 20"
  String _prorationNote(PalaiGoat goat) {
    final p = _prorationFor(goat);
    final joined = DateFormat('d MMM yyyy').format(goat.checkInDate);
    return 'Joined $joined • ${p.label} • '
        '${_currency(p.monthlyCharge)} ÷ ${p.daysInMonth} × ${p.billableDays}';
  }

  double _enteredPalai(PalaiGoat goat) {
    final controller = _palaiControllers[goat.id];

    if (controller == null) {
      return _prorationFor(goat).amount;
    }

    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _palaiChargesTotal => _selectedGoats.fold<double>(
    0,
        (sum, goat) => sum + _enteredPalai(goat),
  );

  List<GoatBillingLine> get _goatBreakdown => _selectedGoats.map((goat) {
    return GoatBillingLine.forGoat(
      goatId: goat.id,
      label: _goatLabel(goat),
      amount: _enteredPalai(goat),
      proration: _prorationFor(goat),
    );
  }).toList();

  double get _enteredOutstanding =>
      double.tryParse(_outstandingController.text.trim()) ?? 0;

  double get _enteredAdvance =>
      double.tryParse(_advanceController.text.trim()) ?? 0;

  double get _currentAmountDue => (_palaiChargesTotal +
      _enteredOutstanding -
      _enteredAdvance)
      .clamp(0, double.infinity)
      .toDouble();

  bool get _billingReady {
    if (_loadingBilling) return false;

    if (_existingMonthlyBill != null) {
      return _existingMonthlyBill!.goatBreakdown.length >=
          _selectedGoats.length;
    }

    if (_selectedGoats.isEmpty) return false;

    return _selectedGoats.every((goat) {
      final controller = _palaiControllers[goat.id];

      if (controller == null) return false;

      final value = double.tryParse(controller.text.trim());

      return value != null && value >= 0;
    });
  }

  bool get _readyToGenerate =>
      _allPhotosCaptured &&
          _allWeightsEntered &&
          _billingReady;

  // =====================================================================
  // GENERATE
  // =====================================================================

  Future<void> _generate({required bool share}) async {
    if (!_allPhotosCaptured) {
      _showSnack(
        'Take a photo for every goat before generating the report.',
      );
      return;
    }

    if (!_allWeightsEntered) {
      _showSnack(
        'Enter the current weight for every goat before generating the report.',
      );
      return;
    }

    if (!_billingReady) {
      _showSnack(
        'Billing is not ready for every active goat.',
      );
      return;
    }

    setState(() => _generating = true);

    try {
      final farm = await FirestoreService.instance.getFarmById(
        widget.farmId,
      );

      final originalBillSettings =
          farm?.billSettings ?? const BillSettings();

      final billSettings = originalBillSettings.billLogo != null &&
          originalBillSettings.billLogo!.isNotEmpty
          ? originalBillSettings
          : originalBillSettings.copyWith(
        billLogo: farm?.profileImage,
        billLogoContentType:
        farm?.profileImageContentType ?? 'image/jpeg',
      );

      final now = DateTime.now();

      MonthlyBill monthlyBill;

      if (_existingMonthlyBill != null) {
        monthlyBill = _existingMonthlyBill!;
      } else {
        try {
          monthlyBill =
          await MonthlyBillingService.instance.createCurrentMonthMonthlyBill(
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
          final billId = _monthlyBillId(
            widget.customer.id,
            now.year,
            now.month,
          );

          final existing =
          await MonthlyBillingService.instance.getMonthlyBill(
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

        entries.add(
          GoatProgressEntry(
            goat: goat,
            previousImageBytes: previous.bytes,
            previousLabel: previous.label,
            previousDate: previous.date,
            previousWeight: previous.weight,
            currentImageBytes: captured.bytes,
            currentDate: now,
            currentWeight: currentWeight,
            weightChain: previous.weightChain,
            latestHealthRecord: previous.latestHealthRecord,
            latestVaccinationDate: previous.latestVaccinationDate,
            latestHoofCuttingDate: previous.latestHoofCuttingDate,
            latestHairTrimmingDate: previous.latestHairTrimmingDate,
          ),
        );

        final report = GoatReport(
          id: '',
          type: GoatReportType.progress,
          fromDate: previous.date,
          toDate: now,
          generatedAt: now,
          startWeight: previous.weight,
          endWeight: currentWeight,
          healthStatus:
          previous.latestHealthRecord?.healthStatus.isNotEmpty == true
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
            healthStatus:
            previous.latestHealthRecord?.healthStatus.isNotEmpty == true
                ? previous.latestHealthRecord!.healthStatus
                : goat.healthStatus,
            doctorNotes:
            'Recorded during Progress Report generation.',
            recordedAt: now,
          ),
        );

        await FirestoreService.instance.addMonthlyPhoto(
          widget.farmId,
          widget.customer.id,
          goat.id,
          MonthlyPhoto(
            id: '',
            month: DateTime(now.year, now.month),
            image: captured.bytes,
            imageContentType: captured.contentType,
            weightKg: currentWeight,
            capturedAt: now,
          ),
        );
      }

      // Re-read the customer's live balance just before printing, so the
      // Payment Details page can show what is owed right now (the same
      // figure as Customer Profile and Customer Ledger), not only the
      // frozen numbers the bill was generated with.
      double? liveOutstanding;
      try {
        final liveCustomer = await FirestoreService.instance.getCustomer(
          widget.farmId,
          widget.customer.id,
        );
        liveOutstanding = liveCustomer?.pendingAmount;
      } catch (_) {
        // Falls back to the bill's own remaining balance in the PDF.
      }

      if (share) {
        await CustomerGoatsProgressReportPdfService.instance.share(
          customer: widget.customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
          currentOutstanding: liveOutstanding,
        );
      } else {
        await CustomerGoatsProgressReportPdfService.instance.preview(
          customer: widget.customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
          currentOutstanding: liveOutstanding,
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showSnack(
        'Could not generate report: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  // =====================================================================
  // MAIN BUILD
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: _phase == _Phase.capturing
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed:
          _generating ? null : _backToSelecting,
        )
            : null,
        title: Text(
          'Progress Report',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: _phase == _Phase.selecting
          ? _buildSelectingPhase()
          : _buildCapturingPhase(),
    );
  }

  // =====================================================================
  // SELECTING PHASE
  // =====================================================================

  Widget _buildSelectingPhase() {
    return StreamBuilder<List<PalaiGoat>>(
      stream: _goatsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primaryGreen,
            ),
          );
        }

        final goats = (snapshot.data ?? [])
            .where((goat) => !goat.isCheckedOut)
            .toList();

        _lastLoadedGoats = goats;

        if (_selectedIds.isEmpty && goats.isNotEmpty) {
          _selectedIds.addAll(goats.map((goat) => goat.id));
        }

        if (goats.isEmpty) {
          final hadAnyGoats =
              (snapshot.data ?? []).isNotEmpty;

          return _buildEmptyState(
            allCheckedOut: hadAnyGoats,
          );
        }

        return Column(
          children: [
            _buildHeaderCard(goats),
            Expanded(
              child: _buildGoatsSelectionList(goats),
            ),
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
                  Text(
                    widget.customer.name,
                    style: AppTheme.heading(size: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_selectedIds.length} of ${goats.length} goats selected',
                    style: AppTheme.body(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _toggleSelectAll(goats),
              child: Text(
                allSelected ? 'Deselect All' : 'Select All',
              ),
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
            : (goat.tagNumber.trim().isNotEmpty
            ? goat.tagNumber
            : goat.id);

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
                    goat.name.trim().isNotEmpty
                        ? goat.name
                        : goatId,
                    style: AppTheme.heading(size: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                    AppColors.primaryGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ID: $goatId',
                    style: AppTheme.body(
                      size: 10,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${goat.breed.isNotEmpty ? goat.breed : 'Breed unknown'} • '
                  '${goat.healthStatus.isNotEmpty ? goat.healthStatus : 'No health status'}',
              style: AppTheme.body(
                size: 11,
                color: AppColors.textMuted,
              ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
            _loadingPrevious ? null : _continueToCapture,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Continue to Photos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    bool allCheckedOut = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color:
                AppColors.primaryGreen.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                GoatIcons.paw,
                size: 35,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              allCheckedOut
                  ? 'No active goats'
                  : 'No goats found',
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 6),
            Text(
              allCheckedOut
                  ? 'All of this customer\'s goats have already been checked out of Palai.'
                  : 'This customer has no goats under Palai yet.',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // CAPTURING PHASE
  // =====================================================================

  Widget _buildCapturingPhase() {
    if (_loadingPrevious) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      );
    }

    final goats = _selectedGoats;

    final capturedCount = _capturedByGoatId.length;

    final weighedCount = goats.where((goat) {
      final weight = _enteredWeight(goat.id);
      return weight != null && weight > 0;
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
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Take a photo & weight for each goat',
                        style: AppTheme.heading(size: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$capturedCount of ${goats.length} photos • '
                            '$weighedCount of ${goats.length} weights'
                            '${_billingReady ? ' • billing ready' : ' • billing pending'}',
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _readyToGenerate
                      ? Icons.check_circle
                      : Icons.camera_alt_outlined,
                  color: AppColors.primaryGreen,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
        : (goat.tagNumber.trim().isNotEmpty
        ? goat.tagNumber
        : goat.id);

    final weightController =
    _weightControllerFor(goat.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                BorderRadius.circular(10),
                child:
                previous != null &&
                    previous.bytes.isNotEmpty
                    ? Image.memory(
                  previous.bytes,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                )
                    : Container(
                  width: 52,
                  height: 52,
                  color: AppColors.lightGreen,
                  child: const Icon(
                    Icons
                        .image_not_supported_outlined,
                    color:
                    AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            goat.name.trim().isNotEmpty
                                ? goat.name
                                : goatId,
                            style:
                            AppTheme.heading(
                              size: 13,
                            ),
                            overflow:
                            TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration:
                          BoxDecoration(
                            color: AppColors
                                .primaryGreen
                                .withOpacity(0.12),
                            borderRadius:
                            BorderRadius.circular(5),
                          ),
                          child: Text(
                            'ID: $goatId',
                            style: AppTheme.body(
                              size: 9,
                              color: AppColors
                                  .primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previous != null
                          ? 'Previous: ${previous.label}'
                          : '',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: capturing
                    ? null
                    : () => _capturePhoto(goat.id),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.circular(12),
                    border: Border.all(
                      color: captured != null
                          ? AppColors.primaryGreen
                          : AppColors.primaryGreen
                          .withOpacity(0.4),
                      width:
                      captured != null ? 2 : 1.5,
                    ),
                  ),
                  child: capturing
                      ? const Center(
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                      AppColors.primaryGreen,
                    ),
                  )
                      : captured != null
                      ? ClipRRect(
                    borderRadius:
                    BorderRadius.circular(
                        10.5),
                    child: Image.memory(
                      captured.bytes,
                      fit: BoxFit.cover,
                    ),
                  )
                      : const Icon(
                    Icons.camera_alt,
                    color:
                    AppColors.primaryGreen,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last weight',
                      style: AppTheme.body(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previous?.weight != null
                          ? '${previous!.weight!.toStringAsFixed(1)} kg'
                          : 'Not recorded',
                      style:
                      AppTheme.heading(size: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: weightController,
                  keyboardType:
                  const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  style: AppTheme.heading(size: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'New weight (kg)',
                    labelStyle: AppTheme.body(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                    contentPadding:
                    const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(
                      Icons.monitor_weight_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // BILLING CARD
  // =====================================================================

  String _currency(double value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  Widget _buildBillingCard() {
    final existing = _existingMonthlyBill;
    final monthLabel =
    DateFormat('MMMM yyyy').format(DateTime.now());

    return Container(
      margin:
      const EdgeInsets.only(top: 4, bottom: 10),
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primaryGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Monthly Billing — $monthLabel',
                  style: AppTheme.heading(size: 14),
                ),
              ),
              if (existing == null)
                IconButton(
                  tooltip:
                  'Re-fetch live Outstanding & Advance',
                  icon: _loadingBilling
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(
                    Icons.refresh,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed:
                  _loadingBilling
                      ? null
                      : _loadBillingInfo,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            existing != null
                ? 'The current-month bill is already generated. Its saved goat amounts are shown below. Missing active goats were automatically added to this same bill.'
                : 'Set each goat\'s Monthly Palai Amount below, then Old Pending Payment and Current Advance.',
            style: AppTheme.body(
              size: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          if (_loadingBilling)
            const Center(
              child: Padding(
                padding:
                EdgeInsets.symmetric(vertical: 12),
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                  AppColors.primaryGreen,
                ),
              ),
            )
          else if (_billingLoadError != null)
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  _billingLoadError!,
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadBillingInfo,
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                  ),
                  label:
                  const Text('Retry'),
                ),
              ],
            )
          else if (existing != null)
              ..._existingBillingRows(existing)
            else
              _newBillingFields(),
        ],
      ),
    );
  }

  List<Widget> _existingBillingRows(
      MonthlyBill bill,
      ) {
    final widgets = <Widget>[];

    for (final line in bill.goatBreakdown) {
      widgets.add(
        Padding(
          padding:
          const EdgeInsets.only(bottom: 4),
          child: _billingRow(
            line.displayLabel,
            _currency(line.palaiAmount),
          ),
        ),
      );
    }

    if (bill.goatBreakdown.isNotEmpty) {
      widgets.add(
        const Divider(height: 14),
      );
    }

    widgets.add(
      _billingRow(
        'Current Month Palai',
        _currency(bill.palaiCharges),
      ),
    );

    widgets.add(
      const SizedBox(height: 4),
    );

    widgets.add(
      _billingRow(
        'Old Pending Payment (at time of billing)',
        _currency(bill.previousOutstanding),
      ),
    );

    widgets.add(
      const SizedBox(height: 4),
    );

    widgets.add(
      _billingRow(
        'Advance Applied (at time of billing)',
        '- ${_currency(bill.advanceApplied)}',
      ),
    );

    widgets.add(
      const Divider(height: 20),
    );

    widgets.add(
      _billingRow(
        'Total Pending Payment (as billed)',
        _currency(bill.totalDue),
        bold: true,
      ),
    );

    if (bill.amountPaid > 0) {
      widgets.add(
        const SizedBox(height: 4),
      );
      widgets.add(
        _billingRow(
          'Paid So Far',
          _currency(bill.amountPaid),
        ),
      );
    }

    widgets.add(
      const SizedBox(height: 8),
    );

    widgets.add(
      Row(
        mainAxisAlignment:
        MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Remaining On This Bill',
            style: AppTheme.body(
              size: 12,
              color: AppColors.textMuted,
            ),
          ),
          Row(
            children: [
              Icon(
                bill.remainingAmount <= 0
                    ? Icons.check_circle
                    : Icons.error_outline,
                size: 14,
                color: bill.remainingAmount <= 0
                    ? AppColors.success
                    : AppColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                bill.remainingAmount <= 0
                    ? 'PAID'
                    : _currency(
                  bill.remainingAmount,
                ),
                style: AppTheme.heading(
                  size: 13,
                  color: bill.remainingAmount <= 0
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if ((_currentOutstanding -
        bill.remainingAmount)
        .abs() >
        0.5) {
      widgets.add(
        const SizedBox(height: 12),
      );

      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
            AppColors.warning.withOpacity(0.12),
            borderRadius:
            BorderRadius.circular(8),
            border: Border.all(
              color:
              AppColors.warning.withOpacity(0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customer\'s overall outstanding today: '
                      '${_currency(_currentOutstanding)}, '
                      'which doesn\'t match what\'s left on this specific bill '
                      '(${_currency(bill.remainingAmount)}).',
                  style: AppTheme.body(
                    size: 10.5,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (bill.palaiCharges <= 0) {
      widgets.add(
        const SizedBox(height: 12),
      );

      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
            AppColors.warning.withOpacity(0.12),
            borderRadius:
            BorderRadius.circular(8),
            border: Border.all(
              color:
              AppColors.warning.withOpacity(0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This month\'s bill shows ₹0 Current Month Palai. Fix it in Monthly Billing before sharing this report.',
                      style: AppTheme.body(
                        size: 10.5,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                  _openMonthlyBillingToFix,
                  icon: const Icon(
                    Icons.build_outlined,
                    size: 16,
                  ),
                  label: const Text(
                    'Fix in Monthly Billing',
                  ),
                  style:
                  OutlinedButton.styleFrom(
                    foregroundColor:
                    AppColors.warning,
                    side: const BorderSide(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _newBillingFields() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly Palai Amount (per goat)',
          style: AppTheme.body(
            size: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        for (final goat in _selectedGoats) ...[
          _goatPalaiCard(goat),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        _billingRow(
          'Current Month Palai',
          _currency(_palaiChargesTotal),
          bold: true,
        ),
        const SizedBox(height: 14),
        _billingField(
          controller: _outstandingController,
          label: 'Old Pending Payment',
          icon:
          Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 10),
        _billingField(
          controller: _advanceController,
          label: 'Current Advance',
          icon: Icons.savings_outlined,
        ),
        const Divider(height: 24),
        _billingRow(
          'Total Pending Payment',
          _currency(_currentAmountDue),
          bold: true,
        ),
        const SizedBox(height: 4),
        Text(
          'This will be saved to the customer\'s profile the moment you generate this report.',
          style: AppTheme.body(
            size: 10,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed:
            _openMonthlyBillingToFix,
            icon: const Icon(
              Icons.open_in_new,
              size: 15,
            ),
            label: const Text(
              'Fill in Monthly Billing instead',
            ),
          ),
        ),
      ],
    );
  }

  Widget _goatPalaiCard(PalaiGoat goat) {
    final controller = _palaiControllerFor(goat);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
        AppColors.lightGreen.withOpacity(0.5),
        borderRadius:
        BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _goatLabel(goat),
                  style:
                  AppTheme.heading(size: 13),
                ),
                TextSpan(
                  text:
                  '  •  Palai Price: ${_currency(goat.pricing)}',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType:
            const TextInputType.numberWithOptions(
              decimal: true,
            ),
            onChanged: (_) => setState(() {}),
            style: AppTheme.heading(size: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText:
              'Monthly Palai Amount',
              labelStyle: AppTheme.body(
                size: 11,
                color: AppColors.textMuted,
              ),
              prefixText: '₹ ',
              contentPadding:
              const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(8),
              ),
            ),
          ),
          if (_prorationFor(goat).isPartialMonth) ...[
            const SizedBox(height: 6),
            Text(
              _prorationNote(goat),
              style: AppTheme.body(
                size: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _billingRow(
      String label,
      String value, {
        bool bold = false,
      }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold
                ? AppTheme.heading(size: 13)
                : AppTheme.body(
              size: 12,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Text(
          value,
          style: bold
              ? AppTheme.heading(
            size: 14,
            color: AppColors.primaryGreen,
          )
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
      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        prefixText: '₹ ',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
    );
  }

  // =====================================================================
  // BOTTOM BAR / NAVIGATION
  // =====================================================================

  Widget _buildCaptureBottomBar() {
    return Container(
      padding:
      const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                (_generating ||
                    !_readyToGenerate)
                    ? null
                    : () => _generate(
                  share: false,
                ),
                icon: const Icon(
                  Icons.visibility_outlined,
                ),
                label: const Text('Preview'),
                style:
                OutlinedButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                  side: const BorderSide(
                    color:
                    AppColors.primaryGreen,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                (_generating ||
                    !_readyToGenerate)
                    ? null
                    : () => _generate(
                  share: true,
                ),
                icon: _generating
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(
                  Icons.share_outlined,
                ),
                label: Text(
                  _generating
                      ? 'Generating...'
                      : 'Share Report',
                ),
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,
                  foregroundColor:
                  Colors.white,
                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _backToSelecting() {
    setState(() {
      _phase = _Phase.selecting;

      _previousByGoatId.clear();
      _capturedByGoatId.clear();

      for (final controller
      in _weightControllers.values) {
        controller.dispose();
      }
      _weightControllers.clear();

      for (final controller
      in _palaiControllers.values) {
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

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        isError ? AppColors.error : null,
      ),
    );
  }
}