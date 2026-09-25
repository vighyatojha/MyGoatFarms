import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds and sends WhatsApp payment reminders from the Customer Ledger.
///
/// Each customer gets a message with THEIR OWN pending amount — Ramesh
/// with ₹5,000 pending receives "₹5,000", Raj with ₹20,900 receives
/// "₹20,900".
///
/// How sending works: this opens WhatsApp with the message already
/// typed for that customer, and the farm owner taps WhatsApp's own Send
/// button. It needs no WhatsApp Business account, no API key and costs
/// nothing. (Fully automatic sending to everyone in one tap needs the
/// WhatsApp Business Cloud API — see the notes that came with this
/// feature.)
class PaymentReminderService {
  PaymentReminderService._();
  static final PaymentReminderService instance = PaymentReminderService._();

  static const _daysPrefKey = 'payment_reminder_days';
  static const int defaultDays = 7;

  /// Country code prepended when a saved number has no country code.
  static const String defaultCountryCode = '91';

  // ---------------------------------------------------------------------
  // "Days to pay" — remembered between uses
  // ---------------------------------------------------------------------

  Future<int> loadDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_daysPrefKey) ?? defaultDays;
  }

  Future<void> saveDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_daysPrefKey, days);
  }

  // ---------------------------------------------------------------------
  // Message
  // ---------------------------------------------------------------------

  String formatAmount(double amount) {
    return '₹${NumberFormat.decimalPattern('en_IN').format(amount.round())}';
  }

  /// The text sent to one customer.
  String buildMessage({
    required String customerName,
    required double pendingAmount,
    required int days,
    String farmName = '',
  }) {
    final dayText = days == 1 ? '1 day' : '$days days';
    final from = farmName.trim().isEmpty ? '' : ' from ${farmName.trim()}';

    return 'Namaste ${customerName.trim()} 🙏\n\n'
        'This is a friendly reminder$from.\n\n'
        'An amount of *${formatAmount(pendingAmount)}* is pending '
        'in your account.\n'
        'Kindly clear the payment within *$dayText*.\n\n'
        'If you have already paid, please ignore this message. '
        'Thank you!';
  }

  // ---------------------------------------------------------------------
  // Phone number
  // ---------------------------------------------------------------------

  /// Turns whatever is saved on the customer ("98765 43210", "+91-98765
  /// 43210", "098765 43210") into digits-only international format
  /// ("919876543210"), which is what wa.me expects. Returns null if the
  /// number is clearly not usable.
  String? normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    // Drop a leading 0 (trunk prefix), e.g. 09876543210.
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    // Plain 10-digit local number -> add country code.
    if (digits.length == 10) {
      return '$defaultCountryCode$digits';
    }

    // Already has a country code (e.g. 91 + 10 digits).
    if (digits.length >= 11 && digits.length <= 15) {
      return digits;
    }

    return null;
  }

  // ---------------------------------------------------------------------
  // Send
  // ---------------------------------------------------------------------

  /// Opens WhatsApp with [message] pre-filled for [mobile].
  /// Returns false if the number is unusable or WhatsApp couldn't open.
  Future<bool> openWhatsApp({
    required String mobile,
    required String message,
  }) async {
    final phone = normalizePhone(mobile);
    if (phone == null) return false;

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}