import 'package:iptv_flutter/playback/subtitle_customization.dart';
import 'package:iptv_flutter/presentation/next_episode_countdown.dart';
import 'package:iptv_flutter/data/playback_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/playback_engine.dart';
import 'package:iptv_flutter/playback/video_display.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/vod_player_controls.dart';
import 'guide_player_stability_test.dart' show StableEngine;
import 'widget_test.dart' show FakeProvider;

class VodEngine extends StableEngine
    implements
        AudioTrackPlaybackEngine,
        VideoDisplayEngine,
        SubtitleOverlayAvoidanceEngine {
  final lengths = StreamController<Duration>.broadcast();
  final sources = <PlaybackSource>[];
  double subtitleInset = 0;
  @override
  void setSubtitleBottomInset(double value) {
    subtitleInset = value;
  }

  @override
  Stream<Duration> get duration => lengths.stream;
  @override
  Future<void> open(PlaybackSource source) async {
    sources.add(source);
    await super.open(source);
    lengths.add(const Duration(minutes: 10));
    frames.add(const Duration(minutes: 2));
  }

  @override
  VideoDisplay videoDisplay = const VideoDisplay();
  @override
  void setVideoDisplay(VideoDisplay value) {
    videoDisplay = value;
  }

  @override
  List<SubtitleOption> get currentAudioTracks => [
    const SubtitleOption('en', 'English'),
    const SubtitleOption('fr', 'French'),
  ];
  @override
  Stream<List<SubtitleOption>> get audioTracks =>
      Stream.value(currentAudioTracks);
  @override
  String selectedAudioTrack = 'en';
  @override
  Future<void> selectAudioTrack(String id) async {
    selectedAudioTrack = id;
  }

  @override
  Future<void> dispose() async {
    await lengths.close();
    await super.dispose();
  }
}

class VodProvider extends FakeProvider {
  Episode? requested;
  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async {
    requested = episode;
    return PlaybackSource(
      uri: Uri.parse('https://example.com/${episode?.id ?? item.id}'),
      title: item.name,
      isLive: false,
      headers: const {'User-Agent': 'test-agent'},
    );
  }
}

