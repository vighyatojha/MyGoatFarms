import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/payment_reminder_service.dart';

/// Bottom sheet for sending WhatsApp payment reminders.
///
/// Pass every customer who should get one (already filtered to
/// pendingAmount > 0). Each row builds that customer's own message and
/// opens WhatsApp for it; a tick appears once it has been opened so the
/// owner can see who is left when working down the list.
Future<void> showPaymentReminderSheet(
    BuildContext context, {
      required List<PalaiCustomer> customers,
      required String farmName,
    }) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _PaymentReminderSheet(customers: customers, farmName: farmName),
      );
    },
  );
}

class _PaymentReminderSheet extends StatefulWidget {
  final List<PalaiCustomer> customers;
  final String farmName;

  const _PaymentReminderSheet({
    required this.customers,
    required this.farmName,
  });

  @override
  State<_PaymentReminderSheet> createState() => _PaymentReminderSheetState();
}

class _PaymentReminderSheetState extends State<_PaymentReminderSheet> {
  final _service = PaymentReminderService.instance;
  final _daysController = TextEditingController(
    text: PaymentReminderService.defaultDays.toString(),
  );
  final Set<String> _sent = {};

  @override
  void initState() {
    super.initState();
    _service.loadDays().then((days) {
      if (!mounted) return;
      setState(() => _daysController.text = days.toString());
    });
  }

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  int get _days {
    final parsed = int.tryParse(_daysController.text.trim()) ?? 0;
    return parsed < 1 ? 1 : parsed;
  }

  String _messageFor(PalaiCustomer c) => _service.buildMessage(
    customerName: c.name,
    pendingAmount: c.pendingAmount,
    days: _days,
    farmName: widget.farmName,
  );

  Future<void> _send(PalaiCustomer c) async {
    await _service.saveDays(_days);

    final opened = await _service.openWhatsApp(
      mobile: c.mobileNumber,
      message: _messageFor(c),
    );

    if (!mounted) return;

    if (opened) {
      setState(() => _sent.add(c.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _service.normalizePhone(c.mobileNumber) == null
                ? "${c.name}'s mobile number looks invalid."
                : 'Could not open WhatsApp.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = widget.customers;
    final total = customers.fold<double>(0, (sum, c) => sum + c.pendingAmount);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Send Payment Reminder', style: AppTheme.heading(size: 17)),
              const SizedBox(height: 2),
              Text(
                customers.length == 1
                    ? '1 customer • ${_service.formatAmount(total)} pending'
                    : '${customers.length} customers • '
                    '${_service.formatAmount(total)} pending in total',
                style: AppTheme.body(size: 12, color: AppColors.textGrey),
              ),
              const SizedBox(height: 12),

              // Days to pay
              Row(
                children: [
                  Text(
                    'Time to pay:',
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.textDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _daysController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      style: AppTheme.body(size: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('days', style: AppTheme.body(size: 13)),
                ],
              ),
              const SizedBox(height: 12),

              // Live preview using the first customer's real numbers
              if (customers.isNotEmpty) ...[
                Text(
                  'Message preview',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCF8C6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _messageFor(customers.first).replaceAll('*', ''),
                    style: AppTheme.body(size: 12, color: AppColors.textDark),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Customer rows
              Flexible(
                child: customers.isEmpty
                    ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No customers have a pending amount.',
                      style: AppTheme.body(size: 13),
                    ),
                  ),
                )
                    : ListView.separated(
                  shrinkWrap: true,
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _row(customers[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(PalaiCustomer c) {
    final sent = _sent.contains(c.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: AppTheme.card(radius: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_service.formatAmount(c.pendingAmount)} pending',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.error,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (sent)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 20,
              ),
            ),
          FilledButton.icon(
            onPressed: () => _send(c),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.send, size: 15),
            label: Text(sent ? 'Resend' : 'Send'),
          ),
        ],
      ),
    );
  }
}