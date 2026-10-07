import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../models/sale_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/wait_booking_split_service.dart';
import '../../../widgets/fast_route.dart';
import '../../trading/goat_stock/booking_delivery_customer_screen.dart';
import '../../trading/goat_stock/wait_delivery_customer_screen.dart';
import 'delivery_section.dart';

/// Wait on Delivery OR Booking & Holding → customer → goats → COMPLETE →
/// THIS SCREEN (goat checklist) → Continue → EXISTING checkout of that
/// section:
///   * Wait on Delivery  → [WaitDeliveryCustomerScreen]
///   * Booking & Holding → [BookingDeliveryCustomerScreen]
///
/// This screen does no money maths and completes nothing itself. On
/// Continue it:
///
///  1. Checks every selected booking can be used (before changing
///     anything).
///  2. For a booking where only SOME goats are ticked, uses the existing
///     [WaitBookingSplitService] (the same one behind "Edit booking") to
///     trim that booking to the ticked goats. The unticked goats move to a
///     new booking of the same kind for the same customer, with their
///     share of the advance / booking amount, so they stay where they
///     were. (For Booking & Holding the service also splits the
///     booking-day Finance entry, so money is never counted twice.)
///  3. Opens the section's existing checkout limited to the selected
///     bookings (`onlySaleIds`). Pickup weights / delivery date, holding
///     charges, previous payments, remaining balance, discount,
///     transport, credit, excess handling, bill and saving all stay
///     exactly as they are there.
///
/// Duplicate taps: Continue is locked while it runs, and the existing
/// checkout already locks its own Deliver button and re-checks every
/// booking inside the save transaction, so the same goats can never be
/// completed or paid for twice.
class CompleteGoatsSelectorScreen extends StatefulWidget {
  final String farmId;
  final DeliverySection section;
  final String customerKey;
  final String customerName;

  const CompleteGoatsSelectorScreen({
    super.key,
    required this.farmId,
    required this.section,
    required this.customerKey,
    required this.customerName,
  });

  @override
  State<CompleteGoatsSelectorScreen> createState() =>
      _CompleteGoatsSelectorScreenState();
}

