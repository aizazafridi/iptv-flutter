import 'package:iptv_flutter/presentation/activation_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'package:iptv_flutter/presentation/dashboard.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'package:iptv_flutter/presentation/search_screen.dart';
import 'widget_test.dart' show FakeProvider;

class CatalogProvider extends FakeProvider {
  int allCalls = 0, categoryCalls = 0;
  final requested = <String>[];
  bool fail = false, empty = false;
  Episode? resolved;
  @override
  Set<ContentType> get supportedTypes => {ContentType.series};
  @override
  Future<List<Category>> getCategories(ContentType type) async {
    categoryCalls++;
    if (fail) throw const ProviderException('Offline');
    return [
      for (var i = 0; i < 20; i++)
        Category(
          '$i',
          i == 0
              ? 'Drama'
              : i == 1
              ? 'Crime'
              : 'Category $i',
          ContentType.series,
        ),
    ];
  }

  List<ContentItem> titles(String category) => empty
      ? []
      : [
          for (var i = 0; i < 20; i++)
            ContentItem(
              id: '$category-$i',
              name: 'Series $category ${i.toString().padLeft(2, '0')}',
              type: ContentType.series,
              categoryId: category,
              addedAt: DateTime.utc(2026, 10, 20 - i),
              rating: 9 - i * .1,
              releaseYear: 2026 - i,
            ),
        ];
  @override
  Future<List<ContentItem>> getItems(Category category) async {
    requested.add(category.id);
    return titles(category.id);
  }

  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async {
    allCalls++;
    return [...titles('0'), ...titles('1')];
  }

  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem item) async =>
      SeriesDetails(
        MediaDetails(
          item: item,
          synopsis: 'Real provider synopsis',
          genre: 'Drama',
          rating: '8.8',
          releaseDate: '2023-01-01',
        ),
        const [
          Episode(
            id: 'ep1',
            title: 'Pilot',
            season: 1,
            number: 1,
            extension: 'mp4',
          ),
          Episode(
            id: 'ep2',
            title: 'Next',
            season: 1,
            number: 2,
            extension: 'mp4',
          ),
        ],
      );
  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async {
    resolved = episode;
    throw const ProviderException('Playback test');
  }
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

SeriesPosterCard focused(WidgetTester tester) => tester
    .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
    .firstWhere((w) => w.focusNode?.hasFocus == true);
