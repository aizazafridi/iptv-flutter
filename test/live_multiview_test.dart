import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/playback_engine.dart';
import 'package:iptv_flutter/presentation/live_multiview_screen.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;

class AudioEngine extends FakeEngine implements AudioPlaybackEngine {
  final List<AudioEngine> all;
  final events = StreamController<bool>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final failures = StreamController<String>.broadcast();
  @override
  Stream<String> get errors => failures.stream;
  @override
  Stream<bool> get playing => events.stream;
  @override
  Stream<Duration> get position => positions.stream;
  final sources = <PlaybackSource>[];
  int opens = 0;
  bool connected = false, disposed = false;
  double volume = 100;
  final VoidCallback onOpen;
  AudioEngine(this.all, this.onOpen);
  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> open(PlaybackSource source) async {
    opens++;
    sources.add(source);
    connected = true;
    onOpen();
    events.add(true);
  }

  @override
  Future<void> stop() async {
    connected = false;
    events.add(false);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    connected = false;
    unawaited(events.close());
    unawaited(positions.close());
    unawaited(failures.close());
  }
}

const one = ContentItem(id: '1', name: 'Channel One', type: ContentType.live);
const two = ContentItem(id: '2', name: 'Channel Two', type: ContentType.live);
PlaybackSource stream(ContentItem channel) => PlaybackSource(
  uri: Uri.parse('https://example.com/${channel.id}'),
  title: channel.name,
  isLive: true,
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'controlled handoff, independent channels, exclusive audio, fullscreen and cleanup',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engines = <AudioEngine>[];
      var maximumConnections = 0;
      AudioEngine create() {
        final engine = AudioEngine(engines, () {
          final active = engines.where((entry) => entry.connected).length;
          if (active > maximumConnections) maximumConnections = active;
        });
        engines.add(engine);
        return engine;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: stream(one),
            item: one,
            engineFactory: create,
            loadChannels: () async => [one, two],
            resolveChannel: (item) async => stream(item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Multi View',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiveMultiviewScreen), findsOneWidget);
      expect(engines, hasLength(2)); // Empty Screen 2 owns no player.
      expect(engines.first.connected, isFalse);
      expect(engines[1].volume, 100);
      await tester.tap(find.byKey(const ValueKey('multiview-panel-1')));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find.byKey(const ValueKey('multiview-channel-drawer')),
      );
      expect(bounds.left, 0);
      expect(bounds.width, closeTo(1280 * .35, 1));
      await tester.tap(find.text('Channel Two'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(engines, hasLength(3));
      expect(engines[2].connected, isTrue);
      expect(engines[2].volume, 0);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Audio - Screen 2',
        ),
      );
      await tester.pumpAndSettle();
      expect(engines[1].volume, 0);
      expect(engines[2].volume, 100);
      await tester.tap(find.text('Swap Screens'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('multiview-panel-0')),
          matching: find.text('Channel Two'),
        ),
        findsOneWidget,
      );
      expect(engines[1].opens, 1);
      expect(engines[2].opens, 1);
      expect(engines[2].volume, 100);
      await tester.tap(find.text('Swap Screens'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 Screens'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('multiview-panel-3')), findsOneWidget);
      expect(engines, hasLength(3));
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Full screen - Screen 2',
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(engines[1].disposed, isTrue);
      expect(engines[2].opens, 1);
      await tester.tap(find.text('Return to Multi View'));
      await tester.pumpAndSettle();
      expect(engines[2].opens, 1);
      expect(engines, hasLength(4));
      await tester.tap(find.text('Exit Multi View'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byType(LiveMultiviewScreen), findsNothing);
      expect(engines.skip(1).every((e) => e.disposed), isTrue);
      expect(engines[0].connected, isTrue);
      expect(engines[0].opens, 2);
      expect(engines[0].sources.last.title, two.name);
      expect(maximumConnections, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'remote follows four-panel geometry and Back closes a drawer without leaving',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({
        'playback_settings:multiview-local': '{"multiview":{"layout":4}}',
      });
      final engines = <AudioEngine>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LiveMultiviewScreen(
            initialSource: stream(one),
            initialChannel: one,
            engineFactory: () {
              final engine = AudioEngine(engines, () {});
              engines.add(engine);
              return engine;
            },
            loadChannels: () async => [one, two],
            resolveChannel: (item) async => stream(item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(engines, hasLength(1));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Multi View Screen 1',
      );
      for (final step in [
        (LogicalKeyboardKey.arrowRight, 'Multi View Screen 2'),
        (LogicalKeyboardKey.arrowDown, 'Multi View Screen 4'),
        (LogicalKeyboardKey.arrowLeft, 'Multi View Screen 3'),
        (LogicalKeyboardKey.arrowUp, 'Multi View Screen 1'),
        (LogicalKeyboardKey.arrowUp, 'Multi View header 0'),
        (LogicalKeyboardKey.arrowRight, 'Multi View header 1'),
        (LogicalKeyboardKey.arrowDown, 'Multi View Screen 1'),
        (LogicalKeyboardKey.arrowDown, 'Multi View Screen 3'),
        (LogicalKeyboardKey.arrowDown, 'Multi View toolbar 0'),
        (LogicalKeyboardKey.arrowUp, 'Multi View Screen 3'),
      ]) {
        await tester.sendKeyEvent(step.$1);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, step.$2);
      }
      await tester.tap(find.text('Channel List'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Channel'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Choose Channel'), findsNothing);
      expect(find.byType(LiveMultiviewScreen), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Multi View Screen 3',
      );
      expect(engines.single.opens, 1);
      await tester.tap(find.text('3 Screens'));
      await tester.pumpAndSettle();
      for (final step in [
        (LogicalKeyboardKey.arrowLeft, 'Multi View Screen 1'),
        (LogicalKeyboardKey.arrowRight, 'Multi View Screen 2'),
        (LogicalKeyboardKey.arrowDown, 'Multi View Screen 3'),
        (LogicalKeyboardKey.arrowUp, 'Multi View Screen 2'),
      ]) {
        await tester.sendKeyEvent(step.$1);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, step.$2);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(engines.single.disposed, isTrue);
    },
  );
}
