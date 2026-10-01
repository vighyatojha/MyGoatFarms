import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/sale_settlement.dart';

/// Shown on the delivery screens when the customer has paid MORE than the
/// final bill (for example 85 kg x 620 = 52,700 against a 60,000 advance).
///
/// It replaces the old "nothing more to collect" line with
/// "Extra ₹7,300" and lets the person choose what happens to that money:
///  * Add to customer's advance (default), or
///  * Return to customer.
///
/// The choice is passed on to SalesService through the payment objects.
class ExcessActionPicker extends StatelessWidget {
  /// The extra amount (must be above 0 for this widget to be shown).
  final double excess;

  final ExcessAction value;

  /// Null disables the choice (for example while saving).
  final ValueChanged<ExcessAction>? onChanged;

  /// Optional, used in the explanation text ("Mohan's advance").
  final String? customerName;

  /// What the extra was paid toward, e.g. "advance" or "booking amount".
  final String paidLabel;

  /// Replaces the default explanation under the "Extra" heading. Used by
  /// the batch screens, where several bookings are delivered together.
  final String? message;

  const ExcessActionPicker({
    super.key,
    required this.excess,
    required this.value,
    required this.onChanged,
    this.customerName,
    this.paidLabel = 'advance',
    this.message,
  });

  String _currency(num amount) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final name = (customerName ?? '').trim();
    final who = name.isEmpty ? 'the customer' : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.30),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Extra ${_currency(excess)}',
                      style: AppTheme.heading(
                        size: 13,
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                message ??
                    'The $paidLabel is ${_currency(excess)} more than the final '
                        'bill, so there is nothing more to collect from $who.',
                style: AppTheme.body(size: 10.5, color: AppColors.textGrey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'What should happen to the extra money?',
          style: AppTheme.body(
            size: 12,
            color: AppColors.textGrey,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ExcessAction.values.map((action) {
            final selected = value == action;

            return ChoiceChip(
              label: Text(action.label),
              selected: selected,
              onSelected: onChanged == null ? null : (_) => onChanged!(action),
              selectedColor: AppColors.primaryGreen.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.darkGreen : AppColors.textDark,
              ),
              side: BorderSide(
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          value == ExcessAction.carryToAdvance
              ? '${_currency(excess)} is kept on $who\'s profile as an '
              'advance balance. It is not farm revenue.'
              : '${_currency(excess)} is handed back to $who and recorded '
              'as a Customer Refund in Finance.',
          style: AppTheme.body(size: 10, color: AppColors.textGrey),
        ),
      ],
    );
  }
}