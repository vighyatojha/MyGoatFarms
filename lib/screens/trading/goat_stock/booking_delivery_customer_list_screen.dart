import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/booking_delivery_group.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/booking_delivery_service.dart';
import '../../../services/goat_service.dart';
import '../../../widgets/fast_route.dart';
import 'booking_delivery_customer_screen.dart';

/// Booking / Holding — customer list.
///
/// Reached from the Booked tab on the Goat Stock list. Mirrors
/// [WaitDeliveryCustomerListScreen] exactly, but groups the customer-wise
/// view around open Booking / Holding sales (via [BookingDeliveryGroup])
/// instead of Wait for Delivery ones. Tapping a customer opens
/// [BookingDeliveryCustomerScreen], where their goats can be delivered
/// one booking at a time or several at once — including the "Sell on
/// Credit" option the old single-sale-only flow didn't offer here.
class BookingDeliveryCustomerListScreen extends StatefulWidget {
  final String farmId;

  const BookingDeliveryCustomerListScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<BookingDeliveryCustomerListScreen> createState() =>
      _BookingDeliveryCustomerListScreenState();
}

class _BookingDeliveryCustomerListScreenState
    extends State<BookingDeliveryCustomerListScreen> {
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Goat>> _goatsStream =
  GoatService.instance.goatsStream(widget.farmId);

  late final Stream<List<Sale>> _salesStream =
  BookingDeliveryService.instance.openSalesStream(widget.farmId);

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCustomer(BookingDeliveryCustomer customer) async {
    await Navigator.of(context).push(
      fastRoute(
        BookingDeliveryCustomerScreen(
          farmId: widget.farmId,
          customerKey: customer.key,
          customerName: customer.name,
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: StreamBuilder<List<Goat>>(
                stream: _goatsStream,
                builder: (context, goatSnap) {
                  return StreamBuilder<List<Sale>>(
                    stream: _salesStream,
                    builder: (context, saleSnap) {
                      if (goatSnap.hasError || saleSnap.hasError) {
                        return _errorState();
                      }

                      if (!goatSnap.hasData || !saleSnap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryGreen,
                          ),
                        );
                      }

                      final customers = BookingDeliveryCustomer.group(
                        sales: saleSnap.data!,
                        goats: goatSnap.data!,
                      );

                      return _body(customers);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Back',
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Booking / Holding',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(size: 19),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BODY
  // ---------------------------------------------------------------------------

  Widget _body(List<BookingDeliveryCustomer> customers) {
    final visible = customers.where((c) => c.matches(_search)).toList();

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (customers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 1, 14, 10),
              child: _searchBox(),
            ),
          ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(hasAny: customers.isNotEmpty),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                return _customerCard(visible[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _searchBox() {
    return Container(
      height: 46,
      decoration: AppTheme.card(radius: 15).copyWith(
        border: Border.all(
          color: AppColors.divider.withOpacity(0.6),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _search = value;
          });
        },
        textInputAction: TextInputAction.search,
        style: AppTheme.body(size: 12, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'Search customer, mobile, goat or booking ID',
          hintStyle: AppTheme.body(size: 12, color: AppColors.textGrey),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.textGrey,
          ),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              _searchController.clear();
              setState(() {
                _search = '';
              });
            },
            icon: const Icon(
              Icons.close_rounded,
              size: 17,
              color: AppColors.textGrey,
            ),
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CUSTOMER CARD
  // ---------------------------------------------------------------------------

  Widget _customerCard(BookingDeliveryCustomer customer) {
    final bookingsLabel = customer.sales.length == 1
        ? '1 booking'
        : '${customer.sales.length} bookings';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCustomer(customer),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: AppTheme.card(radius: 18).copyWith(
            border: Border.all(
              color: AppColors.divider.withOpacity(0.6),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(customer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.heading(size: 15),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _goatCountPill(customer.goatCount),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      customer.mobile.isEmpty
                          ? bookingsLabel
                          : '${customer.mobile} · $bookingsLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        _infoChip(
                          Icons.calendar_month_outlined,
                          'Since '
                              '${_dateFormat.format(customer.latestBookedAt)}',
                        ),
                        _infoChip(
                          Icons.payments_outlined,
                          'Booking amount '
                              '${_money.format(customer.bookingAmountTotal)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(BookingDeliveryCustomer customer) {
    final initial = customer.name.trim().isEmpty
        ? '?'
        : customer.name.trim().substring(0, 1).toUpperCase();

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.14),
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTheme.heading(
          size: 17,
          color: AppColors.warning,
        ),
      ),
    );
  }

  Widget _goatCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(GoatIcons.paw, size: 10, color: AppColors.warning),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              color: AppColors.warning,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textGrey),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textDark,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY / ERROR
  // ---------------------------------------------------------------------------

  Widget _emptyState({required bool hasAny}) {
    final title = hasAny ? 'No matching customers' : 'No open bookings';

    final subtitle = hasAny
        ? 'Try a different name, mobile, goat or booking ID.'
        : 'Goats booked as Booking / Holding will show up here, grouped '
        'by customer.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_outline_rounded,
                size: 25,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.error,
            ),
            const SizedBox(height: 10),
            Text(
              'Unable to load Booking / Holding',
              style: AppTheme.heading(size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11),
            ),
          ],
        ),
      ),
    );
  }
}