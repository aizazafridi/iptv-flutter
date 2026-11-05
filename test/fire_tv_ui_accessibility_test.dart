import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'live_stream_recovery_test.dart' show RecoveryEngine;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/player_drawer.dart';
import 'package:iptv_flutter/presentation/player_settings_drawer.dart';
import 'live_channel_browser_test.dart' show openBrowser, BrowserProvider;

class SpeedEngine extends RecoveryEngine {
  double rate = 1;
  @override
  Future<void> setRate(double value) async {
    rate = value;
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'movie More settings receives remote focus and applies a setting',
    (tester) async {
      var rate = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPlayerDrawer<void>(
                  context,
                  title: 'Player Settings',
                  settings: true,
                  builder: (_) => PlayerSettingsDrawer(
                    autoplay: null,
                    rate: 1,
                    seekSeconds: 10,
                    ratio: 'Original',
                    allowSpeed: true,
                    onAutoplay: (_) async {},
                    onRate: (v) async {
                      rate = v;
                    },
                    onSeek: (_) async {},
                    onRatio: (_) async {},
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
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        focused.context!.findAncestorWidgetOfExactType<PlayerSettingsDrawer>(),
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(rate, 1.5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('category search results and input can be reached after typing', (
    tester,
  ) async {
    final provider = BrowserProvider();
    await openBrowser(tester, provider, []);
    await tester.tap(find.byTooltip('Search categories'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'category search input',
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sports');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'channel category sports',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'category search input',
    );
    expect(find.byTooltip('Search channels'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  testWidgets(
    'category and channel search are exclusive and focus the opened field',
    (tester) async {
      final provider = BrowserProvider();
      await openBrowser(tester, provider, []);
      for (final channels in [false, true, false]) {
        await tester.tap(
          find.byTooltip(channels ? 'Search channels' : 'Search categories'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
          channels ? 'Search channels' : 'Search categories',
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          channels ? 'channel search input' : 'category search input',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  for (final live in [true, false]) {
    testWidgets('saved half speed applies only to VOD: live=$live', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        'playback_settings:speed': '{"rate":0.5}',
      });
      final engine = SpeedEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/stream'),
              title: 'Title',
              isLive: live,
            ),
            liveTvMode: live,
            history: WatchHistory('speed'),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.rate, live ? 1 : .5);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
