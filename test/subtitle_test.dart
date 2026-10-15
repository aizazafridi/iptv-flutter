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
    'player uses compact icon controls and applies all playback speeds',
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
      final width = tester
          .getSize(find.byKey(const ValueKey('play-pause-control')))
          .width;
      expect(
        tester.getSize(find.byKey(const ValueKey('seek-control'))).width,
        width * 2,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('speed-control'))).width,
        width,
      );
      for (final entry in {
        '0.5×': 0.5,
        '2×': 2.0,
        '3×': 3.0,
        '5×': 5.0,
        'Normal': 1.0,
      }.entries) {
        await tester.tap(find.byTooltip('Playback speed'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key).last);
        await tester.pumpAndSettle();
        expect(engine.lastRate, entry.value);
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
    expect(tester.getCenter(find.byTooltip('Episodes')).dx, greaterThan(740));
    await tester.tap(find.byTooltip('Episodes'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      Colors.transparent,
    );
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('S2 · E1 · Later season'));
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
      await tester.tap(find.text('Next episode'));
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
      for (final entry in {
        'Rewind 30 seconds': const Duration(minutes: 4, seconds: 30),
        'Forward 30 seconds': const Duration(minutes: 5, seconds: 30),
        'Rewind 1 minute': const Duration(minutes: 4),
        'Forward 1 minute': const Duration(minutes: 6),
        'Rewind 2 minutes': const Duration(minutes: 3),
        'Forward 2 minutes': const Duration(minutes: 7),
        'Rewind 3 minutes': const Duration(minutes: 2),
        'Forward 3 minutes': const Duration(minutes: 8),
      }.entries) {
        await tester.tap(find.byTooltip('Seek interval'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(entry.key.split(' ').skip(1).join(' ')).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(entry.key));
        await tester.pumpAndSettle();
        expect(engine.sought, entry.value);
      }
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pumpAndSettle();
      expect(find.text('Search online subtitles'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(engine.selected, '1');
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Subtitles'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit fullscreen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
