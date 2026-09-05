import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';

class IncomeDetailScreen extends StatefulWidget {
  const IncomeDetailScreen({super.key});

  @override
  State<IncomeDetailScreen> createState() =>
      _IncomeDetailScreenState();
}

class _IncomeDetailScreenState
    extends State<IncomeDetailScreen> {
  String? _farmId;
  bool _loadingFarm = true;

  Stream<double>? _monthlyPaymentsStream;
  Stream<double>? _outstandingStream;

  DateTime? _selectedDate;
  bool _showCalendar = false;

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    try {
      final id =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId = id;
        _loadingFarm = false;
        if (id != null) {
          _monthlyPaymentsStream = FirestoreService.instance
              .monthlyPaymentsReceivedStream(id);
          _outstandingStream = FirestoreService.instance
              .totalPendingPaymentsStream(id);
        }
      });
    } catch (e) {
      debugPrint('Income screen farm error: $e');
      if (!mounted) return;
      setState(() => _loadingFarm = false);
    }
  }

  DateTime? _getDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  String _formatDate(dynamic value) {
    final date = _getDate(value);

    if (date == null) {
      return 'Date unavailable';
    }

    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;

    final minute =
    date.minute.toString().padLeft(2, '0');

    final period =
    date.hour >= 12 ? 'PM' : 'AM';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} • '
        '$hour:$minute $period';
  }

  String _formatDayLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  double _number(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  String _rupees(double value) {
    return '₹${value.toStringAsFixed(0)}';
  }

  Widget _buildNotLinkedState() {
    return FarmNotLinkedState(
      buttonColor: AppColors.primaryGreen,
      onRetry: () {
        setState(() => _loadingFarm = true);
        _loadFarm();
      },
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

        title: Text(
          'Income & Payments',
          style: AppTheme.heading(size: 17),
        ),

        actions: [
          IconButton(
            tooltip: 'Browse by date',
            icon: Icon(
              _showCalendar
                  ? Icons.calendar_month
                  : Icons.calendar_month_outlined,
              color: AppColors.primaryGreen,
            ),
            onPressed: () {
              setState(() {
                _showCalendar = !_showCalendar;
              });
            },
          ),
        ],
      ),

      body: _loadingFarm
          ? const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      )
          : _farmId == null
          ? _buildNotLinkedState()
          : Column(
        children: [
          _buildSummaryBoxes(),
          if (_showCalendar) _buildCalendar(),
          if (_selectedDate != null) _buildFilterChip(),
          const SizedBox(height: 4),
          Expanded(
            child: _buildTransactions(),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // SUMMARY BOXES — THIS MONTH'S PAYMENTS + TOTAL OUTSTANDING
  // ================================================================

  Widget _buildSummaryBoxes() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<double>(
              stream: _monthlyPaymentsStream,
              builder: (context, snapshot) {
                final value = snapshot.data ?? 0;
                return _summaryBox(
                  icon: Icons.account_balance_wallet,
                  iconColor: AppColors.success,
                  label: "This Month's Payments",
                  value: snapshot.hasData
                      ? _rupees(value)
                      : '—',
                  valueColor: AppColors.primaryGreen,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<double>(
              stream: _outstandingStream,
              builder: (context, snapshot) {
                final value = snapshot.data ?? 0;
                return _summaryBox(
                  icon: Icons.credit_card_outlined,
                  iconColor: AppColors.error,
                  label: 'Total Outstanding',
                  value: snapshot.hasData
                      ? _rupees(value)
                      : '—',
                  valueColor: AppColors.error,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(size: 18, color: valueColor),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTheme.body(size: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // CALENDAR
  // ================================================================

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: AppTheme.card(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: CalendarDatePicker(
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(DateTime.now().year - 5),
        lastDate: DateTime.now(),
        onDateChanged: (date) {
          setState(() {
            _selectedDate = date;
            _showCalendar = false;
          });
        },
      ),
    );
  }

  Widget _buildFilterChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event,
                  size: 14,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDayLabel(_selectedDate!),
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _selectedDate = null),
            child: Text(
              'Clear',
              style: AppTheme.body(
                size: 12,
                color: AppColors.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // TRANSACTIONS
  // ================================================================

  Widget _buildTransactions() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('farms')
        .doc(_farmId)
        .collection('transactions')
        .orderBy('date', descending: true);

    if (_selectedDate != null) {
      final day = _selectedDate!;
      final startOfDay = DateTime(day.year, day.month, day.day);
      final startOfNextDay = startOfDay.add(const Duration(days: 1));

      query = query
          .where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
      )
          .where(
        'date',
        isLessThan: Timestamp.fromDate(startOfNextDay),
      );
    } else {
      query = query.limit(50);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),

      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(
            snapshot.error.toString(),
          );
        }

        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primaryGreen,
            ),
          );
        }

        final docs =
            snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24,
          ),
          itemCount: docs.length,

          itemBuilder: (context, index) {
            final doc = docs[index];

            return _TransactionCard(
              data: doc.data(),
              dateFormatter: _formatDate,
              rupees: _rupees,
              number: _number,
            );
          },
        );
      },
    );
  }

  // ================================================================
  // EMPTY STATE
  // ================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [
            Container(
              padding:
              const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: AppColors.primaryGreen
                    .withOpacity(0.10),
                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.receipt_long_outlined,
                size: 35,
                color: AppColors.primaryGreen,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              _selectedDate != null
                  ? 'No transactions on this day'
                  : 'No transactions yet',
              style: AppTheme.heading(
                size: 15,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              _selectedDate != null
                  ? 'Try picking a different date from the calendar.'
                  : 'Payments and expenses will appear here automatically.',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // ERROR STATE
  // ================================================================

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.error,
            ),

            const SizedBox(height: 12),

            Text(
              'Could not load transactions',
              style: AppTheme.heading(
                size: 15,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow:
              TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// TRANSACTION CARD
// ====================================================================

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> data;

  final String Function(dynamic) dateFormatter;

  final String Function(double) rupees;

  final double Function(dynamic) number;

  const _TransactionCard({
    required this.data,
    required this.dateFormatter,
    required this.rupees,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIncome =
        data['isIncome'] == true;

    final double amount =
    number(data['amount']);

    final String category =
    (data['category'] ?? 'Transaction')
        .toString();

    final String note =
    (data['note'] ?? '').toString();

    final String customerName =
    (data['customerName'] ?? '')
        .toString();

    final String paymentMethod =
    (data['paymentMethod'] ?? '')
        .toString();

    final String paymentNumber =
    (data['paymentNumber'] ?? '')
        .toString();

    final String billNumber =
    (data['billNumber'] ?? '')
        .toString();

    final double appliedToPending =
    number(
      data['amountAppliedToPending'] ??
          data['amountAppliedToBill'],
    );

    final double advanceAdded =
    number(
      data['advanceAmount'],
    );

    final bool hasPaymentDetails =
        isIncome &&
            (
                customerName.isNotEmpty ||
                    paymentMethod.isNotEmpty ||
                    paymentNumber.isNotEmpty ||
                    billNumber.isNotEmpty ||
                    appliedToPending > 0 ||
                    advanceAdded > 0
            );

    return Container(
      margin:
      const EdgeInsets.only(bottom: 10),

      decoration:
      AppTheme.card(radius: 14),

      child: InkWell(
        borderRadius:
        BorderRadius.circular(14),

        onTap: hasPaymentDetails
            ? () {
          _showDetails(context);
        }
            : null,

        child: Padding(
          padding:
          const EdgeInsets.all(14),

          child: Column(
            children: [
              Row(
                children: [
                  _buildIcon(isIncome),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [
                        Text(
                          category,
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style:
                          AppTheme.heading(
                            size: 13,
                          ),
                        ),

                        if (customerName
                            .isNotEmpty)
                          Padding(
                            padding:
                            const EdgeInsets
                                .only(
                              top: 3,
                            ),
                            child: Text(
                              customerName,
                              maxLines: 1,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                              style:
                              AppTheme.body(
                                size: 11,
                                color:
                                AppColors
                                    .textDark,
                              ),
                            ),
                          ),

                        if (note.isNotEmpty)
                          Padding(
                            padding:
                            const EdgeInsets
                                .only(
                              top: 2,
                            ),
                            child: Text(
                              note,
                              maxLines: 1,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                              style:
                              AppTheme.body(
                                size: 10,
                                color:
                                AppColors
                                    .textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.end,

                    children: [
                      Text(
                        '${isIncome ? '+' : '-'}'
                            '${rupees(amount)}',

                        style:
                        AppTheme.heading(
                          size: 13,
                          color: isIncome
                              ? AppColors
                              .success
                              : AppColors
                              .error,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        dateFormatter(
                          data['date'],
                        ),
                        style:
                        AppTheme.body(
                          size: 9,
                          color: AppColors
                              .textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if (hasPaymentDetails) ...[
                const SizedBox(height: 10),

                Container(
                  width: double.infinity,

                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),

                  decoration:
                  BoxDecoration(
                    color: AppColors
                        .paleGreen,
                    borderRadius:
                    BorderRadius
                        .circular(8),
                  ),

                  child: Row(
                    children: [
                      if (paymentMethod
                          .isNotEmpty) ...[
                        const Icon(
                          Icons
                              .payment_outlined,
                          size: 14,
                          color: AppColors
                              .textMuted,
                        ),
                        const SizedBox(
                          width: 5,
                        ),
                        Text(
                          paymentMethod,
                          style:
                          AppTheme.body(
                            size: 10,
                          ),
                        ),
                      ],

                      if (paymentMethod
                          .isNotEmpty &&
                          (appliedToPending >
                              0 ||
                              advanceAdded >
                                  0))
                        const Padding(
                          padding:
                          EdgeInsets
                              .symmetric(
                            horizontal: 7,
                          ),
                          child: Text(
                            '•',
                          ),
                        ),

                      if (appliedToPending >
                          0)
                        Text(
                          'Pending ${rupees(appliedToPending)}',
                          style:
                          AppTheme.body(
                            size: 10,
                          ),
                        ),

                      if (advanceAdded >
                          0) ...[
                        const Padding(
                          padding:
                          EdgeInsets
                              .symmetric(
                            horizontal: 7,
                          ),
                          child: Text(
                            '•',
                          ),
                        ),

                        Text(
                          'Advance ${rupees(advanceAdded)}',
                          style:
                          AppTheme.body(
                            size: 10,
                            color:
                            AppColors
                                .darkGreen,
                          ),
                        ),
                      ],

                      const Spacer(),

                      const Icon(
                        Icons
                            .chevron_right,
                        size: 16,
                        color: AppColors
                            .textMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(bool isIncome) {
    return Container(
      padding:
      const EdgeInsets.all(10),

      decoration: BoxDecoration(
        color: (isIncome
            ? AppColors.success
            : AppColors.error)
            .withOpacity(0.12),

        shape: BoxShape.circle,
      ),

      child: Icon(
        isIncome
            ? Icons.arrow_downward
            : Icons.arrow_upward,

        color: isIncome
            ? AppColors.success
            : AppColors.error,

        size: 16,
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final bool isIncome =
        data['isIncome'] == true;

    final String customerName =
    (data['customerName'] ?? '')
        .toString();

    final String paymentMethod =
    (data['paymentMethod'] ?? '')
        .toString();

    final String paymentNumber =
    (data['paymentNumber'] ?? '')
        .toString();

    final String billNumber =
    (data['billNumber'] ?? '')
        .toString();

    final double amount =
    number(data['amount']);

    final double pendingBefore =
    number(data['pendingBefore']);

    final double appliedToPending =
    number(
      data['amountAppliedToPending'] ??
          data['amountAppliedToBill'],
    );

    final double pendingAfter =
    number(data['pendingAfter']);

    final double advanceBefore =
    number(data['advanceBefore']);

    final double advanceAdded =
    number(data['advanceAmount']);

    final double advanceAfter =
    number(data['advanceAfter']);

    final String note =
    (data['note'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,

      builder: (context) {
        return Container(
          padding:
          const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            28,
          ),

          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
            const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),

          child: SafeArea(
            child: Column(
              mainAxisSize:
              MainAxisSize.min,

              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration:
                    BoxDecoration(
                      color:
                      Colors.grey.shade300,
                      borderRadius:
                      BorderRadius
                          .circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'Payment Details',
                  style: AppTheme.heading(
                    size: 18,
                  ),
                ),

                const SizedBox(height: 18),

                _detailRow(
                  'Amount',
                  rupees(amount),
                ),

                if (customerName
                    .isNotEmpty)
                  _detailRow(
                    'Customer',
                    customerName,
                  ),

                if (paymentNumber
                    .isNotEmpty)
                  _detailRow(
                    'Payment Number',
                    paymentNumber,
                  ),

                if (billNumber
                    .isNotEmpty)
                  _detailRow(
                    'Bill Number',
                    billNumber,
                  ),

                if (paymentMethod
                    .isNotEmpty)
                  _detailRow(
                    'Payment Method',
                    paymentMethod,
                  ),

                if (pendingBefore > 0)
                  _detailRow(
                    'Pending Before',
                    rupees(pendingBefore),
                  ),

                if (appliedToPending > 0)
                  _detailRow(
                    'Applied to Pending',
                    rupees(appliedToPending),
                  ),

                _detailRow(
                  'Pending After',
                  rupees(pendingAfter),
                ),

                if (advanceBefore > 0)
                  _detailRow(
                    'Advance Before',
                    rupees(advanceBefore),
                  ),

                if (advanceAdded > 0)
                  _detailRow(
                    'Advance Added',
                    rupees(advanceAdded),
                  ),

                if (advanceAfter > 0)
                  _detailRow(
                    'Advance After',
                    rupees(advanceAfter),
                  ),

                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),

                  Text(
                    'Note',
                    style: AppTheme.heading(
                      size: 12,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    note,
                    style: AppTheme.body(
                      size: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,

                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },

                    style:
                    ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors
                          .primaryGreen,
                      foregroundColor:
                      Colors.white,
                      padding:
                      const EdgeInsets
                          .symmetric(
                        vertical: 14,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),

                    child:
                    const Text('Close'),
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
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 5,
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: 12,
                color:
                AppColors.textMuted,
              ),
            ),
          ),

          const SizedBox(width: 15),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.heading(
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// TRANSACTION CARD  — unchanged, keep the existing class below this
// point exactly as it is in your current file.
// ====================================================================