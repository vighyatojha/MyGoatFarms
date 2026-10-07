import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_theme.dart';
import '../../../models/customer_account.dart';
import '../../../models/customer_sales_history.dart';
import '../../../models/palai_models.dart';
import '../../../services/customer_account_service.dart';
import '../../../services/payment_reminder_service.dart';
import '../../../widgets/fast_route.dart';
import '../../finance/credit_customer_detail_screen.dart';
import '../../home/delivery_flow/delivery_customer_goats_screen.dart';
import '../../home/delivery_flow/delivery_section.dart';
import '../customer_profile_screen.dart';
import 'customer_sales_history_screen.dart';
import 'customer_trading_ledger_screen.dart';
import 'hub_widgets.dart';
import 'sale_money_widgets.dart';

/// One customer's page in the Customer hub. Kept short: who they are,
/// their trading balance, and one named entry per thing, each opening its
/// own screen:
///
///   Wait on Delivery   → this customer's goats waiting for delivery
///                        ([DeliveryCustomerGoatsScreen]: goat details,
///                        updates, Complete → checkout)
///   Booking & Holding  → this customer's booked / held goats
///                        ([DeliveryCustomerGoatsScreen])
///   Purchase history   → only delivered purchases (lots, pricing, goats)
///   Trading ledger     → only bills, payments and what is pending
///   Palai profile      → the existing Palai screen
///
/// Read-only. It never writes money.
class CustomerHubProfileScreen extends StatefulWidget {
  const CustomerHubProfileScreen({
    super.key,
    required this.farmId,
    required this.personKey,
    this.initialName = '',
  });

  final String farmId;

  /// [CustomerAccount.key] of the person to show.
  final String personKey;

  /// Shown in the title while the account loads.
  final String initialName;

  @override
  State<CustomerHubProfileScreen> createState() => _CustomerHubProfileScreenState();
}

class _CustomerHubProfileScreenState extends State<CustomerHubProfileScreen> {
  late final Stream<CustomerProfileData> _data = CustomerAccountService.instance
      .profileStream(widget.farmId, widget.personKey);

  void _push(Widget screen) => Navigator.of(context).push(fastRoute(screen));

  /// This customer's Wait on Delivery goats.
  Future<void> _openWait(CustomerAccount a) =>
      _openGoats(a, DeliverySection.waitOnDelivery, a.waitGroups);

  /// This customer's Booking & Holding goats.
  Future<void> _openHolding(CustomerAccount a) =>
      _openGoats(a, DeliverySection.bookingHolding, a.bookingGroups);

  /// Opens the goat list of one of [groups] for [section]. A person whose
  /// bookings were saved under more than one name has more than one
  /// group: they choose which one, so none of their goats is hidden.
  Future<void> _openGoats(
      CustomerAccount a,
      DeliverySection section,
      List<DeliveryGroupSummary> groups,
      ) async {
    if (groups.isEmpty) return;

    final group = groups.length == 1
        ? groups.single
        : await _pickGroup(section, groups);
    if (group == null || !mounted) return;

    _push(DeliveryCustomerGoatsScreen(
      farmId: widget.farmId,
      section: section,
      customerKey: group.key,
      customerName: group.name.trim().isEmpty ? a.name : group.name,
    ));
  }

