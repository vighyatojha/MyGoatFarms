
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import 'final_checkout_report_screen.dart';

/// Data carried from the Review Checkout screen into
/// Charges & Payment.
class GoatCheckoutDraft {
final PalaiGoat goat;
final double finalWeight;
final String healthStatus;
final String deliveryStatus;
final Uint8List? afterImage;
final String notes;

const GoatCheckoutDraft({
required this.goat,
required this.finalWeight,
required this.healthStatus,
required this.deliveryStatus,
required this.afterImage,
required this.notes,
});
}

class CheckoutChargesPaymentScreen extends StatefulWidget {
final String farmId;
final String customerId;
final List<GoatCheckoutDraft> goats;

const CheckoutChargesPaymentScreen({
super.key,
required this.farmId,
required this.customerId,
required this.goats,
});

@override
State<CheckoutChargesPaymentScreen> createState() =>
_CheckoutChargesPaymentScreenState();
}

class _CheckoutChargesPaymentScreenState
extends State<CheckoutChargesPaymentScreen> {
PalaiCustomer? _customer;

BillSettings _billSettings = const BillSettings();

bool _loading = true;
bool _saving = false;

String? _error;

late final TextEditingController _chargesController;

/// This controller is ONLY for the second transport charge:
/// transport collected at checkout.
late final TextEditingController _checkOutTransportController;

late final TextEditingController _discountController;
late final TextEditingController _paidController;
late final TextEditingController _noteController;

String _paymentMethod = 'Cash';

@override
void initState() {
super.initState();

final defaultCharges = widget.goats.fold<double>(
0,
(sum, item) => sum + item.goat.pricing,
);

_chargesController = TextEditingController(
text: defaultCharges.toStringAsFixed(0),
);

_checkOutTransportController =
TextEditingController(text: '0');

_discountController =
TextEditingController(text: '0');

_paidController =
TextEditingController(text: '0');

_noteController =
TextEditingController();

_loadCustomer();
}

@override
void dispose() {
_chargesController.dispose();
_checkOutTransportController.dispose();
_discountController.dispose();
_paidController.dispose();
_noteController.dispose();
super.dispose();
}

// ================================================================
// LOAD CUSTOMER
// ================================================================

Future<void> _loadCustomer() async {
try {
final customer =
await FirestoreService.instance.getCustomer(
widget.farmId,
widget.customerId,
);

if (!mounted) return;

if (customer == null) {
setState(() {
_loading = false;
_error = 'Customer could not be found.';
});
return;
}

final farm =
await FirestoreService.instance.getFarmById(
widget.farmId,
);

if (!mounted) return;

setState(() {
_customer = customer;
_billSettings =
farm?.billSettings ?? const BillSettings();
_loading = false;
});
} catch (e) {
if (!mounted) return;

setState(() {
_loading = false;
_error = FirestoreService.instance.describeError(e);
});
}
}

// ================================================================
// PARSING
// ================================================================

double _parse(TextEditingController controller) {
return double.tryParse(
controller.text.trim(),
) ??
0;
}

// ================================================================
// AMOUNT CALCULATIONS
// ================================================================

/// Palai/package charges for the goats being checked out.
double get _palaiCharges =>
_parse(_chargesController);

/// Transport collected at FINAL CHECKOUT.
///
/// This is intentionally separate from [checkInTransportTotal].
double get _checkOutTransport =>
_parse(_checkOutTransportController);

/// Transport already collected at CHECK-IN.
///
/// This value must NOT be added to the current bill again because
/// it has already been posted during check-in.
double get _checkInTransportTotal {
return widget.goats.fold<double>(
0,
(sum, draft) =>
sum + draft.goat.checkInTransportCharge,
);
}

double get _discount =>
_parse(_discountController);

double get _paid =>
_parse(_paidController);

double get _previousPending =>
_customer?.pendingAmount ?? 0;

double get _advanceBefore =>
_customer?.advanceAmount ?? 0;

/// Charges being added NOW.
///
/// IMPORTANT:
/// Check-in transport is deliberately NOT included here.
/// It was already charged/recorded when the goats entered the farm.
///
/// Only:
///   Palai charges
///   + Check-out transport
///   - Discount
///
/// are part of this final checkout bill.
double get _newCharges {
return (
_palaiCharges +
_checkOutTransport -
_discount
)
    .clamp(
0,
double.infinity,
)
    .toDouble();
}

double get _totalBeforeAdvance {
return _previousPending + _newCharges;
}

double get _advanceApplied {
return _advanceBefore
    .clamp(
0,
_totalBeforeAdvance,
)
    .toDouble();
}

double get _totalDue {
return (
_totalBeforeAdvance -
_advanceApplied
)
    .clamp(
0,
double.infinity,
)
    .toDouble();
}

double get _amountAppliedFromPayment {
return _paid
    .clamp(
0,
_totalDue,
)
    .toDouble();
}

double get _newAdvanceFromPayment {
return (
_paid -
_totalDue
)
    .clamp(
0,
double.infinity,
)
    .toDouble();
}

double get _pendingAfter {
return (
_totalDue -
_paid
)
    .clamp(
0,
double.infinity,
)
    .toDouble();
}

double get _advanceAfter {
return (
_advanceBefore -
_advanceApplied +
_newAdvanceFromPayment
)
    .clamp(
0,
double.infinity,
)
    .toDouble();
}

// ================================================================
// COMPLETE CHECKOUT
// ================================================================

Future<void> _completeCheckout() async {
if (_saving) return;

if (widget.goats.isEmpty) {
_showError(
'No goats were selected for checkout.',
);
return;
}

if (_palaiCharges < 0 ||
_checkOutTransport < 0 ||
_discount < 0 ||
_paid < 0) {
_showError(
'Amounts cannot be negative.',
);
return;
}

if (_discount >
(_palaiCharges + _checkOutTransport)) {
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

/// The final checkout flow currently requires the customer
/// account to be completely settled before proceeding.
if (_pendingAfter > 0) {
await _showPaymentRequiredDialog();
return;
}

setState(() {
_saving = true;
});

try {
// ------------------------------------------------------------
// CREATE THE FINAL BILL RECORD.
//
// The transport amount sent here is ONLY the checkout
// transport amount.
//
// Check-in transport was already recorded during check-in
// and is intentionally not sent again.
// ------------------------------------------------------------

final billResult =
await FirestoreService.instance.createMonthlyBill(
farmId: widget.farmId,
customerId: widget.customerId,
monthlyCharges: _palaiCharges,
transportCharges: _checkOutTransport,
discount: _discount,
paidAmount: _paid,
paymentMethod: _paymentMethod,
note: _noteController.text.trim(),
);

if (!mounted) return;

setState(() {
_saving = false;
});

// ------------------------------------------------------------
// IMPORTANT FLOW
//
// Complete Checkout
//        ↓
// Final Checkout Report
//        ↓
// Existing Monthly Reports listed
//        ↓
// Review all final checkout data
//        ↓
// Generate PDF
//        ↓
// PDF Generated screen
//        ↓
// Download OR Share
//        ↓
// Done becomes enabled
//        ↓
// ONLY THEN mark goats as checked out
//
// Therefore NO goat is checked out here.
// ------------------------------------------------------------

final result =
await Navigator.of(context).push(
MaterialPageRoute(
builder: (_) =>
FinalCheckoutReportScreen(
farmId: widget.farmId,
customerId: widget.customerId,
goats: widget.goats,
billResult: billResult,
billSettings: _billSettings,

/// Second transport charge:
/// transport collected at checkout.
checkOutTransport:
_checkOutTransport,

/// The final report screen calls this only after
/// Generate PDF -> Download/Share -> Done.
onDone: () async {
for (final draft in widget.goats) {
await FirestoreService.instance
    .checkOutGoat(
widget.farmId,
widget.customerId,
draft.goat.id,
finalWeight:
draft.finalWeight,
healthStatus:
draft.healthStatus,
afterImage:
draft.afterImage,
afterImageContentType:
draft.afterImage != null
? 'image/jpeg'
    : null,
);
}
},
),
),
);

if (!mounted) return;

if (result == true) {
Navigator.of(context).pop(true);
}
} catch (e) {
if (!mounted) return;

setState(() {
_saving = false;
});

_showError(
FirestoreService.instance.describeError(e),
);
}
}

// ================================================================
// PAYMENT REQUIRED
// ================================================================

Future<void> _showPaymentRequiredDialog() async {
if (!mounted) return;

await showDialog<void>(
context: context,
builder: (dialogContext) {
return AlertDialog(
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(16),
),
title: const Row(
children: [
Icon(
Icons.error_outline,
color: Colors.orange,
),
SizedBox(width: 8),
Text('Payment Required'),
],
),
content: Column(
mainAxisSize:
MainAxisSize.min,
crossAxisAlignment:
CrossAxisAlignment.stretch,
children: [
const Text(
'The final checkout cannot be completed while an amount is still outstanding. Please collect the remaining balance before checking out.',
),
const SizedBox(height: 16),
_paymentRequiredRow(
'Final Amount Due',
_rupees(_totalDue),
),
_paymentRequiredRow(
'Already Paid',
_rupees(_paid),
),
const Divider(height: 20),
_paymentRequiredRow(
'Remaining',
_rupees(_pendingAfter),
bold: true,
),
],
),
actions: [
TextButton(
onPressed: () =>
Navigator.of(dialogContext).pop(),
child: const Text('Okay'),
),
],
);
},
);
}

Widget _paymentRequiredRow(
String label,
String value, {
bool bold = false,
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
Expanded(
child: Text(
label,
style: TextStyle(
fontWeight: bold
? FontWeight.w700
    : FontWeight.w400,
),
),
),
Text(
value,
style: TextStyle(
fontWeight:
FontWeight.w700,
color: bold
? AppColors.error
    : AppColors.textDark,
),
),
],
),
);
}

