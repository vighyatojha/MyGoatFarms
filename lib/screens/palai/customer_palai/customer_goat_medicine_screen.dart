import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/medicine_record.dart';
import '../../../models/palai_models.dart';
import 'add_medicine_screen.dart';

class CustomerGoatMedicineScreen extends StatefulWidget {
  final String farmId;
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatMedicineScreen({
    super.key,
    required this.farmId,
    required this.customerId,
    required this.goat,
  });

  @override
  State<CustomerGoatMedicineScreen> createState() =>
      _CustomerGoatMedicineScreenState();
}

class _CustomerGoatMedicineScreenState
    extends State<CustomerGoatMedicineScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>
  get _medicineCollection {
    return _firestore
        .collection('farms')
        .doc(widget.farmId)
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('medicineRecords');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _medicineStream() {
    return _medicineCollection
        .orderBy(
      'treatmentDate',
      descending: true,
    )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _medicineStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(context, snapshot.error);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data?.docs
            .map((doc) => MedicineRecord.fromDoc(doc))
            .toList() ??
            <MedicineRecord>[];

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
                          child: _buildMedicineCard(context, record),
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
  // SECTION HEADER — inline "Add Medicine" action (matches the
  // Health tab pattern; no FAB, since this is embedded tab content).
  // ===========================================================================

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Medicine Records',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openAddMedicineScreen,
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Add Medicine'),
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
      List<MedicineRecord> records,
      ) {
    final latest =
    records.isEmpty ? null : records.first;

    final now = DateTime.now();

    final thisMonthCount = records.where(
          (record) {
        return record.treatmentDate.year ==
            now.year &&
            record.treatmentDate.month ==
                now.month;
      },
    ).length;

    final medicineNames = records
        .map(
          (record) =>
          record.medicineName.trim(),
    )
        .where(
          (name) => name.isNotEmpty,
    )
        .toSet()
        .length;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          'Medicine Summary',
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
                Icons.medication_outlined,
                title: 'Total records',
                value:
                records.length.toString(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                context,
                icon:
                Icons.calendar_month_outlined,
                title: 'This month',
                value:
                thisMonthCount.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                context,
                icon:
                Icons.medical_services_outlined,
                title: 'Medicines used',
                value:
                medicineNames.toString(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                context,
                icon:
                Icons.history,
                title: 'Last treatment',
                value: latest == null
                    ? '—'
                    : _formatDate(
                  latest.treatmentDate,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String value,
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
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
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
          'Medicine History',
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
              ? 'No medicine records'
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

  Widget _buildMedicineCard(
      BuildContext context,
      MedicineRecord record,
      ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
                  Icons.medication_outlined,
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
                      record.medicineName
                          .trim()
                          .isEmpty
                          ? 'Medicine / Treatment'
                          : record.medicineName,
                      maxLines: 2,
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
                    const SizedBox(height: 6),
                    Text(
                      'Date: ${record.formattedTreatmentDate}',
                      style: theme
                          .textTheme
                          .bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.treatmentSummary,
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style: theme
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: colors
                            .onSurfaceVariant,
                      ),
                    ),
                    if (record.reason
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Reason: ${record.reason}',
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: theme
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                    if (record.veterinarian
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Vet: ${record.veterinarian}',
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
              Icons.medication_outlined,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No medicine records yet',
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
              'Record medicines and treatments given to this goat.',
              textAlign:
              TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
              _openAddMedicineScreen,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Medicine',
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
      MedicineRecord record,
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
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration:
                      BoxDecoration(
                        shape:
                        BoxShape.circle,
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .primaryContainer,
                      ),
                      child: Icon(
                        Icons
                            .medication_outlined,
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: Text(
                        record.medicineName
                            .trim()
                            .isEmpty
                            ? 'Medicine / Treatment'
                            : record.medicineName,
                        style: Theme.of(
                          context,
                        )
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight:
                          FontWeight
                              .w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 20,
                ),
                _detailRow(
                  context,
                  'Treatment date',
                  record
                      .formattedTreatmentDate,
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
                  'Frequency',
                  record.frequency.isEmpty
                      ? '—'
                      : record.frequency,
                ),
                _detailRow(
                  context,
                  'Duration',
                  record.durationText,
                ),
                _detailRow(
                  context,
                  'Reason',
                  record.reason.isEmpty
                      ? '—'
                      : record.reason,
                ),
                _detailRow(
                  context,
                  'Administered by',
                  record.administeredBy
                      .isEmpty
                      ? '—'
                      : record.administeredBy,
                ),
                _detailRow(
                  context,
                  'Veterinarian',
                  record.veterinarian
                      .isEmpty
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
  // TEXT FIELD
  // ===========================================================================

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    IconData? icon,
    bool required = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization:
      TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: required
            ? '$label *'
            : label,
        hintText: hint,
        border:
        const OutlineInputBorder(),
        prefixIcon: icon == null
            ? null
            : Icon(icon),
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
  // CONTROLLER CLEANUP
  // ===========================================================================

  void _disposeControllers(
      List<TextEditingController>
      controllers,
      ) {
    for (final controller
    in controllers) {
      controller.dispose();
    }
  }

  // ===========================================================================
  // FEEDBACK
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
          return 'You do not have permission to access medicine records.';

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
              'Unable to load medicine records',
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

  void _openAddMedicineScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => AddMedicineScreen(
          farmId: widget.farmId,
          customerId: widget.customerId,
          goat: widget.goat,
        ),
      ),
    );
  }
}