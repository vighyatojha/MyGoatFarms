import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../app_theme.dart';
import '../../services/firestore_service.dart';

/// Reached from the "Today's Income" stat card. Shows a running total plus
/// a live list of today's transactions (income and expense) from Firestore.
class IncomeDetailScreen extends StatefulWidget {
  const IncomeDetailScreen({super.key});

  @override
  State<IncomeDetailScreen> createState() => _IncomeDetailScreenState();
}

class _IncomeDetailScreenState extends State<IncomeDetailScreen> {
  String? _farmId;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text("Today's Income", style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<double>(
                    stream: FirestoreService.instance.todaysIncomeStream(_farmId!),
                    builder: (context, snap) {
                      final value = snap.data ?? 0;
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: AppTheme.card(radius: 18),
                        child: Column(
                          children: [
                            Text('Net Income Today', style: AppTheme.body(size: 12)),
                            const SizedBox(height: 6),
                            Text(
                              '₹${value.toStringAsFixed(0)}',
                              style: AppTheme.heading(size: 28, color: AppColors.primaryGreen),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('farms')
                        .doc(_farmId)
                        .collection('transactions')
                        .orderBy('date', descending: true)
                        .limit(30)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Center(child: Text('No transactions yet.', style: AppTheme.body(size: 13)));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final isIncome = data['isIncome'] == true;
                          final amount = (data['amount'] ?? 0).toDouble();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: AppTheme.card(radius: 14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: (isIncome ? AppColors.success : AppColors.error).withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                    color: isIncome ? AppColors.success : AppColors.error,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(data['category'] ?? '', style: AppTheme.heading(size: 13)),
                                      Text(data['note'] ?? '', style: AppTheme.body(size: 11)),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${isIncome ? '+' : '-'}₹${amount.toStringAsFixed(0)}',
                                  style: AppTheme.heading(size: 13, color: isIncome ? AppColors.success : AppColors.error),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
