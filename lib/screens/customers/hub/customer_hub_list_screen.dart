import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/customer_account.dart';
import '../../../services/customer_account_service.dart';
import '../../../services/payment_reminder_service.dart';
import '../../../widgets/fast_route.dart';
import '../../finance/credit_customers_screen.dart';
import 'customer_hub_profile_screen.dart';
import 'hub_widgets.dart';

/// Customers, opened from the Trading dashboard: every person the farm
/// trades with (Palai customers and goat buyers), one row per mobile
/// number.
///
/// Trading money only (no Palai bills or payments). Read-only. Totals come
/// from [CustomerAccountBook], the same calculation the account screen
/// uses: total sale pending = Finance ▸ Trading ▸ Receivable. Due at
/// delivery is an estimate for open bookings and is not in Finance until
/// the goats are delivered.
class CustomerHubListScreen extends StatefulWidget {
  const CustomerHubListScreen({
    super.key,
    required this.farmId,
    this.initialFilter = CustomerFilter.all,
  });

  final String farmId;
  final CustomerFilter initialFilter;

  @override
  State<CustomerHubListScreen> createState() => _CustomerHubListScreenState();
}

class _CustomerHubListScreenState extends State<CustomerHubListScreen> {
  late final Stream<CustomerAccountBook> _book =
  CustomerAccountService.instance.bookStream(widget.farmId);

  final TextEditingController _search = TextEditingController();
  late CustomerFilter _filter = widget.initialFilter;
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  void _open(CustomerAccount account) {
    Navigator.of(context).push(
      fastRoute(
        CustomerHubProfileScreen(
          farmId: widget.farmId,
          personKey: account.key,
          initialName: account.name,
        ),
      ),
    );
  }

  void _openFinanceCredit() {
    Navigator.of(context).push(
      fastRoute(CreditCustomersScreen(farmId: widget.farmId)),
    );
  }

  Future<void> _remind(CustomerAccount account) async {
    final reminders = PaymentReminderService.instance;
    final days = await reminders.loadDays();
    final ok = await reminders.openWhatsApp(
      mobile: account.mobile,
      message: reminders.buildMessage(
        customerName: account.name,
        pendingAmount: account.goatSaleCredit,
        days: days,
      ),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't open WhatsApp. Check the mobile number."),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _header(),
            ),
            Expanded(
              child: StreamBuilder<CustomerAccountBook>(
                stream: _book,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return HubMessage(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load customers",
                      subtitle: 'Check your connection and open this screen again.',
                    );
                  }
                  if (!snap.hasData) return const _ListSkeleton();
                  return _body(snap.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        HubHeaderButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _searching
              ? TextField(
            controller: _search,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Name or mobile',
              isDense: true,
              contentPadding:
              EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          )
              : Row(
            children: [
              const HubIconBox(
                icon: Icons.groups_2_outlined,
                color: HubColors.customers,
                size: 38,
              ),
              const SizedBox(width: 10),
              Text('Customers', style: AppTheme.heading(size: 20)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        HubHeaderButton(
          icon: _searching ? Icons.close_rounded : Icons.search_rounded,
          tooltip: _searching ? 'Close search' : 'Search',
          onTap: _toggleSearch,
        ),
      ],
    );
  }

  Widget _body(CustomerAccountBook book) {
    final visible = book.accounts
        .where(_filter.test)
        .where((a) => a.matches(_query))
        .toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        _summary(book),
        const SizedBox(height: 14),
        _chips(book),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          HubMessage(
            icon: Icons.person_search_outlined,
            title: _query.isNotEmpty
                ? 'No customer matches "${_query.trim()}"'
                : 'No customers in this filter',
            action: _filter == CustomerFilter.all && _query.isEmpty
                ? null
                : TextButton(
              onPressed: () => setState(() {
                _filter = CustomerFilter.all;
                _search.clear();
                _query = '';
              }),
              child: const Text('Show all'),
            ),
          )
        else
          for (final account in visible) ...[
            _CustomerRow(
              account: account,
              onTap: () => _open(account),
              onRemind: () => unawaited(_remind(account)),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------

  Widget _summary(CustomerAccountBook book) {
    const divider = Divider(height: 20, color: AppColors.divider);

    return HubCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Customers',
                  value: '${book.accounts.length}',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Goats with farm',
                  value: '${book.goatsWithFarm}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Sale pending',
                  value: hubMoney(book.totalSalePending),
                  color: book.totalSalePending > 0
                      ? HubColors.owes
                      : AppColors.textDark,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Due on open bookings (est.)',
                  value: hubMoney(book.totalDueAtDelivery),
                  color: book.totalDueAtDelivery > 0
                      ? HubColors.estimate
                      : AppColors.textDark,
                ),
              ),
            ],
          ),
          divider,
          _SummaryLine(
            label: 'Trading receivable in Finance',
            value: hubMoney(book.allGoatSaleCredit),
            trailing: book.isReconciled
                ? const HubPill('Matches', AppColors.success)
                : const HubPill('Check', AppColors.warning),
            onTap: _openFinanceCredit,
          ),
          if (!book.isReconciled)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Sale pending doesn't match Finance. Don't take payments from here until this is fixed.",
                      style: AppTheme.body(size: 10, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTER CHIPS
  // ---------------------------------------------------------------------------

  Widget _chips(CustomerAccountBook book) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: CustomerFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = CustomerFilter.values[i];
          final selected = filter == _filter;
          return Material(
            color: selected ? AppColors.primaryGreen : Colors.white,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? AppColors.primaryGreen : AppColors.divider,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _filter = filter),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    '${filter.label}  ${book.countFor(filter)}',
                    style: AppTheme.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// ROW
// =============================================================================

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.account,
    required this.onTap,
    required this.onRemind,
  });

  final CustomerAccount account;
  final VoidCallback onTap;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[
      if (account.waitGoats > 0) HubPill('Wait ${account.waitGoats}', HubColors.wait),
      if (account.holdingGoats > 0)
        HubPill('Holding ${account.holdingGoats}', HubColors.holding),
      if (account.palaiGoats > 0) HubPill('Palai ${account.palaiGoats}', HubColors.palai),
    ];

    return HubCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          HubAvatar(name: account.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 14),
                ),
                Text(
                  account.mobile.trim().isEmpty ? 'No mobile' : account.mobile,
                  maxLines: 1,
                  style: AppTheme.body(size: 11),
                ),
                if (pills.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: pills),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              HubNetText(net: account.net),
              if (account.owes && account.hasMobile) ...[
                const SizedBox(height: 6),
                Tooltip(
                  message: 'Send WhatsApp reminder',
                  child: InkResponse(
                    onTap: onRemind,
                    radius: 22,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chat_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SMALL PIECES
// =============================================================================

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.color = AppColors.textDark,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(size: 11)),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, style: AppTheme.heading(size: 19, color: color)),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTheme.body(size: 12)),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
            Text(value, style: AppTheme.heading(size: 13)),
            SizedBox(
              width: 22,
              child: onTap == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        HubBone(height: 170),
        SizedBox(height: 14),
        HubBone(height: 34, radius: 20),
        SizedBox(height: 12),
        HubBone(height: 78),
        SizedBox(height: 10),
        HubBone(height: 78),
        SizedBox(height: 10),
        HubBone(height: 78),
      ],
    );
  }
}