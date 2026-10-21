import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/channel_picker.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:iptv_flutter/presentation/widgets.dart';
import 'provider_test.dart' show FixtureClient;
import 'subtitle_test.dart' show FakeEngine;
import 'profiles_locks_test.dart' show CatalogFixture;

class GuideClient extends FixtureClient {
  final actions = <String?>[];
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  @override
  Future<dynamic> request({
    String? action,
    Map<String, String> params = const {},
  }) async {
    actions.add(action);
    final upcoming = {
      'title': 'Later show',
      'start_timestamp': now + 600,
      'stop_timestamp': now + 3600,
    };
    return {
      'epg_listings': [
        if (action == 'get_simple_data_table')
          {
            'title': 'Current show',
            'start_timestamp': now - 600,
            'stop_timestamp': now + 600,
          },
        upcoming,
        upcoming,
      ],
    };
  }
}

class ChannelEngine extends FakeEngine {
  final opened = <String>[];
  final events = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => events.stream;
  @override
  Future<void> dispose() async {
    await events.close();
  }

  @override
  Future<void> open(PlaybackSource source) async {
    opened.add(source.title);
    events.add(true);
  }
}

void main() {
  test(
    'full EPG recovers the current show missing from short EPG and deduplicates',
    () async {
      final client = GuideClient();
      final provider = XtreamProvider(client);
      final entries = await provider.getEpg(
        const ContentItem(id: '42', name: 'News', type: ContentType.live),
      );
      expect(client.actions, ['get_short_epg', 'get_simple_data_table']);
      expect(entries.length, 2);
      expect(entries.first.title, 'Current show');
      expect(entries.first.isCurrent(DateTime.now()), isTrue);
      provider.dispose();
    },
  );

  testWidgets('channel picker restores the current channel in a long list', (
    tester,
  ) async {
    final rows = List.generate(
      100,
      (index) => ContentItem(
        id: '$index',
        name: 'Channel $index',
        type: ContentType.live,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelPicker(
            title: 'Channels',
            currentId: '80',
            load: () async => rows,
            onSelect: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Channel 80'),
    );
    expect(tile.selected, isTrue);
    expect(tile.focusNode!.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'live controls hide subtitles and channel picker switches playback and EPG',
    (tester) async {
      final engine = ChannelEngine();
      const first = ContentItem(
        id: '1',
        name: 'First channel',
        type: ContentType.live,
      );
      const next = ContentItem(
        id: '2',
        name: 'Second channel',
        type: ContentType.live,
      );
      String? epgId;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/1'),
              title: first.name,
              isLive: true,
            ),
            item: first,
            engineFactory: () => engine,
            channelCategory: 'English',
            loadChannels: () async => [first, next],
            resolveChannel: (item) async => PlaybackSource(
              uri: Uri.parse('https://example.com/${item.id}'),
              title: item.name,
              isLive: true,
            ),
            channelEpg: (item) async {
              epgId = item.id;
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Subtitles'), findsNothing);
      await tester.tap(find.byTooltip('Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPicker), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, Colors.transparent);
      expect(dialog.alignment, Alignment.centerLeft);
      expect(find.text('English'), findsOneWidget);
      await tester.tap(find.text('Second channel'));
      await tester.pumpAndSettle();
      expect(engine.opened, ['First channel', 'Second channel']);
      expect(find.byType(ChannelPicker), findsOneWidget);
      final selectedTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Second channel'),
      );
      expect(selectedTile.selected, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPicker), findsNothing);
      await tester.tap(find.byTooltip('Programme guide'));
      await tester.pumpAndSettle();
      expect(epgId, '2');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'live navigation is wide with compact rows and matching My list width',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final provider = CatalogFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(provider: provider, type: ContentType.live),
        ),
      );
      await tester.pumpAndSettle();
      final saved = find.ancestor(
        of: find.text('My list'),
        matching: find.byType(FocusCard),
      );
      final category = find.ancestor(
        of: find.text('English (4K)'),
        matching: find.byType(FocusCard),
      );
      expect(tester.getSize(saved).width, tester.getSize(category).width);
      expect(tester.getSize(saved).height, tester.getSize(category).height);
      expect(tester.getSize(saved).width, greaterThan(260));
      expect(tester.getSize(category).height, lessThan(72));
      expect(tester.getSize(saved).height, lessThan(72));
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
