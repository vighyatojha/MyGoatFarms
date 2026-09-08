import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/hoof_cutting_record.dart';
import '../../../models/palai_models.dart';
import '../../../services/firestore_service.dart';
import 'add_hoof_cutting_screen.dart';

class CustomerGoatHoofScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatHoofScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<CustomerGoatHoofScreen> createState() =>
      _CustomerGoatHoofScreenState();
}

class _CustomerGoatHoofScreenState
    extends State<CustomerGoatHoofScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  int _reminderDays = 30;

  @override
  void initState() {
    super.initState();
    _loadReminderSetting();
  }

  Future<void> _loadReminderSetting() async {
    try {
      final doc = await _firestore
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .get();

      final settings = doc.data()?['settings'];

      final rawDays = settings is Map
          ? settings['hoofCuttingReminderDays']
          : null;

      int? days;

      if (rawDays is num) {
        days = rawDays.toInt();
      } else {
        days = int.tryParse(
          rawDays?.toString() ?? '',
        );
      }

      if (mounted && days != null && days > 0) {
        setState(() {
          _reminderDays = days!;
        });
      }
    } catch (_) {}
  }

  CollectionReference<Map<String, dynamic>>
  get _hoofCollection {
    return _firestore
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('hoofCuttingRecords');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _hoofStream() {
    return _hoofCollection
        .orderBy(
      'cuttingDate',
      descending: true,
    )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _hoofStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(
            context,
            snapshot.error,
          );
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final records = snapshot.data?.docs
            .map(
              (doc) => HoofCuttingRecord.fromDoc(doc),
        )
            .toList() ??
            <HoofCuttingRecord>[];

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics:
            const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  24,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      _buildSectionHeader(),
                      const SizedBox(height: 12),
                      _buildSummary(
                        context,
                        records,
                      ),
                      const SizedBox(height: 28),
                      _buildHistoryHeader(
                        context,
                        records.length,
                      ),
                      const SizedBox(height: 12),
                      if (records.isEmpty)
                        _buildEmptyState(context)
                      else
                        ...records.map(
                              (record) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: 10,
                            ),
                            child: _buildHoofCard(
                              context,
                              record,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Hoof Cutting',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openAddHoofScreen,
          icon: const Icon(
            Icons.add,
            size: 15,
          ),
          label: const Text(
            'Add Hoof Cutting',
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            textStyle: const TextStyle(
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(
      BuildContext context,
      List<HoofCuttingRecord> records,
      ) {
    HoofCuttingRecord? latest;
    HoofCuttingRecord? next;

    if (records.isNotEmpty) {
      latest = records.first;

      final scheduled = records
          .where(
            (record) => record.nextDueDate != null,
      )
          .toList();

      if (scheduled.isNotEmpty) {
        scheduled.sort(
              (a, b) => a.nextDueDate!.compareTo(
            b.nextDueDate!,
          ),
        );

        next = scheduled.first;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hoof Cutting Summary',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                context,
                icon: Icons.content_cut,
                title: 'Last cutting',
                value: latest == null
                    ? '—'
                    : _formatDate(
                  latest.cuttingDate,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                context,
                icon: Icons.event_available_outlined,
                title: 'Next due',
                value: next == null
                    ? 'Not scheduled'
                    : _formatDate(
                  next.nextDueDate!,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCurrentStatus(
          context,
          next,
        ),
        const SizedBox(height: 10),
        _summaryCard(
          context,
          icon: Icons.format_list_numbered_outlined,
          title: 'Total cuttings',
          value: records.length.toString(),
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _summaryCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String value,
        bool fullWidth = false,
      }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer,
              ),
              child: Icon(
                icon,
                color: colors.onPrimaryContainer,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                      color:
                      colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: fullWidth ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStatus(
      BuildContext context,
      HoofCuttingRecord? next,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (next == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No upcoming hoof-cutting date is scheduled.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Color statusColor;
    final IconData statusIcon;

    if (next.isOverdue) {
      statusColor = colors.error;
      statusIcon = Icons.warning_amber_rounded;
    } else if (next.isDueToday) {
      statusColor = colors.tertiary;
      statusIcon =
          Icons.notifications_active_outlined;
    } else {
      statusColor = colors.primary;
      statusIcon = Icons.check_circle_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withValues(
                  alpha: 0.12,
                ),
              ),
              child: Icon(
                statusIcon,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current status',
                    style: theme
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                      color:
                      colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    next.dueStatus,
                    style: theme
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryHeader(
      BuildContext context,
      int count,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hoof Cutting History',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          count == 0
              ? 'No hoof-cutting records'
              : '$count ${count == 1 ? 'record' : 'records'}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHoofCard(
      BuildContext context,
      HoofCuttingRecord record,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Color statusColor;
    final IconData statusIcon;

    if (record.isOverdue) {
      statusColor = colors.error;
      statusIcon = Icons.warning_amber_rounded;
    } else if (record.isDueToday) {
      statusColor = colors.tertiary;
      statusIcon =
          Icons.notifications_active_outlined;
    } else {
      statusColor = colors.primary;
      statusIcon = Icons.event_available_outlined;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showRecordDetails(record),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primaryContainer,
                ),
                child: Icon(
                  Icons.content_cut,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hoof cutting',
                      style: theme
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cutting date: ${record.formattedCuttingDate}',
                      style: theme
                          .textTheme
                          .bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Next due: ${record.formattedNextDueDate}',
                      style: theme
                          .textTheme
                          .bodySmall,
                    ),
                    if (record.performedBy
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Performed by: ${record.performedBy}',
                        style: theme
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                    if (record.hasNextDueDate) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius:
                          BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize:
                          MainAxisSize.min,
                          children: [
                            Icon(
                              statusIcon,
                              size: 15,
                              color: statusColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              record.dueStatus,
                              style: theme
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                color: statusColor,
                                fontWeight:
                                FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context,
      ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.content_cut,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No hoof-cutting records',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add the first hoof-cutting record for this goat.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openAddHoofScreen,
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Hoof Cutting',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );

    if (mounted) {
      await _loadReminderSetting();
    }
  }

  Future<void> _showRecordDetails(
      HoofCuttingRecord record,
      ) async {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              4,
              20,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoof Cutting Details',
                  style: theme
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                _detailRow(
                  context,
                  'Cutting date',
                  record.formattedCuttingDate,
                ),
                _detailRow(
                  context,
                  'Next due',
                  record.formattedNextDueDate,
                ),
                if (record.performedBy
                    .trim()
                    .isNotEmpty)
                  _detailRow(
                    context,
                    'Performed by',
                    record.performedBy,
                  ),
                if (record.note.trim().isNotEmpty)
                  _detailRow(
                    context,
                    'Notes',
                    record.note,
                  ),
                if (record.hasNextDueDate)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                        colors.surfaceContainerHighest,
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                      child: Text(
                        record.dueStatus,
                        style: theme
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _markAsDone(record);
                    },
                    child: const Text(
                      'Mark as Completed',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
      BuildContext context,
      String label,
      String value,
      ) {
    if (value.trim().isEmpty ||
        value.trim() == '—') {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: theme
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsDone(
      HoofCuttingRecord record,
      ) async {
    try {
      await _firestore
          .collection('farms')
          .doc(widget.farmId)
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .collection('goats')
          .doc(widget.goat.id)
          .collection('hoofCuttingRecords')
          .doc(record.id)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hoof cutting marked as completed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to update record: $e',
          ),
        ),
      );
    }
  }

  Widget _buildErrorState(
      BuildContext context,
      Object? error,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colors.error,
            ),
            const SizedBox(height: 14),
            Text(
              'Unable to load hoof-cutting records',
              textAlign: TextAlign.center,
              style: theme
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyErrorMessage(error),
              textAlign: TextAlign.center,
              style: theme
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyErrorMessage(
      Object? error,
      ) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to view these records.';

        case 'failed-precondition':
          return 'Firestore needs an index for this query.';

        case 'unavailable':
          return 'The service is temporarily unavailable. Check your internet connection.';

        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
      }
    }

    return 'Something went wrong. Please try again.';
  }

  String _formatDate(
      DateTime date,
      ) {
    final day = date.day
        .toString()
        .padLeft(2, '0');

    final month = date.month
        .toString()
        .padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  void _openAddHoofScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => AddHoofCuttingScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goat: widget.goat,
          reminderDays: _reminderDays,
        ),
      ),
    );
  }
}