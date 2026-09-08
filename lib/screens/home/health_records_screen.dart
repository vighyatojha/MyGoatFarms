import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../palai/customer_palai/goat_profile_screen.dart';

/// Home > Quick Access > Health Records.
///
/// Farm-wide list of every vaccination / hoof-cutting / hair-trimming
/// record, across every customer's goats, split into three tabs:
///
///   * Pending   — due today or already overdue.
///   * Upcoming  — due at some point in the future.
///   * Complete  — no reminder set (never had one, or cleared via the
///     "Done" button on the record's detail sheet).
///
/// See FirestoreService.allCustomerHealthRecordSummaries for how these
/// are classified.
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
    if (recordType == 'vaccination') return 3;
    if (recordType == 'hoofCutting') return 4;
    if (recordType == 'hairTrimming') return 5;
    return 2;
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

  Widget _list(List<HealthRecordSummary> all, HealthRecordStatus status) {
    final items = all.where((r) => r.status == status).toList()
      ..sort((a, b) {
        if (status == HealthRecordStatus.complete) {
          return b.recordDate.compareTo(a.recordDate); // most recent first
        }
        // Pending/Upcoming: soonest/most-overdue due date first.
        return a.dueDate!.compareTo(b.dueDate!);
      });

    if (items.isEmpty) {
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

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final r = items[index];
          final subtitle = status == HealthRecordStatus.complete
              ? 'Logged ${_dateFmt.format(r.recordDate)}'
              : r.status == HealthRecordStatus.pending
              ? (r.dueDate!.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
              ? 'Overdue since ${_dateFmt.format(r.dueDate!)}'
              : 'Due today')
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
                        Text('${r.goat.goatCode} · ${r.label}', style: AppTheme.heading(size: 13)),
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
            return Center(child: Text('Could not load health records.', style: AppTheme.body(size: 13)));
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