// ================================================================
// ERROR
// ================================================================

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

// ================================================================
// RUPEES
// ================================================================

String _rupees(double value) {
return '₹${value.toStringAsFixed(0)}';
}

// ================================================================
// BUILD
// ================================================================

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
title: Text(
'Charges & Payment',
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

if (_error != null ||
_customer == null) {
return Scaffold(
backgroundColor:
AppColors.paleGreen,
appBar: AppBar(
backgroundColor:
AppColors.paleGreen,
elevation: 0,
title: Text(
'Charges & Payment',
style:
AppTheme.heading(size: 17),
),
),
body: Center(
child: Padding(
padding:
const EdgeInsets.all(24),
child: Column(
mainAxisSize:
MainAxisSize.min,
children: [
const Icon(
Icons.error_outline,
color:
AppColors.error,
size: 46,
),
const SizedBox(height: 12),
Text(
_error ??
'Customer not found.',
textAlign:
TextAlign.center,
style:
AppTheme.body(size: 13),
),
],
),
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
'Charges & Payment',
style:
AppTheme.heading(size: 17),
),
),
bottomNavigationBar:
_buildBottomBar(),
body: SafeArea(
child: ListView(
padding:
const EdgeInsets.fromLTRB(
16,
10,
16,
120,
),
children: [
_buildHeader(),

const SizedBox(height: 16),

_buildCustomerCard(),

const SizedBox(height: 16),

_buildGoatsCard(),

const SizedBox(height: 16),

_buildChargesCard(),

const SizedBox(height: 16),

_buildBalanceCard(),

const SizedBox(height: 16),

_buildPaymentCard(),

const SizedBox(height: 16),

_buildNoteCard(),
],
),
),
);
}

// ================================================================
// HEADER
// ================================================================

Widget _buildHeader() {
return Container(
padding:
const EdgeInsets.all(18),
decoration: BoxDecoration(
gradient:
const LinearGradient(
colors:
AppColors.headerGradient,
begin:
Alignment.topLeft,
end:
Alignment.bottomRight,
),
borderRadius:
BorderRadius.circular(18),
),
child: Row(
children: [
Container(
width: 48,
height: 48,
decoration:
BoxDecoration(
color: Colors.white
    .withOpacity(.18),
shape:
BoxShape.circle,
),
child:
const Icon(
Icons.receipt_long_outlined,
color:
Colors.white,
size: 25,
),
),
const SizedBox(width: 13),
Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
'Charges & Payment',
style:
AppTheme.heading(
size: 17,
color:
Colors.white,
),
),
const SizedBox(height: 3),
Text(
'Review the final charges and payment before generating the checkout report.',
style:
AppTheme.body(
size: 11,
color: Colors.white
    .withOpacity(.9),
),
),
],
),
),
],
),
);
}

