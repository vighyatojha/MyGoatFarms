import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_goat.dart';
import '../../../models/vaccination_record.dart';

class CustomerGoatVaccinationScreen extends StatefulWidget {
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatVaccinationScreen({
    super.key,
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

  CollectionReference<Map<String, dynamic>>
  get _vaccinationCollection {
    return _firestore
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vaccination'),
      ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _vaccinationStream(),
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
                VaccinationRecord.fromDoc(
                  doc,
                ),
          )
              .toList() ??
              <VaccinationRecord>[];

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
                            _buildVaccinationCard(
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
        _showAddVaccinationDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Vaccination'),
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
                value: next == null
                    ? 'Not scheduled'
                    : _shortDate(
                  next.nextDueDate!,
                ),
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
              _showAddVaccinationDialog,
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
  // ADD VACCINATION
  // ===========================================================================

  Future<void>
  _showAddVaccinationDialog() async {
    final vaccineController =
    TextEditingController();

    final diseaseController =
    TextEditingController();

    final batchController =
    TextEditingController();

    final dosageController =
    TextEditingController();

    final veterinarianController =
    TextEditingController();

    final noteController =
    TextEditingController();

    DateTime vaccinationDate =
    DateTime.now();

    DateTime? nextDueDate;

    if (!mounted) {
      _disposeControllers(
        [
          vaccineController,
          diseaseController,
          batchController,
          dosageController,
          veterinarianController,
          noteController,
        ],
      );
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
                'Add Vaccination',
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      TextField(
                        controller:
                        vaccineController,
                        autofocus: true,
                        textCapitalization:
                        TextCapitalization
                            .sentences,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Vaccine name *',
                          hintText:
                          'Example: PPR Vaccine',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      TextField(
                        controller:
                        diseaseController,
                        textCapitalization:
                        TextCapitalization
                            .sentences,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Disease / protection',
                          hintText:
                          'Example: PPR',
                          border:
                          OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      _dateField(
                        context,
                        label:
                        'Vaccination date',
                        date:
                        vaccinationDate,
                        onTap: () async {
                          final picked =
                          await showDatePicker(
                            context:
                            context,
                            initialDate:
                            vaccinationDate,
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
                                vaccinationDate =
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
                                vaccinationDate.add(
                                  const Duration(
                                    days: 30,
                                  ),
                                ),
                            firstDate:
                            vaccinationDate,
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
                        batchController,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Batch number',
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
                        dosageController,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Dosage',
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
                        veterinarianController,
                        textCapitalization:
                        TextCapitalization
                            .words,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Veterinarian',
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
                        maxLines: 2,
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
                    final vaccineName =
                    vaccineController
                        .text
                        .trim();

                    if (vaccineName
                        .isEmpty) {
                      _showError(
                        context,
                        'Please enter the vaccine name.',
                      );
                      return;
                    }

                    setDialogState(
                          () {
                        saving = true;
                      },
                    );

                    try {
                      await _saveVaccination(
                        vaccineName:
                        vaccineName,
                        disease:
                        diseaseController
                            .text
                            .trim(),
                        vaccinationDate:
                        vaccinationDate,
                        nextDueDate:
                        nextDueDate,
                        batchNumber:
                        batchController
                            .text
                            .trim(),
                        dosage:
                        dosageController
                            .text
                            .trim(),
                        veterinarian:
                        veterinarianController
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
                        'Vaccination recorded successfully.',
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
                    'Save Vaccination',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeControllers(
      [
        vaccineController,
        diseaseController,
        batchController,
        dosageController,
        veterinarianController,
        noteController,
      ],
    );
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _saveVaccination({
    required String vaccineName,
    required String disease,
    required DateTime vaccinationDate,
    required DateTime? nextDueDate,
    required String batchNumber,
    required String dosage,
    required String veterinarian,
    required String note,
  }) async {
    final reference =
    _vaccinationCollection.doc();

    final record = VaccinationRecord(
      id: reference.id,
      goatId: widget.goat.id,
      vaccineName: vaccineName,
      disease: disease,
      vaccinationDate:
      vaccinationDate,
      nextDueDate: nextDueDate,
      batchNumber: batchNumber,
      dosage: dosage,
      veterinarian: veterinarian,
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

  void _disposeControllers(
      List<TextEditingController>
      controllers,
      ) {
    for (final controller
    in controllers) {
      controller.dispose();
    }
  }
}