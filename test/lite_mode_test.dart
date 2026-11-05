import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/presentation/settings_screen.dart';
import 'package:iptv_flutter/presentation/dashboard.dart';
import 'package:iptv_flutter/application/recent_catalog_cache.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/presentation/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'package:iptv_flutter/presentation/lite_media_list.dart';
import 'package:iptv_flutter/presentation/lite_details.dart';
import 'package:iptv_flutter/presentation/activation_text_field.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'series_catalog_screen_test.dart' show CatalogProvider;
import 'movie_catalog_screen_test.dart' show MovieProvider;

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
  });
  tearDown(() async {
    await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
  });
  test(
    'device browsing mode defaults to Premium and survives new settings instances',
    () async {
      final setting = BrowsingModeSettings();
      await setting.load();
      expect(setting.mode, BrowsingMode.premium);
      await setting.choose(BrowsingMode.lite);
      final restored = BrowsingModeSettings();
      await restored.load();
      expect(restored.mode, BrowsingMode.lite);
      await restored.choose(BrowsingMode.premium);
      await setting.load();
      expect(setting.mode, BrowsingMode.premium);
    },
  );
  for (final type in [ContentType.movies, ContentType.series]) {
    testWidgets(
      'Lite $type renders text, searches, restores focus and switches without catalog reload',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
        final provider = type == ContentType.movies
            ? MovieProvider()
            : CatalogProvider();
        final key = GlobalKey<SeriesCatalogScreenState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SeriesCatalogScreen(
                key: key,
                type: type,
                provider: provider,
                onNavigation: () {},
                onSettings: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LiteMediaTile), findsWidgets);
        expect(find.byTooltip('Settings'), findsOneWidget);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byType(SeriesPosterCard), findsNothing);
        expect(provider.allCalls, 1);
        key.currentState!.focusEntry();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus!.debugLabel, isNotNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(LiteDetails), findsOneWidget);
        expect(find.byType(CachedNetworkImage), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(DetailsScreen), findsNothing);
        expect(FocusManager.instance.primaryFocus, focused);
        await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
        await tester.pumpAndSettle();
        expect(find.byType(LiteMediaTile), findsNothing);
        await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
        await tester.pumpAndSettle();
        expect(provider.allCalls, 1);
        final field = find.byType(ActivationTextField);
        await tester.tap(field);
        await tester.enterText(find.byType(TextField), 'no matching name');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(find.text('No matching titles.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      },
    );
  }
  testWidgets(
    'Appearance offers device-wide browsing mode without changing account',
    (tester) async {
      final provider = MovieProvider();
      final session = Session(ProviderRegistry(), const CredentialStore())
        ..provider = provider
        ..account = const Account('demo', 'Active', null)
        ..loading = false;
      session.activeProfile = const AccountProfile(
        id: 'device-test',
        name: 'Demo',
        avatar: 0,
        config: ProviderConfig(
          providerId: 'fixture',
          server: 'https://example.com',
          username: 'demo',
          password: 'fixture',
        ),
      );
      final appearance = AppAppearance();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            session: session,
            appearance: appearance,
            switchUser: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Appearance and browsing'));
      await tester.tap(find.text('Appearance and browsing'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lite'));
      await tester.tap(find.text('Lite'));
      await tester.pumpAndSettle();
      expect(BrowsingModeSettings.instance.lite, isTrue);
      expect(session.provider, same(provider));
      expect(session.account!.username, 'demo');
      await appearance.activate('another-profile');
      expect(BrowsingModeSettings.instance.lite, isTrue);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'Lite dashboard Continue Watching contains text and progress with no movie artwork',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      final provider = MovieProvider();
      final item = ContentItem(
        id: '0-3',
        name: 'Saved movie',
        categoryId: '0',
        type: ContentType.movies,
        artwork: Uri.parse('https://example.invalid/poster.jpg'),
      );
      await WatchHistory.forProvider(provider).save(
        WatchEntry(
          item,
          null,
          const Duration(minutes: 20),
          const Duration(minutes: 90),
          DateTime.now(),
        ),
      );
      final session = Session(ProviderRegistry(), const CredentialStore())
        ..provider = provider
        ..account = const Account('demo', 'Active', null)
        ..loading = false;
      final appearance = AppAppearance();
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('Saved movie'), findsOneWidget);
      expect(find.text('70 min left'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'Lite categories, sort, My List and Continue Watching reuse existing data and restrictions',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      final provider = MovieProvider();
      final item = provider.titles('0')[3];
      await MyList.forProvider(provider).toggle(item);
      await WatchHistory.forProvider(provider).save(
        WatchEntry(
          item,
          null,
          const Duration(minutes: 20),
          const Duration(minutes: 90),
          DateTime.now(),
        ),
      );
      final hidden = provider.titles('1')[0];
      await MyList.forProvider(provider).toggle(hidden);
      await CategoryLocks.forProvider(
        provider,
      ).setHidden(const Category('1', 'Crime', ContentType.movies), true);
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
      await tester.tap(find.text('My List'));
      await tester.pumpAndSettle();
      expect(find.text(item.name), findsOneWidget);
      expect(find.text(hidden.name), findsNothing);
      expect(find.text('70 min left'), findsOneWidget);
      await tester.tap(find.text('Continue Watching'));
      await tester.pumpAndSettle();
      expect(find.text(item.name), findsOneWidget);
      await tester.tap(find.text('All Movies'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort movies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title Z-A'));
      await tester.pumpAndSettle();
      expect(key.currentState!.sort, 'za');
      await tester.tap(find.textContaining('Categories:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drama'));
      await tester.pumpAndSettle();
      expect(key.currentState!.filter, '0');
      await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
      await tester.pumpAndSettle();
      expect(key.currentState!.filter, '0');
      expect(key.currentState!.sort, 'za');
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      await tester.pumpAndSettle();
      expect(key.currentState!.filter, '0');
      expect(key.currentState!.sort, 'za');
      expect(provider.allCalls, 1);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  test(
    'catalog cache shares full metadata with recent rows and isolates providers',
    () async {
      final one = MovieProvider(), two = MovieProvider();
      await RecentCatalogCache.load(one, ContentType.movies);
      await RecentCatalogCache.loadAll(one, ContentType.movies);
      expect(one.allCalls, 1);
      await RecentCatalogCache.loadAll(two, ContentType.movies);
      expect(two.allCalls, 1);
      RecentCatalogCache.invalidate(one);
      await RecentCatalogCache.loadAll(one, ContentType.movies);
      expect(one.allCalls, 2);
    },
  );
  testWidgets(
    'Lite movie resume and restart use existing progress without artwork',
    (tester) async {
      final provider = MovieProvider();
      final item = provider.titles('0').first;
      final saved = WatchEntry(
        item,
        null,
        const Duration(minutes: 20),
        const Duration(minutes: 90),
        DateTime.now(),
      );
      bool? restart;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiteDetails(
              provider: provider,
              info: MediaDetails(
                item: item,
                synopsis: 'Synopsis',
                cast: 'Actor Name',
                backdrop: Uri.parse('https://example.invalid/backdrop.jpg'),
              ),
              episodes: const [],
              previous: saved,
              resolving: false,
              onPlay: (_, beginning) async {
                restart = beginning;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Actor Name'), findsOneWidget);
      await tester.tap(find.text('Resume \u00b7 70 min left'));
      await tester.pump();
      expect(restart, false);
      await tester.tap(find.text('Play From Beginning'));
      await tester.pump();
      expect(restart, true);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'Lite search results are text rows even when metadata contains artwork URLs',
    (tester) async {
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      final provider = MovieProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogSearchScreen(
            provider: provider,
            type: ContentType.movies,
            initialCatalog: Future.value([
              ContentItem(
                id: 'image',
                name: 'Movie',
                type: ContentType.movies,
                artwork: Uri.parse('https://example.invalid/poster.jpg'),
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ActivationTextField));
      await tester.enterText(find.byType(TextField), 'Movie');
      await tester.pumpAndSettle();
      expect(find.byType(LiteMediaTile), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'Lite series seasons and episode resume work without image widgets',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = CatalogProvider();
      const item = ContentItem(
        id: 'show',
        name: 'Example',
        type: ContentType.series,
      );
      const first = Episode(
        id: 'one',
        title: 'First',
        season: 1,
        number: 1,
        extension: 'mp4',
        artwork: null,
      );
      const second = Episode(
        id: 'two',
        title: 'Second',
        season: 2,
        number: 1,
        extension: 'mp4',
      );
      Episode? played;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiteDetails(
              provider: provider,
              info: const MediaDetails(
                item: item,
                synopsis: 'Synopsis',
                cast: 'Actor',
              ),
              episodes: const [first, second],
              previous: null,
              resolving: false,
              onPlay: (episode, restart) async {
                played = episode;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play S1 E1'));
      await tester.pump();
      expect(played?.id, 'one');
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Season 2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('S2 E1 \u00b7 Second'));
      await tester.pump();
      expect(played?.id, 'two');
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets('Lite list lazily navigates thousands of titles', (tester) async {
    final titles = [
      for (var i = 0; i < 5000; i++)
        ContentItem(id: '$i', name: 'Movie $i', type: ContentType.movies),
    ];
    final entry = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiteMediaList(
            items: titles,
            entryFocus: entry,
            onOpen: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    entry.requestFocus();
    await tester.pump();
    expect(find.byType(LiteMediaTile).evaluate().length, lessThan(30));
    for (var i = 0; i < 25; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(find.text('Movie 25'), findsOneWidget);
    expect(find.byType(LiteMediaTile).evaluate().length, lessThan(30));
    await tester.pumpWidget(const SizedBox());
    entry.dispose();
  });
}
