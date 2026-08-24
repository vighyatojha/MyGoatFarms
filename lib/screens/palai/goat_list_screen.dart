import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';
import 'check_in_screen.dart';
import 'multi_goat_checkout_screen.dart';
import 'generate_report_screen.dart';
import 'health_records_screen.dart';

/// Lists every goat currently boarded in Palai.
///
/// From this screen the user can:
/// - Check in a new goat
/// - Open Health & Care
/// - Generate a Monthly Report
/// - Start the Final Report & Check-Out flow
///
/// The old CheckOutGoatScreen has intentionally been removed.
/// Final checkout now goes through MultiGoatCheckoutScreen.
class GoatListScreen extends StatefulWidget {
  const GoatListScreen({super.key});

  @override
  State<GoatListScreen> createState() => _GoatListScreenState();
}

enum _HealthFilter {
  all,
  healthy,
  watch,
  sick,
}

class _GoatListScreenState extends State<GoatListScreen> {
  String? _farmId;

  List<PalaiGoat> _goats = [];

  bool _initialLoading = true;
  bool _hasLoadedOnce = false;

  String? _errorMessage;

  StreamSubscription<List<PalaiGoat>>? _subscription;

  final TextEditingController _searchController =
  TextEditingController();

  String _query = '';

  _HealthFilter _filter = _HealthFilter.all;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      if (!mounted) return;

