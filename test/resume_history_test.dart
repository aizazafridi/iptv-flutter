import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/data/recorded_segments.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'widget_test.dart' show FakeProvider;

const movie = ContentItem(id: '42', name: 'Movie', type: ContentType.movies);
const series = ContentItem(id: '7', name: 'Series', type: ContentType.series);
const episode = Episode(
  id: 'ep1',
  title: 'Pilot',
  season: 1,
  number: 1,
  extension: 'mp4',
);
WatchEntry progress(ContentItem item, [Episode? ep]) => WatchEntry(
  item,
  ep,
  const Duration(minutes: 5),
  const Duration(minutes: 30),
  DateTime.utc(2026),
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'clearing selected or all history preserves movie/episode resume positions and recordings after reload',
    () async {
      for (final type in [ContentType.movies, ContentType.series, null]) {
        final scope = 'account-$type';
        final history = WatchHistory(scope);
        await history.save(progress(movie));
        await history.save(progress(series, episode));
        final recording = RecordedSegments(scope, 'series:7:ep1');
        await recording.load();
        recording.begin(const Duration(seconds: 10));
        await recording.finish(const Duration(seconds: 20));
        await history.clear(type: type);
        final reload = WatchHistory(scope);
        expect(
          (await reload.latest(movie))!.position,
          const Duration(minutes: 5),
        );
        expect(
          (await reload.latest(series, episode: episode))!.position,
          const Duration(minutes: 5),
        );
        expect((await reload.entries()).length, type == null ? 0 : 1);
        final saved = RecordedSegments(scope, 'series:7:ep1');
        await saved.load();
        expect(saved.entries.length, 1);
        expect(await WatchHistory('different-account').latest(movie), isNull);
        recording.dispose();
        saved.dispose();
      }
    },
  );
  test(
    'legacy history is migrated before clearing, and completed media has no resume',
    () async {
      const storage = FlutterSecureStorage();
      await storage.write(
        key: 'watch_history:legacy',
        value: jsonEncode([progress(movie).toJson()]),
      );
      await WatchHistory('legacy').clear();
      final reload = WatchHistory('legacy');
      expect(await reload.entries(), isEmpty);
      expect(
        (await reload.latest(movie))!.position,
        const Duration(minutes: 5),
      );
      await reload.save(
        WatchEntry(
          movie,
          null,
          const Duration(minutes: 30),
          const Duration(minutes: 30),
          DateTime.now(),
        ),
      );
      expect(await WatchHistory('legacy').latest(movie), isNull);
    },
  );
  testWidgets('series offers wide resume progress and play from beginning', (
    tester,
  ) async {
    final provider = FakeProvider();
    final details = await provider.getSeriesDetails(series);
    await WatchHistory.forProvider(
      provider,
    ).save(progress(series, details.episodes.first));
    await tester.pumpWidget(
      MaterialApp(
        home: DetailsScreen(provider: provider, item: series),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.text('25 min left'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('Resume'),
              matching: find.byType(TextButton),
            ),
          )
          .width,
      greaterThan(250),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  testWidgets('movie details retain Resume after clearing watch history', (
    tester,
  ) async {
    final provider = FakeProvider();
    final history = WatchHistory.forProvider(provider);
    await history.save(progress(movie));
    await history.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailsScreen(provider: provider, item: movie),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.text('25 min left'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1 / 6, .001),
    );
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
