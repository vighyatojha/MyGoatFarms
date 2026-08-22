import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/goat_weight_record.dart';
import '../../../models/palai_models.dart';

class CustomerGoatWeightScreen extends StatefulWidget {
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatWeightScreen({
    super.key,
    required this.customerId,
    required this.goat,
  });

  @override
  State<CustomerGoatWeightScreen> createState() =>
      _CustomerGoatWeightScreenState();
}

class _CustomerGoatWeightScreenState
    extends State<CustomerGoatWeightScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ===========================================================================
  // FIRESTORE REFERENCE
  // ===========================================================================

  CollectionReference<Map<String, dynamic>>
  get _weightCollection {
    return _firestore
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('weightRecords');
  }

  DocumentReference<Map<String, dynamic>>
  get _goatReference {
    return _firestore
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id);
  }

  // ===========================================================================
  // STREAM
  // ===========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _weightStream() {
    return _weightCollection
        .orderBy('date', descending: true)
        .snapshots();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weight Tracking'),
      ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _weightStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(
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
                GoatWeightRecord.fromDoc(
                  doc,
                ),
          )
              .toList() ??
              <GoatWeightRecord>[];

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
                        _buildEmptyHistory(context)
                      else
                        ...records.map(
                              (record) =>
                              Padding(
                                padding:
                                const EdgeInsets.only(
                                  bottom: 10,
                                ),
                                child:
                                _buildWeightCard(
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
        onPressed: _showAddWeightDialog,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'Add Weight',
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
    final colorScheme = theme.colorScheme;

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
                    widget.goat.tagNumber
                        .trim()
                        .isEmpty
                        ? 'No tag number'
                        : 'Tag: ${widget.goat.tagNumber}',
                    style: theme
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                      color: colorScheme
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
              _buildDefaultAvatar(
                context,
              ),
        ),
      );
    }

    return _buildDefaultAvatar(
      context,
    );
  }

  Widget _buildDefaultAvatar(
      BuildContext context,
      ) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(14),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Icon(
        Icons.pets_outlined,
        size: 30,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant,
      ),
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildSummary(
      BuildContext context,
      List<GoatWeightRecord> records,
      ) {
    final latest =
    records.isEmpty ? null : records.first;

    final oldest =
    records.isEmpty ? null : records.last;

    final currentWeight =
        latest?.weight ??
            widget.goat.currentWeight;

    double? overallChange;

    if (oldest != null &&
        latest != null &&
        records.length > 1) {
      overallChange =
          latest.weight - oldest.weight;
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'Growth Summary',
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
              child: _buildSummaryCard(
                context,
                icon:
                Icons.monitor_weight_outlined,
                title: 'Current',
                value: currentWeight == null
                    ? '—'
                    : '${_formatWeight(currentWeight)} kg',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                context,
                icon:
                Icons.trending_up_outlined,
                title: 'Overall Change',
                value: overallChange == null
                    ? '—'
                    : _formatChange(
                  overallChange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                context,
                icon:
                Icons.history_outlined,
                title: 'Measurements',
                value:
                records.length.toString(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                context,
                icon:
                Icons.calendar_today_outlined,
                title: 'Latest Date',
                value: latest == null
                    ? '—'
                    : _formatDate(
                  latest.date,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String value,
      }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: colorScheme.primary,
              size: 22,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style: theme
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                color: colorScheme
                    .onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
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
    );
  }

  // ===========================================================================
  // HISTORY HEADER
  // ===========================================================================

  Widget _buildHistoryHeader(
      BuildContext context,
      int count,
      ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Weight History',
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
                    ? 'No measurements recorded'
                    : '$count ${count == 1 ? 'measurement' : 'measurements'}',
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
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WEIGHT CARD
  // ===========================================================================

  Widget _buildWeightCard(
      BuildContext context,
      GoatWeightRecord record,
      ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final change = record.weightChange;

    final changeColor = change == null
        ? colorScheme.onSurfaceVariant
        : change > 0
        ? colorScheme.primary
        : change < 0
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;

    return Card(
      clipBehavior:
      Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _showRecordDetails(
              record,
            ),
        child: Padding(
          padding:
          const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration:
                BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme
                      .primaryContainer,
                ),
                child: Icon(
                  Icons
                      .monitor_weight_outlined,
                  color: colorScheme
                      .onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.formattedWeight,
                      style: theme
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(
                        record.date,
                      ),
                      style: theme
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                    if (record.note
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 5,
                      ),
                      Text(
                        record.note,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: theme
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (change != null)
                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.end,
                  children: [
                    Icon(
                      change > 0
                          ? Icons
                          .arrow_upward
                          : change < 0
                          ? Icons
                          .arrow_downward
                          : Icons
                          .remove,
                      size: 18,
                      color: changeColor,
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      record
                          .formattedWeightChange,
                      style: theme
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                        color:
                        changeColor,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // EMPTY HISTORY
  // ===========================================================================

  Widget _buildEmptyHistory(
      BuildContext context,
      ) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons
                  .monitor_weight_outlined,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No weight records yet',
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
              'Add the first measurement to start tracking this goat\'s growth.',
              textAlign:
              TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
              _showAddWeightDialog,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add First Weight',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ADD WEIGHT DIALOG
  // ===========================================================================

  Future<void> _showAddWeightDialog() async {
    final weightController =
    TextEditingController();

    final noteController =
    TextEditingController();

    DateTime selectedDate =
    DateTime.now();

    final latestWeight =
    await _getLatestWeight();

    if (!mounted) {
      weightController.dispose();
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
                'Add Weight',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    if (latestWeight != null)
                      Padding(
                        padding:
                        const EdgeInsets.only(
                          bottom: 14,
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
                            color: Theme.of(
                              context,
                            )
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          child: Text(
                            'Previous weight: ${_formatWeight(latestWeight)} kg',
                            style: Theme.of(
                              context,
                            )
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    TextField(
                      controller:
                      weightController,
                      autofocus: true,
                      keyboardType:
                      const TextInputType
                          .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Weight',
                        hintText:
                        'Enter weight in kg',
                        suffixText:
                        'kg',
                        border:
                        OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    InkWell(
                      borderRadius:
                      BorderRadius
                          .circular(
                        12,
                      ),
                      onTap:
                      saving
                          ? null
                          : () async {
                        final picked =
                        await showDatePicker(
                          context:
                          context,
                          initialDate:
                          selectedDate,
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
                              selectedDate =
                                  picked;
                            },
                          );
                        }
                      },
                      child: InputDecorator(
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Measurement date',
                          border:
                          OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons
                                  .calendar_today_outlined,
                              size: 20,
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Text(
                              _formatDate(
                                selectedDate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller:
                      noteController,
                      maxLines: 2,
                      textCapitalization:
                      TextCapitalization
                          .sentences,
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Note (optional)',
                        hintText:
                        'Example: Morning measurement',
                        border:
                        OutlineInputBorder(),
                      ),
                    ),
                  ],
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
                    final weight =
                    double.tryParse(
                      weightController
                          .text
                          .trim(),
                    );

                    if (weight ==
                        null ||
                        weight <= 0) {
                      _showDialogError(
                        context,
                        'Please enter a valid weight.',
                      );
                      return;
                    }

                    setDialogState(
                          () {
                        saving = true;
                      },
                    );

                    try {
                      await _saveWeight(
                        weight: weight,
                        date:
                        selectedDate,
                        note:
                        noteController
                            .text
                            .trim(),
                        previousWeight:
                        latestWeight,
                      );

                      if (!context
                          .mounted) {
                        return;
                      }

                      Navigator.pop(
                        dialogContext,
                      );

                      _showSuccess(
                        'Weight added successfully.',
                      );
                    } catch (error) {
                      setDialogState(
                            () {
                          saving = false;
                        },
                      );

                      _showDialogError(
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
                    'Save Weight',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    weightController.dispose();
    noteController.dispose();
  }

  // ===========================================================================
  // SAVE WEIGHT
  // ===========================================================================

  Future<void> _saveWeight({
    required double weight,
    required DateTime date,
    required String note,
    required double? previousWeight,
  }) async {
    final weightChange =
    previousWeight == null
        ? null
        : weight - previousWeight;

    final recordReference =
    _weightCollection.doc();

    final batch =
    _firestore.batch();

    batch.set(
      recordReference,
      {
        'goatId': widget.goat.id,
        'weight': weight,
        'previousWeight':
        previousWeight,
        'weightChange':
        weightChange,
        'date': Timestamp.fromDate(
          date,
        ),
        'note': note,
        'recordedAt':
        FieldValue.serverTimestamp(),
      },
    );

    // Keep the goat's currentWeight synchronized
    // with the newest measurement.
    batch.update(
      _goatReference,
      {
        'currentWeight': weight,
        'updatedAt':
        FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
  }

  // ===========================================================================
  // GET LATEST WEIGHT
  // ===========================================================================

  Future<double?> _getLatestWeight() async {
    final snapshot =
    await _weightCollection
        .orderBy(
      'date',
      descending: true,
    )
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final record =
      GoatWeightRecord.fromDoc(
        snapshot.docs.first,
      );

      return record.weight;
    }

    return widget.goat.currentWeight;
  }

  // ===========================================================================
  // RECORD DETAILS
  // ===========================================================================

  void _showRecordDetails(
      GoatWeightRecord record,
      ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final change =
            record.weightChange;

        return SafeArea(
          child: Padding(
            padding:
            const EdgeInsets.fromLTRB(
              20,
              4,
              20,
              24,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Weight Details',
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
                  'Weight',
                  record.formattedWeight,
                ),
                _detailRow(
                  context,
                  'Date',
                  _formatDate(
                    record.date,
                  ),
                ),
                _detailRow(
                  context,
                  'Previous weight',
                  record.previousWeight ==
                      null
                      ? '—'
                      : '${_formatWeight(record.previousWeight!)} kg',
                ),
                _detailRow(
                  context,
                  'Change',
                  change == null
                      ? '—'
                      : record
                      .formattedWeightChange,
                ),
                if (record.note
                    .trim()
                    .isNotEmpty)
                  _detailRow(
                    context,
                    'Note',
                    record.note,
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
            width: 130,
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
        milliseconds: 350,
      ),
    );
  }

  // ===========================================================================
  // UI HELPERS
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

  void _showDialogError(
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

  Widget _buildErrorState(
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
            const Icon(
              Icons.error_outline,
              size: 52,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              'Unable to load weight history',
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
            const SizedBox(
              height: 8,
            ),
            Text(
              _friendlyError(error),
              textAlign:
              TextAlign.center,
            ),
            const SizedBox(
              height: 18,
            ),
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

  String _friendlyError(
      Object? error,
      ) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to access these weight records.';

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

  String _formatWeight(
      double weight,
      ) {
    if (weight ==
        weight.roundToDouble()) {
      return weight.toStringAsFixed(0);
    }

    return weight.toStringAsFixed(1);
  }

  String _formatChange(
      double change,
      ) {
    if (change > 0) {
      return '+${_formatWeight(change)} kg';
    }

    if (change < 0) {
      return '${_formatWeight(change)} kg';
    }

    return '0 kg';
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
}