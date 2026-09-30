import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/legacy_conversion_plan.dart';
import '../../../services/firestore_service.dart';
import '../../../services/trading_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Bottom sheet that converts older, goat-first purchases into Purchase
/// Lots.
///
/// It always shows a dry run first (what will change, what looks odd) and
/// only writes after the owner confirms. After the conversion it refreshes
/// the dashboard counters once, as the conversion changes what they count.
///
/// Returns true when at least one purchase was converted.
Future<bool?> showLegacyConversionSheet({
  required BuildContext context,
  required String farmId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _LegacyConversionSheet(farmId: farmId),
  );
}

enum _Phase { loading, preview, running, done, failed }

class _LegacyConversionSheet extends StatefulWidget {
  final String farmId;

  const _LegacyConversionSheet({required this.farmId});

  @override
  State<_LegacyConversionSheet> createState() =>
      _LegacyConversionSheetState();
}

class _LegacyConversionSheetState extends State<_LegacyConversionSheet> {
  _Phase _phase = _Phase.loading;

  LegacyConversionPreview? _preview;
  LegacyConversionReport? _report;

  String? _error;

  /// Set when the conversion worked but refreshing the dashboard counters
  /// did not — the owner can still pull to refresh on the dashboard.
  String? _refreshError;

  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });

    try {
      final preview = await TradingService.instance
          .previewLegacyConversion(widget.farmId);

      if (!mounted) return;

      setState(() {
        _preview = preview;
        _phase = _Phase.preview;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = FirestoreService.instance.describeError(error);
        _phase = _Phase.failed;
      });
    }
  }

  Future<void> _convert() async {
    final preview = _preview;
    if (preview == null || preview.isEmpty) return;

    final confirmed = await showWizardConfirm(
      context: context,
      title: 'Convert ${preview.purchaseCount} purchases?',
      message:
      'Each older purchase becomes a Purchase Lot. Goats already '
          'registered stay as they are, no money moves and no Finance '
          'entries are added.',
      confirmLabel: 'Convert',
      icon: Icons.swap_horiz_rounded,
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _phase = _Phase.running;
      _done = 0;
      _total = preview.purchaseCount;
      _refreshError = null;
    });

    try {
      final report = await TradingService.instance
          .convertLegacyPurchasesToLots(
        widget.farmId,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );

      // Conversion changes what the dashboard counters should say
      // (lot stock is counted by farmQty), so recompute them once.
      if (report.convertedCount > 0) {
        try {
          await TradingService.instance
              .backfillDashboardSummary(widget.farmId);
        } catch (error) {
          _refreshError = FirestoreService.instance.describeError(error);
        }
      }

      if (!mounted) return;

      setState(() {
        _report = report;
        _phase = _Phase.done;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = FirestoreService.instance.describeError(error);
        _phase = _Phase.failed;
      });
    }
  }

  void _close() {
    Navigator.of(context).pop((_report?.convertedCount ?? 0) > 0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.running,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Convert Older Purchases',
                    style: AppTheme.heading(size: 19),
                  ),
                  const SizedBox(height: 12),
                  _body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return _centered(
          'Checking your older purchases…',
          showSpinner: true,
        );
      case _Phase.preview:
        return _previewBody();
      case _Phase.running:
        return _runningBody();
      case _Phase.done:
        return _doneBody();
      case _Phase.failed:
        return _failedBody();
    }
  }

  Widget _centered(String text, {bool showSpinner = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            if (showSpinner) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
            ],
            Text(text, style: AppTheme.body(size: 13)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PREVIEW
  // ---------------------------------------------------------------------

  Widget _previewBody() {
    final preview = _preview!;

    if (preview.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WizardNote(
            'Nothing to convert — every purchase is already a lot.',
          ),
          const SizedBox(height: 16),
          _closeButton('Close'),
        ],
      );
    }

    final warnings = preview.warnings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'These purchases were made before Purchase Lots existed. '
              'Converting them lets you receive, pay, sell and transfer '
              'their goats from Lot Management.',
          style: AppTheme.body(size: 12.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: WizardStatTile(
                icon: Icons.receipt_long_outlined,
                label: 'Purchases',
                value: '${preview.purchaseCount}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WizardStatTile(
                icon: Icons.home_work_outlined,
                label: 'Goats at farm',
                value: '${preview.farmGoats}',
              ),
            ),
          ],
        ),
        if (preview.supplierGoats > 0) ...[
          const SizedBox(height: 8),
          WizardStatTile(
            icon: Icons.local_shipping_outlined,
            label: 'Goats still at supplier (receiving pending)',
            value: '${preview.supplierGoats}',
          ),
        ],
        const SizedBox(height: 14),
        const WizardNote(
          'Goats already registered stay as they are. Each purchase is '
              'marked as paid in full, as it was. No money moves and no '
              'Finance entries are added.',
        ),
        if (preview.adjustedCount > 0) ...[
          const SizedBox(height: 8),
          WizardNote(
            '${preview.adjustedCount} purchase(s) had registered or '
                'waiting counts that did not match the goats that exist. '
                'They will be corrected during conversion.',
            tone: WizardNoteTone.warning,
          ),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final w in warnings.take(5)) ...[
            WizardNote(w, tone: WizardNoteTone.warning),
            const SizedBox(height: 6),
          ],
          if (warnings.length > 5)
            Text(
              '…and ${warnings.length - 5} more.',
              style: AppTheme.body(size: 11),
            ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _close,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text('Not now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _convert,
                style: _primaryStyle(),
                child: Text(
                  'Convert ${preview.purchaseCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // RUNNING
  // ---------------------------------------------------------------------

  Widget _runningBody() {
    final value = _total == 0 ? null : _done / _total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: value,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            color: AppColors.primaryGreen,
            backgroundColor: AppColors.lightGreen,
          ),
          const SizedBox(height: 12),
          Text(
            'Converting $_done of $_total…',
            style: AppTheme.body(size: 13, color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            'Please keep the app open.',
            style: AppTheme.body(size: 11),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // DONE
  // ---------------------------------------------------------------------

  Widget _doneBody() {
    final report = _report!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardNote(
          report.convertedCount == 0
              ? 'Nothing was converted.'
              : '${report.convertedCount} purchase(s) converted to lots.',
        ),
        if (report.adjustedIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          WizardNote(
            'Counts corrected on: ${report.adjustedIds.join(', ')}.',
            tone: WizardNoteTone.warning,
          ),
        ],
        if (report.skippedIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          WizardNote(
            'Changed while converting, so left as they were: '
                '${report.skippedIds.join(', ')}. Open this again to '
                'convert them.',
            tone: WizardNoteTone.warning,
          ),
        ],
        if (report.failures.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final f in report.failures.take(5)) ...[
            WizardNote(f, tone: WizardNoteTone.error),
            const SizedBox(height: 6),
          ],
        ],
        for (final w in report.warnings.take(5)) ...[
          const SizedBox(height: 8),
          WizardNote(w, tone: WizardNoteTone.warning),
        ],
        if (_refreshError != null) ...[
          const SizedBox(height: 8),
          WizardNote(
            'Dashboard numbers could not be refreshed ($_refreshError). '
                'Pull down on the Trading dashboard to refresh them.',
            tone: WizardNoteTone.warning,
          ),
        ],
        const SizedBox(height: 16),
        _closeButton('Done'),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // FAILED
  // ---------------------------------------------------------------------

  Widget _failedBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardNote(
          _error ?? 'Something went wrong.',
          tone: WizardNoteTone.error,
        ),
        const SizedBox(height: 8),
        Text(
          'Each purchase converts on its own, so anything that finished '
              'stays converted and the rest is safe to run again.',
          style: AppTheme.body(size: 11.5),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _close,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _loadPreview,
                style: _primaryStyle(),
                child: const Text(
                  'Try Again',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // SHARED
  // ---------------------------------------------------------------------

  ButtonStyle _primaryStyle() => ElevatedButton.styleFrom(
    backgroundColor: AppColors.primaryGreen,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
    ),
  );

  Widget _closeButton(String label) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _close,
        style: _primaryStyle(),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}