import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/palai_models.dart';
import '../services/firestore_service.dart';

/// Shared "pick a customer" bottom sheet.
///
/// Used anywhere we need the person to choose which customer an action
/// (register a goat, receive a payment, ...) belongs to before continuing.
///
/// -----------------------------------------------------------------------
/// WHY THIS EXISTS / BUG FIX
/// -----------------------------------------------------------------------
/// The old inline version of this sheet (previously duplicated inside
/// PalaiScreen) bound its StreamBuilder to a `Stream<List<PalaiCustomer>>?`
/// field that was only ever assigned once, inside the parent screen's
/// `initState()`. If that field was created too early, got tied to a
/// listener that stalled (slow first Firestore round-trip, a transient
/// permission/index hiccup, flaky network, etc.), or simply never emitted
/// for any reason, the StreamBuilder had no way out: `ConnectionState
/// .waiting` doesn't change on its own, so the sheet was stuck showing a
/// spinner forever with no error and no retry — this is the "loads
/// infinitely" bug.
///
/// This version fixes that by:
/// 1. Creating a brand-new stream at the moment the sheet actually opens
///    (not relying on a field populated during some earlier async
///    callback), so there's no stale/never-started listener to get stuck
///    on.
/// 2. Wrapping the first snapshot in an explicit timeout. If Firestore
///    hasn't returned anything within [timeout], we stop waiting and show
///    a "Taking longer than expected" state with a Retry button instead
///    of spinning forever.
/// 3. Giving every non-happy path (error, timeout, empty list) a visible,
///    actionable UI state.
///
/// Returns the selected [PalaiCustomer], or `null` if the person closed
/// the sheet without picking one.
Future<PalaiCustomer?> showCustomerSelectionSheet(
    BuildContext context, {
      required String farmId,
      String title = 'Select Customer',
      String subtitle = 'Choose a customer to continue',
    }) {
  return showModalBottomSheet<PalaiCustomer>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _CustomerSelectionSheet(
        farmId: farmId,
        title: title,
        subtitle: subtitle,
      );
    },
  );
}

class _CustomerSelectionSheet extends StatefulWidget {
  final String farmId;
  final String title;
  final String subtitle;

  const _CustomerSelectionSheet({
    required this.farmId,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_CustomerSelectionSheet> createState() => _CustomerSelectionSheetState();
}

class _CustomerSelectionSheetState extends State<_CustomerSelectionSheet> {
  static const _timeout = Duration(seconds: 12);

  late Future<List<PalaiCustomer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Fresh fetch every time — either on first open or on Retry. Never
  /// reuses a stream/future created somewhere else, and always resolves
  /// (data, error, or timeout) instead of hanging indefinitely.
  Future<List<PalaiCustomer>> _load() {
    return FirestoreService.instance
        .customersStream(widget.farmId)
        .first
        .timeout(
      _timeout,
      onTimeout: () => throw TimeoutException(
        'Timed out loading customers',
      ),
    );
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_search, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: AppTheme.heading(size: 17)),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: AppTheme.body(size: 12, color: AppColors.textGrey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade200),
            Flexible(
              child: FutureBuilder<List<PalaiCustomer>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.primaryGreen),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    final isTimeout = snapshot.error is TimeoutException;
                    return SizedBox(
                      height: 220,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isTimeout ? Icons.hourglass_disabled : Icons.error_outline,
                                size: 40,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                isTimeout
                                    ? 'Taking longer than expected to load customers.'
                                    : 'Unable to load customers.',
                                textAlign: TextAlign.center,
                                style: AppTheme.body(size: 13, color: AppColors.error),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                onPressed: _retry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGreen,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final customers = snapshot.data ?? [];

                  if (customers.isEmpty) {
                    return SizedBox(
                      height: 180,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_outline, size: 42, color: AppColors.textGrey),
                            const SizedBox(height: 10),
                            Text(
                              'No customers found.',
                              style: AppTheme.body(size: 13, color: AppColors.textGrey),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return Material(
                        color: AppColors.lightGreen.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).pop(customer),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 21,
                                  backgroundColor: AppColors.primaryGreen,
                                  child: const Icon(Icons.person, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.body(
                                          size: 14,
                                          weight: FontWeight.w600,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        customer.mobileNumber,
                                        style: AppTheme.body(size: 11, color: AppColors.textGrey),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 13,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}