import 'dart:async';

import 'package:flutter/material.dart';

import '../models/palai_models.dart';
import '../services/firestore_service.dart';

/// Live count of goats currently boarded in Palai for [farmId] — the same
/// source `GoatListScreen` uses — shared by the "Total Goats" stat cards
/// on Home and on the Palai dashboard so they never disagree.
///
/// Two bugs this fixes (both present on the old stat cards):
///  1. Binding `FirestoreService.instance.allActiveGoatsStream(farmId)`
///     straight into a `StreamBuilder`'s `stream:` parameter creates a
///     *brand-new* stream on every rebuild of the parent screen. Each new
///     stream re-subscribes from scratch, so the count keeps flashing back
///     to "—"/0 and briefly showing whatever the fresh listener's first
///     (possibly stale, cache-only) snapshot happens to contain.
///  2. Even with a stream created once and reused, `allActiveGoatsStream`
///     is a `collectionGroup('goats')` query, which needs a Firestore
///     collection-group index. If that listener ever errors (index still
///     building, or a transient hiccup), `StreamBuilder` throws away
///     whatever good data it was holding and the card drops to "—" for
///     good — this is the same glitch documented in `goat_list_screen.dart`.
///
/// This widget owns a single subscription for the lifetime of [farmId],
/// re-subscribing only if [farmId] itself changes, and simply keeps the
/// last good count on screen if a later snapshot errors, instead of
/// wiping it out.
class GoatCountBuilder extends StatefulWidget {
  final String farmId;
  final Widget Function(BuildContext context, int? count) builder;

  const GoatCountBuilder({
    super.key,
    required this.farmId,
    required this.builder,
  });

  @override
  State<GoatCountBuilder> createState() => _GoatCountBuilderState();
}

class _GoatCountBuilderState extends State<GoatCountBuilder> {
  int? _count;
  StreamSubscription<List<PalaiGoat>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant GoatCountBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.farmId != widget.farmId) {
      _count = null;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription =
        FirestoreService.instance.allActiveGoatsStream(widget.farmId).listen(
              (goats) {
            if (!mounted) return;
            setState(() => _count = goats.length);
          },
          onError: (Object error) {
            // Keep whatever count we last had on screen — a transient listener
            // error (e.g. the collection-group index rebuilding) shouldn't
            // blank out a number that was already correct.
            debugPrint('GoatCountBuilder stream error: $error');
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _count);
}