import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/admin_contact_model.dart';
import '../models/farm_model.dart';
import '../services/firestore_service.dart';

/// Shown after a new farm owner verifies their email and their farm
/// document is created, replacing the old direct jump to Home.
///
/// Stays on screen — listening live to `farms/{farmId}` — until the admin
/// approves the farm from the admin panel (status becomes 'Active'), at
/// which point it auto-navigates to Home. If the admin rejects the farm
/// instead, it shows the rejection reason and lets the owner sign out.
///
/// Reachable two ways:
///  1. Right after registration, with [farmId]/[farmName]/[ownerName]
///     already known — the live stream starts immediately, no extra read.
///  2. On a fresh app launch while still pending/rejected (the owner
///     closed the app and reopened it) — see the initial-route check in
///     main.dart. No farmId is passed then, so this screen resolves the
///     signed-in user's farm itself first.
///
/// The contact card shows everything the admin entered in the admin
/// panel (Settings → Support contact): name, mobile (with Call and
/// WhatsApp), any other phone numbers and every email.
class FarmApprovalPendingScreen extends StatefulWidget {
  final String? farmId;
  final String? farmName;
  final String? ownerName;

  const FarmApprovalPendingScreen({
    super.key,
    this.farmId,
    this.farmName,
    this.ownerName,
  });

  @override
  State<FarmApprovalPendingScreen> createState() =>
      _FarmApprovalPendingScreenState();
}

