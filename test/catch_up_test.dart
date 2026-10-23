import 'package:iptv_flutter/data/locked_provider.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/xtream/xtream_client.dart';
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/catch_up_panel.dart';

class ArchiveClient extends XtreamClient {
  int archive = 1;
  ArchiveClient()
    : super(
        const ProviderConfig(
          providerId: 'xtream',
          server: 'https://example.com/prefix',
          username: 'user name',
          password: 'p/a',
        ),
      );
  @override
  Future<dynamic> request({
    String? action,
    Map<String, String> params = const {},
  }) async {
    if (action == 'get_live_streams') {
      return [
        {'stream_id': 42, 'tv_archive': archive, 'tv_archive_duration': 7},
      ];
    }
    final now = DateTime.now().toUtc();
    Map<String, dynamic> row(int days, int enabled) {
      final start = now.subtract(Duration(days: days, hours: 2));
      return {
        'title': 'Programme $days', 'description': '', 'has_archive': enabled,
        'start_timestamp': start.millisecondsSinceEpoch ~/ 1000,
        'stop_timestamp':
            start.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        // Server wall clock deliberately differs from device time.
        'start': '2026-10-20 21:30:00',
      };
    }

    return {
      'epg_listings': [row(1, 1), row(9, 1), row(2, 0), row(-1, 1)],
    };
  }
}

const channel = ContentItem(id: '42', name: 'Channel', type: ContentType.live);
void main() {
  testWidgets(
    'catch-up icon works through locked provider and disables unsupported channels',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final client = ArchiveClient();
      addTearDown(client.dispose);
      final provider = LockedProvider(
        XtreamProvider(client),
        CategoryLocks('catch-up-icon'),
      );
      Future<void> show(int key) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerScreen(
              key: ValueKey(key),
              source: PlaybackSource(
                uri: Uri.parse('https://example.com/live'),
                title: 'Channel',
                isLive: true,
              ),
              item: channel,
              provider: provider,
              engineFactory: FakeEngine.new,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(1);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Catch-up',
              ),
            )
            .onPressed,
        isNotNull,
      );
      client.archive = 0;
      await show(2);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Catch-up unavailable for this channel',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'archive filters availability and uses provider clock and encoded credentials',
    () async {
      final client = ArchiveClient();
      addTearDown(client.dispose);
      final provider = XtreamProvider(client);
      final entries = await provider.getCatchUp(channel);
      expect(entries, hasLength(1));
      final source = await provider.resolveCatchUp(channel, entries.single);
      expect(source.isLive, isFalse);
      expect(source.uri.pathSegments, [
        'prefix',
        'timeshift',
        'user name',
        'p/a',
        '60',
        '2026-10-20:21-30',
        '42.ts',
      ]);
      expect(source.title, contains('Programme 1'));
      client.archive = 0;
      expect(await provider.getCatchUp(channel), isEmpty);
      expect(
        () => client.catchUp('../42', '2026-10-20:21-30', 60),
        throwsA(isA<ProviderException>()),
      );
    },
  );
  testWidgets(
    'catch-up picker selects a programme and reports empty archives',
    (tester) async {
      final entry = EpgProgramme(
        title: 'Evening news',
        description: '',
        start: DateTime(2026, 10, 20, 20),
        end: DateTime(2026, 10, 20, 21),
      );
      EpgProgramme? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showDialog<EpgProgramme>(
                  context: context,
                  builder: (_) => CatchUpPanel(
                    channelName: 'Channel',
                    load: () async => [entry],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evening news'));
      await tester.pumpAndSettle();
      expect(selected, same(entry));
      await tester.pumpWidget(
        MaterialApp(
          home: CatchUpPanel(channelName: 'Empty', load: () async => []),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No catch-up programmes are available for this channel.'),
        findsOneWidget,
      );
    },
  );
}
