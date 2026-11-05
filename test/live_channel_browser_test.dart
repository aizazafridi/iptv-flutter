import 'dart:async';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/application/live_favourite_groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/live_channel_browser.dart';
import 'tv_guide_screen_test.dart' show GuideProvider;

class BrowserProvider extends GuideProvider {
  final channels = List.generate(
    120,
    (i) => ContentItem(
      id: '$i',
      name: 'Channel $i',
      type: ContentType.live,
      categoryId: 'news',
    ),
  );
  @override
  Future<List<Category>> getCategories(ContentType type) async => [
    const Category('news', 'News', ContentType.live),
    const Category('sports', 'Sports', ContentType.live),
  ];
  @override
  Future<List<ContentItem>> getItems(Category category) async =>
      category.id == 'sports'
      ? [
          const ContentItem(
            id: 'sports-1',
            name: 'Sports channel',
            type: ContentType.live,
            categoryId: 'sports',
          ),
        ]
      : channels;
}

class QueuedBrowserProvider extends BrowserProvider {
  final release = Completer<void>();
  int active = 0, peak = 0;
  @override
  Future<List<EpgProgramme>> getEpg(ContentItem channel) async {
    active++;
    if (active > peak) peak = active;
    await release.future;
    active--;
    return [];
  }
}

Future<void> openBrowser(
  WidgetTester tester,
  BrowserProvider provider,
  List<String> selections, {
  String currentId = '0',
  LiveChannelBrowserSelection? selection,
}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => LiveChannelBrowser(
                provider: provider,
                load: () async => provider.channels,
                currentId: currentId,
                categoryId: 'news',
                selection: selection,
                onSelect: (item) async {
                  selections.add(item.id);
                  return true;
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selector bounds EPG work while rows are being browsed', (
    tester,
  ) async {
    final provider = QueuedBrowserProvider();
    await openBrowser(tester, provider, []);
    expect(provider.active, 2);
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(provider.peak, 2);
    provider.release.complete();
    await tester.pumpAndSettle();
    expect(provider.active, 0);
    expect(provider.peak, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  testWidgets(
    'My List tabs share category styling and remote focus moves independently of selection',
    (tester) async {
      final provider = BrowserProvider();
      final list = MyList.forProvider(provider);
      await list.toggle(provider.channels[0]);
      final groups = list.groups;
      final a = await groups.create('Pakistan');
      final b = await groups.create('Dramas');
      await groups.assign('0', {a, b});
      final played = <String>[];
      await openBrowser(tester, provider, played);
      final nativeStyle = tester.widget<Text>(find.text('News')).style;
      await tester.tap(find.text('My List'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel group ${LiveFavouriteGroups.all}',
      );
      expect(
        tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text('All Favorites'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        const Color(0xff30445d),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel group $a',
      );
      expect(groups.selectedGroup, LiveFavouriteGroups.all);
      expect(tester.widget<Text>(find.text('Pakistan')).style, nativeStyle);
      expect(
        tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text('Pakistan'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        const Color(0xff30445d),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(groups.selectedGroup, a);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel group $b',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel group $a',
      );
      expect(played, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'reopening keeps My List group instead of the selected channel native category',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final provider = BrowserProvider();
      await MyList.forProvider(provider).toggle(provider.channels[0]);
      await MyList.forProvider(provider).toggle(provider.channels[1]);
      final groups = LiveFavouriteGroups.forProvider(provider);
      final dramas = await groups.create('Dramas');
      await groups.assign('0', {dramas});
      final selection = LiveChannelBrowserSelection();
      final played = <String>[];
      await openBrowser(tester, provider, played, selection: selection);
      await tester.tap(find.text('My List'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dramas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel 0'));
      await tester.pumpAndSettle();
      expect(played, ['0']);
      expect(find.byType(LiveChannelBrowser), findsOneWidget);
      await tester.tap(find.text('Channel 0'));
      await tester.pumpAndSettle();
      expect(selection.categoryId, 'favorites');
      expect(selection.groupId, dramas);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 1'), findsNothing);
      expect(groups.selectedGroup, dramas);
      final selectedRow = find
          .ancestor(of: find.text('Channel 0'), matching: find.byType(InkWell))
          .first;
      expect(Focus.of(tester.element(selectedRow)).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel group $dramas',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(selectedRow)).hasFocus, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await groups.delete(dramas);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('All Favorites'), findsOneWidget);
      expect(find.text('Channel 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );

  testWidgets(
    'favorites group tabs filter locally and are reachable from channels',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final provider = BrowserProvider();
      final list = MyList.forProvider(provider);
      await list.toggle(provider.channels[0]);
      await list.toggle(provider.channels[1]);
      final groups = LiveFavouriteGroups.forProvider(provider);
      final id = await groups.create('Local group');
      await groups.assign('0', {id});
      final selections = <String>[];
      await openBrowser(tester, provider, selections);
      await tester.tap(find.text('My List'));
      await tester.pumpAndSettle();
      expect(find.text('All Favorites'), findsOneWidget);
      await tester.tap(find.text('Local group'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 1'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel group $id',
      );
      expect(groups.selectedGroup, id);
      expect(selections, isEmpty);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );

  testWidgets(
    'remote selects another category without tuning, then OK plays its channel',
    (tester) async {
      final selections = <String>[];
      await openBrowser(tester, BrowserProvider(), selections);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel category news',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'channel category sports',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Sports channel'), findsOneWidget);
      expect(selections, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selections, ['sports-1']);
      expect(find.byType(LiveChannelBrowser), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Left from a channel focuses its active native category without tuning',
    (tester) async {
      final played = <String>[];
      await openBrowser(tester, BrowserProvider(), played);
      await tester.tap(find.text('Sports'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'channel category sports',
      );
      expect(played, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'remote browsing preserves playback, categories return focus, OK plays and closes',
    (tester) async {
      final selections = <String>[];
      await openBrowser(tester, BrowserProvider(), selections);
      expect(find.text('Programme 0'), findsOneWidget);
      final width = tester
          .getSize(find.byKey(const ValueKey('live-channel-browser-panel')))
          .width;
      expect(width, closeTo(960 * .45, .1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(selections, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Channel 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selections, ['1']);
      expect(find.byType(LiveChannelBrowser), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reopens scrolled to the playing channel beyond initial viewport',
    (tester) async {
      final selections = <String>[];
      await openBrowser(
        tester,
        BrowserProvider(),
        selections,
        currentId: '100',
      );
      expect(find.text('Channel 100'), findsOneWidget);
      expect(find.text('Channel 0'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selections, ['100']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'holding OK opens favorites actions without tuning; Back closes browser',
    (tester) async {
      final selections = <String>[];
      await openBrowser(tester, BrowserProvider(), selections);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(selections, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(selections, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
