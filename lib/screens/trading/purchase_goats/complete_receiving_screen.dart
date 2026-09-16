import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/trading_service.dart';

/// Receiving screen for an existing Trading purchase.
///
/// This screen is ONLY for completing receiving after a purchase
/// was previously saved with receivingStatus = "pending".
///
/// IMPORTANT:
/// - Does NOT create a new purchase.
/// - Uses TradingService.completeReceiving().
/// - Existing purchase ID remains unchanged.
class CompleteReceivingScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase purchase;

  const CompleteReceivingScreen({
    super.key,
    required this.farmId,
    required this.purchase,
  });

  @override
  State<CompleteReceivingScreen> createState() =>
      _CompleteReceivingScreenState();
}

class _CompleteReceivingScreenState
    extends State<CompleteReceivingScreen> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _receivedDate;

  late final TextEditingController _arrivalWeightController;
  late final TextEditingController _mortalityController;
  late final TextEditingController _remarksController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _receivedDate = DateTime.now();

    _arrivalWeightController = TextEditingController();
    _mortalityController = TextEditingController(text: '0');
    _remarksController = TextEditingController();
  }

  @override
  void dispose() {
    _arrivalWeightController.dispose();
    _mortalityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(value);
  }

  double get _arrivalWeight {
    return double.tryParse(
      _arrivalWeightController.text.trim(),
    ) ??
        0;
  }

  int get _mortality {
    return int.tryParse(
      _mortalityController.text.trim(),
    ) ??
        0;
  }

  double get _weightLoss {
    final loss =
        widget.purchase.totalWeightAtPurchase - _arrivalWeight;

    return loss < 0 ? 0 : loss;
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _receivedDate,
      firstDate: widget.purchase.purchaseDate,
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _receivedDate = selected;
    });
  }

  Future<void> _completeReceiving() async {
    final formState = _formKey.currentState;

    if (formState == null || !formState.validate()) {
      return;
    }

    final arrivalWeight = _arrivalWeight;
    final mortality = _mortality;

    if (arrivalWeight <= 0) {
      _showError('Enter the total weight after arrival.');
      return;
    }

    if (arrivalWeight > widget.purchase.totalWeightAtPurchase) {
      _showError(
        'Arrival weight cannot be greater than purchase weight.',
      );
      return;
    }

    if (mortality > widget.purchase.totalGoats) {
      _showError(
        'Mortality cannot be greater than total goats.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final updated =
      await TradingService.instance.completeReceiving(
        farmId: widget.farmId,
        purchaseId: widget.purchase.id,
        dateReceivedAtFarm: _receivedDate,
        totalWeightAfterArrival: arrivalWeight,
        mortality: mortality,
        remarks: _remarksController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receiving completed successfully.'),
          backgroundColor: AppColors.darkGreen,
        ),
      );

      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Complete Receiving',
          style: AppTheme.heading(size: 19),
        ),
        iconTheme: const IconThemeData(
          color: Colors.black87,
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _purchaseHeader(),
              const SizedBox(height: 16),

              _sectionTitle(
                icon: Icons.inventory_2_outlined,
                title: 'Receiving Details',
              ),

              const SizedBox(height: 10),

              _dateField(),
              const SizedBox(height: 12),

              _textField(
                controller: _arrivalWeightController,
                label: 'Total Weight After Arrival',
                hint: 'Enter arrival weight',
                suffix: 'Kg',
                icon: Icons.monitor_weight_outlined,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                // Without this, typing a value updates the
                // controller/text field itself (which manages its own
                // rendering) but never calls setState, so
                // _receivingSummary() below — which reads
                // _arrivalWeight/_weightLoss/effective-cost-per-kg via
                // getters — keeps rendering whatever it saw on the
                // last rebuild (i.e. stays stuck on "—").
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final parsed = double.tryParse(
                    value?.trim() ?? '',
                  );

                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid arrival weight';
                  }

                  if (parsed >
                      widget.purchase.totalWeightAtPurchase) {
                    return 'Cannot exceed purchase weight';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 12),

              _textField(
                controller: _mortalityController,
                label: 'Mortality',
                hint: 'Enter mortality count',
                suffix: 'Goats',
                icon: Icons.pets_outlined,
                keyboardType: TextInputType.number,
                // Same reason as the arrival-weight field above: the
                // Mortality row in the summary card reads _mortality
                // via a getter, so it needs a setState to pick up the
                // new value as the user types.
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final parsed = int.tryParse(
                    value?.trim() ?? '',
                  );

                  if (parsed == null || parsed < 0) {
                    return 'Enter a valid mortality count';
                  }

                  if (parsed > widget.purchase.totalGoats) {
                    return 'Cannot exceed total goats';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 12),

              _textField(
                controller: _remarksController,
                label: 'Remarks',
                hint: 'Add receiving notes if needed',
                icon: Icons.notes_outlined,
                maxLines: 4,
                textCapitalization:
                TextCapitalization.sentences,
              ),

              const SizedBox(height: 18),

              _receivingSummary(),

              const SizedBox(height: 24),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed:
                  _saving ? null : _completeReceiving,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                    AppColors.primaryGreen.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                      : const Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 21,
                      ),
                      SizedBox(width: 9),
                      Text(
                        'Complete Receiving',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PURCHASE HEADER
  // ---------------------------------------------------------------------------

  Widget _purchaseHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.card(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color:
                  AppColors.primaryGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.primaryGreen,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Receiving',
                      style: AppTheme.body(size: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.purchase.id,
                      style: AppTheme.heading(size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _infoRow(
            'Seller',
            widget.purchase.sellerName,
          ),
          const SizedBox(height: 8),
          _infoRow(
            'Purchase Date',
            DateFormat(
              'dd MMM yyyy',
            ).format(widget.purchase.purchaseDate),
          ),
          const SizedBox(height: 8),
          _infoRow(
            'Total Goats',
            '${widget.purchase.totalGoats}',
          ),
          const SizedBox(height: 8),
          _infoRow(
            'Purchase Weight',
            '${widget.purchase.totalWeightAtPurchase.toStringAsFixed(2)} Kg',
          ),
          const SizedBox(height: 8),
          _infoRow(
            'Purchase Amount',
            _currency(widget.purchase.purchaseAmount),
            valueBold: true,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE
  // ---------------------------------------------------------------------------

  Widget _dateField() {
    return InkWell(
      onTap: _saving ? null : _selectDate,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date Received at Farm',
          prefixIcon: const Icon(
            Icons.calendar_today_outlined,
            color: AppColors.primaryGreen,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
          const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
        ),
        child: Text(
          DateFormat('dd MMM yyyy').format(_receivedDate),
          style: AppTheme.body(size: 14),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  Widget _receivingSummary() {
    final arrivalWeight = _arrivalWeight;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                color: AppColors.primaryGreen,
                size: 21,
              ),
              const SizedBox(width: 9),
              Text(
                'Receiving Summary',
                style: AppTheme.heading(size: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _summaryRow(
            'Purchase Weight',
            '${widget.purchase.totalWeightAtPurchase.toStringAsFixed(2)} Kg',
          ),
          const SizedBox(height: 10),
          _summaryRow(
            'Arrival Weight',
            arrivalWeight > 0
                ? '${arrivalWeight.toStringAsFixed(2)} Kg'
                : '—',
          ),
          const SizedBox(height: 10),
          _summaryRow(
            'Weight Loss',
            arrivalWeight > 0
                ? '${_weightLoss.toStringAsFixed(2)} Kg'
                : '—',
          ),
          const SizedBox(height: 10),
          _summaryRow(
            'Mortality',
            '$_mortality goats',
          ),
          const SizedBox(height: 10),
          _summaryRow(
            'Effective Cost / Kg',
            arrivalWeight > 0
                ? _currency(
              widget.purchase.grandTotal /
                  arrivalWeight,
            )
                : '—',
            bold: true,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED UI
  // ---------------------------------------------------------------------------

  Widget _sectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.primaryGreen,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTheme.heading(size: 16),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    int maxLines = 1,
    TextCapitalization textCapitalization =
        TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: AppColors.primaryGreen,
        ),
        suffixText: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.3,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
      String label,
      String value, {
        bool valueBold = false,
      }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.body(size: 12),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: valueBold
                ? AppTheme.heading(size: 13)
                : AppTheme.body(size: 13),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
      String label,
      String value, {
        bool bold = false,
      }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.body(size: 12),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: bold
                ? AppTheme.heading(size: 13)
                : AppTheme.body(size: 13),
          ),
        ),
      ],
    );
  }
}