import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/own_farm_models.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/farm_not_linked_state.dart';

/// Complete health & performance history for one farm-owned goat:
/// weight/growth tracking, health status, vaccination schedule & history,
/// hoof cutting (khud cutting) & hair trimming reminders, medicine
/// records, breeding details and feed/health expenses.
class OwnFarmGoatDetailScreen extends StatefulWidget {
  final OwnFarmGoat goat;
  const OwnFarmGoatDetailScreen({super.key, required this.goat});

  @override
  State<OwnFarmGoatDetailScreen> createState() => _OwnFarmGoatDetailScreenState();
}

class _OwnFarmGoatDetailScreenState extends State<OwnFarmGoatDetailScreen> {
  String? _farmId;
  bool _loadingFarm = true;
  final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  void _loadFarm() {
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() {
        _farmId = id;
        _loadingFarm = false;
      });
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.primaryGreen),
    );
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
    final goat = widget.goat;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          elevation: 0,
          foregroundColor: AppColors.textDark,
          title: Text(goat.goatCode, style: AppTheme.heading(size: 17)),
          bottom: TabBar(
            labelColor: AppColors.primaryGreen,
            unselectedLabelColor: AppColors.textGrey,
            indicatorColor: AppColors.primaryGreen,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Growth'),
              Tab(text: 'Health'),
              Tab(text: 'Breeding'),
              Tab(text: 'Expenses'),
            ],
          ),
        ),
        body: _loadingFarm
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _farmId == null
            ? _buildNotLinkedState()
            : TabBarView(
                children: [
                  _GrowthTab(farmId: _farmId!, goat: goat, dateFmt: _dateFmt, onMessage: _showSnack),
                  _HealthTab(farmId: _farmId!, goat: goat, dateFmt: _dateFmt, onMessage: _showSnack),
                  _BreedingTab(farmId: _farmId!, goat: goat, dateFmt: _dateFmt, onMessage: _showSnack),
                  _ExpensesTab(farmId: _farmId!, goat: goat, dateFmt: _dateFmt, onMessage: _showSnack),
                ],
              ),
      ),
    );
  }
}

// ===========================================================================
// Growth / weight tracking
// ===========================================================================

class _GrowthTab extends StatelessWidget {
  final String farmId;
  final OwnFarmGoat goat;
  final DateFormat dateFmt;
  final void Function(String, {bool isError}) onMessage;

  const _GrowthTab({required this.farmId, required this.goat, required this.dateFmt, required this.onMessage});

