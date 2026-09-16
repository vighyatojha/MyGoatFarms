import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app_theme.dart';
import '../../../../models/trading_purchase_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 3 — Receiving & Transport.
///
/// Receiving information is required only when the user chooses
/// "Fill Receiving Details Now".
///
/// Fields:
/// - Date Received at Farm
/// - Total Weight After Arrival
/// - Mortality
/// - Remarks
/// - Transport Cost
/// - Loading Charges
/// - Unloading Charges
/// - Other Expenses
///
/// All calculated values update live from [PurchaseDraft].
class Step3ReceivingTransport extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PurchaseDraft draft;

  const Step3ReceivingTransport({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<Step3ReceivingTransport> createState() =>
      _Step3ReceivingTransportState();
}

class _Step3ReceivingTransportState
    extends State<Step3ReceivingTransport> {
  late final TextEditingController _weightAfterController;
  late final TextEditingController _mortalityController;
  late final TextEditingController _remarksController;
  late final TextEditingController _transportController;
  late final TextEditingController _loadingController;
  late final TextEditingController _unloadingController;
  late final TextEditingController _otherController;

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _weightAfterController = TextEditingController(
      text: draft.totalWeightAfterArrival == 0
          ? ''
          : _trimZero(draft.totalWeightAfterArrival),
    );

    _mortalityController = TextEditingController(
      text: draft.mortality == 0
          ? ''
          : draft.mortality.toString(),
    );

    _remarksController = TextEditingController(
      text: draft.remarks,
    );

    _transportController = TextEditingController(
      text: draft.transportCost == 0
          ? ''
          : _trimZero(draft.transportCost),
    );

    _loadingController = TextEditingController(
      text: draft.loadingCharges == 0
          ? ''
          : _trimZero(draft.loadingCharges),
    );

    _unloadingController = TextEditingController(
      text: draft.unloadingCharges == 0
          ? ''
          : _trimZero(draft.unloadingCharges),
    );

    _otherController = TextEditingController(
      text: draft.otherExpenses == 0
          ? ''
          : _trimZero(draft.otherExpenses),
    );
  }

  String _trimZero(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _weightAfterController.dispose();
    _mortalityController.dispose();
    _remarksController.dispose();
    _transportController.dispose();
    _loadingController.dispose();
    _unloadingController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _pickReceivedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.draft.dateReceivedAtFarm,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(
        const Duration(days: 1),
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(
              primary: AppColors.primaryGreen,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      widget.draft.dateReceivedAtFarm = picked;
    });
  }

  void _recalculate() {
    final draft = widget.draft;

    draft.totalWeightAfterArrival =
        double.tryParse(
          _weightAfterController.text.trim(),
        ) ??
            0;

    draft.mortality =
        int.tryParse(
          _mortalityController.text.trim(),
        ) ??
            0;

    draft.remarks = _remarksController.text;

    draft.transportCost =
        double.tryParse(
          _transportController.text.trim(),
        ) ??
            0;

    draft.loadingCharges =
        double.tryParse(
          _loadingController.text.trim(),
        ) ??
            0;

    draft.unloadingCharges =
        double.tryParse(
          _unloadingController.text.trim(),
        ) ??
            0;

    draft.otherExpenses =
        double.tryParse(
          _otherController.text.trim(),
        ) ??
            0;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24,
        ),
        children: [
          _buildReceivingSection(draft),
          const SizedBox(height: 14),
          _buildTransportSection(draft),
          const SizedBox(height: 14),
          _buildTransportTotal(draft),
        ],
      ),
    );
  }

  Widget _buildReceivingSection(
      PurchaseDraft draft,
      ) {
    return WizardSectionCard(
      title: 'Receiving Details',
      icon: Icons.inventory_2_outlined,
      children: [
        WizardDateField(
          label: 'Date Received at Farm',
          date: draft.dateReceivedAtFarm,
          onTap: _pickReceivedDate,
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _weightAfterController,
          label: 'Total Weight After Arrival',
          hint: '0.00',
          icon: Icons.scale_outlined,
          suffix: 'KG',
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          onChanged: (_) => _recalculate(),
          validator: (value) {
            final number = double.tryParse(
              value?.trim() ?? '',
            );

            if (number == null || number <= 0) {
              return 'Enter a valid weight';
            }

            if (number > draft.totalWeightAtPurchase) {
              return 'Cannot exceed purchase weight';
            }

            return null;
          },
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _mortalityController,
          label: 'Mortality',
          hint: 'Optional — goats lost in transit',
          icon: Icons.report_gmailerrorred_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          optional: true,
          onChanged: (_) => _recalculate(),
          validator: (value) {
            final number = int.tryParse(
              value?.trim() ?? '',
            );

            if (value != null &&
                value.trim().isNotEmpty &&
                (number == null || number < 0)) {
              return 'Enter a valid number';
            }

            if (number != null &&
                number > draft.totalGoats) {
              return 'Cannot exceed total goats';
            }

            return null;
          },
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _remarksController,
          label: 'Remarks',
          hint: 'Optional',
          icon: Icons.edit_note_rounded,
          maxLines: 3,
          optional: true,
          onChanged: (value) {
            draft.remarks = value;
          },
        ),

        const SizedBox(height: 12),

        _buildComputedRow(
          label: 'Weight Loss',
          value:
          '${_trimZero(draft.weightLoss)} KG',
        ),
      ],
    );
  }

  Widget _buildTransportSection(
      PurchaseDraft draft,
      ) {
    return WizardSectionCard(
      title: 'Transport Expenses',
      icon: Icons.local_shipping_outlined,
      children: [
        wizardField(
          controller: _transportController,
          label: 'Transport Cost',
          hint: 'Optional',
          icon: Icons.directions_car_outlined,
          suffix: '₹',
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          optional: true,
          onChanged: (_) => _recalculate(),
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _loadingController,
          label: 'Loading Charges',
          hint: 'Optional',
          icon: Icons.upload_outlined,
          suffix: '₹',
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          optional: true,
          onChanged: (_) => _recalculate(),
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _unloadingController,
          label: 'Unloading Charges',
          hint: 'Optional',
          icon: Icons.download_outlined,
          suffix: '₹',
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          optional: true,
          onChanged: (_) => _recalculate(),
        ),

        const SizedBox(height: 14),

        wizardField(
          controller: _otherController,
          label: 'Other Expenses',
          hint: 'Optional',
          icon: Icons.more_horiz_rounded,
          suffix: '₹',
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          optional: true,
          onChanged: (_) => _recalculate(),
        ),
      ],
    );
  }

  Widget _buildTransportTotal(
      PurchaseDraft draft,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
          AppColors.primaryGreen.withOpacity(0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen
                  .withOpacity(0.12),
              borderRadius:
              BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.darkGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Transportation Expenses',
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 12,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Transport + loading + unloading + other',
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _currency(
                draft.totalTransportExpenses,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style: AppTheme.heading(
                size: 17,
                color: AppColors.darkGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComputedRow({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius:
        BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: 11,
                color: AppColors.textGrey,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style: AppTheme.heading(
                size: 12,
                color: AppColors.darkGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}