import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/trading_purchase_draft.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 1 — Supplier Details.
///
/// Captures the wholesale supplier information before the lot details are
/// entered.
///
/// Required:
/// - Seller Name
/// - Mobile Number
/// - Purchase Date
///
/// Optional:
/// - Market / Location
/// - Vehicle / Transport Details (free text: vehicle number, driver, tempo…)
/// - Expected Delivery Date (when the supplier is due to deliver the lot)
/// - Remarks (saved with the lot whether or not the goats have arrived)
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
  late final TextEditingController _remarksController;

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
    _remarksController = TextEditingController(text: draft.supplierRemarks);
  }

  @override
  void dispose() {
    _sellerNameController.dispose();
    _mobileController.dispose();
    _marketController.dispose();
    _vehicleController.dispose();
    _remarksController.dispose();
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

  Future<void> _pickExpectedDelivery() async {
    // Delivery is in the future (or today) — the opposite of the purchase
    // date — so the range starts at the purchase date.
    final start = DateTime(
      widget.draft.purchaseDate.year,
      widget.draft.purchaseDate.month,
      widget.draft.purchaseDate.day,
    );

    final picked = await showWizardDatePicker(
      context: context,
      initialDate: widget.draft.expectedDeliveryDate ??
          (_today.isBefore(start) ? start : _today),
      firstDate: start,
      lastDate: DateTime(_today.year + 2),
      helpText: 'Expected delivery date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      widget.draft.expectedDeliveryDate = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    // The purchase date can be changed after an expected date was chosen;
    // a delivery date before the purchase makes no sense, so drop it.
    final expected = draft.expectedDeliveryDate;
    if (expected != null && expected.isBefore(
      DateTime(
        draft.purchaseDate.year,
        draft.purchaseDate.month,
        draft.purchaseDate.day,
      ),
    )) {
      draft.expectedDeliveryDate = null;
    }

    return Form(
      key: widget.formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          WizardSectionCard(
            title: 'Supplier Details',
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
                label: 'Vehicle / Transport Details',
                hint: 'e.g. MH12AB1234, tempo, driver name',
                icon: Icons.local_shipping_outlined,
                optional: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  // Free text (vehicle number, driver, transport mode) —
                  // just cap the length so it stays a one-line detail.
                  LengthLimitingTextInputFormatter(120),
                ],
                onChanged: (value) {
                  draft.vehicleNumber = value;
                },
              ),

              const SizedBox(height: 14),

              WizardDateField(
                label: 'Purchase Date *',
                date: draft.purchaseDate,
                onTap: _pickPurchaseDate,
              ),

              const SizedBox(height: 14),

              // Optional — shown as "Not set" until chosen, with a clear
              // button once it is.
              Stack(
                alignment: Alignment.centerRight,
                children: [
                  InkWell(
                    onTap: _pickExpectedDelivery,
                    borderRadius: BorderRadius.circular(13),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Expected Delivery Date',
                        helperText:
                        'Optional — when the supplier will deliver the lot',
                        prefixIcon: const Icon(
                          Icons.local_shipping_outlined,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        draft.expectedDeliveryDate == null
                            ? 'Not set'
                            : wizardDate(draft.expectedDeliveryDate!),
                        style: TextStyle(
                          fontSize: 13,
                          color: draft.expectedDeliveryDate == null
                              ? Colors.black45
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  if (draft.expectedDeliveryDate != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 18),
                      child: IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          draft.expectedDeliveryDate = null;
                        }),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 14),

              wizardField(
                controller: _remarksController,
                label: 'Remarks',
                hint: 'e.g. Bought at Sunday mandi, 5 goats look weak',
                icon: Icons.edit_note_rounded,
                maxLines: 3,
                optional: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) {
                  draft.supplierRemarks = value;
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}