import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/palai_models.dart';
import '../../palai/multi_goat_checkout_screen.dart';
import '../../../widgets/fast_route.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_goat.dart';
import 'customer_goat_weight_screen.dart';
import 'customer_goat_hoof_screen.dart';
import 'customer_goat_vaccination_screen.dart';

class CustomerPalaiGoatProfileScreen extends StatelessWidget {
  final PalaiGoat goat;

  const CustomerPalaiGoatProfileScreen({
    super.key,
    required this.goat,
  });

  // ===========================================================================
  // DIRECT CHECKOUT
  // ===========================================================================

  Future<void> _openDirectCheckout(BuildContext context) async {
    if (goat.isCheckedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This goat has already been checked out.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      fastRoute(
        MultiGoatCheckoutScreen(
          customerId: goat.customerId,
          initialSelectedGoats: [goat],
          allowSelection: false,
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,

        title: Text(
          'Goat Profile',
          style: AppTheme.heading(
            size: 18,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'More options',
            onPressed: () => _showMoreOptions(context),
            icon: const Icon(
              Icons.more_vert,
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                32,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    _buildProfileHeader(context),

                    const SizedBox(height: 18),

                    // ---------------------------------------------------------
                    // DIRECT CHECKOUT BUTTON
                    // ---------------------------------------------------------

                    if (!goat.isCheckedOut)
                      _buildCheckoutButton(context),

                    if (!goat.isCheckedOut)
                      const SizedBox(height: 24),

                    // ---------------------------------------------------------
                    // CURRENT OVERVIEW
                    // ---------------------------------------------------------

                    _buildSectionTitle(
                      context,
                      'Current Overview',
                      'Important information at a glance.',
                    ),

                    const SizedBox(height: 12),

                    _buildCurrentOverview(context),

                    const SizedBox(height: 28),

                    // ---------------------------------------------------------
                    // GOAT MANAGEMENT
                    // ---------------------------------------------------------

                    _buildSectionTitle(
                      context,
                      'Goat Management',
                      'Open a section to add or view records.',
                    ),

                    const SizedBox(height: 12),

                    _buildManagementGrid(context),

                    const SizedBox(height: 28),

                    // ---------------------------------------------------------
                    // HISTORY
                    // ---------------------------------------------------------

                    _buildSectionTitle(
                      context,
                      'History',
                      'View the complete activity of this goat.',
                    ),

                    const SizedBox(height: 12),

                    _buildHistoryCard(context),
                  ],
                ),
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
    return Container(
      decoration: AppTheme.card(
        radius: 16,
      ),
      padding: const EdgeInsets.all(16),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGoatImage(),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goat.goatCode.trim().isEmpty
                      ? 'Unnamed Goat'
                      : goat.goatCode,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 19,
                  ),
                ),

                const SizedBox(height: 5),

                if (goat.color.trim().isNotEmpty)
                  Text(
                    'Color: ${goat.color}',
                    style: AppTheme.body(
                      size: 11,
                      color: AppColors.textGrey,
                    ),
                  ),

                const SizedBox(height: 10),

                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (goat.gender.trim().isNotEmpty)
                      _buildSmallChip(
                        goat.gender,
                        Icons.wc_outlined,
                      ),

                    if (goat.breed.trim().isNotEmpty)
                      _buildSmallChip(
                        goat.breed,
                        Icons.category_outlined,
                      ),

                    _buildStatusChip(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GOAT IMAGE
  // ===========================================================================

  Widget _buildGoatImage() {
    final image = goat.beforeImage;

    return Container(
      width: 90,
      height: 90,

      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),

      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),

        child: image != null
            ? Image.memory(
          image,
          fit: BoxFit.cover,
        )
            : const Icon(
          Icons.pets_outlined,
          size: 42,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }

  // ===========================================================================
  // CHECKOUT BUTTON
  // ===========================================================================

  Widget _buildCheckoutButton(BuildContext context) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(16),

        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: ElevatedButton.icon(
        onPressed: () => _openDirectCheckout(context),

        icon: const Icon(
          Icons.logout_rounded,
          size: 21,
        ),

        label: const Text(
          'CHECK OUT THIS GOAT',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),

        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,

          minimumSize: const Size.fromHeight(56),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CURRENT OVERVIEW
  // ===========================================================================

  Widget _buildCurrentOverview(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildOverviewCard(
            icon: Icons.monitor_weight_outlined,
            title: 'Weight',
            value: goat.currentWeight == null
                ? '${goat.weightAtCheckIn.toStringAsFixed(1)} kg'
                : '${goat.currentWeight!.toStringAsFixed(1)} kg',
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _buildOverviewCard(
            icon: Icons.calendar_today_outlined,
            title: 'Checked In',
            value: _formatDate(goat.checkInDate),
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      decoration: AppTheme.card(
        radius: 14,
      ),

      padding: const EdgeInsets.all(14),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,

            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),

            child: Icon(
              icon,
              size: 18,
              color: AppColors.primaryGreen,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            title,
            style: AppTheme.body(
              size: 10,
              color: AppColors.textGrey,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(
              size: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MANAGEMENT GRID
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
        subtitle: goat.healthStatus,
        icon: Icons.health_and_safety_outlined,
        onTap: () => _showComingSoon(
          context,
          'Health',
        ),
      ),

      _GoatAction(
        title: 'Vaccination',
        subtitle: 'Schedule & history',
        icon: Icons.vaccines_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomerGoatVaccinationScreen(
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
              builder: (_) => CustomerGoatHoofScreen(
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
        onTap: () => _showComingSoon(
          context,
          'Hair Trimming',
        ),
      ),

      _GoatAction(
        title: 'Medicine',
        subtitle: 'Medicine records',
        icon: Icons.medication_outlined,
        onTap: () => _showComingSoon(
          context,
          'Medicine',
        ),
      ),

      _GoatAction(
        title: 'Photos',
        subtitle: 'Monthly photos',
        icon: Icons.photo_library_outlined,
        onTap: () => _showComingSoon(
          context,
          'Photos',
        ),
      ),

      _GoatAction(
        title: 'Check-In / Out',
        subtitle: goat.isCheckedOut
            ? 'Already checked out'
            : 'Boarding movement',
        icon: Icons.swap_horiz_outlined,
        onTap: goat.isCheckedOut
            ? null
            : () => _openDirectCheckout(context),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),

      itemCount: actions.length,

      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(
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
    final enabled = action.onTap != null;

    return Container(
      decoration: AppTheme.card(
        radius: 14,
      ),

      child: InkWell(
        onTap: enabled ? action.onTap : null,

        borderRadius: BorderRadius.circular(14),

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
                  color: enabled
                      ? AppColors.lightGreen
                      : Colors.grey.shade100,
                ),

                child: Icon(
                  action.icon,
                  color: enabled
                      ? AppColors.primaryGreen
                      : AppColors.textGrey,
                ),
              ),

              const Spacer(),

              Text(
                action.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(
                  size: 12,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                action.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 10,
                  color: AppColors.textGrey,
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
    return Container(
      decoration: AppTheme.card(
        radius: 14,
      ),

      padding: const EdgeInsets.all(15),

      child: Column(
        children: [
          _historyRow(
            icon: Icons.login_rounded,
            title: 'Check-In',
            value: _formatDate(goat.checkInDate),
          ),

          if (goat.checkOutDate != null) ...[
            const Divider(height: 20),

            _historyRow(
              icon: Icons.logout_rounded,
              title: 'Check-Out',
              value: _formatDate(
                goat.checkOutDate!,
              ),
            ),
          ],

          const Divider(height: 20),

          _historyRow(
            icon: Icons.health_and_safety_outlined,
            title: 'Health',
            value: goat.healthStatus,
          ),

          const Divider(height: 20),

          _historyRow(
            icon: Icons.receipt_long_outlined,
            title: 'Monthly Package',
            value: goat.monthlyPackage.isEmpty
                ? 'Not specified'
                : goat.monthlyPackage,
          ),

          const Divider(height: 20),

          _historyRow(
            icon: Icons.currency_rupee,
            title: 'Palai Price',
            value:
            '₹${goat.pricing.toStringAsFixed(0)}',
          ),

          if (goat.notes.trim().isNotEmpty) ...[
            const Divider(height: 20),

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notes_outlined,
                  size: 18,
                  color: AppColors.textGrey,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notes',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textGrey,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        goat.notes,
                        style: AppTheme.body(
                          size: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,

          decoration: const BoxDecoration(
            color: AppColors.lightGreen,
            shape: BoxShape.circle,
          ),

          child: Icon(
            icon,
            size: 17,
            color: AppColors.primaryGreen,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Text(
            title,
            style: AppTheme.body(
              size: 11,
              color: AppColors.textGrey,
            ),
          ),
        ),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTheme.heading(
              size: 11,
            ),
          ),
        ),
      ],
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
          style: AppTheme.heading(
            size: 17,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          subtitle,
          style: AppTheme.body(
            size: 10,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SMALL CHIP
  // ===========================================================================

  Widget _buildSmallChip(
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
        color: AppColors.lightGreen,
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.darkGreen,
          ),

          const SizedBox(width: 5),

          Text(
            text,
            style: AppTheme.body(
              size: 9,
              color: AppColors.darkGreen,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATUS CHIP
  // ===========================================================================

  Widget _buildStatusChip() {
    final checkedOut = goat.isCheckedOut;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),

        color: checkedOut
            ? Colors.grey.shade200
            : AppColors.lightGreen,
      ),

      child: Text(
        checkedOut
            ? 'Checked Out'
            : 'Currently Boarded',

        style: AppTheme.body(
          size: 9,

          color: checkedOut
              ? AppColors.textGrey
              : AppColors.darkGreen,

          weight: FontWeight.w700,
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

      backgroundColor: Colors.white,

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

              if (!goat.isCheckedOut)
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                  ),

                  title: const Text(
                    'Check Out Goat',
                  ),

                  onTap: () {
                    Navigator.pop(sheetContext);

                    _openDirectCheckout(
                      context,
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
  // HELPERS
  // ===========================================================================

  String _formatDate(DateTime date) {
    final day =
    date.day.toString().padLeft(2, '0');

    final month =
    date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  void _showComingSoon(
      BuildContext context,
      String feature,
      ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature is coming soon.',
        ),
      ),
    );
  }
}

// ============================================================================
// ACTION MODEL
// ============================================================================

class _GoatAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _GoatAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}