class _CompleteGoatsSelectorScreenState
    extends State<CompleteGoatsSelectorScreen> {
  DeliverySection get _section => widget.section;

  /// "advance" for Wait on Delivery, "booking amount" for Booking.
  String get _paidWord => _section.isWait ? 'advance' : 'booking amount';

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  late final Stream<List<Goat>> _goats =
  GoatService.instance.goatsStream(widget.farmId);
  late final Stream<List<Sale>> _sales =
  _section.openSalesStream(widget.farmId);

  /// Ticked registered goats, by goat ID.
  final Set<String> _goatIds = <String>{};

  /// Ticked lot bookings → how many of the lot's goats to complete.
  final Map<String, int> _lotQty = <String, int>{};

  /// Latest data from the streams, used when Continue is tapped.
  SectionCustomer? _customer;

  bool _busy = false;

  // ===========================================================================
  // SELECTION
  // ===========================================================================

  /// Drops ticks for goats / lots that are no longer waiting (completed
  /// elsewhere, or edited on another device).
  void _prune(SectionCustomer customer) {
    final liveGoats = <String>{
      for (final b in customer.bookings)
        for (final g in b.goats) g.id,
    };
    _goatIds.removeWhere((id) => !liveGoats.contains(id));

    final lots = {
      for (final b in customer.bookings)
        if (b.isLot) b.id: b.goatCount,
    };
    _lotQty.removeWhere((id, _) => !lots.containsKey(id));
    _lotQty.updateAll((id, q) => q.clamp(1, lots[id]!).toInt());
  }

  int get _selectedGoatCount =>
      _goatIds.length + _lotQty.values.fold<int>(0, (a, b) => a + b);

  int _totalGoats(SectionCustomer c) => c.goatCount;

  bool _allSelected(SectionCustomer c) => _selectedGoatCount == _totalGoats(c);

  void _toggleAll(SectionCustomer c) {
    if (_busy) return;
    setState(() {
      if (_allSelected(c)) {
        _goatIds.clear();
        _lotQty.clear();
      } else {
        for (final b in c.bookings) {
          if (b.isLot) {
            _lotQty[b.id] = b.goatCount;
          } else {
            _goatIds.addAll(b.goats.map((g) => g.id));
          }
        }
      }
    });
  }

  // ===========================================================================
  // CONTINUE
  // ===========================================================================

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        backgroundColor: error ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _continue() async {
    final customer = _customer;
    if (_busy || customer == null || _selectedGoatCount == 0) return;

    setState(() => _busy = true);

    try {
      // ---- 1. Work out what each selected booking needs -----------------
      final whole = <SectionBooking>[];
      final partial = <_PartialPlan>[];

      for (final b in customer.bookings) {
        if (b.isLot) {
          final qty = _lotQty[b.id];
          if (qty == null) continue;
          if (qty >= b.goatCount) {
            whole.add(b);
          } else {
            partial.add(_PartialPlan.lot(b, qty));
          }
          continue;
        }

        final picked = b.goats.where((g) => _goatIds.contains(g.id)).toList();
        if (picked.isEmpty) continue;

        if (picked.length == b.goats.length) {
          whole.add(b);
        } else {
          partial.add(_PartialPlan.goats(b, picked));
        }
      }

      if (whole.isEmpty && partial.isEmpty) return;

      // ---- 2. Check before changing anything ----------------------------
      // A booking with payments recorded against it cannot be split (same
      // rule as Edit booking), so stop here instead of half-way through.
      final blocked = partial.where((p) => p.booking.sale.payments.isNotEmpty);
      if (blocked.isNotEmpty) {
        final ids = blocked.map((p) => p.booking.id).join(', ');
        _snack(
          'Booking $ids already has payments recorded, so its goats cannot '
              'be split. Select all goats of that booking to complete it.',
          error: true,
        );
        return;
      }

      // ---- 3. Confirm the split, then split -----------------------------
      if (partial.isNotEmpty) {
        final ok = await _confirmSplit(partial);
        if (ok != true || !mounted) return;

        for (final p in partial) {
          await WaitBookingSplitService.instance.splitBooking(
            farmId: widget.farmId,
            saleId: p.booking.id,
            deliverGoatIds: p.isLot ? null : p.goatIds,
            deliverQuantity: p.isLot ? p.quantity : null,
            leftover: LeftoverGoatsAction.keepBooked,
          );
        }
        if (!mounted) return;
      }

      // ---- 4. Existing checkout, only the selected bookings -------------
      // The split keeps the ORIGINAL booking ID on the goats being
      // completed, so these IDs are exactly the selected goats.
      final saleIds = <String>{
        ...whole.map((b) => b.id),
        ...partial.map((p) => p.booking.id),
      };

      final done = await Navigator.of(context).push<bool>(
        fastRoute(
          _section.isWait
              ? WaitDeliveryCustomerScreen(
            farmId: widget.farmId,
            customerKey: customer.key,
            customerName: customer.name,
            onlySaleIds: saleIds,
          )
              : BookingDeliveryCustomerScreen(
            farmId: widget.farmId,
            customerKey: customer.key,
            customerName: customer.name,
            onlySaleIds: saleIds,
          ),
        ),
      );

      if (!mounted) return;

      if (done == true) {
        // Everything selected was completed — back to the goat list,
        // where only the unselected goats are still waiting.
        Navigator.of(context).pop(true);
        return;
      }

      // Backed out of checkout (or only part was delivered): stay here.
      // Ticks for goats that did get delivered drop out on the next
      // update.
      setState(() {
        _goatIds.clear();
        _lotQty.clear();
      });
    } on StateError catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (e) {
      if (mounted) {
        _snack(FirestoreService.instance.describeError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmSplit(List<_PartialPlan> partial) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Complete only some goats?',
            style: AppTheme.heading(size: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These bookings have goats you did not select. The unselected '
                    'goats will stay in ${_section.title} on a new booking for '
                    'this customer, with their share of the $_paidWord.',
                style: AppTheme.body(size: 12, color: AppColors.textDark),
              ),
              const SizedBox(height: 10),
              for (final p in partial) ...[
                _splitLine(p),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// One booking's split, with the advance shared the same way the split
  /// service will save it.
  Widget _splitLine(_PartialPlan p) {
    final sale = p.booking.sale;
    final share = p.isLot
        ? WaitBookingSplitService.shareOf(
      deliverCount: p.quantity,
      totalCount: p.booking.goatCount,
    )
        : WaitBookingSplitService.shareOf(
      deliverCount: p.goatIds.length,
      totalCount: p.booking.goats.length,
      deliverWeights: [
        for (final g in p.booking.goats)
          if (p.goatIds.contains(g.id)) g.weight,
      ],
      leftoverWeights: [
        for (final g in p.booking.goats)
          if (!p.goatIds.contains(g.id)) g.weight,
      ],
    );

    final figures = WaitBookingSplitService.figures(
      sale: sale,
      share: share,
      action: LeftoverGoatsAction.keepBooked,
    );

    final now = p.isLot ? p.quantity : p.goatIds.length;
    final left = p.booking.goatCount - now;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Booking ${p.booking.id}', style: AppTheme.heading(size: 13)),
          const SizedBox(height: 2),
          Text(
            'Complete now: $now goat${now == 1 ? '' : 's'} · '
                '$_paidWord ${_money.format(figures.deliverAdvance)}'
                '${_section.isWait ? '' : ' · sale ${_money.format(figures.deliverTotal)}'}',
            style: AppTheme.body(size: 11, color: AppColors.textDark),
          ),
          Text(
            '${_section.isWait ? 'Stay waiting' : 'Stay booked'}: '
                '$left goat${left == 1 ? '' : 's'} · '
                '$_paidWord ${_money.format(figures.leftAdvance)}'
                '${_section.isWait ? '' : ' · sale ${_money.format(figures.leftTotal)}'}',
            style: AppTheme.body(size: 11, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: StreamBuilder<List<Goat>>(
        stream: _goats,
        builder: (context, goatSnap) {
          return StreamBuilder<List<Sale>>(
            stream: _sales,
            builder: (context, saleSnap) {
              Widget body;
              Widget? bottom;

              if (goatSnap.hasError || saleSnap.hasError) {
                body = const DeliveryMessage(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  title: 'Unable to load goats',
                  subtitle: 'Please check your connection and try again.',
                );
              } else if (!goatSnap.hasData || !saleSnap.hasData) {
                body = const Center(
                  child:
                  CircularProgressIndicator(color: AppColors.primaryGreen),
                );
              } else {
                SectionCustomer? customer;
                for (final c in _section.group(
                  sales: saleSnap.data!,
                  goats: goatSnap.data!,
                )) {
                  if (c.key == widget.customerKey) {
                    customer = c;
                    break;
                  }
                }

                _customer = customer;

                if (customer == null) {
                  body = DeliveryMessage(
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    title: _section.isWait
                        ? 'No goats waiting'
                        : 'No booked goats',
                    subtitle:
                    'Every goat for this customer has been delivered.',
                  );
                } else {
                  _prune(customer);
                  body = _body(customer);
                  bottom = _bottomBar();
                }
              }

              return Scaffold(
                backgroundColor: AppColors.paleGreen,
                bottomNavigationBar: bottom,
                body: SafeArea(
                  child: Column(
                    children: [
                      DeliveryHeader(
                        title: 'Select goats to complete',
                        subtitle: widget.customerName,
                        enabled: !_busy,
                      ),
                      Expanded(child: body),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(SectionCustomer customer) {
    final all = _allSelected(customer);
    final none = _selectedGoatCount == 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _toggleAll(customer),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: all ? true : (none ? false : null),
                    tristate: true,
                    activeColor: AppColors.darkGreen,
                    onChanged: _busy ? null : (_) => _toggleAll(customer),
                  ),
                  Expanded(
                    child: Text('Select all goats',
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.textDark,
                          weight: FontWeight.w600,
                        )),
                  ),
                  Text('$_selectedGoatCount of ${_totalGoats(customer)}',
                      style: AppTheme.body(size: 10.5)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < customer.bookings.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _bookingCard(customer.bookings[i]),
        ],
      ],
    );
  }

  Widget _bookingCard(SectionBooking b) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 6),
      decoration: AppTheme.card(radius: 18).copyWith(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 2),
            child: Text('Booking ${b.id}', style: AppTheme.heading(size: 13)),
          ),
          if (b.isLot) _lotTile(b) else for (final g in b.goats) _goatTile(g),
        ],
      ),
    );
  }

  Widget _goatTile(Goat goat) {
    final ticked = _goatIds.contains(goat.id);

    return CheckboxListTile(
      value: ticked,
      onChanged: _busy
          ? null
          : (v) => setState(() {
        if (v == true) {
          _goatIds.add(goat.id);
        } else {
          _goatIds.remove(goat.id);
        }
      }),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.darkGreen,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(goat.id, style: AppTheme.heading(size: 13)),
      subtitle: Text(
        goat.weight > 0
            ? '${goat.weight.toStringAsFixed(1)} kg'
            : 'Weight not recorded',
        style: AppTheme.body(size: 10.5),
      ),
      secondary: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: goat.photo != null
            ? Image.memory(goat.photo!, width: 36, height: 36, fit: BoxFit.cover)
            : Container(
          width: 36,
          height: 36,
          color: _section.color.withValues(alpha: 0.12),
          child: Icon(GoatIcons.paw, size: 16, color: _section.color),
        ),
      ),
    );
  }

  Widget _lotTile(SectionBooking b) {
    final qty = _lotQty[b.id];
    final ticked = qty != null;

    return Column(
      children: [
        CheckboxListTile(
          value: ticked,
          onChanged: _busy
              ? null
              : (v) => setState(() {
            if (v == true) {
              _lotQty[b.id] = b.goatCount;
            } else {
              _lotQty.remove(b.id);
            }
          }),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.darkGreen,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(b.sale.lotDisplayId, style: AppTheme.heading(size: 13)),
          subtitle: Text(
            '${b.goatCount} goat${b.goatCount == 1 ? '' : 's'} from a lot',
            style: AppTheme.body(size: 10.5),
          ),
        ),
        if (qty != null && b.goatCount > 1)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('How many to complete now',
                      style: AppTheme.body(size: 11, color: AppColors.textDark)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy || qty <= 1
                      ? null
                      : () => setState(() => _lotQty[b.id] = qty - 1),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                ),
                Text('$qty', style: AppTheme.heading(size: 14)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy || qty >= b.goatCount
                      ? null
                      : () => setState(() => _lotQty[b.id] = qty + 1),
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bottomBar() {
    final count = _selectedGoatCount;
    final enabled = count > 0 && !_busy;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: const BoxDecoration(
          color: AppColors.paleGreen,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: enabled ? _continue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.divider,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _busy
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
                : Text(
              count == 0
                  ? 'Select goats to continue'
                  : 'Continue with $count goat${count == 1 ? '' : 's'}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selected booking where only some of its goats are being completed.
class _PartialPlan {
  final SectionBooking booking;
  final Set<String> goatIds;
  final int quantity;

  bool get isLot => booking.isLot;

  _PartialPlan.goats(this.booking, List<Goat> picked)
      : goatIds = picked.map((g) => g.id).toSet(),
        quantity = picked.length;

  _PartialPlan.lot(this.booking, this.quantity) : goatIds = const <String>{};
}