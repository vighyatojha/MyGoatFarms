import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import '../palai/add_customer_screen.dart';
import '../palai/check_in_screen.dart';
import '../palai/check_out_screen.dart';

/// Full profile for one Palai customer: contact details, lifetime stats,
/// and every goat they've ever boarded (active and checked-out), newest
/// first. Reached by tapping a customer card on the Customers tab.
///
/// [goatsForCustomerStream] already existed in FirestoreService but had
/// no screen consuming it — this is that screen.
class CustomerProfileScreen extends StatefulWidget {
  final PalaiCustomer customer;
  final String farmId;

  const CustomerProfileScreen({
    super.key,
    required this.customer,
    required this.farmId,
  });

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  // Holds the latest customer record so an edit made from here (via the
  // pencil icon) is reflected immediately without leaving this screen.
  late PalaiCustomer _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<void> _openEdit() async {
    await Navigator.of(context)
        .push(fastRoute(AddCustomerScreen(customer: _customer)));
    // Re-fetch in case the edit changed name/package/pending amount, etc.
    final refreshed =
    await FirestoreService.instance.getCustomer(widget.farmId, _customer.id);
    if (!mounted || refreshed == null) return;
    setState(() => _customer = refreshed);
  }

  Future<void> _openCheckIn() async {
    await Navigator.of(context).push(
      fastRoute(CheckInGoatScreen(presetCustomer: _customer)),
    );
  }

  Color _healthColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;
      case 'Under Observation':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _boardedFor(DateTime checkInDate, DateTime? checkOutDate) {
    final end = checkOutDate ?? DateTime.now();
    int months = (end.year - checkInDate.year) * 12 + (end.month - checkInDate.month);
    DateTime monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    if (monthsAgo.isAfter(end)) {
      months -= 1;
      monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    }
    final days = end.difference(monthsAgo).inDays;
    if (months <= 0) return '$days day${days == 1 ? '' : 's'}';
    if (days <= 0) return '$months month${months == 1 ? '' : 's'}';
    return '$months mo $days d';
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = _customer.pendingAmount > 0;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 0,
        title: Text(_customer.name, style: AppTheme.heading(size: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _openEdit,
            tooltip: 'Edit customer',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCheckIn,
        backgroundColor: AppColors.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Check In Goat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<List<PalaiGoat>>(
        stream: FirestoreService.instance.goatsForCustomerStream(widget.farmId, _customer.id),
        builder: (context, snap) {
          final goats = snap.data ?? [];
          final active = goats.where((g) => !g.isCheckedOut).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              FadeInDown(
                duration: const Duration(milliseconds: 180),
                child: _buildContactCard(hasPending),
              ),
              const SizedBox(height: 14),
              FadeInUp(
                delay: const Duration(milliseconds: 40),
                duration: const Duration(milliseconds: 200),
                child: _buildStatsRow(goats.length, active),
              ),
              const SizedBox(height: 20),
              Text('Goat History', style: AppTheme.heading(size: 15)),
              const SizedBox(height: 10),
              if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                )
              else if (goats.isEmpty)
                _emptyGoatsState()
              else
                ...goats.asMap().entries.map(
                      (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FadeInUp(
                      delay: Duration(milliseconds: 20 * entry.key.clamp(0, 8)),
                      duration: const Duration(milliseconds: 200),
                      child: _goatHistoryCard(entry.value),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContactCard(bool hasPending) {
    return Container(
      decoration: AppTheme.card(radius: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  _customer.name.isNotEmpty ? _customer.name[0].toUpperCase() : '?',
                  style: AppTheme.heading(size: 19, color: AppColors.darkGreen),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_customer.name, style: AppTheme.heading(size: 16)),
                    const SizedBox(height: 3),
                    Text(_customer.mobileNumber, style: AppTheme.body(size: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(10)),
                child: Text(_customer.package, style: AppTheme.body(size: 11, color: AppColors.darkGreen, weight: FontWeight.w600)),
              ),
            ],
          ),
          if (_customer.address.isNotEmpty) ...[
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textGrey),
                const SizedBox(width: 8),
                Expanded(child: Text(_customer.address, style: AppTheme.body(size: 12))),
              ],
            ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.textGrey),
              const SizedBox(width: 8),
              Text('Joined ${DateFormat('dd MMM yyyy').format(_customer.joiningDate)}', style: AppTheme.body(size: 12)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (hasPending ? AppColors.error : AppColors.success).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  hasPending ? 'Pending ₹${_customer.pendingAmount.toStringAsFixed(0)}' : 'No dues',
                  style: AppTheme.body(size: 11, color: hasPending ? AppColors.error : AppColors.success, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int totalGoats, int activeGoats) {
    return Row(
      children: [
        Expanded(child: _statCard(icon: Icons.pets, label: 'Total Goats (All Time)', value: '$totalGoats', color: AppColors.primaryGreen)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(icon: Icons.login, label: 'Currently Boarded', value: '$activeGoats', color: AppColors.info)),
      ],
    );
  }

  Widget _statCard({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      decoration: AppTheme.card(radius: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(value, style: AppTheme.heading(size: 18)),
          Text(label, style: AppTheme.body(size: 11)),
        ],
      ),
    );
  }

  Widget _goatHistoryCard(PalaiGoat goat) {
    final healthColor = _healthColor(goat.healthStatus);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: goat.isCheckedOut
            ? null
            : () => Navigator.of(context).push(fastRoute(CheckOutGoatScreen(goat: goat))),
        child: Container(
          decoration: AppTheme.card(radius: 16),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.lightGreen,
                  border: Border.all(color: healthColor.withOpacity(0.6), width: 2.5),
                ),
                child: ClipOval(
                  child: goat.beforeImage != null
                      ? Image.memory(goat.beforeImage!, fit: BoxFit.cover, width: 48, height: 48)
                      : const Icon(Icons.pets, color: AppColors.primaryGreen),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goat.goatCode, style: AppTheme.heading(size: 13)),
                    const SizedBox(height: 2),
                    Text('${goat.breed} · ${goat.gender}', style: AppTheme.body(size: 11)),
                    const SizedBox(height: 4),
                    Text(
                      goat.isCheckedOut
                          ? 'Checked out · ${_boardedFor(goat.checkInDate, goat.checkOutDate)}'
                          : 'Boarded · ${_boardedFor(goat.checkInDate, null)}',
                      style: AppTheme.body(size: 10, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: goat.isCheckedOut ? AppColors.lightGreen : healthColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  goat.isCheckedOut ? 'Checked Out' : goat.healthStatus,
                  style: AppTheme.body(
                    size: 10,
                    color: goat.isCheckedOut ? AppColors.darkGreen : healthColor,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyGoatsState() {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
              child: const Icon(Icons.pets, size: 34, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 14),
            Text('No goats yet', style: AppTheme.heading(size: 14)),
            const SizedBox(height: 4),
            Text(
              'Goats checked in for ${_customer.name} will show up here.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12),
            ),
          ],
        ),
      ),
    );
  }
}