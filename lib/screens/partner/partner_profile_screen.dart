import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/partner_model.dart';
import '../../services/firestore_service.dart';
import '../profile/farm_activity_screen.dart';

class PartnerProfileScreen extends StatefulWidget {
  final String farmId;
  final PartnerModel partner;

  const PartnerProfileScreen({
    super.key,
    required this.farmId,
    required this.partner,
  });

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  bool _removing = false;

  String get farmId => widget.farmId;
  PartnerModel get partner => widget.partner;

  String get _partnerName {
    final name = partner.name.trim();
    return name.isEmpty ? 'Unnamed partner' : name;
  }

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.person_remove_outlined,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Remove partner?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '$_partnerName will no longer be listed as a farm partner '
                'and will lose access to this farm.',
            style: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(90, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Remove',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);

    try {
      await FirestoreService.instance.deletePartner(
        farmId: farmId,
        partnerId: partner.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Partner removed.'),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirestoreService.instance.describeError(e),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _removing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text(
          'Partner Profile',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.darkGreen,
          ),
        ),
        backgroundColor: AppColors.paleGreen,
        foregroundColor: AppColors.darkGreen,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          _buildProfileHeader(),

          const SizedBox(height: 14),

          _buildContactSection(),

          const SizedBox(height: 14),

          _buildActivitySection(),

          const SizedBox(height: 14),

          _buildAccessSection(),

          const SizedBox(height: 22),

          _buildDangerSection(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 22),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: .12),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person_outline,
              size: 40,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 13),

          Text(
            _partnerName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(
              size: 19,
              color: AppColors.darkGreen,
            ),
          ),

          const SizedBox(height: 7),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _PartnerBadge(),
              const SizedBox(width: 7),
              _StatusBadge(isActive: partner.isActive),
            ],
          ),

          const SizedBox(height: 15),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9F8),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: const Color(0xFFE9EEEB),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.handshake_outlined,
                  size: 17,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Farm partner with access to farm management',
                    style: AppTheme.body(
                      size: 10,
                      color: AppColors.textGrey,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    final hasEmail = partner.email.trim().isNotEmpty;
    final hasMobile = partner.mobileNumber.trim().isNotEmpty;

    return _sectionCard(
      title: 'Contact Information',
      icon: Icons.contact_page_outlined,
      child: Column(
        children: [
          if (hasEmail)
            _infoRow(
              Icons.email_outlined,
              'EMAIL',
              partner.email.trim(),
            ),
          if (hasEmail && hasMobile) const SizedBox(height: 8),
          if (hasMobile)
            _infoRow(
              Icons.phone_outlined,
              'MOBILE NUMBER',
              partner.mobileNumber.trim(),
            ),
          if (!hasEmail && !hasMobile)
            _emptyInfoRow(
              Icons.contactless_outlined,
              'No contact information provided',
            ),
        ],
      ),
    );
  }

  Widget _buildActivitySection() {
    return _sectionCard(
      title: 'Farm Activity',
      icon: Icons.history_outlined,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FarmActivityScreen(
                  farmId: farmId,
                ),
              ),
            );
          },
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE9EEEB),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.timeline_outlined,
                    size: 19,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Farm Activity',
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.textDark,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'See everything happening on the farm',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 9,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 21,
                  color: AppColors.textGrey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccessSection() {
    return _sectionCard(
      title: 'Partner Access',
      icon: Icons.admin_panel_settings_outlined,
      child: _infoRow(
        partner.isActive
            ? Icons.check_circle_outline
            : Icons.pause_circle_outline,
        'ACCESS STATUS',
        partner.isActive
            ? 'Active — partner can access this farm'
            : 'Inactive — partner access is currently disabled',
        verified: partner.isActive,
      ),
    );
  }

  Widget _buildDangerSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.error.withValues(alpha: .14),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Partner Management',
                  style: AppTheme.heading(
                    size: 14,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Removing this partner will revoke their access to this farm.',
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _removing ? null : _confirmRemove,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                disabledForegroundColor:
                AppColors.error.withValues(alpha: .55),
                side: BorderSide(
                  color: _removing
                      ? AppColors.error.withValues(alpha: .35)
                      : AppColors.error,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _removing
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.error,
                ),
              )
                  : const Icon(
                Icons.person_remove_outlined,
                size: 19,
              ),
              label: Text(
                _removing ? 'Removing Partner...' : 'Remove Partner',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 20),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 14,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(
      IconData icon,
      String label,
      String value, {
        bool verified = false,
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE9EEEB),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppColors.textGrey,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 7,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'Not provided' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (verified)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.verified_outlined,
                size: 15,
                color: AppColors.primaryGreen,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyInfoRow(
      IconData icon,
      String text,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE9EEEB),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: AppColors.textGrey,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                size: 10,
                color: AppColors.textGrey,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerBadge extends StatelessWidget {
  const _PartnerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'PARTNER',
        style: TextStyle(
          color: AppColors.info,
          fontWeight: FontWeight.w900,
          fontSize: 8,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;

  const _StatusBadge({
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textGrey;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive
                ? Icons.check_circle
                : Icons.pause_circle_outline,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}