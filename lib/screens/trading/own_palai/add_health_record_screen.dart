import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/trading_goat_health_record.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';

/// Task 3.3 — "log a new entry per type" form, reached from the Health
/// Tracking section of the Own Palai Goat Profile.
///
/// [type] is fixed by whichever of the four buttons (Vaccination, Hoof
/// Cutting, Hair Trimming, Medicine) opened this screen — the person
/// never picks it here, matching the plan's "current status + history
/// for each of" four separate sections rather than one combined type
/// picker.
///
/// The optional "Next Due Date" is what feeds the reminder logic
/// (Task 1.3 / 3.4) — left off (null) means this entry has no
/// follow-up due, per [GoatHealthRecord.nextDueDate]'s doc comment.
class AddHealthRecordScreen extends StatefulWidget {
  final String farmId;
  final String goatId;
  final GoatHealthRecordType type;

  const AddHealthRecordScreen({
    super.key,
    required this.farmId,
    required this.goatId,
    required this.type,
  });

  @override
  State<AddHealthRecordScreen> createState() => _AddHealthRecordScreenState();
}

class _AddHealthRecordScreenState extends State<AddHealthRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  DateTime _date = DateTime.now();

  bool _setNextDueDate = false;
  DateTime? _nextDueDate;

  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.darkGreen,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickNextDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDueDate ?? _date.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _nextDueDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      await GoatService.instance.addHealthRecord(
        farmId: widget.farmId,
        goatId: widget.goatId,
        record: GoatHealthRecord(
          id: '',
          type: widget.type,
          date: _date,
          notes: _notesController.text,
          nextDueDate: _setNextDueDate ? _nextDueDate : null,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack(FirestoreService.instance.describeError(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Log ${widget.type.label}', style: AppTheme.heading(size: 17)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Date'),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: AppTheme.card(radius: 12),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: AppColors.stockTeal,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('dd MMM yyyy').format(_date),
                          style:
                          AppTheme.body(size: 13, color: AppColors.textDark),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _label('Notes'),
                _textField(
                  _notesController,
                  hint: 'Optional notes',
                  maxLines: 3,
                  optional: true,
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: AppTheme.card(radius: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.stockTeal,
                    title: Text(
                      'Set next due date',
                      style: AppTheme.body(
                          size: 13,
                          color: AppColors.textDark,
                          weight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Feeds the reminder for this goat\'s next '
                          '${widget.type.label.toLowerCase()}.',
                      style: AppTheme.body(size: 11, color: AppColors.textGrey),
                    ),
                    value: _setNextDueDate,
                    onChanged: (v) => setState(() {
                      _setNextDueDate = v;
                      if (v) {
                        _nextDueDate ??= _date.add(const Duration(days: 30));
                      }
                    }),
                  ),
                ),
                if (_setNextDueDate) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickNextDueDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: AppTheme.card(radius: 12),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_repeat_outlined,
                            size: 16,
                            color: AppColors.stockTeal,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _nextDueDate != null
                                ? DateFormat('dd MMM yyyy')
                                .format(_nextDueDate!)
                                : 'Choose a date',
                            style: AppTheme.body(
                                size: 13, color: AppColors.textDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.stockTeal,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      'Save ${widget.type.label} Record',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: AppTheme.heading(size: 13)),
  );

  Widget _textField(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        bool optional = false,
        String? Function(String?)? validator,
      }) {
    return Container(
      decoration: AppTheme.card(radius: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator ??
                (v) => (!optional && (v == null || v.trim().isEmpty))
                ? 'Required'
                : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.body(size: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
        style: AppTheme.body(size: 13, color: AppColors.textDark),
      ),
    );
  }
}