// ================================================================
// CUSTOMER CARD
// ================================================================

Widget _buildCustomerCard() {
return Container(
padding:
const EdgeInsets.all(15),
decoration:
AppTheme.card(radius: 16),
child: Row(
children: [
Container(
width: 48,
height: 48,
decoration:
const BoxDecoration(
color:
AppColors.lightGreen,
shape:
BoxShape.circle,
),
alignment:
Alignment.center,
child: Text(
_customer!.name.isNotEmpty
? _customer!.name[0]
    .toUpperCase()
    : '?',
style:
AppTheme.heading(
size: 18,
color:
AppColors.darkGreen,
),
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
_customer!.name,
style:
AppTheme.heading(
size: 14,
),
),
const SizedBox(height: 3),
Text(
_customer!.mobileNumber,
style:
AppTheme.body(size: 11),
),
],
),
),
],
),
);
}

// ================================================================
// GOATS CARD
// ================================================================

Widget _buildGoatsCard() {
return Container(
padding:
const EdgeInsets.all(15),
decoration:
AppTheme.card(radius: 16),
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Row(
children: [
const Icon(
Icons.pets,
color:
AppColors.primaryGreen,
size: 19,
),
const SizedBox(width: 8),
Text(
'Goats Being Checked Out',
style:
AppTheme.heading(size: 14),
),
const Spacer(),
Text(
'${widget.goats.length}',
style:
AppTheme.heading(
size: 14,
color:
AppColors.primaryGreen,
),
),
],
),

const SizedBox(height: 12),

...widget.goats.map(
(draft) => Padding(
padding:
const EdgeInsets.only(
bottom: 8,
),
child: Container(
padding:
const EdgeInsets.all(10),
decoration:
BoxDecoration(
color:
AppColors.paleGreen,
borderRadius:
BorderRadius.circular(
12,
),
),
child: Row(
children: [
Container(
width: 38,
height: 38,
decoration:
const BoxDecoration(
color:
AppColors.lightGreen,
shape:
BoxShape.circle,
),
child:
const Icon(
Icons.pets,
size: 19,
color:
AppColors
    .primaryGreen,
),
),
const SizedBox(width: 10),
Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment
    .start,
children: [
Text(
draft.goat
    .goatCode,
style:
AppTheme
    .heading(
size: 12,
),
),
const SizedBox(
height: 2,
),
Text(
'${draft.goat.breed} · ${draft.goat.gender}',
style:
AppTheme.body(
size: 10,
),
),
],
),
),
Text(
'₹${draft.goat.pricing.toStringAsFixed(0)}',
style:
AppTheme.heading(
size: 11,
color:
AppColors
    .darkGreen,
),
),
],
),
),
),
),
],
),
);
}

