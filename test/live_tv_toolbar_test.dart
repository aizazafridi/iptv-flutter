import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/live_tv_controls.dart';
import 'live_tv_experience_test.dart' show alpha, beta, source;
import 'guide_player_stability_test.dart' show StableEngine;
import 'tv_guide_screen_test.dart' show GuideProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final visibleButton in [true, false]) {
    testWidgets(
      visibleButton
          ? 'equal toolbar buttons and visible Back exits Live TV'
          : 'remote Back hides controls then exits Live TV',
      (tester) async {
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final engine = StableEngine();
        final provider = GuideProvider();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Dashboard'),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        source: source(alpha),
                        item: alpha,
                        provider: provider,
                        liveTvMode: true,
                        engineFactory: () => engine,
                        loadChannels: () async => [alpha, beta],
                        resolveChannel: (item) async => source(item),
                        channelEpg: provider.getEpg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byType(LiveTvControls), findsOneWidget);
        expect(find.byTooltip('More'), findsNothing);
        expect(find.text('Channel Health'), findsNothing);
        const titles = [
          'Channels',
          'TV Guide',
          'Search channels',
          'Record',
          'Multi View',
          'Aspect ratio',
          'Mute',
          'Catch-up',
          'Add to My list',
        ];
        final rects = titles
            .map((title) => tester.getRect(find.byTooltip(title)))
            .toList();
        for (final rect in rects) {
          expect(rect.height, 64);
          expect(rect.width, closeTo(rects.first.width, .01));
        }
        final gap = rects[1].center.dx - rects[0].center.dx;
        for (var i = 2; i < rects.length; i++) {
          expect(rects[i].center.dx - rects[i - 1].center.dx, closeTo(gap, .1));
        }
        if (visibleButton) {
          await tester.tap(find.byTooltip('Back to dashboard'));
        } else {
          await tester.sendKeyEvent(
            LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await tester.pumpAndSettle();
          expect(find.byType(LiveTvControls), findsNothing);
          expect(find.byType(PlayerScreen), findsOneWidget);
          await tester.sendKeyEvent(
            LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape,
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.text('Dashboard'), findsOneWidget);
        expect(engine.surfaces, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
