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
        title: const Text('Partner Management'),
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
      ),
      body: StreamBuilder<List<PartnerModel>>(
        stream: FirestoreService.instance.partnersStream(farmId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }

          final partners = snapshot.data ?? const <PartnerModel>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(partners: partners),
              const SizedBox(height: 14),
              ...partners.map(
                (partner) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PartnerCard(
                    farmId: farmId,
                    partner: partner,
                  ),
                ),
              ),
              if (partners.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                    child: Text('No partners added yet.'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<PartnerModel> partners;

  const _SummaryCard({required this.partners});

  @override
  Widget build(BuildContext context) {
    final active = partners.where((p) => p.isActive).length;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                value: '${partners.length}',
                label: 'Total',
              ),
            ),
            Expanded(
              child: _Metric(
                value: '$active',
                label: 'Active',
              ),
            ),
            const Icon(
              Icons.admin_panel_settings_outlined,
              size: 34,
              color: AppColors.primaryGreen,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.primaryGreen,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
      ],
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 7,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.info.withValues(alpha: .10),
          child: const Icon(
            Icons.handshake_outlined,
            color: AppColors.info,
          ),
        ),
        title: Text(
          partner.name.isEmpty ? 'Unnamed partner' : partner.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          partner.email.isNotEmpty
              ? partner.email
              : partner.mobileNumber,
        ),
        trailing: const Icon(Icons.chevron_right),
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
      ),
    );
  }
}