// ================================================================
// CHARGES
// ================================================================

Widget _buildChargesCard() {
return Container(
padding:
const EdgeInsets.all(15),
decoration:
AppTheme.card(radius: 16),
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Row(
children: [
Text(
'Charges',
style:
AppTheme.heading(size: 14),
),
const Spacer(),
Container(
padding:
const EdgeInsets.symmetric(
horizontal: 8,
vertical: 4,
),
decoration:
BoxDecoration(
color:
AppColors.lightGreen,
borderRadius:
BorderRadius.circular(
8,
),
),
child: Text(
'Final Checkout',
style:
AppTheme.body(
size: 9,
color:
AppColors.darkGreen,
weight:
FontWeight.w700,
),
),
),
],
),

const SizedBox(height: 12),

_amountField(
label:
'Palai Charges',
controller:
_chargesController,
onChanged:
(_) => setState(() {}),
),

const SizedBox(height: 12),

// ----------------------------------------------------------
// CHECK-IN TRANSPORT
// ----------------------------------------------------------
//
// This is NOT editable here.
// It was captured at check-in and already recorded.
// ----------------------------------------------------------

_readOnlyAmountField(
label:
'Check-In Transport',
value:
_checkInTransportTotal,
helper:
'Already recorded at check-in',
),

const SizedBox(height: 12),

// ----------------------------------------------------------
// CHECK-OUT TRANSPORT
// ----------------------------------------------------------
//
// This is the second transport charge.
// It is optional and entered now.
// ----------------------------------------------------------

_amountField(
label:
'Check-Out Transport (Optional)',
controller:
_checkOutTransportController,
onChanged:
(_) => setState(() {}),
),

const SizedBox(height: 6),

Text(
'This is the transport charge collected when the goat leaves the farm.',
style:
AppTheme.body(
size: 9,
color:
AppColors.textGrey,
),
),

const SizedBox(height: 12),

_amountField(
label:
'Discount',
controller:
_discountController,
onChanged:
(_) => setState(() {}),
),
],
),
);
}

// ================================================================
// READ ONLY AMOUNT FIELD
// ================================================================

