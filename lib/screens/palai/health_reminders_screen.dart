import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import 'customer_palai/goat_profile_screen.dart';

/// Farm-wide list of every goat with a health check due today or
/// overdue — the screen the Goat List's reminders banner opens into.
/// Each tile shows which customer the goat belongs to (fetched
/// alongside, since PalaiGoat only carries a customerId) and jumps
/// straight into that goat's Health tab when tapped.
class HealthRemindersScreen extends StatefulWidget {
  final String farmId;

  const HealthRemindersScreen({super.key, required this.farmId});

  @override
  State<HealthRemindersScreen> createState() => _HealthRemindersScreenState();
}

class _HealthRemindersScreenState extends State<HealthRemindersScreen> {
  late Stream<List<PalaiGoat>> _stream;

  /// customerId -> customer name, filled in lazily as goats stream in
  /// so each tile doesn't have to wait on its own network round trip
  /// before showing anything.
  final Map<String, String> _customerNames = {};

  @override
  void initState() {
    super.initState();
    _stream = FirestoreService.instance.dueHealthReminderGoatsStream(widget.farmId);
  }

  Future<void> _ensureCustomerName(String customerId) async {
    if (_customerNames.containsKey(customerId)) return;
    _customerNames[customerId] = '';
    final customer = await FirestoreService.instance.getCustomer(widget.farmId, customerId);
    if (!mounted) return;
    setState(() => _customerNames[customerId] = customer?.name ?? '');
  }

  bool _isOverdue(PalaiGoat goat) {
    final due = goat.nextHealthCheckDate;
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Health Reminders', style: AppTheme.heading(size: 17)),
      ),
      body: StreamBuilder<List<PalaiGoat>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }

          final goats = snapshot.data ?? [];

          if (goats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.10), shape: BoxShape.circle),
                      child: const Icon(Icons.check_circle_outline, size: 32, color: AppColors.success),
                    ),
                    const SizedBox(height: 14),
                    Text('No health checks due', style: AppTheme.heading(size: 15)),
                    const SizedBox(height: 6),
                    Text(
                      'Every goat with a scheduled next check date is up to date.',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(size: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            );
          }

          for (final goat in goats) {
            _ensureCustomerName(goat.customerId);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: goats.length,
            itemBuilder: (context, index) => _reminderTile(goats[index]),
          );
        },
      ),
    );
  }

  Widget _reminderTile(PalaiGoat goat) {
    final overdue = _isOverdue(goat);
    final color = overdue ? AppColors.error : AppColors.warning;
    final goatId = goat.goatCode.trim().isNotEmpty
        ? goat.goatCode
        : (goat.tagNumber.trim().isNotEmpty ? goat.tagNumber : goat.id);
    final customerName = _customerNames[goat.customerId];
    final due = goat.nextHealthCheckDate;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(radius: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          fastRoute(
            GoatProfileScreen(
              farmId: widget.farmId,
              goat: goat,
              initialTabIndex: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.notifications_active_outlined,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            goat.name.trim().isNotEmpty ? goat.name : goatId,
                            style: AppTheme.heading(size: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('ID: $goatId', style: AppTheme.body(size: 9.5, color: AppColors.primaryGreen)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customerName == null || customerName.isEmpty ? 'Loading…' : customerName,
                      style: AppTheme.body(size: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      due != null
                          ? (overdue ? 'Overdue — was due ${DateFormat('d MMM yyyy').format(due)}' : 'Due today')
                          : 'Due',
                      style: AppTheme.body(size: 11, color: color, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}