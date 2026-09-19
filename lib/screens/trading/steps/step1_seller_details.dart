import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/trading_purchase_draft.dart';
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
  State<Step1SellerDetails> createState() => _Step1SellerDetailsState();
}

class _Step1SellerDetailsState extends State<Step1SellerDetails> {
  late final TextEditingController _sellerNameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _marketController;
  late final TextEditingController _vehicleController;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    _sellerNameController = TextEditingController(text: draft.sellerName);
    _mobileController = TextEditingController(text: draft.mobile);
    _marketController = TextEditingController(text: draft.market);
    _vehicleController = TextEditingController(text: draft.vehicleNumber);
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
    // A purchase is something that already happened, so today is the latest
    // date allowed (this used to allow tomorrow).
    final picked = await showWizardDatePicker(
      context: context,
      initialDate: widget.draft.purchaseDate,
      firstDate: DateTime(2020),
      lastDate: _today,
      helpText: 'Purchase date',
    );

    if (picked == null || !mounted) return;

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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                textCapitalization: TextCapitalization.words,
                onChanged: (value) {
                  draft.sellerName = value;
                },
                validator: (value) {
                  final v = value?.trim() ?? '';

                  if (v.isEmpty) return 'Enter seller name';
                  if (v.length < 2) return 'Name is too short';

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

                  if (v.isEmpty) return 'Enter mobile number';

                  if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) {
                    return 'Enter a valid 10-digit number';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _marketController,
                label: 'Market / Location',
                hint: 'e.g. Bakrid Mandi, Pune',
                icon: Icons.location_on_outlined,
                optional: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) {
                  draft.market = value;
                },
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _vehicleController,
                label: 'Vehicle Number',
                hint: 'e.g. MH12AB1234',
                icon: Icons.local_shipping_outlined,
                optional: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  // Vehicle numbers have no spaces or symbols worth keeping.
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[A-Za-z0-9 -]'),
                  ),
                ],
                onChanged: (value) {
                  draft.vehicleNumber = value.toUpperCase();
                },
              ),

              const SizedBox(height: 14),

              WizardDateField(
                label: 'Purchase Date *',
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