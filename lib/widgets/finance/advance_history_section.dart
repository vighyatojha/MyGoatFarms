import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_theme.dart';

/// "Advance History" for one Palai customer: every time their advance went
/// up (an extra amount with a payment, or a Trading-sale excess) or was used
/// up by a bill, read from palaiCustomers/{id}/advanceEntries.
///
/// The current Advance balance shown on the profile still comes from the
/// customer document; this list only explains why it moved.
class AdvanceHistorySection extends StatelessWidget {
  final String farmId;
  final String customerId;

  const AdvanceHistorySection({
    super.key,
    required this.farmId,
    required this.customerId,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('palaiCustomers')
        .doc(customerId)
        .collection('advanceEntries')
        .snapshots();
  }

  String _sourceLabel(Map<String, dynamic> d) {
    switch ((d['source'] ?? '').toString()) {
      case 'tradingSale':
        return 'Trading sale ${(d['saleId'] ?? '').toString()}'.trim();
      case 'palaiPayment':
        return 'Payment ${(d['paymentNumber'] ?? '').toString()}'.trim();
      case 'monthlyBillPayment':
      case 'palaiBill':
        final bill = (d['billNumber'] ?? '').toString();
        return bill.isEmpty ? 'Bill payment' : 'Bill $bill';
      case 'monthlyBill':
        final bill = (d['billNumber'] ?? '').toString();
        return bill.isEmpty ? 'Monthly bill' : 'Monthly bill $bill';
      default:
        return (d['note'] ?? 'Advance').toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(),
      builder: (context, snapshot) {
        // Nothing to show (or still loading / failed): stay out of the way.
        if (!snapshot.hasData) return const SizedBox.shrink();

        final docs = [...snapshot.data!.docs];
        if (docs.isEmpty) return const SizedBox.shrink();

        DateTime when(Map<String, dynamic> d) {
          final v = d['date'] ?? d['createdAt'];
          return v is Timestamp
              ? v.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
        }

        docs.sort((a, b) => when(b.data()).compareTo(when(a.data())));

        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Advance History', style: AppTheme.heading(size: 16)),
              const SizedBox(height: 2),
              Text(
                'Why the advance balance changed',
                style: AppTheme.body(size: 11),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: AppTheme.card(radius: 16),
                child: Column(
                  children: [
                    for (var i = 0; i < docs.length; i++)
                      _row(docs[i].data(), when(docs[i].data()),
                          showDivider: i != docs.length - 1),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> d, DateTime date,
      {required bool showDivider}) {
    final isCredit = (d['type'] ?? '').toString() == 'credit';
    final amount = ((d['amount'] ?? 0) as num).toDouble();
    final color = isCredit ? AppColors.success : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCredit
                      ? Icons.add_rounded
                      : Icons.remove_rounded,
                  color: color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCredit ? 'Added to advance' : 'Used on bill',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.textDark,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _sourceLabel(d),
                      style: AppTheme.body(size: 10, color: AppColors.textGrey),
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(date),
                      style: AppTheme.body(size: 9, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
              Text(
                '${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(0)}',
                style: AppTheme.body(
                  size: 13,
                  color: color,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (showDivider) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.divider.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );
  }
}