      setState(() {
        _query =
            _searchController.text.trim().toLowerCase();
      });
    });

    _loadFarm();
  }

  Future<void> _loadFarm() async {
    try {
      final id =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      setState(() {
        _farmId = id;
      });

      if (id == null) {
        setState(() {
          _initialLoading = false;
          _errorMessage = 'Farm could not be identified.';
        });
        return;
      }

      try {
        await FirestoreService.instance
            .backfillMissingGoatFarmIds(id);
      } catch (e) {
        debugPrint(
          'backfillMissingGoatFarmIds failed: $e',
        );
      }

      if (!mounted) return;

      _subscribeToGoats(id);
    } catch (e) {
      debugPrint('Could not load farm: $e');

      if (!mounted) return;

      setState(() {
        _initialLoading = false;
        _errorMessage =
        'Could not load farm information. Please try again.';
      });
    }
  }

  void _subscribeToGoats(
      String farmId, {
        VoidCallback? onSettled,
      }) {
    _subscription?.cancel();

    _subscription =
        FirestoreService.instance.allActiveGoatsStream(farmId).listen(
              (goats) {
            if (!mounted) return;

            setState(() {
              _goats = goats;
              _initialLoading = false;
              _hasLoadedOnce = true;
              _errorMessage = null;
            });

            onSettled?.call();
          },
          onError: (Object error) {
            if (!mounted) return;

            debugPrint(
              'GoatListScreen stream error: $error',
            );

            setState(() {
              _initialLoading = false;

              _errorMessage = _hasLoadedOnce
                  ? 'Live updates paused — pull down to retry.'
                  : "Couldn't load goats. Check your connection and retry.";
            });

            onSettled?.call();
          },
        );
  }

  Future<void> _handleRefresh() async {
    final farmId = _farmId;

    if (farmId == null) return;

    final completer = Completer<void>();

    _subscribeToGoats(
      farmId,
      onSettled: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await Future.wait([
      completer.future,
      Future.delayed(
        const Duration(milliseconds: 400),
      ),
    ]);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _boardedFor(DateTime arrivalDate) {
    final now = DateTime.now();

    // Normalize both dates to midnight so the calculation is based
    // on calendar dates rather than hours/minutes.
    final startDate = DateTime(
      arrivalDate.year,
      arrivalDate.month,
      arrivalDate.day,
    );

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    // Safety: never show a negative boarding duration.
    if (startDate.isAfter(today)) {
      return '0 days';
    }

    int months =
        (today.year - startDate.year) * 12 +
            (today.month - startDate.month);

    DateTime monthsAgo = DateTime(
      startDate.year,
      startDate.month + months,
      startDate.day,
    );

    if (monthsAgo.isAfter(today)) {
      months -= 1;

      monthsAgo = DateTime(
        startDate.year,
        startDate.month + months,
        startDate.day,
      );
    }

    final days =
        today.difference(monthsAgo).inDays;

    if (months <= 0) {
      return '$days day${days == 1 ? '' : 's'}';
    }

    if (days <= 0) {
      return '$months month${months == 1 ? '' : 's'}';
    }

    return '$months mo $days d';
  }

  Color _healthColor(String status) {
    switch (status) {
      case 'Sick':
        return AppColors.error;

      case 'Under Observation':
        return AppColors.warning;

      default:
        return AppColors.success;
    }
  }

  bool _matchesFilter(PalaiGoat goat) {
    switch (_filter) {
      case _HealthFilter.all:
        return true;

      case _HealthFilter.healthy:
        return goat.healthStatus != 'Sick' &&
            goat.healthStatus != 'Under Observation';

      case _HealthFilter.watch:
        return goat.healthStatus ==
            'Under Observation';

      case _HealthFilter.sick:
        return goat.healthStatus == 'Sick';
    }
  }

  List<PalaiGoat> _filtered(
      List<PalaiGoat> goats,
      ) {
    final sorted = [...goats]
      ..sort(
            (a, b) =>
            b.checkInDate.compareTo(a.checkInDate),
      );

    return sorted.where((goat) {
      if (!_matchesFilter(goat)) {
        return false;
      }

      if (_query.isEmpty) {
        return true;
      }

      return goat.goatCode
          .toLowerCase()
          .contains(_query) ||
          goat.breed
              .toLowerCase()
              .contains(_query) ||
          goat.color
              .toLowerCase()
              .contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 0,
        title: Text(
          'Goats in Palai',
          style: AppTheme.heading(size: 17),
        ),
      ),

      floatingActionButton:
      (_farmId == null || _goats.isEmpty)
          ? null
          : FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            fastRoute(
              const CheckInGoatScreen(),
            ),
          );
        },
        backgroundColor:
        AppColors.primaryGreen,
        icon: const Icon(
          Icons.add,
          color: Colors.white,
        ),
        label: const Text(
          'Check In',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      body: _farmId == null
          ? const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return _loadingSkeleton();
    }

    if (_goats.isEmpty && _errorMessage != null) {
      return _fullErrorState();
    }

    if (_goats.isEmpty) {
      return _emptyState();
    }

    final goats = _filtered(_goats);

    return Column(
      children: [
        _summaryHeader(_goats),

        _filterChips(),

        _searchBar(),

        if (_errorMessage != null)
          _inlineErrorBanner(),

        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: _handleRefresh,
            child: goats.isEmpty
                ? ListView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              children: [
                _noResultsState(),
              ],
            )
                : ListView.separated(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding:
              const EdgeInsets.fromLTRB(
                16,
                4,
                16,
                88,
              ),
              itemCount: goats.length,
              separatorBuilder:
                  (_, __) =>
              const SizedBox(height: 10),
              itemBuilder:
                  (context, index) {
                return _AnimatedListEntry(
                  index: index,
                  child:
                  _goatCard(goats[index]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _inlineErrorBanner() {
    return Container(
      margin:
      const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color:
        AppColors.warning.withOpacity(0.12),
        borderRadius:
        BorderRadius.circular(12),
        border: Border.all(
          color:
          AppColors.warning.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.warning,
            size: 18,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTheme.body(
                size: 12,
                color: AppColors.textDark,
              ),
            ),
          ),

          TextButton(
            onPressed: () {
              final farmId = _farmId;

              if (farmId != null) {
                _subscribeToGoats(farmId);
              }
            },
            style: TextButton.styleFrom(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 8,
              ),
            ),
            child: Text(
              'Retry',
              style: AppTheme.body(
                size: 12,
                color: AppColors.darkGreen,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fullErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color:
                AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 38,
                color: AppColors.error,
              ),
            ),

            const SizedBox(height: 18),

            Text(
              "Couldn't load goats",
              style: AppTheme.heading(size: 15),
            ),

            const SizedBox(height: 6),

            Text(
              _errorMessage ??
                  'Something went wrong. Please try again.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 13),
            ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () {
                final farmId = _farmId;

                if (farmId != null) {
                  _subscribeToGoats(farmId);
                }
              },
              icon: const Icon(
                Icons.refresh,
                size: 18,
              ),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(10),
                ),
                textStyle:
                const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingSkeleton() {
    return ListView(
      padding:
      const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16,
      ),
      physics:
      const NeverScrollableScrollPhysics(),
      children: [
        _skeletonBlock(
          height: 64,
          radius: 16,
        ),

        const SizedBox(height: 12),

        _skeletonBlock(
          height: 44,
          radius: 12,
        ),

        const SizedBox(height: 16),

        for (int i = 0; i < 5; i++) ...[
          _skeletonBlock(
            height: 78,
            radius: 14,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _skeletonBlock({
    required double height,
    required double radius,
  }) {
    return _Shimmer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _summaryHeader(
      List<PalaiGoat> allGoats,
      ) {
    final sick = allGoats
        .where(
          (g) => g.healthStatus == 'Sick',
    )
        .length;

    final watch = allGoats
        .where(
          (g) =>
      g.healthStatus ==
          'Under Observation',
    )
        .length;

    final healthy =
        allGoats.length - sick - watch;

    return Container(
      margin:
      const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        12,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
        BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color:
            AppColors.darkGreen
                .withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  '${allGoats.length}',
                  style: AppTheme.heading(
                    size: 26,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'goat${allGoats.length == 1 ? '' : 's'} boarded',
                  style: AppTheme.body(
                    size: 12,
                    color: Colors.white
                        .withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),

          _statPill(
            icon: Icons.favorite,
            color: Colors.white,
            label: '$healthy',
            sub: 'Healthy',
          ),

          const SizedBox(width: 10),

          _statPill(
            icon: Icons.visibility,
            color: Colors.white,
            label: '$watch',
            sub: 'Watch',
          ),

          const SizedBox(width: 10),

          _statPill(
            icon: Icons.local_hospital,
            color: Colors.white,
            label: '$sick',
            sub: 'Sick',
          ),
        ],
      ),
    );
  }

  Widget _statPill({
    required IconData icon,
    required Color color,
    required String label,
    required String sub,
  }) {
    return Column(
      children: [
        Container(
          padding:
          const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white
                .withOpacity(0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 15,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          label,
          style: AppTheme.body(
            size: 13,
            color: Colors.white,
            weight: FontWeight.w700,
          ),
        ),

        Text(
          sub,
          style: AppTheme.body(
            size: 9,
            color: Colors.white
                .withOpacity(0.85),
          ),
        ),
      ],
    );
  }

  Widget _filterChips() {
    final options =
    <(_HealthFilter, String, Color)>[
      (
      _HealthFilter.all,
      'All',
      AppColors.primaryGreen,
      ),
      (
      _HealthFilter.healthy,
      'Healthy',
      AppColors.success,
      ),
      (
      _HealthFilter.watch,
      'Watch',
      AppColors.warning,
      ),
      (
      _HealthFilter.sick,
      'Sick',
      AppColors.error,
      ),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection:
        Axis.horizontal,
        padding:
        const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          10,
        ),
        itemCount: options.length,
        separatorBuilder:
            (_, __) =>
        const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (
          value,
          label,
          color
          ) = options[index];

          final selected =
              _filter == value;

          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _filter = value;
              });
            },
            labelStyle: AppTheme.body(
              size: 12,
              color: selected
                  ? Colors.white
                  : AppColors.textDark,
              weight: FontWeight.w600,
            ),
            selectedColor: color,
            backgroundColor:
            Colors.white,
            side: BorderSide(
              color: selected
                  ? color
                  : AppColors.divider,
            ),
            shape:
            RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(18),
            ),
            visualDensity:
            VisualDensity.compact,
            materialTapTargetSize:
            MaterialTapTargetSize
                .shrinkWrap,
          );
        },
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ),
      child: Container(
        decoration:
        AppTheme.card(radius: 12),
        child: TextField(
          controller:
          _searchController,
          style: AppTheme.body(
            size: 13,
            color: AppColors.textDark,
          ),
          decoration:
          InputDecoration(
            hintText:
            'Search by goat ID, breed or color',
            hintStyle:
            AppTheme.body(size: 13),
            prefixIcon:
            const Icon(
              Icons.search,
              color:
              AppColors.textGrey,
              size: 20,
            ),
            suffixIcon:
            _query.isEmpty
                ? null
                : IconButton(
              icon:
              const Icon(
                Icons.close,
                color:
                AppColors.textGrey,
                size: 18,
              ),
              onPressed: () {
                _searchController
                    .clear();
              },
            ),
            border:
            InputBorder.none,
            contentPadding:
            const EdgeInsets
                .symmetric(
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openGoatActionSheet(
      PalaiGoat goat,
      ) async {
    final choice =
    await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
      Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration:
            const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            padding:
            const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration:
                  BoxDecoration(
                    color:
                    Colors.grey.shade300,
                    borderRadius:
                    BorderRadius.circular(
                      10,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration:
                      const BoxDecoration(
                        color:
                        AppColors.lightGreen,
                        shape:
                        BoxShape.circle,
                      ),
                      child:
                      const Icon(
                        Icons.pets,
                        color:
                        AppColors.primaryGreen,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          Text(
                            goat.goatCode,
                            style:
                            AppTheme.heading(
                              size: 16,
                            ),
                          ),

                          const SizedBox(
                            height: 3,
                          ),

                          Text(
                            '${goat.breed} · ${goat.gender}',
                            style:
                            AppTheme.body(
                              size: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                _actionTile(
                  icon: Icons
                      .medical_services_outlined,
                  color:
                  AppColors.primaryGreen,
                  title:
                  'Health & Care',
                  subtitle:
                  'Checkups, vaccination, hoof cutting, medicine and photos',
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      'health',
                    );
                  },
                ),

                const SizedBox(height: 10),

                _actionTile(
                  icon: Icons
                      .description_outlined,
                  color:
                  AppColors.info,
                  title:
                  'Monthly Report',
                  subtitle:
                  'Generate the goat progress report up to today',
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      'monthly',
                    );
                  },
                ),

                const SizedBox(height: 10),

                _actionTile(
                  icon: Icons
                      .logout_rounded,
                  color:
                  AppColors.error,
                  title:
                  'Final Report & Check-Out',
                  subtitle:
                  'Complete final report, billing and check-out',
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      'final',
                    );
                  },
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted ||
        choice == null) {
      return;
    }

    switch (choice) {
      case 'health':
        Navigator.of(context).push(
          fastRoute(
            HealthRecordsScreen(
              initialGoat: goat,
            ),
          ),
        );
        break;

      case 'monthly':
        Navigator.of(context).push(
          fastRoute(
            GenerateReportScreen(
              goat: goat,
            ),
          ),
        );
        break;

      case 'final':
      // IMPORTANT:
      // The old CheckOutGoatScreen has been
      // removed from the project.
      //
      // Final checkout now starts directly
      // in MultiGoatCheckoutScreen.
      //
      // We pass the current goat as the
      // initially selected goat and disable
      // selection so this Goat List action
      // remains for THIS goat only.
        Navigator.of(context).push(
          fastRoute(
            MultiGoatCheckoutScreen(
              customerId: goat.customerId,
              initialSelectedGoats: [goat],
              allowSelection: false,
            ),
          ),
        );
        break;
    }
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius:
        BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding:
          const EdgeInsets.all(15),
          decoration:
          BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(16),
            border: Border.all(
              color:
              AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration:
                BoxDecoration(
                  color: color
                      .withOpacity(0.10),
                  shape:
                  BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 22,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      title,
                      style:
                      AppTheme.body(
                        size: 14,
                        color:
                        AppColors
                            .textDark,
                        weight:
                        FontWeight.w700,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      subtitle,
                      style:
                      AppTheme.body(
                        size: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              const Icon(
                Icons
                    .chevron_right_rounded,
                color:
                AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goatCard(PalaiGoat goat) {
    final healthColor = _healthColor(goat.healthStatus);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openGoatActionSheet(goat),
        child: Container(
          width: double.infinity,
          decoration: AppTheme.card(radius: 18),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------------------
              // GOAT IMAGE
              // ------------------------------------------------------------
              _goatAvatar(
                goat: goat,
                healthColor: healthColor,
              ),

              const SizedBox(width: 12),

              // ------------------------------------------------------------
              // MAIN INFORMATION
              // ------------------------------------------------------------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goat.goatCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.heading(
                              size: 14,
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),

                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textGrey.withOpacity(0.7),
                        ),
                      ],
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '${goat.breed} · ${goat.gender}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.textGrey,
                      ),
                    ),

                    if (goat.pricing > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '₹${goat.pricing.toStringAsFixed(0)}/month',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 11,
                          color: AppColors.textGrey,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],

                    const SizedBox(height: 7),

                    // Health status
                    _healthBadge(
                      goat.healthStatus,
                      healthColor,
                    ),

                    const SizedBox(height: 7),

                    // IMPORTANT:
                    // This is now width-constrained and can never overflow.
                    _reportBadge(goat),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ------------------------------------------------------------
              // BOARDING DURATION
              // ------------------------------------------------------------
              _boardingBadge(goat),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goatAvatar({
    required PalaiGoat goat,
    required Color healthColor,
  }) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.lightGreen,
        border: Border.all(
          color: healthColor.withOpacity(0.55),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: healthColor.withOpacity(0.10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: goat.beforeImage != null
            ? Image.memory(
          goat.beforeImage!,
          fit: BoxFit.cover,
          width: 58,
          height: 58,
          errorBuilder: (_, __, ___) {
            return const Icon(
              Icons.pets,
              color: AppColors.primaryGreen,
              size: 26,
            );
          },
        )
            : const Icon(
          Icons.pets,
          color: AppColors.primaryGreen,
          size: 26,
        ),
      ),
    );
  }

  Widget _boardingBadge(PalaiGoat goat) {
    final duration = _boardedFor(
      goat.farmArrivalDate ?? goat.checkInDate,
    );

    return Container(
      constraints: const BoxConstraints(
        minWidth: 62,
        maxWidth: 76,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.08),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            duration,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              size: 10,
              color: AppColors.darkGreen,
              weight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            'boarded',
            style: AppTheme.body(
              size: 8,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthBadge(
      String status,
      Color healthColor,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: healthColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: healthColor,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 5),

          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 10,
                color: healthColor,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportBadge(PalaiGoat goat) {
    final generated =
        goat.reportStatus != 'Not Generated' &&
            goat.reportsCount > 0;

    final color = generated
        ? AppColors.info
        : AppColors.textGrey;

    final text = generated
        ? goat.reportStatus
        : 'No report yet';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: 28,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(
            generated
                ? Icons.description_outlined
                : Icons.description_outlined,
            size: 13,
            color: color,
          ),

          const SizedBox(width: 5),

          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: AppTheme.body(
                size: 10,
                color: color,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding:
          const EdgeInsets.only(
            top: 80,
          ),
          child: Center(
            child: Padding(
              padding:
              const EdgeInsets.all(24),
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration:
                    const BoxDecoration(
                      color:
                      AppColors
                          .lightGreen,
                      shape:
                      BoxShape.circle,
                    ),
                    child:
                    const Icon(
                      Icons.pets,
                      size: 42,
                      color:
                      AppColors
                          .primaryGreen,
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  Text(
                    'No goats currently boarded',
                    style:
                    AppTheme.heading(
                      size: 16,
                    ),
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Text(
                    'Goats you check in to Palai will show up here.',
                    textAlign:
                    TextAlign.center,
                    style:
                    AppTheme.body(
                      size: 13,
                    ),
                  ),

                  const SizedBox(
                    height: 22,
                  ),

                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).push(
                        fastRoute(
                          const CheckInGoatScreen(),
                        ),
                      );
                    },
                    icon:
                    const Icon(
                      Icons.add,
                      size: 18,
                    ),
                    label: const Text(
                      'Check In a Goat',
                    ),
                    style:
                    ElevatedButton
                        .styleFrom(
                      backgroundColor:
                      AppColors
                          .primaryGreen,
                      foregroundColor:
                      Colors.white,
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius
                            .circular(
                          10,
                        ),
                      ),
                      textStyle:
                      const TextStyle(
                        fontSize: 13,
                        fontWeight:
                        FontWeight
                            .w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _noResultsState() {
    return Padding(
      padding:
      const EdgeInsets.only(
        top: 60,
      ),
      child: Center(
        child: Padding(
          padding:
          const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration:
                const BoxDecoration(
                  color:
                  AppColors
                      .lightGreen,
                  shape:
                  BoxShape.circle,
                ),
                child:
                const Icon(
                  Icons.search_off,
                  size: 32,
                  color:
                  AppColors.textGrey,
                ),
              ),

              const SizedBox(
                height: 14,
              ),

              Text(
                _query.isEmpty
                    ? 'No goats match this filter'
                    : 'No goats match "${_searchController.text}"',
                style:
                AppTheme.body(
                  size: 13,
                ),
                textAlign:
                TextAlign.center,
              ),

              if (_filter !=
                  _HealthFilter.all ||
                  _query.isNotEmpty) ...[
                const SizedBox(
                  height: 10,
                ),

                TextButton(
                  onPressed: () {
                    setState(() {
                      _filter =
                          _HealthFilter.all;
                      _searchController
                          .clear();
                    });
                  },
                  child: Text(
                    'Clear filters',
                    style:
                    AppTheme.body(
                      size: 12,
                      color:
                      AppColors
                          .darkGreen,
                      weight:
                      FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated list entry.
class _AnimatedListEntry
    extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedListEntry({
    required this.index,
    required this.child,
  });

  @override
  State<_AnimatedListEntry>
  createState() =>
      _AnimatedListEntryState();
}

class _AnimatedListEntryState
    extends State<_AnimatedListEntry> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();

    final steps =
    widget.index > 8
        ? 8
        : widget.index;

    final delay = Duration(
      milliseconds: 25 * steps,
    );

    Future.delayed(
      delay,
          () {
        if (mounted) {
          setState(() {
            _visible = true;
          });
        }
      },
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return AnimatedSlide(
      duration:
      const Duration(
        milliseconds: 260,
      ),
      curve:
      Curves.easeOutCubic,
      offset: _visible
          ? Offset.zero
          : const Offset(0, 0.08),
      child:
      AnimatedOpacity(
        duration:
        const Duration(
          milliseconds: 260,
        ),
        opacity:
        _visible ? 1 : 0,
        child:
        widget.child,
      ),
    );
  }
}

/// Lightweight shimmer used for
/// loading skeletons.
class _Shimmer
    extends StatefulWidget {
  final Widget child;

  const _Shimmer({
    required this.child,
  });

  @override
  State<_Shimmer> createState() =>
      _ShimmerState();
}

class _ShimmerState
    extends State<_Shimmer>
    with
        SingleTickerProviderStateMixin {
  late final AnimationController
  _controller =
  AnimationController(
    vsync: this,
    duration:
    const Duration(
      milliseconds: 1200,
    ),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, child) {
        return ShaderMask(
          blendMode:
          BlendMode.srcATop,
          shaderCallback:
              (bounds) {
            final t =
                _controller.value;

            return LinearGradient(
              colors: [
                AppColors.lightGreen
                    .withOpacity(0.5),
                Colors.white,
                AppColors.lightGreen
                    .withOpacity(0.5),
              ],
              stops: const [
                0.35,
                0.5,
                0.65,
              ],
              begin: Alignment(
                -1 - t * 2,
                0,
              ),
              end: Alignment(
                1 - t * 2,
                0,
              ),
            ).createShader(
              bounds,
            );
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}