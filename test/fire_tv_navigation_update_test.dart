import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/live_channel_browser.dart';
import 'package:iptv_flutter/presentation/details_title.dart';
import 'package:iptv_flutter/presentation/cinematic_movie_details.dart';
import 'package:iptv_flutter/presentation/cinematic_series_details.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'guide_player_stability_test.dart' show StableEngine;
import 'live_channel_browser_test.dart' show BrowserProvider;
import 'widget_test.dart' show FakeProvider;
import 'cinematic_series_details_test.dart' as fixture;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'live browser tunes without closing, second OK closes, Back closes overlay then confirms exit',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = StableEngine(), provider = BrowserProvider();
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/player',
          routes: {
            '/': (_) => const Scaffold(body: Text('Dashboard')),
            '/player': (_) => PlayerScreen(
              liveTvMode: true,
              source: PlaybackSource(
                uri: Uri.parse('https://example.com/live'),
                title: 'Channel',
                isLive: true,
              ),
              item: provider.channels.first,
              provider: provider,
              loadChannels: () async => provider.channels,
              resolveChannel: (item) async => PlaybackSource(
                uri: Uri.parse('https://example.com/live/${item.id}'),
                title: item.name,
                isLive: true,
              ),
              engineFactory: () => engine,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channels').last);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsOneWidget);
      expect(engine.opens, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(engine.opens, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channels').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.text('Exit Live TV?'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Live TV?'), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final type in [ContentType.movies, ContentType.series]) {
    testWidgets('$type details Up returns entire page to top', (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final item = ContentItem(
        id: 'test',
        name:
            'A very long title that should display correctly across two complete lines on the information page',
        type: type,
        categoryId: '7',
      );
      final info = MediaDetails(
        item: item,
        synopsis: 'Synopsis',
        cast: 'Actor One, Actor Two',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: type == ContentType.movies
                ? CinematicMovieDetails(
                    provider: FakeProvider(),
                    info: info,
                    previous: null,
                    resolving: false,
                    onPlay: (_) {},
                  )
                : CinematicSeriesDetails(
                    provider: FakeProvider(),
                    info: info,
                    episodes: fixture.episodes(),
                    resolving: false,
                    onPlay: (_, _) async {},
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byKey(
        PageStorageKey(
          type == ContentType.movies
              ? 'cinematic-movie-scroll'
              : 'series-details-test',
        ),
      );
      final scroll = tester.widget<SingleChildScrollView>(finder).controller!;
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(scroll.offset, greaterThan(0));
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
      }
      expect(scroll.offset, closeTo(0, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('movie Continue Watching never shows invented season/episode', (
    tester,
  ) async {
    const movie = ContentItem(
      id: 'v',
      name: 'Verity',
      type: ContentType.movies,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 220,
          height: 250,
          child: SeriesPosterCard(
            item: movie,
            provider: FakeProvider(),
            progress: WatchEntry(
              movie,
              null,
              const Duration(minutes: 10),
              const Duration(minutes: 90),
              DateTime.now(),
            ),
            onOpen: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('S1'), findsNothing);
    expect(find.textContaining('80 min left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'long title scales to fit a short logo slot without clipping its second line',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 260,
              height: 50,
              child: DetailsTitle(
                'A long movie title that requires two lines of text to display',
                fontSize: 34,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FittedBox), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
