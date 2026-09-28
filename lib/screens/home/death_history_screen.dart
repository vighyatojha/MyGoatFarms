import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';
import '../../models/death_record.dart';
import '../../services/death_settlement_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../../widgets/Loss_proof.dart';
import 'record_farm_loss_screen.dart';

/// "Farm Losses" — Home Screen / Finance entry point.
///
/// Centralized, farm-wide history across every kind of loss: Customer
/// Palai, Own Palai, Available Stock goat deaths, and manually-logged
/// losses (fire, theft, disease, spoiled feed, storm damage, etc.).
///
/// Recording a goat death still happens from the relevant goat/customer
/// screen (Customer Profile, Own Palai goat profile, Goat Stock detail),
/// per the original feature spec. A manual loss can be recorded directly
/// from here via the "+" button.
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

  Color _typeColor(DeathRecord record) {
    if (record.isManualLoss) return AppColors.error;
    switch (record.goatType) {
      case DeathRecord.typeOwnPalai:
        return AppColors.tradingBlue;
      case DeathRecord.typeAvailableStock:
        return AppColors.warning;
      case DeathRecord.typeCustomerPalai:
      default:
        return AppColors.primaryGreen;
    }
  }

  Future<void> _addProof(DeathRecord record) async {
    if (_farmId == null) return;
    final picked = await pickLossProofImage(context);
    if (picked == null) return;

    try {
      await DeathSettlementService.instance.addLossProof(
        farmId: _farmId!,
        lossId: record.id,
        image: picked,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save photo: $e')),
      );
    }
  }

  Future<void> _openRecordLoss() async {
    if (_farmId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordFarmLossScreen(farmId: _farmId!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Farm Losses'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      floatingActionButton: (_farmId == null)
          ? null
          : FloatingActionButton.extended(
        onPressed: _openRecordLoss,
        backgroundColor: AppColors.error,
        icon: const Icon(Icons.add),
        label: const Text('Record Loss'),
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
                  const SizedBox(width: 8),
                  _filterChip('Other Losses', DeathRecord.typeManualLoss),
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
                      'No losses recorded yet.',
                      style: AppTheme.body(size: 13, color: AppColors.textGrey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
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
    final color = _typeColor(record);

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
                  record.isManualLoss ? record.displayTitle : record.goatLabel,
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

          if (record.isManualLoss) ...[
            if (record.description.trim().isNotEmpty)
              Text(
                record.description,
                style: AppTheme.body(size: 11, color: AppColors.textDark),
              ),
            const SizedBox(height: 6),
            Text(
              '${record.isCashLoss ? 'Cash Loss' : 'Value Loss'}: '
                  '₹${record.farmLossAmount.toStringAsFixed(0)}',
              style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppColors.error),
            ),
            const SizedBox(height: 8),
            if (record.hasProof)
              LossProofThumb(
                farmId: _farmId!,
                lossId: record.id,
                proofCount: record.proofCount,
              )
            else
              InkWell(
                onTap: () => _addProof(record),
                child: Row(
                  children: [
                    const Icon(Icons.add_a_photo_outlined, size: 14, color: AppColors.textGrey),
                    const SizedBox(width: 4),
                    Text(
                      'Add proof',
                      style: AppTheme.body(size: 11, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
          ] else ...[
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
              if (record.goatPendingCharge > 0 ||
                  record.customerAmountToPay > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Goat Pending: ₹${record.goatPendingCharge.toStringAsFixed(0)} · '
                      'Customer Pays: ₹${record.customerAmountToPay.toStringAsFixed(0)}',
                  style: AppTheme.body(size: 11, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  'Customer Pending: ₹${(record.customerPendingBefore ?? 0).toStringAsFixed(0)} → '
                      '₹${(record.customerPendingAfter ?? 0).toStringAsFixed(0)}',
                  style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppColors.textDark),
                ),
              ],
              if (record.hasFarmLoss) ...[
                const SizedBox(height: 4),
                Text(
                  'Farm Loss: ₹${record.farmLossAmount.toStringAsFixed(0)}',
                  style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppColors.error),
                ),
              ] else if (record.paidInFull) ...[
                const SizedBox(height: 4),
                Text(
                  'Paid in full — no loss',
                  style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppColors.primaryGreen),
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
        ],
      ),
    );
  }
}