  Future<void> _addWeight(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Weight'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Weight in kg'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await FirestoreService.instance.addGrowthRecord(
        farmId,
        goat.id,
        GrowthRecord(id: '', weight: result, recordedAt: DateTime.now()),
      );
      onMessage('Weight logged');
    } catch (e) {
      onMessage(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWeight(context),
        backgroundColor: AppColors.primaryGreen,
        icon: const Icon(Icons.monitor_weight_outlined),
        label: const Text('Log Weight'),
      ),
      body: StreamBuilder<List<GrowthRecord>>(
        stream: FirestoreService.instance.growthRecordsStream(farmId, goat.id),
        builder: (context, snap) {
          final records = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(radius: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current Weight', style: AppTheme.body(size: 11)),
                          Text('${goat.currentWeight.toStringAsFixed(1)} kg', style: AppTheme.heading(size: 20)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Birth Weight', style: AppTheme.body(size: 11)),
                        Text('${goat.birthWeight.toStringAsFixed(1)} kg', style: AppTheme.heading(size: 14)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Weight History', style: AppTheme.heading(size: 14)),
              const SizedBox(height: 10),
              if (records.isEmpty) Text('No weight entries logged yet.', style: AppTheme.body(size: 12)),
              ...records.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.card(radius: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.monitor_weight_outlined, size: 18, color: AppColors.primaryGreen),
                        const SizedBox(width: 10),
                        Text('${r.weight.toStringAsFixed(1)} kg', style: AppTheme.heading(size: 13)),
                        const Spacer(),
                        Text(dateFmt.format(r.recordedAt), style: AppTheme.body(size: 11)),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Health, vaccination, hoof cutting (khud cutting), hair trimming, medicine
// ===========================================================================

class _HealthTab extends StatelessWidget {
  final String farmId;
  final OwnFarmGoat goat;
  final DateFormat dateFmt;
  final void Function(String, {bool isError}) onMessage;

  const _HealthTab({required this.farmId, required this.goat, required this.dateFmt, required this.onMessage});

  Future<void> _addEvent(BuildContext context) async {
    HealthEventType type = HealthEventType.vaccination;
    final descController = TextEditingController();
    DateTime date = DateTime.now();
    // Hoof cutting defaults to a 30/45-day reminder cadence; other event
    // types default to no reminder unless the person sets one.
    int? reminderDays = 30;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add Health Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<HealthEventType>(
                  value: type,
                  isExpanded: true,
                  items: HealthEventType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(HealthEvent(id: '', type: t, description: '', date: date).label)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    type = v ?? type;
                    reminderDays = type == HealthEventType.hoofCutting ? 30 : null;
                  }),
                ),
                TextField(controller: descController, decoration: const InputDecoration(hintText: 'Description / medicine used')),
                const SizedBox(height: 8),
                if (type == HealthEventType.hoofCutting)
                  Row(
                    children: [
                      Text('Remind after: ', style: AppTheme.body(size: 12)),
                      DropdownButton<int>(
                        value: reminderDays,
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 days')),
                          DropdownMenuItem(value: 45, child: Text('45 days')),
                        ],
                        onChanged: (v) => setState(() => reminderDays = v),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await FirestoreService.instance.addHealthEvent(
        farmId,
        goat.id,
        HealthEvent(
          id: '',
          type: type,
          description: descController.text.trim(),
          date: date,
          nextDueDate: reminderDays != null ? date.add(Duration(days: reminderDays!)) : null,
        ),
      );
      onMessage('Health record added');
    } catch (e) {
      onMessage(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEvent(context),
        backgroundColor: AppColors.breedingPurple,
        icon: const Icon(Icons.favorite_border),
        label: const Text('Add Record'),
      ),
      body: StreamBuilder<List<HealthEvent>>(
        stream: FirestoreService.instance.healthEventsStream(farmId, goat.id),
        builder: (context, snap) {
          final events = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(radius: 14),
                child: Row(
                  children: [
                    const Icon(Icons.health_and_safety_outlined, color: AppColors.success, size: 20),
                    const SizedBox(width: 10),
                    Text('Health Status: ${goat.healthStatus}', style: AppTheme.heading(size: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('History', style: AppTheme.heading(size: 14)),
              const SizedBox(height: 10),
              if (events.isEmpty) Text('No health records yet.', style: AppTheme.body(size: 12)),
              ...events.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.card(radius: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_iconFor(e.type), size: 18, color: AppColors.breedingPurple),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.label, style: AppTheme.heading(size: 13)),
                              if (e.description.isNotEmpty) Text(e.description, style: AppTheme.body(size: 11)),
                              Text('On ${dateFmt.format(e.date)}', style: AppTheme.body(size: 11)),
                              if (e.nextDueDate != null)
                                Text('Next due: ${dateFmt.format(e.nextDueDate!)}',
                                    style: AppTheme.body(size: 11, color: AppColors.warning, weight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(HealthEventType type) {
    switch (type) {
      case HealthEventType.vaccination:
        return Icons.vaccines_outlined;
      case HealthEventType.deworming:
        return Icons.medication_liquid_outlined;
      case HealthEventType.hoofCutting:
        return Icons.content_cut;
      case HealthEventType.hairTrimming:
        return Icons.cut;
      case HealthEventType.medicine:
        return Icons.medical_services_outlined;
      case HealthEventType.checkup:
        return Icons.fact_check_outlined;
    }
  }
}

// ===========================================================================
// Breeding
// ===========================================================================

class _BreedingTab extends StatelessWidget {
  final String farmId;
  final OwnFarmGoat goat;
  final DateFormat dateFmt;
  final void Function(String, {bool isError}) onMessage;

  const _BreedingTab({required this.farmId, required this.goat, required this.dateFmt, required this.onMessage});

  Future<void> _addRecord(BuildContext context) async {
    final partnerController = TextEditingController();
    final kidsController = TextEditingController(text: '0');
    DateTime matingDate = DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Breeding Record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: partnerController, decoration: const InputDecoration(hintText: 'Partner Goat ID')),
            TextField(
              controller: kidsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Kids born (if known)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await FirestoreService.instance.addBreedingRecord(
        farmId,
        goat.id,
        BreedingRecord(
          id: '',
          partnerCode: partnerController.text.trim(),
          matingDate: matingDate,
          expectedKiddingDate: matingDate.add(const Duration(days: 150)), // ~5 month goat gestation
          kidsCount: int.tryParse(kidsController.text.trim()) ?? 0,
        ),
      );
      onMessage('Breeding record added');
    } catch (e) {
      onMessage(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addRecord(context),
        backgroundColor: AppColors.breedingPurple,
        icon: const Icon(Icons.family_restroom),
        label: const Text('Add Breeding'),
      ),
      body: StreamBuilder<List<BreedingRecord>>(
        stream: FirestoreService.instance.breedingRecordsStream(farmId, goat.id),
        builder: (context, snap) {
          final records = snap.data ?? [];
          if (records.isEmpty) {
            return Center(child: Text('No breeding records yet.', style: AppTheme.body(size: 12)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
            children: records
                .map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: AppTheme.card(radius: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Partner: ${r.partnerCode.isEmpty ? 'Unknown' : r.partnerCode}', style: AppTheme.heading(size: 13)),
                          const SizedBox(height: 4),
                          Text('Mated: ${dateFmt.format(r.matingDate)}', style: AppTheme.body(size: 11)),
                          if (r.expectedKiddingDate != null)
                            Text('Expected kidding: ${dateFmt.format(r.expectedKiddingDate!)}', style: AppTheme.body(size: 11)),
                          if (r.kidsCount > 0) Text('Kids: ${r.kidsCount}', style: AppTheme.body(size: 11)),
                        ],
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Feed / health expenses
// ===========================================================================

class _ExpensesTab extends StatelessWidget {
  final String farmId;
  final OwnFarmGoat goat;
  final DateFormat dateFmt;
  final void Function(String, {bool isError}) onMessage;

  const _ExpensesTab({required this.farmId, required this.goat, required this.dateFmt, required this.onMessage});

  Future<void> _addExpense(BuildContext context) async {
    String category = 'Feed';
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: category,
                isExpanded: true,
                items: const ['Feed', 'Medicine', 'Vet Visit', 'Other']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v ?? category),
              ),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Amount (₹)'),
              ),
              TextField(controller: notesController, decoration: const InputDecoration(hintText: 'Notes (optional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      onMessage('Enter a valid amount', isError: true);
      return;
    }
    try {
      await FirestoreService.instance.addOwnFarmExpense(
        farmId,
        OwnFarmExpense(
          id: '',
          goatId: goat.id,
          category: category,
          amount: amount,
          date: DateTime.now(),
          notes: notesController.text.trim(),
        ),
      );
      onMessage('Expense recorded');
    } catch (e) {
      onMessage(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addExpense(context),
        backgroundColor: AppColors.warning,
        icon: const Icon(Icons.currency_rupee),
        label: const Text('Add Expense'),
      ),
      body: StreamBuilder<List<OwnFarmExpense>>(
        stream: FirestoreService.instance.ownFarmExpensesStream(farmId, goatId: goat.id),
        builder: (context, snap) {
          final expenses = snap.data ?? [];
          final total = expenses.fold<double>(0, (s, e) => s + e.amount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Spent on ${goat.goatCode}', style: AppTheme.body(size: 11)),
                    Text('₹${total.toStringAsFixed(0)}', style: AppTheme.heading(size: 20)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (expenses.isEmpty) Text('No expenses logged yet.', style: AppTheme.body(size: 12)),
              ...expenses.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.card(radius: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.category, style: AppTheme.heading(size: 13)),
                              Text(dateFmt.format(e.date), style: AppTheme.body(size: 11)),
                            ],
                          ),
                        ),
                        Text('₹${e.amount.toStringAsFixed(0)}', style: AppTheme.heading(size: 13, color: AppColors.error)),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
