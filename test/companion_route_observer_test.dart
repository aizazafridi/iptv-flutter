import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/companion_route_observer.dart';

class ClosingPlayer extends StatefulWidget {
  final Completer<void> shutdown;
  final VoidCallback onDispose;
  const ClosingPlayer({
    super.key,
    required this.shutdown,
    required this.onDispose,
  });
  @override
  State<ClosingPlayer> createState() => _ClosingPlayerState();
}

class _ClosingPlayerState extends State<ClosingPlayer> {
  @override
  void dispose() {
    widget.onDispose();
    CompanionRouteObserver.trackCleanup(widget.shutdown.future);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const PopScope(canPop: false, child: Scaffold(body: Text('Old player')));
}

void main() {
  testWidgets(
    'phone switching removes old title/player and waits for native shutdown',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final observer = CompanionRouteObserver();
      late Route<dynamic> dashboard;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) {
              dashboard = ModalRoute.of(context)!;
              return const Scaffold(body: Text('Dashboard'));
            },
          ),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Old details')),
        ),
      );
      await tester.pumpAndSettle();
      final shutdown = Completer<void>();
      var disposed = false;
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ClosingPlayer(
            shutdown: shutdown,
            onDispose: () => disposed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      var completed = false;
      final switching = observer
          .returnTo(dashboard)
          .then((_) => completed = true);
      await tester.pumpAndSettle();
      expect(disposed, true);
      expect(completed, false);
      expect(find.text('Old details'), findsNothing);
      expect(find.text('Old player'), findsNothing);
      shutdown.complete();
      await tester.pumpAndSettle();
      await switching;
      expect(completed, true);
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('New title')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New title'), findsOneWidget);
      // A second remote selection works without manually backing out of the title.
      final again = observer.returnTo(dashboard);
      await tester.pumpAndSettle();
      await again;
      expect(find.text('Dashboard'), findsOneWidget);
      expect(CompanionRouteObserver.of(nav.currentState!), same(observer));
    },
  );
}
