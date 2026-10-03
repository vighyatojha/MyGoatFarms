import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../goat_icons.dart';
import '../../models/bill_settings_model.dart';
import '../../models/customer_credit.dart';
import '../../models/monthly_bill_model.dart' show MonthlyBill;
import '../../models/palai_models.dart';
import '../../models/report_models.dart';
import '../../services/customer_goats_progress_report_pdf_service.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/monthly_statement_engine.dart';
import '../../services/sales_service.dart';
import '../../widgets/fast_route.dart';
import '../../widgets/latest_statement_card.dart';
import 'monthly_bills_screen.dart';

/// Consolidated Progress Report for all active goats belonging to one
/// Palai customer.
///
/// Billing on this report is READ-ONLY: it shows the customer's latest
/// monthly statement and what they owe today (see [LatestStatementCard]).
/// Reports never create or change bills; bills are statements for the
/// previous month, made by [MonthlyStatementEngine].
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

  double _currentOutstanding = 0;
  double _currentAdvanceAvailable = 0;

  /// This customer's unpaid Trading goat sales (e.g. a goat "Transfer to
  /// Palai" sale that still has a balance due), re-fetched fresh at the
  /// same time as [_currentOutstanding]. Null when they owe nothing on
  /// any sale.
  ///
  /// Kept SEPARATE from [_currentOutstanding] (`customer.pendingAmount`,
  /// which only tracks Palai boarding dues) — never merged into it or
  /// saved on top of it, since `pendingAmount` is also what payment
  /// settlement (`settleSalesInTransaction`) reads and writes. It is
  /// only surfaced as its own labelled line and folded into the
  /// on-screen "Total Pending Payment" total so this report never
  /// silently excludes a pending Trading balance.
  CustomerCredit? _goatSaleCredit;


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
  // BILLING (read-only)
  // =====================================================================

  /// Loads the customer's live balance, their latest monthly bill and
  /// any unpaid Trading goat sales. Nothing is written: reports never
  /// create or change bills.
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

      // The newest bill from the new billing; reports never create one.
      final latestBill = await MonthlyStatementEngine.instance.latestBill(
        farmId: widget.farmId,
        customerId: widget.customer.id,
        preferStatement: true,
      );

      // Same lookup the Goat sale credit card on the customer's profile
      // uses, so this report and that card always agree.
      final goatSaleCredit = await SalesService.instance.creditForPerson(
        widget.farmId,
        customerId: widget.customer.id,
        mobile: freshCustomer?.mobileNumber ?? widget.customer.mobileNumber,
        name: freshCustomer?.name ?? widget.customer.name,
      );

      if (!mounted) return;

      setState(() {
        _currentOutstanding =
            freshCustomer?.pendingAmount ?? widget.customer.pendingAmount;
        _currentAdvanceAvailable =
            freshCustomer?.advanceAmount ?? widget.customer.advanceAmount;
        _goatSaleCredit = goatSaleCredit;
        _existingMonthlyBill = latestBill;
        _loadingBilling = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingBilling = false;
        _billingLoadError = 'Could not load billing info: $e';
      });
    }
  }

  Future<void> _openMonthlyBills() async {
    await Navigator.of(context).push(
      fastRoute(
        MonthlyBillsScreen(
          farmId: widget.farmId,
          customerId: widget.customer.id,
          customerName: widget.customer.name,
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
      date: goat.billingStartDate,
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

  /// Billing is ready once it has loaded. A customer without any bill
  /// yet can still get a report; it simply has no bill in it.
  bool get _billingReady => !_loadingBilling && _billingLoadError == null;

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
        'Billing is still loading. Try again in a moment.',
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

      // Billing is read-only: the latest bill as issued (may be null).
      final monthlyBill = _existingMonthlyBill;

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
      CustomerCredit? liveGoatSaleCredit;
      try {
        final liveCustomer = await FirestoreService.instance.getCustomer(
          widget.farmId,
          widget.customer.id,
        );
        liveOutstanding = liveCustomer?.pendingAmount;
        liveGoatSaleCredit = await SalesService.instance.creditForPerson(
          widget.farmId,
          customerId: widget.customer.id,
          mobile: liveCustomer?.mobileNumber ?? widget.customer.mobileNumber,
          name: liveCustomer?.name ?? widget.customer.name,
        );
      } catch (_) {
        // Falls back to the bill's own remaining balance, and to
        // whatever Goat Sale Credit was already loaded on screen, in
        // the PDF.
        liveGoatSaleCredit = _goatSaleCredit;
      }

      if (share) {
        await CustomerGoatsProgressReportPdfService.instance.share(
          customer: widget.customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
          currentOutstanding: liveOutstanding,
          goatSaleCredit: liveGoatSaleCredit,
        );
      } else {
        await CustomerGoatsProgressReportPdfService.instance.preview(
          customer: widget.customer,
          entries: entries,
          billSettings: billSettings,
          monthlyBill: monthlyBill,
          currentOutstanding: liveOutstanding,
          goatSaleCredit: liveGoatSaleCredit,
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
                    AppColors.primaryGreen.withValues(alpha: 0.12),
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
            color: Colors.black.withValues(alpha: 0.05),
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
                AppColors.primaryGreen.withValues(alpha: 0.10),
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
                                .withValues(alpha: 0.12),
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
                          .withValues(alpha: 0.4),
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


  Widget _buildBillingCard() {
    return LatestStatementCard(
      bill: _existingMonthlyBill,
      livePending: _currentOutstanding,
      liveAdvance: _currentAdvanceAvailable,
      loading: _loadingBilling,
      error: _billingLoadError,
      onRetry: _loadBillingInfo,
      goatSaleCredit: _goatSaleCredit,
      onOpenBills: _openMonthlyBills,
    );
  }

  Widget _buildCaptureBottomBar() {
    return Container(
      padding:
      const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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


      _existingMonthlyBill = null;
      _billingLoadError = null;
      _currentOutstanding = 0;
      _currentAdvanceAvailable = 0;
      _goatSaleCredit = null;
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