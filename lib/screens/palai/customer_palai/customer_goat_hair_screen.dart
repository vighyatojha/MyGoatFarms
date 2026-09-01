import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/hair_trimming_record.dart';
import '../../../models/palai_models.dart';
import 'add_hair_trimming_screen.dart';

class CustomerGoatHairScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatHairScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<CustomerGoatHairScreen> createState() =>
      _CustomerGoatHairScreenState();
}

class _CustomerGoatHairScreenState
    extends State<CustomerGoatHairScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // Reminder interval for scheduling the next due date, pulled from
  // this customer's settings (CustomerSettingsScreen); falls back to
  // 30 days if the customer has no override saved yet.
  int _reminderDays = 30;

  @override
  void initState() {
    super.initState();
    _loadReminderSetting();
  }

  Future<void> _loadReminderSetting() async {
    try {
      final doc = await _firestore
          .collection('farms')
          .doc(widget.farmId)
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .get();
      final settings = doc.data()?['settings'];
      final days = settings is Map ? settings['hairTrimmingReminderDays'] : null;
      if (mounted && days is int && days > 0) {
        setState(() => _reminderDays = days);
      }
    } catch (_) {
      // Keep the default reminder interval if settings can't be loaded.
    }
  }

  CollectionReference<Map<String, dynamic>>
  get _hairCollection {
    return _firestore
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('hairTrimmingRecords');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _hairStream() {
    return _hairCollection
        .orderBy(
      'trimmingDate',
      descending: true,
    )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _hairStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(context, snapshot.error);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data?.docs
            .map((doc) => HairTrimmingRecord.fromDoc(doc))
            .toList() ??
            <HairTrimmingRecord>[];

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSectionHeader(),
                    const SizedBox(height: 12),
                    _buildSummary(context, records),
                    const SizedBox(height: 28),
                    _buildHistoryHeader(context, records.length),
                    const SizedBox(height: 12),
                    if (records.isEmpty)
                      _buildEmptyState(context)
                    else
                      ...records.map(
                            (record) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildHairCard(context, record),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // SECTION HEADER — inline "Add Hair Trimming" action (matches the
  // Health tab pattern; no FAB, since this is embedded tab content).
  // ===========================================================================

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Hair Trimming',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openAddHairScreen,
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Add Hair Trimming'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildSummary(
      BuildContext context,
      List<HairTrimmingRecord> records,
      ) {
    HairTrimmingRecord? latest;
    HairTrimmingRecord? next;

    if (records.isNotEmpty) {
      latest = records.first;

      final scheduled = records
          .where(
            (record) =>
        record.nextDueDate != null,
      )
          .toList();

      if (scheduled.isNotEmpty) {
        scheduled.sort(
              (a, b) => a.nextDueDate!
              .compareTo(
            b.nextDueDate!,
          ),
        );

        next = scheduled.first;
      }
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'Hair Trimming Summary',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight:
            FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                context,
                icon:
                Icons.content_cut,
                title: 'Last trimming',
                value: latest == null
                    ? '—'
                    : _formatDate(
                  latest.trimmingDate,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                context,
                icon:
                Icons.event_available_outlined,
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
          icon:
          Icons.format_list_numbered_outlined,
          title: 'Total trimmings',
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
                color:
                colors.primaryContainer,
              ),
              child: Icon(
                icon,
                color:
                colors.onPrimaryContainer,
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
                      color: colors
                          .onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: fullWidth ? 2 : 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style: theme
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w800,
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
      HairTrimmingRecord? next,
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
                color:
                colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No upcoming hair-trimming date is scheduled.',
                  style: theme
                      .textTheme
                      .bodyMedium,
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
      statusIcon =
          Icons.warning_amber_rounded;
    } else if (next.isDueToday) {
      statusColor = colors.tertiary;
      statusIcon =
          Icons.notifications_active_outlined;
    } else {
      statusColor = colors.primary;
      statusIcon =
          Icons.check_circle_outline;
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
                      color: colors
                          .onSurfaceVariant,
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
                      fontWeight:
                      FontWeight.w800,
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

  // ===========================================================================
  // HISTORY
  // ===========================================================================

  Widget _buildHistoryHeader(
      BuildContext context,
      int count,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'Hair Trimming History',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight:
            FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          count == 0
              ? 'No hair-trimming records'
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

  Widget _buildHairCard(
      BuildContext context,
      HairTrimmingRecord record,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Color statusColor;
    final IconData statusIcon;

    if (record.isOverdue) {
      statusColor = colors.error;
      statusIcon =
          Icons.warning_amber_rounded;
    } else if (record.isDueToday) {
      statusColor = colors.tertiary;
      statusIcon =
          Icons.notifications_active_outlined;
    } else {
      statusColor = colors.primary;
      statusIcon =
          Icons.event_available_outlined;
    }

    return Card(
      clipBehavior:
      Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _showRecordDetails(record),
        child: Padding(
          padding:
          const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                  colors.primaryContainer,
                ),
                child: Icon(
                  Icons.content_cut,
                  color:
                  colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hair trimming',
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
                      'Trimming date: ${record.formattedTrimmingDate}',
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
                        const EdgeInsets
                            .symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration:
                        BoxDecoration(
                          color: statusColor
                              .withValues(
                            alpha: 0.12,
                          ),
                          borderRadius:
                          BorderRadius
                              .circular(
                            8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize:
                          MainAxisSize.min,
                          children: [
                            Icon(
                              statusIcon,
                              size: 15,
                              color:
                              statusColor,
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            Text(
                              record.dueStatus,
                              style: theme
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                color:
                                statusColor,
                                fontWeight:
                                FontWeight
                                    .w700,
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
        padding:
        const EdgeInsets.all(24),
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
              'No hair-trimming records yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight:
                FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Record the first hair trimming to start this goat\'s hair-care history.',
              textAlign:
              TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
              _openAddHairScreen,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Hair Trimming',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DETAILS
  // ===========================================================================

  void _showRecordDetails(
      HairTrimmingRecord record,
      ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding:
            const EdgeInsets.fromLTRB(
              20,
              4,
              20,
              28,
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Hair Trimming',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(
                  height: 18,
                ),
                _detailRow(
                  context,
                  'Trimming date',
                  record
                      .formattedTrimmingDate,
                ),
                _detailRow(
                  context,
                  'Next due',
                  record
                      .formattedNextDueDate,
                ),
                _detailRow(
                  context,
                  'Performed by',
                  record.performedBy.isEmpty
                      ? '—'
                      : record.performedBy,
                ),
                _detailRow(
                  context,
                  'Notes',
                  record.note.isEmpty
                      ? '—'
                      : record.note,
                ),
                if (record.hasNextDueDate)
                  Padding(
                    padding:
                    const EdgeInsets.only(
                      top: 8,
                    ),
                    child: Container(
                      width:
                      double.infinity,
                      padding:
                      const EdgeInsets.all(
                        12,
                      ),
                      decoration:
                      BoxDecoration(
                        borderRadius:
                        BorderRadius
                            .circular(
                          12,
                        ),
                        color: record.isOverdue
                            ? Theme.of(
                          context,
                        )
                            .colorScheme
                            .errorContainer
                            : Theme.of(
                          context,
                        )
                            .colorScheme
                            .primaryContainer,
                      ),
                      child: Text(
                        record.dueStatus,
                        style: Theme.of(
                          context,
                        )
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                          fontWeight:
                          FontWeight.w700,
                        ),
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
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  Future<void> _refresh() async {
    await Future<void>.delayed(
      const Duration(
        milliseconds: 300,
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  void _showSuccess(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  void _showError(
      BuildContext context,
      String message,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  String _friendlyError(
      Object? error,
      ) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to access hair-trimming records.';

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
    final day =
    date.day.toString().padLeft(
      2,
      '0',
    );

    final month =
    date.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${date.year}';
  }

  // ===========================================================================
  // ERROR STATE
  // ===========================================================================

  Widget _buildErrorState(
      BuildContext context,
      Object? error,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .error,
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to load hair-trimming records',
              textAlign:
              TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight:
                FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyError(error),
              textAlign:
              TextAlign.center,
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

  void _openAddHairScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => AddHairTrimmingScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goat: widget.goat,
          reminderDays: _reminderDays,
        ),
      ),
    );
  }
}