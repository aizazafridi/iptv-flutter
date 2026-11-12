import 'dart:async';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/presentation/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'package:iptv_flutter/presentation/cinematic_movie_details.dart';
import 'series_catalog_screen_test.dart' show CatalogProvider;

class MovieProvider extends CatalogProvider {
  int movieDetails = 0;
  @override
  Set<ContentType> get supportedTypes => {ContentType.movies};
  @override
  Future<List<Category>> getCategories(ContentType type) async {
    expect(type, ContentType.movies);
    return [
      const Category('0', 'Drama', ContentType.movies),
      const Category('1', 'Crime', ContentType.movies),
    ];
  }

  @override
  List<ContentItem> titles(String category) => [
    for (var i = 0; i < 20; i++)
      ContentItem(
        id: '$category-$i',
        name: 'Movie $category $i',
        type: ContentType.movies,
        categoryId: category,
        rating: 9 - i * .1,
        releaseYear: 2026 - i,
        addedAt: DateTime.utc(2026, 10, 20 - i),
      ),
  ];
  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem item) =>
      throw StateError('Movies must not use series details');
  @override
  Future<MediaDetails> getMovieDetails(ContentItem item) async {
    movieDetails++;
    return MediaDetails(
      item: item,
      synopsis: 'Movie synopsis',
      genre: 'Drama',
      releaseDate: '2026-01-01',
    );
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final type in [ContentType.movies, ContentType.series]) {
    for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
      testWidgets(
        '$type category grid reaches final item and separates search at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey<SeriesCatalogScreenState>();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SeriesCatalogScreen(
                  key: key,
                  provider: type == ContentType.movies
                      ? MovieProvider()
                      : CatalogProvider(),
                  type: type,
                  onNavigation: () {},
                  onSettings: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          key.currentState!.showGrid('0');
          await tester.pumpAndSettle();
          final controls = find.byKey(const ValueKey('catalog-grid-controls'));
          final search = find.byType(TextField);
          expect(
            tester.getTopLeft(search).dy - tester.getTopLeft(controls).dy,
            greaterThanOrEqualTo(12),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          for (var i = 0; i < 19; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
          }
          SeriesPosterCard focused() => tester
              .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
              .singleWhere((card) => card.focusNode?.hasFocus == true);
          expect(focused().item.id, '0-19');
          final last = find.byWidget(focused());
          final grid = find.byType(GridView);
          expect(tester.getRect(grid).contains(tester.getCenter(last)), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(focused().item.id, '0-19');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(focused().item.id, '0-19');
          key.currentState!.gridSearch.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(focused().item.id, '0-0');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('$type focused category heading stays visible', (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<SeriesCatalogScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeriesCatalogScreen(
              key: key,
              provider: type == ContentType.movies
                  ? MovieProvider()
                  : CatalogProvider(),
              type: type,
              onNavigation: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final row in [2, 3, 2]) {
        unawaited(key.currentState!.focusRow(row));
        await tester.pumpAndSettle();
        final section = find.byKey(
          ValueKey('series-section:category:${row - 2}'),
        );
        final heading = find.descendant(
          of: section,
          matching: find.text(row == 2 ? 'Drama' : 'Crime'),
        );
        final viewport = find
            .ancestor(of: section, matching: find.byType(ListView))
            .first;
        expect(
          tester.getTopLeft(heading).dy,
          greaterThanOrEqualTo(tester.getTopLeft(viewport).dy),
        );
        expect(
          tester.getBottomLeft(heading).dy,
          lessThanOrEqualTo(tester.getBottomLeft(viewport).dy),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'Movies keep stable cards and update the pinned featured panel on remote focus',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = MovieProvider();
      final key = GlobalKey<SeriesCatalogScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeriesCatalogScreen(
              key: key,
              provider: provider,
              type: ContentType.movies,
              onNavigation: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(key.currentState!.focusRow(0));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsNothing,
      );
      expect(find.text('Movie synopsis'), findsOneWidget);
      final first = key.currentState!.featured!.id;
      final card = find
          .ancestor(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is TextButton &&
                  widget.focusNode?.hasPrimaryFocus == true,
            ),
            matching: find.byType(SeriesPosterCard),
          )
          .first;
      final cardSize = tester.getSize(card);
      final before = FocusManager.instance.primaryFocus;
      final heroTop = tester.getTopLeft(
        find.byKey(const ValueKey('series-featured-hero')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(before)));
      expect(key.currentState!.featured!.id, isNot(first));
      expect(tester.getSize(card), cardSize);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('series-featured-hero'))),
        heroTop,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('series-featured-hero'))),
        heroTop,
      );
      expect(key.currentState!.handleBack(), isFalse);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets('dashboard Movies opens the new catalog and Back restores Home', (
    tester,
  ) async {
    final provider = MovieProvider();
    final session = Session(ProviderRegistry(), const CredentialStore())
      ..provider = provider
      ..account = const Account('demo', 'Active', null)
      ..loading = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamoraDashboard(
            session: session,
            appearance: AppAppearance(),
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus!.debugLabel,
      'dashboard nav Movies',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SeriesCatalogScreen>(find.byType(SeriesCatalogScreen)).type,
      ContentType.movies,
    );
    expect(find.text('All Movies'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus!.debugLabel,
      'dashboard nav Home',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets(
    'movie category drawer keeps search and sort and restores its opener',
    (tester) async {
      final provider = MovieProvider();
      final key = GlobalKey<SeriesCatalogScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeriesCatalogScreen(
              key: key,
              provider: provider,
              type: ContentType.movies,
              onNavigation: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Movies').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Movie');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort movies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title Z-A'));
      await tester.pumpAndSettle();
      expect(key.currentState!.query, 'movie');
      final requests = provider.requested.length;
      await tester.tap(find.textContaining('Categories:'));
      await tester.pumpAndSettle();
      expect(provider.requested.length, requests);
      await tester.tap(find.text('Other Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crime'));
      await tester.pumpAndSettle();
      expect(key.currentState!.filter, '1');
      expect(key.currentState!.query, 'movie');
      expect(key.currentState!.sort, 'za');
      expect(find.text('Categories: Crime'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'catalog categories',
      );
      expect(
        tester
            .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
            .every((w) => w.item.categoryId == '1'),
        isTrue,
      );
      await tester.tap(find.textContaining('Categories:'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'category:1');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key.currentState!.filter, '1');
      await tester.tap(find.textContaining('Categories:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Movies').last);
      await tester.pumpAndSettle();
      expect(key.currentState!.filter, isNull);
      expect(key.currentState!.query, 'movie');
      expect(key.currentState!.sort, 'za');
      expect(provider.allCalls, 1);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'movie catalog uses cinematic rows and opens movie details at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = MovieProvider();
        final key = GlobalKey<SeriesCatalogScreenState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SeriesCatalogScreen(
                key: key,
                provider: provider,
                type: ContentType.movies,
                onNavigation: () {},
                onSettings: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('All Movies'), findsOneWidget);
        expect(find.text('Recently Added'), findsOneWidget);
        expect(provider.allCalls, 0);
        key.currentState!.focusEntry();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(CinematicMovieDetails), findsOneWidget);
        final details = tester.widget<DetailsScreen>(
          find.byType(DetailsScreen),
        );
        expect(details.item.type, ContentType.movies);
        expect(details.autoPlay, isFalse);
        expect(provider.movieDetails, 1);
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      },
    );
  }
  testWidgets(
    'movie banner cycles watched movies with Resume and movie-only grid',
    (tester) async {
      final provider = MovieProvider();
      final items = provider.titles('0');
      final history = WatchHistory.forProvider(provider);
      for (var i = 0; i < 2; i++) {
        await history.save(
          WatchEntry(
            items[i],
            null,
            const Duration(minutes: 20),
            const Duration(minutes: 90),
            DateTime.utc(2026, 10, 20 - i),
          ),
        );
      }
      final key = GlobalKey<SeriesCatalogScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeriesCatalogScreen(
              key: key,
              provider: provider,
              type: ContentType.movies,
              onNavigation: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsNothing);
      expect(key.currentState!.featured!.id, items[0].id);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(key.currentState!.featured!.id, items[1].id);
      expect(find.text('Resume'), findsNothing);
      await tester.tap(find.text('All Movies').last);
      await tester.pumpAndSettle();
      expect(provider.allCalls, 1);
      expect(find.text('Search all movies'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
