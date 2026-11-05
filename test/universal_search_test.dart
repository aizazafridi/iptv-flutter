import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/application/universal_search.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/data/recent_searches.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/universal_search_screen.dart';
import 'package:iptv_flutter/presentation/activation_text_field.dart';
import 'series_catalog_screen_test.dart' show CatalogProvider;
import 'widget_test.dart' show FakeProvider;
import 'package:iptv_flutter/presentation/lite_media_list.dart';
import 'package:iptv_flutter/application/recent_catalog_cache.dart';

ContentItem item(String id, String name) =>
    ContentItem(id: id, name: name, type: ContentType.series);
Future<void> waitUntil(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Asynchronous search did not settle');
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'normalization and ranking preserve distinct versions and collapse duplicate IDs',
    () async {
      final index = await SearchIndex.build([
        item('1', 'The Last of Us - Hindi'),
        item('2', 'Watch The Last of Us'),
        item('3', 'The Last of Us'),
        item('4', 'Us and the last journey of hope'),
        item('5', 'THE LAST OF US'),
        item('3', 'Duplicate'),
      ]);
      expect(normalizeSearch('  THE: Last-of Us! '), 'the last of us');
      expect((await index.search('the LAST-of us')).map((e) => e.id), [
        '3',
        '5',
        '1',
        '2',
        '4',
      ]);
    },
  );
  test('large catalog cancellation and provider index reuse', () async {
    final provider = CatalogProvider();
    final source = Future.value(
      List.generate(50000, (i) => item('$i', 'Title $i')),
    );
    final a = SearchIndex.forCatalog(provider, ContentType.series, source);
    expect(
      identical(
        a,
        SearchIndex.forCatalog(provider, ContentType.series, source),
      ),
      isTrue,
    );
    final index = await a;
    expect((await index.search('Title 49999')).first.id, '49999');
    expect(await index.search('Title', cancelled: () => true), isEmpty);
  });
  test('recent searches are profile scoped, deduplicated and capped', () async {
    final a = RecentSearches('profile-a'), b = RecentSearches('profile-b');
    for (var i = 0; i < 10; i++) {
      await a.add('Title $i');
    }
    await a.add('title-9');
    expect((await a.load()).length, 8);
    expect((await a.load()).first, 'title-9');
    expect(await b.load(), isEmpty);
    await a.clear();
    expect(await a.load(), isEmpty);
  });
  testWidgets(
    'Premium grouped results and Lite result activation share catalog and preserve query',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
      final provider = FakeProvider();
      ContentItem? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchScreen(
            provider: provider,
            onOpen: (item) async {
              opened = item;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Example');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.catalogCalls, 3);
      expect(find.text('Series'), findsWidgets);
      expect(find.text('Movies'), findsWidgets);
      expect(tester.takeException(), isNull);
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.tap(find.byType(LiteMediaTile).first);
      await tester.pumpAndSettle();
      expect(opened?.type, ContentType.series);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Example',
      );
      expect(provider.catalogCalls, 3);
      await tester.pumpWidget(const SizedBox());
      await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
    },
  );
  test(
    'controller debounces latest query and reloads after invalidation',
    () async {
      final provider = FakeProvider();
      final controller = UniversalSearchController(provider);
      controller.reload();
      await waitUntil(
        () => !controller.pending && controller.indexes.length == 3,
      );
      controller.setQuery('Example');
      controller.setQuery('Another');
      await waitUntil(
        () =>
            controller.query == 'Another' &&
            !controller.pending &&
            controller.results.length == 3,
      );
      expect(
        controller.results.values.expand((x) => x).every((x) => x.id == '88'),
        isTrue,
      );
      expect(controller.results.length, 3);
      controller.setFilter(ContentType.movies);
      expect(provider.catalogCalls, 3);
      RecentCatalogCache.invalidate(provider);
      await waitUntil(() => provider.catalogCalls == 6 && !controller.pending);
      expect(provider.catalogCalls, 6);
      controller.dispose();
    },
  );
  testWidgets(
    'Lite search keeps keyboard closed, debounces, filters without reload, restores focus',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      addTearDown(
        () => BrowsingModeSettings.instance.choose(BrowsingMode.premium),
      );
      final provider = CatalogProvider();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchScreen(
            provider: provider,
            onOpen: (_) async {
              opened++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state<ActivationTextFieldState>(
        find.byType(ActivationTextField),
      );
      expect(state.editing, isFalse);
      expect(state.focus.hasFocus, isTrue);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Series');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.allCalls, 1);
      expect(
        await RecentSearches('fixture-${provider.displayName}').load(),
        isEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      state.finish();
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Series'));
      await tester.pumpAndSettle();
      expect(provider.allCalls, 1);
      expect(opened, 0);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
