import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/death_record.dart';
import '../../services/death_settlement_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';

/// "Goat Death & Settlement" — Home Screen entry point.
///
/// Centralized, farm-wide history across all three cases (Customer
/// Palai, Own Palai, Available Stock). Recording a new death happens
/// from the relevant goat/customer screen itself (Customer Profile,
/// Own Palai goat profile, or Goat Stock detail) — this screen is for
/// quick access and history, per the feature spec.
class DeathHistoryScreen extends StatefulWidget {
  const DeathHistoryScreen({super.key});

  @override
  State<DeathHistoryScreen> createState() => _DeathHistoryScreenState();
}

class _DeathHistoryScreenState extends State<DeathHistoryScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    try {
      final id = await FirestoreService.instance.currentFarmId();
      if (!mounted) return;
      setState(() {
        _farmId = id;
        _loadingFarm = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _farmId = null;
        _loadingFarm = false;
      });
    }
  }

  Color _typeColor(String goatType) {
    switch (goatType) {
      case DeathRecord.typeOwnPalai:
        return AppColors.tradingBlue;
      case DeathRecord.typeAvailableStock:
        return AppColors.warning;
      case DeathRecord.typeCustomerPalai:
      default:
        return AppColors.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Goat Death & Settlement'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: _loadingFarm
          ? const Center(child: CircularProgressIndicator())
          : _farmId == null
          ? FarmNotLinkedState(onRetry: _loadFarm)
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _filterChip('Customer Palai', DeathRecord.typeCustomerPalai),
                  const SizedBox(width: 8),
                  _filterChip('Own Palai', DeathRecord.typeOwnPalai),
                  const SizedBox(width: 8),
                  _filterChip('Available Stock', DeathRecord.typeAvailableStock),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<DeathRecord>>(
              stream: DeathSettlementService.instance.deathHistoryStream(_farmId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final records = snapshot.data!
                    .where((r) => _typeFilter == 'all' || r.goatType == _typeFilter)
                    .toList();

                if (records.isEmpty) {
                  return Center(
                    child: Text(
                      'No goat deaths recorded yet.',
                      style: AppTheme.body(size: 13, color: AppColors.textGrey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _recordCard(records[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _typeFilter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => setState(() => _typeFilter = value),
      selectedColor: AppColors.primaryGreen,
      labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textDark),
      backgroundColor: Colors.white,
    );
  }

  Widget _recordCard(DeathRecord record) {
    final color = _typeColor(record.goatType);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  record.goatTypeLabel,
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.goatLabel,
                  style: AppTheme.heading(size: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                DateFormat('dd MMM yyyy').format(record.deathDate),
                style: AppTheme.body(size: 10, color: AppColors.textGrey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Reason: ${record.reason.isEmpty ? '—' : record.reason}',
            style: AppTheme.body(size: 11, color: AppColors.textDark),
          ),
          if (record.isCustomerPalai) ...[
            const SizedBox(height: 4),
            Text(
              record.customerName ?? '',
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
            if (record.hasSettlement) ...[
              const SizedBox(height: 4),
              Text(
                '${record.isCreditSettlement ? '+' : '-'} ₹${record.settlementAmount.toStringAsFixed(0)} '
                    '${record.isCreditSettlement ? 'Credit' : 'Debit'} · '
                    'Pending ₹${(record.customerPendingBefore ?? 0).toStringAsFixed(0)} → '
                    '₹${(record.customerPendingAfter ?? 0).toStringAsFixed(0)}',
                style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppColors.textDark),
              ),
            ],
          ] else if (record.farmLossAmount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Goat Death Loss: ₹${record.farmLossAmount.toStringAsFixed(0)}',
              style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}