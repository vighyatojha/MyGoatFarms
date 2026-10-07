import 'dart:typed_data';

import 'booking_delivery_group.dart';
import 'customer_account.dart';
import 'customer_credit.dart';
import 'goat_model.dart';
import 'sale_model.dart';
import 'sale_settlement.dart';
import 'wait_delivery_group.dart';

/// One goat on a sale, as shown in the purchase history. Only what the
/// customer bought: tag, photo, breed, gender, approximate age, weight and
/// the lot it came from. Never the lot's purchase cost.
class SoldGoatLine {
  final String tag;
  final String breed;
  final String gender;
  final String lotId;

  /// The goat's photo (taken at registration / on the sale).
  final Uint8List? photo;

  /// e.g. "14 months"; '' when not recorded.
  final String age;

  /// Weight on the sale (the selling / pickup weight written to the goat);
  /// 0 when not recorded.
  final double weight;

  const SoldGoatLine({
    required this.tag,
    this.breed = '',
    this.gender = '',
    this.lotId = '',
    this.photo,
    this.age = '',
    this.weight = 0,
  });
}

enum SaleStage { delivered, waiting, onHold, transferredToPalai }

enum MoneyEventKind { received, voided, adjusted }

/// One money movement on a sale: the amount taken at the sale, a later
/// payment, or extra that was kept as advance / returned.
class SaleMoneyEvent {
  final DateTime? date;
  final String label;
  final String method;
  final double amount;
  final MoneyEventKind kind;
  final String note;

  const SaleMoneyEvent({
    required this.date,
    required this.label,
    required this.amount,
    required this.kind,
    this.method = '',
    this.note = '',
  });
}

/// One goat sale, read-only. Bill figures are [Sale]'s own bill getters
/// (the sale receipt's). What is still OWED comes only from Finance: the
/// customer's [CustomerCredit] list, the same list Finance ▸ Trading ▸
/// Receivable adds up. Palai package and monthly Palai charges are never
/// part of it.
class CustomerSaleLine {
  final Sale sale;
  final List<SoldGoatLine> goats;

  /// Lots the goats came from, e.g. {LOT-0007: 3, LOT-0012: 1}.
  final Map<String, int> lots;

  /// What Finance counts as still owed on this sale. Null when Finance
  /// counts nothing (paid, not delivered, or not tracked).
  final double? financeDue;

  /// Finance's credit group this unpaid sale is in (opens the existing
  /// Credit customer screen to collect it). Null when nothing is owed.
  final String? creditKey;

  const CustomerSaleLine({
    required this.sale,
    required this.goats,
    required this.lots,
    this.financeDue,
    this.creditKey,
  });

  String get id => sale.id;
  DateTime? get date => sale.saleDate;
  DateTime? get deliveredOn => sale.isDelivered ? sale.deliveredOn : null;
  int get goatCount => sale.goatCount;

  SaleStage get stage {
    if (sale.status == Sale.statusTransferredToPalai) {
      return SaleStage.transferredToPalai;
    }
    if (sale.isDelivered) return SaleStage.delivered;
    if (sale.isWaitForDelivery) return SaleStage.waiting;
    return SaleStage.onHold;
  }

  bool get isOpen => !sale.isDelivered;

  String get stageLabel {
    switch (stage) {
      case SaleStage.delivered:
        return 'Delivered';
      case SaleStage.waiting:
        return 'Waiting pickup';
      case SaleStage.onHold:
        return 'On hold';
      case SaleStage.transferredToPalai:
        return 'Moved to Palai';
    }
  }

  String get typeLabel {
    if (sale.isDeliverNow) return 'Deliver now';
    if (sale.isBooking) return 'Booking & Holding';
    if (sale.isWaitForDelivery) return 'Wait on Delivery';
    if (sale.isPalaiTransfer) return 'Transfer to Palai';
    return sale.deliveryType;
  }