Widget _readOnlyAmountField({
required String label,
required double value,
String? helper,
}) {
return Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
label,
style:
AppTheme.body(
size: 11,
weight:
FontWeight.w600,
),
),
const SizedBox(height: 6),
Container(
width: double.infinity,
padding:
const EdgeInsets.symmetric(
horizontal: 14,
vertical: 14,
),
decoration:
BoxDecoration(
color:
AppColors.paleGreen,
borderRadius:
BorderRadius.circular(
12,
),
border:
Border.all(
color:
AppColors.divider,
),
),
child: Row(
children: [
Text(
'₹',
style:
AppTheme.body(
size: 13,
color:
AppColors.textGrey,
weight:
FontWeight.w600,
),
),
const SizedBox(width: 8),
Expanded(
child: Text(
value.toStringAsFixed(0),
style:
AppTheme.body(
size: 13,
color:
AppColors.textDark,
weight:
FontWeight.w600,
),
),
),
const Icon(
Icons.lock_outline,
size: 16,
color:
AppColors.textGrey,
),
],
),
),
if (helper != null) ...[
const SizedBox(height: 4),
Text(
helper,
style:
AppTheme.body(
size: 9,
color:
AppColors.textGrey,
),
),
],
],
);
}

// ================================================================
// BALANCE
// ================================================================

Widget _buildBalanceCard() {
return Container(
padding:
const EdgeInsets.all(15),
decoration:
BoxDecoration(
color:
Colors.white,
borderRadius:
BorderRadius.circular(16),
border:
Border.all(
color:
AppColors.divider,
),
),
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
'Account Summary',
style:
AppTheme.heading(size: 14),
),

const SizedBox(height: 12),

_summaryRow(
'Previous Outstanding',
_rupees(
_previousPending,
),
valueColor:
_previousPending > 0
? AppColors.error
    : AppColors.success,
),

_summaryRow(
'New Palai Charges',
_rupees(_palaiCharges),
),

_summaryRow(
'Check-In Transport',
_rupees(
_checkInTransportTotal,
),
valueColor:
AppColors.textGrey,
),

_summaryRow(
'Check-Out Transport',
_rupees(
_checkOutTransport,
),
valueColor:
AppColors.textDark,
),

_summaryRow(
'Discount',
_rupees(_discount),
valueColor:
_discount > 0
? AppColors.success
    : AppColors.textGrey,
),

_summaryRow(
'New Charges',
_rupees(_newCharges),
bold: true,
),

_summaryRow(
'Advance Available',
_rupees(
_advanceBefore,
),
valueColor:
AppColors.success,
),

_summaryRow(
'Advance Applied',
_rupees(
_advanceApplied,
),
valueColor:
AppColors.success,
),

const Divider(
height: 22,
),

_summaryRow(
'Total Due',
_rupees(_totalDue),
bold: true,
),

_summaryRow(
'Payment Received',
_rupees(_paid),
valueColor:
AppColors.success,
),

_summaryRow(
'Pending After',
_rupees(
_pendingAfter,
),
valueColor:
_pendingAfter > 0
? AppColors.error
    : AppColors.success,
bold: true,
),

if (_advanceAfter > 0)
_summaryRow(
'Advance After',
_rupees(
_advanceAfter,
),
valueColor:
AppColors.darkGreen,
bold: true,
),
],
),
);
}

// ================================================================
// PAYMENT
// ================================================================

Widget _buildPaymentCard() {
return Container(
padding:
const EdgeInsets.all(15),
decoration:
AppTheme.card(radius: 16),
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
'Payment',
style:
AppTheme.heading(size: 14),
),

const SizedBox(height: 12),

_amountField(
label:
'Amount Received',
controller:
_paidController,
onChanged:
(_) => setState(() {}),
),

const SizedBox(height: 12),

Text(
'Payment Method',
style:
AppTheme.body(
size: 11,
weight:
FontWeight.w600,
),
),

const SizedBox(height: 6),

Container(
padding:
const EdgeInsets.symmetric(
horizontal: 12,
),
decoration:
BoxDecoration(
color:
Colors.white,
borderRadius:
BorderRadius.circular(
12,
),
border:
Border.all(
color:
AppColors.divider,
),
),
child:
DropdownButtonHideUnderline(
child:
DropdownButton<String>(
value:
_paymentMethod,
isExpanded:
true,
items:
const [
DropdownMenuItem(
value:
'Cash',
child:
Text('Cash'),
),
DropdownMenuItem(
value:
'UPI',
child:
Text('UPI'),
),
DropdownMenuItem(
value:
'Bank Transfer',
child:
Text(
'Bank Transfer'),
),
DropdownMenuItem(
value:
'Cheque',
child:
Text('Cheque'),
),
DropdownMenuItem(
value:
'Other',
child:
Text('Other'),
),
],
onChanged:
(value) {
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
),
],
),
);
}

