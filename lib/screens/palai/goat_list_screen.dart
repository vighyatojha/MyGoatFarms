import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import 'check_out_screen.dart';

/// Lists every goat currently boarded in Palai: a circular "Before Palai"
/// photo, the Goat ID, and how long it's been boarded. Tapping a goat
/// opens its Check-Out page.
class GoatListScreen extends StatefulWidget {
  const GoatListScreen({super.key});

  @override
  State<GoatListScreen> createState() => _GoatListScreenState();
}

class _GoatListScreenState extends State<GoatListScreen> {
  String? _farmId;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.currentFarmId().then((id) {
      if (mounted) setState(() => _farmId = id);
    });
  }

  /// e.g. "2 mo 14 d", "18 days", "3 months" — how long a goat has been
  /// boarded, counted from its check-in date to now.
  String _boardedFor(DateTime checkInDate) {
    final now = DateTime.now();
    int months = (now.year - checkInDate.year) * 12 + (now.month - checkInDate.month);
    DateTime monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    if (monthsAgo.isAfter(now)) {
      months -= 1;
      monthsAgo = DateTime(checkInDate.year, checkInDate.month + months, checkInDate.day);
    }
    final days = now.difference(monthsAgo).inDays;
    if (months <= 0) return '$days day${days == 1 ? '' : 's'}';
    if (days <= 0) return '$months month${months == 1 ? '' : 's'}';
    return '$months mo $days d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Goats in Palai', style: AppTheme.heading(size: 17)),
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No goats currently boarded in Palai.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 13),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: goats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final goat = goats[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).push(fastRoute(CheckOutGoatScreen(goat: goat))),
                        child: Container(
                          decoration: AppTheme.card(radius: 14),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.lightGreen,
                                  border: Border.all(color: AppColors.primaryGreen.withOpacity(0.3), width: 1.5),
                                ),
                                child: ClipOval(
                                  child: goat.beforeImage != null
                                      ? Image.memory(goat.beforeImage!, fit: BoxFit.cover, width: 52, height: 52)
                                      : const Icon(Icons.pets, color: AppColors.primaryGreen),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(goat.goatCode, style: AppTheme.heading(size: 14)),
                                    const SizedBox(height: 3),
                                    Text('${goat.breed} · ${goat.gender}', style: AppTheme.body(size: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                  'Boarded ${_boardedFor(goat.checkInDate)}',
                                  style: AppTheme.body(size: 11, color: AppColors.darkGreen, weight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right, color: AppColors.textGrey),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
