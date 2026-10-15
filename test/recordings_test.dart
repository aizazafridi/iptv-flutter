import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/recorded_segments.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/recordings_panel.dart';
import 'subtitle_test.dart' show FakeEngine;

class SegmentEngine extends FakeEngine {
  final positions = StreamController<Duration>.broadcast();
  final seeks = <Duration>[];
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    positions.add(position);
  }

  @override
  Future<void> dispose() async {
    await positions.close();
  }
}

class InitiallyIgnoredSeekEngine extends SegmentEngine {
  bool ignoreAll = false;
  @override
  Future<void> seek(Duration target) async {
    seeks.add(target);
    positions.add((seeks.length == 1 || ignoreAll) ? Duration.zero : target);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'only time ranges are saved and isolated by account, title and episode',
    () async {
      final store = RecordedSegments('account1', 'series:12:episode1');
      await store.load();
      store.begin(const Duration(seconds: 10));
      await store.finish(const Duration(seconds: 20));
      final json =
          jsonDecode((await store.storage.read(key: store.key))!) as List;
      expect(json.single, {'start': 10000, 'end': 20000});
      final again = RecordedSegments('account1', 'series:12:episode1');
      await again.load();
      expect(again.entries.single.label, '0:00:10 – 0:00:20');
      for (final other in [
        RecordedSegments('account2', 'series:12:episode1'),
        RecordedSegments('account1', 'series:12:episode2'),
        RecordedSegments('account1', 'movies:12:'),
      ]) {
        await other.load();
        expect(other.entries, isEmpty);
        other.dispose();
      }
      store.begin(const Duration(seconds: 30));
      await expectLater(
        store.finish(const Duration(seconds: 29)),
        throwsStateError,
      );
      expect(store.entries.length, 1);
      store.dispose();
      again.dispose();
    },
  );

