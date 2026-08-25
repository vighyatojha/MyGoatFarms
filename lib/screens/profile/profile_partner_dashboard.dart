
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/partner_model.dart';
import '../partner/partner_management_screen.dart';
import '../partner/partner_profile_screen.dart';
import 'farm_activity_screen.dart';

/// Redesigned Partner/Profile area for the existing ProfileScreen.
///
/// This is intentionally a UI component rather than a second ProfileScreen.
/// It consumes the existing ProfileScreen state (_farmId, _partners, etc.)
/// and keeps all existing profile CRUD logic intact.
class ProfilePartnerDashboard extends StatelessWidget {
  final String farmId;
  final List<PartnerModel> partners;
  final bool isOwner;
  final VoidCallback? onAddPartner;

  const ProfilePartnerDashboard({
    super.key,
    required this.farmId,
    required this.partners,
    this.isOwner = true,
    this.onAddPartner,
  });

  @override
  Widget build(BuildContext context) {
    final active = partners.where((p) => p.isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.groups_2_outlined,
          title: 'Team & Activity',
          subtitle: isOwner
              ? 'Your partners and everything happening on the farm'
              : 'Everything happening on the farm',
        ),
        const SizedBox(height: 10),

        _ActivityHero(
          farmId: farmId,
          partnerCount: partners.length,
          activeCount: active,
        ),
        const SizedBox(height: 12),

        if (isOwner) ...[
          _ActionCard(
            icon: Icons.manage_accounts_outlined,
            title: 'Partner Management',
            subtitle: partners.isEmpty
                ? 'No partners yet — add your first teammate'
                : '${partners.length} partner${partners.length == 1 ? '' : 's'} • $active active',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PartnerManagementScreen(farmId: farmId),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        _ActionCard(
          icon: Icons.history_rounded,
          title: 'Farm Activity',
          subtitle: 'Every recorded action across Palai, Stock & Customers',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FarmActivityScreen(farmId: farmId),
            ),
          ),
        ),

        if (isOwner && onAddPartner != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: onAddPartner,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add Partner'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],

        if (partners.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionHeader(
            icon: Icons.verified_user_outlined,
            title: 'Partners',
            subtitle: 'Quick view of your farm team',
          ),
          const SizedBox(height: 10),
          ...partners.take(5).map(
                (partner) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PartnerTile(
                    farmId: farmId,
                    partner: partner,
                    isOwner: isOwner,
                  ),
                ),
              ),
          if (partners.length > 5)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PartnerManagementScreen(farmId: farmId),
                  ),
                ),
                child: const Text('View all partners'),
              ),
            ),
        ],
      ],
    );
  }
}

class _ActivityHero extends StatelessWidget {
  final String farmId;
  final int partnerCount;
  final int activeCount;

  const _ActivityHero({
    required this.farmId,
    required this.partnerCount,
    required this.activeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryGreen,
            AppColors.darkGreen,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: .18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.insights_outlined,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Farm activity',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track every important change made by your team.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .84),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatPill(label: '$partnerCount partners'),
                    const SizedBox(width: 7),
                    _StatPill(label: '$activeCount active'),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open activity',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FarmActivityScreen(farmId: farmId),
              ),
            ),
            icon: const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;

  const _StatPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PartnerTile extends StatelessWidget {
  final String farmId;
  final PartnerModel partner;
  final bool isOwner;

  const _PartnerTile({
    required this.farmId,
    required this.partner,
    this.isOwner = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PartnerProfileScreen(
              farmId: farmId,
              partner: partner,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.primaryGreen.withValues(alpha: .10),
                child: Text(
                  partner.name.trim().isEmpty
                      ? '?'
                      : partner.name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name.trim().isEmpty
                          ? 'Unnamed partner'
                          : partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      partner.email.isNotEmpty
                          ? partner.email
                          : partner.mobileNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(active: partner.isActive),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;

  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryGreen.withValues(alpha: .10)
            : Colors.grey.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'ACTIVE' : 'INACTIVE',
        style: TextStyle(
          color: active ? AppColors.primaryGreen : Colors.grey.shade700,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.primaryGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