// ================================================================
// NOTE
// ================================================================

Widget _buildNoteCard() {
return Container(
padding:
const EdgeInsets.all(15),
decoration:
AppTheme.card(radius: 16),
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
'Note',
style:
AppTheme.heading(size: 14),
),

const SizedBox(height: 10),

TextField(
controller:
_noteController,
maxLines: 3,
decoration:
InputDecoration(
hintText:
'Add any checkout or payment note...',
filled:
true,
fillColor:
Colors.white,
border:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
12,
),
borderSide:
const BorderSide(
color:
AppColors.divider,
),
),
enabledBorder:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
12,
),
borderSide:
const BorderSide(
color:
AppColors.divider,
),
),
focusedBorder:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
12,
),
borderSide:
const BorderSide(
color:
AppColors
    .primaryGreen,
width: 1.5,
),
),
),
),
],
),
);
}

// ================================================================
// AMOUNT FIELD
// ================================================================

Widget _amountField({
required String label,
required TextEditingController controller,
ValueChanged<String>? onChanged,
}) {
return Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [
Text(
label,
style:
AppTheme.body(
size: 11,
weight:
FontWeight.w600,
),
),
const SizedBox(height: 6),
TextField(
controller:
controller,
keyboardType:
const TextInputType.numberWithOptions(
decimal: true,
),
onChanged:
onChanged,
decoration:
InputDecoration(
prefixText:
'₹ ',
filled:
true,
fillColor:
Colors.white,
border:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
12,
),
borderSide:
const BorderSide(
color:
AppColors.divider,
),
),
enabledBorder:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
12,
),
borderSide:
const BorderSide(
color:
AppColors.divider,
),
),
focusedBorder:
OutlineInputBorder(
borderRadius:
BorderRadius.circular(
12,
),
borderSide:
const BorderSide(
color:
AppColors
    .primaryGreen,
width: 1.5,
),
),
),
style:
AppTheme.body(
size: 13,
color:
AppColors.textDark,
),
),
],
);
}

// ================================================================
// SUMMARY ROW
// ================================================================

Widget _summaryRow(
String label,
String value, {
Color? valueColor,
bool bold = false,
}) {
return Padding(
padding:
const EdgeInsets.symmetric(
vertical: 5,
),
child: Row(
children: [
Expanded(
child: Text(
label,
style:
AppTheme.body(
size: 11,
),
),
),
Text(
value,
style:
AppTheme.body(
size: 11,
color:
valueColor ??
AppColors.textDark,
weight: bold
? FontWeight.w700
    : FontWeight.w600,
),
),
],
),
);
}

// ================================================================
// BOTTOM BAR
// ================================================================

Widget _buildBottomBar() {
return SafeArea(
child: Container(
padding:
const EdgeInsets.fromLTRB(
16,
10,
16,
12,
),
decoration:
const BoxDecoration(
color:
Colors.white,
boxShadow: [
BoxShadow(
blurRadius: 12,
offset:
Offset(0, -3),
color:
Color(0x18000000),
),
],
),
child:
Row(
children: [
Expanded(
child:
OutlinedButton(
onPressed:
_saving
? null
    : () =>
Navigator.of(
context,
).pop(),
style:
OutlinedButton.styleFrom(
foregroundColor:
AppColors
    .darkGreen,
side:
const BorderSide(
color:
AppColors.divider,
),
minimumSize:
const Size
    .fromHeight(
52,
),
shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius
    .circular(
14,
),
),
),
child:
const Text(
'Back',
),
),
),

const SizedBox(width: 10),

Expanded(
flex: 2,
child:
ElevatedButton(
onPressed:
_saving
? null
    : _completeCheckout,
style:
ElevatedButton.styleFrom(
backgroundColor:
AppColors
    .primaryGreen,
foregroundColor:
Colors.white,
minimumSize:
const Size
    .fromHeight(
52,
),
shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius
    .circular(
14,
),
),
),
child:
_saving
? const SizedBox(
width: 21,
height: 21,
child:
CircularProgressIndicator(
color:
Colors.white,
strokeWidth:
2,
),
)
    : const Text(
'Complete Checkout',
style:
TextStyle(
fontWeight:
FontWeight
    .w700,
),
),
),
),
],
),
),
);
}
}
