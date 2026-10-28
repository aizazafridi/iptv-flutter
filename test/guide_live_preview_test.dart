import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/live_tv_launch_screen.dart';
import 'package:iptv_flutter/presentation/live_tv_controls.dart';
import 'package:iptv_flutter/presentation/tv_guide_screen.dart';
import 'package:iptv_flutter/presentation/channel_picker.dart';
import 'guide_player_stability_test.dart' show StableEngine;
import 'tv_guide_screen_test.dart' show GuideProvider;

class PreviewProvider extends GuideProvider {
  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async => PlaybackSource(
    uri: Uri.parse('https://example.com/${item.id}'),
    title: item.name,
    isLive: true,
  );
}

void main() {
  testWidgets(
    'dashboard guide starts playback, channel selection tunes preview, preview expands without reopening',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      final engine = StableEngine();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: LiveTvLaunchScreen(
            provider: PreviewProvider(),
            openGuide: true,
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TvGuideScreen), findsOneWidget);
      expect(find.byType(ChannelPicker), findsNothing);
      expect(engine.opens, 1);
      expect(engine.surfaces, 1);
      Focus.of(tester.element(find.text('Channel Beta'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(TvGuideScreen), findsNothing);
      expect(find.byType(LiveTvControls), findsNothing);
      expect(engine.opens, 2);
      expect(engine.surfaces, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LiveTvControls), findsOneWidget);
      expect(engine.opens, 2);
      expect(engine.builds, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
