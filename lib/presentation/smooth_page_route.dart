import 'package:flutter/material.dart';

/// Both screens move together; content stays painted rather than swapping abruptly.
class SmoothPageRoute<T> extends MaterialPageRoute<T> {
  SmoothPageRoute({
    required super.builder,
    super.settings,
    super.allowSnapshotting = false,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final incoming = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final outgoing = secondaryAnimation.drive(
      CurveTween(curve: Curves.easeInOutCubic),
    );
    return SlideTransition(
      position: outgoing.drive(
        Tween(begin: Offset.zero, end: const Offset(-0.04, 0)),
      ),
      child: FadeTransition(
        opacity: outgoing.drive(Tween(begin: 1.0, end: 0.75)),
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position: incoming.drive(
              Tween(begin: const Offset(0.12, 0), end: Offset.zero),
            ),
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}