  Future<DeliveryGroupSummary?> _pickGroup(
      DeliverySection section,
      List<DeliveryGroupSummary> groups,
      ) {
    String goats(int n) => n == 1 ? '1 goat' : '$n goats';
    String bookings(int n) => n == 1 ? '1 booking' : '$n bookings';

    return showModalBottomSheet<DeliveryGroupSummary>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(section.title, style: AppTheme.heading(size: 16)),
            ),
            for (final g in groups)
              ListTile(
                leading: HubIconBox(icon: section.icon, color: section.color),
                title: Text(
                  g.name.trim().isEmpty ? 'Customer' : g.name,
                  style: AppTheme.heading(size: 13.5),
                ),
                subtitle: Text(
                  '${goats(g.goatCount)} · ${bookings(g.bookingCount)}',
                  style: AppTheme.body(size: 11),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textGrey,
                ),
                onTap: () => Navigator.of(sheetContext).pop(g),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openHistory(CustomerAccount a) {
    _push(CustomerSalesHistoryScreen(
      farmId: widget.farmId,
      personKey: a.key,
      customerName: a.name,
    ));
  }

  void _openLedger(CustomerAccount a) {
    _push(CustomerTradingLedgerScreen(
      farmId: widget.farmId,
      personKey: a.key,
      customerName: a.name,
    ));
  }

  void _openPalai(PalaiCustomer palai) {
    _push(CustomerProfileScreen(customer: palai, farmId: widget.farmId));
  }

  /// Collect a delivered sale's balance. One Finance credit group: its
  /// existing collect screen. More than one: the ledger, where each unpaid
  /// sale has its own Collect button.
  void _collect(CustomerAccount a) {
    if (a.credits.length == 1) {
      _push(CreditCustomerDetailScreen(
        farmId: widget.farmId,
        creditKey: a.credits.single.key,
        customerName: a.name,
      ));
    } else {
      _openLedger(a);
    }
  }

  Future<void> _call(String mobile) async {
    final digits = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (_) {
      _snack("Couldn't start the call.");
    }
  }

  Future<void> _remind(CustomerAccount a) async {
    final reminders = PaymentReminderService.instance;
    final days = await reminders.loadDays();
    final ok = await reminders.openWhatsApp(
      mobile: a.mobile,
      message: reminders.buildMessage(
        customerName: a.name,
        pendingAmount: a.goatSaleCredit,
        days: days,
      ),
    );
    if (!ok) _snack("Couldn't open WhatsApp. Check the mobile number.");
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CustomerProfileData>(
      stream: _data,
      builder: (context, snap) {
        final a = snap.data?.account;
        final title = a?.name ?? (widget.initialName.isEmpty ? 'Customer' : widget.initialName);

        return Scaffold(
          backgroundColor: AppColors.paleGreen,
          body: SafeArea(
            child: Column(
              children: [
                HubTopBar(title: title, trailing: a == null ? null : _menu(a)),
                Expanded(
                  child: snap.hasError
                      ? const HubMessage(
                    icon: Icons.cloud_off_outlined,
                    title: "Couldn't load this customer",
                    subtitle: 'Check your connection and open this screen again.',
                  )
                      : !snap.hasData
                      ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen),
                  )
                      : a == null
                      ? const HubMessage(
                    icon: Icons.person_off_outlined,
                    title: 'Customer not found',
                    subtitle: 'This customer may have been deleted.',
                  )
                      : _content(a, snap.data!.history),
                ),
              ],
            ),
          ),
          bottomNavigationBar:
          a != null && a.goatSaleCredit > 0 ? _bottomBar(a) : null,
        );
      },
    );
  }

  Widget? _menu(CustomerAccount a) {
    if (!a.hasMobile) return null;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) {
        if (v == 'call') unawaited(_call(a.mobile));
        if (v == 'remind') unawaited(_remind(a));
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'call', child: Text('Call')),
        if (a.goatSaleCredit > 0)
          const PopupMenuItem(value: 'remind', child: Text('Send WhatsApp reminder')),
      ],
    );
  }

  Widget _content(CustomerAccount a, CustomerSalesHistory? h) {
    final delivered = h?.delivered ?? const <CustomerSaleLine>[];
    final waitCount = h?.openWait.length ?? 0;
    final holdCount = h?.openHolding.length ?? 0;

    String bookings(int n) => n == 1 ? '1 booking' : '$n bookings';
    String goats(int n) => n == 1 ? '1 goat' : '$n goats';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _identity(a),
        const SizedBox(height: 12),
        _balance(a),

        const HubSection('Open bookings'),
        _Group(children: [
          _Entry(
            icon: Icons.local_shipping_outlined,
            color: HubColors.wait,
            title: 'Wait on Delivery',
            subtitle: waitCount == 0
                ? 'No goats waiting for pickup'
                : '${goats(a.waitGoats)} · ${bookings(waitCount)}',
            value: waitCount == 0 ? null : hubMoney(a.waitDue),
            valueNote: waitCount == 0 ? null : 'due (est.)',
            onTap: a.waitGroups.isEmpty ? null : () => unawaited(_openWait(a)),
          ),
          _Entry(
            icon: Icons.event_available_outlined,
            color: HubColors.holding,
            title: 'Booking & Holding',
            subtitle: holdCount == 0
                ? 'No goats on hold'
                : '${goats(a.holdingGoats)} · ${bookings(holdCount)}',
            value: holdCount == 0 ? null : hubMoney(a.holdingDue),
            valueNote: holdCount == 0 ? null : 'due today (est.)',
            onTap: a.bookingGroups.isEmpty
                ? null
                : () => unawaited(_openHolding(a)),
          ),
        ]),

        const HubSection('Sales and money'),
        _Group(children: [
          _Entry(
            icon: Icons.shopping_bag_outlined,
            color: AppColors.tradingBlue,
            title: 'Purchase history',
            subtitle: delivered.isEmpty
                ? 'No delivered purchases yet'
                : '${delivered.length} delivered · last ${saleDay(h!.lastPurchase)}',
            onTap: delivered.isEmpty ? null : () => _openHistory(a),
          ),
          _Entry(
            icon: Icons.receipt_long_outlined,
            color: AppColors.info,
            title: 'Trading ledger',
            subtitle: 'Bills, payments and pending',
            value: a.goatSaleCredit > 0 ? hubMoney(a.goatSaleCredit) : 'Paid up',
            valueColor: a.goatSaleCredit > 0 ? HubColors.owes : AppColors.success,
            onTap: () => _openLedger(a),
          ),
        ]),

        if (a.isPalaiCustomer) ...[
          const HubSection('Palai boarding'),
          _Group(children: [
            for (final p in a.palaiCustomers)
              _Entry(
                icon: Icons.home_work_outlined,
                color: HubColors.palai,
                title: a.palaiCustomers.length > 1 ? 'Palai profile · ${p.name}' : 'Palai profile',
                subtitle: '${p.package.trim().isEmpty ? 'Palai' : p.package}'
                    ' · since ${saleDay(p.joiningDate)}',
                onTap: () => _openPalai(p),
              ),
          ]),
          if (a.palaiCustomers.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'This mobile number is saved on ${a.palaiCustomers.length} Palai records.',
                style: AppTheme.body(size: 10.5, color: AppColors.warning),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------

  Widget _identity(CustomerAccount a) {
    final palai = a.palai;
    return HubCard(
      child: Row(
        children: [
          HubAvatar(name: a.name, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: AppTheme.heading(size: 17)),
                if (a.hasMobile)
                  InkWell(
                    onTap: () => unawaited(_call(a.mobile)),
                    child: Text(
                      a.mobile,
                      style: AppTheme.body(
                          size: 12.5, color: AppColors.info, weight: FontWeight.w500),
                    ),
                  )
                else
                  Text('No mobile saved', style: AppTheme.body(size: 12)),
                if (a.address.trim().isNotEmpty)
                  Text(a.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 11.5)),
                const SizedBox(height: 6),
                HubPill(
                  palai != null ? 'Palai customer' : 'Goat buyer',
                  palai != null ? HubColors.palai : AppColors.textGrey,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _balance(CustomerAccount a) {
    return HubCard(
      onTap: () => _openLedger(a),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trading balance', style: AppTheme.body(size: 11.5)),
          const SizedBox(height: 4),
          HubNetText(net: a.net, big: true),
          const Divider(height: 22, color: AppColors.divider),
          Row(
            children: [
              HubFact('Pending on sales', hubMoney(a.goatSaleCredit),
                  color: a.goatSaleCredit > 0 ? HubColors.owes : null),
              HubFact('Advance held', hubMoney(a.goatSaleAdvance),
                  color: a.goatSaleAdvance > 0 ? AppColors.success : null),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Delivered goat sales only, same as Finance. Palai bills are not included.',
            style: AppTheme.body(size: 10),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(CustomerAccount a) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _collect(a),
            icon: const Icon(Icons.payments_outlined, size: 20),
            label: Text(
              'Collect ${hubMoney(a.goatSaleCredit)}',
              style: AppTheme.heading(size: 15, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PIECES
// =============================================================================

/// White card holding entries separated by thin dividers.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppTheme.card(radius: 16),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 12, endIndent: 12, color: AppColors.divider),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One named entry that opens its own screen. Greyed out when empty.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.value,
    this.valueNote,
    this.valueColor,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? value;
  final String? valueNote;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              HubIconBox(icon: icon, color: enabled ? color : AppColors.textGrey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.heading(size: 13.5)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 11)),
                  ],
                ),
              ),
              if (value != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value!,
                        style: AppTheme.heading(
                            size: 13.5, color: valueColor ?? HubColors.estimate)),
                    if (valueNote != null)
                      Text(valueNote!, style: AppTheme.body(size: 9.5)),
                  ],
                ),
              const SizedBox(width: 4),
              if (enabled)
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textGrey),
            ],
          ),
        ),
      ),
    );
  }
}