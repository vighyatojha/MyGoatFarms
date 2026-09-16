import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_theme.dart';
import '../../../../models/trading_purchase_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 1 — Seller Details.
///
/// Captures the wholesale seller information before the goat purchase
/// details are entered.
///
/// Required:
/// - Seller Name
/// - Mobile Number
/// - Purchase Date
///
/// Optional:
/// - Market / Location
/// - Vehicle Number
class Step1SellerDetails extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PurchaseDraft draft;

  const Step1SellerDetails({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<Step1SellerDetails> createState() =>
      _Step1SellerDetailsState();
}

class _Step1SellerDetailsState
    extends State<Step1SellerDetails> {
  late final TextEditingController _sellerNameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _marketController;
  late final TextEditingController _vehicleController;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _sellerNameController = TextEditingController(
      text: draft.sellerName,
    );

    _mobileController = TextEditingController(
      text: draft.mobile,
    );

    _marketController = TextEditingController(
      text: draft.market,
    );

    _vehicleController = TextEditingController(
      text: draft.vehicleNumber,
    );
  }

  @override
  void dispose() {
    _sellerNameController.dispose();
    _mobileController.dispose();
    _marketController.dispose();
    _vehicleController.dispose();

    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.draft.purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(
        const Duration(days: 1),
      ),
      builder: (context, child) {
        final theme = Theme.of(context);

        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textDark,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor:
              AppColors.primaryGreen,
              headerForegroundColor: Colors.white,
              todayForegroundColor:
              const WidgetStatePropertyAll(
                AppColors.primaryGreen,
              ),
              todayBorder: const BorderSide(
                color: AppColors.primaryGreen,
              ),
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
      widget.draft.purchaseDate = picked;
    });
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
          WizardSectionCard(
            title: 'Seller Details',
            icon: Icons.person_outline_rounded,
            children: [
              wizardField(
                controller: _sellerNameController,
                label: 'Seller Name',
                hint: 'e.g. Ramesh Traders',
                icon: Icons.badge_outlined,
                onChanged: (value) {
                  draft.sellerName = value;
                },
                validator: (value) {
                  final v = value?.trim() ?? '';

                  if (v.isEmpty) {
                    return 'Enter seller name';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _mobileController,
                label: 'Mobile Number',
                hint: '10-digit mobile number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (value) {
                  draft.mobile = value;
                },
                validator: (value) {
                  final v = value?.trim() ?? '';

                  if (v.isEmpty) {
                    return 'Enter mobile number';
                  }

                  if (!RegExp(
                    r'^[0-9]{10}$',
                  ).hasMatch(v)) {
                    return 'Enter a valid 10-digit number';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _marketController,
                label: 'Market / Location',
                hint: 'Optional',
                icon: Icons.location_on_outlined,
                optional: true,
                onChanged: (value) {
                  draft.market = value;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _vehicleController,
                label: 'Vehicle Number',
                hint: 'Optional',
                icon: Icons.local_shipping_outlined,
                optional: true,
                onChanged: (value) {
                  draft.vehicleNumber = value;
                },
              ),

              const SizedBox(height: 14),

              WizardDateField(
                label: 'Purchase Date',
                date: draft.purchaseDate,
                onTap: _pickPurchaseDate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}