import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/live_channel_browser.dart';
import 'package:iptv_flutter/presentation/live_tv_controls.dart';
import 'guide_player_stability_test.dart' show StableEngine;
import 'live_channel_browser_test.dart' show BrowserProvider;
import 'live_tv_experience_test.dart' show source;

void main() {
  testWidgets(
    'selector owns remote focus without pausing, reopening or replacing playback',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = BrowserProvider();
      final channel = provider.channels.first;
      final engine = StableEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: source(channel),
            item: channel,
            provider: provider,
            liveTvMode: true,
            engineFactory: () => engine,
            loadChannels: () async => provider.channels,
            resolveChannel: (item) async => source(item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveChannelBrowser), findsOneWidget);
      final surface = tester.widget<Focus>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Focus &&
              widget.focusNode?.debugLabel == 'live video surface',
        ),
      );
      surface.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(surface.focusNode!.hasFocus, isFalse);
      final builds = engine.builds;
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(engine.opens, 1);
        expect(engine.pauses, 0);
        expect(engine.surfaces, 1);
        expect(engine.builds, builds);
        expect(find.byType(LiveTvControls), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<LiveChannelBrowser>(),
          isNotNull,
        );
      }
      await tester.pump(const Duration(seconds: 16));
      expect(find.byType(LiveChannelBrowser), findsOneWidget);
      expect(engine.pauses, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byType(LiveChannelBrowser), findsNothing);
      expect(engine.opens, 1);
      expect(engine.pauses, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
