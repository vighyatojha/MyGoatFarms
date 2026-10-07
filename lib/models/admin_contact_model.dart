/// The admin's name and contact details, shown to a farm owner while their
/// registration is awaiting approval, rejected or blocked (see
/// [FarmApprovalPendingScreen]).
///
/// Backed by the single Firestore document `config/adminContact`, which
/// the admin panel (Settings → Support contact) writes:
///
///   name    — the admin's name
///   mobile  — main mobile number (shown first, with Call and WhatsApp)
///   phones  — up to 5 more phone numbers
///   emails  — 1 to 5 email addresses
///   phone / email — copies of the mobile and the first email, kept for
///                   older app versions that only read those two keys
///
/// Older documents that only have `name`, `phone` and `email` still work:
/// `phone` is read as the mobile and `email` as the only email.
/// If the document doesn't exist yet, [AdminContact.fallback] is used so
/// the waiting screen never shows blank contact fields.
class AdminContact {
  final String name;

  /// Main mobile number. Empty if the admin hasn't set one.
  final String mobile;

  /// Extra phone numbers, not including [mobile].
  final List<String> phones;

  /// Email addresses, in the order the admin entered them.
  final List<String> emails;

  const AdminContact({
    required this.name,
    required this.mobile,
    this.phones = const [],
    this.emails = const [],
  });

  /// Shown until an admin fills in `config/adminContact` in Firestore, or if
  /// that read fails for any reason (offline, permissions, etc).
  static const AdminContact fallback = AdminContact(
    name: 'My Goat Farms Support',
    mobile: '',
    emails: ['mygoatfarm20@gmail.com'],
  );

  /// Kept so existing code that reads a single phone keeps working.
  String get phone => mobile;

  /// Kept so existing code that reads a single email keeps working.
  String get email => emails.isEmpty ? '' : emails.first;

  /// Every phone number to show: the mobile first, then the extra ones.
  List<String> get allPhones => _unique([mobile, ...phones]);

  bool get hasPhone => allPhones.isNotEmpty;
  bool get hasEmail => emails.isNotEmpty;

  factory AdminContact.fromMap(Map<String, dynamic>? data) {
    if (data == null) return fallback;

    final name = _string(data['name']);
    final mobile = _string(data['mobile']).isNotEmpty
        ? _string(data['mobile'])
        : _string(data['phone']);

    final phones = _unique(_stringList(data['phones']))
        .where((p) => _digits(p) != _digits(mobile))
        .toList();

    final emails = _unique(
      [..._stringList(data['emails']), _string(data['email'])],
      key: (e) => e.toLowerCase(),
    );

    return AdminContact(
      name: name.isEmpty ? fallback.name : name,
      mobile: mobile,
      phones: phones,
      emails: emails.isEmpty ? fallback.emails : emails,
    );
  }

  // ---------------------------------------------------------------------
  // Helpers — tolerant of missing or wrongly typed fields.
  // ---------------------------------------------------------------------

  static String _string(dynamic value) => value is String ? value.trim() : '';

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().map((s) => s.trim()).toList();
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  /// Drops blanks and duplicates. Phone numbers are compared by their
  /// digits (so "98765 43210" and "9876543210" count as the same).
  static List<String> _unique(
      List<String> values, {
        String Function(String)? key,
      }) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in values) {
      final trimmed = v.trim();
      if (trimmed.isEmpty) continue;
      final digits = _digits(trimmed);
      final k = key != null ? key(trimmed) : (digits.isNotEmpty ? digits : trimmed);
      if (seen.add(k)) out.add(trimmed);
    }
    return out;
  }
}