import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/sports.dart';
import 'package:iptv_flutter/domain/live_score.dart';
import 'package:iptv_flutter/presentation/sports_hub_screen.dart';
import 'package:iptv_flutter/presentation/sports_match_graphics.dart';

void main() {
  test(
    'score snapshots preserve team artwork when home/away order reverses',
    () {
      final score = LiveScoreEvent(
        providerId: 'cricketdata',
        providerEventId: '1',
        sport: 'Cricket',
        homeTeamName: 'A',
        awayTeamName: 'B',
        homeLogo: 'https://example.com/a.png',
        awayLogo: 'https://example.com/b.png',
        fetchedAt: DateTime.now(),
        freshUntil: DateTime.now(),
      );
      expect(
        score.snapshot(reversed: true).homeLogo,
        'https://example.com/b.png',
      );
      expect(
        score.snapshot(reversed: true).awayLogo,
        'https://example.com/a.png',
      );
    },
  );
  for (final lite in [true, false]) {
    testWidgets(
      'separate teams, innings and overs fit compact card lite=$lite',
      (tester) async {
        final node = FocusNode();
        addTearDown(node.dispose);
        var opened = 0, followed = 0;
        final event = SportsEvent(
          id: 'c1',
          name: 'Patrons XI vs Sri Lanka',
          sportId: 'Cricket',
          homeTeamId: 'a',
          awayTeamId: 'b',
          homeTeamName: 'Pakistan Cricket Board Patrons XI',
          awayTeamName: 'Sri Lanka',
          scoreUpdate: SportsScoreSnapshot(
            providerId: 'cricketdata',
            providerEventId: 'c',
            fetchedAt: DateTime.now(),
            freshUntil: DateTime.now().add(const Duration(minutes: 2)),
            status: SportsEventStatus.live,
            homeScore: '151/8 (16) / 181/10 (54.3)',
            awayScore: '223/7 (58)',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 530,
                  height: lite ? 232 : 266,
                  child: SportsEventCard(
                    event: event,
                    lite: lite,
                    followed: false,
                    focusNode: node,
                    onOpen: () => opened++,
                    onFollow: () => followed++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('151/8'), findsOneWidget);
        expect(find.text('181/10'), findsOneWidget);
        expect(find.text('223/7'), findsOneWidget);
        expect(find.textContaining('54.3 overs'), findsOneWidget);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text('Watch Live'), findsNothing);
        expect(tester.takeException(), isNull);
        node.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          Focus.of(tester.element(find.text('Match Details'))).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(followed, 1);
        expect(opened, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('team artwork fallback shows initials without fabricated flags', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: SportsTeamIdentity(name: 'Patrons XI', lite: false),
          ),
        ),
      ),
    );
    expect(find.text('PX'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