class _FarmApprovalPendingScreenState
    extends State<FarmApprovalPendingScreen> {
  static const Color _whatsAppGreen = Color(0xFF25D366);

  final _firestore = FirestoreService.instance;

  StreamSubscription<FarmModel?>? _farmSub;
  FarmModel? _farm;
  String? _resolveError;
  bool _resolving = true;
  bool _navigatedAway = false;

  AdminContact _adminContact = AdminContact.fallback;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _farmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    unawaited(_loadAdminContact());

    var farmId = widget.farmId;

    if (farmId == null) {
      // Reached via a fresh app launch (main.dart) rather than straight
      // after registration — resolve which farm this signed-in user owns
      // before we have anything to subscribe to.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _goToLogin();
        return;
      }

      final farm = await _firestore.getFarmForUser(uid);
      if (!mounted) return;

      if (farm == null) {
        setState(() {
          _resolving = false;
          _resolveError = "We couldn't find your farm registration.";
        });
        return;
      }

      farmId = farm.id;
      _farm = farm;
    }

    if (!mounted) return;
    setState(() => _resolving = false);
    _subscribe(farmId!);
  }

  Future<void> _loadAdminContact() async {
    final contact = await _firestore.getAdminContact();
    if (!mounted) return;
    setState(() => _adminContact = contact);
  }

  void _subscribe(String farmId) {
    _farmSub = _firestore.farmDocStream(farmId).listen(
          (farm) {
        if (!mounted) return;
        setState(() => _farm = farm);
        _maybeLeaveScreen(farm);
      },
      // Losing the live connection shouldn't strand the owner with a
      // spinner forever — the last-known status (already on screen) just
      // stops updating until connectivity comes back.
      onError: (_) {},
    );
  }

  void _maybeLeaveScreen(FarmModel? farm) {
    if (_navigatedAway || farm == null) return;
    if (farm.status == 'Active') {
      _navigatedAway = true;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    _goToLogin();
  }

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // ---------------------------------------------------------------------
  // Contact actions
  // ---------------------------------------------------------------------

  Future<bool> _launch(Uri uri, {bool external = false}) async {
    try {
      return await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _call(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    final ok = await _launch(Uri(scheme: 'tel', path: number));
    if (!ok) _showSnack("Couldn't open the dialer. The number is $phone.");
  }

  Future<void> _whatsApp(String phone) async {
    final number = _whatsAppNumber(phone);
    if (number == null) {
      _showSnack("This number can't be opened in WhatsApp.");
      return;
    }
    final farmPart = _farmName.isEmpty ? 'my farm' : '"$_farmName"';
    final message =
        'Hello, I need help with $farmPart on My Goat Farms.';
    final ok = await _launch(
      Uri.parse(
        'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
      ),
      external: true,
    );
    if (!ok) _showSnack("Couldn't open WhatsApp. Is it installed?");
  }

  Future<void> _email(String email) async {
    final address = email.trim();
    if (address.isEmpty) return;
    final subject = _farmName.isEmpty
        ? 'My Goat Farms: farm registration'
        : 'My Goat Farms: $_farmName';
    final ok = await _launch(
      Uri.parse(
        'mailto:$address?subject=${Uri.encodeComponent(subject)}',
      ),
    );
    if (!ok) _showSnack("Couldn't open an email app. The address is $address.");
  }

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnack('$what copied');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// "98765 43210", "+91 98765 43210", "098765 43210" -> "919876543210",
  /// which is what wa.me expects. Null if the number isn't usable.
  String? _whatsAppNumber(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length == 10) return '91$digits';
    if (digits.length >= 11 && digits.length <= 15) return digits;
    return null;
  }

  /// Shows a 10-digit mobile as "98765 43210"; anything else as entered.
  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '${digits.substring(0, 5)} ${digits.substring(5)}';
    }
    return raw.trim();
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF4),
      body: SafeArea(
        child: _resolving
            ? const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        )
            : _resolveError != null
            ? _ErrorState(
          message: _resolveError!,
          onSignOut: _signOut,
        )
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: _farm?.status == 'Blocked'
              ? _buildBlocked()
              : _farm?.status == 'Rejected'
              ? _buildRejected()
              : _buildWaiting(),
        ),
      ),
    );
  }

  String get _farmName => (_farm?.farmName ?? widget.farmName ?? '').trim();
  String get _ownerName =>
      (_farm?.ownerName ?? widget.ownerName ?? '').trim();

  Widget _buildWaiting() {
    return Column(
      children: [
        _iconBadge(
          icon: Icons.hourglass_top_rounded,
          color: AppColors.primaryGreen,
        ),
        const SizedBox(height: 26),
        Text(
          _ownerName.isEmpty
              ? 'Your farm is under review'
              : 'Thanks, $_ownerName!',
          textAlign: TextAlign.center,
          style: AppTheme.heading(size: 22, color: AppColors.darkGreen),
        ),
        const SizedBox(height: 10),
        Text(
          _farmName.isEmpty
              ? 'Your farm registration is waiting on admin approval. '
              "This usually doesn't take long — you'll be moved to "
              'the app automatically as soon as it\'s approved.'
              : '"$_farmName" is waiting on admin approval. This usually '
              "doesn't take long — you'll be moved to the app "
              'automatically as soon as it\'s approved.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 14, color: AppColors.textGrey, weight: FontWeight.w400)
              .copyWith(height: 1.5),
        ),
        const SizedBox(height: 8),
        _statusChip(
          label: 'Pending approval',
          color: AppColors.warning,
          icon: Icons.schedule_rounded,
        ),
        const SizedBox(height: 30),
        _contactCard(),
        const SizedBox(height: 28),
        _signOutButton(),
      ],
    );
  }

  Widget _buildBlocked() {
    return Column(
      children: [
        _iconBadge(
          icon: Icons.block_rounded,
          color: AppColors.error,
        ),
        const SizedBox(height: 26),
        Text(
          'Farm blocked',
          textAlign: TextAlign.center,
          style: AppTheme.heading(size: 22, color: AppColors.error),
        ),
        const SizedBox(height: 10),
        Text(
          _farmName.isEmpty
              ? 'Your farm account has been blocked by the admin.'
              : '"$_farmName" has been blocked by the admin.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 14, color: AppColors.textGrey)
              .copyWith(height: 1.5),
        ),
        const SizedBox(height: 10),
        Text(
          'You cannot use the app while your farm is blocked. '
              'Please contact admin for assistance.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 13, color: AppColors.textGrey)
              .copyWith(height: 1.5),
        ),
        const SizedBox(height: 8),
        _statusChip(
          label: 'Blocked',
          color: AppColors.error,
          icon: Icons.block_rounded,
        ),
        const SizedBox(height: 30),
        _contactCard(),
        const SizedBox(height: 28),
        _signOutButton(),
      ],
    );
  }

  Widget _buildRejected() {
    final reason = (_farm?.rejectionReason ?? '').trim();

    return Column(
      children: [
        _iconBadge(
          icon: Icons.cancel_outlined,
          color: AppColors.error,
        ),
        const SizedBox(height: 26),
        Text(
          'Registration not approved',
          textAlign: TextAlign.center,
          style: AppTheme.heading(size: 22, color: AppColors.error),
        ),
        const SizedBox(height: 10),
        Text(
          _farmName.isEmpty
              ? "Your farm registration wasn't approved."
              : 'Your registration for "$_farmName" wasn\'t approved.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 14, color: AppColors.textGrey)
              .copyWith(height: 1.5),
        ),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason given',
                  style: AppTheme.body(size: 11, color: AppColors.error)
                      .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: AppTheme.body(size: 13.5, color: AppColors.textDark)
                      .copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'If you think this is a mistake, reach out using the details below.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 13, color: AppColors.textGrey),
        ),
        const SizedBox(height: 22),
        _contactCard(),
        const SizedBox(height: 28),
        _signOutButton(),
      ],
    );
  }

  Widget _iconBadge({required IconData icon, required Color color}) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 42),
    );
  }

  Widget _statusChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.body(size: 12.5, color: color)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Contact card — everything the admin set in Settings → Support contact
  // ---------------------------------------------------------------------

  Widget _contactCard() {
    final contact = _adminContact;
    final mobile = contact.mobile.trim();
    final otherPhones = contact.allPhones
        .where((p) => p.replaceAll(RegExp(r'[^0-9]'), '') !=
        mobile.replaceAll(RegExp(r'[^0-9]'), ''))
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: AppColors.darkGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help? Contact admin',
                      style: AppTheme.body(size: 11, color: AppColors.textGrey)
                          .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.name,
                      style: AppTheme.heading(size: 15.5),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Main mobile: Call + WhatsApp
          if (mobile.isNotEmpty) ...[
            const SizedBox(height: 16),
            _mobileBlock(mobile),
          ],

          // Other phone numbers
          if (otherPhones.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionLabel(
              mobile.isEmpty
                  ? (otherPhones.length == 1 ? 'Phone' : 'Phones')
                  : (otherPhones.length == 1 ? 'Other number' : 'Other numbers'),
            ),
            for (final phone in otherPhones)
              _contactRow(
                icon: Icons.call_rounded,
                value: _formatPhone(phone),
                onTap: () => _call(phone),
                onLongPress: () => _copy(phone, 'Number'),
              ),
          ],

          // Emails
          if (contact.emails.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionLabel(contact.emails.length == 1 ? 'Email' : 'Emails'),
            for (final email in contact.emails)
              _contactRow(
                icon: Icons.email_rounded,
                value: email,
                onTap: () => _email(email),
                onLongPress: () => _copy(email, 'Email'),
              ),
          ],

          const SizedBox(height: 10),
          Text(
            'Tap to call or email. Press and hold to copy.',
            style: AppTheme.body(size: 11.5, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Widget _mobileBlock(String mobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mobile',
            style: AppTheme.body(size: 11, color: AppColors.textGrey, weight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onLongPress: () => _copy(mobile, 'Number'),
            child: Text(
              _formatPhone(mobile),
              style: AppTheme.heading(size: 19, color: AppColors.darkGreen),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.call_rounded,
                  label: 'Call',
                  color: AppColors.darkGreen,
                  filled: false,
                  onTap: () => _call(mobile),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: _whatsAppGreen,
                  filled: true,
                  onTap: () => _whatsApp(mobile),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(vertical: 12, horizontal: 8);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: filled ? Colors.white : color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 13.5,
              color: filled ? Colors.white : color,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (filled) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: padding,
          shape: shape,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        padding: padding,
        shape: shape,
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: AppTheme.body(size: 11, color: AppColors.textGrey, weight: FontWeight.w600),
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.primaryGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: AppTheme.body(size: 13.5, color: AppColors.textDark),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textGrey.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _signOutButton() {
    return TextButton.icon(
      onPressed: _signOut,
      icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.textGrey),
      label: Text(
        'Sign out',
        style: AppTheme.body(size: 13.5, color: AppColors.textGrey)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onSignOut;

  const _ErrorState({required this.message, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 46, color: AppColors.textGrey),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 14, color: AppColors.textGrey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onSignOut,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
              child: const Text('Sign out', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}