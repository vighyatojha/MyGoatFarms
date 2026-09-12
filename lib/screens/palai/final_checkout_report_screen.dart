import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/final_checkout_report_model.dart';
import '../../models/palai_models.dart';
import '../../services/finance_service.dart';
import '../../services/firestore_service.dart';
import '../../services/final_checkout_report_pdf_service.dart';
import '../../services/monthly_report_service.dart';
import 'checkout_charges_payment_screen.dart' show GoatCheckoutDraft;

/// Final stage of the Palai checkout flow.
///
/// Flow:
///
/// Charges & Payment
///        ↓
/// Final Checkout Report
///        ↓
/// Review all information
///        ↓
/// Generate PDF
///        ↓
/// PDF Generated
///        ↓
/// Download OR Share
///        ↓
/// Done becomes enabled
///        ↓
/// Goat(s) are finally marked as checked out.
///
/// IMPORTANT:
/// This screen does NOT check out goats when it opens.
/// The parent supplies [onDone], and only after the generated PDF has
/// successfully been downloaded/shared do we call that callback.
class FinalCheckoutReportScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final List<GoatCheckoutDraft> goats;
  final MonthlyBillResult billResult;
  final BillSettings billSettings;

  /// Check-out transport entered on the Payment Details screen.
  ///
  /// Check-in transport is already stored against each goat and is
  /// therefore read from [PalaiGoat.checkInTransportCharge].
  final double checkOutTransport;

  /// Called only after the user successfully downloads or shares the
  /// final PDF and presses Done.
  ///
  /// The callback is responsible for performing the actual Firestore
  /// goat checkout.
  final Future<void> Function()? onDone;

  const FinalCheckoutReportScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goats,
    required this.billResult,
    required this.billSettings,
    this.checkOutTransport = 0,
    this.onDone,
  });

  @override
  State<FinalCheckoutReportScreen> createState() =>
      _FinalCheckoutReportScreenState();
}

enum _ReportStage {
  review,
  generating,
  generated,
}

