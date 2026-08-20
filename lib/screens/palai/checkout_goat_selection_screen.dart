import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/fast_route.dart';

class CheckoutGoatSelectionScreen extends StatefulWidget {
  const CheckoutGoatSelectionScreen({super.key});

  @override
  State<CheckoutGoatSelectionScreen> createState() =>
      _CheckoutGoatSelectionScreenState();
}

class _CheckoutGoatSelectionScreenState
    extends State<CheckoutGoatSelectionScreen> {
  String? _farmId;

  List<PalaiGoat> _goats = [];
  final Set<String> _selectedGoatIds = {};

  bool _loading = true;
  String? _error;

  final TextEditingController _searchController =
  TextEditingController();

  String _search = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      if (!mounted) return;

      setState(() {
        _search =
            _searchController.text.trim().toLowerCase();
      });
    });

    _loadGoats();
  }

  Future<void> _loadGoats() async {
    try {
      final farmId =
      await FirestoreService.instance.currentFarmId();

      if (!mounted) return;

      if (farmId == null || farmId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Farm information could not be found.';
        });
        return;
      }

      setState(() {
        _farmId = farmId;
      });

      final goats = await FirestoreService.instance
          .allActiveGoatsStream(farmId)
          .first;

      if (!mounted) return;

      setState(() {
        _goats = goats;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint(
        'Checkout goat selection error: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error =
        'Could not load goats. Please check your connection and try again.';
      });
    }
  }

  List<PalaiGoat> get _filteredGoats {
    if (_search.isEmpty) {
      return _goats;
    }

    return _goats.where((goat) {
      final code =
      goat.goatCode.toLowerCase();

      final breed =
      goat.breed.toLowerCase();

      final color =
      goat.color.toLowerCase();

      return code.contains(_search) ||
          breed.contains(_search) ||
          color.contains(_search);
    }).toList();
  }

  void _toggleGoat(PalaiGoat goat) {
    setState(() {
      if (_selectedGoatIds.contains(goat.id)) {
        _selectedGoatIds.remove(goat.id);
      } else {
        _selectedGoatIds.add(goat.id);
      }
    });
  }

  void _selectAll() {
    final visibleGoats = _filteredGoats;

    setState(() {
      final allSelected = visibleGoats.every(
            (goat) => _selectedGoatIds.contains(goat.id),
      );

      if (allSelected) {
        for (final goat in visibleGoats) {
          _selectedGoatIds.remove(goat.id);
        }
      } else {
        for (final goat in visibleGoats) {
          _selectedGoatIds.add(goat.id);
        }
      }
    });
  }

  void _continue() {
    final selected = _goats
        .where(
          (goat) =>
          _selectedGoatIds.contains(goat.id),
    )
        .toList();

    if (selected.isEmpty) {
      _showMessage(
        'Please select at least one goat.',
        isError: true,
      );
      return;
    }

    /*
     * STEP 2 WILL BE CONNECTED HERE.
     *
     * We intentionally do not open the old
     * CheckOutGoatScreen because that screen
     * supports only one goat.
     *
     * The next screen will receive:
     *
     * List<PalaiGoat> selectedGoats
     *
     * and will handle:
     *
     * - final weight
     * - health
     * - photos
     * - delivery
     * - charges
     * - payment
     * - review
     */
    Navigator.of(context).push(
      fastRoute(
        CheckoutReviewPlaceholderScreen(
          goats: selected,
        ),
      ),
    );
  }

  void _showMessage(
      String message, {
        bool isError = false,
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? AppColors.error
            : AppColors.darkGreen,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleGoats = _filteredGoats;

    final allVisibleSelected =
        visibleGoats.isNotEmpty &&
            visibleGoats.every(
                  (goat) =>
                  _selectedGoatIds.contains(goat.id),
            );

    return Scaffold(
      backgroundColor: AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor:
        AppColors.paleGreen,
        elevation: 0,
        foregroundColor:
        AppColors.textDark,

        title: Text(
          'Select Goat(s)',
          style: AppTheme.heading(
            size: 17,
          ),
        ),
      ),

      bottomNavigationBar:
      _selectedGoatIds.isEmpty
          ? null
          : SafeArea(
        child: Container(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12,
          ),
          decoration:
          const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                blurRadius: 12,
                offset: Offset(0, -3),
                color: Color(
                  0x18000000,
                ),
              ),
            ],
          ),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _continue,
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor:
                Colors.white,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue with '
                        '${_selectedGoatIds.length} '
                        '${_selectedGoatIds.length == 1 ? 'Goat' : 'Goats'}',
                    style:
                    const TextStyle(
                      fontSize: 14,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 19,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      body: _loading
          ? const Center(
        child:
        CircularProgressIndicator(
          color:
          AppColors.primaryGreen,
        ),
      )
          : _error != null
          ? _errorState()
          : Column(
        children: [
          _header(),

          _searchBox(),

          if (_goats.isNotEmpty)
            _selectAllRow(
              allVisibleSelected,
            ),

          Expanded(
            child:
            visibleGoats.isEmpty
                ? _emptyState()
                : RefreshIndicator(
              color:
              AppColors.primaryGreen,
              onRefresh:
              _loadGoats,
              child:
              ListView.separated(
                physics:
                const AlwaysScrollableScrollPhysics(),
                padding:
                const EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  100,
                ),
                itemCount:
                visibleGoats.length,
                separatorBuilder:
                    (_, __) =>
                const SizedBox(
                  height: 10,
                ),
                itemBuilder:
                    (context, index) {
                  return _goatCard(
                    visibleGoats[
                    index],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      margin:
      const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        12,
      ),
      padding:
      const EdgeInsets.all(18),

      decoration: BoxDecoration(
        gradient:
        const LinearGradient(
          colors:
          AppColors.headerGradient,
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
        ),
        borderRadius:
        BorderRadius.circular(18),
      ),

      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration:
            BoxDecoration(
              color: Colors.white
                  .withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child:
            const Icon(
              Icons.logout_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Goat Check-Out',
                  style:
                  AppTheme.heading(
                    size: 16,
                    color:
                    Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  'Select one or more goats '
                      'to continue.',
                  style:
                  AppTheme.body(
                    size: 11,
                    color: Colors.white
                        .withOpacity(
                      0.9,
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

  Widget _searchBox() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        8,
      ),

      child: TextField(
        controller:
        _searchController,

        decoration:
        InputDecoration(
          hintText:
          'Search Goat ID, breed or color',
          hintStyle:
          AppTheme.body(
            size: 12,
            color:
            AppColors.textMuted,
          ),

          prefixIcon:
          const Icon(
            Icons.search,
            size: 20,
            color:
            AppColors.textMuted,
          ),

          suffixIcon:
          _search.isEmpty
              ? null
              : IconButton(
            onPressed:
                () {
              _searchController
                  .clear();
            },
            icon:
            const Icon(
              Icons.close,
              size: 18,
            ),
          ),

          filled: true,
          fillColor:
          Colors.white,

          contentPadding:
          const EdgeInsets
              .symmetric(
            vertical: 14,
            horizontal: 14,
          ),

          border:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(
              12,
            ),
            borderSide:
            BorderSide(
              color: AppColors
                  .divider,
            ),
          ),

          enabledBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(
              12,
            ),
            borderSide:
            BorderSide(
              color: AppColors
                  .divider,
            ),
          ),

          focusedBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(
              12,
            ),
            borderSide:
            const BorderSide(
              color:
              AppColors.primaryGreen,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectAllRow(
      bool allVisibleSelected,
      ) {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        16,
        2,
        16,
        8,
      ),

      child: Row(
        children: [
          Checkbox(
            value:
            allVisibleSelected,
            activeColor:
            AppColors.primaryGreen,
            onChanged: (_) =>
                _selectAll(),
          ),

          GestureDetector(
            onTap:
            _selectAll,
            child: Text(
              allVisibleSelected
                  ? 'Clear Selection'
                  : 'Select All',
              style:
              AppTheme.body(
                size: 12,
                color:
                AppColors.darkGreen,
                weight:
                FontWeight.w700,
              ),
            ),
          ),

          const Spacer(),

          Text(
            '${_selectedGoatIds.length} selected',
            style:
            AppTheme.body(
              size: 11,
              color:
              AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatCard(
      PalaiGoat goat,
      ) {
    final selected =
    _selectedGoatIds
        .contains(goat.id);

    final healthColor =
    _healthColor(
      goat.healthStatus,
    );

    return GestureDetector(
      onTap: () =>
          _toggleGoat(goat),

      child: AnimatedContainer(
        duration:
        const Duration(
          milliseconds: 180,
        ),

        padding:
        const EdgeInsets.all(12),

        decoration:
        BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.circular(
            16,
          ),

          border: Border.all(
            color: selected
                ? AppColors
                .primaryGreen
                : AppColors.divider,
            width:
            selected ? 1.8 : 1,
          ),

          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(
                selected
                    ? 0.08
                    : 0.04,
              ),
              blurRadius: 8,
              offset:
              const Offset(
                0,
                3,
              ),
            ),
          ],
        ),

        child: Row(
          children: [
            _photo(goat),

            const SizedBox(
              width: 12,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          goat.goatCode,
                          style:
                          AppTheme.heading(
                            size: 14,
                          ),
                        ),
                      ),

                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration:
                        BoxDecoration(
                          color: healthColor
                              .withOpacity(
                            0.10,
                          ),
                          borderRadius:
                          BorderRadius
                              .circular(
                            20,
                          ),
                        ),
                        child: Text(
                          goat.healthStatus,
                          style:
                          AppTheme.body(
                            size: 9,
                            color:
                            healthColor,
                            weight:
                            FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    '${goat.breed} • ${goat.gender}',
                    style:
                    AppTheme.body(
                      size: 11,
                      color:
                      AppColors.textMuted,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Text(
                    'Current weight: '
                        '${_weight(goat)} kg',
                    style:
                    AppTheme.body(
                      size: 11,
                    ),
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  Text(
                    'Checked in: '
                        '${_date(goat.checkInDate)}',
                    style:
                    AppTheme.body(
                      size: 9,
                      color:
                      AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            AnimatedContainer(
              duration:
              const Duration(
                milliseconds: 180,
              ),
              width: 30,
              height: 30,
              decoration:
              BoxDecoration(
                color: selected
                    ? AppColors
                    .primaryGreen
                    : Colors.white,
                shape:
                BoxShape.circle,
                border:
                Border.all(
                  color: selected
                      ? AppColors
                      .primaryGreen
                      : AppColors
                      .divider,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(
                Icons.check,
                color:
                Colors.white,
                size: 18,
              )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(
      PalaiGoat goat,
      ) {
    return Container(
      width: 70,
      height: 82,
      decoration:
      BoxDecoration(
        color:
        AppColors.lightGreen,
        borderRadius:
        BorderRadius.circular(
          12,
        ),
      ),
      clipBehavior:
      Clip.antiAlias,

      child:
      goat.beforeImage != null
          ? Image.memory(
        goat.beforeImage!,
        fit: BoxFit.cover,
      )
          : const Icon(
        Icons.pets,
        color:
        AppColors.primaryGreen,
        size: 30,
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(
          height: 90,
        ),

        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration:
                BoxDecoration(
                  color: AppColors
                      .primaryGreen
                      .withOpacity(
                    0.10,
                  ),
                  shape:
                  BoxShape.circle,
                ),
                child:
                const Icon(
                  Icons.search_off,
                  color:
                  AppColors.primaryGreen,
                  size: 34,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              Text(
                _search.isEmpty
                    ? 'No goats available'
                    : 'No goats found',
                style:
                AppTheme.heading(
                  size: 15,
                ),
              ),

              const SizedBox(
                height: 6,
              ),

              Text(
                _search.isEmpty
                    ? 'There are no active goats available for checkout.'
                    : 'Try searching with another Goat ID, breed or color.',
                textAlign:
                TextAlign.center,
                style:
                AppTheme.body(
                  size: 12,
                  color:
                  AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(
          24,
        ),

        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color:
              AppColors.error,
              size: 42,
            ),

            const SizedBox(
              height: 12,
            ),

            Text(
              'Could not load goats',
              style:
              AppTheme.heading(
                size: 15,
              ),
            ),

            const SizedBox(
              height: 7,
            ),

            Text(
              _error!,
              textAlign:
              TextAlign.center,
              style:
              AppTheme.body(
                size: 12,
                color:
                AppColors.textMuted,
              ),
            ),

            const SizedBox(
              height: 18,
            ),

            ElevatedButton.icon(
              onPressed:
              _loadGoats,
              icon:
              const Icon(
                Icons.refresh,
                size: 18,
              ),
              label:
              const Text('Retry'),
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                AppColors
                    .primaryGreen,
                foregroundColor:
                Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _weight(
      PalaiGoat goat,
      ) {
    return goat.currentWeight ??
        goat.weightAtCheckIn;
  }

  String _date(
      DateTime date,
      ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Color _healthColor(
      String status,
      ) {
    switch (status) {
      case 'Sick':
        return AppColors.error;

      case 'Under Observation':
        return AppColors.warning;

      default:
        return AppColors.success;
    }
  }
}


// ======================================================================
// TEMPORARY STEP-2 PLACEHOLDER
// ======================================================================
//
// This is deliberately included in this file for now so you can run and
// test Step 1 immediately.
//
// Once we build the real checkout review screen, this class will be
// replaced by the actual multi-goat checkout workflow.
//

class CheckoutReviewPlaceholderScreen
    extends StatelessWidget {
  final List<PalaiGoat> goats;

  const CheckoutReviewPlaceholderScreen({
    super.key,
    required this.goats,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      AppColors.paleGreen,

      appBar: AppBar(
        backgroundColor:
        AppColors.paleGreen,
        elevation: 0,
        foregroundColor:
        AppColors.textDark,
        title: Text(
          'Checkout Review',
          style:
          AppTheme.heading(
            size: 17,
          ),
        ),
      ),

      body: Column(
        children: [
          Container(
            margin:
            const EdgeInsets.all(
              16,
            ),
            padding:
            const EdgeInsets.all(
              16,
            ),
            decoration:
            AppTheme.card(
              radius: 16,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color:
                  AppColors
                      .primaryGreen,
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    '${goats.length} '
                        '${goats.length == 1 ? 'goat' : 'goats'} selected',
                    style:
                    AppTheme.heading(
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.separated(
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 16,
              ),
              itemCount:
              goats.length,
              separatorBuilder:
                  (_, __) =>
              const SizedBox(
                height: 10,
              ),
              itemBuilder:
                  (context, index) {
                final goat =
                goats[index];

                return Container(
                  padding:
                  const EdgeInsets
                      .all(
                    14,
                  ),
                  decoration:
                  AppTheme.card(
                    radius: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration:
                        BoxDecoration(
                          color: AppColors
                              .lightGreen,
                          borderRadius:
                          BorderRadius
                              .circular(
                            10,
                          ),
                        ),
                        child:
                        goat.beforeImage !=
                            null
                            ? ClipRRect(
                          borderRadius:
                          BorderRadius.circular(
                            10,
                          ),
                          child:
                          Image.memory(
                            goat.beforeImage!,
                            fit:
                            BoxFit.cover,
                          ),
                        )
                            : const Icon(
                          Icons.pets,
                          color:
                          AppColors.primaryGreen,
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Expanded(
                        child:
                        Column(
                          crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                          children: [
                            Text(
                              goat.goatCode,
                              style:
                              AppTheme.heading(
                                size: 13,
                              ),
                            ),
                            const SizedBox(
                              height: 3,
                            ),
                            Text(
                              '${goat.breed} • '
                                  '${goat.gender}',
                              style:
                              AppTheme.body(
                                size: 11,
                                color:
                                AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          SafeArea(
            child: Padding(
              padding:
              const EdgeInsets.all(
                16,
              ),
              child:
              const Text(
                'Step 2 checkout form will be connected here next.',
                textAlign:
                TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}