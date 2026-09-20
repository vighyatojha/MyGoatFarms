import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/sale_draft.dart';
import '../../../services/sales_service.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Step 2 — Customer Mobile Lookup.
///
/// Enter a mobile number (or name) -> search across both the Sale
/// `customers` collection AND the existing `palaiCustomers` collection,
/// so a person who already boards a goat here is recognised immediately
/// instead of getting registered a second time under a new ID.
///
/// - Existing match found: pre-fill Name/Address (editable), and flag
///   clearly when the match is an existing Palai customer.
/// - No match: fall through to blank Name/Mobile/Address fields for a
///   brand-new customer.
///
/// Exposes [validate] via its State (same pattern as Step4Summary in the
/// Purchase wizard) so the wizard's Next button can block advancing
/// until a customer has actually been picked or created.
class Step2CustomerLookup extends StatefulWidget {
  final String farmId;
  final SaleDraft draft;

  const Step2CustomerLookup({
    super.key,
    required this.farmId,
    required this.draft,
  });

  @override
  State<Step2CustomerLookup> createState() =>
      Step2CustomerLookupState();
}

class Step2CustomerLookupState extends State<Step2CustomerLookup> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  Timer? _debounce;
  bool _searching = false;
  List<CustomerMatch> _results = const [];

  /// True once a customer (existing or new) has been confirmed and the
  /// editable detail form should show instead of the search list.
  bool _detailsMode = false;

  @override
  void initState() {
    super.initState();

    final draft = widget.draft;

    // Coming back to Step 2 after already picking someone (Back button
    // from Step 3+) should re-open straight into the detail form.
    if (draft.mobile.isNotEmpty || draft.customerName.isNotEmpty) {
      _detailsMode = true;
      _nameController.text = draft.customerName;
      _mobileController.text = draft.mobile;
      _addressController.text = draft.address;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  void _onQueryChanged(String value) {
    _debounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
    });

    _debounce = Timer(
      const Duration(milliseconds: 350),
          () async {
        final matches = await SalesService.instance.searchCustomerMatches(
          widget.farmId,
          value,
        );

        if (!mounted) return;

        setState(() {
          _results = matches;
          _searching = false;
        });
      },
    );
  }

  void _selectMatch(CustomerMatch match) {
    widget.draft.applyMatch(match);

    _nameController.text = match.name;
    _mobileController.text = match.mobile;
    _addressController.text = match.address;

    setState(() {
      _detailsMode = true;
    });
  }

  void _addAsNewCustomer() {
    final typed = _queryController.text.trim();

    widget.draft.clearCustomerMatch();

    // If what was typed looks like a mobile number, seed the Mobile
    // field with it so the person doesn't have to retype it.
    final looksLikeMobile = RegExp(r'^[0-9]{4,}$').hasMatch(typed);

    _nameController.text = '';
    _mobileController.text = looksLikeMobile ? typed : '';
    _addressController.text = '';

    setState(() {
      _detailsMode = true;
    });
  }

  void _searchDifferentCustomer() {
    widget.draft.clearCustomerMatch();

    setState(() {
      _detailsMode = false;
      _results = const [];
      _queryController.clear();
    });
  }

  // ===========================================================================
  // VALIDATE (called by the wizard's Next button)
  // ===========================================================================

  bool validate() {
    if (!_detailsMode) {
      wizardSnack(
        context,
        'Search and select a customer, or add a new one first.',
        error: true,
      );
      return false;
    }

    final valid = _formKey.currentState?.validate() ?? false;

    if (!valid) return false;

    _formKey.currentState?.save();

    widget.draft.customerName = _nameController.text.trim();
    widget.draft.mobile = _mobileController.text.trim();
    widget.draft.address = _addressController.text.trim();

    return true;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_detailsMode) {
      return _buildDetailsForm();
    }

    return _buildSearch();
  }

  // ---------------------------------------------------------------------------
  // SEARCH VIEW
  // ---------------------------------------------------------------------------

  Widget _buildSearch() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        WizardSectionCard(
          title: 'Find Customer',
          icon: Icons.person_search_outlined,
          children: [
            TextFormField(
              controller: _queryController,
              onChanged: _onQueryChanged,
              keyboardType: TextInputType.text,
              style: AppTheme.body(size: 13, color: AppColors.textDark),
              decoration: InputDecoration(
                labelText: 'Mobile Number or Name',
                hintText: 'e.g. 9876543210 or Ramesh',
                prefixIcon: const Icon(
                  Icons.phone_outlined,
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
                labelStyle: AppTheme.body(
                  size: 12,
                  color: AppColors.textGrey,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(
                    color: AppColors.primaryGreen,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryGreen,
              ),
            ),
          )
        else if (_queryController.text.trim().isNotEmpty) ...[
          if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No matching customer found.',
                style: AppTheme.body(size: 12, color: AppColors.textGrey),
              ),
            )
          else
            ..._results.map(
                  (match) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CustomerMatchTile(
                  match: match,
                  onTap: () => _selectMatch(match),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],

        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _addAsNewCustomer,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
            label: const Text(
              'Add as New Customer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: BorderSide(
                color: AppColors.primaryGreen.withOpacity(0.35),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // DETAIL FORM VIEW
  // ---------------------------------------------------------------------------

  Widget _buildDetailsForm() {
    final draft = widget.draft;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (draft.isExistingCustomer)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: (draft.isExistingPalaiCustomer
                      ? AppColors.tradingBlue
                      : AppColors.info)
                      .withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      draft.isExistingPalaiCustomer
                          ? Icons.holiday_village_outlined
                          : Icons.verified_user_outlined,
                      size: 17,
                      color: draft.isExistingPalaiCustomer
                          ? AppColors.tradingBlue
                          : AppColors.info,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        draft.isExistingPalaiCustomer
                            ? 'Existing Palai customer — details filled in below'
                            : 'Existing customer — details filled in below',
                        style: AppTheme.body(
                          size: 11,
                          color: draft.isExistingPalaiCustomer
                              ? AppColors.tradingBlue
                              : AppColors.info,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          WizardSectionCard(
            title: 'Customer Details',
            icon: Icons.badge_outlined,
            children: [
              wizardField(
                controller: _nameController,
                label: 'Name',
                hint: 'Customer name',
                icon: Icons.person_outline_rounded,
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Enter customer name';
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
                controller: _addressController,
                label: 'Address',
                hint: 'Optional',
                icon: Icons.location_on_outlined,
                optional: true,
                maxLines: 2,
              ),
            ],
          ),

          const SizedBox(height: 10),

          TextButton.icon(
            onPressed: _searchDifferentCustomer,
            icon: const Icon(Icons.search_rounded, size: 17),
            label: const Text(
              'Search a different customer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CUSTOMER MATCH TILE
// ============================================================================

class _CustomerMatchTile extends StatelessWidget {
  final CustomerMatch match;
  final VoidCallback onTap;

  const _CustomerMatchTile({
    required this.match,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPalai = match.source == CustomerMatchSource.palai;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(radius: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isPalai
                      ? AppColors.tradingBlue
                      : AppColors.primaryGreen)
                      .withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: isPalai
                      ? AppColors.tradingBlue
                      : AppColors.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            match.name.isEmpty ? 'Unnamed' : match.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.heading(
                              size: 13,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        if (isPalai)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tradingBlue.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              match.palaiPackageName?.isNotEmpty == true
                                  ? 'Palai · ${match.palaiPackageName}'
                                  : 'Palai Customer',
                              style: const TextStyle(
                                color: AppColors.tradingBlue,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      match.mobile,
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}