  /// "From supplier" / "From farm" for a lot sale, empty otherwise.
  String get sourceLabel {
    if (!sale.isLotSale) return '';
    if (sale.sourceLocation == Sale.sourceSupplier) return 'From supplier';
    if (sale.sourceLocation == Sale.sourceFarm) return 'From farm';
    return '';
  }

  /// Transfer to Palai saved before the goat price was asked for: nothing
  /// was recorded as owed or received.
  bool get priceNotTracked =>
      sale.isPalaiTransfer && sale.amountReceived == null;

  /// A delivered sale with a price: counted in "total bought".
  bool get countsInTotals => sale.isDelivered && !priceNotTracked;

  // Pricing --------------------------------------------------------------

  bool get isFixedPrice => sale.isFixedPrice;
  double get ratePerKg => sale.bookingPricePerKg ?? sale.sellingPricePerKg;

  /// Weight the bill was worked out on: pickup weight once picked up,
  /// otherwise the weight recorded at the sale.
  double get weight =>
      sale.pickupWeight ?? sale.bookingWeight ?? sale.sellingWeight;

  // Bill (Sale's own receipt getters) -------------------------------------

  double get goatValue => sale.billGoatSaleBeforeDiscount;
  double get discount => sale.appliedDiscount;
  double get holdingCharges => sale.billHoldingCharges;
  double get transport => sale.billTransportCharges;
  double get total => sale.billCustomerTotal;
  double get initialPayment => sale.billInitialPayment;
  String get initialPaymentLabel => sale.billInitialPaymentLabel;
  double get excessAdjusted => sale.billExcessAdjusted;
  List<SalePayment> get payments => sale.payments;

  /// Everything received against the bill (receipt figure).
  double get received => sale.billAmountPaid;

  // Owed (Finance) ---------------------------------------------------------

  /// Still owed, as Finance counts it.
  double get balance => financeDue ?? 0;
  bool get hasBalance => balance > 0;

  /// The bill maths shows money left, but the sale is saved as paid, so
  /// Finance does not count it. Shown as a note so it can be checked;
  /// never added to the pending figure.
  double get notCountedByFinance =>
      countsInTotals && financeDue == null ? sale.billBalanceDue : 0;

  /// Received more than the bill, with no extra recorded as advance or
  /// refund.
  double get overpaid {
    if (!countsInTotals) return 0;
    final over = sale.billInitialPayment +
        sale.billBalancePayments -
        sale.billExcessAdjusted -
        total;
    return over > 0.009 ? Sale.roundMoney(over) : 0;
  }

  bool get needsCheck => notCountedByFinance > 0 || overpaid > 0;

  /// Every money movement on the sale, oldest first.
  List<SaleMoneyEvent> get moneyEvents {
    final method = (sale.paymentMethod ?? '').trim();
    final events = <SaleMoneyEvent>[
      if (initialPayment > 0)
        SaleMoneyEvent(
          date: date,
          label: initialPaymentLabel,
          method: method,
          amount: initialPayment,
          kind: MoneyEventKind.received,
        ),
      for (final p in payments)
        SaleMoneyEvent(
          date: p.date,
          label: p.voided
              ? 'Payment voided'
              : p.isBookingTransfer
              ? 'Moved from another booking'
              : 'Payment received',
          method: p.method.trim(),
          amount: p.amount,
          kind: p.voided ? MoneyEventKind.voided : MoneyEventKind.received,
          note: p.isPalaiSettlement ? 'Taken at Palai counter for this sale' : '',
        ),
      if (excessAdjusted > 0)
        SaleMoneyEvent(
          date: deliveredOn,
          label: 'Extra kept as advance or returned',
          amount: excessAdjusted,
          kind: MoneyEventKind.adjusted,
        ),
    ];
    events.sort((a, b) {
      final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });
    return events;
  }

  // Open bookings (estimate, same getters as the delivery screens) --------

  /// What delivery would settle at: Wait at the booking weight, Booking if
  /// delivered on [today]. Null once delivered.
  SaleSettlement? estimate([DateTime? today]) {
    if (!isOpen) return null;
    if (sale.isWaitForDelivery) {
      return WaitDeliverySale(sale: sale, goats: const <Goat>[])
          .settlementAt(sale.bookingWeight ?? 0);
    }
    if (sale.isBooking) {
      return BookingDeliverySale(sale: sale, goats: const <Goat>[])
          .settlementAt(today ?? DateTime.now());
    }
    return null;
  }

