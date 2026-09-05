import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../services/pdf_bill_service.dart';
import '../../widgets/farm_not_linked_state.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() =>
      _BillingScreenState();
}

class _BillingScreenState
    extends State<BillingScreen> {
  String? _farmId;
  bool _loading = true;

  PalaiCustomer? _selectedCustomer;
  PalaiCustomer? _liveCustomer;

  final _monthlyChargesController =
  TextEditingController(text: '0');

  final _transportController =
  TextEditingController(text: '0');

  final _discountController =
  TextEditingController(text: '0');

  final _paidController =
  TextEditingController(text: '0');

  final _noteController =
  TextEditingController();

  String _paymentMethod = 'Cash';

  bool _saving = false;

  BillSettings _billSettings =
  const BillSettings();

  static const List<String> _paymentMethods = [
    'Cash',
    'UPI',
    'Bank Transfer',
    'Other',
  ];

  @override
  void initState() {
    super.initState();

    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final id =
    await FirestoreService.instance.currentFarmId();

    if (!mounted) return;

    if (id == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _farmId = id;
      _loading = false;
    });

    final farm =
    await FirestoreService.instance.getFarmById(id);

    if (mounted && farm != null) {
      setState(() {
        _billSettings =
            farm.billSettings;
      });
    }
  }

  @override
  void dispose() {
    _monthlyChargesController.dispose();
    _transportController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double _parse(
      TextEditingController controller,
      ) {
    return double.tryParse(
      controller.text.trim(),
    ) ??
        0;
  }

  double get _monthlyCharges =>
      _parse(_monthlyChargesController);

  double get _transport =>
      _parse(_transportController);

  double get _discount =>
      _parse(_discountController);

  double get _paid =>
      _parse(_paidController);

  PalaiCustomer? get _customer =>
      _liveCustomer ?? _selectedCustomer;

  double get _previousPending =>
      _customer?.pendingAmount ?? 0;

  double get _advance =>
      _customer?.advanceAmount ?? 0;

  double get _newCharges =>
      (_monthlyCharges +
          _transport -
          _discount)
          .clamp(0, double.infinity)
          .toDouble();

  double get _advanceApplied =>
      _advance
          .clamp(
        0,
        _previousPending + _newCharges,
      )
          .toDouble();

  double get _totalDue =>
      (_previousPending +
          _newCharges -
          _advanceApplied)
          .clamp(0, double.infinity)
          .toDouble();

  double get _pendingAfter =>
      (_totalDue - _paid)
          .clamp(0, double.infinity)
          .toDouble();

  double get _newAdvance =>
      (_advance -
          _advanceApplied +
          (_paid - _totalDue)
              .clamp(
            0,
            double.infinity,
          ))
          .clamp(0, double.infinity)
          .toDouble();

  Future<void> _prefillMonthlyCharges(
      PalaiCustomer customer,
      ) async {
    if (_farmId == null) return;

    try {
      final goats =
      await FirestoreService.instance
          .goatsForCustomerStream(
        _farmId!,
        customer.id,
      )
          .first;

      final activePricingTotal =
      goats
          .where((g) => !g.isCheckedOut)
          .fold<double>(
        0,
            (sum, goat) =>
        sum + goat.pricing,
      );

      if (!mounted) return;

      if (activePricingTotal > 0) {
        setState(() {
          _monthlyChargesController.text =
              activePricingTotal
                  .toStringAsFixed(0);
        });
      }
    } catch (e) {
      debugPrint(
        'Could not prefill Palai charges: $e',
      );
    }
  }

  Future<void> _generateBill() async {
    final customer = _customer;

    if (_farmId == null ||
        customer == null) {
      _showError(
        'Please select a customer.',
      );
      return;
    }

    if (_monthlyCharges < 0 ||
        _transport < 0 ||
        _discount < 0 ||
        _paid < 0) {
      _showError(
        'Amounts cannot be negative.',
      );
      return;
    }

    if (_discount >
        (_monthlyCharges + _transport)) {
      _showError(
        'Discount cannot be greater than the charges.',
      );
      return;
    }

    if (_paid > 0 &&
        _paymentMethod.trim().isEmpty) {
      _showError(
        'Please select a payment method.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final result =
      await FirestoreService.instance
          .createMonthlyBill(
        farmId: _farmId!,
        customerId: customer.id,
        monthlyCharges: _monthlyCharges,
        transportCharges: _transport,
        discount: _discount,
        paidAmount: _paid,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
      );

      if (!mounted) return;

      setState(() => _saving = false);

      _showSuccess(
        'Bill ${result.billNumber} created successfully.',
      );

      await _showPdfOptions(
        customerName: customer.name,
        billNumber: result.billNumber,
        monthlyCharges: _monthlyCharges,
        transport: _transport,
        previousBalance: result.previousPending,
        advanceBefore: result.advanceBefore,
        advanceApplied: result.advanceApplied,
        discount: _discount,
        paid: result.paid,
        totalBill: result.totalDue,
        pendingAmount: result.pendingAfter,
        advanceAfter: result.advanceAfter,
        paymentMethod: result.paymentMethod,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      _showError(
        FirestoreService.instance
            .describeError(e),
      );
    }
  }

  Future<void> _showPdfOptions({
    required String customerName,
    required String billNumber,
    required double monthlyCharges,
    required double transport,
    required double previousBalance,
    required double advanceBefore,
    required double advanceApplied,
    required double discount,
    required double paid,
    required double totalBill,
    required double pendingAmount,
    required double advanceAfter,
    required String paymentMethod,
  }) async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      shape:
      const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding:
            const EdgeInsets.all(20),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Bill Generated',
                  style:
                  AppTheme.heading(
                    size: 16,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Bill No. $billNumber',
                  style:
                  AppTheme.body(
                    size: 12,
                    color:
                    AppColors.textGrey,
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child:
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await PdfBillService
                            .instance
                            .shareMonthlyBill(
                          customerName:
                          customerName,
                          billNumber:
                          billNumber,
                          monthlyCharges:
                          monthlyCharges,
                          transport:
                          transport,
                          previousBalance:
                          previousBalance,
                          advanceBefore:
                          advanceBefore,
                          advanceApplied:
                          advanceApplied,
                          discount:
                          discount,
                          paid:
                          paid,
                          totalBill:
                          totalBill,
                          pendingAmount:
                          pendingAmount,
                          advanceAfter:
                          advanceAfter,
                          paymentMethod:
                          paymentMethod,
                          billSettings:
                          _billSettings,
                        );
                      } catch (_) {
                        if (!sheetContext
                            .mounted) {
                          return;
                        }

                        ScaffoldMessenger
                            .of(sheetContext)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not share the PDF.',
                            ),
                            backgroundColor:
                            AppColors.error,
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.ios_share,
                      size: 17,
                    ),
                    label: const Text(
                      'Share PDF',
                      style: TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    style:
                    ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors.primaryGreen,
                      foregroundColor:
                      Colors.white,
                      padding:
                      const EdgeInsets
                          .symmetric(
                        vertical: 14,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child:
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final path =
                        await PdfBillService
                            .instance
                            .saveMonthlyBillToDevice(
                          customerName:
                          customerName,
                          billNumber:
                          billNumber,
                          monthlyCharges:
                          monthlyCharges,
                          transport:
                          transport,
                          previousBalance:
                          previousBalance,
                          advanceBefore:
                          advanceBefore,
                          advanceApplied:
                          advanceApplied,
                          discount:
                          discount,
                          paid:
                          paid,
                          totalBill:
                          totalBill,
                          pendingAmount:
                          pendingAmount,
                          advanceAfter:
                          advanceAfter,
                          paymentMethod:
                          paymentMethod,
                          billSettings:
                          _billSettings,
                        );

                        if (!sheetContext
                            .mounted) {
                          return;
                        }

                        ScaffoldMessenger
                            .of(sheetContext)
                            .showSnackBar(
                          SnackBar(
                            content: Text(
                              'Saved to $path',
                            ),
                            backgroundColor:
                            AppColors
                                .primaryGreen,
                          ),
                        );
                      } catch (_) {
                        if (!sheetContext
                            .mounted) {
                          return;
                        }

                        ScaffoldMessenger
                            .of(sheetContext)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not save the PDF.',
                            ),
                            backgroundColor:
                            AppColors.error,
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.download_outlined,
                      size: 17,
                    ),
                    label: const Text(
                      'Download PDF',
                      style: TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    style:
                    OutlinedButton.styleFrom(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        vertical: 14,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                      ),
                      side:
                      const BorderSide(
                        color: AppColors
                            .primaryGreen,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.of(
                          sheetContext,
                        ).pop(),
                    child: Text(
                      'Close',
                      style:
                      AppTheme.body(
                        size: 13,
                        color:
                        AppColors
                            .textGrey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        AppColors.error,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        AppColors.primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor:
        AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor:
          AppColors.paleGreen,
          elevation: 0,
          foregroundColor:
          AppColors.textDark,
          title: Text(
            'Billing & Payments',
            style:
            AppTheme.heading(size: 17),
          ),
        ),
        body: const Center(
          child:
          CircularProgressIndicator(
            color:
            AppColors.primaryGreen,
          ),
        ),
      );
    }

    if (_farmId == null) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          backgroundColor: AppColors.paleGreen,
          elevation: 0,
          foregroundColor: AppColors.textDark,
          title: Text(
            'Billing & Payments',
            style: AppTheme.heading(size: 17),
          ),
        ),
        body: Center(
          child: FarmNotLinkedState(
            onRetry: () {
              setState(() => _loading = true);
              _loadFarm();
            },
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
      AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor:
        AppColors.paleGreen,
        elevation: 0,
        foregroundColor:
        AppColors.textDark,
        title: Text(
          'Billing & Payments',
          style:
          AppTheme.heading(size: 17),
        ),
      ),

      body: StreamBuilder<
          List<PalaiCustomer>>(
        stream:
        FirestoreService.instance
            .customersStream(
          _farmId!,
        ),
        builder:
            (context, snapshot) {
          final customers =
              snapshot.data ?? [];

          PalaiCustomer? liveCustomer;

          if (_selectedCustomer != null) {
            for (final customer
            in customers) {
              if (customer.id ==
                  _selectedCustomer!.id) {
                liveCustomer =
                    customer;
                break;
              }
            }
          }

          _liveCustomer =
              liveCustomer;

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

                Container(
                  decoration:
                  AppTheme.card(
                    radius: 12,
                  ),
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 12,
                  ),
                  child:
                  DropdownButtonHideUnderline(
                    child:
                    DropdownButton<
                        PalaiCustomer>(
                      value:
                      liveCustomer,
                      isExpanded: true,

                      hint: Text(
                        'Choose a customer',
                        style:
                        AppTheme.body(
                          size: 13,
                        ),
                      ),

                      items: customers
                          .map(
                            (customer) =>
                            DropdownMenuItem<
                                PalaiCustomer>(
                              value:
                              customer,
                              child: Text(
                                customer.name,
                                style:
                                AppTheme.body(
                                  size: 13,
                                  color:
                                  AppColors.textDark,
                                ),
                              ),
                            ),
                      )
                          .toList(),

                      onChanged:
                          (customer) {
                        if (customer ==
                            null) {
                          return;
                        }

                        setState(() {
                          _selectedCustomer =
                              customer;
                          _liveCustomer =
                              customer;
                        });

                        _prefillMonthlyCharges(
                          customer,
                        );
                      },
                    ),
                  ),
                ),

                if (_customer != null) ...[
                  const SizedBox(
                    height: 18,
                  ),

                  _balanceCard(),

                  const SizedBox(
                    height: 20,
                  ),
                ],

                _label(
                  'Monthly Charges (₹)',
                ),
                _amountField(
                  _monthlyChargesController,
                ),

                const SizedBox(
                  height: 12,
                ),

                _label(
                  'Transportation Charges (₹)',
                ),
                _amountField(
                  _transportController,
                ),

                const SizedBox(
                  height: 12,
                ),

                _label(
                  'Discount (₹)',
                ),
                _amountField(
                  _discountController,
                ),

                const SizedBox(
                  height: 18,
                ),

                _label(
                  'Payment Received (₹)',
                ),
                _amountField(
                  _paidController,
                ),

                if (_paid > 0) ...[
                  const SizedBox(
                    height: 12,
                  ),

                  _label(
                    'Payment Method',
                  ),

                  _dropdown(
                    value:
                    _paymentMethod,
                    items:
                    _paymentMethods,
                    onChanged: (value) {
                      setState(() {
                        _paymentMethod =
                            value;
                      });
                    },
                  ),
                ],

                const SizedBox(
                  height: 12,
                ),

                _label(
                  'Note (optional)',
                ),

                Container(
                  decoration:
                  AppTheme.card(
                    radius: 12,
                  ),
                  child: TextField(
                    controller:
                    _noteController,
                    maxLines: 2,
                    decoration:
                    const InputDecoration(
                      border:
                      InputBorder.none,
                      contentPadding:
                      EdgeInsets.all(
                        14,
                      ),
                      hintText:
                      'Payment note / reference',
                    ),
                    style:
                    AppTheme.body(
                      size: 13,
                      color:
                      AppColors.textDark,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                _totalCard(),

                const SizedBox(
                  height: 24,
                ),

                SizedBox(
                  width:
                  double.infinity,
                  child:
                  ElevatedButton(
                    onPressed:
                    _saving
                        ? null
                        : _generateBill,
                    style:
                    ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors
                          .primaryGreen,
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
                        BorderRadius.circular(
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
                        strokeWidth:
                        2,
                        color:
                        Colors.white,
                      ),
                    )
                        : const Text(
                      'Generate & Save Bill',
                      style: TextStyle(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 30,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _balanceCard() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(16),
      decoration:
      AppTheme.card(radius: 14),
      child: Column(
        children: [
          _summaryRow(
            'Previous Pending',
            _previousPending,
            color:
            AppColors.error,
          ),

          _summaryRow(
            'Existing Advance',
            _advance,
            color:
            AppColors.primaryGreen,
          ),

          const Divider(
            height: 18,
          ),

          _summaryRow(
            'New Charges',
            _newCharges,
          ),

          _summaryRow(
            'Advance Applied',
            _advanceApplied,
            color:
            AppColors.primaryGreen,
          ),

          const Divider(
            height: 18,
          ),

          _summaryRow(
            'Total Due',
            _totalDue,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _totalCard() {
    final hasAdvance =
        _paid > _totalDue;

    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(16),
      decoration:
      AppTheme.card(radius: 14),
      child: Column(
        children: [
          _summaryRow(
            'Total Due',
            _totalDue,
            bold: true,
          ),

          _summaryRow(
            'Payment',
            _paid,
            color:
            AppColors.success,
          ),

          const Divider(
            height: 20,
          ),

          _summaryRow(
            'Pending After',
            _pendingAfter,
            color:
            _pendingAfter > 0
                ? AppColors.error
                : AppColors
                .primaryGreen,
            bold: true,
          ),

          if (hasAdvance) ...[
            const SizedBox(
              height: 8,
            ),

            _summaryRow(
              'New Advance',
              _newAdvance,
              color:
              AppColors.primaryGreen,
              bold: true,
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
        MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style:
            AppTheme.body(size: 13),
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

  Widget _label(String text) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 6,
      ),
      child: Text(
        text,
        style:
        AppTheme.heading(size: 13),
      ),
    );
  }

  Widget _amountField(
      TextEditingController controller,
      ) {
    return Container(
      decoration:
      AppTheme.card(radius: 12),
      child: TextField(
        controller:
        controller,
        keyboardType:
        const TextInputType
            .numberWithOptions(
          decimal: true,
        ),
        onChanged: (_) {
          setState(() {});
        },
        decoration:
        const InputDecoration(
          border:
          InputBorder.none,
          contentPadding:
          EdgeInsets.all(14),
        ),
        style:
        AppTheme.body(
          size: 13,
          color:
          AppColors.textDark,
        ),
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String>
    onChanged,
  }) {
    return Container(
      decoration:
      AppTheme.card(radius: 12),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      child:
      DropdownButtonHideUnderline(
        child:
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items
              .map(
                (item) =>
                DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    style:
                    AppTheme.body(
                      size: 13,
                      color:
                      AppColors
                          .textDark,
                    ),
                  ),
                ),
          )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
      ),
    );
  }
}