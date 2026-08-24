import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_models.dart';
import 'customer_goat_registration_screen.dart';
import 'customer_palai_goat_profile_screen.dart';

class CustomerGoatListScreen extends StatefulWidget {
  final String customerId;
  final String? customerName;

  const CustomerGoatListScreen({
    super.key,
    required this.customerId,
    this.customerName,
  });

  @override
  State<CustomerGoatListScreen> createState() =>
      _CustomerGoatListScreenState();
}

class _CustomerGoatListScreenState
    extends State<CustomerGoatListScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final TextEditingController _searchController =
  TextEditingController();

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _onSearchChanged,
    );
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(
        _onSearchChanged,
      )
      ..dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    final query =
    _searchController.text
        .trim()
        .toLowerCase();

    if (query == _searchQuery) {
      return;
    }

    setState(() {
      _searchQuery = query;
    });
  }

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _goatsStream() {
    return _firestore
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .orderBy(
      'registrationDate',
      descending: true,
    )
        .snapshots();
  }

  // ===========================================================================
  // ADD GOAT
  // ===========================================================================

  Future<void> _addGoat() async {
    final result =
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerGoatRegistrationScreen(
              customerId:
              widget.customerId,
            ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (result is PalaiGoat) {
      final goatCode =
      result.goatCode.trim();

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            goatCode.isEmpty
                ? 'Goat registered successfully.'
                : 'Goat $goatCode registered and checked in successfully.',
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
        const Text('Customer Goats'),
      ),

      body:
      StreamBuilder<
          QuerySnapshot<
              Map<String, dynamic>>>(
        stream:
        _goatsStream(),

        builder:
            (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(
              snapshot.error,
            );
          }

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return _buildLoadingState();
          }

          final documents =
              snapshot.data?.docs ?? [];

          final goats =
          documents
              .map(
                (document) =>
                PalaiGoat.fromDoc(
                  document,
                ),
          )
              .toList();

          final filteredGoats =
          _filterGoats(goats);

          return RefreshIndicator(
            onRefresh:
            _refresh,

            child:
            CustomScrollView(
              physics:
              const AlwaysScrollableScrollPhysics(),

              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      0,
                    ),

                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [
                        _buildHeader(
                          goats.length,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        _buildSearchField(),

                        const SizedBox(
                          height: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                if (filteredGoats.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody:
                    false,

                    child:
                    _buildEmptyState(
                      hasGoats:
                      goats.isNotEmpty,
                    ),
                  )
                else
                  SliverPadding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      100,
                    ),

                    sliver:
                    SliverList(
                      delegate:
                      SliverChildBuilderDelegate(
                            (
                            context,
                            index,
                            ) {
                          final goat =
                          filteredGoats[
                          index];

                          return Padding(
                            padding:
                            const EdgeInsets.only(
                              bottom: 12,
                            ),

                            child:
                            _buildGoatCard(
                              goat,
                            ),
                          );
                        },

                        childCount:
                        filteredGoats.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),

      floatingActionButton:
      FloatingActionButton.extended(
        onPressed:
        _addGoat,

        icon:
        const Icon(Icons.add),

        label:
        const Text('Add Goat'),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader(
      int totalGoats,
      ) {
    final customerName =
    widget.customerName?.trim();

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        Text(
          customerName == null ||
              customerName.isEmpty
              ? 'Goats'
              : '$customerName\'s Goats',

          style:
          Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(
            fontWeight:
            FontWeight.w800,
          ),
        ),

        const SizedBox(
          height: 6,
        ),

        Text(
          totalGoats == 0
              ? 'No goats registered yet.'
              : '$totalGoats ${totalGoats == 1 ? 'goat' : 'goats'} registered',

          style:
          Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(
            color:
            Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  Widget _buildSearchField() {
    return TextField(
      controller:
      _searchController,

      textInputAction:
      TextInputAction.search,

      decoration:
      InputDecoration(
        hintText:
        'Search by goat code or breed',

        prefixIcon:
        const Icon(
          Icons.search,
        ),

        suffixIcon:
        _searchQuery.isEmpty
            ? null
            : IconButton(
          tooltip:
          'Clear search',

          onPressed: () {
            _searchController
                .clear();
          },

          icon:
          const Icon(
            Icons.clear,
          ),
        ),

        border:
        const OutlineInputBorder(),
      ),
    );
  }

  // ===========================================================================
  // FILTER
  // ===========================================================================

  List<PalaiGoat> _filterGoats(
      List<PalaiGoat> goats,
      ) {
    if (_searchQuery.isEmpty) {
      return goats;
    }

    return goats.where((goat) {
      final goatCode =
      goat.goatCode
          .trim()
          .toLowerCase();

      final name =
      goat.name
          .trim()
          .toLowerCase();

      final breed =
      goat.breed
          .trim()
          .toLowerCase();

      final tagNumber =
      goat.tagNumber
          .trim()
          .toLowerCase();

      return goatCode.contains(
        _searchQuery,
      ) ||
          name.contains(
            _searchQuery,
          ) ||
          breed.contains(
            _searchQuery,
          ) ||
          tagNumber.contains(
            _searchQuery,
          );
    }).toList();
  }

  // ===========================================================================
  // GOAT CARD
  // ===========================================================================

  Widget _buildGoatCard(
      PalaiGoat goat,
      ) {
    final status =
    goat.status.trim().isEmpty
        ? 'active'
        : goat.status;

    final isActive =
        status.toLowerCase() ==
            'active' ||
            status.toLowerCase() ==
                'checkedin';

    final displayName =
    goat.goatCode.trim().isNotEmpty
        ? goat.goatCode.trim()
        : goat.name.trim().isNotEmpty
        ? goat.name.trim()
        : goat.tagNumber.trim().isNotEmpty
        ? goat.tagNumber.trim()
        : 'Unnamed Goat';

    return Card(
      clipBehavior:
      Clip.antiAlias,

      child:
      InkWell(
        onTap: () {
          _openGoatProfile(
            goat,
          );
        },

        child:
        Padding(
          padding:
          const EdgeInsets.all(
            14,
          ),

          child:
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [
              _buildGoatAvatar(
                goat,
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child:
                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [
                        Expanded(
                          child:
                          Text(
                            displayName,

                            maxLines: 1,

                            overflow:
                            TextOverflow
                                .ellipsis,

                            style:
                            Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        _buildStatusChip(
                          status,
                          isActive,
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 6,
                    ),

                    Text(
                      _goatSubtitle(
                        goat,
                      ),

                      maxLines: 2,

                      overflow:
                      TextOverflow
                          .ellipsis,

                      style:
                      Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color:
                        Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Row(
                      children: [
                        if (goat.currentWeight !=
                            null)
                          _buildInfoItem(
                            Icons
                                .monitor_weight_outlined,
                            '${_formatWeight(goat.currentWeight!)} kg',
                          ),

                        if (goat.currentWeight !=
                            null)
                          const SizedBox(
                            width: 16,
                          ),

                        _buildInfoItem(
                          Icons
                              .calendar_today_outlined,
                          _formatDate(
                            goat.registrationDate,
                          ),
                        ),

                        const Spacer(),

                        const Icon(
                          Icons
                              .chevron_right,
                          size: 22,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // AVATAR
  // ===========================================================================

  Widget _buildGoatAvatar(
      PalaiGoat goat,
      ) {
    final imageUrl =
    goat.imageUrl?.trim();

    if (imageUrl != null &&
        imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius:
        BorderRadius.circular(
          14,
        ),

        child:
        Image.network(
          imageUrl,

          width: 68,
          height: 68,

          fit:
          BoxFit.cover,

          errorBuilder:
              (_, __, ___) {
            return _buildDefaultAvatar();
          },

          loadingBuilder:
              (
              context,
              child,
              loadingProgress,
              ) {
            if (loadingProgress ==
                null) {
              return child;
            }

            return _buildDefaultAvatar();
          },
        ),
      );
    }

    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 68,
      height: 68,

      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(
          14,
        ),

        color:
        Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),

      child:
      Icon(
        Icons.pets_outlined,

        size: 32,

        color:
        Theme.of(context)
            .colorScheme
            .onSurfaceVariant,
      ),
    );
  }

  // ===========================================================================
  // STATUS
  // ===========================================================================

  Widget _buildStatusChip(
      String status,
      bool isActive,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),

      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(
          20,
        ),

        color: isActive
            ? Theme.of(context)
            .colorScheme
            .primaryContainer
            : Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),

      child:
      Text(
        _formatStatus(
          status,
        ),

        style:
        Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }

  // ===========================================================================
  // INFO ITEM
  // ===========================================================================

  Widget _buildInfoItem(
      IconData icon,
      String text,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,

      children: [
        Icon(
          icon,
          size: 16,
          color:
          Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),

        const SizedBox(
          width: 5,
        ),

        Text(
          text,
          style:
          Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // EMPTY STATE
  // ===========================================================================

  Widget _buildEmptyState({
    required bool hasGoats,
  }) {
    if (hasGoats &&
        _searchQuery.isNotEmpty) {
      return Center(
        child:
        Padding(
          padding:
          const EdgeInsets.all(
            24,
          ),

          child:
          Column(
            mainAxisSize:
            MainAxisSize.min,

            children: [
              Icon(
                Icons.search_off,
                size: 52,
                color:
                Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),

              const SizedBox(
                height: 14,
              ),

              Text(
                'No goat found',
                style:
                Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                  fontWeight:
                  FontWeight.w700,
                ),
              ),

              const SizedBox(
                height: 6,
              ),

              Text(
                'Try searching with a different goat code, tag number or breed.',
                textAlign:
                TextAlign.center,
                style:
                Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child:
      Padding(
        padding:
        const EdgeInsets.all(
          24,
        ),

        child:
        Column(
          mainAxisSize:
          MainAxisSize.min,

          children: [
            Container(
              width: 84,
              height: 84,

              decoration:
              BoxDecoration(
                shape:
                BoxShape.circle,

                color:
                Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),

              child:
              Icon(
                Icons.pets_outlined,
                size: 42,
                color:
                Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),

            const SizedBox(
              height: 18,
            ),

            Text(
              'No goats registered',
              style:
              Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              'Start by registering the first goat for this customer.',
              textAlign:
              TextAlign.center,
              style:
              Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),

            const SizedBox(
              height: 20,
            ),

            FilledButton.icon(
              onPressed:
              _addGoat,

              icon:
              const Icon(
                Icons.add,
              ),

              label:
              const Text(
                'Register First Goat',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // LOADING
  // ===========================================================================

  Widget _buildLoadingState() {
    return const Center(
      child:
      CircularProgressIndicator(),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildErrorState(
      Object? error,
      ) {
    return Center(
      child:
      Padding(
        padding:
        const EdgeInsets.all(
          24,
        ),

        child:
        Column(
          mainAxisSize:
          MainAxisSize.min,

          children: [
            const Icon(
              Icons.error_outline,
              size: 52,
            ),

            const SizedBox(
              height: 14,
            ),

            const Text(
              'Unable to load goats.',
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              error?.toString() ??
                  'Unknown error',
              textAlign:
              TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  Future<void> _refresh() async {
    await Future<void>.delayed(
      const Duration(
        milliseconds: 300,
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  // ===========================================================================
  // PROFILE
  // ===========================================================================

  void _openGoatProfile(
      PalaiGoat goat,
      ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerPalaiGoatProfileScreen(
              customerId:
              widget.customerId,
              goat:
              goat,
            ),
      ),
    );
  }

  // ===========================================================================
  // SUBTITLE
  // ===========================================================================

  String _goatSubtitle(
      PalaiGoat goat,
      ) {
    final parts =
    <String>[];

    if (goat.breed.trim().isNotEmpty) {
      parts.add(
        goat.breed.trim(),
      );
    }

    if (goat.gender.trim().isNotEmpty) {
      parts.add(
        goat.gender.trim(),
      );
    }

    if (goat.color.trim().isNotEmpty) {
      parts.add(
        goat.color.trim(),
      );
    }

    if (goat.monthlyPackage
        .trim()
        .isNotEmpty) {
      parts.add(
        goat.monthlyPackage
            .trim(),
      );
    }

    if (parts.isEmpty) {
      return 'Palai goat';
    }

    return parts.join(' · ');
  }

  // ===========================================================================
  // FORMATTING
  // ===========================================================================

  String _formatWeight(
      double value,
      ) {
    if (value == value.roundToDouble()) {
      return value
          .toInt()
          .toString();
    }

    return value
        .toStringAsFixed(1);
  }

  String _formatDate(
      DateTime date,
      ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatStatus(
      String status,
      ) {
    if (status.trim().isEmpty) {
      return 'Active';
    }

    final normalized =
    status.trim();

    switch (normalized
        .toLowerCase()) {
      case 'active':
        return 'Active';

      case 'checkedin':
      case 'checked_in':
        return 'Checked In';

      case 'checkedout':
      case 'checked_out':
        return 'Checked Out';

      case 'inactive':
        return 'Inactive';

      default:
        return normalized;
    }
  }
}