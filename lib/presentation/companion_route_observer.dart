import 'dart:async';
import 'package:flutter/widgets.dart';

/// Tracks the app navigator so explicit phone selections can replace a title
/// without leaving old players alive underneath the new route.
class CompanionRouteObserver extends NavigatorObserver {
  static final _cleanups = <Future<void>>{};
  static void trackCleanup(Future<void> work) {
    final safe = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _cleanups.add(safe);
    unawaited(safe.then((_) => _cleanups.remove(safe)));
  }

  static final _observers = Expando<CompanionRouteObserver>();
  static CompanionRouteObserver? of(NavigatorState navigator) =>
      _observers[navigator];
  final _routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (navigator != null) _observers[navigator!] = this;
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }

  Future<void> returnTo(Route<dynamic> dashboard) async {
    final index = _routes.indexOf(dashboard);
    final nav = navigator;
    if (index < 0 || nav == null) {
      throw StateError('Dashboard is no longer active');
    }
    final obsolete = _routes.skip(index + 1).toList().reversed.toList();
    for (final route in obsolete) {
      if (route.navigator != nav) continue;
      // A new selection on the paired phone explicitly replaces the old title.
      // removeRoute avoids sending Back through a player's exit confirmation.
      nav.removeRoute(route);
      if (route is TransitionRoute<dynamic>) await route.completed;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future.wait(_cleanups.toList());
  }
}
