import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../services/customer_goats_report_pdf_service.dart';
import '../../services/firestore_service.dart';

/// Lets the owner generate ONE consolidated report covering all (or a
/// chosen subset of) the goats under a single Palai customer — instead
/// of generating a report per goat one at a time.
class CustomerGoatsReportScreen extends StatefulWidget {
  final String farmId;
  final PalaiCustomer customer;

  const CustomerGoatsReportScreen({
    super.key,
    required this.farmId,
    required this.customer,
  });

  @override
  State<CustomerGoatsReportScreen> createState() =>
      _CustomerGoatsReportScreenState();
}

class _CustomerGoatsReportScreenState
    extends State<CustomerGoatsReportScreen> {
  Stream<List<PalaiGoat>>? _goatsStream;

  final Set<String> _selectedIds = {};
  List<PalaiGoat> _lastLoadedGoats = [];

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _goatsStream = FirestoreService.instance.goatsForCustomerStream(
      widget.farmId,
      widget.customer.id,
    );
  }

  void _toggleSelectAll(List<PalaiGoat> goats) {
    setState(() {
      if (_selectedIds.length == goats.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(goats.map((g) => g.id));
      }
    });
  }

  void _toggleGoat(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  List<PalaiGoat> get _selectedGoats =>
      _lastLoadedGoats.where((g) => _selectedIds.contains(g.id)).toList();

  // ================================================================
  // GENERATE
  // ================================================================

  Future<void> _generate({required bool share}) async {
    if (_selectedGoats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one goat to include in the report.'),
        ),
      );
      return;
    }

    setState(() => _generating = true);

    try {
      final farm = await FirestoreService.instance.getFarmById(widget.farmId);
      final billSettings = farm?.billSettings ?? const BillSettings();

      if (share) {
        await CustomerGoatsReportPdfService.instance.share(
          customer: widget.customer,
          goats: _selectedGoats,
          billSettings: billSettings,
        );
      } else {
        await CustomerGoatsReportPdfService.instance.preview(
          customer: widget.customer,
          goats: _selectedGoats,
          billSettings: billSettings,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate report: $e')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(
          'Goats Report',
          style: AppTheme.heading(size: 17),
        ),
      ),

      body: StreamBuilder<List<PalaiGoat>>(
        stream: _goatsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }

          final goats = snapshot.data ?? [];
          _lastLoadedGoats = goats;

          // Default to everything selected the first time goats load.
          if (_selectedIds.isEmpty && goats.isNotEmpty) {
            _selectedIds.addAll(goats.map((g) => g.id));
          }

          if (goats.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              _buildHeaderCard(goats),
              Expanded(child: _buildGoatsList(goats)),
              _buildBottomBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(List<PalaiGoat> goats) {
    final allSelected = _selectedIds.length == goats.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(radius: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer.name,
                    style: AppTheme.heading(size: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_selectedIds.length} of ${goats.length} goats selected',
                    style: AppTheme.body(size: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _toggleSelectAll(goats),
              child: Text(allSelected ? 'Deselect All' : 'Select All'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoatsList(List<PalaiGoat> goats) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: goats.length,
      itemBuilder: (context, index) {
        final goat = goats[index];
        final selected = _selectedIds.contains(goat.id);

        final goatId = goat.goatCode.trim().isNotEmpty
            ? goat.goatCode
            : (goat.tagNumber.trim().isNotEmpty
            ? goat.tagNumber
            : goat.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: AppTheme.card(radius: 14),
          child: CheckboxListTile(
            value: selected,
            onChanged: (_) => _toggleGoat(goat.id),
            activeColor: AppColors.primaryGreen,
            controlAffinity: ListTileControlAffinity.leading,
            title: Row(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ID: $goatId',
                    style: AppTheme.body(
                      size: 10,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${goat.breed.isNotEmpty ? goat.breed : 'Breed unknown'} • '
                  '${goat.healthStatus.isNotEmpty ? goat.healthStatus : 'No health status'}',
              style: AppTheme.body(size: 11, color: AppColors.textMuted),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _generating ? null : () => _generate(share: false),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.primaryGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _generating ? null : () => _generate(share: true),
                icon: _generating
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.share_outlined),
                label: Text(_generating ? 'Generating...' : 'Share Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pets_outlined,
                size: 35,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 14),
            Text('No goats found', style: AppTheme.heading(size: 15)),
            const SizedBox(height: 6),
            Text(
              'This customer has no goats under Palai yet.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}