  double dueAtDelivery([DateTime? today]) =>
      estimate(today)?.balanceDue ?? 0;

  /// A per-KG Wait booking with no booking weight can't be estimated.
  bool get estimateNeedsWeight =>
      isOpen &&
          sale.isWaitForDelivery &&
          !isFixedPrice &&
          (sale.bookingWeight ?? 0) <= 0;

  /// The customer key the Wait on Delivery / Booking & Holding customer
  /// screens are opened with (same rule as their grouping).
  String get deliveryKey => deliveryKeyOf(sale);

  static String deliveryKeyOf(Sale sale) {
    final digits = CustomerAccountBook.digitsOf(sale.mobile);
    if (digits.isNotEmpty) return 'm:$digits';
    final id = sale.customerId.trim();
    if (id.isNotEmpty) return 'c:$id';
    return 'n:${sale.customerName.trim().toLowerCase()}';
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (sale.id.toLowerCase().contains(q)) return true;
    if (lots.keys.any((l) => l.toLowerCase().contains(q))) return true;
    return goats.any((g) => g.tag.toLowerCase().contains(q));
  }
}

/// Goats bought from one lot, across all of the customer's sales.
class LotPurchaseSummary {
  final String lotId;
  final int goats;
  final int sales;

  const LotPurchaseSummary({
    required this.lotId,
    required this.goats,
    required this.sales,
  });
}

/// Purchase history filters. Delivered sales only: open bookings are on
/// the Wait on Delivery and Booking & Holding screens.
enum SalesHistoryFilter { all, unpaid, paid }

extension SalesHistoryFilterLabel on SalesHistoryFilter {
  String get label {
    switch (this) {
      case SalesHistoryFilter.all:
        return 'All';
      case SalesHistoryFilter.unpaid:
        return 'Unpaid';
      case SalesHistoryFilter.paid:
        return 'Paid';
    }
  }

  bool test(CustomerSaleLine line) {
    if (!line.sale.isDelivered) return false;
    switch (this) {
      case SalesHistoryFilter.all:
        return true;
      case SalesHistoryFilter.unpaid:
        return line.hasBalance;
      case SalesHistoryFilter.paid:
        return !line.hasBalance;
    }
  }
}

/// One line of a customer's trading account history: a bill or a money
/// movement on a delivered sale.
class AccountHistoryEntry {
  final DateTime? date;
  final String saleId;
  final String title;
  final String detail;
  final double amount;

  /// Null for a bill.
  final MoneyEventKind? kind;

  const AccountHistoryEntry({
    required this.date,
    required this.saleId,
    required this.title,
    required this.detail,
    required this.amount,
    this.kind,
  });

  bool get isBill => kind == null;
}

/// A customer's goat purchase history, newest first.
class CustomerSalesHistory {
  final List<CustomerSaleLine> lines;

  /// The account's goat sale credit (the Finance figure). Kept here so the
  /// history can say if any unpaid sale is filed under another number.
  final double financeGoatSaleCredit;

  const CustomerSalesHistory({
    required this.lines,
    required this.financeGoatSaleCredit,
  });

  static const String unknownLot = 'Lot not recorded';

  /// PUR-0007 -> LOT-0007, the same rule as TradingPurchase.lotId and
  /// Sale.lotDisplayId.
  static String lotIdFromPurchaseId(String purchaseId) {
    final id = purchaseId.trim();
    if (id.isEmpty) return unknownLot;
    final dash = id.indexOf('-');
    return dash < 0 ? id : 'LOT-${id.substring(dash + 1)}';
  }

