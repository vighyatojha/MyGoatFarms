import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';

class ReceivePaymentScreen extends StatefulWidget {
  const ReceivePaymentScreen({super.key});

  @override
  State<ReceivePaymentScreen> createState() =>
      _ReceivePaymentScreenState();
}

class _ReceivePaymentScreenState
    extends State<ReceivePaymentScreen> {
  String? _farmId;

  PalaiCustomer? _selectedCustomer;

  final TextEditingController _amountController =
  TextEditingController(text: '0');

  final TextEditingController _noteController =
  TextEditingController();

  String _paymentMethod = 'Cash';

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final farmId =
    await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    setState(() {
      _farmId = farmId;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();

    super.dispose();
  }

  double get _amount {
    return double.tryParse(
      _amountController.text.trim(),
    ) ??
        0;
  }

  double get _pendingBefore {
    return _selectedCustomer?.pendingAmount ?? 0;
  }

  double get _advanceBefore {
    return _selectedCustomer?.advanceAmount ?? 0;
  }

  double get _amountAppliedToPending {
    return _amount
        .clamp(0, _pendingBefore)
        .toDouble();
  }

  double get _advanceAdded {
    return (_amount - _amountAppliedToPending)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double get _pendingAfter {
    return (_pendingBefore - _amount)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double get _advanceAfter {
    return _advanceBefore + _advanceAdded;
  }

  bool get _isAdvance {
    return _advanceAdded > 0;
  }

  Future<void> _receivePayment() async {
    if (_selectedCustomer == null) {
      _showError('Please select a customer.');
      return;
    }

    if (_amount <= 0) {
      _showError(
        'Enter an amount greater than ₹0.',
      );
      return;
    }

    if (_farmId == null) {
      _showError(
        'Farm information is not available.',
      );
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final result =
      await FirestoreService.instance.receivePalaiPayment(
        farmId: _farmId!,
        customerId: _selectedCustomer!.id,
        paidAmount: _amount,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      await _showSuccessDialog(result);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      final message =
      FirestoreService.instance.describeError(e);

      _showError(message);
    }
  }

  Future<void> _showSuccessDialog(
      StandalonePaymentResult result,
      ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Payment Recorded',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                size: 54,
                color: AppColors.primaryGreen,
              ),

              const SizedBox(height: 14),

              Text(
                'Payment ${result.paymentNumber}',
                style: AppTheme.heading(size: 15),
              ),

              const SizedBox(height: 16),

              _dialogRow(
                'Amount Received',
                result.amountReceived,
              ),

              _dialogRow(
                'Applied to Pending',
                result.amountAppliedToPending,
              ),

              _dialogRow(
                'Pending After',
                result.pendingAfter,
              ),

              if (result.advanceAdded > 0) ...[
                const Divider(),

                _dialogRow(
                  'Advance Added',
                  result.advanceAdded,
                ),

                _dialogRow(
                  'Total Advance',
                  result.advanceAfter,
                ),
              ],

              const SizedBox(height: 8),

              Text(
                'Payment Method: ${result.paymentMethod}',
                style: AppTheme.body(size: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
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
        foregroundColor: AppColors.textDark,

        title: Text(
          'Receive Payment',
          style: AppTheme.heading(size: 17),
        ),
      ),

      body: _farmId == null
          ? const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      )
          : StreamBuilder<List<PalaiCustomer>>(
        stream: FirestoreService.instance
            .customersStream(_farmId!),

        builder: (context, snapshot) {
          final customers =
              snapshot.data ?? [];

          return SingleChildScrollView(
            padding:
            const EdgeInsets.all(20),

            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                _label(
                  'Select Customer',
                ),

                _customerDropdown(
                  customers,
                ),

                const SizedBox(height: 20),

                _label(
                  'Amount Received (₹)',
                ),

                _amountField(),

                const SizedBox(height: 20),

                _label(
                  'Payment Method',
                ),

                _paymentMethodDropdown(),

                const SizedBox(height: 20),

                _label(
                  'Note',
                ),

                _noteField(),

                const SizedBox(height: 20),

                if (_selectedCustomer !=
                    null)
                  _paymentSummary(),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,

                  child: ElevatedButton(
                    onPressed:
                    _saving
                        ? null
                        : _receivePayment,

                    style:
                    ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors.primaryGreen,

                      foregroundColor:
                      Colors.white,

                      padding:
                      const EdgeInsets
                          .symmetric(
                        vertical: 16,
                      ),

                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius
                            .circular(
                          12,
                        ),
                      ),
                    ),

                    child: _saving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                        Colors.white,
                      ),
                    )
                        : const Text(
                      'Record Payment',
                      style: TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _customerDropdown(
      List<PalaiCustomer> customers,
      ) {
    return Container(
      decoration: AppTheme.card(radius: 12),

      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),

      child: DropdownButtonHideUnderline(
        child: DropdownButton<PalaiCustomer>(
          value:
          customers.contains(
            _selectedCustomer,
          )
              ? _selectedCustomer
              : null,

          isExpanded: true,

          hint: Text(
            'Choose a customer',
            style: AppTheme.body(size: 13),
          ),

          items: customers.map(
                (customer) {
              return DropdownMenuItem<
                  PalaiCustomer>(
                value: customer,

                child: Text(
                  '${customer.name} · '
                      'Pending ₹${customer.pendingAmount.toStringAsFixed(0)}'
                      '${customer.advanceAmount > 0 ? ' · Advance ₹${customer.advanceAmount.toStringAsFixed(0)}' : ''}',

                  style: AppTheme.body(
                    size: 13,
                    color:
                    AppColors.textDark,
                  ),
                ),
              );
            },
          ).toList(),

          onChanged: _saving
              ? null
              : (customer) {
            setState(() {
              _selectedCustomer =
                  customer;
            });
          },
        ),
      ),
    );
  }

  Widget _amountField() {
    return Container(
      decoration:
      AppTheme.card(radius: 12),

      child: TextField(
        controller:
        _amountController,

        keyboardType:
        const TextInputType.numberWithOptions(
          decimal: true,
        ),

        onChanged: (_) {
          setState(() {});
        },

        decoration:
        const InputDecoration(
          border: InputBorder.none,

          contentPadding:
          EdgeInsets.all(14),

          prefixText: '₹ ',
        ),

        style: AppTheme.body(
          size: 14,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _paymentMethodDropdown() {
    return Container(
      decoration:
      AppTheme.card(radius: 12),

      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),

      child:
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _paymentMethod,

          isExpanded: true,

          items: const [
            DropdownMenuItem(
              value: 'Cash',
              child: Text('Cash'),
            ),
            DropdownMenuItem(
              value: 'UPI',
              child: Text('UPI'),
            ),
            DropdownMenuItem(
              value: 'Bank Transfer',
              child: Text('Bank Transfer'),
            ),
            DropdownMenuItem(
              value: 'Cheque',
              child: Text('Cheque'),
            ),
            DropdownMenuItem(
              value: 'Other',
              child: Text('Other'),
            ),
          ],

          onChanged: _saving
              ? null
              : (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _paymentMethod =
                  value;
            });
          },
        ),
      ),
    );
  }

  Widget _noteField() {
    return Container(
      decoration:
      AppTheme.card(radius: 12),

      child: TextField(
        controller:
        _noteController,

        maxLines: 3,

        decoration:
        const InputDecoration(
          border: InputBorder.none,

          hintText:
          'Optional payment note',

          contentPadding:
          EdgeInsets.all(14),
        ),

        style: AppTheme.body(
          size: 13,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _paymentSummary() {
    return Container(
      padding:
      const EdgeInsets.all(16),

      decoration:
      AppTheme.card(radius: 14),

      child: Column(
        children: [
          _summaryRow(
            'Pending Before',
            _pendingBefore,
            color: AppColors.error,
          ),

          _summaryRow(
            'Amount Received',
            _amount,
            color: AppColors.success,
          ),

          _summaryRow(
            'Applied to Pending',
            _amountAppliedToPending,
          ),

          const Divider(
            height: 20,
          ),

          _summaryRow(
            'Pending After',
            _pendingAfter,
            bold: true,
          ),

          const SizedBox(height: 8),

          _summaryRow(
            'Advance Before',
            _advanceBefore,
          ),

          _summaryRow(
            'Advance Added',
            _advanceAdded,
          ),

          _summaryRow(
            'Advance After',
            _advanceAfter,
            bold: true,
          ),

          if (_isAdvance) ...[
            const SizedBox(height: 12),

            Container(
              width: double.infinity,

              padding:
              const EdgeInsets.all(10),

              decoration:
              BoxDecoration(
                borderRadius:
                BorderRadius.circular(
                  8,
                ),

                color:
                AppColors.lightGreen,
              ),

              child: Text(
                '₹${_advanceAdded.toStringAsFixed(0)} '
                    'will be stored as customer advance.',
                style: AppTheme.body(
                  size: 11,
                  color:
                  AppColors.darkGreen,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(
      String label,
      double value, {
        bool bold = false,
        Color? color,
      }) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 4,
      ),

      child: Row(
        mainAxisAlignment:
        MainAxisAlignment
            .spaceBetween,

        children: [
          Text(
            label,
            style: AppTheme.body(
              size: 13,
            ),
          ),

          Text(
            '₹${value.toStringAsFixed(0)}',

            style: bold
                ? AppTheme.heading(
              size: 14,
              color:
              color ??
                  AppColors
                      .textDark,
            )
                : AppTheme.body(
              size: 13,
              color:
              color ??
                  AppColors
                      .textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(
      String label,
      double value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 3,
      ),

      child: Row(
        mainAxisAlignment:
        MainAxisAlignment
            .spaceBetween,

        children: [
          Text(
            label,
            style: AppTheme.body(
              size: 12,
            ),
          ),

          Text(
            '₹${value.toStringAsFixed(0)}',
            style: AppTheme.heading(
              size: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 6,
      ),

      child: Text(
        text,
        style: AppTheme.heading(
          size: 13,
        ),
      ),
    );
  }
}