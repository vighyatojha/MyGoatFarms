import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../palai/customer_palai/goat_profile_screen.dart';

class HealthRecordsScreen extends StatefulWidget {
  const HealthRecordsScreen({super.key});

  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen>
    with SingleTickerProviderStateMixin {
  String? _farmId;
  bool _loadingFarm = true;

  Future<List<HealthRecordSummary>>? _future;

  final Map<String, List<HealthRecordSummary>> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final farmId = await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    setState(() {
      _farmId = farmId;
      _loadingFarm = false;
    });
  }

  Future<List<HealthRecordSummary>> _loadRecords() {
    final farmId = _farmId;

    if (farmId == null) {
      return Future.value(<HealthRecordSummary>[]);
    }

    _future ??= FirestoreService.instance
        .allCustomerHealthRecordSummaries(farmId);

    return _future!;
  }

  Future<List<HealthRecordSummary>> _getRecordsForType(
      String type,
      ) async {
    if (_cache.containsKey(type)) {
      return _cache[type]!;
    }

    final all = await _loadRecords();

    final records = all
        .where((record) => record.recordType == type)
        .toList();

    _cache[type] = records;

    return records;
  }

  Future<void> _refresh() async {
    final farmId = _farmId;

    if (farmId == null) return;

    _cache.clear();

    final future = FirestoreService.instance
        .allCustomerHealthRecordSummaries(farmId);

    setState(() {
      _future = future;
    });

    await future;
  }

