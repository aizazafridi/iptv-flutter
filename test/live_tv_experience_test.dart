import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/live_tv_start.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/data/last_live_channel.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/channel_picker.dart';
import 'package:iptv_flutter/presentation/tv_guide_screen.dart';
import 'package:iptv_flutter/presentation/live_tv_controls.dart';
import 'tv_guide_screen_test.dart' show GuideProvider;
import 'guide_player_stability_test.dart' show StableEngine;

const alpha = ContentItem(
  id: '1',
  name: 'Channel Alpha',
  type: ContentType.live,
);
const beta = ContentItem(id: '2', name: 'Channel Beta', type: ContentType.live);
PlaybackSource source(ContentItem item) => PlaybackSource(
  uri: Uri.parse('https://example.com/${item.id}'),
  title: item.name,
  isLive: true,
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'startup prefers last watched, then favourites, then API order',
    () async {
      final p = GuideProvider();
      final api = await prepareLiveTv(p);
      expect(api.channel.id, '1');
      expect(api.firstUse, isTrue);
      await MyList.forProvider(p).toggle(beta);
      expect((await prepareLiveTv(p)).channel.id, '2');
      await LastLiveChannel.forProvider(p).save(alpha);
      final last = await prepareLiveTv(p);
      expect(last.channel.id, '1');
      expect(last.firstUse, isFalse);
    },
  );
  testWidgets(
    'Live TV starts clean, zaps remotely, and overlays close back to playback',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = GuideProvider();
      final engine = StableEngine();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PlayerScreen(
            source: source(alpha),
            item: alpha,
            provider: p,
            liveTvMode: true,
            engineFactory: () => engine,
            loadChannels: () async => [alpha, beta],
            resolveChannel: (item) async => source(item),
            channelEpg: p.getEpg,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiveTvControls), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(engine.opens, 2);
      expect(find.byType(LiveTvControls), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LiveTvControls), findsOneWidget);
      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
      expect(find.byTooltip('Catch-up'), findsOneWidget);
      expect(find.byTooltip('Add to My list'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPicker), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPicker), findsNothing);
      expect(find.byType(LiveTvControls), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('TV Guide'));
      await tester.pumpAndSettle();
      expect(find.byType(TvGuideScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TvGuideScreen), findsNothing);
      expect(find.byType(LiveTvControls), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelStrip), findsOneWidget);
      await tester.tap(find.text('Channel Alpha'));
      await tester.pumpAndSettle();
      expect(engine.opens, 3);
      expect(engine.surfaces, 1);
      expect(engine.builds, 1);
      expect(engine.pauses, 0);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 14));
      expect(find.byType(LiveTvControls), findsOneWidget);
      // Remote activity restarts the full inactivity interval.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 14));
      expect(find.byType(LiveTvControls), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LiveTvControls), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('first use automatically opens channel selection', (
    tester,
  ) async {
    final engine = StableEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          source: source(alpha),
          item: alpha,
          liveTvMode: true,
          initialChannelPicker: true,
          engineFactory: () => engine,
          loadChannels: () async => [alpha, beta],
          resolveChannel: (item) async => source(item),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPicker), findsOneWidget);
    expect(engine.opens, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
