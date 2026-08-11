import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';

/// Reached from the "Total Goats" stat card on the Home dashboard.
/// Shows every goat currently checked into Palai, live from Firestore.
class TotalGoatsScreen extends StatefulWidget {
  const TotalGoatsScreen({super.key});

  @override
  State<TotalGoatsScreen> createState() => _TotalGoatsScreenState();
}

class _TotalGoatsScreenState extends State<TotalGoatsScreen> {
  String? _farmId;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Total Goats', style: AppTheme.heading(size: 17)),
      ),
      body: _farmId == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : StreamBuilder<List<PalaiGoat>>(
              stream: FirestoreService.instance.allActiveGoatsStream(_farmId!),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                }
                final goats = snap.data!;
                if (goats.isEmpty) {
                  return Center(child: Text('No goats checked in yet.', style: AppTheme.body(size: 13)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: goats.length,
                  itemBuilder: (context, index) {
                    final g = goats[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: AppTheme.card(radius: 14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
                            child: const Icon(Icons.pets, color: AppColors.primaryGreen),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.goatCode, style: AppTheme.heading(size: 14)),
                                Text('${g.breed} · ${g.gender} · ${g.color}', style: AppTheme.body(size: 11)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${g.currentWeight ?? g.weightAtCheckIn} kg', style: AppTheme.heading(size: 13)),
                              Text(g.healthStatus, style: AppTheme.body(size: 10, color: AppColors.success)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
