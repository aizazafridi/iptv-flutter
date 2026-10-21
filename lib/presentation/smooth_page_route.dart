import 'package:flutter/material.dart';

/// A brief fade keeps navigation immediate without moving the whole screen.
class SmoothPageRoute<T> extends MaterialPageRoute<T> {
  SmoothPageRoute({
    required super.builder,
    super.settings,
    super.allowSnapshotting = true,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
      child: RepaintBoundary(child: child),
    );
  }
}
