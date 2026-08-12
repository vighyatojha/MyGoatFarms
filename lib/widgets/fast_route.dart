import 'package:flutter/material.dart';

/// A fast, light-weight replacement for [MaterialPageRoute].
///
/// The stock Material page route runs a ~300ms full-width slide, which on
/// top of every screen's own entrance animations made navigation feel
/// sluggish. This is a quick fade + gentle upward slide (~180ms) — enough
/// to signal a transition happened without making the user wait for it.
///
/// Usage:
/// ```dart
/// Navigator.of(context).push(fastRoute(const AddCustomerScreen()));
/// ```
Route<T> fastRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}