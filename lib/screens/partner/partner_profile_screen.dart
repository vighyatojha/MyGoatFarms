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

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Remove partner?'),
          content: Text(
            '${partner.name} will no longer be listed as a farm partner '
            'and will lose access to this farm.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
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
          content: Text(FirestoreService.instance.describeError(e)),
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
        title: const Text('Partner Profile'),
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: Color(0xFFE8F3EB),
                    child: Icon(
                      Icons.person_outline,
                      size: 34,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    partner.name.isEmpty ? 'Unnamed partner' : partner.name,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const _PartnerBadge(),
                  const SizedBox(height: 16),
                  if (partner.email.isNotEmpty)
                    _InfoRow(Icons.email_outlined, partner.email),
                  if (partner.mobileNumber.isNotEmpty)
                    _InfoRow(Icons.phone_outlined, partner.mobileNumber),
                  _InfoRow(
                    partner.isActive
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                    partner.isActive ? 'Active' : 'Inactive',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.history,
                    color: AppColors.darkGreen,
                  ),
                  title: const Text(
                    'Farm Activity',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('See everything happening on the farm'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FarmActivityScreen(farmId: farmId),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _removing ? null : _confirmRemove,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
                  : const Icon(Icons.person_remove_outlined),
              label: const Text(
                'Remove Partner',
                style: TextStyle(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'PARTNER',
        style: TextStyle(
          color: AppColors.info,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoRow(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 9),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
