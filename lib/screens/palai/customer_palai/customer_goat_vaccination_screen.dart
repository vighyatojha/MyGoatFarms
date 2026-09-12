import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/health_reminder_settings_model.dart';
import '../../../models/palai_models.dart';
import '../../../models/vaccination_record.dart';
import '../../../services/firestore_service.dart';
import '../../../services/health_reminder_scheduler.dart';
import 'add_vaccination_screen.dart';

class CustomerGoatVaccinationScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatVaccinationScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<CustomerGoatVaccinationScreen> createState() =>
      _CustomerGoatVaccinationScreenState();
}

class _CustomerGoatVaccinationScreenState
    extends State<CustomerGoatVaccinationScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // Farm-level Health Reminder Settings (Profile > Health Reminder
  // Settings). Used as a fallback so the summary can show the
  // farm-configured next-due date even when no individual vaccination
  // record has its own nextDueDate set (e.g. records saved before the
  // farm setting existed, or before this reminder was configured).
  HealthReminderSettings? _farmSettings;

  // NOTE: this screen used to fetch a per-customer reminder-day
  // override here and pass it down to AddVaccinationScreen. Health
  // Reminder Settings are farm-level now (Profile > Health Reminder
  // Settings) — AddVaccinationScreen reads them itself via
  // FirestoreService.getHealthReminderSettings.

  @override
  void initState() {
    super.initState();
    _loadFarmSettings();
  }

  Future<void> _loadFarmSettings() async {
    final settings =
    await FirestoreService.instance.getHealthReminderSettings(widget.farmId);

    if (!mounted) return;

    setState(() {
      _farmSettings = settings;
    });
  }

  CollectionReference<Map<String, dynamic>>
  get _vaccinationCollection {
    return _firestore
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('vaccinationRecords');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _vaccinationStream() {
    return _vaccinationCollection
        .orderBy(
      'vaccinationDate',
      descending: true,
    )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _vaccinationStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data?.docs
            .map((doc) => VaccinationRecord.fromDoc(doc))
            .toList() ??
            <VaccinationRecord>[];

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
                          child: _buildVaccinationCard(context, record),
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
  // SECTION HEADER — inline "Add Vaccination" action (matches the
  // Health tab pattern; no FAB, since this is embedded tab content).
  // ===========================================================================

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Vaccination',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openAddVaccinationScreen,
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Add Vaccination'),
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
      List<VaccinationRecord> records,
      ) {
    VaccinationRecord? latest;
    VaccinationRecord? next;

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

    // Fall back to the farm's configured vaccination next-due date
    // when no record carries one of its own.
    final DateTime? effectiveNextDue =
        next?.nextDueDate ?? _farmSettings?.vaccinationNextDueDate;
    final bool isFallback =
        next?.nextDueDate == null && effectiveNextDue != null;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'Vaccination Summary',
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
                Icons.vaccines_outlined,
                title: 'Last vaccination',
                value: latest == null
                    ? '—'
                    : _shortDate(
                  latest.vaccinationDate,
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
                value: effectiveNextDue == null
                    ? 'Not scheduled'
                    : _shortDate(
                  effectiveNextDue,
                ),
                subtitle: isFallback ? 'Farm default' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _summaryCard(
          context,
          icon:
          Icons.format_list_numbered_outlined,
          title: 'Total vaccinations',
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
        String? subtitle,
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
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
          'Vaccination History',
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
              ? 'No vaccinations recorded'
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

  Widget _buildVaccinationCard(
      BuildContext context,
      VaccinationRecord record,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final statusColor =
    record.isOverdue
        ? colors.error
        : record.isDueToday
        ? colors.tertiary
        : colors.primary;

    final statusIcon =
    record.isOverdue
        ? Icons.warning_amber_rounded
        : record.isDueToday
        ? Icons.notifications_active_outlined
        : Icons.event_available_outlined;

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
                  Icons.vaccines_outlined,
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
                      record.vaccineName
                          .trim()
                          .isEmpty
                          ? 'Vaccination'
                          : record.vaccineName,
                      style: theme
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    if (record.disease
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        record.disease,
                        style: theme
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                          color: colors
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Given: ${record.formattedVaccinationDate}',
                      style: theme
                          .textTheme
                          .bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Next: ${record.formattedNextDueDate}',
                      style: theme
                          .textTheme
                          .bodySmall,
                    ),
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
              Icons.vaccines_outlined,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No vaccination records yet',
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
              'Record the first vaccination to start this goat\'s vaccination history.',
              textAlign:
              TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
              _openAddVaccinationScreen,
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Vaccination',
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
      VaccinationRecord record,
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
                  record.vaccineName,
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
                  'Disease / protection',
                  record.disease.isEmpty
                      ? '—'
                      : record.disease,
                ),
                _detailRow(
                  context,
                  'Vaccination date',
                  record
                      .formattedVaccinationDate,
                ),
                _detailRow(
                  context,
                  'Next due',
                  record
                      .formattedNextDueDate,
                ),
                _detailRow(
                  context,
                  'Batch number',
                  record.batchNumber.isEmpty
                      ? '—'
                      : record.batchNumber,
                ),
                _detailRow(
                  context,
                  'Dosage',
                  record.dosage.isEmpty
                      ? '—'
                      : record.dosage,
                ),
                _detailRow(
                  context,
                  'Veterinarian',
                  record.veterinarian.isEmpty
                      ? '—'
                      : record.veterinarian,
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
                if (record.hasNextDueDate)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _markAsDone(record, context),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Done'),
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

  /// Clears this record's reminder — call once the follow-up vaccination
  /// is done and there's nothing further to remind about. Cancels the
  /// on-device scheduled notifications for it and clears any
  /// "due"/"overdue" entry already sitting in the Notifications feed.
  Future<void> _markAsDone(
      VaccinationRecord record,
      BuildContext sheetContext,
      ) async {
    try {
      await _vaccinationCollection.doc(record.id).update({'nextDueDate': null});

      unawaited(HealthReminderScheduler.instance.cancelForCustomerRecord(
        customerId: widget.customerId,
        goatId: widget.goat.id,
        recordType: 'vaccination',
        recordId: record.id,
      ));

      for (final suffix in ['due', 'overdue']) {
        unawaited(FirestoreService.instance
            .markNotificationRead(
          widget.farmId,
          'health_${widget.goat.id}_vaccination_${record.id}_$suffix',
        )
            .catchError((_) {}));
      }

      if (!mounted) return;
      Navigator.of(sheetContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as done — reminder cleared.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark as done: $e')),
      );
    }
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
            width: 145,
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
    await _loadFarmSettings();
    await Future<void>.delayed(
      const Duration(
        milliseconds: 300,
      ),
    );
  }

// ===========================================================================
// ERROR STATE
// ===========================================================================

  Widget _buildErrorState(
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
              size: 52,
              color: colors.error,
            ),
            const SizedBox(height: 14),
            Text(
              'Unable to load vaccination records',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyError(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
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
          return 'You do not have permission to access vaccination records.';

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

  String _shortDate(
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

  void _openAddVaccinationScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => AddVaccinationScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goat: widget.goat,
        ),
      ),
    );
  }
}