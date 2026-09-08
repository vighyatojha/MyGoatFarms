import 'package:flutter/material.dart';

import '../models/monthly_report_model.dart';
import '../services/monthly_report_service.dart';

class MonthlyReportScreen extends StatefulWidget {
  /// The farm whose goats should be included in the report.
  final String farmId;

  const MonthlyReportScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState
    extends State<MonthlyReportScreen> {
  final MonthlyReportService _reportService =
      MonthlyReportService.instance;

  late DateTime _selectedMonth;

  MonthlyReport? _report;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _selectedMonth = DateTime(
      now.year,
      now.month,
    );

    _loadReport();
  }

  // ---------------------------------------------------------------------------
  // LOAD REPORT
  // ---------------------------------------------------------------------------

  Future<void> _loadReport() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final report =
      await _reportService.generateMonthlyReport(
        farmId: widget.farmId,
        month: _selectedMonth,
      );

      if (!mounted) return;

      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // SELECT MONTH
  // ---------------------------------------------------------------------------

  Future<void> _selectMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Select report month',
      initialEntryMode:
      DatePickerEntryMode.calendarOnly,
    );

    if (selected == null) {
      return;
    }

    final month = DateTime(
      selected.year,
      selected.month,
    );

    setState(() {
      _selectedMonth = month;
      _report = null;
    });

    await _loadReport();
  }

  // ---------------------------------------------------------------------------
  // DATE FORMATTING
  // ---------------------------------------------------------------------------

  String _monthName(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[date.month - 1];
  }

  String _formatMonth(DateTime date) {
    return '${_monthName(date)} ${date.year}';
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Report'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _report == null) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 300),
          Center(
            child: CircularProgressIndicator(),
          ),
        ],
      );
    }

    if (_error != null && _report == null) {
      return ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 80),
          const Icon(
            Icons.error_outline,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Unable to generate report',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ),
        ],
      );
    }

    if (_report == null) {
      return ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 80),
          const Icon(
            Icons.description_outlined,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'No report available',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        32,
      ),
      children: [
        _buildMonthSelector(),
        const SizedBox(height: 16),
        _buildReportHeader(),
        const SizedBox(height: 16),
        _buildGoatSection(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MONTH SELECTOR
  // ---------------------------------------------------------------------------

  Widget _buildMonthSelector() {
    return InkWell(
      onTap: _selectMonth,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer,
                borderRadius:
                BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.calendar_month,
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Period',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatMonth(_selectedMonth),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REPORT HEADER
  // ---------------------------------------------------------------------------

  Widget _buildReportHeader() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Farm Report',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(
                fontWeight:
                FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatMonth(_selectedMonth),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GOAT-WISE REPORT
  // ---------------------------------------------------------------------------

  Widget _buildGoatSection() {
    final report = _report!;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(
            left: 4,
            bottom: 10,
          ),
          child: Text(
            'Goat-wise Report',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),

        if (report.goats.isEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.pets_outlined,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No goat activity found',
                    style: TextStyle(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'There are no goats available for ${_formatMonth(_selectedMonth)}.',
                    textAlign:
                    TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...report.goats.map(
                (goat) => _buildGoatCard(goat),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ONE GOAT
  // ---------------------------------------------------------------------------

  Widget _buildGoatCard(
      MonthlyReportGoat goat,
      ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: ExpansionTile(
        leading: const CircleAvatar(
          child: Icon(Icons.pets),
        ),
        title: Text(
          goat.goatName.isEmpty
              ? 'Unnamed Goat'
              : goat.goatName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          goat.tagNumber.isEmpty
              ? 'No tag number'
              : 'Tag: ${goat.tagNumber}',
        ),
        childrenPadding:
        const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16,
        ),
        children: [
          _detailRow(
            'Weight Records',
            goat.weightRecordsCount,
          ),
          _detailRow(
            'Health Records',
            goat.healthRecordsCount,
          ),
          _detailRow(
            'Vaccinations',
            goat.vaccinationCount,
          ),
          _detailRow(
            'Medicines',
            goat.medicineCount,
          ),
          _detailRow(
            'Hoof Cutting',
            goat.hoofCuttingCount,
          ),
          _detailRow(
            'Hair Trimming',
            goat.hairTrimmingCount,
          ),
          _detailRow(
            'Monthly Photos',
            goat.monthlyPhotoCount,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DETAIL ROW
  // ---------------------------------------------------------------------------

  Widget _detailRow(
      String label,
      int value,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}