  testWidgets(
    'record toggle saves range; selection loops and Stop returns to normal playback',
    (tester) async {
      final engine = SegmentEngine();
      const movie = ContentItem(
        id: '12',
        name: 'Movie',
        type: ContentType.movies,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/movie'),
              title: 'Movie',
            ),
            engineFactory: () => engine,
            item: movie,
            history: WatchHistory('account1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.positions.add(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byTooltip('Record'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Stop recording'), findsOneWidget);
      engine.positions.add(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Record'), findsOneWidget);
      expect(find.text('Recording saved.'), findsOneWidget);
      engine.positions.add(const Duration(seconds: 90));
      await tester.pump();
      await tester.tap(find.byTooltip('Recordings'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingsPanel), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, Colors.transparent);
      expect(dialog.alignment, Alignment.topRight);
      expect(find.text('0:00:10 – 0:00:20'), findsOneWidget);
      await tester.tap(find.text('Recording 1'));
      await tester.pumpAndSettle();
      expect(engine.seeks.last, const Duration(seconds: 10));
      expect(tester.widget<Slider>(find.byType(Slider)).min, 10000);
      expect(tester.widget<Slider>(find.byType(Slider)).max, 20000);
      engine.positions.add(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(engine.seeks, [
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ]);
      await tester.tap(find.byTooltip('Stop recording playback'));
      await tester.pumpAndSettle();
      expect(engine.seeks.last, const Duration(seconds: 90));
      expect(tester.widget<Slider>(find.byType(Slider)).min, 0);
      expect(tester.widget<Slider>(find.byType(Slider)).max, 600000);
      engine.positions.add(const Duration(seconds: 95));
      await tester.pumpAndSettle();
      expect(engine.seeks.length, 3);
      // The panel's stop action also restores the main clip position.
      await tester.tap(find.byTooltip('Recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recording 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop recording playback'));
      await tester.pumpAndSettle();
      expect(engine.seeks.last, const Duration(seconds: 95));
      await tester.tap(find.byTooltip('Close recordings'));
      await tester.pumpAndSettle();
      final reloaded = RecordedSegments('account1', 'movies:12:');
      await reloaded.load();
      expect(reloaded.entries.length, 1);
      reloaded.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'deleting a loop or all ranges persists only for the selected title',
    () async {
      final store = RecordedSegments('account1', 'movies:12:');
      await store.load();
      for (var i = 1; i <= 2; i++) {
        store.begin(Duration(seconds: i * 10));
        await store.finish(Duration(seconds: i * 10 + 5));
      }
      final other = RecordedSegments('account1', 'series:12:ep2');
      await other.load();
      other.begin(Duration.zero);
      await other.finish(const Duration(seconds: 5));
      store.loop(store.entries.first);
      await store.delete(store.entries.first);
      expect(store.activeLoop, isNull);
      expect(store.entries.length, 1);
      final reload = RecordedSegments('account1', 'movies:12:');
      await reload.load();
      expect(reload.entries.length, 1);
      await store.delete(null);
      final empty = RecordedSegments('account1', 'movies:12:');
      await empty.load();
      expect(empty.entries, isEmpty);
      final untouched = RecordedSegments('account1', 'series:12:ep2');
      await untouched.load();
      expect(untouched.entries.length, 1);
      for (final item in [store, other, reload, empty, untouched]) {
        item.dispose();
      }
    },
  );

  testWidgets(
    'recordings panel offers single deletion and confirmed delete all',
    (tester) async {
      final store = RecordedSegments('account1', 'movies:12:');
      await store.load();
      for (var i = 0; i < 3; i++) {
        store.begin(Duration(seconds: i * 10));
        await store.finish(Duration(seconds: i * 10 + 5));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingsPanel(segments: store, title: 'Movie'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete recording 2'));
      await tester.pumpAndSettle();
      expect(store.entries.length, 2);
      expect(store.entries.last.start, const Duration(seconds: 20));
      await tester.tap(find.byTooltip('Delete all recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.entries.length, 2);
      await tester.tap(find.byTooltip('Delete all recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(find.text('No recordings for this selection.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('recordings button is at the bottom beside episodes', (
    tester,
  ) async {
    const episode = Episode(
      id: 'ep1',
      title: 'Pilot',
      season: 1,
      number: 1,
      extension: 'mp4',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          source: PlaybackSource(
            uri: Uri.parse('https://example.com/episode'),
            title: 'Series',
          ),
          engineFactory: () => FakeEngine(),
          history: WatchHistory('account1'),
          item: const ContentItem(
            id: 'series1',
            name: 'Series',
            type: ContentType.series,
          ),
          episode: episode,
          episodes: const [episode],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final recording = tester.getCenter(find.byTooltip('Recordings'));
    final episodes = tester.getCenter(find.byTooltip('Episodes'));
    expect(recording.dy, episodes.dy);
    expect(recording.dx, greaterThan(600));
    expect(episodes.dx - recording.dx, lessThan(65));
    expect(recording.dy, greaterThan(450));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'recording retries when the first seek reports the episode beginning',
    (tester) async {
      final store = RecordedSegments('account1', 'series:show:ep1');
      await store.load();
      store.begin(const Duration(seconds: 10));
      await store.finish(const Duration(seconds: 20));
      store.dispose();
      final engine = InitiallyIgnoredSeekEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/ep1'),
              title: 'Episode',
            ),
            engineFactory: () => engine,
            history: WatchHistory('account1'),
            item: const ContentItem(
              id: 'show',
              name: 'Series',
              type: ContentType.series,
            ),
            episode: const Episode(
              id: 'ep1',
              title: 'Pilot',
              season: 1,
              number: 1,
              extension: 'mp4',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.positions.add(const Duration(seconds: 90));
      await tester.pump();
      await tester.tap(find.byTooltip('Recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recording 1'));
      await tester.pumpAndSettle();
      expect(engine.seeks.length, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(engine.seeks, [
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ]);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 10000);
      engine.positions.add(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(engine.seeks.last, const Duration(seconds: 10));
      await tester.tap(find.byTooltip('Stop recording playback'));
      await tester.pumpAndSettle();
      expect(engine.seeks.last, const Duration(seconds: 90));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsupported recording seeks stop retrying and show a clear error',
    (tester) async {
      final store = RecordedSegments('account1', 'movies:12:');
      await store.load();
      store.begin(const Duration(seconds: 10));
      await store.finish(const Duration(seconds: 20));
      store.dispose();
      final engine = InitiallyIgnoredSeekEngine()..ignoreAll = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/movie'),
              title: 'Movie',
            ),
            engineFactory: () => engine,
            history: WatchHistory('account1'),
            item: const ContentItem(
              id: '12',
              name: 'Movie',
              type: ContentType.movies,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.positions.add(const Duration(seconds: 90));
      await tester.pump();
      await tester.tap(find.byTooltip('Recordings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recording 1'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }
      expect(
        engine.seeks.where((s) => s == const Duration(seconds: 10)).length,
        3,
      );
      expect(find.byTooltip('Stop recording playback'), findsNothing);
      expect(
        find.text(
          'Could not seek to this recording. This stream may not support seeking.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('live TV has no recording controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          source: PlaybackSource(
            uri: Uri.parse('https://example.com/live'),
            title: 'Live',
            isLive: true,
          ),
          engineFactory: () => FakeEngine(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Record'), findsNothing);
    expect(find.byTooltip('Recordings'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
