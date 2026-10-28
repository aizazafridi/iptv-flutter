import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iptv_flutter/data/omdb_ratings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/cinematic_series_details.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'widget_test.dart' show FakeProvider;

const series = ContentItem(
  id: 's1',
  name: 'A Series (2023)',
  type: ContentType.series,
  categoryId: '7',
);
const info = MediaDetails(
  item: series,
  synopsis: 'Series synopsis',
  releaseDate: '2023-01-01',
  genre: 'Drama',
  rating: '8.87',
);
List<Episode> episodes() => [
  for (var i = 1; i <= 12; i++)
    Episode(
      id: 'e$i',
      title: i == 1 ? 'Pilot' : 'Episode $i',
      season: 1,
      number: i,
      extension: 'mp4',
      synopsis: 'Episode $i synopsis',
      duration: '00:42:00',
    ),
  const Episode(
    id: 's2e1',
    title: 'New season',
    season: 2,
    number: 1,
    extension: 'mkv',
  ),
];
Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Finder button(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(TextButton));
bool focused(WidgetTester tester, String text) =>
    tester.widget<TextButton>(button(text)).focusNode!.hasFocus;
Future<void> mount(
  WidgetTester tester,
  FakeProvider provider, {
  List<Episode>? items,
  Future<void> Function(Episode, bool)? onPlay,
  MediaDetails details = info,
}) async {
  final client = TmdbCastService();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CinematicSeriesDetails(
          provider: provider,
          info: details,
          episodes: items ?? episodes(),
          resolving: false,
          castService: client,
          artworkService: TmdbArtworkService(client: client, persist: false),
          onPlay: onPlay ?? (_, _) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final width in [960.0, 1280.0, 1920.0]) {
    testWidgets(
      'TV remote traverses actions, seasons and lazy episodes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, width * 9 / 16);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = FakeProvider();
        Episode? played;
        await mount(
          tester,
          provider,
          onPlay: (ep, _) async {
            played = ep;
          },
        );
        expect(find.text('Play S1 E1'), findsOneWidget);
        expect(find.text('A Series'), findsOneWidget);
        expect(find.text('\u2605 8.9/10'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'series primary action',
        );
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(tester, 'Season 1'), isTrue);
        await key(tester, LogicalKeyboardKey.arrowRight);
        await key(tester, LogicalKeyboardKey.enter);
        expect(find.text('1. New season'), findsOneWidget);
        expect(find.text('1. Pilot'), findsNothing);
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(tester, '1. New season'), isTrue);
        expect(played, isNull); // Browsing never tunes a stream.
        await key(tester, LogicalKeyboardKey.enter);
        expect(played!.id, 's2e1');
        expect(focused(tester, '1. New season'), isTrue);
        await key(tester, LogicalKeyboardKey.arrowUp);
        expect(focused(tester, 'Season 2'), isTrue);
        await key(tester, LogicalKeyboardKey.arrowLeft);
        await key(tester, LogicalKeyboardKey.enter);
        await key(tester, LogicalKeyboardKey.arrowDown);
        for (var i = 0; i < 8; i++) {
          await key(tester, LogicalKeyboardKey.arrowRight);
        }
        expect(focused(tester, '9. Episode 9'), isTrue);
        await key(tester, LogicalKeyboardKey.arrowUp);
        expect(focused(tester, 'Season 1'), isTrue);
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(tester, '9. Episode 9'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'profile resume selects its season and refreshes progress after playback',
    (tester) async {
      final provider = FakeProvider();
      final history = WatchHistory.forProvider(provider);
      final ep = episodes().last;
      await history.save(
        WatchEntry(
          series,
          ep,
          const Duration(minutes: 10),
          const Duration(minutes: 40),
          DateTime.now(),
        ),
      );
      await mount(
        tester,
        provider,
        onPlay: (selected, restart) async {
          expect(selected.id, 's2e1');
          expect(restart, isFalse);
          await history.save(
            WatchEntry(
              series,
              selected,
              const Duration(minutes: 20),
              const Duration(minutes: 40),
              DateTime.now(),
            ),
          );
        },
      );
      expect(find.text('Resume S2 E1'), findsOneWidget);
      expect(find.text('30 min left'), findsOneWidget);
      expect(find.text('1. New season'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.text('20 min left'), findsOneWidget);
      expect(
        (await history.latest(series, episode: ep))!.position,
        const Duration(minutes: 20),
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, '1. New season'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'watched indicators persist per profile without putting completed episodes back in resume',
    () async {
      final ep = episodes().first;
      final history = WatchHistory('series-completion');
      await history.save(
        WatchEntry(
          series,
          ep,
          const Duration(minutes: 40),
          const Duration(minutes: 42),
          DateTime.now(),
        ),
      );
      expect(await WatchHistory('series-completion').latest(series), isNull);
      expect(
        (await WatchHistory(
          'series-completion',
        ).seriesProgress(series)).single.episode!.id,
        'e1',
      );
      expect(
        await WatchHistory('another-profile').seriesProgress(series),
        isEmpty,
      );
    },
  );
  testWidgets(
    'specials, empty metadata, My List and full synopsis are usable',
    (tester) async {
      final provider = FakeProvider();
      await mount(
        tester,
        provider,
        items: const [
          Episode(
            id: 'special',
            title: 'Special',
            season: 0,
            number: 1,
            extension: 'mp4',
          ),
        ],
        details: const MediaDetails(item: series, synopsis: ''),
      );
      expect(find.text('Specials'), findsOneWidget);
      expect(find.text('No synopsis available.'), findsOneWidget);
      expect(find.text('Trailer'), findsNothing);
      await tester.tap(find.text('My List'));
      await tester.pumpAndSettle();
      expect(MyList.forProvider(provider).contains(series), isTrue);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('More Info'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'first episode-row focus follows a saved episode in the same season',
    (tester) async {
      final provider = FakeProvider();
      await WatchHistory.forProvider(provider).save(
        WatchEntry(
          series,
          episodes()[8],
          const Duration(minutes: 5),
          const Duration(minutes: 42),
          DateTime.now(),
        ),
      );
      await mount(tester, provider);
      expect(find.text('Resume S1 E9'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, '9. Episode 9'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty series shows an honest empty state', (tester) async {
    await mount(tester, FakeProvider(), items: const []);
    expect(find.text('No episodes available'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'TMDB TV logos and credits use TV endpoints and cached metadata',
    (tester) async {
      final paths = <String>[];
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          paths.add(uri.path);
          if (uri.path.endsWith('/images')) {
            return {
              'logos': [
                {'file_path': '/logo.png', 'iso_639_1': 'en'},
              ],
            };
          }
          if (uri.path.endsWith('/aggregate_credits')) {
            return {
              'cast': [
                {
                  'name': 'Actor Name',
                  'character': 'Hero',
                  'profile_path': '/actor.jpg',
                },
              ],
            };
          }
          return {};
        },
      );
      const details = MediaDetails(item: series, synopsis: '', tmdbId: 123);
      final artwork = TmdbArtworkService(client: client, persist: false);
      expect((await artwork.titleLogo(details))!.path, contains('logo.png'));
      expect((await client.credits(details)).single.name, 'Actor Name');
      expect(
        paths,
        containsAll(['/3/tv/123/images', '/3/tv/123/aggregate_credits']),
      );
      await artwork.titleLogo(details);
      await client.credits(details);
      expect(paths.length, 2);
    },
  );
  testWidgets(
    'returning from playback preserves the episode, season and scroll position',
    (tester) async {
      final provider = FakeProvider();
      final history = WatchHistory.forProvider(provider);
      await mount(
        tester,
        provider,
        onPlay: (episode, restart) async {
          final context = tester.element(find.byType(CinematicSeriesDetails));
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Playback route')),
            ),
          );
          await history.save(
            WatchEntry(
              series,
              episode,
              const Duration(minutes: 8),
              const Duration(minutes: 42),
              DateTime.now(),
            ),
          );
        },
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 8; i++) {
        await key(tester, LogicalKeyboardKey.arrowRight);
      }
      final before = tester.getTopLeft(find.text('9. Episode 9'));
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.text('Playback route'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(focused(tester, '9. Episode 9'), isTrue);
      expect(find.text('Resume S1 E9'), findsOneWidget);
      expect(
        (tester.getTopLeft(find.text('9. Episode 9')) - before).distance,
        lessThan(2),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'recommendations and cast participate in remote rows and Back restores the series',
    (tester) async {
      final provider = _RelatedProvider();
      await mount(
        tester,
        provider,
        details: const MediaDetails(
          item: series,
          synopsis: '',
          cast: 'An Actor',
        ),
      );
      expect(find.text('More Like This'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text('An Actor'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'series row item 0',
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, 'Season 1'), isTrue);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, '1. Pilot'), isTrue);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, 'Related show'), isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(find.text('Related show'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DetailsScreen), findsNothing);
      expect(focused(tester, 'Related show'), isTrue);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, '1. Pilot'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('large text and long titles do not overflow', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = TmdbCastService();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: CinematicSeriesDetails(
            provider: FakeProvider(),
            info: const MediaDetails(
              item: ContentItem(
                id: 'long',
                name:
                    'A considerably longer series title with multiple parts and subtitles',
                type: ContentType.series,
              ),
              synopsis:
                  'A long synopsis. A long synopsis. A long synopsis. A long synopsis. A long synopsis.',
            ),
            episodes: episodes(),
            resolving: false,
            onPlay: (_, _) async {},
            castService: client,
            artworkService: TmdbArtworkService(client: client, persist: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'language-tagged series show TMDB artwork and cast above wide compact season tabs',
    (tester) async {
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          if (uri.path.endsWith('/search/tv')) {
            return {
              'results': [
                {'id': 100088, 'name': 'The Last of Us'},
              ],
            };
          }
          if (uri.path.endsWith('/aggregate_credits')) {
            return {
              'cast': [
                {
                  'name': 'Pedro Pascal',
                  'profile_path': '/pedro.jpg',
                  'roles': [
                    {'character': 'Joel'},
                  ],
                },
              ],
            };
          }
          if (uri.path.endsWith('/images')) return {'logos': []};
          return {'backdrop_path': '/backdrop.jpg'};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CinematicSeriesDetails(
              provider: FakeProvider(),
              info: const MediaDetails(
                item: ContentItem(
                  id: 'tlou',
                  name: 'The Last of Us Hindi',
                  type: ContentType.series,
                ),
                synopsis: '',
              ),
              episodes: episodes(),
              resolving: false,
              onPlay: (_, _) async {},
              castService: client,
              artworkService: TmdbArtworkService(
                client: client,
                persist: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is CachedNetworkImage && w.imageUrl.endsWith('/pedro.jpg'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CachedNetworkImage && w.imageUrl.endsWith('/backdrop.jpg'),
        ),
        findsWidgets,
      );
      expect(
        tester.getTopLeft(find.text('Cast & Crew')).dy,
        lessThan(tester.getTopLeft(find.text('Season 1')).dy),
      );
      final seasonSize = tester.getSize(button('Season 1'));
      expect(seasonSize.width, greaterThan(120));
      expect(seasonSize.height, lessThan(42));
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'series row item 0',
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, 'Season 1'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'series displays IMDb and Rotten Tomatoes logos with honest missing-rating status',
    (tester) async {
      final client = TmdbCastService();
      final ratings = OmdbRatingsService(
        persist: false,
        fetch: (_) async => {
          'Response': 'True',
          'Title': 'A Series',
          'Year': '2023\u2013',
          'imdbRating': '8.4',
          'Ratings': [
            {'Source': 'Internet Movie Database', 'Value': '8.4/10'},
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CinematicSeriesDetails(
              provider: FakeProvider(),
              info: info,
              episodes: episodes(),
              resolving: false,
              onPlay: (_, _) async {},
              ratingsService: ratings,
              castService: client,
              artworkService: TmdbArtworkService(
                client: client,
                persist: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('8.4/10'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(find.textContaining(' ? '), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('series failure has retry and loading skeleton', (tester) async {
    final provider = _RetryProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailsScreen(provider: provider, item: series),
      ),
    );
    expect(find.byType(SeriesDetailsSkeleton), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Unable to load episodes'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Play S1 E1'), findsOneWidget);
    expect(provider.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
}

class _RetryProvider extends FakeProvider {
  int calls = 0;
  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem item) async {
    if (++calls == 1) throw const ProviderException('Provider unavailable');
    return SeriesDetails(info, episodes());
  }
}

class _RelatedProvider extends FakeProvider {
  @override
  Future<List<ContentItem>> getItems(Category category) async => const [
    series,
    ContentItem(id: 'related', name: 'Related show', type: ContentType.series),
    ContentItem(id: 'related', name: 'Related show', type: ContentType.series),
  ];
}
