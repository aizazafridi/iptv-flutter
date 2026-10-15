import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/recorded_segments.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;

void main() {
  testWidgets(
    'series player lists and deletes recordings for its current episode only',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = RecordedSegments('account1', 'series:show:ep1');
      final second = RecordedSegments('account1', 'series:show:ep2');
      for (final store in [first, second]) {
        await store.load();
        store.begin(Duration(seconds: store == first ? 10 : 40));
        await store.finish(Duration(seconds: store == first ? 20 : 50));
      }
      const episode1 = Episode(
        id: 'ep1',
        title: 'Pilot',
        season: 1,
        number: 1,
        extension: 'mp4',
      );
      const episode2 = Episode(
        id: 'ep2',
        title: 'Next',
        season: 1,
        number: 2,
        extension: 'mp4',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/ep1'),
              title: 'Pilot',
            ),
            engineFactory: () => FakeEngine(),
            history: WatchHistory('account1'),
            item: const ContentItem(
              id: 'show',
              name: 'Series',
              type: ContentType.series,
            ),
            episode: episode1,
            episodes: const [episode1, episode2],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Recordings'));
      await tester.pumpAndSettle();
      expect(find.text('0:00:10 – 0:00:20'), findsOneWidget);
      expect(find.text('0:00:40 – 0:00:50'), findsNothing);
      await tester.tap(find.byTooltip('Delete all recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      final check1 = RecordedSegments('account1', 'series:show:ep1');
      final check2 = RecordedSegments('account1', 'series:show:ep2');
      await check1.load();
      await check2.load();
      expect(check1.entries, isEmpty);
      expect(check2.entries.length, 1);
      await tester.pumpWidget(const SizedBox());
      for (final store in [first, second, check1, check2]) {
        store.dispose();
      }
    },
  );
}
