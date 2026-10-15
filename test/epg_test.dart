import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/epg_panel.dart';
import 'package:iptv_flutter/presentation/system_clock.dart';
import 'provider_test.dart' show FixtureClient;
import 'subtitle_test.dart' show FakeEngine;

void main() {
  test(
    'EPG decodes text and uses absolute timestamps, not server wall time',
    () async {
      final client = FixtureClient();
      final provider = XtreamProvider(client);
      const channel = ContentItem(
        id: '42',
        name: 'News',
        type: ContentType.live,
      );
      client.fixture = {
        'epg_listings': [
          {
            'title': base64.encode(utf8.encode('Morning news')),
            'description': base64.encode(utf8.encode('Headlines')),
            'start_timestamp': '1800000000',
            'stop_timestamp': 1800003600,
            'start': '1999-01-01 00:00:00',
          },
          {
            'title': 'Invalid',
            'start_timestamp': '1800000000',
            'stop_timestamp': 'oops',
          },
        ],
      };
      final result = await provider.getEpg(channel);
      expect(client.lastAction, 'get_simple_data_table');
      expect(client.lastParams['stream_id'], '42');
      expect(result.single.title, 'Morning news');
      expect(result.single.description, 'Headlines');
      final entry = result.single;
      expect(
        entry.start,
        DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true),
      );
      expect(entry.isCurrent(entry.start), isTrue);
      expect(entry.isCurrent(entry.start.toLocal()), isTrue);
      expect(entry.isCurrent(entry.end), isFalse);
      expect(
        entry.isCurrent(entry.start.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      client.fixture = {'epg_listings': []};
      expect(await provider.getEpg(channel), isEmpty);
      provider.dispose();
    },
  );

  testWidgets(
    'live player opens transparent right-side guide with current programme',
    (tester) async {
      final now = DateTime.now();
      final current = EpgProgramme(
        title: 'Current show',
        description: 'Live news',
        start: now.subtract(const Duration(minutes: 5)),
        end: now.add(const Duration(minutes: 25)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'News',
              isLive: true,
            ),
            engineFactory: () => FakeEngine(),
            loadEpg: () async => [
              EpgProgramme(
                title: 'Ended show',
                description: '',
                start: now.subtract(const Duration(hours: 2)),
                end: now.subtract(const Duration(hours: 1)),
              ),
              current,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Programme guide'));
      await tester.pumpAndSettle();
      expect(find.byType(EpgPanel), findsOneWidget);
      expect(find.text('Current show'), findsOneWidget);
      expect(find.text('Ended show'), findsNothing);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, Colors.transparent);
      expect(dialog.alignment, Alignment.centerRight);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('Close guide'));
      await tester.pumpAndSettle();
      expect(find.byType(EpgPanel), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clock reads local system time and guide has retry for failures',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SystemClock())),
      );
      final context = tester.element(find.byType(SystemClock));
      final locale = MaterialLocalizations.of(context);
      expect(
        find.text(locale.formatMediumDate(DateTime.now())),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SystemClock), findsOneWidget);
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EpgPanel(
            channelName: 'News',
            load: () async {
              if (attempts++ == 0) throw Exception('private URL');
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load the programme guide. Please retry.'),
        findsOneWidget,
      );
      expect(find.textContaining('private URL'), findsNothing);
      await tester.tap(find.byTooltip('Refresh guide'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load the programme guide. Please retry.'),
        findsNothing,
      );
      expect(find.textContaining('No current or upcoming'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