  /// True when [sale] belongs to [account]'s person: filed under one of
  /// the person's keys, in Finance's own grouping format
  /// ([CustomerCredit.keyFor]) or the delivery screens' format.
  static bool belongsTo(Sale sale, CustomerAccount account) {
    final keys = account.saleKeys;
    if (keys.contains(CustomerCredit.keyFor(sale))) return true;
    final d = CustomerSaleLine.deliveryKeyOf(sale);
    return keys.contains(d.startsWith('c:') ? 'id:${d.substring(2)}' : d);
  }

  static CustomerSalesHistory build({
    required CustomerAccount account,
    required Iterable<Sale> sales,
    required Iterable<Goat> goats,
  }) {
    final goatById = {for (final g in goats) g.id: g};

    // Finance's figure per unpaid sale, and which credit it is filed in.
    final financeDue = <String, double>{};
    final creditKeyOf = <String, String>{};
    for (final c in account.credits) {
      for (final s in c.sales) {
        financeDue[s.id] = s.billBalanceDue;
        creditKeyOf[s.id] = c.key;
      }
    }

    final lines = <CustomerSaleLine>[];
    final seen = <String>{};

    for (final sale in sales) {
      if (!belongsTo(sale, account) || !seen.add(sale.id)) continue;

      final goatLines = <SoldGoatLine>[];
      final lots = <String, int>{};

      if (sale.isLotSale) {
        lots[sale.lotDisplayId] = sale.lotQuantity;
      } else {
        for (final goatId in sale.goatIds) {
          final goat = goatById[goatId];
          final lot = goat == null
              ? unknownLot
              : lotIdFromPurchaseId(goat.purchaseId);
          lots[lot] = (lots[lot] ?? 0) + 1;
          goatLines.add(
            SoldGoatLine(
              tag: goatId,
              breed: goat?.breed ?? '',
              gender: goat?.gender ?? '',
              lotId: lot,
              photo: goat?.photo,
              age: goat == null || goat.currentAgeMonths <= 0 ? '' : goat.age,
              weight: goat?.weight ?? 0,
            ),
          );
        }
      }

      lines.add(CustomerSaleLine(
        sale: sale,
        goats: goatLines,
        lots: lots,
        financeDue: financeDue[sale.id],
        creditKey: creditKeyOf[sale.id],
      ));
    }

    lines.sort((a, b) {
      final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return CustomerSalesHistory(
      lines: lines,
      financeGoatSaleCredit: account.goatSaleCredit,
    );
  }

  // Totals ---------------------------------------------------------------

  Iterable<CustomerSaleLine> get _delivered =>
      lines.where((l) => l.countsInTotals);
  Iterable<CustomerSaleLine> get _open => lines.where((l) => l.isOpen);

  bool get isEmpty => lines.isEmpty;

  /// Delivered sales, newest first (purchase history and ledger).
  List<CustomerSaleLine> get delivered =>
      lines.where((l) => l.sale.isDelivered).toList();

  /// Open Wait on Delivery bookings, newest first.
  List<CustomerSaleLine> get openWait =>
      lines.where((l) => l.isOpen && l.sale.isWaitForDelivery).toList();

  /// Open Booking & Holding bookings, newest first.
  List<CustomerSaleLine> get openHolding =>
      lines.where((l) => l.isOpen && l.sale.isBooking).toList();

  /// Bills and money movements on delivered sales, newest first. Palai
  /// bills and payments are never part of it.
  List<AccountHistoryEntry> get accountHistory {
    final entries = <AccountHistoryEntry>[];
    for (final l in delivered) {
      if (l.priceNotTracked) continue;
      entries.add(AccountHistoryEntry(
        date: l.deliveredOn ?? l.date,
        saleId: l.id,
        title: 'Bill · ${l.id}',
        detail: '${l.goatCount} goat${l.goatCount == 1 ? '' : 's'}'
            '${l.lots.isEmpty ? '' : ' · ${l.lots.keys.join(', ')}'}',
        amount: l.total,
      ));
      for (final e in l.moneyEvents) {
        entries.add(AccountHistoryEntry(
          date: e.date,
          saleId: l.id,
          title: e.label,
          detail: [
            l.id,
            if (e.method.isNotEmpty) e.method,
            if (e.note.isNotEmpty) e.note,
          ].join(' · '),
          amount: e.amount,
          kind: e.kind,
        ));
      }
    }
    entries.sort((a, b) {
      final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bd.compareTo(ad);
      if (byDate != 0) return byDate;
      // Same day: payment above its bill (newest first reads bottom-up).
      return (a.isBill ? 1 : 0).compareTo(b.isBill ? 1 : 0);
    });
    return entries;
  }

  /// Everything received on delivered sales (receipt figures).
  double get totalReceived => Sale.roundMoney(
      _delivered.fold(0.0, (s, l) => s + l.received));

  int get saleCount => lines.length;
  int get deliveredCount => lines.where((l) => l.sale.isDelivered).length;
  int get openCount => _open.length;
  int get unpaidCount => lines.where((l) => l.hasBalance).length;
  int get needsCheckCount => lines.where((l) => l.needsCheck).length;

  int get goatsBought =>
      lines.where((l) => l.sale.isDelivered).fold(0, (s, l) => s + l.goatCount);
  int get goatsOnOpenBookings => _open.fold(0, (s, l) => s + l.goatCount);

  /// Value of every delivered, priced sale (receipt totals).
  double get totalBought =>
      Sale.roundMoney(_delivered.fold(0.0, (s, l) => s + l.total));
  double get totalDiscount =>
      Sale.roundMoney(_delivered.fold(0.0, (s, l) => s + l.discount));

  /// Still owed on delivered sales: Finance's figure, sale by sale.
  double get pending =>
      Sale.roundMoney(lines.fold(0.0, (s, l) => s + l.balance));

  /// Still to collect on open bookings (estimate; not in Finance yet).
  double get dueAtDelivery =>
      Sale.roundMoney(_open.fold(0.0, (s, l) => s + l.dueAtDelivery()));

  /// Advance / booking amount already paid on bookings not yet delivered.
  double get advanceOnOpenBookings =>
      Sale.roundMoney(_open.fold(0.0, (s, l) => s + l.initialPayment));

  /// [pending] equals the account's Goat sale credit. True by construction;
  /// checked so a future change that breaks it is visible.
  bool get matchesFinance => (pending - financeGoatSaleCredit).abs() < 0.01;

  DateTime? get firstPurchase {
    final d = delivered;
    return d.isEmpty ? null : d.last.date;
  }

  DateTime? get lastPurchase {
    final d = delivered;
    return d.isEmpty ? null : d.first.date;
  }

  /// Weighted average rate per KG over delivered per-KG sales with a
  /// weight. Null when there are none.
  double? get averageRatePerKg {
    var value = 0.0;
    var kg = 0.0;
    for (final l in _delivered) {
      if (l.isFixedPrice || l.weight <= 0) continue;
      value += l.goatValue;
      kg += l.weight;
    }
    return kg <= 0 ? null : Sale.roundMoney(value / kg);
  }

  double get totalWeight => Sale.roundMoney(
    _delivered.fold(0.0, (s, l) => s + (l.weight > 0 ? l.weight : 0)),
  );

  /// Lots the customer has bought from (delivered), most goats first.
  List<LotPurchaseSummary> get lots {
    final goatsByLot = <String, int>{};
    final salesByLot = <String, int>{};
    for (final l in delivered) {
      l.lots.forEach((lot, n) {
        goatsByLot[lot] = (goatsByLot[lot] ?? 0) + n;
        salesByLot[lot] = (salesByLot[lot] ?? 0) + 1;
      });
    }
    final result = [
      for (final lot in goatsByLot.keys)
        LotPurchaseSummary(
          lotId: lot,
          goats: goatsByLot[lot]!,
          sales: salesByLot[lot]!,
        ),
    ];
    result.sort((a, b) {
      final byGoats = b.goats.compareTo(a.goats);
      return byGoats != 0 ? byGoats : a.lotId.compareTo(b.lotId);
    });
    return result;
  }

  int countFor(SalesHistoryFilter f) => lines.where(f.test).length;
}