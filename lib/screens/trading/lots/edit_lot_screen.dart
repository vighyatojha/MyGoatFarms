import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../models/partner_permission_keys.dart';
import '../../../models/purchase_costing.dart';
import '../../../models/trading_purchase_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/partner_access_service.dart';
import '../../../services/trading_service.dart';
import '../../../widgets/fast_route.dart';
import '../purchase_goats/purchase_wizard_widgets.dart';

/// Opens the Edit Lot screen after checking the person may manage stock.
///
/// Returns true when the lot was saved. Used by Lot Management and Lot
/// Detail so both entry points behave the same.
Future<bool?> openEditLotScreen({
  required BuildContext context,
  required String farmId,
  required TradingPurchase lot,
}) async {
  if (!PartnerAccessService.instance
      .allows(PartnerPermissionKeys.tradingManageStock)) {
    wizardSnack(
      context,
      'You don\u2019t have permission to edit lots.',
      error: true,
    );
    return null;
  }

  if (lot.dealCancelled) {
    wizardSnack(
      context,
      'This deal was cancelled, so the lot cannot be edited.',
      error: true,
    );
    return null;
  }

  return Navigator.of(context).push<bool>(
    fastRoute(EditLotScreen(farmId: farmId, lot: lot)),
  );
}

/// Edit Lot — change a lot's supplier details, purchase figures and extra
/// costs. Works while the goats are at the supplier AND after they reached
/// the farm.
///
/// The summary pinned to the top is calculated live from what is typed, with
/// the same [PurchaseCosting] engine the purchase wizard uses, so what is
/// shown is exactly what gets saved.
class EditLotScreen extends StatefulWidget {
  final String farmId;
  final TradingPurchase lot;

  const EditLotScreen({super.key, required this.farmId, required this.lot});

  @override
  State<EditLotScreen> createState() => _EditLotScreenState();
}