  /// Marks one Vaccination / Hoof Cutting / Hair Trimming record as
  /// completed (clears its reminder so it reclassifies out of
  /// Pending/Upcoming into Complete), then invalidates the shared
  /// cache/future so the next read — e.g. when the owner backs out to
  /// the status-selection screen and its counts refresh — picks up the
  /// change instead of a stale snapshot.
  Future<void> _markRecordCompleted(HealthRecordSummary record) async {
    final farmId = _farmId;
    if (farmId == null) return;

    await FirestoreService.instance.markHealthCareRecordCompleted(
      farmId,
      record.goat.customerId,
      record.goat.id,
      record.recordType,
      record.recordId,
    );

    _cache.clear();
    _future = null;
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'vaccination':
        return Icons.vaccines_outlined;
      case 'hoofCutting':
        return Icons.content_cut_outlined;
      case 'hairTrimming':
        return Icons.brush_outlined;
      default:
        return Icons.health_and_safety_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'vaccination':
        return AppColors.info;
      case 'hoofCutting':
        return AppColors.primaryGreen;
      case 'hairTrimming':
        return const Color(0xFF7E57C2);
      default:
        return AppColors.primaryGreen;
    }
  }

  String _titleFor(String type) {
    switch (type) {
      case 'vaccination':
        return 'Vaccination';
      case 'hoofCutting':
        return 'Hoof Cutting';
      case 'hairTrimming':
        return 'Hair Trimming';
      default:
        return 'Health';
    }
  }

  String _descriptionFor(String type) {
    switch (type) {
      case 'vaccination':
        return 'Track vaccination schedules and records';
      case 'hoofCutting':
        return 'Manage hoof care schedules and records';
      case 'hairTrimming':
        return 'Manage grooming schedules and records';
      default:
        return 'Manage goat health activities';
    }
  }

  void _openStatusSelection(String type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HealthStatusSelectionScreen(
          farmId: _farmId!,
          recordType: type,
          loader: () => _getRecordsForType(type),
          onRecordTap: _openRecord,
          onMarkCompleted: _markRecordCompleted,
        ),
      ),
    );
  }

  int _profileTabIndex(String type) {
    switch (type) {
      case 'vaccination':
        return 3;
      case 'hoofCutting':
        return 4;
      case 'hairTrimming':
        return 5;
      default:
        return 2;
    }
  }

  void _openRecord(HealthRecordSummary record) {
    final farmId = _farmId;

    if (farmId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoatProfileScreen(
          farmId: farmId,
          goat: record.goat,
          initialTabIndex: _profileTabIndex(record.recordType),
        ),
      ),
    );
  }

  Widget _healthCard({
    required String type,
  }) {
    final color = _colorFor(type);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openStatusSelection(type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withOpacity(0.13),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(type),
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleFor(type),
                    style: AppTheme.heading(
                      size: 16,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _descriptionFor(type),
                    style: AppTheme.body(
                      size: 11.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'View Already Completed • Upcoming • Pending',
                    style: AppTheme.body(
                      size: 9.5,
                      color: color,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHome() {
    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryGreen.withOpacity(0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.025),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: AppColors.darkGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Health',
                        style: AppTheme.heading(
                          size: 19,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage goat health activities',
                        style: AppTheme.body(
                          size: 11.5,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Health Activities',
            style: AppTheme.heading(
              size: 15,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          _healthCard(type: 'vaccination'),
          _healthCard(type: 'hoofCutting'),
          _healthCard(type: 'hairTrimming'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 19,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Health Records',
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: _loadingFarm
          ? const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      )
          : _farmId == null
          ? FarmNotLinkedState(
        onRetry: _loadFarm,
      )
          : _buildHome(),
    );
  }
}

class HealthStatusSelectionScreen extends StatefulWidget {
  final String farmId;
  final String recordType;
  final Future<List<HealthRecordSummary>> Function() loader;
  final void Function(HealthRecordSummary record) onRecordTap;
  final Future<void> Function(HealthRecordSummary record) onMarkCompleted;

  const HealthStatusSelectionScreen({
    super.key,
    required this.farmId,
    required this.recordType,
    required this.loader,
    required this.onRecordTap,
    required this.onMarkCompleted,
  });

  @override
  State<HealthStatusSelectionScreen> createState() =>
      _HealthStatusSelectionScreenState();
}

class _HealthStatusSelectionScreenState
    extends State<HealthStatusSelectionScreen> {
  Future<List<HealthRecordSummary>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  IconData get _icon {
    switch (widget.recordType) {
      case 'vaccination':
        return Icons.vaccines_outlined;
      case 'hoofCutting':
        return Icons.content_cut_outlined;
      case 'hairTrimming':
        return Icons.brush_outlined;
      default:
        return Icons.health_and_safety_outlined;
    }
  }

  Color get _color {
    switch (widget.recordType) {
      case 'vaccination':
        return AppColors.info;
      case 'hoofCutting':
        return AppColors.primaryGreen;
      case 'hairTrimming':
        return const Color(0xFF7E57C2);
      default:
        return AppColors.primaryGreen;
    }
  }

  String get _title {
    switch (widget.recordType) {
      case 'vaccination':
        return 'Vaccination';
      case 'hoofCutting':
        return 'Hoof Cutting';
      case 'hairTrimming':
        return 'Hair Trimming';
      default:
        return 'Health';
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.loader();
    });

    await _future;
  }

  void _openStatus(
      HealthRecordStatus status,
      List<HealthRecordSummary> records,
      ) async {
    // Awaited so that once the owner backs out of the Pending/Upcoming/
    // Complete list (having possibly marked one or more records as
    // completed there), this screen's own counts refresh immediately
    // instead of still showing the pre-completion numbers.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HealthStatusRecordsScreen(
          recordType: widget.recordType,
          status: status,
          records: records,
          onRecordTap: widget.onRecordTap,
          onMarkCompleted: widget.onMarkCompleted,
        ),
      ),
    );

    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 19,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _title,
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: FutureBuilder<List<HealthRecordSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: _color,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading $_title records...',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return _ErrorView(
              onRetry: _refresh,
            );
          }

          final records = snapshot.data ?? [];

          final completed = records
              .where(
                (r) => r.status == HealthRecordStatus.complete,
          )
              .toList();

          final upcoming = records
              .where(
                (r) => r.status == HealthRecordStatus.upcoming,
          )
              .toList();

          final pending = records
              .where(
                (r) => r.status == HealthRecordStatus.pending,
          )
              .toList();

          return RefreshIndicator(
            color: _color,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                30,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _color.withOpacity(0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: _color.withOpacity(0.11),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _icon,
                          color: _color,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Manage $_title records',
                          style: AppTheme.heading(
                            size: 16,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Select Status',
                  style: AppTheme.heading(
                    size: 15,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                _StatusCard(
                  title: 'Already Completed',
                  subtitle: 'View completed $_title records',
                  count: completed.length,
                  icon: Icons.check_circle_outline,
                  color: AppColors.success,
                  onTap: () => _openStatus(
                    HealthRecordStatus.complete,
                    completed,
                  ),
                ),
                _StatusCard(
                  title: 'Upcoming',
                  subtitle: 'View scheduled $_title appointments',
                  count: upcoming.length,
                  icon: Icons.schedule_outlined,
                  color: AppColors.info,
                  onTap: () => _openStatus(
                    HealthRecordStatus.upcoming,
                    upcoming,
                  ),
                ),
                _StatusCard(
                  title: 'Pending',
                  subtitle: 'View $_title records needing attention',
                  count: pending.length,
                  icon: Icons.priority_high_rounded,
                  color: AppColors.warning,
                  onTap: () => _openStatus(
                    HealthRecordStatus.pending,
                    pending,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HealthStatusRecordsScreen extends StatefulWidget {
  final String recordType;
  final HealthRecordStatus status;
  final List<HealthRecordSummary> records;
  final void Function(HealthRecordSummary record) onRecordTap;
  final Future<void> Function(HealthRecordSummary record) onMarkCompleted;

  const HealthStatusRecordsScreen({
    super.key,
    required this.recordType,
    required this.status,
    required this.records,
    required this.onRecordTap,
    required this.onMarkCompleted,
  });

  @override
  State<HealthStatusRecordsScreen> createState() =>
      _HealthStatusRecordsScreenState();
}

class _HealthStatusRecordsScreenState
    extends State<HealthStatusRecordsScreen> {
  // Local, mutable copy of the records passed in — so a record can be
  // removed from THIS list the moment it's marked completed, without
  // waiting on a full re-fetch from Firestore. The parent
  // (HealthStatusSelectionScreen) still refreshes its own counts from
  // Firestore once this screen is popped.
  late List<HealthRecordSummary> _records;

  // recordIds currently being marked completed, so each card can show
  // its own small spinner instead of blocking the whole list.
  final Set<String> _markingIds = {};

  @override
  void initState() {
    super.initState();
    _records = [...widget.records];
  }

  String get _title {
    switch (widget.recordType) {
      case 'vaccination':
        return 'Vaccination';
      case 'hoofCutting':
        return 'Hoof Cutting';
      case 'hairTrimming':
        return 'Hair Trimming';
      default:
        return 'Health';
    }
  }

  Color get _color {
    switch (widget.status) {
      case HealthRecordStatus.complete:
        return AppColors.success;
      case HealthRecordStatus.upcoming:
        return AppColors.info;
      case HealthRecordStatus.pending:
        return AppColors.warning;
    }
  }

  String get _statusTitle {
    switch (widget.status) {
      case HealthRecordStatus.complete:
        return 'Already Completed';
      case HealthRecordStatus.upcoming:
        return 'Upcoming';
      case HealthRecordStatus.pending:
        return 'Pending';
    }
  }

  IconData get _icon {
    switch (widget.recordType) {
      case 'vaccination':
        return Icons.vaccines_outlined;
      case 'hoofCutting':
        return Icons.content_cut_outlined;
      case 'hairTrimming':
        return Icons.brush_outlined;
      default:
        return Icons.health_and_safety_outlined;
    }
  }

  String _date(DateTime date) {
    return DateFormat('d MMM yyyy').format(date);
  }

  String _goatCode(PalaiGoat goat) {
    if (goat.goatCode.trim().isNotEmpty) {
      return goat.goatCode;
    }

    if (goat.tagNumber.trim().isNotEmpty) {
      return goat.tagNumber;
    }

    return goat.id;
  }

  String _subtitle(HealthRecordSummary record) {
    if (widget.status == HealthRecordStatus.complete) {
      return 'Completed · ${_date(record.recordDate)}';
    }

    if (record.dueDate == null) {
      return 'No scheduled date';
    }

    final due = record.dueDate!;
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final dueDay = DateTime(
      due.year,
      due.month,
      due.day,
    );

    if (widget.status == HealthRecordStatus.pending) {
      if (dueDay.isBefore(today)) {
        return 'Overdue · ${_date(due)}';
      }

      if (dueDay.isAtSameMomentAs(today)) {
        return 'Due today';
      }

      return 'Due soon · ${_date(due)}';
    }

    return 'Scheduled · ${_date(due)}';
  }

  Widget _image(PalaiGoat goat) {
    final url = goat.imageUrl?.trim();

    if (url == null || url.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _color.withOpacity(0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.pets,
          color: _color,
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.pets,
              color: _color,
            ),
          );
        },
      ),
    );
  }

  /// Calls the shared completion handler, drops the record from this
  /// screen's own list on success (so it disappears from Pending/
  /// Upcoming immediately), and surfaces a snack bar either way.
  Future<void> _handleMarkCompleted(HealthRecordSummary record) async {
    setState(() => _markingIds.add(record.recordId));

    try {
      await widget.onMarkCompleted(record);
      if (!mounted) return;
      setState(() {
        _records.remove(record);
        _markingIds.remove(record.recordId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as completed.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingIds.remove(record.recordId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not mark as completed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._records];

    if (widget.status == HealthRecordStatus.complete) {
      sorted.sort(
            (a, b) => b.recordDate.compareTo(a.recordDate),
      );
    } else {
      sorted.sort(
            (a, b) => (a.dueDate ?? DateTime(9999))
            .compareTo(b.dueDate ?? DateTime(9999)),
      );
    }

    // The "Mark as Completed" button only makes sense on records that
    // aren't already complete.
    final canMarkCompleted = widget.status != HealthRecordStatus.complete;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 19,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _title,
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(
              16,
              4,
              16,
              12,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _color.withOpacity(0.10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _icon,
                  color: _color,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusTitle,
                    style: AppTheme.heading(
                      size: 14,
                      color: _color,
                    ),
                  ),
                ),
                Text(
                  '${sorted.length}',
                  style: AppTheme.heading(
                    size: 16,
                    color: _color,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sorted.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _icon,
                    size: 45,
                    color: _color.withOpacity(0.30),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No $_statusTitle records found.',
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                16,
                4,
                16,
                28,
              ),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final record = sorted[index];

                final goatName =
                record.goat.name.trim().isNotEmpty
                    ? record.goat.name
                    : _goatCode(record.goat);

                final isMarking = _markingIds.contains(record.recordId);

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onRecordTap(record),
                  child: Container(
                    margin: const EdgeInsets.only(
                      bottom: 11,
                    ),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _color.withOpacity(0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.025),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _image(record.goat),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    goatName,
                                    style: AppTheme.heading(
                                      size: 14,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '#${_goatCode(record.goat)}',
                                    style: AppTheme.body(
                                      size: 10.5,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Container(
                                    padding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _color.withOpacity(0.10),
                                      borderRadius:
                                      BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      widget.status ==
                                          HealthRecordStatus
                                              .complete
                                          ? 'Completed'
                                          : widget.status ==
                                          HealthRecordStatus
                                              .upcoming
                                          ? 'Scheduled'
                                          : 'Pending',
                                      style: AppTheme.body(
                                        size: 9.5,
                                        color: _color,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _subtitle(record),
                                    style: AppTheme.body(
                                      size: 10.5,
                                      color: _color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: AppColors.textGrey,
                            ),
                          ],
                        ),
                        if (canMarkCompleted) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 34,
                            child: OutlinedButton.icon(
                              onPressed: isMarking
                                  ? null
                                  : () => _handleMarkCompleted(record),
                              icon: isMarking
                                  ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.success,
                                ),
                              )
                                  : const Icon(
                                Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: Text(
                                isMarking
                                    ? 'Marking...'
                                    : 'Mark as Completed',
                                style: AppTheme.body(
                                  size: 11.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.success,
                                side: BorderSide(
                                  color: AppColors.success
                                      .withOpacity(0.5),
                                ),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatusCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.055),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: color.withOpacity(0.18),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.heading(
                      size: 14,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTheme.body(
                      size: 10.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  '$count',
                  style: AppTheme.heading(
                    size: 16,
                    color: color,
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textGrey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              'Could not load health records.',
              style: AppTheme.body(
                size: 13,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}