import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/data/omdb_ratings_service.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/cinematic_movie_details.dart';
import 'widget_test.dart' show FakeProvider;

const movie = ContentItem(
  id: 'film',
  name: 'Cinematic Movie',
  type: ContentType.movies,
  categoryId: '7',
);
const info = MediaDetails(
  item: movie,
  synopsis:
      'A survivor travels across a changed world in search of a new beginning.',
  genre: 'Drama',
  cast: 'Actor One, Actor Two',
  director: 'Director One',
  releaseDate: '2026-10-25',
  duration: '01:40:00',
  rating: '8.2',
);
void main() {
  testWidgets(
    'official title logo preserves initial focus and Roboto fallback on image failure',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async => uri.path.endsWith('/images')
            ? {
                'logos': [
                  {'file_path': '/title.png', 'iso_639_1': 'en'},
                ],
              }
            : {
                'results': [
                  {
                    'id': 42,
                    'title': 'Cinematic Movie',
                    'release_date': '2026-01-01',
                  },
                ],
              },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CinematicMovieDetails(
              provider: FakeProvider(),
              info: info,
              previous: null,
              resolving: false,
              onPlay: (_) {},
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
          (widget) =>
              widget is CachedNetworkImage &&
              widget.imageUrl == 'https://image.tmdb.org/t/p/w500/title.png',
        ),
        findsOneWidget,
      );
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'movie primary action',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'movie page displays source-labeled OMDb ratings without changing initial focus',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final service = OmdbRatingsService(
        persist: false,
        fetch: (_) async => {
          'Response': 'True',
          'Title': 'Cinematic Movie',
          'Year': '2026',
          'imdbRating': '7.8',
          'Ratings': [
            {'Source': 'Rotten Tomatoes', 'Value': '72%'},
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CinematicMovieDetails(
              provider: FakeProvider(),
              info: info,
              previous: null,
              resolving: false,
              onPlay: (_) {},
              ratingsService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7.8/10'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.text('\u2605 8.2/10'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'movie primary action',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'movie typography formatting trims title suffixes and presents concise metadata',
    () {
      expect(
        movieDisplayTitle('The Curious Case of Benjamin Button (2008)(4K).'),
        'The Curious Case of Benjamin Button',
      );
      expect(
        movieDisplayTitle('Wonder Woman 1984 (2020).'),
        'Wonder Woman 1984',
      );
      expect(movieDisplayRating('7.573'), '\u2605 7.6/10');
      expect(movieDisplayRating('8/10'), '\u2605 8.0/10');
      expect(movieDisplayRating('N/A'), 'N/A');
      expect(movieDisplayDuration('02:46:03'), '2h 46m');
      expect(movieDisplayDuration('00:46:03'), '46m');
      expect(movieDisplayDuration('01:00:00'), '1h');
      expect(movieDisplayDuration('Unknown'), 'Unknown');
    },
  );

  testWidgets('TMDB enrichment displays actor photos and character names', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final service = TmdbCastService(
      persist: false,
      fetch: (uri) async => uri.path.endsWith('/credits')
          ? {
              'cast': [
                {
                  'name': 'Featured Actor',
                  'character': 'Lead Character',
                  'order': 0,
                  'profile_path': '/actor.jpg',
                },
              ],
            }
          : {
              'results': [
                {
                  'id': 42,
                  'title': 'Cinematic Movie',
                  'release_date': '2026-01-01',
                },
              ],
            },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CinematicMovieDetails(
            provider: FakeProvider(),
            info: info,
            previous: null,
            resolving: false,
            onPlay: (_) {},
            castService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Featured Actor'), findsOneWidget);
    expect(find.text('Lead Character'), findsOneWidget);
    final card = find.byKey(const ValueKey('cast-credit:Featured Actor'));
    final portrait = tester.widget<CachedNetworkImage>(
      find.descendant(of: card, matching: find.byType(CachedNetworkImage)),
    );
    expect(portrait.fit, BoxFit.cover);
    expect(
      find.descendant(of: card, matching: find.byType(TextButton)),
      findsNothing,
    );
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl == 'https://image.tmdb.org/t/p/w185/actor.jpg',
      ),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'movie primary action',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
    testWidgets('cinematic layout and remote sections at ${size.width}', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? fromBeginning;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: CinematicMovieDetails(
              provider: FakeProvider(),
              info: info,
              previous: null,
              resolving: false,
              onPlay: (value) => fromBeginning = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'movie primary action',
      );
      expect(find.text('Play Movie'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fromBeginning, isFalse);
      for (final label in ['movie cast', 'movie similar']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'movie cast');
      expect(find.text('Movie Details'), findsNothing);
      await tester.ensureVisible(find.text('More Info'));
      await tester.tap(find.text('More Info'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Movie Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('resume shows remaining time, progress and restart action', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    bool? fromBeginning;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: CinematicMovieDetails(
            provider: FakeProvider(),
            info: info,
            previous: WatchEntry(
              movie,
              null,
              const Duration(minutes: 40),
              const Duration(minutes: 100),
              DateTime.now(),
            ),
            resolving: false,
            onPlay: (value) => fromBeginning = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resume - 60 min left'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .4,
    );
    await tester.ensureVisible(find.text('Play from beginning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play from beginning'));
    await tester.pumpAndSettle();
    expect(fromBeginning, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
