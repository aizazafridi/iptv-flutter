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

Future<void> openBrowser(
  WidgetTester tester,
  BrowserProvider provider,
  List<String> selections, {
  String currentId = '0',
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
      expect(find.text('All My List'), findsOneWidget);
      await tester.tap(find.text('Local group'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 1'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Local group'),
      );
      expect(chip.focusNode!.hasFocus, isTrue);
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
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(tester.takeException(), isNull);
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
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'channel My List');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selections, ['1']);
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
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(selections, isEmpty);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(selections, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
