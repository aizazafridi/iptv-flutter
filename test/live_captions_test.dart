import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/live_captions.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/data/subtitle_preferences.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/subtitle_customization.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'guide_player_stability_test.dart' show StableEngine;

class CaptionEngine extends StableEngine
    implements SubtitleCustomizationEngine {
  final captionTracks = StreamController<List<SubtitleOption>>.broadcast();
  bool rejectCaption = false;
  @override
  Future<void> selectSubtitle(String id) async {
    if (rejectCaption && id == '1') {
      throw const ProviderException('Caption decoder unavailable');
    }
    await super.selectSubtitle(id);
  }

  @override
  Stream<List<SubtitleOption>> get subtitles => captionTracks.stream;
  @override
  Stream<String> get selectedSubtitle => const Stream.empty();
  @override
  SubtitleAppearance subtitleAppearance = const SubtitleAppearance();
  @override
  void setSubtitleAppearance(SubtitleAppearance appearance) {
    subtitleAppearance = appearance;
  }

  @override
  Future<void> addNamedSubtitle(Uri uri, String name) async {}
  @override
  Future<void> dispose() async {
    await captionTracks.close();
    await super.dispose();
  }
}

const english = SubtitleOption(
  '1',
  'English',
  language: 'eng',
  codec: 'eia_608',
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'language preference follows changed track IDs and remains profile-scoped',
    () async {
      final engine = CaptionEngine();
      final captions = LiveCaptions(
        engine: engine,
        preferences: const SubtitlePreferences(scope: 'alice'),
        profile: 'alice',
      );
      await captions.beginStream(true);
      captions.updateTracks([english]);
      await captions.restore();
      expect(captions.selected, 'no');
      await captions.choose('1');
      expect(engine.selected, '1');
      await captions.beginStream(true);
      captions.updateTracks([
        const SubtitleOption('1', 'Arabic', language: 'ara'),
        const SubtitleOption(
          '7',
          'English captions',
          language: 'en',
          codec: 'eia_608',
        ),
      ]);
      await captions.restore();
      expect(engine.selected, '7');
      final bob = LiveCaptions(
        engine: engine,
        preferences: const SubtitlePreferences(scope: 'bob'),
        profile: 'bob',
      );
      await bob.beginStream(true);
      bob.updateTracks([english]);
      await bob.restore();
      expect(engine.selected, 'no');
      captions.dispose();
      bob.dispose();
      await engine.dispose();
    },
  );
  test(
    'a rejected native caption selection remains Off and does not save an enabled preference',
    () async {
      final engine = CaptionEngine()..rejectCaption = true;
      final captions = LiveCaptions(
        engine: engine,
        preferences: const SubtitlePreferences(scope: 'alice'),
        profile: 'alice',
      );
      await captions.beginStream(true);
      captions.updateTracks([english]);
      await captions.restore();
      await expectLater(
        captions.choose('1'),
        throwsA(isA<ProviderException>()),
      );
      expect(captions.selected, 'no');
      expect(captions.enabled, isFalse);
      expect(engine.selected, 'no');
      expect(
        await const SubtitlePreferences(
          scope: 'alice',
        ).loadChoice('live-cc:alice'),
        isNull,
      );
      captions.dispose();
      await engine.dispose();
    },
  );
  test(
    'unsupported bitmap tracks are excluded and late text CC discovery applies preference',
    () async {
      final engine = CaptionEngine();
      final captions = LiveCaptions(
        engine: engine,
        preferences: const SubtitlePreferences(),
        profile: 'alice',
      );
      await captions.beginStream(true);
      await captions.restore();
      captions.updateTracks([
        const SubtitleOption('4', 'Bitmap', codec: 'dvb_subtitle'),
      ]);
      expect(captions.available, isFalse);
      await captions.choose('auto');
      captions.updateTracks([english]);
      await Future<void>.delayed(Duration.zero);
      expect(captions.available, isTrue);
      expect(engine.selected, 'auto');
      await captions.choose('no');
      await captions.beginStream(true);
      captions.updateTracks([english]);
      await captions.restore();
      expect(engine.selected, 'no');
      expect(captions.enabled, isFalse);
      captions.dispose();
      await engine.dispose();
    },
  );
  testWidgets(
    'CC stays visible and reports availability while discovered captions reuse the playing engine',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = CaptionEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            liveTvMode: true,
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'Channel',
              isLive: true,
            ),
            history: WatchHistory('alice'),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('CC'), findsOneWidget);
      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();
      expect(
        find.text('No captions detected on this channel.'),
        findsOneWidget,
      );
      expect(find.text('Automatic'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      engine.captionTracks.add([english]);
      await tester.pumpAndSettle();
      expect(find.text('CC'), findsOneWidget);
      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();
      expect(find.text('Closed captions'), findsOneWidget);
      expect(find.text('Search online subtitles'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(engine.selected, '1');
      expect(engine.opens, 1);
      expect(engine.surfaces, 1);
      expect(engine.pauses, 0);
      expect(
        (await const SubtitlePreferences(
          scope: 'alice',
        ).loadChoice('live-cc:alice'))?['mode'],
        'language',
      );
      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();
      engine.captionTracks.add([]);
      await tester.pumpAndSettle();
      expect(
        find.text('No captions detected on this channel.'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('CC'), findsOneWidget);
      expect(engine.selected, 'no');
      expect(engine.opens, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