const item = ContentItem(
  id: 'show',
  name: 'A Series',
  type: ContentType.series,
);
const episodes = [
  Episode(id: 'e1', title: 'Pilot', season: 1, number: 1, extension: 'mp4'),
  Episode(id: 'e2', title: 'Second', season: 1, number: 2, extension: 'mp4'),
  Episode(
    id: 'e3',
    title: 'New Season',
    season: 2,
    number: 1,
    extension: 'mp4',
  ),
];
Future<void> mount(
  WidgetTester tester,
  VodEngine engine, {
  bool series = true,
  WatchHistory? history,
  VodProvider? provider,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: PlayerScreen(
        source: PlaybackSource(
          uri: Uri.parse('https://example.com/e1'),
          title: 'Title',
          isLive: false,
        ),
        item: series
            ? item
            : const ContentItem(
                id: 'movie',
                name: 'A Movie',
                type: ContentType.movies,
              ),
        episode: series ? episodes.first : null,
        episodes: series ? episodes : [],
        provider: provider,
        history: history,
        engineFactory: () => engine,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'settings expand in the same translucent drawer without reopening playback',
    (tester) async {
      final engine = VodEngine();
      await mount(tester, engine);
      final opens = engine.opens;
      final surfaces = engine.surfaces;
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Record'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Off'), findsOneWidget);
      await tester.tap(find.text('Playback Speed'));
      await tester.pumpAndSettle();
      expect(find.text('Player Settings'), findsOneWidget);
      expect(find.byKey(const ValueKey('player-drawer')), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, '1.5\u00d7'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '1.5\u00d7'));
      await tester.pumpAndSettle();
      expect(engine.lastRate, 1.5);
      await tester.tap(find.text('Playback Speed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aspect Ratio'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Stretch'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Stretch'));
      await tester.pumpAndSettle();
      expect(engine.videoDisplay.ratio, 'Stretch');
      expect(engine.opens, opens);
      expect(engine.surfaces, surfaces);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'seek preview confirms once and Back cancels before leaving player',
    (tester) async {
      final engine = VodEngine();
      await mount(tester, engine, series: false);
      tester
          .widget<VodPlayerControls>(find.byType(VodPlayerControls))
          .seekFocus
          .requestFocus();
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.pumpAndSettle();
      expect(engine.sought, isNull);
      expect(find.textContaining('Seek to 02:30'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(engine.sought, isNull);
      expect(find.textContaining('Seek to'), findsNothing);
      tester
          .widget<VodPlayerControls>(find.byType(VodPlayerControls))
          .seekFocus
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(engine.sought, const Duration(minutes: 2, seconds: 10));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Back hides VOD controls before returning to details', (
    tester,
  ) async {
    final engine = VodEngine();
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/player',
        routes: {
          '/': (_) => const Scaffold(body: Text('Details')),
          '/player': (_) => PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/movie'),
              title: 'Movie',
            ),
            engineFactory: () => engine,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(
      tester.widget<VodPlayerControls>(find.byType(VodPlayerControls)).visible,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Details'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'opt-in autoplay persists per profile and counts down before reusing engine',
    (tester) async {
      final engine = VodEngine();
      final provider = VodProvider();
      final history = WatchHistory('alice');
      await mount(tester, engine, provider: provider, history: history);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Off'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        (await const PlaybackPreferences('alice').load())['autoplayNext'],
        isTrue,
      );
      expect(
        (await const PlaybackPreferences('bob').load())['autoplayNext'],
        isNull,
      );
      engine.endings.add(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(NextEpisodeCountdown), findsOneWidget);
      expect(engine.opens, 1);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(engine.opens, 2);
      expect(engine.surfaces, 1);
      expect(provider.requested!.id, 'e2');
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'autoplay button visibly counts down before completion and fills white',
    (tester) async {
      final engine = VodEngine();
      final provider = VodProvider();
      await const PlaybackPreferences('alice').save({'autoplayNext': true});
      await mount(
        tester,
        engine,
        provider: provider,
        history: WatchHistory('alice'),
      );
      engine.frames.add(const Duration(minutes: 9, seconds: 46));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Play Next ('), findsOneWidget);
      final initial = tester
          .widget<FractionallySizedBox>(
            find.byKey(const ValueKey('up-next-button-fill')),
          )
          .widthFactor!;
      await tester.pump(const Duration(seconds: 5));
      final later = tester
          .widget<FractionallySizedBox>(
            find.byKey(const ValueKey('up-next-button-fill')),
          )
          .widthFactor!;
      expect(later, greaterThan(initial));
      expect(later, greaterThan(.25));
      expect(engine.opens, 1);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(engine.opens, 2);
      expect(engine.surfaces, 1);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  for (final autoHide in [false, true]) {
    testWidgets(
      'laptop Escape exits with controls ${autoHide ? 'auto-hidden' : 'visible'}',
      (tester) async {
        final engine = VodEngine();
        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/player',
            routes: {
              '/': (_) => const Scaffold(body: Text('Details')),
              '/player': (_) => PlayerScreen(
                source: PlaybackSource(
                  uri: Uri.parse('https://example.com/movie'),
                  title: 'Movie',
                ),
                engineFactory: () => engine,
              ),
            },
          ),
        );
        await tester.pumpAndSettle();
        if (autoHide) {
          await tester.pump(const Duration(seconds: 6));
          await tester.pumpAndSettle();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(PlayerScreen), findsOneWidget);
          expect(
            tester
                .widget<VodPlayerControls>(find.byType(VodPlayerControls))
                .visible,
            isFalse,
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.text('Details'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('laptop Escape closes the drawer without leaving playback', (
    tester,
  ) async {
    final engine = VodEngine();
    await mount(tester, engine);
    final origin = tester
        .widget<Focus>(
          find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.debugLabel == 'player Subtitles',
          ),
        )
        .focusNode!;
    origin.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(
      tester.widget<VodPlayerControls>(find.byType(VodPlayerControls)).visible,
      isTrue,
    );
    expect(engine.opens, 1);
    expect(FocusManager.instance.primaryFocus, same(origin));
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'player title omits a release year only when metadata already shows it',
    () {
      expect(
        VodPlayerControls.displayTitle('The Voyeurs (2021)', '2021 ? Thriller'),
        'The Voyeurs',
      );
      expect(
        VodPlayerControls.displayTitle('The Voyeurs (2021)', 'Thriller'),
        'The Voyeurs (2021)',
      );
      expect(
        VodPlayerControls.displayTitle(
          '2001: A Space Odyssey (1968)',
          '1968 ? Sci-Fi',
        ),
        '2001: A Space Odyssey',
      );
    },
  );
  testWidgets(
    'compact controls show labels on focus and move subtitles without changing playback',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = VodEngine();
      await mount(tester, engine);
      final baseline = engine.builds;
      final overlay = tester.getRect(
        find.byKey(const ValueKey('vod-controls')),
      );
      expect(overlay.height, lessThanOrEqualTo(720 * .31));
      expect(
        tester.getSize(find.byKey(const ValueKey('vod-play-pause'))).width,
        50,
      );
      final hiddenLabel = find
          .ancestor(
            of: find.text('Audio'),
            matching: find.byType(AnimatedOpacity),
          )
          .first;
      expect(tester.widget<AnimatedOpacity>(hiddenLabel).opacity, 0);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'player Audio');
      expect(tester.widget<AnimatedOpacity>(hiddenLabel).opacity, 1);
      expect(engine.subtitleInset, greaterThan(overlay.height));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(engine.subtitleInset, 0);
      expect(engine.builds, baseline);
      expect(engine.surfaces, 1);
      expect(engine.opens, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets(
      'VOD drawers and selection preserve engine and surface at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final engine = VodEngine();
        final provider = VodProvider();
        final history = WatchHistory('alice');
        await mount(tester, engine, provider: provider, history: history);
        final before = engine.builds;
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'player play pause',
        );
        await tester.tap(find.text('Episodes'));
        await tester.pumpAndSettle();
        expect(find.text('Season 1'), findsOneWidget);
        expect(
          tester
              .widget<VodPlayerControls>(find.byType(VodPlayerControls))
              .visible,
          isFalse,
        );
        expect(engine.subtitleInset, 0);
        await tester.pump(const Duration(seconds: 8));
        expect(find.text('Season 1'), findsOneWidget);
        expect(engine.opens, 1);
        expect(engine.surfaces, 1);
        expect(engine.builds, before);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Audio'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(engine.selectedAudioTrack, 'en');
        await tester.tap(find.text('French'));
        await tester.pumpAndSettle();
        expect(engine.selectedAudioTrack, 'fr');
        await tester.tap(find.text('Subtitles'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();
        expect(engine.selected, '1');
        expect(engine.opens, 1);
        expect(engine.surfaces, 1);
        expect(engine.builds, before);
        await tester.tap(find.text('Episodes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('E2 \u00b7 Second'));
        await tester.pumpAndSettle();
        expect(provider.requested!.id, 'e2');
        expect(engine.opens, 2);
        expect(engine.surfaces, 1);
        expect(engine.builds, before);
        expect(engine.sources.last.headers['User-Agent'], 'test-agent');
        expect(find.textContaining('S1 E2'), findsOneWidget);
        expect(
          (await history.seriesProgress(
            item,
          )).any((e) => e.episode?.id == 'e1' && e.position.inMinutes == 2),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      },
    );
  }
  testWidgets(
    'movie controls hide in five seconds, stay paused, and seek on remote',
    (tester) async {
      final engine = VodEngine();
      await mount(tester, engine, series: false);
      expect(find.text('Episodes'), findsNothing);
      expect(find.text('Next'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VodPlayerControls>(find.byType(VodPlayerControls))
            .visible,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(engine.sought, const Duration(minutes: 2, seconds: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(engine.pauses, 1);
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VodPlayerControls>(find.byType(VodPlayerControls))
            .visible,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'season selection, next prompt and opt-in autoplay use existing engine',
    (tester) async {
      final engine = VodEngine();
      final provider = VodProvider();
      await mount(tester, engine, provider: provider);
      await tester.tap(find.text('Episodes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Season 2').last);
      await tester.pumpAndSettle();
      expect(find.text('E1 \u00b7 New Season'), findsOneWidget);
      expect(engine.opens, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      engine.frames.add(const Duration(minutes: 9, seconds: 35));
      await tester.pumpAndSettle();
      expect(find.text('Up Next'), findsOneWidget);
      engine.endings.add(true);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(engine.opens, 1);
      await tester.tap(find.text('Play Next'));
      await tester.pumpAndSettle();
      expect(engine.opens, 2);
      expect(engine.surfaces, 1);
      expect(provider.requested!.id, 'e2');
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
