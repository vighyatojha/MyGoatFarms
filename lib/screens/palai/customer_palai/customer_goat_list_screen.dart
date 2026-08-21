import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_goat.dart';
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
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text
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
  // FIRESTORE QUERY
  // ===========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _goatsStream() {
    return _firestore
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .orderBy('registrationDate',
        descending: true)
        .snapshots();
  }

  // ===========================================================================
  // ADD GOAT
  // ===========================================================================

  Future<void> _addGoat() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerGoatRegistrationScreen(
              customerId: widget.customerId,
            ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (result is PalaiGoat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.name} was added successfully.',
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
        title: const Text('Customer Goats'),
      ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _goatsStream(),
        builder: (context, snapshot) {
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

          final goats = documents
              .map(
                (document) =>
                PalaiGoat.fromDoc(document),
          )
              .toList();

          final filteredGoats =
          _filterGoats(goats);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
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
                        _buildHeader(goats.length),

                        const SizedBox(height: 16),

                        _buildSearchField(),

                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),

                if (filteredGoats.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child:
                    _buildEmptyState(
                      hasGoats: goats.isNotEmpty,
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
                    sliver: SliverList(
                      delegate:
                      SliverChildBuilderDelegate(
                            (context, index) {
                          final goat =
                          filteredGoats[index];

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
        onPressed: _addGoat,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'Add Goat',
        ),
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
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(
            fontWeight:
            FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          totalGoats == 0
              ? 'No goats registered yet.'
              : '$totalGoats ${totalGoats == 1 ? 'goat' : 'goats'} registered',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
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
  // SEARCH
  // ===========================================================================

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction:
      TextInputAction.search,
      decoration: InputDecoration(
        hintText:
        'Search by goat name or tag',
        prefixIcon: const Icon(
          Icons.search,
        ),
        suffixIcon:
        _searchQuery.isEmpty
            ? null
            : IconButton(
          tooltip: 'Clear search',
          onPressed: () {
            _searchController.clear();
          },
          icon: const Icon(
            Icons.clear,
          ),
        ),
        border:
        const OutlineInputBorder(),
      ),
    );
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
            'active';

    return Card(
      clipBehavior:
      Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openGoatProfile(goat);
        },
        child: Padding(
          padding:
          const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              _buildGoatAvatar(goat),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            goat.name.isEmpty
                                ? 'Unnamed Goat'
                                : goat.name,
                            maxLines: 1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style: Theme.of(
                              context,
                            )
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
                      _goatSubtitle(goat),
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: Theme.of(
                          context,
                        )
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
        BorderRadius.circular(14),
        child: Image.network(
          imageUrl,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) {
            return _buildDefaultAvatar(
              goat,
            );
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

            return _buildDefaultAvatar(
              goat,
            );
          },
        ),
      );
    }

    return _buildDefaultAvatar(
      goat,
    );
  }

  Widget _buildDefaultAvatar(
      PalaiGoat goat,
      ) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(14),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Icon(
        Icons.pets_outlined,
        size: 32,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant,
      ),
    );
  }

  // ===========================================================================
  // STATUS CHIP
  // ===========================================================================

  Widget _buildStatusChip(
      String status,
      bool isActive,
      ) {
    final label = _formatStatus(
      status,
    );

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(20),
        color: isActive
            ? Theme.of(context)
            .colorScheme
            .primaryContainer
            : Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: Theme.of(context)
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
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: Theme.of(context)
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
        child: Padding(
          padding:
          const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 52,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
              const SizedBox(
                height: 14,
              ),
              Text(
                'No goat found',
                style: Theme.of(context)
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
                'Try searching with a different name or tag number.',
                textAlign:
                TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration:
              BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
              child: Icon(
                Icons.pets_outlined,
                size: 42,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),
            const SizedBox(
              height: 18,
            ),
            Text(
              'No goats registered',
              style: Theme.of(context)
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
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),
            const SizedBox(
              height: 20,
            ),
            FilledButton.icon(
              onPressed: _addGoat,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
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
      child: CircularProgressIndicator(),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildErrorState(
      Object? error,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 52,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Unable to load goats',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight:
                FontWeight.w700,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              _errorMessage(error),
              textAlign:
              TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),
            const SizedBox(
              height: 18,
            ),
            FilledButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
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
      final name =
      goat.name.toLowerCase();

      final tag =
      goat.tagNumber.toLowerCase();

      final breed =
      goat.breed.toLowerCase();

      return name.contains(
        _searchQuery,
      ) ||
          tag.contains(
            _searchQuery,
          ) ||
          breed.contains(
            _searchQuery,
          );
    }).toList();
  }

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  Future<void> _refresh() async {
    // The StreamBuilder already receives
    // live Firestore updates.
    //
    // A short delay gives the RefreshIndicator
    // enough time to show the refresh interaction
    // without performing an unnecessary duplicate
    // Firestore request.
    await Future<void>.delayed(
      const Duration(
        milliseconds: 350,
      ),
    );
  }

  // ===========================================================================
  // GOAT PROFILE
  // ===========================================================================

  void _openGoatProfile(
      PalaiGoat goat,
      ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            CustomerPalaiGoatProfileScreen(
              goat: goat,
            ),
      ),
    );
  }

  // ===========================================================================
  // DISPLAY HELPERS
  // ===========================================================================

  String _goatSubtitle(
      PalaiGoat goat,
      ) {
    final parts = <String>[];

    if (goat.tagNumber.isNotEmpty) {
      parts.add(
        'Tag: ${goat.tagNumber}',
      );
    }

    if (goat.breed.isNotEmpty) {
      parts.add(
        goat.breed,
      );
    }

    if (goat.gender.isNotEmpty) {
      parts.add(
        goat.gender,
      );
    }

    if (parts.isEmpty) {
      return 'No additional details';
    }

    return parts.join(' • ');
  }

  String _formatWeight(
      double weight,
      ) {
    if (weight == weight.roundToDouble()) {
      return weight
          .toStringAsFixed(0);
    }

    return weight
        .toStringAsFixed(1);
  }

  String _formatDate(
      DateTime date,
      ) {
    final day =
    date.day.toString().padLeft(
      2,
      '0',
    );

    final month =
    date.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${date.year}';
  }

  String _formatStatus(
      String status,
      ) {
    final normalized =
    status.trim();

    if (normalized.isEmpty) {
      return 'Active';
    }

    switch (
    normalized.toLowerCase()) {
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
          return normalized
              .toUpperCase();
        }

        return normalized[0]
            .toUpperCase() +
            normalized.substring(1);
    }
  }

  String _errorMessage(
      Object? error,
      ) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to view these goats.';

        case 'failed-precondition':
          return 'Firestore needs an index for this query.';

        case 'unavailable':
          return 'The service is temporarily unavailable. Check your internet connection.';

        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
      }
    }

    return 'Something went wrong while loading the goats.';
  }
}