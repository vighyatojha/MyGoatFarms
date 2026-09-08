import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../palai/customer_palai/goat_profile_screen.dart';

/// Home > Quick Access > Health Records.
///
/// Farm-wide list of every active goat's health checkup / vaccination /
/// hoof-cutting / hair-trimming record, split into three tabs:
///
///   * Pending   — due today, overdue, or due within the next
///     [kHealthRecordPendingWindowDays] days (needs attention soon).
///   * Upcoming  — scheduled further out than that.
///   * Complete  — no reminder set (never had one, or cleared via the
///     "Done" button on the record's detail sheet).
///
/// Within each tab, records are grouped under the goat they belong to
/// (goat name shown, not just its code) so it's easy to see, at a
/// glance, every active goat's standing across all four record types.
///
/// See FirestoreService.allCustomerHealthRecordSummaries for how these
/// are fetched and classified.
class HealthRecordsScreen extends StatefulWidget {
  const HealthRecordsScreen({super.key});

  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String? _farmId;
  bool _loadingFarm = true;

  Future<List<HealthRecordSummary>>? _future;
  final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final farmId = await FirestoreService.instance.currentFarmId();
    if (!mounted) return;
    setState(() {
      _farmId = farmId;
      _loadingFarm = false;
      if (farmId != null) {
        _future = FirestoreService.instance.allCustomerHealthRecordSummaries(farmId);
      }
    });
  }

  Future<void> _refresh() async {
    final farmId = _farmId;
    if (farmId == null) return;
    final future = FirestoreService.instance.allCustomerHealthRecordSummaries(farmId);
    setState(() => _future = future);
    await future;
  }

  IconData _iconFor(String recordType) {
    switch (recordType) {
      case 'health':
        return Icons.monitor_heart_outlined;
      case 'vaccination':
        return Icons.vaccines_outlined;
      case 'hoofCutting':
        return Icons.content_cut;
      case 'hairTrimming':
        return Icons.brush_outlined;
      default:
        return Icons.health_and_safety_outlined;
    }
  }

  int _tabIndexFor(String recordType) {
    switch (recordType) {
      case 'health':
        return 2;
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

  void _openRecord(HealthRecordSummary r) {
    final farmId = _farmId;
    if (farmId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoatProfileScreen(
          farmId: farmId,
          goat: r.goat,
          initialTabIndex: _tabIndexFor(r.recordType),
        ),
      ),
    );
  }

  /// Groups this tab's records by the goat they belong to, and orders
  /// the goats so the most urgent one appears first (soonest/most
  /// overdue due date for Pending/Upcoming, most recently logged for
  /// Complete).
  List<MapEntry<String, List<HealthRecordSummary>>> _groupByGoat(
      List<HealthRecordSummary> items,
      HealthRecordStatus status,
      ) {
    final byGoat = <String, List<HealthRecordSummary>>{};
    for (final r in items) {
      byGoat.putIfAbsent(r.goat.id, () => []).add(r);
    }

    int recordCompare(HealthRecordSummary a, HealthRecordSummary b) {
      if (status == HealthRecordStatus.complete) {
        return b.recordDate.compareTo(a.recordDate); // most recent first
      }
      return a.dueDate!.compareTo(b.dueDate!); // soonest/most-overdue first
    }

    for (final list in byGoat.values) {
      list.sort(recordCompare);
    }

    final entries = byGoat.entries.toList()
      ..sort((a, b) => recordCompare(a.value.first, b.value.first));

    return entries;
  }

  Widget _emptyState(HealthRecordStatus status) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          SizedBox(
            height: 260,
            child: Center(
              child: Text(
                status == HealthRecordStatus.complete
                    ? 'Nothing here yet.'
                    : status == HealthRecordStatus.pending
                    ? 'Nothing due right now.'
                    : 'No upcoming reminders.',
                style: AppTheme.body(size: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatHeader(HealthRecordSummary any) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.pets, size: 15, color: AppColors.darkGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              any.goat.name.isNotEmpty ? any.goat.name : any.goat.goatCode,
              style: AppTheme.heading(size: 14, color: AppColors.darkGreen),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(any.goat.goatCode, style: AppTheme.body(size: 11.5)),
        ],
      ),
    );
  }

  String _pendingSubtitle(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (dueDay.isBefore(today)) return 'Overdue since ${_dateFmt.format(dueDate)}';
    if (dueDay.isAtSameMomentAs(today)) return 'Due today';
    return 'Due soon · ${_dateFmt.format(dueDate)}';
  }

  Widget _recordTile(HealthRecordSummary r, HealthRecordStatus status) {
    final subtitle = status == HealthRecordStatus.complete
        ? 'Logged ${_dateFmt.format(r.recordDate)}'
        : status == HealthRecordStatus.pending
        ? _pendingSubtitle(r.dueDate!)
        : 'Due ${_dateFmt.format(r.dueDate!)}';

    final accentColor = status == HealthRecordStatus.pending
        ? AppColors.error
        : status == HealthRecordStatus.upcoming
        ? AppColors.warning
        : AppColors.primaryGreen;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openRecord(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: accentColor.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(_iconFor(r.recordType), color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.label, style: AppTheme.heading(size: 13)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTheme.body(size: 12, color: accentColor)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textGrey),
          ],
        ),
      ),
    );
  }

  Widget _list(List<HealthRecordSummary> all, HealthRecordStatus status) {
    final items = all.where((r) => r.status == status).toList();
    if (items.isEmpty) return _emptyState(status);

    final groups = _groupByGoat(items, status);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final records = groups[index].value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _goatHeader(records.first),
              ...records.map((r) => _recordTile(r, status)),
            ],
          );
        },
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
        title: Text('Health Records', style: AppTheme.heading(size: 17)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: AppColors.textGrey,
          indicatorColor: AppColors.primaryGreen,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Upcoming'),
            Tab(text: 'Complete'),
          ],
        ),
      ),
      body: _loadingFarm
          ? const Center(child: CircularProgressIndicator())
          : _farmId == null
          ? FarmNotLinkedState(onRetry: _load)
          : FutureBuilder<List<HealthRecordSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 28),
                    const SizedBox(height: 10),
                    Text(
                      'Could not load health records.',
                      style: AppTheme.body(size: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${snapshot.error}',
                      style: AppTheme.body(size: 11, color: AppColors.textGrey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final all = snapshot.data ?? [];
          return TabBarView(
            controller: _tabController,
            children: [
              _list(all, HealthRecordStatus.pending),
              _list(all, HealthRecordStatus.upcoming),
              _list(all, HealthRecordStatus.complete),
            ],
          );
        },
      ),
    );
  }
}