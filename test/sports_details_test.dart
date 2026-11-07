import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_flutter/domain/sports.dart';
import 'package:iptv_flutter/application/sports_repository.dart';
import 'package:iptv_flutter/data/the_sports_db_provider.dart';
import 'package:iptv_flutter/presentation/sports_event_details_layout.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'F1 upcoming includes race after practice despite missing league catalogue',
    () async {
      final requests = <Uri>[];
      Map<String, Object> fixture(String id, String date) => {
        'idEvent': id,
        'strEvent': id,
        'strSport': 'Motorsport',
        'idLeague': '4370',
        'strTimestamp': '${date}T17:00:00Z',
        'strStatus': 'NS',
      };
      final api = TheSportsDbProvider(
        wait: (_) async {},
        client: MockClient((r) async {
          requests.add(r.url);
          return http.Response(
            jsonEncode({
              'events': r.url.path.contains('eventsnextleague')
                  ? [fixture('Practice', '2026-11-07')]
                  : r.url.queryParameters['d'] == '2026-11-08'
                  ? [fixture('Grand Prix', '2026-11-08')]
                  : [],
            }),
            200,
          );
        }),
      );
      final rows = await SportsRepository(
        api,
      ).upcomingMotorsport(DateTime.utc(2026, 11, 6), []);
      expect(rows.map((e) => e.name), ['Practice', 'Grand Prix']);
      expect(requests.length, 9);
      expect(
        requests
            .where((r) => r.path.contains('eventsday'))
            .every((r) => r.queryParameters['l'] == '4370'),
        isTrue,
      );
      api.dispose();
    },
  );
  for (final sport in ['Cricket', 'Soccer']) {
    for (final lite in [false, true]) {
      testWidgets('$sport match details fit TV and small window lite=$lite', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final event = SportsEvent(
          id: '1',
          name: 'Bangladesh vs West Indies',
          sportId: sport,
          homeTeamName: 'Bangladesh',
          awayTeamName: 'West Indies',
          homeScore: sport == 'Cricket' ? '88/3 (40.0) / 101/4 (30)' : '2',
          awayScore: sport == 'Cricket' ? '356/10 (106.4)' : '0',
          venue: 'Stadium',
          leagueName: 'International',
          season: '2026',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SportsEventDetailsLayout(
                event: event,
                lite: lite,
                status: 'Finished',
                date: '6/11/2026',
                attribution: 'Test data',
                actions: FilledButton(
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Find Channels'),
                ),
                channels: const Text(
                  'No confirmed channel found for this match.',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('88/3'),
          sport == 'Cricket' ? findsWidgets : findsNothing,
        );
        expect(find.text('LIVE'), findsNothing);
        expect(find.text('Match Information'), findsOneWidget);
        expect(
          find.text(sport == 'Cricket' ? 'Match Progress' : 'Match Summary'),
          findsOneWidget,
        );
        if (sport == 'Cricket') {
          await tester.ensureVisible(find.text('Scorecard'));
          await tester.tap(find.text('Scorecard'));
          await tester.pumpAndSettle();
          expect(find.text('Detailed Scorecard'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(640, 540);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (lite) expect(find.byType(Image), findsNothing);
      });
    }
  }
}
