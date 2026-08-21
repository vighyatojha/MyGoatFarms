import 'package:flutter/material.dart';
import 'customer_goat_weight_screen.dart';
import '../../../models/palai_goat.dart';
import 'customer_goat_hoof_screen.dart';
import 'customer_goat_vaccination_screen.dart';

class CustomerPalaiGoatProfileScreen extends StatelessWidget {
  final PalaiGoat goat;

  const CustomerPalaiGoatProfileScreen({
    super.key,
    required this.goat,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goat Profile'),
        actions: [
          IconButton(
            tooltip: 'More options',
            onPressed: () => _showMoreOptions(context),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildProfileHeader(context),
                  const SizedBox(height: 20),
                  _buildCurrentOverview(context),
                  const SizedBox(height: 28),
                  _buildSectionTitle(
                    context,
                    'Goat Management',
                    'Open a section to add or view records.',
                  ),
                  const SizedBox(height: 12),
                  _buildManagementGrid(context),
                  const SizedBox(height: 28),
                  _buildSectionTitle(
                    context,
                    'History',
                    'View the complete activity of this goat.',
                  ),
                  const SizedBox(height: 12),
                  _buildHistoryCard(context),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PROFILE HEADER
  // ===========================================================================

  Widget _buildProfileHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGoatImage(context),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goat.name.trim().isEmpty
                        ? 'Unnamed Goat'
                        : goat.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    goat.tagNumber.trim().isEmpty
                        ? 'No tag number'
                        : 'Tag: ${goat.tagNumber}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSmallChip(
                        context,
                        goat.gender.trim().isEmpty
                            ? 'Gender not set'
                            : goat.gender,
                        Icons.wc_outlined,
                      ),
                      if (goat.breed.trim().isNotEmpty)
                        _buildSmallChip(
                          context,
                          goat.breed,
                          Icons.category_outlined,
                        ),
                      _buildStatusChip(context),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoatImage(BuildContext context) {
    final imageUrl = goat.imageUrl?.trim();

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          imageUrl,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return _buildDefaultGoatImage(context);
          },
        ),
      );
    }

    return _buildDefaultGoatImage(context);
  }

  Widget _buildDefaultGoatImage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Icon(
        Icons.pets_outlined,
        size: 42,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  // ===========================================================================
  // CURRENT OVERVIEW
  // ===========================================================================

  Widget _buildCurrentOverview(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          context,
          'Current Overview',
          'Important information at a glance.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOverviewCard(
                context,
                icon: Icons.monitor_weight_outlined,
                title: 'Weight',
                value: goat.currentWeight == null
                    ? 'Not added'
                    : '${_formatWeight(goat.currentWeight!)} kg',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOverviewCard(
                context,
                icon: Icons.calendar_today_outlined,
                title: 'Registered',
                value: _formatDate(goat.registrationDate),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOverviewCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String value,
      }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MANAGEMENT
  // ===========================================================================

  Widget _buildManagementGrid(BuildContext context) {
    final actions = <_GoatAction>[
      _GoatAction(
        title: 'Weight',
        subtitle: 'Growth & records',
        icon: Icons.monitor_weight_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomerGoatWeightScreen(
                customerId: goat.customerId,
                goat: goat,
              ),
            ),
          );
        },
      ),
      _GoatAction(
        title: 'Health',
        subtitle: 'Health status',
        icon: Icons.health_and_safety_outlined,
        onTap: () => _showComingSoon(context, 'Health'),
      ),
      _GoatAction(
        title: 'Vaccination',
        subtitle: 'Schedule & history',
        icon: Icons.vaccines_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  CustomerGoatVaccinationScreen(
                    customerId: goat.customerId,
                    goat: goat,
                  ),
            ),
          );
        },
      ),
      _GoatAction(
        title: 'Hoof Cutting',
        subtitle: 'Cutting records',
        icon: Icons.content_cut_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  CustomerGoatHoofScreen(
                    customerId: goat.customerId,
                    goat: goat,
                  ),
            ),
          );
        },
      ),
      _GoatAction(
        title: 'Hair Trimming',
        subtitle: 'Trimming records',
        icon: Icons.content_cut_outlined,
        onTap: () => _showComingSoon(context, 'Hair Trimming'),
      ),
      _GoatAction(
        title: 'Medicine',
        subtitle: 'Medicine records',
        icon: Icons.medication_outlined,
        onTap: () => _showComingSoon(context, 'Medicine'),
      ),
      _GoatAction(
        title: 'Photos',
        subtitle: 'Monthly photos',
        icon: Icons.photo_library_outlined,
        onTap: () => _showComingSoon(context, 'Photos'),
      ),
      _GoatAction(
        title: 'Check-In / Out',
        subtitle: 'Boarding movement',
        icon: Icons.swap_horiz_outlined,
        onTap: () => _showComingSoon(context, 'Check-In / Check-Out'),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.18,
      ),
      itemBuilder: (context, index) {
        return _buildActionCard(
          context,
          actions[index],
        );
      },
    );
  }

  Widget _buildActionCard(
      BuildContext context,
      _GoatAction action,
      ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.primaryContainer,
                ),
                child: Icon(
                  action.icon,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                action.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                action.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HISTORY
  // ===========================================================================

  Widget _buildHistoryCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showComingSoon(context, 'Complete History'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                ),
                child: Icon(
                  Icons.history_outlined,
                  color: Theme.of(context)
                      .colorScheme
                      .onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete History',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Weight, health, medicines, vaccinations and other records.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION TITLE
  // ===========================================================================

  Widget _buildSectionTitle(
      BuildContext context,
      String title,
      String subtitle,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SMALL CHIP
  // ===========================================================================

  Widget _buildSmallChip(
      BuildContext context,
      String text,
      IconData icon,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final status = goat.status.trim().isEmpty
        ? 'active'
        : goat.status;

    final isActive =
        status.toLowerCase() == 'active';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isActive
            ? Theme.of(context)
            .colorScheme
            .primaryContainer
            : Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Text(
        _formatStatus(status),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ===========================================================================
  // MORE OPTIONS
  // ===========================================================================

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                ),
                title: const Text(
                  'Edit Goat',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showComingSoon(
                    context,
                    'Edit Goat',
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                ),
                title: const Text(
                  'Change Photo',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showComingSoon(
                    context,
                    'Change Photo',
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // TEMPORARY NAVIGATION PLACEHOLDER
  // ===========================================================================

  void _showComingSoon(
      BuildContext context,
      String feature,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$feature will be connected next.',
          ),
          duration: const Duration(
            seconds: 2,
          ),
        ),
      );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _formatWeight(double weight) {
    if (weight == weight.roundToDouble()) {
      return weight.toStringAsFixed(0);
    }

    return weight.toStringAsFixed(1);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _formatStatus(String status) {
    final normalized = status.trim();

    if (normalized.isEmpty) {
      return 'Active';
    }

    switch (normalized.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'inactive':
        return 'Inactive';
      case 'checkedin':
      case 'checked_in':
        return 'Checked In';
      case 'checkedout':
      case 'checked_out':
        return 'Checked Out';
      default:
        if (normalized.length == 1) {
          return normalized.toUpperCase();
        }

        return normalized[0].toUpperCase() +
            normalized.substring(1);
    }
  }
}

// ============================================================================
// ACTION MODEL
// ============================================================================

class _GoatAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _GoatAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}