import 'customer_credit.dart';
import 'customer_model.dart';
import 'palai_models.dart';
import 'sale_model.dart';

/// One open Wait on Delivery or Booking & Holding group, reduced to what
/// the customer screens need. Built from [WaitDeliveryCustomer] /
/// [BookingDeliveryCustomer] by CustomerAccountService, so the counts and
/// estimates are the ones those existing screens show.
class DeliveryGroupSummary {
  /// The group key the existing screen is opened with (customerKey).
  final String key;
  final String name;
  final String mobile;
  final String address;
  final int goatCount;
  final int bookingCount;

  /// Still expected at pickup / delivery. An estimate: never part of the
  /// trading balance or of any Finance figure.
  final double estimate;

  const DeliveryGroupSummary({
    required this.key,
    required this.name,
    required this.goatCount,
    required this.bookingCount,
    required this.estimate,
    this.mobile = '',
    this.address = '',
  });

  /// The person key: delivery screens write "c:<id>" where Finance's
  /// grouping writes "id:<id>" for the same customer record.
  String get personKey =>
      key.startsWith('c:') ? 'id:${key.substring(2)}' : key;
}

/// One PERSON's trading account. A person is everyone who shares a mobile
/// number (last 10 digits): their Palai records, their Trading customer
/// records, their goat-sale credit and their open bookings, merged into
/// one row so nobody is missing and nothing is counted twice.
///
/// Trading money only. Palai bills, Palai payments and Palai advance are
/// never part of it.
///   Goat sale pending  Finance's Goat sale credit (delivered, unpaid)
///   Goat sale advance  customers.advanceBalance (extra paid on sales)
///   Due at delivery    open Wait / Booking estimates (not in Finance yet)
class CustomerAccount {
  /// "m:<10 digits>" when there is a mobile number. Without one:
  /// "id:<trading id>", "p:<palai id>" or "n:<name>".
  final String key;
  final String name;
  final String mobile;
  final String address;

  final List<PalaiCustomer> palaiCustomers;
  final List<Customer> tradingCustomers;
  final List<CustomerCredit> credits;
  final List<DeliveryGroupSummary> waitGroups;
  final List<DeliveryGroupSummary> bookingGroups;
  final int palaiGoats;

  const CustomerAccount({
    required this.key,
    required this.name,
    this.mobile = '',
    this.address = '',
    this.palaiCustomers = const [],
    this.tradingCustomers = const [],
    this.credits = const [],
    this.waitGroups = const [],
    this.bookingGroups = const [],
    this.palaiGoats = 0,
  });

  String get id => key;

  bool get hasMobile => CustomerAccountBook.digitsOf(mobile).isNotEmpty;
  bool get isPalaiCustomer => palaiCustomers.isNotEmpty;

  /// The Palai record shown in the header (the oldest one).
  PalaiCustomer? get palai =>
      palaiCustomers.isEmpty ? null : palaiCustomers.first;

  CustomerCredit? get credit => credits.isEmpty ? null : credits.first;
  DeliveryGroupSummary? get wait => waitGroups.isEmpty ? null : waitGroups.first;
  DeliveryGroupSummary? get booking =>
      bookingGroups.isEmpty ? null : bookingGroups.first;

  /// Every key this person's sales can be filed under, in Finance's format.
  Set<String> get saleKeys => {
    key,
    for (final c in credits) c.key,
    for (final g in waitGroups) g.personKey,
    for (final g in bookingGroups) g.personKey,
  };

  /// Delivered goat sales still unpaid: Finance's Goat sale credit.
  double get goatSaleCredit =>
      Sale.roundMoney(credits.fold(0.0, (s, c) => s + c.totalDue));

  /// Extra paid on sales and kept as advance (Trading customer records).
  double get goatSaleAdvance => Sale.roundMoney(
      tradingCustomers.fold(0.0, (s, t) => s + t.advanceBalance));

  int get waitGoats => waitGroups.fold(0, (s, g) => s + g.goatCount);
  int get holdingGoats => bookingGroups.fold(0, (s, g) => s + g.goatCount);
  int get goatsWithFarm => waitGoats + holdingGoats + palaiGoats;

  double get waitDue =>
      Sale.roundMoney(waitGroups.fold(0.0, (s, g) => s + g.estimate));
  double get holdingDue =>
      Sale.roundMoney(bookingGroups.fold(0.0, (s, g) => s + g.estimate));
  double get dueAtDelivery => Sale.roundMoney(waitDue + holdingDue);

  /// Trading balance. Positive: customer owes. Negative: farm owes them.
  double get net => Sale.roundMoney(goatSaleCredit - goatSaleAdvance);

  bool get owes => net > 0;

  /// Anything still to collect on trading: delivered or at delivery.
  bool get hasPending => goatSaleCredit > 0 || dueAtDelivery > 0;
  bool get hasAdvance => goatSaleAdvance > 0;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty &&
        mobile.replaceAll(RegExp(r'\D'), '').contains(digits);
  }
}

enum CustomerFilter { all, wait, holding, palai, pending, advance }

extension CustomerFilterLabel on CustomerFilter {
  String get label {
    switch (this) {
      case CustomerFilter.all:
        return 'All';
      case CustomerFilter.wait:
        return 'Wait on Delivery';
      case CustomerFilter.holding:
        return 'Booking & Holding';
      case CustomerFilter.palai:
        return 'Palai boarding';
      case CustomerFilter.pending:
        return 'Pending';
      case CustomerFilter.advance:
        return 'Sale advance';
    }
  }

