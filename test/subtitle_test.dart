import 'package:flutter/services.dart';
import 'package:iptv_flutter/presentation/vod_player_controls.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/playback_engine.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';

class FakeEngine implements PlaybackEngine {
  Duration? sought;
  double? lastRate;
  String? selected;
  @override
  Stream<Duration> get position => Stream.value(const Duration(minutes: 5));
  @override
  Stream<Duration> get duration => Stream.value(const Duration(minutes: 10));
  @override
  Stream<bool> get playing => Stream.value(true);
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Stream<List<SubtitleOption>> get subtitles =>
      Stream.value([const SubtitleOption('1', 'English')]);
  @override
  Future<void> selectSubtitle(String id) async {
    selected = id;
  }

  @override
  Future<void> addSubtitle(Uri uri) async {}
  @override
  Future<void> open(PlaybackSource source) async {}
  @override
  Future<void> togglePause() async {}
  @override
  Future<void> seek(Duration position) async {
    sought = position;
  }

  @override
  Future<void> setRate(double rate) async {
    lastRate = rate;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  Widget surface() => const SizedBox.expand();
}

void main() {
  testWidgets(
    'player uses cinematic controls and applies existing playback speeds',
    (tester) async {
      final engine = FakeEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/video'),
              title: 'Movie',
            ),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('vod-play-pause'))).width,
        inInclusiveRange(40.0, 52.0),
      );
      for (final rate in [0.5, 1.0, 2.0, 3.0, 5.0]) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Playback Speed'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, '$rate\u00d7'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, '$rate\u00d7'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close Player Settings'));
        await tester.pumpAndSettle();
        expect(engine.lastRate, rate);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('episode picker can jump to another season inside the player', (
    tester,
  ) async {
    final engine = FakeEngine();
    const first = Episode(
      id: '1',
      title: 'Pilot',
      season: 1,
      number: 1,
      extension: 'mp4',
    );
    const other = Episode(
      id: '2',
      title: 'Later season',
      season: 2,
      number: 1,
      extension: 'mp4',
    );
    Episode? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<Episode>(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      source: PlaybackSource(
                        uri: Uri.parse('https://example.com/video'),
                        title: 'Series',
                      ),
                      engineFactory: () => engine,
                      episode: first,
                      episodes: const [first, other],
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Episodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('E1 \u00b7 Later season'));
    await tester.pumpAndSettle();
    expect(result?.id, '2');
  });

  testWidgets(
    'Next episode returns the requested episode to the series screen',
    (tester) async {
      final engine = FakeEngine();
      const next = Episode(
        id: '52',
        title: 'Next season',
        season: 2,
        number: 1,
        extension: 'mp4',
      );
      Episode? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<Episode>(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        source: PlaybackSource(
                          uri: Uri.parse('https://example.com/video'),
                          title: 'Episode',
                        ),
                        engineFactory: () => engine,
                        nextEpisode: next,
                      ),
                    ),
                  );
                },
                child: const Text('Open series'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(result?.id, '52');
      expect(find.text('Open series'), findsOneWidget);
    },
  );
  testWidgets('player resumes at saved playback position', (tester) async {
    final engine = FakeEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          source: PlaybackSource(
            uri: Uri.parse('https://example.com/video'),
            title: 'Movie',
          ),
          engineFactory: () => engine,
          resumeAt: const Duration(minutes: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(engine.sought, const Duration(minutes: 2));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'player seeks by 30 seconds and 3 minutes and selects IPTV subtitles',
    (tester) async {
      final engine = FakeEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/video'),
              title: 'Movie',
            ),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final interval in [30, 60, 120, 180]) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seek Interval'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, '${interval}s'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, '${interval}s'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close Player Settings'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
        await tester.pumpAndSettle();
        expect(engine.sought, Duration(seconds: 300 + interval));
        await tester.sendKeyEvent(LogicalKeyboardKey.mediaRewind);
        await tester.pumpAndSettle();
        expect(engine.sought, Duration(seconds: 300 - interval));
      }
      await tester.tap(find.text('Subtitles'));
      await tester.pumpAndSettle();
      expect(find.text('Search online subtitles'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(engine.selected, '1');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VodPlayerControls>(find.byType(VodPlayerControls))
            .visible,
        isFalse,
      );
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VodPlayerControls>(find.byType(VodPlayerControls))
            .visible,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