class _FinalCheckoutReportScreenState
    extends State<FinalCheckoutReportScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _doneUnlocked = false;

  String? _error;

  PalaiCustomer? _customer;

  FinalCheckoutReportData? _report;

  /// Built once, in [_generatePdf] — [_downloadPdf]/[_sharePdf] reuse
  /// these bytes instead of rebuilding the (photo-heavy) report a
  /// second and third time.
  Uint8List? _pdfBytes;

  _ReportStage _stage = _ReportStage.review;

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  // ========================================================================
  // LOAD / BUILD REPORT DATA
  // ========================================================================

  Future<void> _loadReportData() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final customer = await FirestoreService.instance.getCustomer(
        widget.farmId,
        widget.customerId,
      );

      if (customer == null) {
        throw StateError('Customer could not be found.');
      }

      final checkoutDate = DateTime.now();

      DateTime? earliestCheckIn;

      final goatReports = <FinalGoatReportData>[];

      // This now comes directly from MonthlyReportService.
      //
      // Previously this screen manually recreated the monthly rows.
      // That duplicated logic and could make the Final Checkout Report
      // different from the actual monthly report logic.
      final allMonthlyReports = <MonthlyGoatReportData>[];

      for (final draft in widget.goats) {
        final goat = draft.goat;

        final start = goat.farmArrivalDate ?? goat.checkInDate;

        if (earliestCheckIn == null ||
            start.isBefore(earliestCheckIn!)) {
          earliestCheckIn = start;
        }

        // --------------------------------------------------------------
        // WEIGHT HISTORY
        // --------------------------------------------------------------

        final weightHistory =
        await MonthlyReportService.instance.getGoatWeightHistory(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goatId: goat.id,
          periodStart: start,
          periodEnd: checkoutDate,
        );

        // --------------------------------------------------------------
        // HEALTH HISTORY
        // --------------------------------------------------------------

        final healthHistory =
        await MonthlyReportService.instance.getGoatHealthHistory(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goatId: goat.id,
          periodStart: start,
          periodEnd: checkoutDate,
        );

        // --------------------------------------------------------------
        // COMPLETE MONTHLY HISTORY
        // --------------------------------------------------------------
        //
        // IMPORTANT:
        // Do not manually construct MonthlyGoatReportData here.
        //
        // MonthlyReportService already contains the complete logic for:
        //
        // - monthly weight
        // - carry-forward weight
        // - monthly photos
        // - carry-forward photos
        // - vaccination
        // - medicine
        // - hoof cutting
        // - hair trimming
        // - health notes
        //
        // This is now the single source of truth.
        // --------------------------------------------------------------

        final monthlyReports =
        await MonthlyReportService.instance.getGoatFinalMonthlyReports(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goat: goat,
          periodEnd: checkoutDate,
        );

        allMonthlyReports.addAll(monthlyReports);

        // --------------------------------------------------------------
        // FINAL GOAT REPORT
        // --------------------------------------------------------------

        goatReports.add(
          FinalGoatReportData(
            goatCode: goat.goatCode,
            breed: goat.breed,
            gender: goat.gender,
            color: goat.color,
            checkInWeight: goat.weightAtCheckIn,
            finalWeight: draft.finalWeight,
            healthStatus: draft.healthStatus,
            deliveryStatus: draft.deliveryStatus,
            charges: goat.pricing,
            weightHistory: weightHistory,
            healthHistory: healthHistory,
          ),
        );
      }

      // NOTE: The balance figures on FinalCheckoutReportData below come
      // entirely from widget.billResult (the live createMonthlyBill()
      // result — the one source of truth for the balance), never
      // recomputed here. A redundant FinanceService call used to run
      // in this method and its result was never used — removed; it
      // re-queried both bills and payments for a value nothing read.
      // The lean getCustomerPaymentHistory() call below replaces it
      // for the one piece that actually is needed: the payment rows
      // for the PDF's Payment History table.
      // --------------------------------------------------------------

      // --------------------------------------------------------------
      // PAYMENT HISTORY
      // --------------------------------------------------------------
      //
      // Best-effort only: a failure here (e.g. a Firestore rules gap on
      // the `payments` collection for this caller) must never block the
      // rest of the report — weight/health/monthly data and the bill
      // itself are already known-good by this point. On failure we log
      // and fall back to an empty list; the PDF's Payment History
      // section already handles empty gracefully (it simply omits the
      // section — see `s.paymentHistory.isNotEmpty` in
      // FinalCheckoutReportPdfService).

      List<FinalPaymentHistoryRow> paymentHistory = const [];
      try {
        paymentHistory = await FinanceService.instance.getCustomerPaymentHistory(
          farmId: widget.farmId,
          customerId: widget.customerId,
        );
      } catch (e) {
        debugPrint('Final Checkout Report: could not load payment history — $e');
      }

      // --------------------------------------------------------------
      // FARM IMPORTANT NOTES
      // --------------------------------------------------------------

      final importantNotes = <String>[];

      for (final note in widget.billSettings.importantNotes) {
        if (!note.enabled) continue;

        final title = note.title.trim();
        final text = note.text.trim();

        if (title.isNotEmpty && text.isNotEmpty) {
          importantNotes.add('$title: $text');
        } else if (text.isNotEmpty) {
          importantNotes.add(text);
        }
      }

      if (widget.billSettings.otherNoteEnabled &&
          widget.billSettings.otherNoteText.trim().isNotEmpty) {
        final title = widget.billSettings.otherNoteTitle.trim();

        if (title.isEmpty) {
          importantNotes.add(
            widget.billSettings.otherNoteText.trim(),
          );
        } else {
          importantNotes.add(
            '$title: ${widget.billSettings.otherNoteText.trim()}',
          );
        }
      }

      // --------------------------------------------------------------
      // FINAL REPORT DATA
      // --------------------------------------------------------------

      final firstGoat = widget.goats.first.goat;

      final report = FinalCheckoutReportData(
        reportId: widget.billResult.billNumber,
        customerName: customer.name,
        customerMobile: customer.mobileNumber,
        customerAddress: customer.address,
        packageName: customer.package,
        checkInDate: earliestCheckIn ?? checkoutDate,
        checkOutDate: checkoutDate,
        deliveryStatus: widget.goats.length == 1
            ? widget.goats.first.deliveryStatus
            : 'Multiple goats',
        finalHealthStatus: widget.goats.length == 1
            ? widget.goats.first.healthStatus
            : 'See individual goat health details',
        goats: goatReports,
        months: allMonthlyReports,
        checkInTransport: widget.goats.fold<double>(
          0,
              (sum, draft) =>
          sum + draft.goat.checkInTransportCharge,
        ),
        checkOutTransport: widget.checkOutTransport,
        previousBalance: widget.billResult.previousPending,
        totalBill: widget.billResult.totalDue,
        paidAmount: widget.billResult.paid,
        pendingAmount: widget.billResult.pendingAfter,
        advanceBefore: widget.billResult.advanceBefore,
        advanceApplied: widget.billResult.advanceApplied,
        advanceAfter: widget.billResult.advanceAfter,
        paymentMethod: widget.billResult.paymentMethod,
        beforeImage: firstGoat.beforeImage,
        afterImage: widget.goats.length == 1
            ? widget.goats.first.afterImage
            : null,
        signatureBytes: null,
        importantNotes: importantNotes,
        billSettings: widget.billSettings,
        paymentHistory: paymentHistory,
      );

      if (!mounted) return;

      setState(() {
        _customer = customer;
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error =
        'Could not prepare the final checkout report.\n\n$e';
      });
    }
  }

  // ========================================================================
  // ADAPTER — FinalCheckoutReportData (this screen's on-screen review
  // shape) -> GoatFinalReportEntry / FinalSettlementData (the shape
  // FinalCheckoutReportPdfService — "Engine B" — expects).
  //
  // Purely additive: nothing above builds/uses these two methods, and
  // nothing else in this file (the on-screen review widgets,
  // _generatePdf, etc.) is changed by adding them. They exist to feed
  // Task 3's swap of the PDF call from PdfBillService to
  // FinalCheckoutReportPdfService.
  //
  // KNOWN GAPS — flagged rather than silently guessed:
  //   - FinalSettlementData.totalOtherCharges has no source anywhere
  //     in this screen's data today. Left at 0.0.
  //   - FinalSettlementData.totalDiscount has no source either: the
  //     discount entered on the Payment screen is applied inside
  //     FirestoreService.createMonthlyBill() but never returned on
  //     MonthlyBillResult, and this screen's constructor doesn't take
  //     a discount parameter. Left at 0.0 until that value is threaded
  //     through from the Payment screen.
  //   - totalMonthlyCharges/totalTransport below are scoped to THIS
  //     checkout only, not "the whole Palai period" as the model's
  //     doc comment describes — this screen has no historical,
  //     all-time aggregation of a customer's charges/transport by
  //     category. Using the current-checkout numbers is the accurate,
  //     non-fabricated option available today.
  //   - GoatMonthlyHistoryRow.photos is an approximation: the only
  //     per-month photo data available here is MonthlyGoatReportData's
  //     display images (currentImage/additionalImages), not a raw
  //     per-event photo log. previousImage is excluded because it's a
  //     carry-forward from the prior month, not a new photo taken in
  //     this one.
  // ========================================================================

  List<GoatFinalReportEntry> _toGoatFinalReportEntries() {
    final report = _report;
    if (report == null) return const [];

    final entries = <GoatFinalReportEntry>[];

    for (var i = 0; i < widget.goats.length; i++) {
      final draft = widget.goats[i];
      final goat = draft.goat;
      final goatData = report.goats[i];

      final goatCheckIn = goat.farmArrivalDate ?? goat.checkInDate;

      // Bucket this goat's real weight/health records into the same
      // monthly rows MonthlyReportService already produced for it
      // (report.months, filtered to this goat) — never a second,
      // independently-invented set of month boundaries.
      final goatMonths =
      report.months.where((m) => m.goatCode == goat.goatCode).toList();

      final monthlyHistory = <GoatMonthlyHistoryRow>[];
      final representativePhotoByMonth = <String, Uint8List>{};

      for (final month in goatMonths) {
        final weightCount = goatData.weightHistory
            .where((w) =>
        !w.date.isBefore(month.periodStart) &&
            !w.date.isAfter(month.periodEnd))
            .length;

        final healthInMonth = goatData.healthHistory.where((h) =>
        !h.date.isBefore(month.periodStart) &&
            !h.date.isAfter(month.periodEnd));

        int vaccinationCount = 0;
        int medicineCount = 0;
        int hoofCount = 0;
        int hairCount = 0;
        int healthCount = 0; // catch-all: Health Update, Deworming, ...

        for (final h in healthInMonth) {
          final type = h.type.toLowerCase();
          if (type.contains('vaccination')) {
            vaccinationCount++;
          } else if (type.contains('medicine')) {
            medicineCount++;
          } else if (type.contains('hoof')) {
            hoofCount++;
          } else if (type.contains('hair')) {
            hairCount++;
          } else {
            healthCount++;
          }
        }

        final photoCount =
            (month.currentImage != null ? 1 : 0) +
                month.additionalImages.length;

        monthlyHistory.add(
          GoatMonthlyHistoryRow(
            monthStart: month.periodStart,
            monthLabel: month.monthLabel,
            weightRecords: weightCount,
            health: healthCount,
            vaccination: vaccinationCount,
            medicine: medicineCount,
            hoof: hoofCount,
            hair: hairCount,
            photos: photoCount,
          ),
        );

        final representative = month.currentImage ?? month.previousImage;
        if (representative != null) {
          representativePhotoByMonth[month.monthLabel] = representative;
        }
      }

      entries.add(
        GoatFinalReportEntry(
          goat: goat,
          checkInDate: goatCheckIn,
          checkOutDate: report.checkOutDate,
          initialWeight: goatData.checkInWeight,
          finalWeight: goatData.finalWeight,
          beforeImage: goat.beforeImage,
          afterImage: draft.afterImage,
          monthlyHistory: monthlyHistory,
          weightHistory: goatData.weightHistory,
          representativePhotoByMonth: representativePhotoByMonth,
          healthStatus: goatData.healthStatus,
          deliveryStatus: goatData.deliveryStatus,
        ),
      );
    }

    return entries;
  }

  Future<FinalSettlementData> _toFinalSettlementData() async {
    final report = _report!;
    final billResult = widget.billResult;

    final totalMonthlyCharges =
    report.goats.fold<double>(0, (sum, g) => sum + g.charges);
    final totalTransport = report.checkInTransport + report.checkOutTransport;

    // No source for these two in this screen's data today — see the
    // KNOWN GAPS note above. Left explicit rather than guessed.
    const totalOtherCharges = 0.0;
    const totalDiscount = 0.0;

    final grossCharges = totalMonthlyCharges +
        totalTransport +
        totalOtherCharges -
        totalDiscount;

    // report.paymentHistory was already fetched once, in
    // _loadReportData, via FinanceService.instance
    // .getCustomerPaymentHistory(farmId: ..., customerId: ...) —
    // reused here rather than firing that same Firestore query again.
    return FinalSettlementData(
      customerName: report.customerName,
      goatCount: report.goats.length,
      periodStart: report.checkInDate,
      periodEnd: report.checkOutDate,
      totalMonthlyCharges: totalMonthlyCharges,
      totalTransport: totalTransport,
      totalOtherCharges: totalOtherCharges,
      totalDiscount: totalDiscount,
      grossCharges: grossCharges,
      previousOutstanding: billResult.previousPending,
      advanceBefore: billResult.advanceBefore,
      advanceApplied: billResult.advanceApplied,
      finalAmountDue: billResult.totalDue,
      finalAmountPaid: billResult.paid,
      finalOutstanding: billResult.pendingAfter,
      finalAdvance: billResult.advanceAfter,
      paymentHistory: report.paymentHistory,
    );
  }

  // ========================================================================
  // GENERATE PDF
  // ========================================================================

  Future<void> _generatePdf() async {
    if (_busy || _report == null) return;

    setState(() {
      _busy = true;
      _stage = _ReportStage.generating;
      _error = null;
    });

    try {
      // Build the complete PDF now, and keep the bytes — Download and
      // Share below reuse them rather than rebuilding the report.
      //
      // We intentionally do not check out the goats here.
      // Checkout happens only after Download or Share and Done.
      final bytes = await FinalCheckoutReportPdfService.instance.generatePdf(
        customer: _customer!,
        goatEntries: _toGoatFinalReportEntries(),
        settlement: await _toFinalSettlementData(),
        billSettings: widget.billSettings,
      );

      if (!mounted) return;

      setState(() {
        _pdfBytes = bytes;
        _busy = false;
        _stage = _ReportStage.generated;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _stage = _ReportStage.review;
        _error = 'Could not generate the PDF.\n\n$e';
      });
    }
  }

  // ========================================================================
  // DOWNLOAD
  // ========================================================================

  String _safeFileName(String value) =>
      value.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');

  Future<void> _downloadPdf() async {
    if (_busy || _report == null || _pdfBytes == null) return;

    setState(() {
      _busy = true;
    });

    try {
      final path =
      await FinalCheckoutReportPdfService.instance.saveBytes(
        _pdfBytes!,
        '${_safeFileName(_report!.customerName)}_${_safeFileName(_report!.reportId)}_final_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      if (!mounted) return;

      setState(() {
        _busy = false;
        _doneUnlocked = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Final report saved successfully.\n$path',
          ),
          backgroundColor: AppColors.primaryGreen,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
      });

      _showError(
        'Could not download the report.\n\n$e',
      );
    }
  }

  // ========================================================================
  // SHARE
  // ========================================================================

  Future<void> _sharePdf() async {
    if (_busy || _report == null || _pdfBytes == null) return;

    setState(() {
      _busy = true;
    });

    try {
      await FinalCheckoutReportPdfService.instance.shareBytes(
        _pdfBytes!,
        '${_safeFileName(_report!.customerName)}_${_safeFileName(_report!.reportId)}_final_report.pdf',
      );

      if (!mounted) return;

      setState(() {
        _busy = false;
        _doneUnlocked = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Final report is ready to share.',
          ),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
      });

      _showError(
        'Could not share the report.\n\n$e',
      );
    }
  }

  // ========================================================================
  // DONE / ACTUAL CHECKOUT
  // ========================================================================

  Future<void> _finishCheckout() async {
    if (_busy || !_doneUnlocked) return;

    setState(() {
      _busy = true;
    });

    try {
      if (widget.onDone != null) {
        await widget.onDone!();
      }

      if (!mounted) return;

      setState(() {
        _busy = false;
      });

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
      });

      _showError(
        'The report was generated, but the goats could not be marked as checked out.\n\n$e',
      );
    }
  }

  // ========================================================================
  // UI
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(
          _stage == _ReportStage.generated
              ? 'Report Generated'
              : 'Final Checkout Report',
          style: AppTheme.heading(size: 17),
        ),
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      )
          : _error != null && _report == null
          ? _buildFatalError()
          : _stage == _ReportStage.generating
          ? _buildGenerating()
          : _stage == _ReportStage.generated
          ? _buildGenerated()
          : _buildReview(),
    );
  }

  // ========================================================================
  // REVIEW SCREEN
  // ========================================================================

  Widget _buildReview() {
    final report = _report!;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              20,
            ),
            children: [
              _buildReviewHeader(),
              const SizedBox(height: 16),

              if (_error != null) ...[
                _errorCard(),
                const SizedBox(height: 12),
              ],

              _sectionTitle(
                Icons.person_outline,
                'Customer Details',
              ),
              _customerCard(report),

              const SizedBox(height: 14),

              _sectionTitle(
                Icons.calendar_month_outlined,
                'Checkout Period',
              ),
              _periodCard(report),

              const SizedBox(height: 14),

              _sectionTitle(
                Icons.pets_outlined,
                'Goats',
              ),

              for (int i = 0; i < widget.goats.length; i++) ...[
                _goatReviewCard(
                  widget.goats[i],
                  report.goats[i],
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 4),

              _sectionTitle(
                Icons.monitor_weight_outlined,
                'Weight Progress',
              ),
              _weightSummary(report),

              const SizedBox(height: 14),

              _sectionTitle(
                Icons.medical_services_outlined,
                'Health History',
              ),
              _healthSummary(report),

              const SizedBox(height: 14),

              _sectionTitle(
                Icons.history_outlined,
                'Monthly History',
              ),
              _monthlyHistory(report),

              const SizedBox(height: 14),

              _sectionTitle(
                Icons.account_balance_wallet_outlined,
                'Payment Summary',
              ),
              _paymentSummary(report),
            ],
          ),
        ),
        _buildReviewBottomBar(),
      ],
    );
  }

  Widget _buildReviewHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(.18),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: AppColors.primaryGreen,
              size: 30,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Review Final Checkout',
            style: AppTheme.heading(size: 17),
          ),
          const SizedBox(height: 4),
          Text(
            'Review all checkout, health, monthly and payment information before generating the final report.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerCard(FinalCheckoutReportData report) {
    return _card(
      children: [
        _infoRow('Name', report.customerName),
        _infoRow('Mobile', report.customerMobile),
        _infoRow('Address', report.customerAddress),
        _infoRow('Package', report.packageName),
      ],
    );
  }

  Widget _periodCard(FinalCheckoutReportData report) {
    final duration =
        report.checkOutDate.difference(report.checkInDate).inDays;

    return _card(
      children: [
        _infoRow(
          'Check-in',
          _date(report.checkInDate),
        ),
        _infoRow(
          'Check-out',
          _date(report.checkOutDate),
        ),
        _infoRow(
          'Duration',
          '$duration day${duration == 1 ? '' : 's'}',
        ),
        _infoRow(
          'Total goats',
          '${report.goats.length}',
        ),
      ],
    );
  }

  Widget _goatReviewCard(
      GoatCheckoutDraft draft,
      FinalGoatReportData report,
      ) {
    final goat = draft.goat;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.lightGreen,
                child: const Icon(
                  Icons.pets,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      goat.goatCode,
                      style: AppTheme.body(
                        size: 14,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${goat.breed} • ${goat.gender}',
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Arrival',
                  '${report.checkInWeight.toStringAsFixed(1)} kg',
                ),
              ),
              Expanded(
                child: _miniStat(
                  'Current',
                  '${report.finalWeight.toStringAsFixed(1)} kg',
                ),
              ),
              Expanded(
                child: _miniStat(
                  'Gain',
                  '${report.weightGain >= 0 ? '+' : ''}'
                      '${report.weightGain.toStringAsFixed(1)} kg',
                ),
              ),
            ],
          ),

          const Divider(height: 20),

          _infoRow('Color', goat.color),
          _infoRow('Health', draft.healthStatus),
          _infoRow('Delivery', draft.deliveryStatus),

          if (draft.notes.trim().isNotEmpty)
            _infoRow('Notes', draft.notes),

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _photoStatus(
                  Icons.photo_camera_outlined,
                  'Arrival photo',
                  goat.beforeImage != null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _photoStatus(
                  Icons.photo_camera_back_outlined,
                  'Current photo',
                  draft.afterImage != null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weightSummary(FinalCheckoutReportData report) {
    return _card(
      children: [
        _infoRow(
          'Total arrival weight',
          '${report.goats.fold<double>(
            0,
                (s, g) => s + g.checkInWeight,
          ).toStringAsFixed(1)} kg',
        ),
        _infoRow(
          'Total current weight',
          '${report.totalFinalWeight.toStringAsFixed(1)} kg',
        ),
        _infoRow(
          'Total weight gain',
          '${report.totalWeightGain >= 0 ? '+' : ''}'
              '${report.totalWeightGain.toStringAsFixed(1)} kg',
          valueColor: AppColors.darkGreen,
        ),
        const SizedBox(height: 8),
        const Text(
          'Each goat’s complete weight history is included in the generated PDF.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  Widget _healthSummary(
      FinalCheckoutReportData report,
      ) {
    return Column(
      children: [
        for (final goat in report.goats)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(radius: 12),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  goat.goatCode,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${goat.healthHistory.length} health record'
                      '${goat.healthHistory.length == 1 ? '' : 's'}',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
                if (goat.healthHistory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final entry
                  in goat.healthHistory.take(5))
                    Padding(
                      padding:
                      const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            _date(entry.date),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${entry.type}: ${entry.detail}',
                              style: const TextStyle(
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _monthlyHistory(
      FinalCheckoutReportData report,
      ) {
    if (report.months.isEmpty) {
      return _card(
        children: const [
          Text(
            'No previous monthly records were found for the selected goats.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textGrey,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (final month in report.months)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(radius: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.lightGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    size: 20,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        month.monthLabel,
                        style: AppTheme.body(
                          size: 13,
                          color: AppColors.textDark,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${month.goatCode} • '
                            '${month.weightGain >= 0 ? '+' : ''}'
                            '${month.weightGain.toStringAsFixed(1)} kg',
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Health ${month.healthStatus} • '
                            'Vaccination ${month.vaccination}',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _paymentSummary(
      FinalCheckoutReportData report,
      ) {
    return _card(
      children: [
        _infoRow(
          'Previous pending',
          _currency(report.previousBalance),
        ),
        _infoRow(
          'Previous advance',
          _currency(report.advanceBefore),
        ),
        _infoRow(
          'Check-in transport',
          _currency(report.checkInTransport),
        ),
        _infoRow(
          'Check-out transport',
          _currency(report.checkOutTransport),
        ),
        const Divider(height: 18),
        _infoRow(
          'Total due',
          _currency(report.totalBill),
          bold: true,
        ),
        _infoRow(
          'Paid',
          _currency(report.paidAmount),
        ),
        _infoRow(
          'Pending after checkout',
          _currency(report.pendingAmount),
        ),
        _infoRow(
          'Advance after checkout',
          _currency(report.advanceAfter),
        ),
        _infoRow(
          'Payment method',
          report.paymentMethod,
        ),
      ],
    );
  }

  Widget _buildReviewBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(
                  'edit',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.darkGreen,
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                  side: const BorderSide(
                    color: AppColors.primaryGreen,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed:
                _busy ? null : _generatePdf,
                icon: const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 19,
                ),
                label: const Text('Generate PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // GENERATING
  // ========================================================================

  Widget _buildGenerating() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: AppTheme.card(radius: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 58,
                height: 58,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Generating Final Report...',
                style: AppTheme.heading(size: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Preparing your complete checkout report.',
                style: AppTheme.body(
                  size: 12,
                  color: AppColors.textGrey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              _progressItem(
                Icons.person_outline,
                'Customer & checkout details',
              ),
              _progressItem(
                Icons.pets_outlined,
                'Goat records',
              ),
              _progressItem(
                Icons.monitor_weight_outlined,
                'Weight history',
              ),
              _progressItem(
                Icons.medical_services_outlined,
                'Health history',
              ),
              _progressItem(
                Icons.calendar_month_outlined,
                'Monthly history',
              ),
              _progressItem(
                Icons.account_balance_wallet_outlined,
                'Payment information',
              ),
              _progressItem(
                Icons.picture_as_pdf_outlined,
                'Generating PDF',
                active: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressItem(
      IconData icon,
      String title, {
        bool active = false,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: active
                ? AppColors.primaryGreen
                : AppColors.textGrey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: active
                    ? AppColors.textDark
                    : AppColors.textGrey,
                fontWeight: active
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          if (active)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryGreen,
              ),
            )
          else
            const Icon(
              Icons.check,
              size: 15,
              color: AppColors.primaryGreen,
            ),
        ],
      ),
    );
  }

  // ========================================================================
  // GENERATED SCREEN
  // ========================================================================

  Widget _buildGenerated() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: AppTheme.card(radius: 22),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.primaryGreen,
                  size: 52,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'PDF Generated',
                style: AppTheme.heading(size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Your final checkout report has been generated successfully.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 12,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  _busy ? null : _downloadPdf,
                  icon: const Icon(
                    Icons.download_rounded,
                  ),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize:
                    const Size.fromHeight(52),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                  _busy ? null : _sharePdf,
                  icon: const Icon(
                    Icons.share_outlined,
                  ),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                    AppColors.darkGreen,
                    minimumSize:
                    const Size.fromHeight(52),
                    side: const BorderSide(
                      color: AppColors.primaryGreen,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                  _doneUnlocked && !_busy
                      ? _finishCheckout
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.darkGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                    Colors.grey.shade300,
                    disabledForegroundColor:
                    Colors.grey.shade600,
                    minimumSize:
                    const Size.fromHeight(52),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    _doneUnlocked
                        ? 'Done'
                        : 'Done — Download or Share First',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _doneUnlocked
                    ? 'Report action completed. You can now finish checkout.'
                    : 'Download or share the report to unlock Done.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================================================
  // HELPERS
  // ========================================================================

  Widget _sectionTitle(
      IconData icon,
      String title,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.darkGreen,
          ),
          const SizedBox(width: 7),
          Text(
            title,
            style: AppTheme.heading(size: 13),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 14),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _infoRow(
      String label,
      String value, {
        bool bold = false,
        Color? valueColor,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: AppTheme.body(
                size: bold ? 13 : 11,
                color:
                valueColor ?? AppColors.textDark,
                weight: bold
                    ? FontWeight.w700
                    : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
      String label,
      String value,
      ) {
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.body(
            size: 13,
            color: AppColors.darkGreen,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTheme.body(
            size: 9,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  Widget _photoStatus(
      IconData icon,
      String title,
      bool available,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: available
            ? AppColors.lightGreen
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(
            available
                ? Icons.check_circle_outline
                : icon,
            size: 15,
            color: available
                ? AppColors.darkGreen
                : AppColors.textGrey,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              available
                  ? '$title available'
                  : '$title missing',
              style: TextStyle(
                fontSize: 9,
                color: available
                    ? AppColors.darkGreen
                    : AppColors.textGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFatalError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _loadReportData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _currency(double value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(value);
  }

  String _date(DateTime value) {
    return DateFormat(
      'dd MMM yyyy',
    ).format(value);
  }
}