  bool test(CustomerAccount a) {
    switch (this) {
      case CustomerFilter.all:
        return true;
      case CustomerFilter.wait:
        return a.waitGoats > 0;
      case CustomerFilter.holding:
        return a.holdingGoats > 0;
      case CustomerFilter.palai:
        return a.palaiGoats > 0;
      case CustomerFilter.pending:
        return a.hasPending;
      case CustomerFilter.advance:
        return a.hasAdvance;
    }
  }
}

/// Every customer (Palai or trading) as one account each.
class CustomerAccountBook {
  final List<CustomerAccount> accounts;

  /// Every goat-sale credit: what Finance ▸ Trading ▸ Receivable adds up.
  final double allGoatSaleCredit;

  const CustomerAccountBook({
    required this.accounts,
    required this.allGoatSaleCredit,
  });

  static const CustomerAccountBook empty =
  CustomerAccountBook(accounts: <CustomerAccount>[], allGoatSaleCredit: 0);

  /// Sum of every person's sale pending. Every credit belongs to exactly
  /// one person, so this equals [allGoatSaleCredit].
  double get totalSalePending =>
      Sale.roundMoney(accounts.fold(0.0, (s, a) => s + a.goatSaleCredit));

  double get totalDueAtDelivery =>
      Sale.roundMoney(accounts.fold(0.0, (s, a) => s + a.dueAtDelivery));

  int get goatsWithFarm => accounts.fold(0, (s, a) => s + a.goatsWithFarm);

  bool get isReconciled =>
      (totalSalePending - allGoatSaleCredit).abs() < 0.01;

  CustomerAccount? byId(String key) {
    for (final a in accounts) {
      if (a.key == key) return a;
    }
    return null;
  }

  int countFor(CustomerFilter filter) => accounts.where(filter.test).length;

  /// Last 10 digits, same rule as [CustomerCredit.keyFromParts].
  static String digitsOf(String mobile) {
    var digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    return digits;
  }

  static CustomerAccountBook build({
    required List<PalaiCustomer> palaiCustomers,
    required List<CustomerCredit> credits,
    required List<Customer> tradingCustomers,
    List<DeliveryGroupSummary> waitGroups = const [],
    List<DeliveryGroupSummary> bookingGroups = const [],
    Map<String, int> activePalaiGoats = const {},
  }) {
    final people = <String, _Draft>{};
    _Draft at(String key) => people.putIfAbsent(key, () => _Draft(key));

    // Trading customer id -> person key, so an "id:<x>" credit or a
    // "c:<x>" booking lands on the person who owns record x.
    final keyOfTradingId = <String, String>{};

    final palaiSorted = [...palaiCustomers]
      ..sort((a, b) => a.joiningDate.compareTo(b.joiningDate));
    for (final p in palaiSorted) {
      final d = digitsOf(p.mobileNumber);
      at(d.isNotEmpty ? 'm:$d' : 'p:${p.id}').palai.add(p);
    }

    for (final t in tradingCustomers) {
      final d = digitsOf(t.mobile);
      final key = d.isNotEmpty ? 'm:$d' : 'id:${t.id}';
      at(key).trading.add(t);
      keyOfTradingId[t.id] = key;
    }

    String resolve(String key) {
      if (key.startsWith('id:')) {
        return keyOfTradingId[key.substring(3)] ?? key;
      }
      return key;
    }

    for (final c in credits) {
      at(resolve(c.key)).credits.add(c);
    }
    for (final g in waitGroups) {
      at(resolve(g.personKey)).wait.add(g);
    }
    for (final g in bookingGroups) {
      at(resolve(g.personKey)).booking.add(g);
    }

    final accounts = people.values.map((d) => d.build(activePalaiGoats)).toList()
      ..sort((a, b) {
        final byNet = b.net.compareTo(a.net);
        if (byNet != 0) return byNet;
        final byDue = b.dueAtDelivery.compareTo(a.dueAtDelivery);
        if (byDue != 0) return byDue;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return CustomerAccountBook(
      accounts: accounts,
      allGoatSaleCredit: CustomerCredit.totalOf(credits),
    );
  }
}

class _Draft {
  _Draft(this.key);

  final String key;
  final List<PalaiCustomer> palai = [];
  final List<Customer> trading = [];
  final List<CustomerCredit> credits = [];
  final List<DeliveryGroupSummary> wait = [];
  final List<DeliveryGroupSummary> booking = [];

  CustomerAccount build(Map<String, int> activePalaiGoats) {
    String pick(Iterable<String> values) => values
        .map((v) => v.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    final name = pick([
      ...palai.map((p) => p.name),
      ...trading.map((t) => t.name),
      ...credits.map((c) => c.name),
      ...wait.map((g) => g.name),
      ...booking.map((g) => g.name),
    ]);
    final mobile = pick([
      ...palai.map((p) => p.mobileNumber),
      ...trading.map((t) => t.mobile),
      ...credits.map((c) => c.mobile),
      ...wait.map((g) => g.mobile),
      ...booking.map((g) => g.mobile),
    ]);
    final address = pick([
      ...palai.map((p) => p.address),
      ...trading.map((t) => t.address),
      ...credits.map((c) => c.address),
      ...wait.map((g) => g.address),
      ...booking.map((g) => g.address),
    ]);

    return CustomerAccount(
      key: key,
      name: name.isEmpty ? 'Unnamed customer' : name,
      mobile: mobile,
      address: address,
      palaiCustomers: List.unmodifiable(palai),
      tradingCustomers: List.unmodifiable(trading),
      credits: List.unmodifiable(credits),
      waitGroups: List.unmodifiable(wait),
      bookingGroups: List.unmodifiable(booking),
      palaiGoats: palai.fold(0, (s, p) => s + (activePalaiGoats[p.id] ?? 0)),
    );
  }
}