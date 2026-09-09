import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/partner_model.dart';
import '../../services/firestore_service.dart';
import 'partner_profile_screen.dart';

class PartnerManagementScreen extends StatelessWidget {
  final String farmId;

  const PartnerManagementScreen({
    super.key,
    required this.farmId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text(
          'Partner Management',
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
      body: StreamBuilder<List<PartnerModel>>(
        stream: FirestoreService.instance.partnersStream(farmId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryGreen,
              ),
            );
          }

          final partners = snapshot.data ?? const <PartnerModel>[];

          final activeCount = partners.where((p) => p.isActive).length;
          final inactiveCount = partners.length - activeCount;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              _buildIntroCard(partners.length, activeCount),
              const SizedBox(height: 14),

              _buildStatsRow(
                total: partners.length,
                active: activeCount,
                inactive: inactiveCount,
              ),

              const SizedBox(height: 22),

              if (partners.isNotEmpty) ...[
                _buildSectionHeader(
                  title: 'Farm Partners',
                  subtitle: 'People who have access to this farm',
                  count: partners.length,
                ),
                const SizedBox(height: 10),
                ...partners.map(
                      (partner) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PartnerCard(
                      farmId: farmId,
                      partner: partner,
                    ),
                  ),
                ),
              ] else
                _buildEmptyState(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIntroCard(int total, int active) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 20),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.groups_2_outlined,
              size: 28,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Farm Partners',
                  style: AppTheme.heading(
                    size: 16,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? 'No partners have been added yet.'
                      : '$active active ${active == 1 ? 'partner' : 'partners'} '
                      'currently have access.',
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow({
    required int total,
    required int active,
    required int inactive,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.people_outline,
            value: '$total',
            label: 'Total',
            iconColor: AppColors.primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_outline,
            value: '$active',
            label: 'Active',
            iconColor: AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.pause_circle_outline,
            value: '$inactive',
            label: 'Inactive',
            iconColor: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required int count,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.heading(
                  size: 14,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count ${count == 1 ? 'person' : 'people'}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryGreen,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 34,
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.person_add_alt_1_outlined,
              size: 32,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No partners yet',
            style: AppTheme.heading(
              size: 16,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Farm partners will appear here once they are added '
                'to this farm.',
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.card(radius: 16),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTheme.heading(
              size: 20,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: AppTheme.body(
              size: 9,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  final String farmId;
  final PartnerModel partner;

  const _PartnerCard({
    required this.farmId,
    required this.partner,
  });

  @override
  Widget build(BuildContext context) {
    final name = partner.name.trim().isEmpty
        ? 'Unnamed partner'
        : partner.name.trim();

    final contact = partner.email.trim().isNotEmpty
        ? partner.email.trim()
        : partner.mobileNumber.trim().isNotEmpty
        ? partner.mobileNumber.trim()
        : 'No contact information';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PartnerProfileScreen(
                farmId: farmId,
                partner: partner,
              ),
            ),
          );
        },
        child: Ink(
          decoration: AppTheme.card(radius: 18),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 25,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              size: 13,
                              color: AppColors.textDark,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _PartnerBadge(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          partner.email.trim().isNotEmpty
                              ? Icons.email_outlined
                              : Icons.phone_outlined,
                          size: 13,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            contact,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              size: 10,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(isActive: partner.isActive),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textGrey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'PARTNER',
        style: TextStyle(
          color: AppColors.info,
          fontWeight: FontWeight.w800,
          fontSize: 7,
          letterSpacing: .4,
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
        horizontal: 8,
        vertical: 4,
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
            size: 11,
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