class _EditLotScreenState extends State<EditLotScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _mobile;
  late final TextEditingController _market;
  late final TextEditingController _vehicle;
  late final TextEditingController _remarks;

  late final TextEditingController _goats;
  late final TextEditingController _male;
  late final TextEditingController _female;
  late final TextEditingController _weight;
  late final TextEditingController _price;

  late final TextEditingController _transport;
  late final TextEditingController _loading;
  late final TextEditingController _unloading;
  late final TextEditingController _other;

  late DateTime _purchaseDate;
  DateTime? _expectedDelivery;

  bool _saving = false;

  TradingPurchase get _lot => widget.lot;

  @override
  void initState() {
    super.initState();

    final lot = widget.lot;

    String money(double v) => v > 0 ? PurchaseCosting.formatNumber(v) : '';

    _name = TextEditingController(text: lot.sellerName);
    _mobile = TextEditingController(text: lot.mobile);
    _market = TextEditingController(text: lot.market);
    _vehicle = TextEditingController(text: lot.vehicleNumber);
    _remarks = TextEditingController(text: lot.remarks);

    _goats = TextEditingController(text: '${lot.totalGoats}');
    _male = TextEditingController(
      text: (lot.maleGoats > 0 || lot.femaleGoats > 0) ? '${lot.maleGoats}' : '',
    );
    _female = TextEditingController(
      text:
      (lot.maleGoats > 0 || lot.femaleGoats > 0) ? '${lot.femaleGoats}' : '',
    );
    _weight = TextEditingController(
      text: PurchaseCosting.formatNumber(lot.totalWeightAtPurchase),
    );
    _price = TextEditingController(
      text: PurchaseCosting.formatNumber(lot.pricePerKg),
    );

    _transport = TextEditingController(text: money(lot.transportCost));
    _loading = TextEditingController(text: money(lot.loadingCharges));
    _unloading = TextEditingController(text: money(lot.unloadingCharges));
    _other = TextEditingController(text: money(lot.otherExpenses));

    _purchaseDate = lot.purchaseDate;
    _expectedDelivery = lot.expectedDeliveryDate;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _mobile,
      _market,
      _vehicle,
      _remarks,
      _goats,
      _male,
      _female,
      _weight,
      _price,
      _transport,
      _loading,
      _unloading,
      _other,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // LIVE NUMBERS
  // ---------------------------------------------------------------------

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  PurchaseCosting get _costing => PurchaseCosting(
    totalGoats: _i(_goats),
    weightAtPurchase: _d(_weight),
    pricePerKg: _d(_price),
    weightAfterArrival: _lot.totalWeightAfterArrival ?? 0,
    mortality: _lot.mortality,
    transportCost: _d(_transport),
    loadingCharges: _d(_loading),
    unloadingCharges: _d(_unloading),
    otherExpenses: _d(_other),
  );

  void _refresh() => setState(() {});

  // ---------------------------------------------------------------------
  // DATES
  // ---------------------------------------------------------------------

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: _today,
      helpText: 'Purchase date',
    );

    if (picked == null || !mounted) return;
    setState(() => _purchaseDate = picked);
  }

  Future<void> _pickExpectedDelivery() async {
    final first = DateTime(
      _purchaseDate.year,
      _purchaseDate.month,
      _purchaseDate.day,
    );

    final picked = await showWizardDatePicker(
      context: context,
      initialDate: _expectedDelivery ?? _today,
      firstDate: first,
      lastDate: _today.add(const Duration(days: 365)),
      helpText: 'Expected delivery date',
    );

    if (picked == null || !mounted) return;
    setState(() => _expectedDelivery = picked);
  }

  // ---------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final costing = _costing;

    if (costing.purchaseAmount + 0.005 < _lot.paidAmount) {
      _fail(
        'The new purchase amount (${wizardCurrency(costing.purchaseAmount)}) '
            'is less than the ${wizardCurrency(_lot.paidAmount)} already paid. '
            'Void a payment first, or raise the weight / price.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await TradingService.instance.editLot(
        farmId: widget.farmId,
        lotDocId: _lot.id,
        sellerName: _name.text,
        mobile: _mobile.text,
        market: _market.text,
        vehicleNumber: _vehicle.text,
        purchaseDate: _purchaseDate,
        remarks: _remarks.text,
        expectedDeliveryDate: _lot.supplierQty > 0 ? _expectedDelivery : null,
        totalGoats: _i(_goats),
        maleGoats: _i(_male),
        femaleGoats: _i(_female),
        totalWeightAtPurchase: _d(_weight),
        pricePerKg: _d(_price),
        transportCost: _d(_transport),
        loadingCharges: _d(_loading),
        unloadingCharges: _d(_unloading),
        otherExpenses: _d(_other),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      _fail(e.message?.toString() ?? 'Please check the lot details.');
    } on StateError catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail(FirestoreService.instance.describeError(e));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _saving = false);
    wizardSnack(context, message, error: true);
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lot = _lot;

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(title: Text('Edit ${lot.lotId}')),
      body: Column(
        children: [
          // Pinned: stays visible while the form scrolls.
          _liveSummary(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  WizardNote(
                    lot.location == LotLocation.atSupplier
                        ? 'Goats are still at the supplier. You can change '
                        'every detail of the deal.'
                        : 'Goats have reached the farm (${lot.receivedTotalQty} '
                        'received). Changes recalculate the lot cost; sales '
                        'already made keep the cost they were saved with.',
                  ),
                  const SizedBox(height: 14),
                  _supplierCard(),
                  const SizedBox(height: 14),
                  _purchaseCard(),
                  const SizedBox(height: 14),
                  _costsCard(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
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
                          : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Purchase amount, grand total, paid and balance due — recalculated on
  /// every keystroke.
  Widget _liveSummary() {
    final costing = _costing;
    final amount = costing.purchaseAmount;
    final paid = _lot.paidAmount;
    final dueRaw = PurchaseCosting.round2(amount - paid);
    final overpaid = dueRaw < -0.005;
    final due = dueRaw < 0 ? 0.0 : dueRaw;
    final changed = (amount - _lot.purchaseAmount).abs() >= 0.005;

    Widget cell(String label, String value, {Color? color}) {
      return Expanded(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: AppTheme.heading(
                  size: 16,
                  color: color ?? AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 10),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Live totals', style: AppTheme.heading(size: 13)),
                const Spacer(),
                if (changed)
                  Text(
                    'was ${wizardCurrency(_lot.purchaseAmount)}',
                    style: AppTheme.body(size: 11),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                cell('Purchase amount', wizardCurrency(amount),
                    color: AppColors.primaryGreen),
                cell('Grand total', wizardCurrency(costing.grandTotal)),
                cell('Paid', wizardCurrency(paid)),
                cell(
                  'Balance due',
                  wizardCurrency(due),
                  color: due >= 0.01 ? AppColors.error : AppColors.success,
                ),
              ],
            ),
            if (overpaid) ...[
              const SizedBox(height: 8),
              Text(
                'New amount is ${wizardCurrency(-dueRaw)} less than already '
                    'paid — raise the weight / price or void a payment.',
                style: AppTheme.body(size: 11, color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SECTIONS
  // ---------------------------------------------------------------------

  Widget _supplierCard() {
    final lot = _lot;

    return WizardSectionCard(
      title: 'Supplier',
      icon: Icons.person_outline_rounded,
      children: [
        wizardField(
          controller: _name,
          label: 'Supplier name',
          hint: 'Supplier name',
          icon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
        ),
        const SizedBox(height: 12),
        wizardField(
          controller: _mobile,
          label: 'Mobile',
          hint: 'Mobile number',
          icon: Icons.phone_outlined,
          optional: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            LengthLimitingTextInputFormatter(15),
          ],
        ),
        const SizedBox(height: 12),
        wizardField(
          controller: _market,
          label: 'Market',
          hint: 'Market / place',
          icon: Icons.storefront_outlined,
          optional: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
        ),
        const SizedBox(height: 12),
        wizardField(
          controller: _vehicle,
          label: 'Vehicle / Transport',
          hint: 'e.g. GJ05 AB 1234',
          icon: Icons.local_shipping_outlined,
          optional: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(30)],
        ),
        const SizedBox(height: 12),
        WizardDateField(
          label: 'Purchase date *',
          date: _purchaseDate,
          onTap: _pickPurchaseDate,
        ),
        if (lot.supplierQty > 0) ...[
          const SizedBox(height: 12),
          if (_expectedDelivery == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickExpectedDelivery,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: const Text('Add expected delivery date'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: WizardDateField(
                    label: 'Expected delivery',
                    date: _expectedDelivery!,
                    onTap: _pickExpectedDelivery,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove expected delivery date',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _expectedDelivery = null),
                ),
              ],
            ),
        ],
        const SizedBox(height: 12),
        wizardField(
          controller: _remarks,
          label: 'Remarks',
          hint: 'Anything worth remembering',
          icon: Icons.notes_rounded,
          optional: true,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
        ),
      ],
    );
  }

  Widget _purchaseCard() {
    final lot = _lot;
    final minGoats = lot.minEditableTotalGoats;
    final arrivedWeight = lot.totalWeightAfterArrival ?? 0;

    String? genderCheck(String? _) {
      final m = _i(_male);
      final f = _i(_female);

      if (m + f == 0) return null;

      if (m + f != _i(_goats)) {
        return 'Male + Female must equal total goats';
      }

      return null;
    }

    return WizardSectionCard(
      title: 'Purchase',
      icon: Icons.shopping_cart_outlined,
      children: [
        wizardField(
          controller: _goats,
          label: 'Total goats',
          hint: '0',
          icon: Icons.pets_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          helper: minGoats > 0
              ? 'At least $minGoats — already sold from the supplier or '
              'received'
              : null,
          onChanged: (_) => _refresh(),
          validator: (value) {
            final n = int.tryParse(value?.trim() ?? '');

            if (n == null || n <= 0) return 'Enter at least 1 goat';

            if (n < minGoats) return 'Cannot be less than $minGoats';

            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: wizardField(
                controller: _male,
                label: 'Male',
                hint: '0',
                icon: Icons.male_rounded,
                optional: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (_) => _refresh(),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '') ?? 0;

                  if ((n > 0 || _i(_female) > 0) && n < lot.maleRegistered) {
                    return 'At least ${lot.maleRegistered} (registered)';
                  }

                  return genderCheck(value);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: wizardField(
                controller: _female,
                label: 'Female',
                hint: '0',
                icon: Icons.female_rounded,
                optional: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (_) => _refresh(),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '') ?? 0;

                  if ((n > 0 || _i(_male) > 0) && n < lot.femaleRegistered) {
                    return 'At least ${lot.femaleRegistered} (registered)';
                  }

                  return genderCheck(value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        wizardField(
          controller: _weight,
          label: 'Weight at purchase',
          hint: '0.00',
          icon: Icons.scale_outlined,
          suffix: 'kg',
          keyboardType: wizardDecimalKeyboard,
          inputFormatters: wizardDecimalFormatters(),
          helper: arrivedWeight > 0
              ? 'At least ${PurchaseCosting.formatNumber(arrivedWeight)} kg — '
              'already arrived'
              : null,
          onChanged: (_) => _refresh(),
          validator: (value) {
            final n = double.tryParse(value?.trim() ?? '');

            if (n == null || n <= 0) return 'Enter a weight greater than 0';

            if (n + 0.005 < arrivedWeight) {
              return 'Cannot be less than '
                  '${PurchaseCosting.formatNumber(arrivedWeight)} kg';
            }

            return null;
          },
        ),
        const SizedBox(height: 12),
        wizardField(
          controller: _price,
          label: 'Price per kg',
          hint: '0.00',
          icon: Icons.currency_rupee_rounded,
          keyboardType: wizardDecimalKeyboard,
          inputFormatters: wizardDecimalFormatters(),
          onChanged: (_) => _refresh(),
          validator: (value) {
            final n = double.tryParse(value?.trim() ?? '');

            if (n == null || n <= 0) return 'Enter a price greater than 0';

            return null;
          },
        ),
      ],
    );
  }

  Widget _costsCard() {
    Widget cost(TextEditingController c, String label, IconData icon) {
      return wizardField(
        controller: c,
        label: label,
        hint: '0.00',
        icon: icon,
        optional: true,
        keyboardType: wizardDecimalKeyboard,
        inputFormatters: wizardDecimalFormatters(),
        onChanged: (_) => _refresh(),
      );
    }

    final costing = _costing;

    return WizardSectionCard(
      title: 'Transport & other costs',
      icon: Icons.receipt_long_outlined,
      children: [
        cost(_transport, 'Transport', Icons.local_shipping_outlined),
        const SizedBox(height: 12),
        cost(_loading, 'Loading charges', Icons.upload_outlined),
        const SizedBox(height: 12),
        cost(_unloading, 'Unloading charges', Icons.download_outlined),
        const SizedBox(height: 12),
        cost(_other, 'Other expenses', Icons.more_horiz_rounded),
        const Divider(height: 24, color: AppColors.divider),
        WizardComputedRow(
          label: 'Total costs',
          value: wizardCurrency(costing.totalExpenses),
        ),
        WizardComputedRow(
          label: 'Grand total',
          value: wizardCurrency(costing.grandTotal),
          emphasize: true,
        ),
      ],
    );
  }
}