Future<GlobalKey<SeriesCatalogScreenState>> mount(
  WidgetTester tester,
  CatalogProvider provider, {
  VoidCallback? navigation,
}) async {
  final key = GlobalKey<SeriesCatalogScreenState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SeriesCatalogScreen(
          key: key,
          provider: provider,
          onNavigation: navigation ?? () {},
          onSettings: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  key.currentState!.focusEntry();
  await tester.pumpAndSettle();
  return key;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'featured banner rotates watched series every 15 seconds and loops without losing focus',
    (tester) async {
      final provider = CatalogProvider();
      final history = WatchHistory.forProvider(provider);
      final items = provider.titles('0').take(3).toList();
      for (var i = 0; i < items.length; i++) {
        await history.save(
          WatchEntry(
            items[i],
            Episode(
              id: 'ep${i + 1}',
              title: 'Episode',
              season: 1,
              number: i + 1,
              extension: 'mp4',
            ),
            const Duration(minutes: 10),
            const Duration(minutes: 40),
            DateTime.utc(2026, 10, 20 - i),
          ),
        );
      }
      final key = await mount(tester, provider);
      expect(key.currentState!.featured!.id, items[0].id);
      final focus = FocusManager.instance.primaryFocus;
      await tester.pump(const Duration(seconds: 14));
      expect(key.currentState!.featured!.id, items[0].id);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(key.currentState!.featured!.id, items[1].id);
      expect(find.text('Resume S1 E2'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(focus));
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(key.currentState!.featured!.id, items[2].id);
      expect(find.text('Resume S1 E3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(key.currentState!.featured!.id, items[0].id);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'catalog rows browse lazily and restore focus at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = CatalogProvider();
        var rail = 0;
        await mount(tester, provider, navigation: () => rail++);
        expect(provider.allCalls, 0);
        expect(provider.requested, isNot(contains('19')));
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'series featured details',
        );
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(tester).item.id, '0-0');
        for (var i = 0; i < 7; i++) {
          await press(tester, LogicalKeyboardKey.arrowRight);
        }
        expect(focused(tester).item.id, '0-7');
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(tester).item.id, '0-8');
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focused(tester).item.id, '0-0');
        for (var i = 0; i < 7; i++) {
          await press(tester, LogicalKeyboardKey.arrowRight);
        }
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.byType(DetailsScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(focused(tester).item.id, '0-7');
        for (var i = 0; i < 7; i++) {
          await press(tester, LogicalKeyboardKey.arrowLeft);
        }
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(rail, 1);
        expect(provider.allCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'vertical category navigation starts at the first item and returns to the hero',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = CatalogProvider();
      await mount(tester, provider);
      await press(tester, LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      for (var i = 0; i < 8; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(provider.requested, contains('6'));
      for (var i = 0; i < 8; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(focused(tester).item.id, '0-0');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'series featured details',
      );
      expect(provider.allCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dashboard reuses the rail, highlights Series, and Back restores Home',
    (tester) async {
      final provider = CatalogProvider();
      final appearance = AppAppearance();
      final session = Session(ProviderRegistry(), const CredentialStore())
        ..provider = provider
        ..account = const Account('demo', 'Active', null)
        ..loading = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StreamoraDashboard(
              session: session,
              appearance: appearance,
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'dashboard nav Series',
      );
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(SeriesCatalogScreen), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-sidebar'))).width,
        76,
      );
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'series featured details',
      );
      await press(tester, LogicalKeyboardKey.arrowLeft); // Details -> Watch.
      await press(tester, LogicalKeyboardKey.arrowLeft); // Watch -> rail.
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'dashboard nav Series',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-sidebar'))).width,
        172,
      );
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'series featured details',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'dashboard nav Home',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'All Series loads only after selection, filters, sorts and searches',
    (tester) async {
      final provider = CatalogProvider();
      final key = await mount(tester, provider);
      await tester.tap(find.text('All Series'));
      await tester.pumpAndSettle();
      expect(provider.allCalls, 1);
      await tester.tap(find.byTooltip('Sort series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title Z-A'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
            .first
            .item
            .id,
        '1-19',
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'SERIES 0 03');
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
            .single
            .item
            .id,
        '0-3',
      );
      expect(provider.allCalls, 1);
      await tester.tap(find.textContaining('Categories:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crime'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
            .every((w) => w.item.categoryId == '1'),
        isTrue,
      );
      expect(key.currentState!.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Watch Now'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('search uses the existing Series-only search screen', (
    tester,
  ) async {
    final provider = CatalogProvider();
    await mount(tester, provider);
    await tester.tap(find.byTooltip('Search series'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CatalogSearchScreen>(find.byType(CatalogSearchScreen)).type,
      ContentType.series,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus!.debugLabel,
      'series catalog search',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Continue Watching deduplicates series, excludes movies, and resumes the correct episode',
    (tester) async {
      final provider = CatalogProvider();
      final history = WatchHistory.forProvider(provider);
      final item = provider.titles('0').first;
      for (final number in [1, 2]) {
        await history.save(
          WatchEntry(
            item,
            Episode(
              id: 'ep$number',
              title: 'Episode',
              season: 1,
              number: number,
              extension: 'mp4',
            ),
            const Duration(minutes: 10),
            const Duration(minutes: 40),
            DateTime.utc(2026, 10, number),
          ),
        );
      }
      await history.save(
        WatchEntry(
          const ContentItem(
            id: 'movie',
            name: 'Movie must not appear',
            type: ContentType.movies,
          ),
          null,
          const Duration(minutes: 1),
          const Duration(minutes: 10),
          DateTime.now(),
        ),
      );
      await mount(tester, provider);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester).progress!.episode!.id, 'ep2');
      expect(find.text('Movie must not appear'), findsNothing);
      await press(tester, LogicalKeyboardKey.enter);
      expect(provider.resolved!.id, 'ep2');
      expect(
        tester.widget<DetailsScreen>(find.byType(DetailsScreen)).autoPlay,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty and retry states use actual provider data', (
    tester,
  ) async {
    final provider = CatalogProvider()..fail = true;
    await mount(tester, provider);
    expect(find.text('Unable to load series'), findsOneWidget);
    provider.fail = false;
    provider.empty = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No series available'), findsOneWidget);
    expect(provider.allCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'hidden and PIN-protected categories cannot leak into the featured catalog',
    (tester) async {
      final provider = CatalogProvider();
      final locks = CategoryLocks.forProvider(provider);
      await locks.setHidden(
        const Category('0', 'Drama', ContentType.series),
        true,
      );
      await locks.setPassword('123456');
      await locks.setLocked(
        const Category('1', 'Crime', ContentType.series),
        true,
        password: '123456',
      );
      await mount(tester, provider);
      expect(provider.requested, isNot(contains('0')));
      expect(provider.requested, isNot(contains('1')));
      expect(find.text('Series 0 00'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('profile history is isolated when switching accounts', (
    tester,
  ) async {
    final first = CatalogProvider(), second = CatalogProvider();
    WatchHistory.attach(
      first,
      const ProviderConfig(
        providerId: 'fixture',
        server: 'https://example.com',
        username: 'demo',
        password: 'fixture',
        profileId: 'profile-a',
      ),
    );
    WatchHistory.attach(
      second,
      const ProviderConfig(
        providerId: 'fixture',
        server: 'https://example.com',
        username: 'demo',
        password: 'fixture',
        profileId: 'profile-b',
      ),
    );
    await WatchHistory.forProvider(first).save(
      WatchEntry(
        first.titles('0').first,
        const Episode(
          id: 'ep2',
          title: 'Second',
          season: 1,
          number: 2,
          extension: 'mp4',
        ),
        const Duration(minutes: 10),
        const Duration(minutes: 40),
        DateTime.now(),
      ),
    );
    await mount(tester, first);
    expect(find.text('Continue Watching'), findsOneWidget);
    await mount(tester, second);
    expect(find.text('Continue Watching'), findsNothing);
    expect(find.text('Watch Now'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('grid search moves right to Sort and Catalog with the remote', (
    tester,
  ) async {
    await mount(tester, CatalogProvider());
    await tester.tap(find.text('All Series').first);
    await tester.pumpAndSettle();
    tester
        .widget<ActivationTextField>(find.byType(ActivationTextField))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'catalog grid sort');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      FocusManager.instance.primaryFocus!.debugLabel,
      'catalog grid catalog',
    );
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'catalog grid sort');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      FocusManager.instance.primaryFocus!.debugLabel,
      'series grid search',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
