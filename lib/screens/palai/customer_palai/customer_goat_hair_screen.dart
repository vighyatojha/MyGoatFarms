import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/hair_trimming_record.dart';
import '../../../models/palai_goat.dart';

class CustomerGoatHairScreen extends StatefulWidget {
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatHairScreen({
    super.key,
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

  CollectionReference<Map<String, dynamic>>
  get _hairCollection {
    return _firestore
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hair Trimming'),
      ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _hairStream(),
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
                (doc) =>
                HairTrimmingRecord.fromDoc(
                  doc,
                ),
          )
              .toList() ??
              <HairTrimmingRecord>[];

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
                    100,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildGoatHeader(context),
                      const SizedBox(height: 20),
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
                            padding:
                            const EdgeInsets.only(
                              bottom: 10,
                            ),
                            child:
                            _buildHairCard(
                              context,
                              record,
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton:
      FloatingActionButton.extended(
        onPressed:
        _showAddHairDialog,
        icon: const Icon(
          Icons.content_cut,
        ),
        label: const Text(
          'Add Hair Trimming',
        ),
      ),
    );
  }

  // ===========================================================================
  // GOAT HEADER
  // ===========================================================================

  Widget _buildGoatHeader(
      BuildContext context,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildGoatAvatar(context),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.goat.name.trim().isEmpty
                        ? 'Unnamed Goat'
                        : widget.goat.name,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style: theme
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.goat.tagNumber.trim().isEmpty
                        ? 'No tag number'
                        : 'Tag: ${widget.goat.tagNumber}',
                    style: theme
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                      color: colors
                          .onSurfaceVariant,
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

  Widget _buildGoatAvatar(
      BuildContext context,
      ) {
    final imageUrl =
    widget.goat.imageUrl?.trim();

    if (imageUrl != null &&
        imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius:
        BorderRadius.circular(14),
        child: Image.network(
          imageUrl,
          width: 62,
          height: 62,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) =>
              _defaultAvatar(context),
        ),
      );
    }

    return _defaultAvatar(context);
  }

  Widget _defaultAvatar(
      BuildContext context,
      ) {
    final colors =
        Theme.of(context).colorScheme;

    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(14),
        color: colors
            .surfaceContainerHighest,
      ),
      child: Icon(
        Icons.pets_outlined,
        size: 30,
        color: colors
            .onSurfaceVariant,
      ),
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
              _showAddHairDialog,
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
  // ADD HAIR TRIMMING
  // ===========================================================================

  Future<void> _showAddHairDialog() async {
    final performedByController =
    TextEditingController();

    final noteController =
    TextEditingController();

    DateTime trimmingDate =
    DateTime.now();

    DateTime? nextDueDate;

    if (!mounted) {
      performedByController.dispose();
      noteController.dispose();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return AlertDialog(
              title: const Text(
                'Add Hair Trimming',
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      _dateField(
                        context,
                        label:
                        'Trimming date',
                        date:
                        trimmingDate,
                        onTap: () async {
                          final picked =
                          await showDatePicker(
                            context:
                            context,
                            initialDate:
                            trimmingDate,
                            firstDate:
                            DateTime(
                              2000,
                            ),
                            lastDate:
                            DateTime.now(),
                          );

                          if (picked !=
                              null) {
                            setDialogState(
                                  () {
                                trimmingDate =
                                    picked;
                              },
                            );
                          }
                        },
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      _dateField(
                        context,
                        label:
                        'Next due date',
                        date:
                        nextDueDate,
                        optional: true,
                        onTap: () async {
                          final picked =
                          await showDatePicker(
                            context:
                            context,
                            initialDate:
                            nextDueDate ??
                                trimmingDate.add(
                                  const Duration(
                                    days: 30,
                                  ),
                                ),
                            firstDate:
                            trimmingDate,
                            lastDate:
                            DateTime(
                              2100,
                            ),
                          );

                          if (picked !=
                              null) {
                            setDialogState(
                                  () {
                                nextDueDate =
                                    picked;
                              },
                            );
                          }
                        },
                        onClear:
                        nextDueDate == null
                            ? null
                            : () {
                          setDialogState(
                                () {
                              nextDueDate =
                              null;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      TextField(
                        controller:
                        performedByController,
                        textCapitalization:
                        TextCapitalization
                            .words,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Performed by',
                          hintText:
                          'Optional',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      TextField(
                        controller:
                        noteController,
                        maxLines: 3,
                        textCapitalization:
                        TextCapitalization
                            .sentences,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Notes',
                          hintText:
                          'Optional',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                  const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                    setDialogState(
                          () {
                        saving = true;
                      },
                    );

                    try {
                      await _saveHairRecord(
                        trimmingDate:
                        trimmingDate,
                        nextDueDate:
                        nextDueDate,
                        performedBy:
                        performedByController
                            .text
                            .trim(),
                        note:
                        noteController
                            .text
                            .trim(),
                      );

                      if (!context
                          .mounted) {
                        return;
                      }

                      Navigator.pop(
                        dialogContext,
                      );

                      _showSuccess(
                        'Hair trimming recorded successfully.',
                      );
                    } catch (error) {
                      setDialogState(
                            () {
                          saving = false;
                        },
                      );

                      _showError(
                        context,
                        _friendlyError(
                          error,
                        ),
                      );
                    }
                  },
                  child: saving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Save Hair Trimming',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    performedByController.dispose();
    noteController.dispose();
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _saveHairRecord({
    required DateTime trimmingDate,
    required DateTime? nextDueDate,
    required String performedBy,
    required String note,
  }) async {
    final reference =
    _hairCollection.doc();

    final record = HairTrimmingRecord(
      id: reference.id,
      goatId: widget.goat.id,
      trimmingDate: trimmingDate,
      nextDueDate: nextDueDate,
      performedBy: performedBy,
      note: note,
      recordedAt: DateTime.now(),
    );

    await reference.set(
      record.toCreateMap(),
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
  // DATE FIELD
  // ===========================================================================

  Widget _dateField(
      BuildContext context, {
        required String label,
        required DateTime? date,
        required VoidCallback onTap,
        bool optional = false,
        VoidCallback? onClear,
      }) {
    return InkWell(
      borderRadius:
      BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration:
        InputDecoration(
          labelText: label,
          border:
          const OutlineInputBorder(),
          suffixIcon: onClear == null
              ? null
              : IconButton(
            onPressed: onClear,
            icon: const Icon(
              Icons.clear,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                date == null
                    ? optional
                    ? 'Not scheduled'
                    : 'Select date'
                    : _formatDate(date),
              ),
            ),
          ],
        ),
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
}