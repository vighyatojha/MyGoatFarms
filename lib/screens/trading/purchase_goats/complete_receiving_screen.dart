import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/trading_service.dart';
import 'purchase_cost_card.dart';
import 'purchase_wizard_widgets.dart';

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
  late final TextEditingController _transportController;
  late final TextEditingController _loadingController;
  late final TextEditingController _unloadingController;
  late final TextEditingController _otherController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _receivedDate = DateTime.now();

    _arrivalWeightController = TextEditingController();
    _mortalityController = TextEditingController(text: '0');
    _remarksController = TextEditingController();
    _transportController = TextEditingController();
    _loadingController = TextEditingController();
    _unloadingController = TextEditingController();
    _otherController = TextEditingController();
  }

  @override
  void dispose() {
    _arrivalWeightController.dispose();
    _mortalityController.dispose();
    _remarksController.dispose();
    _transportController.dispose();
    _loadingController.dispose();
    _unloadingController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
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

  double _money(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  /// Live costing: the purchase as saved + whatever is typed on this
  /// screen. Same engine as the wizard, so the numbers match everywhere.
  PurchaseCosting get _costing {
    final p = widget.purchase;

    return PurchaseCosting(
      totalGoats: p.totalGoats,
      weightAtPurchase: p.totalWeightAtPurchase,
      pricePerKg: p.pricePerKg,
      weightAfterArrival: _arrivalWeight,
      mortality: _mortality,
      transportCost: _money(_transportController),
      loadingCharges: _money(_loadingController),
      unloadingCharges: _money(_unloadingController),
      otherExpenses: _money(_otherController),
    );
  }

  Future<void> _selectDate() async {
    final selected = await showWizardDatePicker(
      context: context,
      initialDate: _receivedDate,
      firstDate: widget.purchase.purchaseDate,
      lastDate: DateTime.now(),
      helpText: 'Date received at farm',
    );

    if (selected == null || !mounted) return;

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

    if (mortality >= widget.purchase.totalGoats) {
      _showError(
        'Mortality must be less than the '
            '${widget.purchase.totalGoats} goats purchased.',
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
        transportCost: _money(_transportController),
        loadingCharges: _money(_loadingController),
        unloadingCharges: _money(_unloadingController),
        otherExpenses: _money(_otherController),
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
                inputFormatters: wizardDecimalFormatters(),
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

              // Mortality clarification:
              // explicitly tells the user that mortality means goats that died.
              _textField(
                controller: _mortalityController,
                label: 'Mortality (Goats Died)',
                hint: 'Enter number of goats that died',
                suffix: 'Goats',
                icon: GoatIcons.paw,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final parsed = int.tryParse(
                    value?.trim() ?? '',
                  );

                  if (parsed == null || parsed < 0) {
                    return 'Enter a valid mortality count';
                  }

                  if (parsed >= widget.purchase.totalGoats) {
                    return 'Must be less than the '
                        '${widget.purchase.totalGoats} goats purchased';
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

              const SizedBox(height: 22),

              _sectionTitle(
                icon: Icons.local_shipping_outlined,
                title: 'Transportation & Expenses',
              ),

              const SizedBox(height: 4),

              Text(
                'Add whatever applies. Every amount is optional.',
                style: AppTheme.body(size: 11),
              ),

              const SizedBox(height: 10),

              _moneyField(
                controller: _transportController,
                label: 'Transport Cost',
                icon: Icons.directions_car_outlined,
              ),
              const SizedBox(height: 12),

              _moneyField(
                controller: _loadingController,
                label: 'Loading Charges',
                icon: Icons.upload_outlined,
              ),
              const SizedBox(height: 12),

              _moneyField(
                controller: _unloadingController,
                label: 'Unloading Charges',
                icon: Icons.download_outlined,
              ),
              const SizedBox(height: 12),

              _moneyField(
                controller: _otherController,
                label: 'Other Expenses',
                icon: Icons.more_horiz_rounded,
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

  Widget _receivingSummary() {
    return PurchaseCostCard(
      costing: _costing,
    );
  }

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
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
    int maxLines = 1,
    TextCapitalization textCapitalization =
        TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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
        prefixText: prefix,
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

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return _textField(
      controller: controller,
      label: label,
      hint: '0.00',
      icon: icon,
      prefix: '₹ ',
      keyboardType:
      const TextInputType.numberWithOptions(
        decimal: true,
      ),
      inputFormatters: wizardDecimalFormatters(),
      onChanged: (_) => setState(() {}),
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
}